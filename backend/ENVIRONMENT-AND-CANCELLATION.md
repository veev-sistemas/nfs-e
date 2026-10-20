# Ambiente por empresa e cancelamento

Aplicar `database/009-environment-cancellation.sql` depois da migração 008, antes de iniciar o novo backend. Manter backup do banco antes da atualização.

No administrador, a ação **Ambiente** escolhe homologação ou produção por empresa. O cliente vê a indicação sem seletor. A API confere o ambiente em criação de rascunho e emissão; uma tela antiga deve ser atualizada se o administrador alterar a configuração. A seleção não substitui certificado, sequência, liberação da empresa e habilitação do servidor. Empresas existentes começam em homologação.

`GET /v1/invoices` aceita `status=authorized|cancelled|imported`, combinado com datas e ambiente, antes de limitar a 100 resultados. O nome do tomador vem do XML autorizado, com fallback para o cadastro vinculado ao rascunho.

## Pedido de cancelamento

- `POST /v1/invoices/:id/cancel`: `reason_code` string `1`, `2` ou `9`, `reason` de 15 a 255 caracteres e `confirm_cancellation: true` booleano.
- `GET /v1/invoices/:id/cancellation`: última tentativa persistida.
- `GET /v1/invoices/:id/cancellation/xml`: evento confirmado de cancelamento.

O backend usa o evento 101101, certificado do prestador e endpoint fixo do ambiente original da nota. Homologação depende de `NFSE_ENABLE_HOMOLOGATION=1`; produção depende de `NFSE_ENABLE_PRODUCTION=1` e do CNPJ permitido no servidor. Não é necessário manter a emissão de novas notas liberada para cancelar uma nota anterior.

A reserva é persistida antes de chamar a SEFIN. Bloqueio por nota e índice único impedem dois pedidos simultâneos. Pedidos `sending`, `unknown` e `cancelled` são idempotentes: retornam a tentativa existente, sem nova transmissão. Só uma rejeição explícita da SEFIN permite novo pedido. A resposta de sucesso precisa conter evento válido no XSD, assinatura válida e correspondência de chave, CNPJ autor e ambiente para atualizar a nota para `cancelled`. O XML original é preservado; o DANFSe original deixa de ser disponibilizado para uma nota cancelada.

**Resultado inconclusivo:** a consulta da tela lê a tentativa persistida, sem retransmitir. A conciliação remota automática de eventos ainda não está implementada. Se houver queda do processo ou retorno sem confirmação, conferir o evento no ambiente nacional e tratar a tentativa com suporte antes de qualquer reenvio. Não apagar a reserva nem marcar a nota como cancelada sem evento confirmado.

Não foram emitidas ou canceladas notas reais na validação. O teste HTTP mantém ambos os ambientes desabilitados e utiliza banco e certificados fictícios; o probe Delphi prepara pedidos sem instanciar serviço HTTP, validados contra os XSDs de ambos os ambientes.

Referência: [documentação técnica oficial e Anexo II de eventos](https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/documentacao-atual).
