program DpsNt009Probe;
{$APPTYPE CONSOLE}
uses
  System.SysUtils, System.IOUtils,
  PadraoNacional.GravarXml in '..\vendor\acbr-compat\PadraoNacional.GravarXml.pas',
  ACBrNFSeX, ACBrDFe.Conversao, ACBrNFSeXConversao, ACBrNFSeXNotasFiscais;
var NFSe: TACBrNFSeX; Note: TNotaFiscal; Xml: string;
begin
  try
    if ParamCount<>1 then raise Exception.Create('Informe diretorio local de saida.');
    NFSe:=TACBrNFSeX.Create(nil);
    try
      NFSe.Configuracoes.Geral.LayoutNFSe:=lnfsPadraoNacionalv101;
      NFSe.Configuracoes.WebServices.Ambiente:=taHomologacao;
      NFSe.Configuracoes.Geral.CodigoMunicipio:=3136702;
      NFSe.SetProvedor(proPadraoNacional,ve101);
      Note:=NFSe.NotasFiscais.New;
      with Note.NFSe do
      begin
        Numero:='1'; IdentificacaoRps.Numero:='1'; IdentificacaoRps.Serie:='999';
        verAplic:='VEEV-API-1.0'; DataEmissao:=Now; DataEmissaoRPS:=Now; Competencia:=Date;
        cLocEmi:='3136702'; tpEmit:=tePrestador;
        IBSCBS.finNFSe:=fnfsRegular;
        RegimeEspecialTributacao:=retNenhum; OptanteSN:=osnOptanteMEEPP;
        RegimeApuracaoSN:=raFederaisMunicipalpeloSN;
        Prestador.IdentificacaoPrestador.CpfCnpj:='11111111000191';
        Prestador.RazaoSocial:='EMPRESA FICTICIA DE TESTE'; Prestador.cUF:=31;
        Prestador.Endereco.CodigoMunicipio:='3136702'; Prestador.Endereco.UF:='MG';
        Servico.ItemListaServico:='090103'; Servico.CodigoTributacaoMunicipio:='002';
        Servico.CodigoNBS:='103031100'; Servico.CodigoMunicipio:='3136702';
        Servico.CodigoInterContr:='TESTELOCAL';
        Servico.Discriminacao:='ENSAIO LOCAL SEM TRANSMISSAO';
        Servico.Valores.ValorServicos:=100;
        Servico.Valores.tribMun.tribISSQN:=tiOperacaoTributavel;
        Servico.Valores.tribMun.tpRetISSQN:=trNaoRetido;
        Servico.Valores.totTrib.pTotTribSN:=13.46;
      end;
      ForceDirectories(ParamStr(1));
      Xml:=Note.GerarXML;
      if Xml='' then Xml:=Note.XmlRps;
      if Pos('<finNFSe>0</finNFSe><cLocEmi>',Xml)=0 then
        raise Exception.Create('finNFSe ausente ou fora de ordem.');
      TFile.WriteAllText(TPath.Combine(ParamStr(1),'dps-sem-tomador.xml'),Xml,TEncoding.UTF8);
      Note.NFSe.Tomador.IdentificacaoTomador.CpfCnpj:='11144477735';
      Note.NFSe.Tomador.RazaoSocial:='TOMADOR FICTICIO';
      Xml:=Note.GerarXML;
      if Xml='' then Xml:=Note.XmlRps;
      TFile.WriteAllText(TPath.Combine(ParamStr(1),'dps-com-tomador.xml'),Xml,TEncoding.UTF8);
      Note.NFSe.IBSCBS.cIndOp := '030101';
      Note.NFSe.IBSCBS.valores.trib.gIBSCBS.CST := cst200;
      Note.NFSe.IBSCBS.valores.trib.gIBSCBS.cClassTrib := '200048';
      Xml:=Note.GerarXML;
      if Xml='' then Xml:=Note.XmlRps;
      TFile.WriteAllText(TPath.Combine(ParamStr(1),'dps-ibs-cbs.xml'),Xml,TEncoding.UTF8);
      Note.NFSe.IBSCBS.valores.trib.gIBSCBS.CST := cstNenhum;
      Xml:=Note.GerarXML;
      if Xml='' then Xml:=Note.XmlRps;
      if Pos('<IBSCBS>',Xml)>0 then raise Exception.Create('Grupo IBS/CBS nao desativado.');
      NFSe.Configuracoes.WebServices.Ambiente:=taProducao;
      TFile.WriteAllText(TPath.Combine(ParamStr(1),'servicos.ini'),'[PadraoNacional]'+sLineBreak+
        'Versao=1.01'+sLineBreak+'ProGerarNFSe=https://sefin.nfse.gov.br/SefinNacional'+sLineBreak,TEncoding.ASCII);
      NFSe.Configuracoes.Arquivos.IniServicos:=TPath.Combine(ParamStr(1),'servicos.ini');
      NFSe.Configuracoes.WebServices.LerParams;
      NFSe.SetProvedor(proPadraoNacional,ve101);
      if NFSe.Provider.ConfigWebServices.Producao.GerarNFSe<>'https://sefin.nfse.gov.br/SefinNacional' then
        raise Exception.Create('Endpoint de producao incorreto.');
      Xml:=Note.GerarXML;
      if Pos('<tpAmb>1</tpAmb>',Xml)=0 then raise Exception.Create('DPS de producao sem tpAmb=1.');
      TFile.WriteAllText(TPath.Combine(ParamStr(1),'dps-producao.xml'),Xml,TEncoding.UTF8);
      Note.NFSe.IBSCBS.valores.trib.gIBSCBS.CST:=cst200;
      Xml:=Note.GerarXML;
      TFile.WriteAllText(TPath.Combine(ParamStr(1),'dps-producao-ibs.xml'),Xml,TEncoding.UTF8);
      Writeln('OK: geracao e regeneracao com finNFSe=0; sem certificado e sem transmissao.');
    finally NFSe.Free; end;
  except on E:Exception do begin Writeln(E.ClassName,': ',E.Message); ExitCode:=1; end; end;
end.
