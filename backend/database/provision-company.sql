-- psql -v company_name='Empresa teste' -v company_document='00000000000000' -v api_token='CHAVE_ALEATORIA_DE_PELO_MENOS_32_CARACTERES' -f database/provision-company.sql
-- Use uma chave gerada com fonte criptografica; mantenha-a no servidor do frontend.
BEGIN;
WITH company AS (
  INSERT INTO companies(name, document)
  VALUES (:'company_name', :'company_document') RETURNING id
)
INSERT INTO api_keys(company_id, token_hash)
SELECT id, encode(digest(:'api_token', 'sha256'), 'hex') FROM company;
COMMIT;
