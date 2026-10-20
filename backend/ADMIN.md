# Administracao de empresas

Tela: `/admin.html` no mesmo dominio do frontend. O link "Acesso administrativo" fica na tela de login da empresa.

## Instalacao

1. No banco existente, aplicar `database/006_admin_and_filters.sql` uma unica vez, depois das migracoes 001 a 005. A migracao e transacional e nao altera XMLs ou snapshots autorizados.
2. No console privado do banco, executar `database/bootstrap-admin.sql`. Ele gera uma senha criptograficamente aleatoria para o usuario `admin`, salva apenas bcrypt e mostra a senha inicial no resultado. Guardar essa senha em local privado; nao colar em mensagens nem capturas. Reexecutar o bootstrap redefine a senha e encerra as sessoes desse administrador.
3. Implantar backend e frontend atualizados. Entrar em `/admin.html` com o usuario e a senha gerada no banco.

Nao existe criacao publica de administradores, senha padrao ou chave administrativa no frontend. O bootstrap nao e uma rota HTTP. Caso o servidor utilize um usuario de banco limitado, conceder a ele acesso as novas tabelas/sequencias e EXECUTE em `login_admin(text,text)`, `set_company_password(uuid,text)` e `set_company_access(uuid,boolean)`. Nao conceder `set_admin_password` ao usuario de execucao. O usuario de deploy/dono do schema executa a migracao e o bootstrap.

## Operacoes

- Listar e buscar ate 1.000 empresas por nome/CNPJ.
- Cadastrar razao social, CNPJ e senha inicial; gerar senha aleatoria no navegador usando `crypto.getRandomValues` ou informar uma senha propria. Senhas tem de 12 a 72 bytes UTF-8. A API nunca retorna a senha ou o hash na listagem.
- Cadastrar opcionalmente endereco, municipio IBGE, UF, CEP, serie de homologacao e inscricao municipal. A tela indica perfil pendente quando ele ainda nao existe. Certificados permanecem provisionados no volume privado; o cadastro de acesso nao habilita emissao sem perfil, parametros e certificado.
- Bloquear/liberar o acesso de uma empresa. Bloqueio afeta sessoes e chaves de API; desbloqueio exige novo login da empresa.
- Redefinir senha da empresa, invalidando suas sessoes atuais. As chaves de integracao conservam seu ciclo de vida proprio.

As contas empresariais nao podem acessar nenhuma rota administrativa. As sessoes administrativas sao aleatorias, guardadas no banco somente como SHA-256 e expiram em uma hora. O navegador as mantem somente em memoria. Login usa bcrypt custo 12 e bloqueia a conta por 15 minutos apos cinco falhas. Todas as mutacoes administrativas registram autor, empresa, acao e horario, sem senha, na tabela `admin_audit`.

Rotas:

| Metodo | Rota | Funcao |
| --- | --- | --- |
| POST | /v1/admin/auth/login | Login com username/password |
| GET | /v1/admin/auth/me | Identidade administrativa |
| POST | /v1/admin/auth/logout | Encerrar sessao |
| GET/POST | /v1/admin/companies | Listar/cadastrar |
| PATCH | /v1/admin/companies/:id/access | enabled booleano |
| POST | /v1/admin/companies/:id/password | Redefinir senha |

Cadastro e perfil fiscal sao gravados em uma transacao. Duplicidade de CNPJ retorna 409. A empresa entra pelo CNPJ e senha na tela usual; a permissao de administrador nunca e derivada do CNPJ, da chave de API ou de campos enviados pelo usuario.

## Tomadores e datas

A migracao normaliza os nomes dos tomadores existentes e instala um trigger para INSERT/UPDATE em caixa alta. A interface tambem converte a digitacao, incluindo acentos. Os parametros textuais FireDAC usam Unicode para preservar nomes e senhas UTF-8. XMLs ja emitidos nao sao reescritos.

`GET /v1/invoices?date_from=AAAA-MM-DD&date_to=AAAA-MM-DD` filtra por emissao (`issued_at`, extraida de `infNFSe/dhProc`), antes do limite de 100 registros. A data final e inclusiva em America/Sao_Paulo. Sem data, retorna as ultimas 100 notas. Na ausencia de data valida no XML legado, utiliza `imported_at` como fallback. O indice por empresa/emissao suporta a consulta e a separacao por empresa e mantida.

## Validacao

`tests/access-http-regression.sh` usa exclusivamente `nfse_access_test`, com dados ficticios. Testa isolamento empresa/admin, cadastro atomico, duplicidade, bloqueio e revogacao, reset, auditoria, logout, expiracao, nomes com acentos em caixa alta e limites de datas de Brasilia. Nao apontar esse script para um banco com dados reais.
