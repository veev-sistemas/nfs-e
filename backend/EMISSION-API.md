# Emissao de homologacao pela API

Correcao E1235/cNBS de 20/10/2026: o grupo cServ passa a seguir cTribNac, cTribMun opcional, cNBS, cIntContrib opcional, xDescServ, no fluxo suportado. Nao remove NBS nem muda seu valor para contornar a regra. Testes offline verificam a geracao com/sem tomador e rejeitam a ordem anterior no perfil XSD local atualizado. Isso e independente da pendencia E0855 e nao implementa o envio completo IBS/CBS.

Parametros opcionais: `send_ibs_cbs` booleano (ausente = false), `cst_ibs_cbs` texto com tres digitos, `cclass_trib` e `cind_op` textos com seis digitos. Preservar zeros iniciais. Perfil IBS/CBS implementado somente em homologacao regular de hospedagem: CST `200`, cClassTrib `200048`, cIndOp `030101`, destinatario igual ao tomador. Outros perfis sao recusados antes de reservar numeracao. A escolha e os codigos ficam no snapshot de cada novo rascunho; mudar os parametros nao altera o historico. Desmarcado nao gera IBSCBS nem contorna E0855. Sem ativacao automatica por data. O gerador escreve cIndOp em IBSCBS e CST/cClassTrib em IBSCBS/valores/trib, conforme Anexo VI NT009 v1.04.01, linhas 375 e 423-425. Sem valores de imposto inventados, ajustes, credito presumido ou diferimento. A autorizacao depende da validacao da SEFIN. O renderizador PDF local aceita este perfil IBS/CBS com base nos valores retornados no XML autorizado; consultar DANFSE.md.

Atualizacao 20/10/2026: gerador local de compatibilidade NT009 inclui finNFSe=0 em infDPS antes de cLocEmi. O schema embarcado possui o mesmo requisito no perfil regular de homologacao. Ver `vendor/acbr-compat/README.md` para origem e limites. Erros novos incluem o complemento retornado pelo provedor, exibido no frontend. Tentativas rejeitadas anteriores nao sao alteradas nem reenviadas.

## Preparacao

Aplicar 004_emission_attempts.sql depois de 003, e depois configure-carlton-homologation.sql. Esse cadastro usa os dados fornecidos pelo usuario e a serie 901, separada da serie 900 dos ensaios. Nao modifica rascunhos antigos. A inscricao municipal permanece ausente e o escopo inicial e Simples ME/EPP em Juiz de Fora, sem regime especial e sem retencao de ISS. Outras situacoes fiscais ainda nao sao atendidas por este fluxo.

Reimplantar o ZIP atualizado. A imagem inclui schemas 1.01 e bibliotecas ACBr/OpenSSL/XML; nao contem certificados. O sistema inicia normalmente com NFSE_ENABLE_HOMOLOGATION=0. A emissao fica indisponivel ate sua habilitacao explicita.

Configurar armazenamento persistente privado em /var/lib/nfse e montar certificados em /run/nfse-certificates. O usuario do container UID 10001 deve poder escrever no primeiro e ler no segundo. O volume de certificados deve ser protegido por permissoes e backup apropriados e, se possivel, montado somente para leitura. PFX e senha nunca devem entrar no ZIP, repositorio ou corpo de uma chamada publica.

Para cada empresa, colocar dois arquivos no volume privado, usando seu UUID do cadastro:
- UUID.pfx: certificado A1 binario.
- UUID.password: senha do certificado. Apenas a quebra de linha final e removida.

O arquivo de senha e um segredo em texto no volume privado: utilizar armazenamento de segredos da infraestrutura, controle de acesso e criptografia de disco quando disponiveis. Nao e um cofre criptografado desenvolvido pela aplicacao. Este fluxo ainda nao e gerenciamento comercial de certificados multiusuario.

Variaveis da imagem:

```env
NFSE_ENABLE_HOMOLOGATION=0
NFSE_SCHEMAS_DIR=/app/schemas
NFSE_DATA_DIR=/var/lib/nfse
NFSE_CERTIFICATES_DIR=/run/nfse-certificates
```

So alterar NFSE_ENABLE_HOMOLOGATION para 1 depois de montar os segredos e persistencia. As demais variaveis PostgreSQL permanecem como antes. Os diretorios do Dockerfile nao substituem a montagem de volumes: arquivos apenas no container podem desaparecer em nova implantacao.

## Chamadas

Criar novo rascunho com a chave CARLTON, depois do cadastro dos padroes corretos. Nao usar os rascunhos antigos com codigo TESTE.

POST /v1/drafts/:id/emit-homologation recebe:

```json
{"issued_at":"2026-10-16T10:00:00-03:00","competence":"2026-10-16"}
```

Essas datas sao ilustrativas; informar a data efetiva da operacao, com fuso, e sua competencia. Nao ha subtracao automatica de segundos no fluxo da API. A data de emissao nao pode ser futura. O rascunho fornece valor, servico e tomador opcional. O perfil fornece prestador e tributacao inicial. approx_simples_percent e o percentual para tributos aproximados; simples_percent nao e convertido em aliquota de ISS.

O banco reserva uma tentativa e numero por rascunho, serializando a numeracao da empresa. Repetir a chamada devolve a tentativa existente sem enviar novamente. A API gera e valida a DPS, salva o XML antes do envio, marca sending e chama ACBr no ambiente fixo de homologacao. Chamadas ACBr sao serializadas dentro de cada processo; a reserva no PostgreSQL protege contra duplicacao entre replicas.

GET /v1/emission-attempts/:id retorna a tentativa da empresa autenticada. Estados: reserved, prepared, sending, authorized, rejected, unknown e local_error. Qualquer um deles bloqueia novo envio do mesmo rascunho. Nao ha retry automatico nem recuperacao automatica de processos interrompidos. Falha de comunicacao ou resposta ambigua requer consulta e conciliacao antes de outra emissao para a mesma operacao. O endpoint de conciliacao ainda nao foi implementado.

Quando ha autorizacao com chave e XML, a API grava a nota na tabela invoices com status authorized_homologation e source sefin_api, vinculada ao draft_id. Dados de tentativa e nota sao confirmados em uma transacao. Se a persistencia falhar depois do envio, arquivos no volume privado permitem recuperacao manual e a tentativa nao e reenviada. A API nao transforma o rascunho original nem apaga seu snapshot.

Em local_error, verifique a configuracao e o resultado da tentativa antes de decidir o procedimento seguinte. Nenhuma falha e apresentada como autorizacao. Mensagens de validacao ficam no resultado; erros internos nao retornam credenciais ou caminhos do servidor.

## Validacao

Correcao de 2026-10-19: verAplic reduzido para VEEV-API-1.0, validado contra TSVerAplic do schema 1.01. Os caminhos internos de arquivos do ACBr (PathSalvar, PathGer, PathRPS, PathNFSe e PathCan) agora apontam para o diretorio persistente da tentativa, evitando o padrao ApplicationPath/Docs sem permissao de escrita no container. Excecoes retornam etapa e classe, sem mensagem interna ou credenciais. Essa mudanca nao reenvia nem altera tentativas anteriores. Um HTTP 404/E2404 na consulta significa que a NFS-e nao foi encontrada naquele momento; nao transforma automaticamente unknown em rejected nem libera reenvio.

Compilacao Linux 64-bit concluida em 2026-10-16. Smoke HTTP local passou: /health e autenticacao obrigatoria nas rotas de notas e tentativas. Scripts Bash e PowerShell passaram na verificacao de sintaxe. O ZIP foi conferido com executavel, Dockerfile, schemas e configuracao OpenSSL, sem PFX ou arquivos de senha. Nao houve transmissao durante esses checks. Testes SQL ainda nao executados localmente por falta de PostgreSQL.

Testes de reserva em tests/emission-reservation-regression.sql (executar em banco de teste com rollback). Validacao real de ponta a ponta ainda depende das migracoes, volumes, A1 e habilitacao no EasyPanel. Nao executar emissao para producao: este codigo nao oferece essa opcao.

Compatibilidade SEFIN em 20/10/2026: a DPS8 rejeitou indDest diretamente em infDPS (E1235; esperados toma/interm/serv). O gerador e o schema local agora colocam indDest=0 em IBSCBS, apos cIndOp, preservando finNFSe=0 em infDPS. Este perfil acompanha o ambiente observado; nao se presume implantacao integral da planilha NT009. A confirmacao de autorizacao continua dependendo de novo teste em homologacao.
