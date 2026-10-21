-- Forma de pagamento para controle interno. Não altera XML ou valores fiscais.
BEGIN;
ALTER TABLE drafts ADD COLUMN IF NOT EXISTS payment_method text
  CHECK (payment_method IN ('dinheiro','pix','boleto','cartao_credito','cartao_debito'));
COMMIT;
