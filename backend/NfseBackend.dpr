program NfseBackend;

{$APPTYPE CONSOLE}

uses
  System.SysUtils,
  FireDAC.Comp.Client,
  ACBrDFeXsLibXml2 in 'vendor\acbr-compat\ACBrDFeXsLibXml2.pas',
  PadraoNacional.GravarXml in 'vendor\acbr-compat\PadraoNacional.GravarXml.pas',
  Nfse.Db in 'src\Nfse.Db.pas',
  Nfse.Certificates in 'src\Nfse.Certificates.pas',
  Nfse.Admin in 'src\Nfse.Admin.pas',
  Nfse.Emission in 'src\Nfse.Emission.pas',
  Nfse.Api in 'src\Nfse.Api.pas';

var
  Server: TNfseApi;
  Conn: TFDConnection;
  Guid: TGUID;
begin
  try
    if ParamCount>0 then
    begin
      if (ParamCount<>3) or (ParamStr(1)<>'--reconcile-saved-cancellation') then
        raise Exception.Create('Argumentos administrativos invalidos.');
      Guid:=StringToGUID('{'+ParamStr(2)+'}'); Guid:=StringToGUID('{'+ParamStr(3)+'}');
      Conn:=OpenDatabase;
      try ReconcileSavedCancellation(Conn,ParamStr(2),ParamStr(3)); finally Conn.Free; end;
      Writeln('Evento salvo verificado, sem transmissao fiscal. Consulte o estado da tentativa.');
      Exit;
    end;
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
