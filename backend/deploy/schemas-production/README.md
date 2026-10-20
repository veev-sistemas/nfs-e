# Schemas de producao

Origem: pacote oficial `NFSe-ESQUEMAS_XSD-v1.01-20260209`, pasta `Schemas/1.01`, obtido em 20/10/2026 na [documentacao atual de producao](https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/documentacao-atual/documentacao-atual).

Download: https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/documentacao-atual/nfse-esquemas_xsd-v1-01-20260209.zip

SHA-256 do ZIP original: `e7935cbd9470527c6cc32984c1b2263e614183bf0139ce2733eaaed2de9a8072`.

Compatibilidade libxml2: em `tiposSimples_v1.01.xsd`, somente o pattern de `TSSerieDPS` foi normalizado de `^0{0,4}\d{1,5}$` para `0{0,4}[0-9]{1,5}`. Em XML Schema regex, os caracteres `^`/`$` nao funcionam como ancoras e o original rejeita series numericas normais no libxml2. O limite de cinco caracteres foi preservado; a API exige digitos ASCII. SHA-256 do arquivo original antes dessa alteracao: `830ea116c34d7310699e34b214b7214a65f7e5d3b1f09aeaa702f7e3f4283b17`.

Nao substituir este conjunto pelo schema de homologacao NT009. Producao usa `xDescServ` antes de `cNBS` e `finNFSe` dentro de `IBSCBS`, com o agrupador `trib/gIBSCBS`. Os testes offline verificam os dois ambientes, com e sem IBS/CBS.
