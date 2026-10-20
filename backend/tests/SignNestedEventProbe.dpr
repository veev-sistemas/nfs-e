program SignNestedEventProbe;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils,
  ACBrDFeXsLibXml2 in '..\vendor\acbr-compat\ACBrDFeXsLibXml2.pas',
  ACBrNFSeX, ACBrDFeSSL;
var NFSe: TACBrNFSeX; Xml: string;
begin
  try
    if ParamCount<>1 then raise Exception.Create('Diretorio ficticio obrigatorio.');
    Xml:=TFile.ReadAllText(TPath.Combine(ParamStr(1),'event-unsigned.xml'),TEncoding.UTF8);
    NFSe:=TACBrNFSeX.Create(nil);
    try
      NFSe.Configuracoes.Geral.SSLCryptLib:=cryOpenSSL;
      NFSe.Configuracoes.Geral.SSLXmlSignLib:=xsLibXml2;
      NFSe.SSL.ArquivoPFX:=TPath.Combine(ParamStr(1),'inner-test.pfx'); NFSe.SSL.Senha:='Nested-test-2026';
      NFSe.SSL.CarregarCertificado;
      Xml:=NFSe.SSL.Assinar(Xml,'pedRegEvento','infPedReg','','','','Id');
      NFSe.SSL.DescarregarCertificado;
      NFSe.SSL.ArquivoPFX:=TPath.Combine(ParamStr(1),'outer-test.pfx'); NFSe.SSL.Senha:='Nested-test-2026';
      NFSe.SSL.CarregarCertificado;
      Xml:=NFSe.SSL.Assinar(Xml,'evento','infEvento','','','','Id');
      TFile.WriteAllText(TPath.Combine(ParamStr(1),'event-valid.xml'),Xml,TEncoding.UTF8);
      Xml:=StringReplace(Xml,'Servico nao prestado em teste local','Motivo adulterado em teste local',[rfReplaceAll]);
      TFile.WriteAllText(TPath.Combine(ParamStr(1),'event-tampered.xml'),Xml,TEncoding.UTF8);
      Writeln('PASS: evento ficticio assinado com dois certificados de teste, sem rede.');
    finally NFSe.Free; end;
  except on E:Exception do begin Writeln(E.Message); Halt(1); end; end;
end.
