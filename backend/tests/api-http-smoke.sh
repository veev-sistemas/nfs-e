#!/usr/bin/env bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
binary="$test_dir/../build/linux-api/NfseBackend"
log="$(mktemp)"
NFSE_PORT=19001 NFSE_BIND=127.0.0.1 "$binary" >"$log" 2>&1 &
pid=$!
trap 'kill "$pid" 2>/dev/null || true; rm -f "$log"' EXIT
for n in {1..30}; do
  if curl -fsS http://127.0.0.1:19001/health >/dev/null 2>&1; then break; fi
  sleep 0.1
done
for route in /v1/invoices /v1/invoices/00000000-0000-0000-0000-000000000000 /v1/invoices/00000000-0000-0000-0000-000000000000/xml /v1/invoices/00000000-0000-0000-0000-000000000000/pdf /v1/emission-attempts/00000000-0000-0000-0000-000000000000; do
  status="$(curl -sS -o /dev/null -w '%{http_code}' "http://127.0.0.1:19001$route")"
  [[ "$status" == 401 ]] || { printf 'Rota sem protecao esperada: %s HTTP %s\n' "$route" "$status"; exit 1; }
done
status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:19001/v1/invoices/import-homologation)"
[[ "$status" == 401 ]]
status="$(curl -sS -o /dev/null -w '%{http_code}' -X POST http://127.0.0.1:19001/v1/drafts/00000000-0000-0000-0000-000000000000/emit-homologation)"
[[ "$status" == 401 ]]
printf 'OK: health responde e todas as rotas de notas exigem autenticacao.\n'
