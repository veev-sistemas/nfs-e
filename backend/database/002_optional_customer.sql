-- Aplicar uma vez no banco existente antes de publicar a API atualizada.
-- Preserva os clientes e os rascunhos existentes.
BEGIN;
ALTER TABLE drafts ALTER COLUMN customer_id DROP NOT NULL;
COMMIT;
