# Consulta da NFS-e em homologacao

Rotina implementada em Homologacao.QueryHomologacao, chamada exclusivamente quando NFSE_TEST_QUERY=1. O script limpa as variaveis de emissao e chama ConsultarNFSePorChave do ACBr, que usa GET /nfse/{chave} na SEFIN de producao restrita.

```bash
bash /mnt/d/Fontes_Apps/Nfs-e/backend/tests/test-consulta.sh
```

A chave e lida do resultado.json da DPS 5 autorizada, sem redigitacao. Opcionalmente passe outra chave de homologacao como primeiro argumento. Se nao houver arquivo local ou argumento, o script solicita a chave. O PFX e a senha sao solicitados de forma interativa como nos testes anteriores. A consulta nao exige informar a chave da API do backend.

Cada consulta cria uma pasta privada em ~/nfse-testes/consultas. Salva resposta-original.txt, resultado.json e, quando recuperado com sucesso e chave correspondente, nfse-consultada.xml. Uma resposta sem XML ou com erros nao e apresentada como recuperacao confirmada. Nao sobrescreve os arquivos de autorizacao.

O executavel de teste precisa ser recompilado para Linux apos a alteracao. O script checa a capacidade VEEV_NFSE_CONSULTA_V1 antes de pedir o certificado. A consulta nao foi executada automaticamente com as credenciais do usuario; aguarda execucao interativa. A rota de consulta na API do EasyPanel ainda nao faz parte deste ensaio.
