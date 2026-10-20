program CancelEventProbe;
{$APPTYPE CONSOLE}
uses System.SysUtils, System.IOUtils,
  ACBrNFSeX, ACBrDFe.Conversao, ACBrNFSeXConversao,
  PadraoNacional.Provider, ACBrNFSeXWebservicesResponse;
type
  TOfflineProvider = class(TACBrNFSeProviderPadraoNacional)
  public
    procedure PrepareOnly(Response: TNFSeEnviarEventoResponse);
  end;
procedure TOfflineProvider.PrepareOnly(Response: TNFSeEnviarEventoResponse);
begin PrepararEnviarEvento(Response); end;
var NFSe: TACBrNFSeX; Response: TNFSeEnviarEventoResponse; Env: Integer;
begin
  try
    if ParamCount<>1 then raise Exception.Create('Diretorio de teste obrigatorio.');
    ForceDirectories(ParamStr(1));
    NFSe:=TACBrNFSeX.Create(nil);
    try
      NFSe.Configuracoes.Geral.LayoutNFSe:=lnfsPadraoNacionalv101;
      NFSe.Configuracoes.Geral.CodigoMunicipio:=3136702;
      NFSe.Configuracoes.Geral.Emitente.CNPJ:='11111111000191';
      NFSe.Configuracoes.WebServices.UF:='MG';
      NFSe.Configuracoes.Arquivos.PathCan:=ParamStr(1);
      NFSe.Configuracoes.Arquivos.PathSalvar:=ParamStr(1);
      NFSe.SetProvedor(proPadraoNacional,ve101);
      Response:=TNFSeEnviarEventoResponse.Create;
      try
        for Env:=1 to 2 do
        begin
          Response.Clear;
          with Response.InfEvento.pedRegEvento do
          begin
            tpAmb:=Env; verAplic:='VEEV-API-1.0'; dhEvento:=EncodeDate(2026,10,20)+EncodeTime(10,0,0,0);
            chNFSe:='31367022211111111000191'+StringOfChar('0',27); nPedRegEvento:=1; tpEvento:=teCancelamento;
            cMotivo:=2; xMotivo:='Servico nao prestado &amp; pedido do tomador';
          end;
          // Only XML preparation: never signs, never creates an HTTP service.
          TOfflineProvider(NFSe.Provider as TACBrNFSeProviderPadraoNacional).PrepareOnly(Response);
          if Response.Erros.Count<>0 then raise Exception.Create('Erro no preparo do pedido.');
          TFile.WriteAllText(TPath.Combine(ParamStr(1),'cancelamento-'+IntToStr(Env)+'.xml'),Response.ArquivoEnvio,TEncoding.UTF8);
        end;
      finally Response.Free; end;
    finally NFSe.Free; end;
    Writeln('PASS: pedidos de cancelamento preparados pelo ACBr, sem transmissao.');
  except on E:Exception do begin Writeln(E.Message); Halt(1); end; end;
end.
