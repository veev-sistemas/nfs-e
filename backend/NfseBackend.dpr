program NfseBackend;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  PadraoNacional.GravarXml in 'vendor\acbr-compat\PadraoNacional.GravarXml.pas',
  Nfse.Db in 'src\Nfse.Db.pas',
  Nfse.Certificates in 'src\Nfse.Certificates.pas',
  Nfse.Admin in 'src\Nfse.Admin.pas',
  Nfse.Emission in 'src\Nfse.Emission.pas',
  Nfse.Api in 'src\Nfse.Api.pas';

var
  Server: TNfseApi;
begin
  try
    Server := TNfseApi.Create;
    try
      Server.Start;
    finally
      Server.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln('Falha ao iniciar: ', E.Message);
      ExitCode := 1;
      Writeln('Pressione ENTER para fechar.');
      Readln;
    end;
  end;
end.
