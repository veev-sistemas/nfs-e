# Contato, endereço e consulta CEP do tomador
Campos adicionais opcionais: phone, email, postal_code, municipality_code (IBGE), municipality_name, state_code (UF), district, street, house_number, complement. Permanecem obrigatórios nome e CPF/CNPJ. Telefone e e-mail independentes. Endereço pode ser todo vazio; se informado, o XML exige CEP, IBGE, UF, bairro, logradouro e número completos. Complemento e nome do município podem ficar vazios. CEP genérico pode não trazer bairro/logradouro: completar manualmente. Não se presume número ou complemento de unidade com base no CEP.

GET/POST /v1/customers incluem os dados. PATCH /v1/customers/:id substitui o cadastro completo (enviar nome/CPF-CNPJ e campos adicionais); pode limpar os opcionais. Todos os acessos são restritos à empresa autenticada. API verifica comprimentos, formato, UF/IBGE e endereço parcial. Cadastros antigos permanecem válidos.

GET /v1/postal-codes/:cep autenticado consulta ViaCEP por HTTPS (host fixo, CEP validado com oito dígitos, verificação TLS padrão, timeout de oito segundos, sem redirects). Apenas o CEP é enviado ao ViaCEP; nenhum nome/documento/contato. Falha ou CEP desconhecido mantém preenchimento manual. Interface protege contra resposta atrasada e alterações manuais durante a consulta.

A reserva de emissão grava um snapshot dos dados do tomador. Dados posteriores não alteram tentativas nem XMLs já emitidos. O XML envia contato e endereço quando presentes; DANFSe lê esses campos do XML. Não modifica notas antigas. Nome de município no DANFSe segue a informação disponível no XML; para município diferente do emitente, o renderizador apresenta o código IBGE.

## Implantação
1. Backup do banco de produção.
2. Aplicar database/011-customer-details.sql no banco nfse (transação, coluna jsonb details e atualização da função reserve_emission). Nenhuma emissão, numeração ou autorização é alterada.
3. Enviar build/nfse-api-tomador-cep.zip SOMENTE em nfse-api > Fonte > Upload. O ZIP contém binário com nome exclusivo e checksum obrigatório no Dockerfile.
4. Implantar nfse-web pelo GitHub main; recarregar com Ctrl+F5.

Esta etapa não foi implantada automaticamente. O pacote inclui a migração, mas não a executa. Não exige novo certificado nem alteração de parâmetros de produção.

## Validação
Compilação Linux, harness API em nfse_access_test com emissões desativadas, customer-details-regression.py (legado, opcionais, edição, erros, isolamento, snapshot), DpsNt009Probe + nt009-schema-regression.py, customer-documents-regression.py (XML e PDF fictício), busca real de CEP público de exemplo pela API local, cadastro/edição/preenchimento CEP na prévia fictícia. Nenhuma transmissão fiscal.
