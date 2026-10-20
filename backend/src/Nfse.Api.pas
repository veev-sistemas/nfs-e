unit Nfse.Api;

interface

uses
  System.SysUtils, System.Classes, System.JSON, Data.DB,
  FireDAC.Comp.Client, FireDAC.Stan.Error, FireDAC.Stan.Param,
  Web.HTTPApp, Horse;

type
  EApiError = class(Exception)
  public
    Status: Integer;
    constructor Create(AStatus: Integer; const Message: string);
  end;

  TNfseApi = class
  private
    procedure Handle(Req: THorseRequest; Res: THorseResponse);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Start;
  end;

implementation

uses Nfse.Db, Nfse.Emission, Nfse.Admin, FireDAC.Phys.PGWrapper, System.DateUtils, System.RegularExpressions;

constructor EApiError.Create(AStatus: Integer; const Message: string);
begin
  inherited Create(Message);
  Status := AStatus;
end;

function ParseBody(Request: TWebRequest; MaxSize: Integer = 65536): TJSONObject;
var
  Value: TJSONValue;
begin
  if (Request.Content = '') or (Request.ContentLength > MaxSize) then
    raise EApiError.Create(400, 'Corpo JSON obrigatorio ou limite de tamanho excedido.');
  Value := TJSONObject.ParseJSONValue(Request.Content);
  if not (Value is TJSONObject) then
  begin
    Value.Free;
    raise EApiError.Create(400, 'JSON deve ser um objeto.');
  end;
  Result := TJSONObject(Value);
end;

function RequiredString(Obj: TJSONObject; const Key: string): string;
var V: TJSONValue;
begin
  V := Obj.GetValue(Key);
  if not (V is TJSONString) then
    raise EApiError.Create(422, Key + ' deve ser texto.');
  Result := Trim(V.Value);
  if (Result = '') or (Length(Result) > 500) then
    raise EApiError.Create(422, Key + ' vazio ou muito longo.');
end;

procedure ValidateSettings(Obj: TJSONObject);
var
  Pair: TJSONPair;
  Rate: Double;
  Fmt: TFormatSettings;
begin
  Fmt := TFormatSettings.Create;
  Fmt.DecimalSeparator := '.';
  for Pair in Obj do
  begin
    if (Pair.JsonString.Value = 'simples_percent') or
       (Pair.JsonString.Value = 'iss_percent') or
       (Pair.JsonString.Value = 'approx_simples_percent') then
    begin
      if not (Pair.JsonValue is TJSONNumber) then
        raise EApiError.Create(422, 'Percentual deve ser numero.');
      if not TryStrToFloat(Pair.JsonValue.Value, Rate, Fmt) then
        raise EApiError.Create(422, 'Percentual invalido.');
      if (Rate < 0) or (Rate > 100) then
        raise EApiError.Create(422, 'Percentual deve estar entre 0 e 100.');
    end
    else if Pair.JsonString.Value = 'send_ibs_cbs' then
    begin
      if not (Pair.JsonValue is TJSONBool) then
        raise EApiError.Create(422, 'send_ibs_cbs deve ser booleano: true ou false.');
    end
    else if (Pair.JsonString.Value = 'cclass_trib') or
            (Pair.JsonString.Value = 'cind_op') then
    begin
      if Pair.JsonValue is TJSONNumber then
        raise EApiError.Create(422, Pair.JsonString.Value + ' deve ser texto.');
      if not TRegEx.IsMatch(RequiredString(Obj, Pair.JsonString.Value), '^[0-9]{6}$') then
        raise EApiError.Create(422, Pair.JsonString.Value + ' deve conter seis digitos em texto.');
    end
    else if Pair.JsonString.Value = 'cst_ibs_cbs' then
    begin
      if Pair.JsonValue is TJSONNumber then
        raise EApiError.Create(422, 'cst_ibs_cbs deve ser texto.');
      if not TRegEx.IsMatch(RequiredString(Obj, 'cst_ibs_cbs'), '^[0-9]{3}$') then
        raise EApiError.Create(422, 'cst_ibs_cbs deve conter tres digitos em texto.');
    end
    else if (Pair.JsonString.Value = 'service_code') or
            (Pair.JsonString.Value = 'service_description') or
            (Pair.JsonString.Value = 'tax_regime') or
            (Pair.JsonString.Value = 'municipal_service_code') or
            (Pair.JsonString.Value = 'nbs_code') then
      RequiredString(Obj, Pair.JsonString.Value)
    else
      raise EApiError.Create(422, 'Configuracao desconhecida: ' + Pair.JsonString.Value);
  end;
end;

procedure ValidateDocument(const Document: string);
var Ch: Char;
begin
  if (Length(Document) <> 11) and (Length(Document) <> 14) then
    raise EApiError.Create(422, 'Documento deve ter 11 ou 14 digitos sem pontuacao.');
  for Ch in Document do
    if not CharInSet(Ch, ['0'..'9']) then
      raise EApiError.Create(422, 'Documento deve conter apenas digitos.');
end;

constructor TNfseApi.Create;
begin
  inherited;
  THorse.MaxConnections := 32;
  THorse.Get('/health', Handle);
  THorse.Post('/v1/admin/auth/login', Handle);
  THorse.Get('/v1/admin/auth/me', Handle);
  THorse.Post('/v1/admin/auth/logout', Handle);
  THorse.All('/v1/admin/companies', Handle);
  THorse.Patch('/v1/admin/companies/:id/access', Handle);
  THorse.Post('/v1/admin/companies/:id/password', Handle);
  THorse.Get('/v1/admin/companies/:id/numbering', Handle);
  THorse.Patch('/v1/admin/companies/:id/numbering', Handle);
  THorse.Get('/v1/admin/companies/:id/certificate', Handle);
  THorse.Post('/v1/admin/companies/:id/certificate', Handle);
  THorse.Get('/v1/admin/companies/:id/production', Handle);
  THorse.Patch('/v1/admin/companies/:id/production', Handle);
  THorse.Patch('/v1/admin/companies/:id/environment', Handle);
  THorse.Post('/v1/auth/login', Handle);
  THorse.Post('/v1/auth/logout', Handle);
  THorse.Get('/v1/auth/me', Handle);
  THorse.Get('/v1/emission-config', Handle);
  THorse.All('/v1/settings', Handle);
  THorse.All('/v1/customers', Handle);
  THorse.All('/v1/drafts', Handle);
  THorse.All('/v1/invoices', Handle);
  THorse.All('/v1/invoices/import-homologation', Handle);
  THorse.Get('/v1/invoices/:id', Handle);
  THorse.Get('/v1/invoices/:id/xml', Handle);
  THorse.Get('/v1/invoices/:id/pdf', Handle);
  THorse.Post('/v1/invoices/:id/cancel', Handle);
  THorse.Get('/v1/invoices/:id/cancellation', Handle);
  THorse.Get('/v1/invoices/:id/cancellation/xml', Handle);
  THorse.Post('/v1/drafts/:id/emit-homologation', Handle);
  THorse.Post('/v1/drafts/:id/emit-production', Handle);
  THorse.Get('/v1/emission-attempts/:id', Handle);
end;

destructor TNfseApi.Destroy;
begin
  if THorse.IsRunning then THorse.StopListen;
  inherited;
end;

procedure TNfseApi.Start;
var
  Port: Integer;
  Host: string;
begin
  Port := StrToIntDef(GetEnvironmentVariable('NFSE_PORT'), 9000);
  if (Port < 1) or (Port > 65535) then
    raise Exception.Create('NFSE_PORT invalida.');
  Host := GetEnvironmentVariable('NFSE_BIND');
  if Host = '' then Host := '127.0.0.1';
  THorse.Listen(Port, Host,
    procedure
    begin
      Writeln('Servidor Horse ativo: http://' + Host + ':' + IntToStr(Port) + '/health');
      Writeln('Mantenha este processo aberto. CTRL+C para encerrar.');
    end);
end;

procedure TNfseApi.Handle(Req: THorseRequest; Res: THorseResponse);
var
  Request: TWebRequest;
  Response: TWebResponse;
  Conn: TFDConnection;
  Q: TFDQuery;
  Body, Settings: TJSONObject;
  V: TJSONValue;
  Company, Token, Route, Method, Customer, Document: string;
  Amount: Int64;
  Guid: TGUID;
  InvoiceId, DraftId, InvoiceXml: string;
  IssuedAt, Competence, DateFrom, DateTo, Environment, StatusFilter: string;
  ParsedDate: TDateTime;
  PdfBytes: TBytes;

  procedure Run(const SQL: string);
  begin
    Q.Close;
    Q.SQL.Text := SQL;
    if Q.Params.FindParam('company') <> nil then
      Q.ParamByName('company').AsWideString := Company;
  end;

  procedure ReturnQuery;
  begin
    Q.Open;
    Response.Content := Q.Fields[0].AsString;
  end;

begin
  Request := Req.RawWebRequest;
  Response := Res.RawWebResponse;
  Conn := nil;
  Q := nil;
  Body := nil;
  Response.ContentType := 'application/json; charset=utf-8';
  Response.SetCustomHeader('Cache-Control', 'no-store');
  try
    try
      Route := Request.PathInfo;
      Method := UpperCase(Request.Method);
      if Copy(Route,1,10)='/v1/admin/' then
      begin
        HandleAdmin(Request,Response);
        Exit;
      end;
      if (Method = 'GET') and (Route = '/health') then
      begin
        Response.Content := '{"status":"ok"}';
        Exit;
      end;
      if (Method = 'POST') and (Route = '/v1/auth/login') then
      begin
        Body := ParseBody(Request, 4096);
        Document := RequiredString(Body, 'cnpj');
        Document := TRegEx.Replace(Document, '[./\-\s]', '');
        ValidateDocument(Document);
        if Length(Document) <> 14 then
          raise EApiError.Create(422, 'CNPJ deve ter 14 digitos.');
        V := Body.GetValue('password');
        if not (V is TJSONString) then
          raise EApiError.Create(422, 'password deve ser texto.');
        Token := V.Value;
        if (TEncoding.UTF8.GetByteCount(Token) < 12) or
           (TEncoding.UTF8.GetByteCount(Token) > 72) then
          raise EApiError.Create(401, 'CNPJ ou senha invalidos.');
        Conn := OpenDatabase;
        Q := TFDQuery.Create(nil);
        Q.Connection := Conn;
        Q.SQL.Text := 'select login_company(:document,:password)::text';
        Q.ParamByName('document').AsWideString := Document;
        Q.ParamByName('password').AsWideString := Token;
        Q.Open;
        Response.Content := Q.Fields[0].AsString;
        if Pos('"error"', Response.Content) > 0 then Response.StatusCode := 401;
        Exit;
      end;
      Token := Request.GetFieldByName('Authorization');
      if Copy(Token, 1, 7) <> 'Bearer ' then
        raise EApiError.Create(401, 'Chave de API obrigatoria.');
      Token := Copy(Token, 8, MaxInt);
      if (Length(Token) < 32) or (Length(Token) > 256) then
        raise EApiError.Create(401, 'Chave de API invalida.');
      Conn := OpenDatabase;
      Q := TFDQuery.Create(nil);
      Q.Connection := Conn;
      Q.SQL.Text := 'select c.id::text from companies c where c.access_enabled and (' +
        'exists(select 1 from api_keys k where k.company_id=c.id and k.active ' +
        'and k.token_hash=encode(digest(:token,''sha256''),''hex'')) or ' +
        'exists(select 1 from access_sessions s join company_users u on u.id=s.user_id ' +
        'where u.company_id=c.id and s.expires_at>now() ' +
        'and s.token_hash=encode(digest(:token,''sha256''),''hex'')))';
      Q.ParamByName('token').AsWideString := Token;
      Q.Open;
      if Q.IsEmpty then raise EApiError.Create(401, 'Chave de API invalida.');
      Company := Q.Fields[0].AsString;
      Q.Close;

      if (Route = '/v1/auth/logout') and (Method = 'POST') then
      begin
        Run('delete from access_sessions where token_hash=encode(digest(:token,''sha256''),''hex'')');
        Q.ParamByName('token').AsWideString := Token;
        Q.ExecSQL;
        Response.Content := '{"status":"ok"}';
      end
      else if (Route = '/v1/auth/me') and (Method = 'GET') then
      begin
        Run('select jsonb_build_object(''id'',id,''name'',name,''document'',document)::text ' +
          'from companies where id=cast(:company as uuid)');
        ReturnQuery;
      end
      else if (Route = '/v1/settings') and (Method = 'GET') then
      begin
        Run('select coalesce((select settings::text from fiscal_defaults ' +
          'where company_id = cast(:company as uuid)), ''{}'')');
        ReturnQuery;
      end
      else if (Route = '/v1/settings') and (Method = 'PATCH') then
      begin
        Body := ParseBody(Request);
        ValidateSettings(Body);
        Run('insert into fiscal_defaults(company_id, settings) ' +
          'values(cast(:company as uuid), cast(:settings as jsonb)) ' +
          'on conflict(company_id) do update set ' +
          'settings = fiscal_defaults.settings || excluded.settings, updated_at = now() ' +
          'returning settings::text');
        Q.ParamByName('settings').AsWideString := Body.ToJSON;
        ReturnQuery;
      end
      else if (Route = '/v1/customers') and (Method = 'GET') then
      begin
        Run('select coalesce(jsonb_agg(to_jsonb(c)), ''[]''::jsonb)::text from ' +
          '(select id, name, document from customers where company_id = cast(:company as uuid) ' +
          'order by name, id limit 100) c');
        ReturnQuery;
      end
      else if (Route = '/v1/customers') and (Method = 'POST') then
      begin
        Body := ParseBody(Request);
        Customer := RequiredString(Body, 'name');
        Document := RequiredString(Body, 'document');
        ValidateDocument(Document);
        Run('insert into customers(company_id, name, document) values ' +
          '(cast(:company as uuid), upper(btrim(:name)), :document) returning ' +
          'jsonb_build_object(''id'', id, ''name'', name, ''document'', document)::text');
        Q.ParamByName('name').AsWideString := Customer;
        Q.ParamByName('document').AsWideString := Document;
        ReturnQuery;
        Response.StatusCode := 201;
      end
      else if (Route='/v1/emission-config') and (Method='GET') then
        Response.Content:=EmissionConfig(Conn,Company)
      else if (Route = '/v1/drafts') and (Method = 'POST') then
      begin
        Body := ParseBody(Request);
        Environment:='homologacao';
        if Body.GetValue('environment')<>nil then Environment:=RequiredString(Body,'environment');
        if (Environment<>'homologacao') and (Environment<>'producao') then raise EApiError.Create(422,'Ambiente invalido.');
        Run('select coalesce((select active_environment from company_emission_config where company_id=cast(:company as uuid)),''homologacao'')'); Q.Open;
        if Q.Fields[0].AsString<>Environment then raise EApiError.Create(422,'O ambiente foi definido pelo administrador. Atualize a tela.'); Q.Close;
        Customer := '';
        V := Body.GetValue('customer_id');
        if (V <> nil) and not (V is TJSONNull) then
        begin
          Customer := RequiredString(Body, 'customer_id');
          try
            Guid := StringToGUID('{' + Customer + '}');
          except
            on E: EConvertError do
              raise EApiError.Create(422, 'customer_id deve ser UUID.');
          end;
        end;
        V := Body.GetValue('amount_cents');
        if not (V is TJSONNumber) then
          raise EApiError.Create(422, 'amount_cents deve ser inteiro positivo.');
        if not TryStrToInt64(V.Value, Amount) then
          raise EApiError.Create(422, 'amount_cents deve ser inteiro positivo.');
        if (Amount <= 0) or (Amount > 999999999999) then
          raise EApiError.Create(422, 'Valor fora do intervalo permitido.');
        V := Body.GetValue('overrides');
        if (V <> nil) and not (V is TJSONObject) then
          raise EApiError.Create(422, 'overrides deve ser objeto.');
        Settings := TJSONObject(V);
        if Settings <> nil then ValidateSettings(Settings);
        Run('insert into drafts(company_id, customer_id, amount_cents, settings_snapshot,environment) ' +
          'select f.company_id, c.id, :amount, f.settings || cast(:overrides as jsonb),:environment ' +
          'from fiscal_defaults f left join customers c on c.company_id = f.company_id ' +
          'and c.id = cast(nullif(:customer, '''') as uuid) ' +
          'where f.company_id = cast(:company as uuid) ' +
          'and (:customer = '''' or c.id is not null) ' +
          'and length(trim(coalesce((f.settings || cast(:overrides as jsonb))->>''service_code'', ''''))) > 0 ' +
          'and length(trim(coalesce((f.settings || cast(:overrides as jsonb))->>''service_description'', ''''))) > 0 ' +
          'and length(trim(coalesce((f.settings || cast(:overrides as jsonb))->>''tax_regime'', ''''))) > 0 ' +
          'returning jsonb_build_object(''id'', id, ''customer_id'', customer_id, ' +
          '''amount_cents'', amount_cents, ''settings'', settings_snapshot, ''status'', status,''environment'',environment)::text');
        Q.ParamByName('environment').AsWideString:=Environment;
        Q.ParamByName('amount').AsLargeInt := Amount;
        Q.ParamByName('customer').AsWideString := Customer;
        if Settings = nil then Q.ParamByName('overrides').AsWideString := '{}'
        else Q.ParamByName('overrides').AsWideString := Settings.ToJSON;
        Q.Open;
        if Q.IsEmpty then
          raise EApiError.Create(422, 'Cliente nao encontrado ou configuracao de servico/regime incompleta.');
        Response.Content := Q.Fields[0].AsString;
        Response.StatusCode := 201;
      end
      else if (Route = '/v1/drafts') and (Method = 'GET') then
      begin
        Environment:=Request.QueryFields.Values['environment'];
        if (Environment<>'') and (Environment<>'homologacao') and (Environment<>'producao') then raise EApiError.Create(422,'Ambiente invalido.');
        Run('select coalesce(jsonb_agg(to_jsonb(d)), ''[]''::jsonb)::text from ' +
          '(select r.id, r.customer_id, r.amount_cents, r.settings_snapshot as settings, r.status, r.created_at,r.environment, ' +
          'a.id as attempt_id, a.status as attempt_status, a.invoice_id ' +
          'from drafts r left join emission_attempts a on a.company_id=r.company_id and a.draft_id=r.id ' +
          'where r.company_id = cast(:company as uuid) and (:environment='''' or r.environment=:environment) order by r.created_at desc, r.id limit 100) d');
        Q.ParamByName('environment').AsWideString:=Environment;
        ReturnQuery;
      end
      else if (Copy(Route,1,11)='/v1/drafts/') and (Method='POST') then
      begin
        DraftId:=Req.Params['id'];
        try
          Guid:=StringToGUID('{'+DraftId+'}');
        except
          on E:EConvertError do raise EApiError.Create(422,'Rascunho invalido.');
        end;
        Body:=ParseBody(Request);
        IssuedAt:=RequiredString(Body,'issued_at');
        Competence:=RequiredString(Body,'competence');
        if not TRegEx.IsMatch(IssuedAt,'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(Z|[+-]\d{2}:\d{2})$') or
           not TryISO8601ToDate(IssuedAt,ParsedDate,True) then
          raise EApiError.Create(422,'issued_at deve ser data ISO8601 com fuso horario.');
        if not TRegEx.IsMatch(Competence,'^\d{4}-\d{2}-\d{2}$') or
           not TryISO8601ToDate(Competence+'T00:00:00Z',ParsedDate,True) then
          raise EApiError.Create(422,'competence deve ser AAAA-MM-DD.');
        Environment:='homologacao';
        if Route='/v1/drafts/'+DraftId+'/emit-production' then
        begin
          Environment:='producao';
          if not (Body.GetValue('confirm_production') is TJSONTrue) then
            raise EApiError.Create(422,'Confirme explicitamente a emissao com validade fiscal.');
        end;
        Run('select coalesce((select active_environment from company_emission_config where company_id=cast(:company as uuid)),''homologacao'')'); Q.Open;
        if Q.Fields[0].AsString<>Environment then raise EApiError.Create(422,'O ambiente foi definido pelo administrador. Atualize a tela.'); Q.Close;
        Response.Content:=EmitInvoice(Conn,Company,DraftId,IssuedAt,Competence,Environment);
      end
      else if (Copy(Route,1,22)='/v1/emission-attempts/') and (Method='GET') then
      begin
        InvoiceId:=Req.Params['id'];
        try
          Guid:=StringToGUID('{'+InvoiceId+'}');
        except
          on E:EConvertError do raise EApiError.Create(422,'Tentativa invalida.');
        end;
        Run('select (to_jsonb(a)-''signed_dps''-''invoice_xml''-''response_text'')::text from emission_attempts a where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
        Q.ParamByName('id').AsWideString:=InvoiceId;
        Q.Open;
        if Q.IsEmpty then raise EApiError.Create(404,'Tentativa nao encontrada.');
        Response.Content:=Q.Fields[0].AsString;
      end
      else if (Route = '/v1/invoices/import-homologation') and (Method = 'POST') then
      begin
        Body := ParseBody(Request, 1048576);
        V := Body.GetValue('xml');
        if not (V is TJSONString) then raise EApiError.Create(422, 'xml deve ser texto.');
        InvoiceXml := V.Value;
        DraftId := '';
        V := Body.GetValue('draft_id');
        if (V <> nil) and not (V is TJSONNull) then
        begin
          DraftId := RequiredString(Body, 'draft_id');
          try
            Guid := StringToGUID('{' + DraftId + '}');
          except
            on E: EConvertError do raise EApiError.Create(422, 'draft_id deve ser UUID.');
          end;
        end;
        Run('select import_homologation_invoice(cast(:company as uuid), ' +
          'cast(nullif(:draft, '''') as uuid), :xml)::text');
        Q.ParamByName('draft').AsWideString := DraftId;
        Q.ParamByName('xml').AsWideMemo := InvoiceXml;
        ReturnQuery;
      end
      else if (Route = '/v1/invoices') and (Method = 'GET') then
      begin
        StatusFilter:=Request.QueryFields.Values['status'];
        if (StatusFilter<>'') and (StatusFilter<>'authorized') and (StatusFilter<>'cancelled') and (StatusFilter<>'imported') then
          raise EApiError.Create(422,'Situacao invalida.');
        DateFrom:=Request.QueryFields.Values['date_from'];
        DateTo:=Request.QueryFields.Values['date_to'];
        Environment:=Request.QueryFields.Values['environment'];
        if (Environment<>'') and (Environment<>'homologacao') and (Environment<>'producao') then
          raise EApiError.Create(422,'Ambiente invalido.');
        if (DateFrom<>'') and (not TRegEx.IsMatch(DateFrom,'^[0-9]{4}-[0-9]{2}-[0-9]{2}$') or
           not TryISO8601ToDate(DateFrom+'T00:00:00Z',ParsedDate,True)) then
          raise EApiError.Create(422,'Data inicial invalida. Use AAAA-MM-DD.');
        if (DateTo<>'') and (not TRegEx.IsMatch(DateTo,'^[0-9]{4}-[0-9]{2}-[0-9]{2}$') or
           not TryISO8601ToDate(DateTo+'T00:00:00Z',ParsedDate,True)) then
          raise EApiError.Create(422,'Data final invalida. Use AAAA-MM-DD.');
        if (DateFrom<>'') and (DateTo<>'') and (DateFrom>DateTo) then
          raise EApiError.Create(422,'A data inicial deve ser anterior ou igual a data final.');
        Run('select coalesce(jsonb_agg(to_jsonb(i)), ''[]''::jsonb)::text from ' +
          '(select i.id, i.draft_id, i.environment, i.access_key, i.invoice_number, i.issuer_document, ' +
          'i.amount_cents, i.status, i.source, i.imported_at, i.issued_at, '+
          '(select a.status from cancellation_attempts a where a.invoice_id=i.id and a.company_id=i.company_id order by a.created_at desc,a.id desc limit 1) as cancellation_status, '+
          'coalesce(nullif(x.customer_name,''''),c.name) as customer_name '+
          'from invoices i left join drafts d on d.id=i.draft_id and d.company_id=i.company_id '+
          'left join customers c on c.id=d.customer_id and c.company_id=i.company_id ' +
          'left join XMLTABLE(XMLNAMESPACES(''http://www.sped.fazenda.gov.br/nfse'' AS n),''/n:NFSe/n:infNFSe'' '+
          'PASSING xmlparse(document i.xml_content) COLUMNS customer_name text PATH ''n:DPS/n:infDPS/n:toma/n:xNome'') x on true '+
          'where i.company_id=cast(:company as uuid) '+
          'and (:status='''' or i.status=:status or (:status=''authorized'' and i.status in (''authorized_homologation'',''authorized_production''))) '+
          'and (:environment='''' or i.environment=:environment) '+
          'and (:date_from='''' or issued_at >= (cast(nullif(:date_from,'''') as date)::timestamp at time zone ''America/Sao_Paulo'')) '+
          'and (:date_to='''' or issued_at < ((cast(nullif(:date_to,'''') as date)+1)::timestamp at time zone ''America/Sao_Paulo'')) '+
          'order by i.issued_at desc, i.id limit 100) i');
        Q.ParamByName('status').AsWideString:=StatusFilter;
        Q.ParamByName('date_from').AsWideString:=DateFrom;
        Q.ParamByName('date_to').AsWideString:=DateTo;
        Q.ParamByName('environment').AsWideString:=Environment;
        ReturnQuery;
      end
      else if (Copy(Route,1,13)='/v1/invoices/') and (Method='POST') then
      begin
        InvoiceId:=Req.Params['id'];
        try Guid:=StringToGUID('{'+InvoiceId+'}');
        except on E:EConvertError do raise EApiError.Create(422,'Identificador da nota invalido.'); end;
        Body:=ParseBody(Request);
        if not (Body.GetValue('confirm_cancellation') is TJSONTrue) then raise EApiError.Create(422,'Confirme explicitamente o cancelamento.');
        Customer:=RequiredString(Body,'reason_code');
        if (Customer<>'1') and (Customer<>'2') and (Customer<>'9') then raise EApiError.Create(422,'Motivo invalido.');
        Response.Content:=CancelInvoice(Conn,Company,InvoiceId,RequiredString(Body,'reason'),StrToInt(Customer));
      end
      else if (Copy(Route, 1, 13) = '/v1/invoices/') and (Method = 'GET') then
      begin
        InvoiceId := Req.Params['id'];
        try
          Guid := StringToGUID('{' + InvoiceId + '}');
        except
          on E: EConvertError do raise EApiError.Create(422, 'Identificador da nota invalido.');
        end;
        if (Route='/v1/invoices/'+InvoiceId+'/cancellation') or (Route='/v1/invoices/'+InvoiceId+'/cancellation/xml') then
        begin
          Run('select (to_jsonb(a)-''event_xml'')::text,event_xml from cancellation_attempts a where company_id=cast(:company as uuid) and invoice_id=cast(:id as uuid) order by created_at desc,id desc limit 1');
          Q.ParamByName('id').AsWideString:=InvoiceId; Q.Open;
          if Q.IsEmpty then raise EApiError.Create(404,'Nenhuma tentativa de cancelamento.');
          if Route='/v1/invoices/'+InvoiceId+'/cancellation/xml' then
          begin
            if Q.Fields[1].IsNull then raise EApiError.Create(404,'Evento confirmado indisponivel.');
            Response.ContentType:='application/xml; charset=utf-8'; Response.Content:=Q.Fields[1].AsString;
            Response.SetCustomHeader('Content-Disposition','attachment; filename="cancelamento-'+InvoiceId+'.xml"');
          end
          else Response.Content:=Q.Fields[0].AsString;
          Exit;
        end;
        if Route = '/v1/invoices/' + InvoiceId + '/pdf' then
        begin
          Run('select id,environment,status from invoices where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
          Q.ParamByName('id').AsWideString := InvoiceId;
          Q.Open;
          if Q.IsEmpty then raise EApiError.Create(404,'Nota nao encontrada.');
          if Q.FieldByName('status').AsString='cancelled' then raise EApiError.Create(422,'Nota cancelada. Consulte o evento de cancelamento.');
          Environment:=Q.FieldByName('environment').AsString;
          Q.Close;
          try
            PdfBytes := DownloadDanfse(Conn,Company,InvoiceId);
          except
            on E:EEmissionError do raise EApiError.Create(502,E.Message);
          end;
          Response.ContentType := 'application/pdf';
          Response.SetCustomHeader('Content-Disposition','attachment; filename="danfse-'+Environment+'-'+InvoiceId+'.pdf"');
          Response.SetCustomHeader('X-Content-Type-Options','nosniff');
          Response.ContentStream := TBytesStream.Create(PdfBytes);
          Response.FreeContentStream := True;
          Exit;
        end;
        Run('select to_jsonb(i)::text from (select id, draft_id, environment, access_key, ' +
          'invoice_number, issuer_document, amount_cents, status, source, xml_sha256, imported_at ' +
          'from invoices where id=cast(:id as uuid) and company_id=cast(:company as uuid)) i');
        if Route = '/v1/invoices/' + InvoiceId + '/xml' then
          Run('select xml_content from invoices where id=cast(:id as uuid) and company_id=cast(:company as uuid)');
        Q.ParamByName('id').AsWideString := InvoiceId;
        Q.Open;
        if Q.IsEmpty then raise EApiError.Create(404, 'Nota nao encontrada.');
        Response.Content := Q.Fields[0].AsString;
        if Route = '/v1/invoices/' + InvoiceId + '/xml' then
          Response.ContentType := 'application/xml; charset=utf-8';
      end
      else raise EApiError.Create(404, 'Rota ou metodo nao encontrado.');
    except
      on E:EEmissionError do
      begin
        Response.StatusCode:=422;
        with TJSONObject.Create do
        try
          AddPair('error',E.Message);
          Response.Content:=ToJSON;
        finally
          Free;
        end;
      end;
      on E: EApiError do
      begin
        Response.StatusCode := E.Status;
        with TJSONObject.Create do
        try
          AddPair('error', E.Message);
          Response.Content := ToJSON;
        finally
          Free;
        end;
      end;
      on E: EFDDBEngineException do
      begin
        if (E.ErrorCount > 0) and (E.Errors[0] is TFDPgError) and
           (TFDPgError(E.Errors[0]).ErrorCode = '22023') then
        begin
          Response.StatusCode := 422;
          Response.Content := '{"error":"XML, ambiente, CNPJ ou rascunho invalido para esta empresa."}';
        end
        else if E.Kind = ekUKViolated then
        begin
          Response.StatusCode := 409;
          Response.Content := '{"error":"Cadastro ja existente."}';
        end
        else
        begin
          Response.StatusCode := 503;
          Response.Content := '{"error":"Falha de acesso ao banco de dados."}';
        end;
      end;
      on E: Exception do
      begin
        Response.StatusCode := 500;
        Response.Content := '{"error":"Falha interna."}';
      end;
    end;
  finally
    Body.Free;
    Q.Free;
    Conn.Free;
  end;
end;

end.
