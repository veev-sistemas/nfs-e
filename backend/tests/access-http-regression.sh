#!/usr/bin/env bash
set -euo pipefail
# ROOT, local WSL test only. Never point this harness at a live database.
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d nfse_access_test <<'SQL'
DO $$ BEGIN
  IF NOT EXISTS(SELECT 1 FROM pg_roles WHERE rolname='nfse_access_runner') THEN
    CREATE ROLE nfse_access_runner LOGIN PASSWORD 'local-regression-only';
  END IF;
END $$;
GRANT CONNECT ON DATABASE nfse_access_test TO nfse_access_runner;
GRANT USAGE ON SCHEMA public TO nfse_access_runner;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO nfse_access_runner;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO nfse_access_runner;
GRANT EXECUTE ON FUNCTION login_company(text,text) TO nfse_access_runner;
GRANT EXECUTE ON FUNCTION login_admin(text,text) TO nfse_access_runner;
GRANT EXECUTE ON FUNCTION set_company_password(uuid,text),set_company_access(uuid,boolean) TO nfse_access_runner;
TRUNCATE admin_users CASCADE;
SELECT set_admin_password('regression-admin','Admin-regression-2026');
TRUNCATE companies CASCADE;
INSERT INTO companies(name,document) VALUES('Access regression','99999999999999');
SELECT set_company_password(id,'Regression-password-2026') FROM companies WHERE document='99999999999999';
SQL
NFSE_PORT=19002 NFSE_BIND=127.0.0.1 NFSE_DB_HOST=127.0.0.1 NFSE_DB_PORT=5432 \
 NFSE_DB_NAME=nfse_access_test NFSE_DB_USER=nfse_access_runner \
 NFSE_DB_PASSWORD=local-regression-only "$root/build/linux-api/NfseBackend" >/tmp/nfse-access-http.log 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true' EXIT
for n in {1..50}; do
  if curl -fsS http://127.0.0.1:19002/health >/dev/null 2>&1; then break; fi
  sleep 0.1
done
python3 "$root/tests/access-http-regression.py"
python3 "$root/tests/admin-and-filters-regression.py"
if [[ "${NFSE_QA_KEEP_ALIVE:-0}" == "1" ]]; then
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d nfse_access_test -c "UPDATE admin_users SET enabled=true,failed_attempts=0,locked_until=NULL WHERE username='regression-admin'" >/dev/null
  echo 'QA local pronta em 127.0.0.1:19002; finalizar este processo encerra a API.'
  wait "$pid"
fi
