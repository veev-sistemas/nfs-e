# Código municipal opcional
municipal_service_code aceita texto vazio ou três dígitos. Vazio não gera cTribMun no XML; o schema nacional v1.01 define minOccurs=0 e o gerador ACBr já omite o nó vazio. A aplicação não determina automaticamente o código fiscal de cada município.

Publicar o pacote nfse-api-codigo-municipal-opcional.zip somente no nfse-api, depois implantar nfse-web pelo GitHub. Sem migração. Configurações e rascunhos existentes não são alterados automaticamente.

Para uma empresa sem código municipal aplicável, apagar o campo em Configurações e salvar; criar novo rascunho para usar os novos padrões. Não reutilizar números de DPS reservados. Omitir código não garante autorização pela SEFIN: depende das regras do município.
