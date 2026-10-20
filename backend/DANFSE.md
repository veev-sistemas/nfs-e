# DANFSe local - homologacao

A API nacional de geracao do DANFSe foi suspensa em 03/08/2026. A NT 008 v1.02 determina geracao pelo sistema emissor. Referencias oficiais:

- https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/rtc/nt-008-se-cgnfse-danfse-20260714-v1-02.pdf
- https://www.gov.br/nfse/pt-br/biblioteca/documentacao-tecnica/atualizacoes-e-implantacoes/atualizacoes-e-implantacoes

GET /v1/invoices/:id/pdf continua autenticado pela chave Bearer da empresa. Consulta id e company_id antes de ler o XML do banco. O PDF e criado a partir desse XML, conferindo chave e CNPJ com a nota solicitada. Nenhuma URL ou documento fiscal e aceito do corpo da requisicao. Nao utiliza certificado, senha ou rede e nao emite nem reenvia DPS.

O backend chama download-danfse.sh em processo separado (posix_spawn com argumentos individuais e limite de 90 segundos); o auxiliar executa render-danfse.py. ReportLab e fontes livres sao instalados pela imagem. NFSE_DATA_DIR e necessario; NFSE_ENABLE_HOMOLOGATION nao controla a visualizacao. XML e PDF ficam em diretorio exclusivo por requisicao, sob empresa/danfse no volume persistente. O diretorio e restrito a 700 e o auxiliar usa umask 077. O retorno e application/pdf, download attachment, no-store e nosniff. Falhas do renderizador retornam 502, com detalhes administrativos em renderer-error.txt. A nota armazenada nao e alterada.

## Escopo e limites

Este e o renderizador inicial de HOMOLOGACAO para o XML nacional 1.01 regular (cStat 100), como o ensaio CARLTON. Bloqueia producao, DTD/entidades, XML acima de 512 KiB, CNPJ/chave divergentes, perfis IBS/CBS fora do escopo implementado, retorno IBS/CBS incompleto e conteudo que nao caiba nos campos. O conteudo fiscal vem do XML; campos ausentes exibem traco. Documentos com cancelamento/substituicao posterior exigem consulta de eventos e marcas d'agua, ainda nao implementadas. Nao ha declaracao de conformidade completa para producao.

O modelo segue o Anexo I da NT 008 v1.02: A4, pagina unica, cabecalho de homologacao, logotipo oficial, QR Code e blocos na ordem especificada. Campos ausentes de tomador/destinatario/intermediario sao condensados; o espaco e acrescentado a descricao. O canhoto opcional e omitido. Numeros e datas nao sao substituidos por valores da configuracao ou do computador. Tributos SN nao sao repartidos artificialmente entre esferas.

As fontes normativas sao Arial e Microsoft Sans Serif. O renderizador procura arial.ttf, arialbd.ttf e micross.ttf em NFSE_DANFSE_FONT_DIR (padrao /var/lib/nfse/fonts), ou C:/Windows/Fonts no teste local. Nao sao distribuidas fontes proprietarias no ZIP. Sem essas fontes, usa Liberation Sans na previa de homologacao Linux; essa substituicao fica registrada em renderer-status.txt e precisa ser resolvida antes da validacao de conformidade para producao.

## Validacao realizada

Em 2026-10-19: PDF real da nota de homologacao 2 gerado e renderizado para revisao visual em Windows com fontes normativas e em Linux com as dependencias da imagem. Conferidos pagina unica, identificacao, QR Code, valor R$100,00 e ausencia de sobreposicoes. Testes sinteticos em danfse-renderer-regression.py verificam texto literal/acentos e rejeicao de documento/chave/hash divergente, DTD, producao e IBS/CBS incompleto. A regressao sintetica nao certifica o cumprimento de todas as regras fiscais. O primeiro download integrado no EasyPanel ainda deve ser confirmado apos atualizacao do ZIP.

## Download no PowerShell

```powershell
$pdf = Join-Path ([Environment]::GetFolderPath('Desktop')) 'danfse-homologacao-2.pdf'
Invoke-WebRequest -UseBasicParsing -Uri "$dominio/v1/invoices/$notaId/pdf" -Headers $headers -OutFile $pdf -TimeoutSec 120 -ErrorAction Stop
Start-Process -FilePath $pdf
```

Nenhuma migracao de banco e necessaria.
## IBS/CBS de hospedagem (20/10/2026)

O renderizador aceita o perfil autorizado em homologacao com CST 200, cClassTrib 200048, cIndOp 030101 e indDest=0. Le CST e classificacao em IBSCBS/valores/trib (ou gIBSCBS no leiaute anterior). Aliquotas, reducoes, base e valores monetarios sao extraidos de infNFSe/IBSCBS; campos obrigatorios ausentes ou nao finitos sao recusados. Nao calcula novos tributos nem altera o XML assinado. Perfis com ajustes, credito e diferimento continuam fora do escopo.

Mapeamento NT008: base em valores/vBC; IBS UF e municipal em valores/uf e valores/mun; CBS em valores/fed; apurados em totCIBS/gIBS/gIBSUFTot/vIBSUF, gIBSMunTot/vIBSMun, gIBS/vIBSTot e gCBS/vCBS. Total IBS/CBS e a soma dos dois totais retornados. O campo final usa exatamente totCIBS/vTotNF, sem somar impostos novamente a vLiq. Descontos/exclusoes usam o somatorio previsto no Anexo I. indDest=0 imprime destinatario igual ao tomador.

Validado com regressao sintetica (com/sem IBS/CBS, zero municipal preservado, aliquotas e reducoes, vTotNF sem recarculo, retorno incompleto/NaN/perfil divergente rejeitados) e XML autorizado da DPS9. PDF real em pagina unica revisado visualmente com Arial/Microsoft Sans Serif e Liberation Sans no Linux. O auxiliar download-danfse.sh foi exercitado com a chave e CNPJ do XML. Atualizar apenas nfse-api; nenhuma migracao ou nova emissao e necessaria para baixar o PDF da nota ja autorizada.
