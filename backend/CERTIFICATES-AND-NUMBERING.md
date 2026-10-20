# Certificado A1 e numeracao DPS

## Implantacao

1. Aplicar `database/007-dps-sequences.sql` no Postgres Client, depois das migracoes 001 a 006. Fazer backup antes. Aplicar uma unica vez: a migracao importa os contadores atuais e preserva as tentativas existentes.
2. Caso use papel de banco limitado, conceder SELECT, INSERT e UPDATE em `dps_sequences` ao papel da API. O trigger do perfil fiscal tambem precisa dessas permissoes.
3. Implantar os pacotes backend/frontend desta versao. O Dockerfile instala `python3-cryptography` e copia `manage-certificate.py`.
4. Manter `NFSE_DATA_DIR=/var/lib/nfse` em volume persistente. Usar `NFSE_CERTIFICATES_DIR=/var/lib/nfse/certificados`, diretorio privado pertencente ao UID 10001. Nao expor esses diretorios pelo servidor web.
5. Em `/admin.html`, localizar a empresa e usar **Numeracao DPS** ou **Certificado A1**.

O escopo da emissao continua sendo homologacao. Configurar uma sequencia de producao apenas prepara o contador: nao cria rota de emissao real, nao muda o ambiente das notas e nao transmite documentos. A empresa CARLTON sera o piloto de producao quando esse fluxo for implementado e validado.

## Numeracao e concorrencia

O campo indica a proxima **DPS**, nao o numero da NFS-e atribuido pela SEFIN. Se a ultima DPS da mesma serie foi 500, configurar 501. Conferir a sequencia tambem em outros emissores; preferir uma serie exclusiva por emissor quando permitido pelo provedor.

O banco preserva uma sequencia por empresa/ambiente/serie. Trocar de serie nao apaga a anterior. A configuracao administrativa e a reserva usam a mesma trava no perfil fiscal. A atualizacao exige o valor anteriormente consultado (`expected_next_number`, texto ou null para serie nova); uma tela desatualizada recebe HTTP 409. Nao e permitido reduzir o proximo numero. Serie e numero sao strings de digitos, sem zeros a esquerda, com limites de cinco e quinze digitos.

Reservar uma tentativa consome o numero mesmo se ela for rejeitada ou falhar depois. O banco impede numero repetido e duas tentativas para o mesmo rascunho. Requisicoes repetidas retornam a tentativa existente; resultados desconhecidos nao sao reenviados automaticamente. Criar outro rascunho para o mesmo servico pode gerar outra nota: a identidade comercial da operacao ainda deve ser controlada pela integracao. A sequencia local nao coordena outro software externo.

Rotas administrativas:

- `GET /v1/admin/companies/:id/numbering`: serie ativa de homologacao e sequencias conhecidas.
- `PATCH /v1/admin/companies/:id/numbering`: `{environment, series, next_number, expected_next_number}`. Ambientes `homologacao` e `producao`. Em homologacao a serie escolhida passa a ser ativa. Producao e somente preparacao.

## Certificados e armazenamento

`GET /v1/admin/companies/:id/certificate` retorna somente metadados publicos. `POST` recebe `{pfx_base64, password}`, limitado a PFX/P12 de 512 KiB. A senha pode ser vazia se o arquivo assim exigir. Nenhuma dessas rotas aceita sessao empresarial ou chave de integracao.

Antes da troca, o worker verifica abertura do PKCS12, presenca e correspondencia da chave privada, validade temporal, CNPJ no OtherName ICP-Brasil OID 2.16.76.1.3.3, restricao de CA e uso de assinatura quando presentes. Isso nao substitui validacao da cadeia ICP-Brasil ou consulta de revogacao pelo provedor. Testes usam exclusivamente certificados ficticios.

O PFX e a senha sao criptografados juntos com AES-256-GCM em `<NFSE_CERTIFICATES_DIR>/<UUID>.a1.enc`. A autenticacao criptografica vincula empresa e CNPJ; alteracoes do arquivo impedem a leitura. A troca do arquivo usa renomeacao atomica depois da validacao. Uma troca invalida preserva o certificado anterior. O evento administrativo nao contem a senha. O arquivo e o banco sao armazenamentos separados: a troca atomica do arquivo nao e uma transacao distribuida com o registro de auditoria.

A chave aleatoria de armazenamento e criada uma vez em `<NFSE_DATA_DIR>/.secrets/certificates.key`, com permissao 600. O diretorio tem permissao 700. **O backup privado precisa incluir a chave e os arquivos criptografados**. Nao apagar/rotacionar a chave manualmente: os arquivos se tornam ilegíveis. Se ja houver arquivo criptografado, a ausencia da chave falha de forma segura.

A assinatura utiliza uma copia temporaria privada, removida ao concluir a chamada, com timeout do worker. Uma troca concorrente nao mistura arquivo e senha da emissao que ja iniciou. O volume deve permanecer privado e persistente. Uma queda abrupta do processo pode deixar diretorios privados em `certificate-requests`; remover somente com a API parada e depois de conferir o caminho. Nao enviar certificados, chaves, senhas ou backups ao GitHub.

Compatibilidade: se nao existir o arquivo criptografado, o servidor consulta os arquivos anteriores `<UUID>.pfx` e `<UUID>.password`. Eles nao sao apagados automaticamente; depois de instalar o novo certificado, o criptografado tem prioridade. Os arquivos legados continuam contendo material sensivel e devem permanecer privados ate uma limpeza/backup controlado.

## Validacao local

- `tests/certificates-regression.py`: certificados gerados localmente, senha/CNPJ/validade/chave privada, criptografia, integridade, chave perdida, preservacao na troca e legado.
- `tests/access-http-regression.sh`: somente banco isolado `nfse_access_test`; cobre acesso, cadastro, datas, sequencias concorrentes, repeticao de reserva e upload administrativo. Nunca usar com dados de clientes.

Nenhum desses testes transmite uma nota.
