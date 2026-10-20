# Acesso por CNPJ

Aplique `database/005_access_control.sql` uma vez no banco antes de implantar o novo executavel. Empresas existentes continuam com suas chaves de API; login por senha exige provisionamento administrativo. Nesta etapa o administrador opera pelo console privado PostgreSQL, sem rota publica de cadastro ou administracao.

No console PostgreSQL, substitua os valores abaixo. Nao use a senha do certificado nem derive a senha do CNPJ. Use senha exclusiva com 12 a 72 bytes UTF-8. Evite guardar senhas no historico do console; use `\set HISTFILE /dev/null` antes de provisionar.

```sql
SELECT set_company_password('UUID-DA-EMPRESA'::uuid, 'SENHA-EXCLUSIVA');
SELECT set_company_access('UUID-DA-EMPRESA'::uuid, false); -- bloquear
SELECT set_company_access('UUID-DA-EMPRESA'::uuid, true);  -- desbloquear
```

Cadastre a empresa pela tabela companies, com nome e CNPJ, antes de definir a senha. Perfis fiscais e certificado continuam exigindo provisionamento separado. A senha usa bcrypt custo 12. Redefinir senha ou bloquear/desbloquear revoga todas as sessoes da empresa. Desbloquear nao restaura sessoes antigas. As chaves de integracao existentes voltam a funcionar ao desbloquear; para revogar uma chave permanentemente, desative-a em api_keys.

## HTTP

`POST /v1/auth/login` recebe `{"cnpj":"16783003000189","password":"..."}`. Aceita CNPJ com pontuacao. Retorna access_token, token_type Bearer, expires_in 28800, company_id, name e document. Use somente HTTPS. O frontend nao deve embutir chaves de API: utiliza a sessao retornada pelo login.

`GET /v1/auth/me` retorna a empresa autenticada. `POST /v1/auth/logout` revoga a sessao atual. Ambos recebem Authorization: Bearer TOKEN. As rotas existentes aceitam sessao ou chave de integracao e continuam isoladas por empresa.

Credenciais incorretas, empresa bloqueada ou inexistente retornam a mesma mensagem. Cinco falhas bloqueiam login por 15 minutos; a contagem e persistida no banco. Login correto apos o prazo zera a contagem. O bloqueio administrativo impede a proxima requisicao de qualquer sessao ou chave; operacoes que ja estavam em andamento podem concluir. Nenhuma nota ou dado fiscal e apagado.

Auditoria administrativa e de login fica em access_audit, sem senha ou token. Sessoes guardam somente SHA256 do token aleatorio, expiram em 8 horas e nao tem renovacao automatica. Mantenha as tabelas e funcoes administrativas restritas ao operador; a conta atual do banco e administrativa e deve ser substituida por uma conta de privilegios minimos antes de producao. Aplique tambem limite de requisicoes no proxy antes de disponibilizar login publicamente em escala.

Primeira versao: um usuario por empresa. Multiplos usuarios, recuperacao por email e painel administrativo ficam para etapas seguintes. Nao existe senha inicial padrao e nenhuma senha real foi incluida no pacote.
