-- Executar no console privado psql APOS 006_admin_and_filters.sql.
-- Gera a senha no banco e mostra uma vez. Guarde em local privado.
-- Reexecutar redefine a senha e encerra todas as sessoes deste administrador.
WITH generated AS MATERIALIZED (
  SELECT encode(gen_random_bytes(18),'hex') AS initial_password
)
SELECT 'admin' AS usuario,
       initial_password AS senha_inicial,
       set_admin_password('admin',initial_password)
FROM generated;
