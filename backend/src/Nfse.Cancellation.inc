// Included in Nfse.Emission to share the ACBr process lock.
procedure ValidateCancellationEvent(NFSe: TACBrNFSeX; const Xml, Schemas: string);
var ErrorText: string;
begin
  if (TEncoding.UTF8.GetByteCount(Xml)>524288) or (Pos('<!DOCTYPE',UpperCase(Xml))>0) or
    (Pos('<!ENTITY',UpperCase(Xml))>0) then raise EEmissionError.Create('Evento recebido invalido.');
  if not NFSe.SSL.Validar(Xml,TPath.Combine(Schemas,'evento_v1.01.xsd'),ErrorText) then
    raise EEmissionError.Create('Schema do evento recebido invalido: '+ErrorText);
  if not NFSe.SSL.VerificarAssinatura(Xml,ErrorText,'infEvento','','','','Id') then
    raise EEmissionError.Create('Assinatura do evento invalida: '+ErrorText);
  if not NFSe.SSL.VerificarAssinatura(Xml,ErrorText,'infPedReg','','','','Id') then
    raise EEmissionError.Create('Assinatura do pedido de cancelamento invalida: '+ErrorText);
end;

// Read-only with respect to the fiscal service: only the previously saved reply is used.
// A local confirmation is persisted only after schema/signature + DB identity checks.
procedure ReconcileSavedCancellation(Conn: TFDConnection; const Company, Invoice: string);
var Q: TFDQuery; NFSe: TACBrNFSeX; AttemptId, Environment, Folder, Path, Xml, Schemas: string;
  Report: TJSONObject; Input: TFileStream;
begin
  Q:=TFDQuery.Create(nil); Q.Connection:=Conn; NFSe:=nil; Report:=nil;
  FiscalLock.Acquire;
  try
    Q.SQL.Text:='select a.id::text,i.environment from cancellation_attempts a join invoices i on i.id=a.invoice_id and i.company_id=a.company_id '+
      'where a.company_id=cast(:company as uuid) and a.invoice_id=cast(:invoice as uuid) and a.status in (''sending'',''unknown'') order by a.created_at desc,a.id desc limit 1';
    Q.ParamByName('company').AsWideString:=Company; Q.ParamByName('invoice').AsWideString:=Invoice; Q.Open;
    if Q.IsEmpty then Exit;
    AttemptId:=Q.Fields[0].AsString; Environment:=Q.Fields[1].AsString; Q.Close;
    Folder:=TPath.Combine(TPath.Combine(GetEnvironmentVariable('NFSE_DATA_DIR'),Company),'cancel-'+AttemptId);
    Path:=TPath.Combine(Folder,'resposta.txt');
    if not FileExists(Path) then Exit;
    Input:=TFileStream.Create(Path,fmOpenRead or fmShareDenyNone);
    try if (Input.Size=0) or (Input.Size>524288) then Exit; finally Input.Free; end;
    Xml:=TFile.ReadAllText(Path,TEncoding.UTF8);
    // ACBr replaces ArquivoRetorno with the decompressed event after successful parsing.
    if (Pos('<evento',Xml)=0) then Exit;
    Schemas:=GetEnvironmentVariable('NFSE_SCHEMAS_DIR');
    if Environment='producao' then
    begin Schemas:=GetEnvironmentVariable('NFSE_PRODUCTION_SCHEMAS_DIR'); if Schemas='' then Schemas:='/app/schemas-production'; end;
    NFSe:=TACBrNFSeX.Create(nil);
    NFSe.Configuracoes.Geral.SSLCryptLib:=cryOpenSSL;
    NFSe.Configuracoes.Geral.SSLXmlSignLib:=xsLibXml2;
    NFSe.Configuracoes.Geral.SSLHttpLib:=httpOpenSSL;
    try ValidateCancellationEvent(NFSe,Xml,Schemas);
    except on E:Exception do
      begin
        TFile.WriteAllText(TPath.Combine(Folder,'reconcile-error.txt'),Copy(E.Message,1,2048),TEncoding.UTF8);
        Exit;
      end;
    end; // Invalid or incomplete saved reply remains unresolved.
    Report:=TJSONObject.Create;
    Report.AddPair('status','cancelled'); Report.AddPair('recovered_from_saved_event',TJSONTrue.Create);
    Conn.StartTransaction;
    try
      Q.SQL.Text:='select status from cancellation_attempts where id=cast(:attempt as uuid) and company_id=cast(:company as uuid) for update';
      Q.ParamByName('attempt').AsWideString:=AttemptId; Q.ParamByName('company').AsWideString:=Company; Q.Open;
      if Q.IsEmpty then begin Conn.Rollback; Exit; end;
      if (Q.Fields[0].AsString<>'sending') and (Q.Fields[0].AsString<>'unknown') then begin Q.Close; Conn.Rollback; Exit; end;
      Q.Close;
      // The transition is invisible outside this transaction; the no-resend reservation stays held.
      Q.SQL.Text:='update cancellation_attempts set status=''sending'' where id=cast(:attempt as uuid) and company_id=cast(:company as uuid)';
      Q.ParamByName('attempt').AsWideString:=AttemptId; Q.ParamByName('company').AsWideString:=Company; Q.ExecSQL;
      Q.SQL.Text:='select finish_cancellation(cast(:company as uuid),cast(:attempt as uuid),''cancelled'',cast(:result as jsonb),:xml)';
      Q.ParamByName('company').AsWideString:=Company; Q.ParamByName('attempt').AsWideString:=AttemptId;
      Q.ParamByName('result').AsWideMemo:=Report.ToJSON; Q.ParamByName('xml').AsWideMemo:=Xml; Q.Open; Q.Close;
      Conn.Commit;
    except on E:Exception do
      begin
        if Conn.InTransaction then Conn.Rollback;
        TFile.WriteAllText(TPath.Combine(Folder,'reconcile-error.txt'),Copy(E.Message,1,2048),TEncoding.UTF8);
      end;
    end;
  finally
    Report.Free; NFSe.Free; Q.Free; FiscalLock.Release;
  end;
end;

function CancelInvoice(Conn: TFDConnection; const Company, Invoice, Reason: string; Code: Integer): string;
var
  Q: TFDQuery; NFSe: TACBrNFSeX; Event: TInfEvento;
  Certificate, Envelope, Report, ErrorItem: TJSONObject;
  ResponseValue: TJSONValue;
  Errors: TJSONArray;
  Work, Password, CertPath, Environment, Document, Key, BaseURL, Schemas, Folder, AttemptId, State, Xml, ErrorText: string;
  N: Integer;
  procedure SQL(const Text: string);
  begin
    Q.Close; Q.SQL.Text:=Text;
    if Q.Params.FindParam('company')<>nil then Q.ParamByName('company').AsWideString:=Company;
    if Q.Params.FindParam('invoice')<>nil then Q.ParamByName('invoice').AsWideString:=Invoice;
    if Q.Params.FindParam('attempt')<>nil then Q.ParamByName('attempt').AsWideString:=AttemptId;
  end;
begin
  if not (Code in [1,2,9]) or (Length(Trim(Reason))<15) or (Length(Reason)>255) then
    raise EEmissionError.Create('Informe motivo valido e justificativa de 15 a 255 caracteres.');
  Q:=TFDQuery.Create(nil); Q.Connection:=Conn; NFSe:=nil; Event:=nil;
  Certificate:=nil; Envelope:=nil; Report:=nil; ResponseValue:=nil; Work:=''; Password:='';
  FiscalLock.Acquire;
  try
    SQL('select (to_jsonb(a)-''event_xml'')::text from cancellation_attempts a where company_id=cast(:company as uuid) '+
      'and invoice_id=cast(:invoice as uuid) and status in (''sending'',''unknown'',''cancelled'') limit 1'); Q.Open;
    if not Q.IsEmpty then begin Result:=Q.Fields[0].AsString; Exit; end;
    SQL('select i.environment,i.issuer_document,i.access_key,f.municipality_code from invoices i '+
      'join fiscal_profiles f on f.company_id=i.company_id where i.company_id=cast(:company as uuid) '+
      'and i.id=cast(:invoice as uuid) and i.source=''sefin_api'' and i.status in (''authorized_homologation'',''authorized_production'')'); Q.Open;
    if Q.IsEmpty then raise EEmissionError.Create('Nota autorizada pela SEFIN nao encontrada.');
    Environment:=Q.Fields[0].AsString; Document:=Q.Fields[1].AsString; Key:=Q.Fields[2].AsString;
    CheckDigits(Key,50);
    if Environment='producao' then
    begin
      // Cancellation does not require the active emission series or PDF fonts.
      if (GetEnvironmentVariable('NFSE_ENABLE_PRODUCTION')<>'1') or
        (GetEnvironmentVariable('NFSE_PRODUCTION_ALLOWED_CNPJ')<>Document) then
        raise EEmissionError.Create('Operacoes em producao nao habilitadas no servidor para este CNPJ.');
      BaseURL:='https://sefin.nfse.gov.br/SefinNacional';
      Schemas:=GetEnvironmentVariable('NFSE_PRODUCTION_SCHEMAS_DIR');
      if Schemas='' then Schemas:='/app/schemas-production';
    end
    else
    begin
      if GetEnvironmentVariable('NFSE_ENABLE_HOMOLOGATION')<>'1' then raise EEmissionError.Create('Homologacao nao habilitada.');
      BaseURL:='https://sefin.producaorestrita.nfse.gov.br/SefinNacional';
      Schemas:=GetEnvironmentVariable('NFSE_SCHEMAS_DIR');
    end;
    if not FileExists(TPath.Combine(Schemas,'evento_v1.01.xsd')) then raise EEmissionError.Create('Schemas de eventos indisponiveis.');
    try Certificate:=CertificateOperation(Company,Document,'materialize',nil,Work);
    except on E:ECertificateError do raise EEmissionError.Create(E.Message); end;
    CertPath:=S(Certificate,'path'); Password:=S(Certificate,'password');
    NFSe:=TACBrNFSeX.Create(nil);
    NFSe.Configuracoes.Geral.SSLCryptLib:=cryOpenSSL;
    NFSe.Configuracoes.Geral.SSLXmlSignLib:=xsLibXml2;
    NFSe.Configuracoes.Geral.SSLHttpLib:=httpOpenSSL;
    NFSe.Configuracoes.Geral.LayoutNFSe:=lnfsPadraoNacionalv101;
    NFSe.Configuracoes.Geral.CodigoMunicipio:=Q.Fields[3].AsInteger;
    NFSe.Configuracoes.Geral.Emitente.CNPJ:=Document;
    NFSe.Configuracoes.WebServices.UF:='MG';
    if Environment='producao' then NFSe.Configuracoes.WebServices.Ambiente:=taProducao
    else NFSe.Configuracoes.WebServices.Ambiente:=taHomologacao;
    NFSe.Configuracoes.WebServices.TimeOut:=30000;
    NFSe.Configuracoes.Geral.MontarPathSchema:=False;
    NFSe.Configuracoes.Arquivos.PathSchemas:=IncludeTrailingPathDelimiter(Schemas);
    NFSe.SSL.ArquivoPFX:=CertPath; NFSe.SSL.Senha:=AnsiString(UTF8String(Password)); Password:='';
    NFSe.SSL.CarregarCertificado;
    if NFSe.SSL.CertCNPJ<>Document then raise EEmissionError.Create('Certificado nao pertence ao prestador.');
    SQL('select reserve_cancellation(cast(:company as uuid),cast(:invoice as uuid),:code,:reason)::text');
    Q.ParamByName('code').AsInteger:=Code; Q.ParamByName('reason').AsWideString:=Trim(Reason); Q.Open;
    Envelope:=TJSONObject.ParseJSONValue(Q.Fields[0].AsString) as TJSONObject;
    if not (Envelope.GetValue('created') is TJSONTrue) then begin Result:=Obj(Envelope,'attempt').ToJSON; Exit; end;
    AttemptId:=S(Obj(Envelope,'attempt'),'id'); Q.Close;
    Report:=TJSONObject.Create; Errors:=TJSONArray.Create; Report.AddPair('errors',Errors);
    State:='unknown'; Xml:='';
    try
      Folder:=TPath.Combine(TPath.Combine(GetEnvironmentVariable('NFSE_DATA_DIR'),Company),'cancel-'+AttemptId);
      ForceDirectories(Folder);
      NFSe.Configuracoes.Arquivos.PathSalvar:=Folder; NFSe.Configuracoes.Arquivos.PathGer:=Folder;
      NFSe.Configuracoes.Arquivos.PathCan:=Folder;
      TFile.WriteAllText(TPath.Combine(Folder,'servicos.ini'),'[PadraoNacional]'+sLineBreak+'Versao=1.01'+sLineBreak+
        'HomRecepcionar='+BaseURL+sLineBreak+'ProRecepcionar='+BaseURL+sLineBreak+
        'HomEnviarEvento='+BaseURL+sLineBreak+'ProEnviarEvento='+BaseURL+sLineBreak,TEncoding.ASCII);
      NFSe.Configuracoes.Arquivos.IniServicos:=TPath.Combine(Folder,'servicos.ini');
      NFSe.Configuracoes.WebServices.LerParams; NFSe.SetProvedor(proPadraoNacional,ve101);
      if (Environment='producao') and (NFSe.Provider.ConfigWebServices.Producao.EnviarEvento<>BaseURL) then raise EEmissionError.Create('URL fiscal incorreta.');
      if (Environment='homologacao') and (NFSe.Provider.ConfigWebServices.Homologacao.EnviarEvento<>BaseURL) then raise EEmissionError.Create('URL fiscal incorreta.');
      Event:=TInfEvento.Create;
      with Event.pedRegEvento do
      begin
        if Environment='producao' then tpAmb:=1 else tpAmb:=2;
        verAplic:='VEEV-API-1.0'; dhEvento:=IncHour(TTimeZone.Local.ToUniversalTime(Now),-3);
        chNFSe:=Key; nPedRegEvento:=1; tpEvento:=teCancelamento; cMotivo:=Code;
        // The installed provider interpolates this field into XML before signing.
        xMotivo:=StringReplace(StringReplace(StringReplace(Trim(Reason),'&','&amp;',[rfReplaceAll]),'<','&lt;',[rfReplaceAll]),'>','&gt;',[rfReplaceAll]);
      end;
      NFSe.EnviarEvento(Event);
      TFile.WriteAllText(TPath.Combine(Folder,'resposta.txt'),NFSe.WebService.EnviarEvento.ArquivoRetorno,TEncoding.UTF8);
      for N:=0 to NFSe.WebService.EnviarEvento.Erros.Count-1 do
      begin
        ErrorItem:=TJSONObject.Create;
        ErrorItem.AddPair('code',NFSe.WebService.EnviarEvento.Erros[N].Codigo);
        ErrorItem.AddPair('description',NFSe.WebService.EnviarEvento.Erros[N].Descricao);
        Errors.AddElement(ErrorItem);
      end;
      if NFSe.WebService.EnviarEvento.SucessoCanc and NFSe.WebService.EnviarEvento.Sucesso and (Errors.Count=0) then
      begin
        Xml:=NFSe.WebService.EnviarEvento.XmlRetorno;
        ValidateCancellationEvent(NFSe,Xml,Schemas);
        State:='cancelled';
      end
      else if Errors.Count>0 then
      begin
        ResponseValue:=TJSONObject.ParseJSONValue(NFSe.WebService.EnviarEvento.ArquivoRetorno);
        // Only an explicit SEFIN business rejection permits a new request.
        // HTML, transport errors or malformed/missing event data remain uncertain.
        if (ResponseValue is TJSONObject) and
          (TJSONObject(ResponseValue).GetValue('erros') is TJSONArray) and
          (TJSONArray(TJSONObject(ResponseValue).GetValue('erros')).Count>0) and
          (TJSONObject(ResponseValue).GetValue('eventoXmlGZipB64')=nil) then State:='rejected';
      end;
    except
      on E:Exception do
      begin
        State:='unknown'; Xml:='';
        if DirectoryExists(Folder) then
          TFile.WriteAllText(TPath.Combine(Folder,'diagnostico.txt'),Copy(E.Message,1,2048),TEncoding.UTF8);
        Report.AddPair('error','Cancelamento sem confirmacao. Consulte esta tentativa antes de outra operacao.');
      end;
    end;
    Report.AddPair('status',State);
    try
      SQL('select finish_cancellation(cast(:company as uuid),cast(:attempt as uuid),:status,cast(:result as jsonb),:xml)');
      Q.ParamByName('status').AsWideString:=State; Q.ParamByName('result').AsWideMemo:=Report.ToJSON;
      Q.ParamByName('xml').AsWideMemo:=Xml; Q.Open; Q.Close;
    except
      // Keep the persisted sending reservation: never re-send after an uncertain result.
      on E:Exception do raise EEmissionError.Create('Cancelamento sem confirmacao local. Consulte a tentativa; nao reenvie.');
    end;
    SQL('select (to_jsonb(a)-''event_xml'')::text from cancellation_attempts a where company_id=cast(:company as uuid) and id=cast(:attempt as uuid)');
    Q.Open; Result:=Q.Fields[0].AsString;
  finally
    Password:=''; Event.Free; NFSe.Free; ResponseValue.Free; Report.Free; Envelope.Free; Certificate.Free;
    ClearCertificateWork(Work); Q.Free; FiscalLock.Release;
  end;
end;
