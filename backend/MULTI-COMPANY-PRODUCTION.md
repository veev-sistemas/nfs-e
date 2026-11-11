# Produção para várias empresas
A produção não depende mais de CNPJ piloto. NFSE_PRODUCTION_ALLOWED_CNPJ é ignorada; não é necessário trocar ou acrescentar CNPJs no ambiente do servidor.

NFSE_ENABLE_PRODUCTION=1 continua sendo a chave geral. Cada empresa precisa da liberação individual pelo administrador, certificado A1 válido correspondente ao CNPJ, perfil fiscal, série/sequência de produção e fontes do DANFSe. O isolamento por empresa e a confirmação explícita de emissão continuam ativos. Empresas novas começam bloqueadas. Cancelamento em produção exige servidor habilitado e liberação individual da empresa; consultas de tentativas existentes não reenviam eventos.

pilot_allowed permanece true na resposta apenas para compatibilidade com interfaces antigas; não controla acesso. O administrador mostra Servidor de produção.

Publicar primeiro o pacote atualizado no nfse-api e depois implantar nfse-web pelo GitHub. Sem migração de banco. Não altera liberação, série ou sequência de nenhuma empresa automaticamente.

Município e UF da DPS vêm do perfil fiscal da empresa, inclusive cUF do prestador. Removida a restrição inicial a Juiz de Fora/MG. O prefixo IBGE deve corresponder à UF; esta validação não confirma adesão do município ao ambiente nacional. Teste Pascal local com MG, RJ, SP e entradas divergentes, sem envio fiscal.
