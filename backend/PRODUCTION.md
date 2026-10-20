# Implantacao e piloto de producao

O fluxo de producao esta implementado com liberacao explicita por empresa e por servidor. O teste real ainda precisa ser realizado com dados conferidos pelo responsavel. Nenhum teste automatizado transmite uma nota fiscal.

## Atualizar os servicos

1. Fazer backup do banco e do volume privado `/var/lib/nfse`, incluindo `.secrets/certificates.key` e os certificados criptografados.
2. Aplicar `database/008-production.sql` uma unica vez no Postgres Client, depois das migracoes 001 a 007. Ela preserva os rascunhos/notas anteriores como homologacao. Para usuario de banco limitado, conceder SELECT/INSERT/UPDATE em `company_emission_config` e EXECUTE em `reserve_emission(uuid,uuid,timestamptz,date,text)` e `import_invoice(uuid,uuid,text,text)`; preservar os grants existentes.
3. Implantar `backend/build/nfse-easypanel-producao.zip` no nfse-api e `frontend/build/nfse-frontend-producao.zip` no nfse-web. O ZIP do backend inclui executavel, worker de certificados, renderizador e dois conjuntos de schemas.
4. Manter os volumes e credenciais existentes. Na primeira implantacao manter `NFSE_ENABLE_PRODUCTION=0`. O login e as consultas continuam disponiveis, mas a rota real nao envia documentos.

Configuracoes adicionais do backend:

```dotenv
NFSE_ENABLE_PRODUCTION=0
NFSE_PRODUCTION_ALLOWED_CNPJ=
NFSE_PRODUCTION_SCHEMAS_DIR=/app/schemas-production
NFSE_DANFSE_FONT_DIR=/var/lib/nfse/fonts
```

`NFSE_ENABLE_HOMOLOGATION` conserva seu controle separado. `NFSE_PRODUCTION_ALLOWED_CNPJ` aceita um unico CNPJ de 14 digitos: durante o piloto deve ser o CNPJ da empresa CARLTON cadastrada. Vazio bloqueia todos os CNPJs. Nao trocar o hostname da SEFIN para mudar ambientes; a aplicacao escolhe enderecos fixos por rota.

## Preparar a empresa e o DANFSe

Em `/admin.html`, localizar a CARLTON e conferir o CNPJ. Conferir o perfil fiscal e os parametros do servico antes de criar um rascunho real. O escopo atual e NFS-e regular de ME/EPP do Simples Nacional em Juiz de Fora/MG, com IBS/CBS opcional no perfil CST 200 / cClassTrib 200048 / cIndOp 030101. O enquadramento aplicado deve ser conferido pelo responsavel fiscal.

1. **Certificado A1**: instalar/conferir certificado valido do mesmo CNPJ. O certificado e compartilhado pelos dois ambientes; as notas e as sequencias sao separadas.
2. **Numeracao DPS**: selecionar Producao e configurar a serie e o proximo numero considerando outros emissores. Informar 501 somente se 500 for a ultima DPS daquela serie, nao o numero da NFS-e. Preferir serie exclusiva para evitar concorrencia com outro software. A sequencia nao pode retroceder.
3. **Fontes do DANFSe**: instalar `arial.ttf`, `arialbd.ttf` e `micross.ttf`, com licenciamento apropriado, no volume privado `/var/lib/nfse/fonts`, legivel pelo UID 10001. Nao enviar fontes proprietarias para o GitHub. Homologacao admite Liberation Sans como previa; producao exige as fontes do leiaute. A tela administrativa indica pendencia se os arquivos nao existem. A emissao real fica bloqueada enquanto essa preparacao nao estiver concluida.
4. **Producao**: selecionar a serie ja cadastrada, conferir os dados e marcar a liberacao da empresa. Essa acao e auditada e exige certificado valido. Ela nao habilita o servidor sozinha.
5. Quando estiver pronto para o piloto, definir `NFSE_ENABLE_PRODUCTION=1` e `NFSE_PRODUCTION_ALLOWED_CNPJ` com o CNPJ cadastrado, preservar os demais valores e reimplantar. Conferir na administracao os indicadores Servidor/piloto e Fontes do DANFSe.

## Teste real controlado

Entrar pelo CNPJ da CARLTON e selecionar **Producao** no menu de ambiente. O login sempre inicia em Homologacao. As notas e os rascunhos sao filtrados por ambiente antes do limite da consulta. Um rascunho criado em homologacao nao pode ser convertido em producao: criar outro rascunho com os dados reais conferidos.

Conferir servico, valor, tomador, competencia e parametros. Na revisao, a tela identifica PRODUCAO, informa a validade fiscal e exige marcar a confirmacao. Somente o comando **Emitir nota real em producao** solicita a transmissao. Nao usar dados ficticios do ensaio automatizado nesse passo.

Depois da autorizacao, conferir numero da NFS-e, chave, ambiente, valor, XML e DANFSe. O numero da NFS-e e atribuido pela SEFIN; pode ser diferente do numero da DPS. O DANFSe de producao nao tem tarja de homologacao. O XML retornado deve passar pelo schema e pela verificacao de assinatura antes de ser considerado autorizado pelo fluxo local; o banco tambem confere empresa, ambiente, DPS, serie e valor.

Se houver resultado desconhecido, falha de assinatura/esquema do retorno ou falha de persistencia depois do envio, a tentativa permanece sem reenvio automatico. Consultar a tentativa e conciliar a resposta com o provedor antes de qualquer outra emissao. Desligar a liberacao bloqueia novos envios; uma transmissao ja iniciada pode concluir. Cancelamento e conciliacao automatizada ainda nao fazem parte desta versao.

## Rotas

- `GET /v1/emission-config`: indicadores de liberacao e disponibilidade para a empresa autenticada. Nao substitui a validacao do certificado no envio.
- `GET/PATCH /v1/admin/companies/:id/production`: consultar/liberar/bloquear producao, com `{enabled: boolean, series: string}`. Serie obrigatoria ao liberar.
- `POST /v1/drafts`: campo `environment`, padrao `homologacao`, imutavel depois da criacao.
- `GET /v1/drafts?environment=producao` e `GET /v1/invoices?environment=producao`: filtros opcionais, aplicados antes do limite; filtros de data continuam disponiveis.
- `POST /v1/drafts/:id/emit-production`: `issued_at`, `competence`, `confirm_production: true`. Sem confirmacao booleana explicita ou sem liberacoes, falha antes da reserva/transmissao.
- `POST /v1/drafts/:id/emit-homologation`: conserva o ambiente de testes e rejeita rascunho de producao.

As referencias oficiais de [enderecos das APIs](https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/apis-prod-restrita-e-producao) e [schemas de producao](deploy/schemas-production/README.md) foram conferidas em 20/10/2026. Homologacao e producao usam schemas distintos nesta versao.
