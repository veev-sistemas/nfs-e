unit Nfse.Db;

interface

uses
  System.SysUtils, FireDAC.Comp.Client, FireDAC.Stan.Intf,
  FireDAC.Stan.Def, FireDAC.Stan.Async, FireDAC.Stan.Pool,
  FireDAC.Phys, FireDAC.Phys.PG, FireDAC.Phys.PGDef,
  FireDAC.DApt, FireDAC.UI.Intf, FireDAC.ConsoleUI.Wait;

function OpenDatabase: TFDConnection;
function RequiredEnv(const Name: string): string;

implementation

function RequiredEnv(const Name: string): string;
begin
  Result := GetEnvironmentVariable(Name);
  if Result = '' then
    raise Exception.Create('Variavel obrigatoria ausente: ' + Name);
end;

function OpenDatabase: TFDConnection;
begin
  Result := TFDConnection.Create(nil);
  try
    Result.LoginPrompt := False;
    Result.Params.Values['DriverID'] := 'PG';
    Result.Params.Values['Server'] := RequiredEnv('NFSE_DB_HOST');
    Result.Params.Values['Port'] := GetEnvironmentVariable('NFSE_DB_PORT');
    if Result.Params.Values['Port'] = '' then
      Result.Params.Values['Port'] := '5432';
    Result.Params.Values['Database'] := RequiredEnv('NFSE_DB_NAME');
    Result.Params.Values['User_Name'] := RequiredEnv('NFSE_DB_USER');
    Result.Params.Values['Password'] := RequiredEnv('NFSE_DB_PASSWORD');
    Result.Params.Values['CharacterSet'] := 'utf8';
    Result.Connected := True;
  except
    Result.Free;
    raise;
  end;
end;

end.
