# Persistencia de notas de homologacao

Aplicar 003_invoices.sql no banco que ja recebeu 001 e 002. A migracao cria invoices e uma funcao de importacao com transacao atomica. Em usuarios de banco com permissoes restritas, conceder SELECT/INSERT em invoices e EXECUTE na funcao, alem de SELECT em companies/drafts. Nao ha SECURITY DEFINER.

Rotas autenticadas pela chave da empresa:

- POST /v1/invoices/import-homologation: JSON com xml (texto) e draft_id opcional.
- GET /v1/invoices: ultimas 100 notas da empresa, sem XML na listagem.
- GET /v1/invoices/:id: metadados da nota.
- GET /v1/invoices/:id/xml: XML em application/xml.

O CNPJ do XML deve corresponder ao cadastro da empresa da chave de API. A chave da empresa ficticia, cujo CNPJ e zero, sera rejeitada para importar o XML real. Para o ensaio, provision-carlton-homologation.sql cria a empresa real separadamente e devolve uma nova chave de API. Execute uma vez e guarde a chave; cada execucao gera outra credencial.

O banco extrai chave, numero, CNPJ, valor e ambiente do XML nacional, valida consistencia do CNPJ na chave e DPS, rejeita producao, DTD e entidades, confere empresa/valor do rascunho quando informado e guarda o XML com SHA-256. Reimportar o mesmo XML e vinculo retorna o registro existente; mesma chave com conteudo ou vinculo diferente retorna conflito. Operacoes nao alteram rascunhos antigos.

Status imported significa documento recebido pela API. Esta rota nao consulta a SEFIN nem verifica a assinatura criptografica: nao deve ser apresentada como nova autorizacao fiscal. O XML do ensaio foi recuperado na consulta anterior, mas essa origem nao e autenticada automaticamente pelo endpoint. A integracao de emissao/consulta diretamente na API ainda e uma etapa posterior.

A nota externa do ensaio nao teve rascunho no banco; draft_id fica null para preservar sua origem. Futuras emissoes feitas pela API deverao vincular o rascunho correto e persistir o resultado retornado pelo servico fiscal.

Depois de migrar e publicar o ZIP atualizado, execute no PowerShell:

```powershell
powershell -File D:\Fontes_Apps\Nfs-e\backend\tests\import-invoice.ps1
```

Informe a chave da empresa CARLTON. O script importa o XML consultado, baixa-o novamente e compara conteudo e hash. Nao transmite ao governo. O script nao deve receber PFX nem senha de certificado.

Validado: compilacao Linux da API; health e exigencia de autenticacao nas quatro rotas de notas em servidor local; sintaxe PowerShell do importador; ZIP contem somente Dockerfile e executavel Linux atualizado. O teste SQL em tests/invoices-regression.sql cobre importacao, duplicacao, conflito de XML, CNPJ, producao, DTD e rascunho inexistente com rollback, mas nao foi executado porque nao existe PostgreSQL local configurado. Migracao e testes de persistencia no PostgreSQL do EasyPanel continuam pendentes. Nenhum dado foi importado automaticamente nesta etapa.
