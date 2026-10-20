#!/usr/bin/env bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export NFSE_TEST_DPS=1
export NFSE_TEST_SCHEMAS=/mnt/c/ACBr/Exemplos/ACBrDFe/Schemas/NFSe/PadraoNacional/1.01
export NFSE_TEST_OUTPUT="$HOME/nfse-testes/dps"
umask 077
bash "$test_dir/test-certificate.sh" "$@"
