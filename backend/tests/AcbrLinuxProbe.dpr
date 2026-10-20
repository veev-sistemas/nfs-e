program AcbrLinuxProbe;

{$APPTYPE CONSOLE}

uses
  System.SysUtils, System.IOUtils,
  ACBrNFSeX, ACBrDFeSSL,
  LocalDps in 'LocalDps.pas',
  Homologacao in 'Homologacao.pas';

var
  NFSe: TACBrNFSeX;
  PfxPath, PfxPassword: string;
begin
  if ParamStr(1) = '--capabilities-query' then
  begin
    Writeln('VEEV_NFSE_CONSULTA_V1');
    Exit;
  end;
  if ParamStr(1) = '--capabilities' then
  begin
    Writeln('VEEV_NFSE_HOMOLOGACAO_V2');
    Exit;
  end;
  try
    NFSe := TACBrNFSeX.Create(nil);
    try
      if ParamStr(1) = '--check-config' then
      begin
        CheckHomologacaoConfig(NFSe, TPath.Combine(TPath.GetTempPath, 'veev-nfse-config-check'));
        Writeln('OK: configuracao conferida sem certificado e sem transmissao.');
        Exit;
      end;
      Writeln('OK: ACBrNFSeX criado neste ambiente.');
      PfxPath := GetEnvironmentVariable('NFSE_TEST_PFX');
      if PfxPath <> '' then
      begin
        if not FileExists(PfxPath) then
          raise Exception.Create('Arquivo PFX nao encontrado no caminho informado.');
        PfxPassword := GetEnvironmentVariable('NFSE_TEST_PFX_PASSWORD');
        if PfxPassword = '' then
          raise Exception.Create('Senha de teste nao informada no ambiente.');
        NFSe.Configuracoes.Geral.SSLCryptLib := cryOpenSSL;
        NFSe.SSL.ArquivoPFX := PfxPath;
        NFSe.SSL.Senha := AnsiString(PfxPassword);
        PfxPassword := '';
        NFSe.SSL.CarregarCertificado;
        Writeln('OK: certificado A1 carregado pelo ACBr/OpenSSL.');
        Writeln('Validade ate: ', FormatDateTime('yyyy-mm-dd', NFSe.SSL.CertDataVenc));
        if NFSe.SSL.CertDataVenc < Now then
          raise Exception.Create('Certificado carregado, mas esta vencido.');
        if GetEnvironmentVariable('NFSE_TEST_QUERY') = '1' then
          QueryHomologacao(NFSe, GetEnvironmentVariable('NFSE_TEST_OUTPUT'),
            GetEnvironmentVariable('NFSE_TEST_ACCESS_KEY'))
        else if GetEnvironmentVariable('NFSE_TEST_DPS') = '1' then
          GenerateLocalDps(NFSe);
      end
      else
        Writeln('Certificado nao testado: NFSE_TEST_PFX nao informado.');
      if GetEnvironmentVariable('NFSE_TEST_SEND') <> 'HOMOLOGACAO' then
        Writeln('Teste de componente: nenhuma nota foi transmitida.');
    finally
      PfxPassword := '';
      NFSe.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(E.ClassName, ': ', E.Message);
      ExitCode := 1;
    end;
  end;
end.
