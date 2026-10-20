unit LocalDps;

interface

uses ACBrNFSeX;

procedure GenerateLocalDps(NFSe: TACBrNFSeX);

implementation

uses
  System.SysUtils, System.IOUtils, System.DateUtils,
  ACBrDFeSSL, ACBrDFe.Conversao, ACBrNFSeXConversao,
  ACBrNFSeXNotasFiscais, Homologacao;

procedure GenerateLocalDps(NFSe: TACBrNFSeX);
var
  Note: TNotaFiscal;
  Xml, SignedXml, ErrorText, SchemaDir, OutputDir, Suffix: string;
  Id: TGUID;
begin
  SchemaDir := GetEnvironmentVariable('NFSE_TEST_SCHEMAS');
  if not FileExists(TPath.Combine(SchemaDir, 'DPS_v1.01.xsd')) then
    raise Exception.Create('Informe NFSE_TEST_SCHEMAS com os schemas PadraoNacional/1.01.');
  OutputDir := GetEnvironmentVariable('NFSE_TEST_OUTPUT');
  if OutputDir = '' then
    raise Exception.Create('Informe NFSE_TEST_OUTPUT para gravar os XMLs locais.');
  ForceDirectories(OutputDir);
  NFSe.Configuracoes.Geral.SSLXmlSignLib := xsLibXml2;
  NFSe.Configuracoes.Geral.LayoutNFSe := lnfsPadraoNacionalv101;
  NFSe.Configuracoes.WebServices.Ambiente := taHomologacao;
  NFSe.SetProvedor(proPadraoNacional, ve101);
  NFSe.NotasFiscais.Clear;
  Note := NFSe.NotasFiscais.New;
  with Note.NFSe do
  begin
    Numero := '1'; // Numeracao exclusiva do ensaio local.
    if GetEnvironmentVariable('NFSE_TEST_SEND') = 'HOMOLOGACAO' then
    begin
      Numero := GetEnvironmentVariable('NFSE_TEST_DPS_NUMBER');
      if (StrToInt64Def(Numero, 0) <= 0) or (Length(Numero) > 15) then
        raise Exception.Create('Numero DPS de homologacao invalido.');
    end;
    NumeroLote := '1';
    IdentificacaoRps.Numero := Numero;
    IdentificacaoRps.Serie := '900';
    verAplic := 'VEEV-TesteLocal-1.0';
    // Margem exclusiva deste ensaio: foi observada diferenca de 3 s com a SEFIN.
    // A API definitiva devera receber a data efetiva da operacao, sem este ajuste.
    DataEmissao := IncSecond(Now, -30);
    DataEmissaoRPS := DataEmissao;
    Competencia := DateOf(DataEmissao);
    cLocEmi := '3136702';
    tpEmit := tePrestador;
    RegimeEspecialTributacao := retNenhum;
    OptanteSN := osnOptanteMEEPP;
    RegimeApuracaoSN := raFederaisMunicipalpeloSN;

    Prestador.IdentificacaoPrestador.CpfCnpj := '16783003000189';
    // Inscricao municipal nao informada: nunca usar '-' como identificador.
    Prestador.RazaoSocial := 'ORGANIZACAO CARLTON LTDA';
    Prestador.cUF := 31;
    Prestador.Endereco.Endereco := 'AVENIDA DEUSDEDITH SALGADO';
    Prestador.Endereco.Numero := '5000';
    Prestador.Endereco.Bairro := 'TEIXEIRAS';
    Prestador.Endereco.CodigoMunicipio := '3136702';
    Prestador.Endereco.xMunicipio := 'Juiz de Fora';
    Prestador.Endereco.UF := 'MG';
    Prestador.Endereco.CEP := '36033000';
    Prestador.Endereco.CodigoPais := 1058;
    Prestador.Endereco.xPais := 'BRASIL';

    // Primeira validacao: sem tomador, como no exemplo enviado pelo usuario.
    Servico.ItemListaServico := '090103';
    // O codigo exibido no portal e 09.01.03.002; o XML separa nacional e sufixo.
    Servico.CodigoTributacaoMunicipio := '002';
    Servico.CodigoNBS := '103031100';
    Servico.CodigoMunicipio := '3136702';
    Servico.CodigoPais := 1058;
    Servico.Discriminacao := 'TESTE LOCAL SEM VALIDADE FISCAL - Hospedagem em motel';
    Servico.Valores.ValorServicos := 100;
    Servico.Valores.tribMun.tribISSQN := tiOperacaoTributavel;
    Servico.Valores.tribMun.tpRetISSQN := trNaoRetido;
    // Valor do exemplo do usuario, nao uma aliquota de ISS ou apuracao de DAS.
    Servico.Valores.totTrib.pTotTribSN := 13.46;
  end;

  // Somente operacoes locais. Nao chamar Emitir, Enviar ou consultas HTTP aqui.
  Xml := Note.GerarXML;
  if Xml = '' then Xml := Note.XmlRps;
  if Xml = '' then raise Exception.Create('ACBr nao retornou XML da DPS.');
  CreateGUID(Id);
  Suffix := GUIDToString(Id);
  TFile.WriteAllText(TPath.Combine(OutputDir, Suffix + '-dps-nao-assinada.xml'), Xml, TEncoding.UTF8);
  SignedXml := NFSe.SSL.Assinar(Xml, 'DPS', 'infDPS', '', '', '', 'Id');
  TFile.WriteAllText(TPath.Combine(OutputDir, Suffix + '-dps-assinada.xml'), SignedXml, TEncoding.UTF8);
  Writeln('OK: DPS de homologacao gerada e assinada localmente.');
  if not NFSe.SSL.Validar(SignedXml, TPath.Combine(SchemaDir, 'DPS_v1.01.xsd'), ErrorText) then
    raise Exception.Create('Falha na validacao XSD: ' + ErrorText);
  Writeln('OK: XML validado no schema DPS_v1.01.xsd.');
  if not NFSe.SSL.VerificarAssinatura(SignedXml, ErrorText, 'infDPS', '', '', '', 'Id') then
    raise Exception.Create('Falha na verificacao da assinatura: ' + ErrorText);
  Writeln('OK: assinatura XML verificada.');
  Writeln('Arquivos locais em: ', OutputDir);
  if GetEnvironmentVariable('NFSE_TEST_SEND') = 'HOMOLOGACAO' then
    SendHomologacao(NFSe, OutputDir)
  else
    Writeln('Nenhuma nota transmitida; sem autorizacao fiscal ou validacao cadastral.');
end;

end.
