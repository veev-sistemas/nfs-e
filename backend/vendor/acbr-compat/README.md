# Compatibilidade NT009 / NFS-e regular em homologacao

## Assinaturas aninhadas de eventos

`ACBrDFeXsLibXml2.pas` copia a unidade instalada em C:/ACBr, preservando cabecalho e licenca LGPL. A unica alteracao funcional seleciona `SignedInfo` dentro do `SignNode` ja identificado por `infElement`, em vez da primeira ocorrencia global no documento. O evento de cancelamento contem assinatura do pedido dentro de `infEvento` e assinatura externa do evento. A verificacao global anterior utilizava o `SignedInfo` do pedido ao conferir o evento externo. O DPR referencia explicitamente a copia local. Nao altera XML assinado nem dispensa verificacao de assinatura.

Regressao offline: gerar fixtures com `tests/nested-event-signatures.py`, assinar com `SignNestedEventProbe`, validar com `VerifyEventProbe` e executar `saved-cancellation-regression.py` dentro do harness HTTP. Duas chaves ficticias diferentes; documento adulterado deve falhar; consulta GET deve recuperar uma resposta salva valida sem transmissao fiscal. Nunca incluir PFXs de teste nos pacotes de deploy.

PadraoNacional.GravarXml.pas e uma copia do gerador ACBr instalado em C:/ACBr em 20/10/2026, preservando cabecalho e licenca LGPL. GerarXMLInfDps inclui finNFSe=0 antes de cLocEmi em homologacao e rejeita finalidade de credito/debito. GerarXMLCodigoServico coloca cNBS e cIntContrib antes de xDescServ, conforme o leiaute da NT009 v1.01 (planilha LEIAUTE DPS_NFS-e - RT, linhas 229 a 234). O DPR referencia explicitamente esta copia; nao modifica a instalacao compartilhada do Delphi/ACBr.

Referencia oficial: NT009 v1.01, secao 2.2, pagina 4, https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/rtc/nota-tecnica-009-se-cgnfs-e-v-1-01.pdf . Retorno do servidor em 20/10/2026: E1235 esperando cMotivoEmisTI ou finNFSe quando recebeu cLocEmi.

Esta adaptacao nao implementa toda a NT009. Implementa o perfil IBS/CBS regular de hospedagem em homologacao com CST 200, cClassTrib 200048 e cIndOp 030101, confirmados pelo usuario. indDest=0 em IBSCBS, cIndOp em IBSCBS e CST/cClassTrib em IBSCBS/valores/trib (Anexo VI NT009 v1.04.01, linhas 178 e 373-425). Sem ajustes, credito ou diferimento. Classificacoes diferentes sao recusadas. O schema local restringe o grupo a esse subconjunto. A validacao local nao substitui a autorizacao da SEFIN. Limitada ao fluxo regular, Simples Nacional e homologacao ja suportado. Os dados sao escritos antes da assinatura tanto na preparacao quanto na regeneracao interna feita por Emitir. Nenhum XML assinado e alterado.

O schema tiposComplexos_v1.01.xsd inclui o mesmo requisito local (finNFSe com tipo restrito ao valor 0) e a ordem atual de cServ, identificados por comentarios VEEV. Trata-se de perfil de compatibilidade sobre o pacote anterior, nao de um novo pacote oficial de schemas completo. Historico e XMLs anteriores permanecem intactos. Revisar/remover esta copia quando atualizar o ACBr para uma versao com suporte oficial equivalente.

Compatibilidade SEFIN em 20/10/2026: a DPS8 rejeitou indDest diretamente em infDPS (E1235; esperados toma/interm/serv). O gerador e o schema local agora colocam indDest=0 em IBSCBS, apos cIndOp, preservando finNFSe=0 em infDPS. Este perfil acompanha o ambiente observado; nao se presume implantacao integral da planilha NT009. A confirmacao de autorizacao continua dependendo de novo teste em homologacao.
