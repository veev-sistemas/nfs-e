#!/usr/bin/env bash
set -euo pipefail

test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
binary="${1:-$test_dir/AcbrLinuxProbe}"
if [[ ! -f "$binary" ]]; then
  printf 'Compile AcbrLinuxProbe.dproj para Linux antes de executar. Binario esperado: %s\n' "$binary"
  exit 1
fi
read -r -p 'Caminho Linux do PFX: ' NFSE_TEST_PFX
if [[ ! -f "$NFSE_TEST_PFX" ]]; then
  printf 'Arquivo PFX nao encontrado. Use o caminho /mnt/c/... no WSL.\n'
  exit 1
fi
read -r -s -p 'Senha do PFX (oculta): ' NFSE_TEST_PFX_PASSWORD
printf '\n'
export NFSE_TEST_PFX NFSE_TEST_PFX_PASSWORD
trap 'unset NFSE_TEST_PFX_PASSWORD NFSE_TEST_PFX' EXIT
OPENSSL_CONF="$test_dir/openssl-pfx-test.cnf" \
OPENSSL_MODULES=/usr/lib/x86_64-linux-gnu/ossl-modules \
"$binary"
