# Frontend VEEV NFS-e

Producao (migracao 008): seletor de ambiente, consultas separadas e confirmacao obrigatoria de validade fiscal. A emissao exige liberacao da empresa e do servidor; [instrucoes do piloto](../backend/PRODUCTION.md). O modo local `--demo` e ficticio e bloqueia qualquer emissao real.

Em Configuracoes ha a opcao Enviar grupo IBS/CBS e os codigos fiscais. O perfil implementado e validado em homologacao utiliza CST 200, cClassTrib 200048 e cIndOp 030101. Salvar um codigo nao ativa o grupo. Os valores de cada rascunho permanecem no snapshot. Desmarcar o grupo nao resolve E0855 de um ambiente que exija essas informacoes.

Em `/admin.html`, as acoes **Numeracao DPS** e **Certificado A1** permitem configurar a proxima DPS por empresa/serie/ambiente e instalar um PFX/P12 com senha. Requer backend atualizado e migracao 007. Consulte `../backend/CERTIFICATES-AND-NUMBERING.md` para implantacao e backup privado. Producao permanece somente em preparacao.

Atualizacao 20/10/2026: o resultado da tentativa exibe tambem o complemento de validacao retornado pelo backend atualizado. Tentativas antigas mantem seu resultado salvo; esta alteracao nao reenvia notas.

Interface web em portugues para login por CNPJ, visao geral, tomadores, criacao/revisao de rascunhos, emissao explicita em homologacao, consulta de tentativas, notas, XML, DANFSe e padroes fiscais. Sem dependencias de build, CDNs, fontes externas ou chaves embutidas.

## EasyPanel

1. Atualize primeiro o backend com o novo ZIP: a listagem de rascunhos inclui identificador/status da tentativa e nota vinculada. A migracao 005 ja aplicada continua valida; nao a reaplique.
2. Crie um servico **App** separado chamado **nfse-web** no projeto nfse. Preserve nfse-api e nfse-db.
3. Em Fonte > Upload envie `build/nfse-frontend-easypanel.zip`, builder Dockerfile, caminho Dockerfile.
4. Configure o dominio HTTPS desse novo servico para a porta HTTP interna **80**.
5. Implante e abra o dominio do nfse-web. Entre com CNPJ e a senha ja cadastrada. Nunca utilize a senha do PFX ou chave da API no formulario de login.

O Nginx encaminha `/v1/` ao backend pelo HTTPS existente e verifica o certificado TLS. A URL configurada por padrao e nfse-nfse-api.0piict.easypanel.host. Para outro backend, defina `NFSE_API_HOST` apenas com seu hostname, sem protocolo nem barra. O navegador usa sempre a mesma origem; nao e necessario habilitar CORS no Delphi.

Sessoes ficam somente na memoria da pagina. Atualizar/fechar exige login novamente; sair revoga a sessao no backend. Um bloqueio/expiracao retornando 401 encerra o acesso na proxima requisicao. Nao existem rastreadores, logs de senha nem armazenamento de token no localStorage. Os dados fiscais exibidos sao os retornados pela empresa autenticada.

## Operacao

Rascunhos guardam copia dos campos fiscais; alterar padroes nao muda os anteriores. Informar tomador e opcional. O valor aceita digitos sem separador de milhar e virgula para centavos. A emissao exige abrir a revisao e confirmar **Emitir em homologacao**. Nenhuma emissao e feita no login ou ao abrir listas. Nao existe reenvio automatico. Se houver tentativa inconclusiva, o frontend oferece consulta, sem liberar outra emissao do mesmo rascunho. Notas autorizadas possuem download autenticado dos documentos.

O frontend mostra ate 100 notas/rascunhos/tomadores, conforme limite da API. Indicadores refletem apenas essa consulta. Nao inclui cancelamento, producao, IBS/CBS, recuperacao de senha por email ou painel de administrador. Bloqueio e provisionamento permanecem no console privado, conforme backend/ACCESS-CONTROL.md.

## Verificacao local

`python dev_server.py` serve a interface em http://127.0.0.1:4173. Encaminha chamadas apenas ao backend HTTPS fixo, sem exigir CORS. Para QA sem login real, `python dev_server.py --demo` usa dados ficticios em memoria. O modo demonstracao existe apenas no servidor local de teste e nao e incluido no ZIP/Docker. Nunca use credenciais reais no modo demo.

Sintaxe: `node --check dist/app.js`. Os testes de navegador devem usar modo demo ou banco isolado, sem emissao fiscal real.
# Administracao e consulta por periodo

`dist/admin.html` e `dist/admin.js` oferecem o painel administrativo no mesmo dominio. A API valida uma sessao administrativa propria; a interface nao contem credenciais ou chave administrativa. A tela de acesso da empresa tem um link para essa area. Instalacao e bootstrap: `../backend/ADMIN.md`.

Notas fiscais possuem filtro de emissao inicial/final (Brasilia, data final inclusiva), enviado a API antes do limite de 100 registros. O nome do tomador e convertido para caixa alta durante o cadastro e normalizado no backend. Os rascunhos e XMLs ja autorizados permanecem preservados.

