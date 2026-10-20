program VerifyEventProbe;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils,
  ACBrDFeXsLibXml2 in '..\vendor\acbr-compat\ACBrDFeXsLibXml2.pas',
  ACBrNFSeX, ACBrDFeSSL;
var NFSe: TACBrNFSeX; Xml, ErrorText: string;
begin
  try
    if ParamCount<>2 then raise Exception.Create('Informe XML e schema.');
    Xml:=TFile.ReadAllText(ParamStr(1),TEncoding.UTF8);
    NFSe:=TACBrNFSeX.Create(nil);
    try
      NFSe.Configuracoes.Geral.SSLCryptLib:=cryOpenSSL;
      NFSe.Configuracoes.Geral.SSLXmlSignLib:=xsLibXml2;
      if not NFSe.SSL.Validar(Xml,ParamStr(2),ErrorText) then raise Exception.Create('SCHEMA: '+ErrorText);
      if not NFSe.SSL.VerificarAssinatura(Xml,ErrorText,'infEvento','','','','Id') then raise Exception.Create('OUTER: '+ErrorText);
      if not NFSe.SSL.VerificarAssinatura(Xml,ErrorText,'infPedReg','','','','Id') then raise Exception.Create('INNER: '+ErrorText);
      Writeln('PASS: schema e ambas as assinaturas validas. Sem rede.');
    finally NFSe.Free; end;
  except on E:Exception do begin Writeln(E.Message); Halt(1); end; end;
end.
