# Backend NFS-e em Delphi

## Interface web e controle de acesso

O frontend esta em `frontend/`, com instrucoes em `frontend/README.md`. Login por CNPJ/senha, sessoes e bloqueio da empresa foram implementados na migracao 005; veja `backend/ACCESS-CONTROL.md`. Emissao em homologacao, consulta, XML e DANFSe foram validados no servidor. O painel web usa sessoes de usuario, sem incluir a chave de integracao no navegador. Implante primeiro o ZIP atualizado do backend e depois o frontend em um App separado nfse-web.

## Atualizacao para tomador opcional

Em bancos existentes, aplique `backend/database/002_optional_customer.sql` antes de publicar o backend atualizado. Em instalacoes novas, aplique as migracoes 001 e 002 em ordem. POST `/v1/drafts` aceita `customer_id` omitido ou `null` para representar tomador nao informado. UUID informado continua exigindo cliente da mesma empresa; texto vazio e UUID invalido sao rejeitados. A chave estrangeira continua protegendo o isolamento dos clientes. Esta opcionalidade vale para rascunhos e nao dispensa a validacao fiscal da DPS antes da transmissao.

Exemplo sem tomador: `{"amount_cents":10000}`. Os padroes fiscais e o historico funcionam da mesma forma. Recompile para Linux e gere novamente o pacote de deploy para publicar essa alteracao; o ZIP anterior ainda exige cliente.

Base inicial implementada em Delphi (Horse 3.1.0 + FireDAC + PostgreSQL), compilada com o Delphi 10.3 instalado nesta maquina. Uma conexao de banco por requisicao, consultas parametrizadas e acesso separado por empresa por meio de chave de API. Horse usa o provider Indy/WebBroker e esta incluido em `backend/vendor/horse`.

## Teste local sem banco

Abra `backend/NfseBackend.dproj`, execute **Project > Build** e depois **Run** (F9). A janela deve mostrar `Servidor Horse ativo` e permanecer aberta. Acesse **http://127.0.0.1:9000/health** para receber `{"status":"ok"}`. Este teste nao exige PostgreSQL, libpq ou variaveis de banco. As rotas de clientes, configuracoes e rascunhos continuam exigindo banco configurado.

Tambem e possivel executar `backend/run-local.cmd`, que mantem as mensagens visiveis caso o processo termine. CTRL+C encerra o servidor. Se a porta estiver ocupada, encerre a outra instancia antes de executar novamente. O console permanece aguardando conexoes dentro de `THorse.Listen`, sem depender de ENTER para continuar ativo.

## Fluxo de uso

1. Cadastre a empresa administrativamente e cadastre seus clientes pela API.
2. Salve uma vez o regime, codigo e descricao do servico padrao e percentuais desejados.
3. Para criar outro rascunho, envie apenas `customer_id` e `amount_cents`.
4. Os padroes ficam no PostgreSQL e sobrevivem ao reinicio. Um PATCH muda apenas os campos enviados. Uma alteracao vale para os proximos rascunhos; os antigos conservam uma copia dos valores usados.
5. `overrides` altera somente aquele rascunho. Para alterar o padrao, use explicitamente PATCH `/v1/settings`.

`simples_percent: 6` e um exemplo de configuracao informado pelo usuario. Nao e uma aliquota legal fixa, nem equivale automaticamente ao ISS. Esta base nao calcula DAS, nao apura impostos e nao gera documento fiscal autorizado. Percentuais sao armazenados como configuracao; `amount_cents` usa centavos inteiros (R$ 100,00 = 10000).

## Preparacao

- PostgreSQL com permissao administrativa para instalar `pgcrypto` na migracao.
- Delphi com Indy e FireDAC PostgreSQL. Para Windows, instale `libpq.dll` e suas dependencias na arquitetura do executavel (Win32 neste teste). Para Linux, use Delphi com suporte Linux, libpq e toolchain correspondente; a compilacao Linux ainda nao foi verificada.
- Rode `psql -f backend/database/001_initial.sql` no banco escolhido. A migracao e inicial e deve ser aplicada uma vez em banco vazio.
- Provisione a empresa com `backend/database/provision-company.sql`, conforme exemplo no proprio arquivo. A API guarda somente o hash SHA-256 da chave. Provisione uma chave diferente por empresa.
- Para execucao use conta de banco com SELECT nas tabelas de empresas/chaves e SELECT/INSERT/UPDATE nas tabelas de trabalho; nao utilize o usuario administrador.

Defina no processo que inicia a API:

```powershell
$env:NFSE_DB_HOST = '127.0.0.1'
$env:NFSE_DB_PORT = '5432'
$env:NFSE_DB_NAME = 'nfse'
$env:NFSE_DB_USER = 'nfse_app'
$env:NFSE_DB_PASSWORD = '<senha-do-banco>'
$env:NFSE_PORT = '9000'
$env:NFSE_BIND = '127.0.0.1'
```

Abra `backend/NfseBackend.dproj` no Delphi, compile e execute. As units estao referenciadas no projeto e as pastas `src` e `vendor/horse/src` ja estao no Search Path. O banco e acessado apenas nas rotas `/v1`; uma falha de banco nao encerra o servidor HTTP. CTRL+C encerra o servidor.

O padrao escuta apenas em localhost. Em containers, configure `NFSE_BIND=0.0.0.0` e publique somente por proxy HTTPS. Chaves de API sao para integracoes entre servidores. O frontend usa login por CNPJ/senha e encaminhamento de mesma origem pelo Nginx, sem habilitar CORS. Cadastro e bloqueio de empresas continuam administrativos pelo console privado.

## API

Todas as rotas `/v1` exigem `Authorization: Bearer <chave-da-empresa>`. A empresa vem da chave, nunca do corpo enviado. GET `/health` e publico e informa apenas que o processo HTTP esta ativo.

| Metodo | Rota | Funcao |
|---|---|---|
| GET / PATCH | `/v1/settings` | Consultar/alterar padroes |
| GET / POST | `/v1/customers` | Listar/cadastrar clientes |
| GET / POST | `/v1/drafts` | Listar/criar rascunhos |

GET de clientes e rascunhos retorna no maximo 100 registros. Ainda nao ha paginacao. Cliente exige nome e CPF/CNPJ somente em digitos; a validacao atual confere formato, nao digitos verificadores ou situacao cadastral. Campos fiscais aceitos: `tax_regime`, `service_code`, `service_description`, `simples_percent` e `iss_percent`. Os textos devem ser nao vazios e ter ate 500 caracteres; percentuais numericos entre 0 e 100. Dados municipais e validacoes fiscais serao adicionados na integracao real.

Salvar padrao (PATCH `/v1/settings`):

```json
{
  "tax_regime": "simples_nacional",
  "service_code": "CODIGO_DO_SEU_SERVICO",
  "service_description": "Descricao habitual do servico",
  "simples_percent": 6
}
```

Cadastrar cliente (POST `/v1/customers`):

```json
{"name":"Cliente de teste", "document":"00000000000"}
```

Criar rascunho (POST `/v1/drafts`):

```json
{"customer_id":"UUID_RETORNADO_NO_CADASTRO", "amount_cents":10000}
```

Para uma excecao naquela nota, acrescente `"overrides":{"simples_percent":8}`. Zero tambem e respeitado. Antes de criar um rascunho, regime, codigo e descricao devem estar configurados. A resposta retorna identificador, valor, configuracao aplicada e `status: draft`.

Erros: 400 JSON invalido, 401 chave ausente/invalida, 404 rota/metodo desconhecido, 409 cadastro duplicado, 422 dados invalidos ou configuracao incompleta, 503 falha de banco. Detalhes internos de banco e credenciais nao sao enviados ao cliente.

## Verificacao

Compilacao Win32 validada localmente. O teste de integracao requer API e PostgreSQL em execucao, com empresa exclusiva de testes (altera seus padroes e cria registros):

```powershell
.\backend\tests\api-smoke.ps1 -TestCompanyToken '<chave-teste>' -OtherCompanyToken '<chave-outra-empresa>'
```

O teste verifica heranca de 6%, mudanca para 8%, preservacao do historico, override zero, preservacao dos demais campos no PATCH, percentual invalido e isolamento entre empresas. Sem a segunda chave, a verificacao de isolamento e omitida. Nao foi executado nesta maquina porque nao ha PostgreSQL configurado.

## Proxima etapa fiscal

Geracao, assinatura, transmissao e consulta em homologacao foram verificadas nos ensaios locais com ACBr/Linux. A importacao do XML tambem foi validada no EasyPanel. A emissao direta de um rascunho pela API esta documentada em [backend/EMISSION-API.md](backend/EMISSION-API.md), com reserva de numeracao e bloqueio de reenvio automatico; requer migracao 004, perfil fiscal e volumes antes de habilitar. A integracao completa desse novo fluxo no servidor ainda precisa ser validada.

Permanecem pendentes cancelamento, multiplos usuarios por empresa e reconciliacao automatizada de envios inconclusivos. Rascunhos nao sao notas emitidas. O escopo atual permanece em homologacao.

Referencia tecnica: [conexao PostgreSQL com FireDAC](https://docwiki.embarcadero.com/RADStudio/Alexandria/en/Connect_to_PostgreSQL_%28FireDAC%29).
# Atualizacao: administracao, tomadores e filtros

- Acesso administrativo em `/admin.html`, separado do login por CNPJ.
- Cadastro de empresas, senha inicial, perfil fiscal opcional, bloqueio/liberacao e redefinicao de senha.
- Tomadores em caixa alta, preservando acentos.
- Filtro por data de emissao inicial/final nas notas, consultado no banco.

Antes de implantar esta versao em um banco existente, aplicar `backend/database/006_admin_and_filters.sql` e criar o administrador no console privado com `backend/database/bootstrap-admin.sql`. O bootstrap gera uma senha aleatoria, exibida uma vez. Detalhes em [backend/ADMIN.md](backend/ADMIN.md).

O repositorio contem fontes, testes e configuracoes de exemplo. Nao contem certificados, senhas reais, notas/XMLs de clientes nem executaveis compilados. Horse e distribuido como fonte com sua licenca MIT; a adaptacao ACBr preserva seu cabecalho LGPL e depende da instalacao ACBr/Delphi descrita abaixo.

Certificado A1 pela administracao, armazenamento criptografado e controle de proxima DPS por ambiente/serie: aplicar tambem a migracao 007 e seguir [as instrucoes de implantacao e backup](backend/CERTIFICATES-AND-NUMBERING.md). Configuracao de producao e somente preparacao; a emissao real permanece pendente.

