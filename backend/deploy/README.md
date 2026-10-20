# Publicacao EasyPanel

Controle de acesso: antes de implantar esta versao, aplique `backend/database/005_access_control.sql` no banco existente. Consulte `backend/ACCESS-CONTROL.md` para definir senha, bloquear empresas e testar login. A migracao nao cria senhas padrao e preserva as chaves de integracao existentes.

O pacote `backend/build/nfse-easypanel.zip` contem o executavel Linux compilado, Dockerfile, openssl-pfx.cnf, download-danfse.sh, render-danfse.py, danfse-assets e schemas. Nao contem certificados nem senhas. Recrie o ZIP depois de cada compilacao com esses sete itens na raiz. O DANFSe e gerado do XML local; nao depende da API nacional de PDF suspensa (ver backend/DANFSE.md).

Para emissao via API, siga `backend/EMISSION-API.md`. A imagem inicia com emissao desabilitada; primeiro aplique a migracao 004, configure o perfil fiscal e os volumes privados e persistentes.

No projeto nfse, crie um servico App chamado nfse-api. Em Source/Origem selecione Upload e envie o ZIP. Use o builder Dockerfile, caminho Dockerfile. O Dockerfile usa Ubuntu 26.04 para corresponder ao ambiente do SDK utilizado. O servidor deve ser x86-64.

Defina no Ambiente do servico (a senha e a senha PostgreSQL, nao a chave da API):

```env
NFSE_DB_HOST=nfse_nfse-db
NFSE_DB_PORT=5432
NFSE_DB_NAME=nfse
NFSE_DB_USER=Postgrenfse
NFSE_DB_PASSWORD=<preencher-no-painel>
NFSE_BIND=0.0.0.0
NFSE_PORT=9000
```

Para a fase inicial de teste, o usuario PostgreSQL e o ja criado. Antes de producao configure uma conta de banco com privilegios minimos conforme o README principal.

Configure o dominio do App para a porta HTTP interna 9000 e HTTPS. Mantenha a porta exposta do PostgreSQL em 0. Implante e confira os logs; depois abra /health no dominio da API. Esse health confirma apenas HTTP. Para testar acesso ao banco, use GET /v1/settings com Authorization: Bearer <chave-da-empresa> em ferramenta de teste, sem expor essa chave em URL ou frontend publico.

Status: dependencias ELF verificadas no WSL; teste local /health confirmado pelo usuario. Build e execucao do container e conexao ao PostgreSQL remoto ainda precisam ser validados no EasyPanel.
