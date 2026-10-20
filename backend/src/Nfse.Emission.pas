unit Nfse.Emission;

interface

uses System.SysUtils, System.JSON, FireDAC.Comp.Client;

type
  EEmissionError = class(Exception);

function EmitInvoice(Conn: TFDConnection; const Company, Draft, IssuedAt, Competence, Environment: string): string;
function EmissionConfig(Conn: TFDConnection; const Company: string): string;
function DownloadDanfse(Conn: TFDConnection; const Company, Invoice: string): TBytes;

implementation

uses
  System.Classes, System.IOUtils, System.DateUtils, System.SyncObjs, Nfse.Certificates,
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

function EmissionConfig(Conn: TFDConnection; const Company: string): string;
var Q: TFDQuery; Fonts: string; Ready: Boolean;
begin
  Fonts:=GetEnvironmentVariable('NFSE_DANFSE_FONT_DIR');
  if Fonts='' then Fonts:=TPath.Combine(GetEnvironmentVariable('NFSE_DATA_DIR'),'fonts');
  Ready:=FileExists(TPath.Combine(Fonts,'arial.ttf')) and FileExists(TPath.Combine(Fonts,'arialbd.ttf')) and FileExists(TPath.Combine(Fonts,'micross.ttf'));
  Q:=TFDQuery.Create(nil);
  try
    Q.Connection:=Conn;
    Q.SQL.Text:='select jsonb_build_object(''production_enabled'',coalesce(e.production_enabled,false),'+
      '''production_series'',e.production_series,''server_enabled'',cast(:server as boolean),''pilot_allowed'',c.document=:pilot,'+
      '''fonts_ready'',cast(:fonts as boolean),''production_available'',coalesce(e.production_enabled,false) '+
      'and cast(:server as boolean) and c.document=:pilot and cast(:fonts as boolean) and exists(select 1 from dps_sequences s '+
      'where s.company_id=c.id and s.environment=''producao'' and s.series=e.production_series))::text '+
      'from companies c left join company_emission_config e on e.company_id=c.id where c.id=cast(:company as uuid)';
    Q.ParamByName('company').AsWideString:=Company;
    Q.ParamByName('server').AsBoolean:=GetEnvironmentVariable('NFSE_ENABLE_PRODUCTION')='1';
    Q.ParamByName('pilot').AsWideString:=GetEnvironmentVariable('NFSE_PRODUCTION_ALLOWED_CNPJ');
    Q.ParamByName('fonts').AsBoolean:=Ready;
    Q.Open;
    if Q.IsEmpty then raise EEmissionError.Create('Empresa nao encontrada.');
    Result:=Q.Fields[0].AsString;
  finally Q.Free; end;
end;

function EmitInvoice(Conn: TFDConnection; const Company, Draft, IssuedAt, Competence, Environment: string): string;
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
  CertificateWork, CertificatePath: string;
  CertificateResult: TJSONObject;
  BaseURL, InvoiceStatus, ConfigJson: string;
  Production: Boolean;

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
  Production:=Environment='producao';
  if not Production and (Environment<>'homologacao') then raise EEmissionError.Create('Ambiente invalido.');
  if not Production and (GetEnvironmentVariable('NFSE_ENABLE_HOMOLOGATION') <> '1') then
    raise EEmissionError.Create('Emissao de homologacao ainda nao habilitada no servidor.');
  if Production then
  begin
    ConfigJson:=EmissionConfig(Conn,Company);
    CertificateResult:=TJSONObject.ParseJSONValue(ConfigJson) as TJSONObject;
    try
      if not (CertificateResult.GetValue('production_available') is TJSONTrue) then
        raise EEmissionError.Create('Producao indisponivel. Confira liberacao da empresa, piloto no servidor, serie e fontes do DANFSe.');
    finally CertificateResult.Free; end;
    BaseURL:='https://sefin.nfse.gov.br/SefinNacional'; InvoiceStatus:='authorized_production';
  end
  else begin BaseURL:='https://sefin.producaorestrita.nfse.gov.br/SefinNacional'; InvoiceStatus:='authorized_homologation'; end;
  CertRoot := GetEnvironmentVariable('NFSE_CERTIFICATES_DIR');
  DataRoot := GetEnvironmentVariable('NFSE_DATA_DIR');
  SchemaRoot := GetEnvironmentVariable('NFSE_SCHEMAS_DIR');
  if Production then
  begin
    SchemaRoot:=GetEnvironmentVariable('NFSE_PRODUCTION_SCHEMAS_DIR');
    if SchemaRoot='' then SchemaRoot:='/app/schemas-production';
  end;
  if (CertRoot='') or (DataRoot='') or not FileExists(TPath.Combine(SchemaRoot,'DPS_v1.01.xsd')) then
    raise EEmissionError.Create('Diretorios fiscais ou schemas nao configurados.');
  Q := TFDQuery.Create(nil);
  Q.Connection := Conn;
  Envelope := nil;
  NFSe := nil;
  Report := nil;
  CertificateWork:=''; CertificateResult:=nil;
  try
    Execute('select (to_jsonb(a)-''signed_dps''-''invoice_xml''-''response_text'')::text from emission_attempts a '+
      'where company_id=cast(:company as uuid) and draft_id=cast(:draft as uuid) and environment=:environment');
    Q.ParamByName('draft').AsWideString:=Draft; Q.ParamByName('environment').AsWideString:=Environment; Q.Open;
    if not Q.IsEmpty then begin Result:=Q.Fields[0].AsString; Exit; end;
    Q.Close;
    Execute('select document from companies where id=cast(:company as uuid)'); Q.Open;
    if Q.IsEmpty then raise EEmissionError.Create('Empresa nao encontrada.');
    try
      CertificateResult:=CertificateOperation(Company,Q.Fields[0].AsString,'materialize',nil,CertificateWork);
      CertificatePath:=S(CertificateResult,'path');
      Password:=CertificateResult.GetValue('password').Value;
    except on E:ECertificateError do raise EEmissionError.Create(E.Message); end;
    Q.Close;
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
    Execute('select reserve_emission(cast(:company as uuid),cast(:draft as uuid),cast(:issued as timestamptz),cast(:competence as date),:environment)::text');
    Q.ParamByName('environment').AsWideString:=Environment;
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
          raise EEmissionError.Create('Perfil inicial limitado a Juiz de Fora/MG.');
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
        if Production then NFSe.Configuracoes.WebServices.Ambiente := taProducao
        else NFSe.Configuracoes.WebServices.Ambiente := taHomologacao;
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
          'HomGerarNFSe='+BaseURL+sLineBreak+'ProRecepcionar='+BaseURL+sLineBreak+
          'ProGerarNFSe='+BaseURL+sLineBreak,TEncoding.ASCII);
        NFSe.Configuracoes.Arquivos.IniServicos := TPath.Combine(AttemptDir,'servicos.ini');
        NFSe.Configuracoes.WebServices.LerParams;
        NFSe.Configuracoes.Geral.CodigoMunicipio := StrToInt(S(Profile,'municipality_code'));
        NFSe.SetProvedor(proPadraoNacional,ve101);
        if Production then
        begin
          if NFSe.Provider.ConfigWebServices.Producao.GerarNFSe<>BaseURL then raise EEmissionError.Create('URL de producao incorreta.');
        end
        else if NFSe.Provider.ConfigWebServices.Homologacao.GerarNFSe <> BaseURL then raise EEmissionError.Create('URL de homologacao incorreta.');
        NFSe.SSL.ArquivoPFX := CertificatePath;
        NFSe.SSL.Senha := AnsiString(UTF8String(Password));
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
          if InvoiceXml<>'' then
          begin
            if Production then
            begin
              if not NFSe.SSL.Validar(InvoiceXml,TPath.Combine(SchemaRoot,'NFSe_v1.01.xsd'),ErrorText) then
                raise EEmissionError.Create('Resposta de producao fora do esquema. Consulte a tentativa antes de nova emissao.');
              if not NFSe.SSL.VerificarAssinatura(InvoiceXml,ErrorText,'infNFSe','','','','Id') then
                raise EEmissionError.Create('Assinatura da NFS-e nao confirmada. Consulte a tentativa antes de nova emissao.');
            end;
            State:='authorized';
          end;
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
        Execute('select import_invoice(cast(:company as uuid),cast(:draft as uuid),:xml,:environment)->>''id''');
        Q.ParamByName('environment').AsWideString:=Environment;
        Q.ParamByName('draft').AsWideString:=Draft;
        Q.ParamByName('xml').AsWideMemo:=InvoiceXml;
        Q.Open;
        Xml:=Q.Fields[0].AsString;
        Execute('update invoices set status=:status,source=''sefin_api'' where id=cast(:invoice as uuid) and company_id=cast(:company as uuid)');
        Q.ParamByName('status').AsWideString:=InvoiceStatus;
        Q.ParamByName('invoice').AsWideString:=Xml;
        Q.ExecSQL;
        Execute('update emission_attempts set invoice_id=cast(:invoice as uuid) where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
        Q.ParamByName('invoice').AsWideString:=Xml;
        Q.ExecSQL;
      end;
      Conn.Commit;
    except
      Conn.Rollback;
      // A resposta chegou, mas a persistencia/validacao nao foi concluida: nunca reenviar.
      State:='unknown';
      Report.RemovePair('status').Free;
      Report.AddPair('status',State);
      Report.AddPair('persistence_error','Autorizacao ainda nao conciliada. Consulte a tentativa antes de outra emissao.');
      Execute('update emission_attempts set status=''unknown'',result=cast(:result as jsonb),invoice_xml=:xml,response_text=:response,updated_at=now() '+
        'where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
      Q.ParamByName('result').AsWideMemo:=Report.ToJSON; Q.ParamByName('xml').AsWideMemo:=InvoiceXml;
      Q.ParamByName('response').AsWideMemo:=ResponseText; Q.ExecSQL;
      TFile.WriteAllText(TPath.Combine(AttemptDir,'resultado.json'),Report.ToJSON,TEncoding.UTF8);
    end;
    Execute('select (to_jsonb(a)-''signed_dps''-''invoice_xml''-''response_text'')::text from emission_attempts a where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
    Q.Open;
    Result:=Q.Fields[0].AsString;
  finally
    Password:=''; CertificateResult.Free; ClearCertificateWork(CertificateWork);
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
    Q.SQL.Text := 'select access_key,issuer_document,xml_content from invoices where id=cast(:invoice as uuid) and company_id=cast(:company as uuid)';
    Q.ParamByName('invoice').AsWideString := Invoice;
    Q.ParamByName('company').AsWideString := Company;
    Q.Open;
    if Q.IsEmpty then raise EEmissionError.Create('Nota nao encontrada nesta empresa.');
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
    raise EEmissionError.Create('Falha ou tempo limite ao gerar DANFSe. Consulte renderer-error.txt no volume privado. Esta consulta nao emite notas.');
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
