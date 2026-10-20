unit Homologacao;

interface

uses ACBrNFSeX;

procedure SendHomologacao(NFSe: TACBrNFSeX; const OutputDir: string);
procedure CheckHomologacaoConfig(NFSe: TACBrNFSeX; const OutputDir: string);
procedure QueryHomologacao(NFSe: TACBrNFSeX; const OutputDir, AccessKey: string);

implementation

uses
  System.SysUtils, System.IOUtils, System.JSON, ACBrDFeSSL,
  ACBrDFe.Conversao, ACBrNFSeXConversao;

procedure CheckHomologacaoConfig(NFSe: TACBrNFSeX; const OutputDir: string);
const
  BaseURL = 'https://sefin.producaorestrita.nfse.gov.br/SefinNacional';
var
  IniPath: string;
begin
  ForceDirectories(OutputDir);
  NFSe.Configuracoes.WebServices.Ambiente := taHomologacao;
  NFSe.Configuracoes.Geral.LayoutNFSe := lnfsPadraoNacionalv101;
  IniPath := TPath.Combine(OutputDir, 'servicos-homologacao.ini');
  // Configuracao dedicada: nao contem nenhum endereco de producao.
  TFile.WriteAllText(IniPath, '[PadraoNacional]' + sLineBreak +
    'Versao=1.01' + sLineBreak + 'HomRecepcionar=' + BaseURL + sLineBreak +
    'HomGerarNFSe=' + BaseURL + sLineBreak +
    'HomConsultarNFSePorChave=' + BaseURL + sLineBreak, TEncoding.ASCII);
  NFSe.Configuracoes.Arquivos.IniServicos := IniPath;
  // SetIniServicos so troca o nome: recarregar explicitamente os parametros.
  NFSe.Configuracoes.WebServices.LerParams;
  if Pos('HomGerarNFSe=' + BaseURL, NFSe.Configuracoes.WebServices.Params.Text) = 0 then
    raise Exception.Create('URL de homologacao nao carregada no ACBr. Nenhum envio iniciado.');
  // NFSE_TEST_SCHEMAS ja aponta para 1.01; nao acrescentar a versao novamente.
  NFSe.Configuracoes.Geral.MontarPathSchema := False;
  NFSe.Configuracoes.Arquivos.PathSchemas :=
    IncludeTrailingPathDelimiter(GetEnvironmentVariable('NFSE_TEST_SCHEMAS'));
  if not FileExists(NFSe.Configuracoes.Arquivos.PathSchemas + 'DPS_v1.01.xsd') then
    raise Exception.Create('Schema DPS_v1.01.xsd nao encontrado antes do envio.');
  NFSe.Configuracoes.Geral.SSLHttpLib := httpOpenSSL;
  NFSe.Configuracoes.Geral.ConsultaLoteAposEnvio := False;
  NFSe.Configuracoes.WebServices.TimeOut := 30000;
  // SetProvedor muda o enum, mas xProvedor so e resolvido ao carregar o municipio.
  NFSe.Configuracoes.Geral.CodigoMunicipio := 3136702;
  NFSe.SetProvedor(proPadraoNacional, ve101);
  if NFSe.Configuracoes.Geral.xProvedor <> 'PadraoNacional' then
    raise Exception.Create('Nome interno do provedor nao resolvido. Nenhum envio iniciado.');
  if NFSe.Provider.ConfigWebServices.Homologacao.GerarNFSe <> BaseURL then
    raise Exception.Create('URL efetiva de homologacao incorreta. Nenhum envio iniciado.');
  Writeln('OK: URL efetiva do ACBr = ', NFSe.Provider.ConfigWebServices.Homologacao.GerarNFSe);
end;

procedure QueryHomologacao(NFSe: TACBrNFSeX; const OutputDir, AccessKey: string);
var
  C: Char;
  Xml: string;
  Report, Item: TJSONObject;
  Errors: TJSONArray;
  I: Integer;
  Confirmed: Boolean;
begin
  if Length(AccessKey) <> 50 then
    raise Exception.Create('Chave deve conter 50 digitos.');
  for C in AccessKey do
    if not CharInSet(C, ['0'..'9']) then
      raise Exception.Create('Chave deve conter somente digitos.');
  CheckHomologacaoConfig(NFSe, OutputDir);
  if NFSe.Provider.ConfigWebServices.Homologacao.ConsultarNFSePorChave <>
     'https://sefin.producaorestrita.nfse.gov.br/SefinNacional' then
    raise Exception.Create('URL efetiva de consulta incorreta.');
  NFSe.NotasFiscais.Clear;
  Writeln('Consultando por chave somente em HOMOLOGACAO. Nenhuma emissao sera executada.');
  try
    NFSe.ConsultarNFSePorChave(AccessKey);
  except
    on E: Exception do
    begin
      TFile.WriteAllText(TPath.Combine(OutputDir, 'falha-consulta.txt'), E.Message, TEncoding.UTF8);
      raise Exception.Create('Falha na consulta: ' + E.Message);
    end;
  end;
  TFile.WriteAllText(TPath.Combine(OutputDir, 'resposta-original.txt'),
    NFSe.WebService.ConsultaNFSe.ArquivoRetorno, TEncoding.UTF8);
  Xml := NFSe.WebService.ConsultaNFSe.XmlRetorno;
  if (Xml = '') and (NFSe.NotasFiscais.Count > 0) then
    Xml := NFSe.NotasFiscais[0].XmlNfse;
  Confirmed := NFSe.WebService.ConsultaNFSe.Sucesso and
    (NFSe.WebService.ConsultaNFSe.Erros.Count = 0) and (Xml <> '') and
    (Pos('NFS' + AccessKey, Xml) > 0);
  Report := TJSONObject.Create;
  try
    Report.AddPair('ambiente', 'homologacao');
    Report.AddPair('operacao', 'consulta_por_chave');
    Report.AddPair('chave_acesso', AccessKey);
    Report.AddPair('xml_recuperado', TJSONBool.Create(Confirmed));
    Errors := TJSONArray.Create;
    Report.AddPair('erros', Errors);
    for I := 0 to NFSe.WebService.ConsultaNFSe.Erros.Count - 1 do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('codigo', NFSe.WebService.ConsultaNFSe.Erros[I].Codigo);
      Item.AddPair('descricao', NFSe.WebService.ConsultaNFSe.Erros[I].Descricao);
      Item.AddPair('correcao', NFSe.WebService.ConsultaNFSe.Erros[I].Correcao);
      Errors.AddElement(Item);
    end;
    if Confirmed then
    begin
      TFile.WriteAllText(TPath.Combine(OutputDir, 'nfse-consultada.xml'), Xml, TEncoding.UTF8);
      Writeln('OK: XML da NFS-e recuperado; chave corresponde a consulta.');
    end
    else
    begin
      Writeln('Consulta sem recuperacao confirmada. Verifique a resposta salva.');
      ExitCode := 2;
    end;
    TFile.WriteAllText(TPath.Combine(OutputDir, 'resultado.json'), Report.ToJSON, TEncoding.UTF8);
    Writeln(Report.ToJSON);
    Writeln('Arquivos locais em: ', OutputDir);
  finally
    Report.Free;
  end;
end;

procedure SendHomologacao(NFSe: TACBrNFSeX; const OutputDir: string);
var
  StatusPath: string;
  Report: TJSONObject;
  Errors: TJSONArray;
  Item: TJSONObject;
  I: Integer;
begin
  if GetEnvironmentVariable('NFSE_TEST_SEND') <> 'HOMOLOGACAO' then
    raise Exception.Create('Modo de transmissao de homologacao nao habilitado.');
  if NFSe.Configuracoes.WebServices.Ambiente <> taHomologacao then
    raise Exception.Create('Este teste permite somente homologacao.');
  CheckHomologacaoConfig(NFSe, OutputDir);
  StatusPath := TPath.Combine(OutputDir, 'estado.txt');
  TFile.WriteAllText(StatusPath, 'envio_iniciado_resultado_pendente', TEncoding.UTF8);
  try
    Writeln('Enviando somente para homologacao nacional.');
    NFSe.Emitir('1', meUnitario, False);
  except
    on E: Exception do
    begin
      TFile.WriteAllText(StatusPath, 'resultado_indeterminado: ' + E.Message, TEncoding.UTF8);
      raise Exception.Create('Falha no fluxo de envio: ' + E.Message + sLineBreak +
        'Nao reenviar automaticamente. ' +
        'Consultar a DPS antes de outra tentativa. Detalhes locais: ' + OutputDir);
    end;
  end;

  TFile.WriteAllText(TPath.Combine(OutputDir, 'resposta-original.txt'),
    NFSe.WebService.Emite.ArquivoRetorno, TEncoding.UTF8);
  TFile.WriteAllText(TPath.Combine(OutputDir, 'dps-envio.xml'),
    NFSe.WebService.Emite.ArquivoEnvio, TEncoding.UTF8);
  Report := TJSONObject.Create;
  try
    Report.AddPair('ambiente', 'homologacao');
    Report.AddPair('http_status', TJSONNumber.Create(NFSe.WebService.Emite.RespStatusCode));
    Report.AddPair('sucesso_acbr', TJSONBool.Create(NFSe.WebService.Emite.Sucesso));
    Report.AddPair('id_dps', NFSe.WebService.Emite.idNota);
    Report.AddPair('chave_acesso', NFSe.WebService.Emite.Link);
    Report.AddPair('numero_nfse', NFSe.WebService.Emite.NumeroNota);
    Errors := TJSONArray.Create;
    Report.AddPair('erros', Errors);
    for I := 0 to NFSe.WebService.Emite.Erros.Count - 1 do
    begin
      Item := TJSONObject.Create;
      Item.AddPair('codigo', NFSe.WebService.Emite.Erros[I].Codigo);
      Item.AddPair('descricao', NFSe.WebService.Emite.Erros[I].Descricao);
      Item.AddPair('correcao', NFSe.WebService.Emite.Erros[I].Correcao);
      Errors.AddElement(Item);
    end;
    if NFSe.WebService.Emite.Sucesso and
       (NFSe.WebService.Emite.Link <> '') and
       (NFSe.WebService.Emite.Erros.Count = 0) then
    begin
      TFile.WriteAllText(StatusPath, 'autorizada_em_homologacao', TEncoding.UTF8);
      if (NFSe.NotasFiscais.Count > 0) and (NFSe.NotasFiscais[0].XmlNfse <> '') then
        TFile.WriteAllText(TPath.Combine(OutputDir, 'nfse-retorno.xml'),
          NFSe.NotasFiscais[0].XmlNfse, TEncoding.UTF8);
      Writeln('OK: autorizacao retornada em HOMOLOGACAO, sem validade fiscal de producao.');
    end
    else
    begin
      TFile.WriteAllText(StatusPath, 'nao_autorizada_ou_resultado_indeterminado_verificar_resposta', TEncoding.UTF8);
      Writeln('Sem autorizacao confirmada. Confira os erros e a resposta salva.');
      ExitCode := 2;
    end;
    TFile.WriteAllText(TPath.Combine(OutputDir, 'resultado.json'), Report.ToJSON, TEncoding.UTF8);
    Writeln(Report.ToJSON);
  finally
    Report.Free;
  end;
end;

end.
