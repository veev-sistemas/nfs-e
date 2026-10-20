unit Nfse.Admin;

interface

uses Web.HTTPApp;

procedure HandleAdmin(Request: TWebRequest; Response: TWebResponse);

implementation

uses System.SysUtils, System.JSON, System.RegularExpressions, Data.DB,
  FireDAC.Comp.Client, FireDAC.Stan.Error, FireDAC.Stan.Param, Nfse.Db, Nfse.Certificates;

type
  EAdminError = class(Exception)
    Status: Integer;
    constructor Create(Code: Integer; const Msg: string);
  end;

constructor EAdminError.Create(Code: Integer; const Msg: string);
begin inherited Create(Msg); Status:=Code; end;

function ReadText(Body: TJSONObject; const Key: string; Max: Integer = 500): string;
var V: TJSONValue;
begin
  V:=Body.GetValue(Key);
  if not (V is TJSONString) or (V is TJSONNumber) then
    raise EAdminError.Create(422,Key+' deve ser texto.');
  Result:=Trim(V.Value);
  if (Result='') or (Length(Result)>Max) then raise EAdminError.Create(422,Key+' invalido.');
end;

function ReadPassword(Body: TJSONObject): string;
var V: TJSONValue;
begin
  V:=Body.GetValue('password');
  if not (V is TJSONString) or (V is TJSONNumber) then
    raise EAdminError.Create(422,'Senha obrigatoria.');
  Result:=V.Value;
  if (TEncoding.UTF8.GetByteCount(Result)<12) or (TEncoding.UTF8.GetByteCount(Result)>72) then
    raise EAdminError.Create(422,'Senha deve ter de 12 a 72 bytes.');
end;

procedure HandleAdmin(Request: TWebRequest; Response: TWebResponse);
var
  Conn: TFDConnection;
  Q: TFDQuery;
  Body, Profile: TJSONObject;
  Value, Parsed: TJSONValue;
  Route, Method, Token, AdminId, CompanyId, Name, Document, Password, Field, Action: string;
  Environment, Series, NextNumber, Expected: string;
  CertificateWork: string;
  CertificateResult: TJSONObject;
  Parts: TArray<string>;
  Enabled: Boolean;
  Guid: TGUID;

  procedure SQL(const Statement: string);
  begin
    Q.Close; Q.SQL.Text:=Statement;
    if Q.Params.FindParam('admin')<>nil then Q.ParamByName('admin').AsWideString:=AdminId;
    if Q.Params.FindParam('company')<>nil then Q.ParamByName('company').AsWideString:=CompanyId;
  end;

  procedure Error(Code: Integer; const Message: string);
  var Json: TJSONObject;
  begin
    Response.StatusCode:=Code; Json:=TJSONObject.Create;
    try Json.AddPair('error',Message); Response.Content:=Json.ToJSON; finally Json.Free; end;
  end;

  procedure ReadBody(MaxSize: Integer = 16384);
  begin
    if (Request.Content='') or (Request.ContentLength>MaxSize) or (TEncoding.UTF8.GetByteCount(Request.Content)>MaxSize) then
      raise EAdminError.Create(400,'Corpo JSON obrigatorio ou limite excedido.');
    Parsed:=TJSONObject.ParseJSONValue(Request.Content);
    if not (Parsed is TJSONObject) then begin Parsed.Free; raise EAdminError.Create(400,'Objeto JSON obrigatorio.'); end;
    Body:=TJSONObject(Parsed);
  end;

  procedure Audit(const Event: string);
  begin
    SQL('insert into admin_audit(admin_id,company_id,action) values(cast(:admin as uuid),cast(nullif(:company,'''') as uuid),:action)');
    Q.ParamByName('action').AsWideString:=Event; Q.ExecSQL;
  end;

begin
  Conn:=nil; Q:=nil; Body:=nil; AdminId:=''; CompanyId:=''; Enabled:=False;
  Route:=Request.PathInfo; Method:=UpperCase(Request.Method);
  try
    try
      Conn:=OpenDatabase; Q:=TFDQuery.Create(nil); Q.Connection:=Conn;
      if (Route='/v1/admin/auth/login') and (Method='POST') then
      begin
        ReadBody;
        Name:=LowerCase(ReadText(Body,'username',100));
        Password:=ReadPassword(Body);
        SQL('select login_admin(:username,:password)::text');
        Q.ParamByName('username').AsWideString:=Name;
        Q.ParamByName('password').AsWideString:=Password;
        Q.Open; Response.Content:=Q.Fields[0].AsString;
        if Pos('"error"',Response.Content)>0 then Response.StatusCode:=401;
        Exit;
      end;
      Token:=Request.GetFieldByName('Authorization');
      if Copy(Token,1,7)<>'Bearer ' then raise EAdminError.Create(401,'Acesso administrativo obrigatorio.');
      Token:=Copy(Token,8,MaxInt);
      if Copy(Token,1,6)<>'admin_' then raise EAdminError.Create(403,'Este acesso nao e de administrador.');
      if Length(Token)<>70 then raise EAdminError.Create(401,'Sessao administrativa invalida.');
      SQL('select a.id::text,a.username from admin_sessions s join admin_users a on a.id=s.admin_id '+
        'where a.enabled and s.expires_at>now() and s.token_hash=encode(digest(:token,''sha256''),''hex'')');
      Q.ParamByName('token').AsWideString:=Token; Q.Open;
      if Q.IsEmpty then raise EAdminError.Create(401,'Sessao administrativa expirada ou invalida.');
      AdminId:=Q.Fields[0].AsString; Name:=Q.Fields[1].AsString; Q.Close;

      if (Route='/v1/admin/auth/me') and (Method='GET') then
      begin
        Body:=TJSONObject.Create; Body.AddPair('username',Name); Response.Content:=Body.ToJSON;
      end
      else if (Route='/v1/admin/auth/logout') and (Method='POST') then
      begin
        SQL('delete from admin_sessions where token_hash=encode(digest(:token,''sha256''),''hex'')');
        Q.ParamByName('token').AsWideString:=Token; Q.ExecSQL;
        Response.Content:='{"status":"ok"}';
      end
      else if (Route='/v1/admin/companies') and (Method='GET') then
      begin
        SQL('select coalesce(jsonb_agg(to_jsonb(c)),''[]''::jsonb)::text from '+
          '(select c.id,c.name,c.document,c.access_enabled,c.created_at,'+
          'exists(select 1 from company_users u where u.company_id=c.id) as has_password,'+
          'exists(select 1 from fiscal_profiles f where f.company_id=c.id) as has_fiscal_profile '+
          'from companies c order by c.created_at desc,c.id limit 1000) c');
        Q.Open; Response.Content:=Q.Fields[0].AsString;
      end
      else if (Route='/v1/admin/companies') and (Method='POST') then
      begin
        ReadBody; Name:=ReadText(Body,'name');
        Document:=TRegEx.Replace(ReadText(Body,'cnpj'),'[./\-\s]','');
        if not TRegEx.IsMatch(Document,'^[0-9]{14}$') then raise EAdminError.Create(422,'CNPJ deve ter 14 digitos.');
        Password:=ReadPassword(Body);
        Value:=Body.GetValue('fiscal_profile'); Profile:=nil;
        if (Value<>nil) and not (Value is TJSONNull) then
        begin
          if not (Value is TJSONObject) then raise EAdminError.Create(422,'Perfil fiscal deve ser objeto.');
          Profile:=TJSONObject(Value);
          for Field in TArray<string>.Create('municipality_code','municipality_name','state_code','street','house_number','district','postal_code','homologation_series') do
            ReadText(Profile,Field,255);
          if not TRegEx.IsMatch(ReadText(Profile,'municipality_code'),'^[0-9]{7}$') or
             not TRegEx.IsMatch(ReadText(Profile,'postal_code'),'^[0-9]{8}$') or
             not TRegEx.IsMatch(ReadText(Profile,'state_code'),'^[A-Z]{2}$') or
             not TRegEx.IsMatch(ReadText(Profile,'homologation_series'),'^[0-9]{1,5}$') then
            raise EAdminError.Create(422,'Municipio, UF, CEP ou serie invalido.');
        end;
        Conn.StartTransaction;
        SQL('insert into companies(name,document) values(:name,:document) returning id::text');
        Q.ParamByName('name').AsWideString:=Name; Q.ParamByName('document').AsWideString:=Document;
        Q.Open; CompanyId:=Q.Fields[0].AsString; Q.Close;
        SQL('select set_company_password(cast(:company as uuid),:password)');
        Q.ParamByName('password').AsWideString:=Password; Q.Open; Q.Close;
        SQL('insert into fiscal_defaults(company_id) values(cast(:company as uuid))'); Q.ExecSQL;
        if Profile<>nil then
        begin
          SQL('insert into fiscal_profiles(company_id,municipality_code,municipality_name,state_code,street,house_number,district,postal_code,homologation_series,municipal_registration) '+
            'values(cast(:company as uuid),:municipality_code,:municipality_name,:state_code,:street,:house_number,:district,:postal_code,:homologation_series,:municipal_registration)');
          for Field in TArray<string>.Create('municipality_code','municipality_name','state_code','street','house_number','district','postal_code','homologation_series') do
            Q.ParamByName(Field).AsWideString:=ReadText(Profile,Field,255);
          Value:=Profile.GetValue('municipal_registration');
          if (Value=nil) or (Value is TJSONNull) then
          begin
            Q.ParamByName('municipal_registration').DataType:=ftWideString;
            Q.ParamByName('municipal_registration').Clear;
          end
          else Q.ParamByName('municipal_registration').AsWideString:=ReadText(Profile,'municipal_registration',100);
          Q.ExecSQL;
        end;
        Audit('company_created');
        Conn.Commit;
        SQL('select jsonb_build_object(''id'',id,''name'',name,''document'',document,''access_enabled'',access_enabled)::text from companies where id=cast(:company as uuid)');
        Q.Open; Response.Content:=Q.Fields[0].AsString; Response.StatusCode:=201;
      end
      else if Copy(Route,1,20)='/v1/admin/companies/' then
      begin
        Parts:=Route.Split(['/']);
        if Length(Parts)<>6 then raise EAdminError.Create(404,'Rota administrativa inexistente.');
        CompanyId:=Parts[4]; Action:=Parts[5];
        try Guid:=StringToGUID('{'+CompanyId+'}');
        except on E:EConvertError do raise EAdminError.Create(422,'Empresa invalida.'); end;
        if (Action='certificate') and ((Method='GET') or (Method='POST')) then
        begin
          SQL('select document from companies where id=cast(:company as uuid)'); Q.Open;
          if Q.IsEmpty then raise EAdminError.Create(404,'Empresa nao encontrada.');
          Document:=Q.Fields[0].AsString; Q.Close;
          if Method='POST' then
          begin
            ReadBody(720000);
            ReadText(Body,'pfx_base64',700000);
            Value:=Body.GetValue('password');
            if not (Value is TJSONString) or (Value is TJSONNumber) or (Length(Value.Value)>1024) then
              raise EAdminError.Create(422,'Senha do certificado deve ser texto.');
            // Serialize replacements for this company; emission uses an isolated snapshot.
            Conn.StartTransaction;
            SQL('select id from companies where id=cast(:company as uuid) for update'); Q.Open; Q.Close;
            Action:='install';
          end
          else Action:='status';
          CertificateWork:=''; CertificateResult:=nil;
          try
            CertificateResult:=CertificateOperation(CompanyId,Document,Action,Body,CertificateWork);
            if Method='POST' then begin Audit('company_certificate_uploaded'); Conn.Commit; end;
            Response.Content:=CertificateResult.ToJSON;
          finally CertificateResult.Free; ClearCertificateWork(CertificateWork); end;
          Exit;
        end;
        if (Action='numbering') and (Method='GET') then
        begin
          SQL('select jsonb_build_object(''homologation_series'',f.homologation_series,''sequences'',coalesce('+
            '(select jsonb_agg(jsonb_build_object(''environment'',s.environment,''series'',s.series,''next_number'',s.next_number::text) order by s.environment,s.series) '+
            'from dps_sequences s where s.company_id=c.id),''[]''::jsonb))::text '+
            'from companies c left join fiscal_profiles f on f.company_id=c.id where c.id=cast(:company as uuid)');
          Q.Open;
          if Q.IsEmpty then raise EAdminError.Create(404,'Empresa nao encontrada.');
          Response.Content:=Q.Fields[0].AsString; Exit;
        end;
        if (Action='numbering') and (Method='PATCH') then
        begin
          ReadBody;
          Environment:=ReadText(Body,'environment',20); Series:=ReadText(Body,'series',5);
          NextNumber:=ReadText(Body,'next_number',15);
          if ((Environment<>'homologacao') and (Environment<>'producao')) or
            not TRegEx.IsMatch(Series,'^(0|[1-9][0-9]{0,4})$') or
            not TRegEx.IsMatch(NextNumber,'^[1-9][0-9]{0,14}$') then
            raise EAdminError.Create(422,'Ambiente, serie ou proximo numero invalido.');
          Expected:=''; Value:=Body.GetValue('expected_next_number');
          if (Value=nil) then raise EAdminError.Create(422,'Atualize a numeracao antes de salvar.');
          if not (Value is TJSONNull) then Expected:=ReadText(Body,'expected_next_number',15);
          Conn.StartTransaction;
          SQL('select company_id from fiscal_profiles where company_id=cast(:company as uuid) for update'); Q.Open;
          if Q.IsEmpty then raise EAdminError.Create(422,'Cadastre primeiro o perfil fiscal da empresa.'); Q.Close;
          SQL('select next_number::text from dps_sequences where company_id=cast(:company as uuid) and environment=:environment and series=:series for update');
          Q.ParamByName('environment').AsWideString:=Environment; Q.ParamByName('series').AsWideString:=Series; Q.Open;
          if (Q.IsEmpty and (Expected<>'')) or (not Q.IsEmpty and (Q.Fields[0].AsString<>Expected)) then
            raise EAdminError.Create(409,'A numeracao mudou. Atualize antes de salvar.');
          if not Q.IsEmpty then
            if StrToInt64(NextNumber)<StrToInt64(Q.Fields[0].AsString) then
              raise EAdminError.Create(409,'Nao e permitido voltar a numeracao.');
          Q.Close;
          SQL('insert into dps_sequences(company_id,environment,series,next_number) values(cast(:company as uuid),:environment,:series,cast(:number as bigint)) '+
            'on conflict(company_id,environment,series) do update set next_number=excluded.next_number');
          Q.ParamByName('environment').AsWideString:=Environment; Q.ParamByName('series').AsWideString:=Series;
          Q.ParamByName('number').AsWideString:=NextNumber; Q.ExecSQL;
          if Environment='homologacao' then
          begin
            SQL('update fiscal_profiles set homologation_series=:series,next_homologation_number=cast(:number as bigint) where company_id=cast(:company as uuid)');
            Q.ParamByName('series').AsWideString:=Series; Q.ParamByName('number').AsWideString:=NextNumber; Q.ExecSQL;
          end;
          Audit('dps_sequence_configured_'+Environment+'_'+Series+'_'+NextNumber);
          Conn.Commit; Response.Content:='{"status":"ok"}'; Exit;
        end;
        if not (((Action='access') and (Method='PATCH')) or ((Action='password') and (Method='POST'))) then
          raise EAdminError.Create(405,'Operacao administrativa invalida.');
        ReadBody;
        if Action='access' then
        begin
          Value:=Body.GetValue('enabled');
          if not (Value is TJSONBool) then raise EAdminError.Create(422,'enabled deve ser booleano.');
          Enabled:=TJSONBool(Value).AsBoolean;
        end
        else Password:=ReadPassword(Body);
        Conn.StartTransaction;
        SQL('select id from companies where id=cast(:company as uuid) for update'); Q.Open;
        if Q.IsEmpty then raise EAdminError.Create(404,'Empresa nao encontrada.'); Q.Close;
        if Action='access' then
        begin
          SQL('select set_company_access(cast(:company as uuid),:enabled)');
          Q.ParamByName('enabled').AsBoolean:=Enabled; Q.Open; Q.Close;
          if Enabled then Audit('company_unblocked') else Audit('company_blocked');
        end
        else
        begin
          SQL('select set_company_password(cast(:company as uuid),:password)');
          Q.ParamByName('password').AsWideString:=Password; Q.Open; Q.Close; Audit('company_password_reset');
        end;
        Conn.Commit; Response.Content:='{"status":"ok"}';
      end
      else raise EAdminError.Create(404,'Rota administrativa inexistente.');
    except
      on E:EAdminError do Error(E.Status,E.Message);
      on E:ECertificateError do Error(422,E.Message);
      on E:EFDDBEngineException do
        if E.Kind=ekUKViolated then Error(409,'Ja existe uma empresa com este CNPJ.')
        else Error(503,'Falha no cadastro administrativo. Confira a migracao e o banco.');
      on E:Exception do
      begin
        Writeln('Falha administrativa: '+E.ClassName);
        Error(500,'Falha interna no acesso administrativo.');
      end;
    end;
  finally
    if (Conn<>nil) and Conn.InTransaction then Conn.Rollback;
    Password:=''; Body.Free; Q.Free; Conn.Free;
  end;
end;

end.
