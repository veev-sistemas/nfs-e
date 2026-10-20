# Primeiro envio nacional em homologacao

No ensaio 4, a SEFIN retornou E0008: dhEmi 19:08:56-03:00 e processamento 19:08:53-03:00, ambos de 15/10/2026. O teste passou a usar margem de 30 segundos em dhEmi para tolerar essa diferenca. Este ajuste pertence exclusivamente ao gerador de ensaio e nao deve ser usado como regra automatica de datas na API definitiva.

Esta etapa e separada da API no EasyPanel. Recompile AcbrLinuxProbe.dproj para Linux 64-bit no Delphi. O script verifica uma identificacao de versao para impedir a execucao acidental do teste antigo.

```bash
bash /mnt/d/Fontes_Apps/Nfs-e/backend/tests/test-homologacao.sh 1
```

Ao executar, sera transmitida uma DPS com CNPJ do prestador do ensaio, serie 900, numero fornecido, R$ 100,00 e sem tomador para o ambiente nacional de producao restrita. O PFX e sua senha sao solicitados pelo mesmo script do teste local. Nenhuma credencial e escrita no codigo ou ZIP.

O programa primeiro gera, assina e valida localmente a DPS; depois chama Emitir do ACBr em modo unitario. O ACBr monta JSON/GZip/Base64 e usa certificado cliente. O ambiente e fixado em homologacao e um INI dedicado contem somente HomRecepcionar=https://sefin.producaorestrita.nfse.gov.br/SefinNacional. Nenhum endereco de producao e incluido nesse INI.

Cada numero e reservado atomicamente no diretorio ~/nfse-testes/homologacao/serie-900/dps-N. O estado, XMLs e resultado.json permanecem nesse diretorio. A resposta original e armazenada localmente. Os arquivos contem dados fiscais: nao publica-los no repositorio ou no ZIP. Uma segunda execucao com o mesmo numero e bloqueada. Se a falha ocorrer antes do envio, verificar o estado antes de decidir a proxima tentativa.

Nao ha retry automatico. Em timeout/erro de transporte, o resultado pode ser indeterminado: consultar a DPS antes de reenviar ou gerar outro numero para a mesma operacao. A consulta de reconciliacao ainda nao foi implementada neste ensaio. Uma resposta sem chave de acesso nao e apresentada como autorizada.

Referencias verificadas em 15/10/2026:
- https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/apis-prod-restrita-e-producao
- https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/producao-restrita
- Fontes e configuracao em C:/ACBr/Fontes/ACBrDFe/ACBrNFSeX.

Estado: sintaxe do script verificada; fontes Pascal compilados ate a fase de link na linha de comando. O linker local nao executou por essa via; concluir o Build pelo Delphi com o SDK configurado. O envio ainda nao foi executado. A validacao local bem-sucedida anterior nao garante aceitacao de regras de negocio do ambiente nacional. O teste nao muda percentuais ou status de rascunhos no PostgreSQL.
