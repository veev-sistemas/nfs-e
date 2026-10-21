#!/usr/bin/env bash
set -euo pipefail
# ROOT, local WSL test only. Never point this harness at a live database.
root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d nfse_access_test -f "$root/database/010-payment-method.sql"
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
GRANT EXECUTE ON FUNCTION reserve_cancellation(uuid,uuid,integer,text),finish_cancellation(uuid,uuid,text,jsonb,text) TO nfse_access_runner;
TRUNCATE admin_users CASCADE;
SELECT set_admin_password('regression-admin','Admin-regression-2026');
TRUNCATE companies CASCADE;
INSERT INTO companies(name,document) VALUES('Access regression','99999999999999');
SELECT set_company_password(id,'Regression-password-2026') FROM companies WHERE document='99999999999999';
SQL
private_data="$(mktemp -d /tmp/nfse-certificate-regression.XXXXXXXX)"
export NFSE_QA_DATA="$private_data"
mkdir -m 700 "$private_data/certificates"
NFSE_DATA_DIR="$private_data" NFSE_CERTIFICATES_DIR="$private_data/certificates" NFSE_CERTIFICATE_HELPER="$root/deploy/manage-certificate.py" \
NFSE_ENABLE_PRODUCTION=0 NFSE_ENABLE_HOMOLOGATION=0 NFSE_SCHEMAS_DIR="$root/deploy/schemas" \
NFSE_PORT=19002 NFSE_BIND=127.0.0.1 NFSE_DB_HOST=127.0.0.1 NFSE_DB_PORT=5432 \
 NFSE_DB_NAME=nfse_access_test NFSE_DB_USER=nfse_access_runner \
 NFSE_DB_PASSWORD=local-regression-only "$root/build/linux-api/NfseBackend" >/tmp/nfse-access-http.log 2>&1 &
pid=$!
trap 'result=$?; if [[ "$result" != 0 ]]; then cat /tmp/nfse-access-http.log; fi; kill "$pid" 2>/dev/null || true; rm -rf -- "$private_data"' EXIT
for n in {1..50}; do
  if curl -fsS http://127.0.0.1:19002/health >/dev/null 2>&1; then break; fi
  sleep 0.1
done
python3 "$root/tests/access-http-regression.py"
python3 "$root/tests/admin-and-filters-regression.py"
python3 "$root/tests/numbering-and-certificates-http.py"
python3 "$root/tests/production-regression.py"
python3 "$root/tests/environment-cancellation-regression.py"
python3 "$root/tests/saved-cancellation-regression.py"
python3 "$root/tests/payment-totals-regression.py"
if [[ "${NFSE_QA_KEEP_ALIVE:-0}" == "1" ]]; then
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d nfse_access_test -c "UPDATE admin_users SET enabled=true,failed_attempts=0,locked_until=NULL WHERE username='regression-admin'" >/dev/null
  echo 'QA local pronta em 127.0.0.1:19002; finalizar este processo encerra a API.'
  wait "$pid"
fi
