# Forma de pagamento e totalizadores

Aplicar `database/010-payment-method.sql` antes de atualizar a API. A migração adiciona uma coluna nullable em `drafts`; notas e rascunhos existentes permanecem sem pagamento informado. Não altera valores, XML, numeração ou status fiscal.

`POST /v1/drafts` aceita `payment_method`: `dinheiro`, `pix`, `boleto`, `cartao_credito` ou `cartao_debito`. A interface exige a seleção para novos lançamentos; a API aceita ausência/null para compatibilidade com integrações anteriores. Outros valores e tipos são rejeitados. É controle interno, não comprovação de recebimento nem informação transmitida no XML.

`GET /v1/invoices` continua retornando um array para clientes existentes e agora inclui a forma de pagamento do rascunho associado. Notas antigas/importadas podem retornar null.

Com `include_totals=1`, retorna `{invoices, summary}`. A lista contém até 100 registros; o resumo considera **todos** os registros filtrados por empresa autenticada, ambiente, período, situação e `search` (número, chave ou tomador). A busca é literal, sem curingas SQL, limitada a 200 caracteres.

`summary.count` inclui as canceladas presentes no filtro. `total_cents` e `by_payment` excluem canceladas; `cancelled_count` e `cancelled_cents` informam esse grupo separadamente. Os valores agregados são devolvidos como texto em centavos. Métodos não informados ficam no grupo `nao_informado`.

Validação: `tests/payment-totals-regression.py`, integrado ao harness local `tests/access-http-regression.sh`, cobre métodos válidos/inválidos, persistência, compatibilidade, mais de 100 notas, canceladas, filtros/busca e isolamento entre empresas/ambientes. Nenhuma transmissão fiscal é realizada no harness.
