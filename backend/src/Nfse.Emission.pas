unit Nfse.Emission;

interface

uses System.SysUtils, System.JSON, FireDAC.Comp.Client;

type
  EEmissionError = class(Exception);

function EmitHomologation(Conn: TFDConnection; const Company, Draft, IssuedAt, Competence: string): string;
function DownloadDanfse(Conn: TFDConnection; const Company, Invoice: string): TBytes;

implementation

uses
  System.Classes, System.IOUtils, System.DateUtils, System.SyncObjs,
  ACBrNFSeX, ACBrDFeSSL, ACBrDFe.Conversao, ACBrNFSeXConversao,
  ACBrNFSeXNotasFiscais
  {$IFDEF LINUX}, Posix.Unistd, Posix.SysWait, Posix.Errno{$ENDIF};

{$IFDEF LINUX}
function SpawnDanfse(var PID: Integer; Path: MarshaledAString; Actions, Attrs: Pointer; Argv, Envp: PMarshaledAString): Integer; cdecl; external 'libc.so.6' name 'posix_spawn';
{$ENDIF}

var FiscalLock: TCriticalSection;

function S(Obj: TJSONObject; const Key: string): string;
var V: TJSONValue;
begin
  V := Obj.GetValue(Key);
  if V = nil then raise EEmissionError.Create('Configuracao fiscal incompleta: ' + Key);
  Result := V.Value;
  if Result = '' then raise EEmissionError.Create('Configuracao fiscal vazia: ' + Key);
end;

function Obj(Parent: TJSONObject; const Key: string): TJSONObject;
begin
  if not (Parent.GetValue(Key) is TJSONObject) then
    raise EEmissionError.Create('Configuracao fiscal incompleta.');
  Result := TJSONObject(Parent.GetValue(Key));
end;

procedure CheckDigits(const Value: string; Count: Integer);
var C: Char;
begin
  if Length(Value) <> Count then raise EEmissionError.Create('Codigo fiscal com tamanho invalido.');
  for C in Value do if not CharInSet(C,['0'..'9']) then raise EEmissionError.Create('Codigo fiscal deve ser numerico.');
end;

function EmitHomologation(Conn: TFDConnection; const Company, Draft, IssuedAt, Competence: string): string;
const BaseURL = 'https://sefin.producaorestrita.nfse.gov.br/SefinNacional';
var
  Q: TFDQuery;
  Envelope, Attempt, Payload, Profile, Settings, CompanyData, Customer: TJSONObject;
  NFSe: TACBrNFSeX;
  Note: TNotaFiscal;
  AttemptId, AttemptDir, CertRoot, DataRoot, SchemaRoot, Password, Xml, ErrorText: string;
  State, InvoiceXml, ResponseText, Stage: string;
  Report, Err, ResponseJson: TJSONObject;
  Errors: TJSONArray;
  N: Integer;
  Contacted: Boolean;
  LocalDate: TDateTime;
  Fmt: TFormatSettings;

  procedure Execute(const SQL: string);
  begin
    Q.Close;
    Q.SQL.Text := SQL;
    if Q.Params.FindParam('company') <> nil then Q.ParamByName('company').AsWideString := Company;
    if Q.Params.FindParam('id') <> nil then Q.ParamByName('id').AsWideString := AttemptId;
  end;

  procedure SetState(const Value: string);
  begin
    Execute('update emission_attempts set status=:state,updated_at=now() where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
    Q.ParamByName('state').AsWideString := Value;
    Q.ExecSQL;
  end;

begin
  if GetEnvironmentVariable('NFSE_ENABLE_HOMOLOGATION') <> '1' then
    raise EEmissionError.Create('Emissao de homologacao ainda nao habilitada no servidor.');
  CertRoot := GetEnvironmentVariable('NFSE_CERTIFICATES_DIR');
  DataRoot := GetEnvironmentVariable('NFSE_DATA_DIR');
  SchemaRoot := GetEnvironmentVariable('NFSE_SCHEMAS_DIR');
  if (CertRoot='') or (DataRoot='') or not FileExists(TPath.Combine(SchemaRoot,'DPS_v1.01.xsd')) then
    raise EEmissionError.Create('Diretorios fiscais ou schemas nao configurados.');
  if not FileExists(TPath.Combine(CertRoot,Company+'.pfx')) or
     not FileExists(TPath.Combine(CertRoot,Company+'.password')) then
    raise EEmissionError.Create('Certificado desta empresa nao provisionado no servidor.');
  Q := TFDQuery.Create(nil);
  Q.Connection := Conn;
  Envelope := nil;
  NFSe := nil;
  Report := nil;
  try
    // Validar o perfil suportado antes de reservar numero ou contatar a SEFIN.
    Execute('select settings_snapshot::text from drafts where company_id=cast(:company as uuid) ' +
      'and id=cast(:draft as uuid)');
    Q.ParamByName('draft').AsWideString := Draft;
    Q.Open;
    if not Q.IsEmpty then
    begin
      Settings := TJSONObject.ParseJSONValue(Q.Fields[0].AsString) as TJSONObject;
      try
        if Settings.GetValue('send_ibs_cbs') is TJSONTrue then
          if (S(Settings,'cst_ibs_cbs') <> '200') or
             (S(Settings,'cclass_trib') <> '200048') or
             (S(Settings,'cind_op') <> '030101') then
            raise EEmissionError.Create('Perfil IBS/CBS suportado: CST 200, cClassTrib 200048 e cIndOp 030101. Revise os parametros e crie outro rascunho.');
      finally Settings.Free; end;
    end;
    Q.Close;
    Execute('select reserve_homologation(cast(:company as uuid),cast(:draft as uuid),cast(:issued as timestamptz),cast(:competence as date))::text');
    Q.ParamByName('draft').AsWideString := Draft;
    Q.ParamByName('issued').AsWideString := IssuedAt;
    Q.ParamByName('competence').AsWideString := Competence;
    Q.Open;
    Envelope := TJSONObject.ParseJSONValue(Q.Fields[0].AsString) as TJSONObject;
    Q.Close;
    Attempt := Obj(Envelope,'attempt');
    AttemptId := S(Attempt,'id');
    if not SameText(Envelope.GetValue('created').Value,'true') then
    begin
      Result := Attempt.ToJSON;
      Exit;
    end;
    AttemptDir := TPath.Combine(TPath.Combine(DataRoot,Company),AttemptId);
    Contacted := False;
    State := 'local_error';
    Stage := 'prepare';
    InvoiceXml := '';
    ResponseText := '';
    Report := TJSONObject.Create;
    FiscalLock.Acquire;
    try
      try
        ForceDirectories(AttemptDir);
        Payload := Obj(Attempt,'request_snapshot');
        Profile := Obj(Payload,'profile');
        Settings := Obj(Payload,'settings');
        CompanyData := Obj(Payload,'company');
        if (S(Profile,'municipality_code')<>'3136702') or (S(Profile,'state_code')<>'MG') then
          raise EEmissionError.Create('Perfil inicial de homologacao limitado a Juiz de Fora/MG.');
        if S(Settings,'tax_regime') <> 'simples_nacional' then raise EEmissionError.Create('Fluxo atual preparado somente para ME/EPP do Simples Nacional.');
        CheckDigits(S(CompanyData,'document'),14);
        CheckDigits(S(Settings,'service_code'),6);
        CheckDigits(S(Settings,'municipal_service_code'),3);
        CheckDigits(S(Settings,'nbs_code'),9);
        NFSe := TACBrNFSeX.Create(nil);
        NFSe.Configuracoes.Geral.SSLCryptLib := cryOpenSSL;
        NFSe.Configuracoes.Geral.SSLXmlSignLib := xsLibXml2;
        NFSe.Configuracoes.Geral.SSLHttpLib := httpOpenSSL;
        NFSe.Configuracoes.Geral.LayoutNFSe := lnfsPadraoNacionalv101;
        NFSe.Configuracoes.WebServices.Ambiente := taHomologacao;
        NFSe.Configuracoes.WebServices.TimeOut := 30000;
        NFSe.Configuracoes.Geral.ConsultaLoteAposEnvio := False;
        NFSe.Configuracoes.Geral.MontarPathSchema := False;
        NFSe.Configuracoes.Arquivos.PathSchemas := IncludeTrailingPathDelimiter(SchemaRoot);
        // O padrao do ACBr usa ApplicationPath/Docs, somente leitura no container.
        // O provedor salva a DPS dentro de Emitir antes de iniciar o HTTP.
        NFSe.Configuracoes.Arquivos.PathSalvar := AttemptDir;
        NFSe.Configuracoes.Arquivos.PathGer := AttemptDir;
        NFSe.Configuracoes.Arquivos.PathRPS := AttemptDir;
        NFSe.Configuracoes.Arquivos.PathNFSe := AttemptDir;
        NFSe.Configuracoes.Arquivos.PathCan := AttemptDir;
        TFile.WriteAllText(TPath.Combine(AttemptDir,'servicos.ini'),'[PadraoNacional]' + sLineBreak +
          'Versao=1.01' + sLineBreak + 'HomRecepcionar='+BaseURL+sLineBreak+
          'HomGerarNFSe='+BaseURL+sLineBreak,TEncoding.ASCII);
        NFSe.Configuracoes.Arquivos.IniServicos := TPath.Combine(AttemptDir,'servicos.ini');
        NFSe.Configuracoes.WebServices.LerParams;
        NFSe.Configuracoes.Geral.CodigoMunicipio := StrToInt(S(Profile,'municipality_code'));
        NFSe.SetProvedor(proPadraoNacional,ve101);
        if NFSe.Provider.ConfigWebServices.Homologacao.GerarNFSe <> BaseURL then raise EEmissionError.Create('URL de homologacao incorreta.');
        Password := TFile.ReadAllText(TPath.Combine(CertRoot,Company+'.password'),TEncoding.UTF8);
        while (Length(Password)>0) and CharInSet(Password[Length(Password)],[#10,#13]) do Delete(Password,Length(Password),1);
        NFSe.SSL.ArquivoPFX := TPath.Combine(CertRoot,Company+'.pfx');
        NFSe.SSL.Senha := AnsiString(Password);
        Password := '';
        NFSe.SSL.CarregarCertificado;
        if NFSe.SSL.CertCNPJ <> S(CompanyData,'document') then
          raise EEmissionError.Create('Certificado nao pertence a empresa da tentativa.');
        if NFSe.SSL.CertDataVenc < Now then raise EEmissionError.Create('Certificado vencido.');
        Note := NFSe.NotasFiscais.New;
        with Note.NFSe do
        begin
          Numero := S(Attempt,'dps_number');
          IdentificacaoRps.Numero := Numero;
          IdentificacaoRps.Serie := S(Attempt,'dps_series');
          NumeroLote := '1';
          verAplic := 'VEEV-API-1.0';
          // Municipio do perfil inicial usa UTC-03. Independe do fuso do container.
          LocalDate := IncHour(ISO8601ToDate(S(Attempt,'issued_at'),True),-3);
          DataEmissao := LocalDate;
          DataEmissaoRPS := LocalDate;
          Competencia := ISO8601ToDate(S(Attempt,'competence')+'T00:00:00',False);
          cLocEmi := S(Profile,'municipality_code');
          tpEmit := tePrestador;
          IBSCBS.finNFSe := fnfsRegular;
          if Settings.GetValue('send_ibs_cbs') is TJSONTrue then
          begin
            IBSCBS.cIndOp := S(Settings,'cind_op');
            IBSCBS.valores.trib.gIBSCBS.CST := StrToCSTIBSCBS(S(Settings,'cst_ibs_cbs'));
            IBSCBS.valores.trib.gIBSCBS.cClassTrib := S(Settings,'cclass_trib');
          end;
          RegimeEspecialTributacao := retNenhum;
          OptanteSN := osnOptanteMEEPP;
          RegimeApuracaoSN := raFederaisMunicipalpeloSN;
          Prestador.IdentificacaoPrestador.CpfCnpj := S(CompanyData,'document');
          if (Profile.GetValue('municipal_registration') is TJSONString) then
            Prestador.IdentificacaoPrestador.InscricaoMunicipal := Profile.GetValue('municipal_registration').Value;
          Prestador.RazaoSocial := S(CompanyData,'name');
          Prestador.cUF := 31;
          Prestador.Endereco.Endereco := S(Profile,'street');
          Prestador.Endereco.Numero := S(Profile,'house_number');
          Prestador.Endereco.Bairro := S(Profile,'district');
          Prestador.Endereco.CodigoMunicipio := cLocEmi;
          Prestador.Endereco.xMunicipio := S(Profile,'municipality_name');
          Prestador.Endereco.UF := S(Profile,'state_code');
          Prestador.Endereco.CEP := S(Profile,'postal_code');
          Prestador.Endereco.CodigoPais := 1058;
          if Payload.GetValue('customer') is TJSONObject then
          begin
            Customer := Obj(Payload,'customer');
            Tomador.IdentificacaoTomador.CpfCnpj := S(Customer,'document');
            Tomador.RazaoSocial := S(Customer,'name');
          end;
          Servico.ItemListaServico := S(Settings,'service_code');
          Servico.CodigoTributacaoMunicipio := S(Settings,'municipal_service_code');
          Servico.CodigoNBS := S(Settings,'nbs_code');
          Servico.CodigoMunicipio := cLocEmi;
          Servico.CodigoPais := 1058;
          Servico.Discriminacao := S(Settings,'service_description');
          Servico.Valores.ValorServicos := StrToInt64(S(Payload,'amount_cents')) / 100;
          Servico.Valores.tribMun.tribISSQN := tiOperacaoTributavel;
          Servico.Valores.tribMun.tpRetISSQN := trNaoRetido;
          Fmt := TFormatSettings.Create;
          Fmt.DecimalSeparator := '.';
          Servico.Valores.totTrib.pTotTribSN := StrToFloat(S(Settings,'approx_simples_percent'),Fmt);
        end;
        Xml := Note.GerarXML;
        if Xml='' then Xml:=Note.XmlRps;
        Xml := NFSe.SSL.Assinar(Xml,'DPS','infDPS','','','','Id');
        if not NFSe.SSL.Validar(Xml,TPath.Combine(SchemaRoot,'DPS_v1.01.xsd'),ErrorText) then raise EEmissionError.Create('DPS invalida: '+ErrorText);
        if not NFSe.SSL.VerificarAssinatura(Xml,ErrorText,'infDPS','','','','Id') then raise EEmissionError.Create('Assinatura da DPS invalida.');
        TFile.WriteAllText(TPath.Combine(AttemptDir,'dps-assinada.xml'),Xml,TEncoding.UTF8);
        Execute('update emission_attempts set signed_dps=:xml,status=''prepared'',updated_at=now() where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
        Q.ParamByName('xml').AsWideMemo := Xml;
        Q.ExecSQL;
        SetState('sending');
        Contacted := True;
        Stage := 'acbr_emit';
        NFSe.Emitir('1',meUnitario,False);
        Stage := 'read_response';
        ResponseText := NFSe.WebService.Emite.ArquivoRetorno;
        TFile.WriteAllText(TPath.Combine(AttemptDir,'resposta.txt'),ResponseText,TEncoding.UTF8);
        Errors := TJSONArray.Create;
        Report.AddPair('errors',Errors);
        for N:=0 to NFSe.WebService.Emite.Erros.Count-1 do
        begin
          Err := TJSONObject.Create;
          Err.AddPair('code',NFSe.WebService.Emite.Erros[N].Codigo);
          Err.AddPair('description',NFSe.WebService.Emite.Erros[N].Descricao);
          Err.AddPair('complement',NFSe.WebService.Emite.Erros[N].Correcao);
          Errors.AddElement(Err);
        end;
        State := 'unknown';
        if NFSe.WebService.Emite.Sucesso and (Length(NFSe.WebService.Emite.Link)=50) and (Errors.Count=0) and (NFSe.NotasFiscais.Count>0) then
        begin
          InvoiceXml := NFSe.NotasFiscais[0].XmlNfse;
          if InvoiceXml<>'' then State:='authorized';
        end
        else if (ResponseText<>'') and (Errors.Count>0) then
        begin
          ResponseJson := TJSONObject.ParseJSONValue(ResponseText) as TJSONObject;
          try
            if (ResponseJson<>nil) and (ResponseJson.GetValue('erros') is TJSONArray) and
               (TJSONArray(ResponseJson.GetValue('erros')).Count>0) and
               (ResponseJson.GetValue('chaveAcesso')=nil) then State:='rejected';
          finally
            ResponseJson.Free;
          end;
        end;
        if InvoiceXml<>'' then TFile.WriteAllText(TPath.Combine(AttemptDir,'nfse.xml'),InvoiceXml,TEncoding.UTF8);
      except
        on E: Exception do
        begin
          if Contacted then State:='unknown' else State:='local_error';
          // Nao devolver erros de biblioteca com caminhos internos ou credenciais.
          Report.AddPair('error','Falha no fluxo fiscal. Verifique o estado da tentativa antes de nova operacao.');
          Report.AddPair('stage',Stage);
          Report.AddPair('exception_class',E.ClassName);
          if E is EEmissionError then Report.AddPair('validation',E.Message);
        end;
      end;
    finally
      Password := '';
      NFSe.Free;
      FiscalLock.Release;
    end;
    Report.AddPair('status',State);
    TFile.WriteAllText(TPath.Combine(AttemptDir,'resultado.json'),Report.ToJSON,TEncoding.UTF8);
    Conn.StartTransaction;
    try
      Execute('update emission_attempts set status=:state,result=cast(:result as jsonb),response_text=:response,invoice_xml=:xml,updated_at=now() where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
      Q.ParamByName('state').AsWideString := State;
      Q.ParamByName('result').AsWideMemo := Report.ToJSON;
      Q.ParamByName('response').AsWideMemo := ResponseText;
      Q.ParamByName('xml').AsWideMemo := InvoiceXml;
      Q.ExecSQL;
      if State='authorized' then
      begin
        Execute('select import_homologation_invoice(cast(:company as uuid),cast(:draft as uuid),:xml)->>''id''');
        Q.ParamByName('draft').AsWideString:=Draft;
        Q.ParamByName('xml').AsWideMemo:=InvoiceXml;
        Q.Open;
        Xml:=Q.Fields[0].AsString;
        Execute('update invoices set status=''authorized_homologation'',source=''sefin_api'' where id=cast(:invoice as uuid) and company_id=cast(:company as uuid)');
        Q.ParamByName('invoice').AsWideString:=Xml;
        Q.ExecSQL;
        Execute('update emission_attempts set invoice_id=cast(:invoice as uuid) where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
        Q.ParamByName('invoice').AsWideString:=Xml;
        Q.ExecSQL;
      end;
      Conn.Commit;
    except
      Conn.Rollback;
      raise;
    end;
    Execute('select (to_jsonb(a)-''signed_dps''-''invoice_xml''-''response_text'')::text from emission_attempts a where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
    Q.Open;
    Result:=Q.Fields[0].AsString;
  finally
    Report.Free;
    Envelope.Free;
    Q.Free;
  end;
end;

function DownloadDanfse(Conn: TFDConnection; const Company, Invoice: string): TBytes;
var
  Q: TFDQuery;
  Key, Document, InputXml, DataRoot, OutputDir, PdfPath: string;
  Unique: TGUID;
  Stream: TFileStream;
  {$IFDEF LINUX}
  ArgText: array[0..7] of UTF8String;
  Args: array[0..8] of MarshaledAString;
  Child, Waited, ExitStatus, I: Integer;
  {$ENDIF}
begin
  Q := TFDQuery.Create(nil);
  try
    Q.Connection := Conn;
    Q.SQL.Text := 'select access_key,issuer_document,xml_content from invoices where id=cast(:invoice as uuid) and company_id=cast(:company as uuid) and environment=''homologacao''';
    Q.ParamByName('invoice').AsWideString := Invoice;
    Q.ParamByName('company').AsWideString := Company;
    Q.Open;
    if Q.IsEmpty then raise EEmissionError.Create('Nota de homologacao nao encontrada nesta empresa.');
    Key := Q.Fields[0].AsString;
    Document := Q.Fields[1].AsString;
    InputXml := Q.Fields[2].AsString;
  finally
    Q.Free;
  end;
  CheckDigits(Key,50);
  CheckDigits(Document,14);
  DataRoot := GetEnvironmentVariable('NFSE_DATA_DIR');
  if DataRoot='' then raise EEmissionError.Create('Armazenamento nao configurado para o DANFSe.');
  CreateGUID(Unique);
  OutputDir := TPath.Combine(TPath.Combine(TPath.Combine(DataRoot,Company),'danfse'),GUIDToString(Unique));
  ForceDirectories(OutputDir);
  TFile.WriteAllBytes(TPath.Combine(OutputDir,'nfse.xml'),TEncoding.UTF8.GetBytes(InputXml));
  {$IFDEF LINUX}
  // Argumentos separados: nenhum valor e interpretado como comando shell.
  ArgText[0] := '/usr/bin/timeout';
  ArgText[1] := '90';
  ArgText[2] := '/bin/bash';
  ArgText[3] := '/app/download-danfse.sh';
  ArgText[4] := UTF8String(TPath.Combine(OutputDir,'nfse.xml'));
  ArgText[5] := UTF8String(OutputDir);
  ArgText[6] := UTF8String(Key);
  ArgText[7] := UTF8String(Document);
  for I:=0 to High(ArgText) do Args[I]:=MarshaledAString(ArgText[I]);
  Args[8]:=nil;
  if SpawnDanfse(Child,MarshaledAString(ArgText[0]),nil,nil,@Args[0],Posix.Unistd.environ)<>0 then
    raise EEmissionError.Create('Nao foi possivel iniciar a consulta isolada do DANFSe.');
  repeat
    Waited := waitpid(Child,@ExitStatus,0);
  until (Waited<>-1) or (errno<>EINTR);
  if (Waited<>Child) or not WIFEXITED(ExitStatus) or (WEXITSTATUS(ExitStatus)<>0) then
    raise EEmissionError.Create('Falha ou tempo limite ao gerar DANFSe de homologacao. Consulte renderer-error.txt no volume privado. Nenhuma nota foi emitida.');
  {$ELSE}
  raise EEmissionError.Create('Download oficial do DANFSe disponivel no servidor Linux.');
  {$ENDIF}
  PdfPath := TPath.Combine(OutputDir,'danfse.pdf');
  Stream := TFileStream.Create(PdfPath,fmOpenRead or fmShareDenyWrite);
  try
    if (Stream.Size<8) or (Stream.Size>20*1024*1024) then raise EEmissionError.Create('Tamanho de PDF invalido.');
    SetLength(Result,Stream.Size);
    Stream.ReadBuffer(Result[0],Length(Result));
  finally
    Stream.Free;
  end;
  if (Result[0]<>37) or (Result[1]<>80) or (Result[2]<>68) or (Result[3]<>70) or (Result[4]<>45) then
    raise EEmissionError.Create('Resposta do DANFSe nao e um arquivo PDF.');
end;
initialization
  FiscalLock := TCriticalSection.Create;
finalization
  FiscalLock.Free;
end.
