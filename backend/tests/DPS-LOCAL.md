# Ensaio local da DPS

Este teste usa o mesmo projeto AcbrLinuxProbe.dproj com a unit LocalDps.pas. Recompile o projeto para Linux 64-bit no Delphi antes de executar. A configuracao publicada no EasyPanel nao e alterada.

No Ubuntu, instale as dependencias XML:

```bash
sudo apt update
sudo apt install libxml2-dev libxslt1-dev
```

Execute:

```bash
bash /mnt/d/Fontes_Apps/Nfs-e/backend/tests/test-dps-local.sh
```

Informe o caminho Linux do PFX e a senha quando solicitado. O script reutiliza a configuracao OpenSSL isolada do teste do certificado, ativa geracao local e grava em ~/nfse-testes/dps com permissoes restritas. Nao envie o PFX, senha ou XML assinado ao repositorio.

O teste gera XML sem assinatura, assina a tag infDPS, valida contra DPS_v1.01.xsd e verifica a assinatura. Cada execucao usa um nome de arquivo diferente. A numeracao interna da DPS e fixa e exclusiva de ensaio local: nao reutilizar estes XMLs para transmissao. O script nao chama endpoints nem o metodo Emitir.

Dados de referencia: prestador informado pelo usuario, servico nacional 090103, complemento municipal 002, NBS 103031100, Simples ME/EPP com regime de apuracao federal e municipal pelo Simples, operacao tributavel sem retencao de ISS. O percentual 13,46 corresponde ao campo de tributos aproximados do exemplo enviado; nao representa aliquota de ISS e nao atualiza o percentual dos rascunhos no banco. Valor sintetico R$ 100,00, sem tomador. A inscricao municipal foi omitida porque nao foi fornecida.

Schema e fontes ACBr utilizados: C:/ACBr, PadraoNacional/1.01. Passar no XSD e na verificacao de assinatura nao confirma validade cadastral, regras de negocio fiscais, habilitacao para emitir ou aceitacao pelo ambiente nacional. As regras de homologacao ainda serao verificadas antes de implementar a transmissao.

Estado da verificacao: fontes do ensaio compilados pela linha de comando ate a etapa de link; execucao e validacao do XML ainda pendentes no ambiente do usuario. O teste anterior de carregamento de A1 foi confirmado no Ubuntu.
