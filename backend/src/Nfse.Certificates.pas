unit Nfse.Certificates;

interface

uses System.SysUtils, System.JSON;

type ECertificateError = class(Exception);

function CertificateOperation(const Company, Document, Operation: string;
  Input: TJSONObject; out WorkDir: string): TJSONObject;
procedure ClearCertificateWork(const WorkDir: string);

implementation

uses System.IOUtils
  {$IFDEF LINUX}, Posix.Unistd, Posix.SysWait, Posix.Errno, Posix.SysStat{$ENDIF};

{$IFDEF LINUX}
function SpawnCertificate(var PID: Integer; Path: MarshaledAString; Actions, Attrs: Pointer;
  Argv, Envp: PMarshaledAString): Integer; cdecl; external 'libc.so.6' name 'posix_spawn';
{$ENDIF}

procedure ClearCertificateWork(const WorkDir: string);
begin
  if (WorkDir<>'') and TDirectory.Exists(WorkDir) then TDirectory.Delete(WorkDir,True);
end;

function CertificateOperation(const Company, Document, Operation: string;
  Input: TJSONObject; out WorkDir: string): TJSONObject;
var
  Unique: TGUID;
  DataRoot, Helper: string;
  Request: TJSONObject;
  {$IFDEF LINUX}
  ArgText: array[0..4] of UTF8String;
  Args: array[0..5] of MarshaledAString;
  Child, ExitStatus, Waited, I: Integer;
  {$ENDIF}
begin
  Result:=nil; WorkDir:='';
  {$IFNDEF LINUX}
  raise ECertificateError.Create('Gestao de certificados disponivel no servidor Linux.');
  {$ENDIF}
  DataRoot:=GetEnvironmentVariable('NFSE_DATA_DIR');
  Helper:=GetEnvironmentVariable('NFSE_CERTIFICATE_HELPER');
  if Helper='' then Helper:='/app/manage-certificate.py';
  if (DataRoot='') or not FileExists(Helper) then
    raise ECertificateError.Create('Gestao de certificados nao configurada no servidor.');
  CreateGUID(Unique);
  WorkDir:=TPath.Combine(TPath.Combine(DataRoot,'certificate-requests'),GUIDToString(Unique));
  try
    ForceDirectories(WorkDir);
    {$IFDEF LINUX}
    if chmod(MarshaledAString(UTF8String(WorkDir)),448)<>0 then
      raise ECertificateError.Create('Nao foi possivel proteger o diretorio temporario.');
    {$ENDIF}
    Request:=TJSONObject.Create;
    try
      Request.AddPair('company',Company); Request.AddPair('document',Document);
      Request.AddPair('operation',Operation);
      if Input<>nil then
      begin
        if Input.GetValue('pfx_base64')<>nil then Request.AddPair('pfx_base64',Input.GetValue('pfx_base64').Clone as TJSONValue);
        if Input.GetValue('password')<>nil then Request.AddPair('password',Input.GetValue('password').Clone as TJSONValue);
      end;
      TFile.WriteAllText(TPath.Combine(WorkDir,'request.json'),Request.ToJSON,TEncoding.UTF8);
    finally Request.Free; end;
    {$IFDEF LINUX}
    chmod(MarshaledAString(UTF8String(TPath.Combine(WorkDir,'request.json'))),384);
    ArgText[0]:='/usr/bin/timeout'; ArgText[1]:='20'; ArgText[2]:='/usr/bin/python3';
    ArgText[3]:=UTF8String(Helper); ArgText[4]:=UTF8String(WorkDir);
    for I:=0 to High(ArgText) do Args[I]:=MarshaledAString(ArgText[I]); Args[5]:=nil;
    if SpawnCertificate(Child,MarshaledAString(ArgText[0]),nil,nil,@Args[0],Posix.Unistd.environ)<>0 then
      raise ECertificateError.Create('Nao foi possivel validar o certificado.');
    repeat Waited:=waitpid(Child,@ExitStatus,0); until (Waited<>-1) or (errno<>EINTR);
    if (Waited<>Child) or not WIFEXITED(ExitStatus) or (WEXITSTATUS(ExitStatus)<>0) then
      raise ECertificateError.Create('Validacao do certificado indisponivel ou excedeu o tempo limite.');
    {$ENDIF}
    Result:=TJSONObject.ParseJSONValue(TFile.ReadAllText(TPath.Combine(WorkDir,'result.json'),TEncoding.UTF8)) as TJSONObject;
    if Result=nil then raise ECertificateError.Create('Resposta de certificado invalida.');
    if Result.GetValue('error')<>nil then raise ECertificateError.Create(Result.GetValue('error').Value);
  except
    Result.Free; ClearCertificateWork(WorkDir); WorkDir:=''; raise;
  end;
end;

end.
