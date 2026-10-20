#!/usr/bin/env bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
number="${1:-}"
binary="$test_dir/AcbrLinuxProbe"
if [[ ! -f "$binary" ]] || [[ "$(env -u NFSE_TEST_PFX -u NFSE_TEST_SEND "$binary" --capabilities)" != 'VEEV_NFSE_HOMOLOGACAO_V2' ]]; then
  printf 'Recompile AcbrLinuxProbe.dproj para Linux: executavel de homologacao atualizado nao encontrado.\n'
  exit 1
fi
if [[ ! "$number" =~ ^[1-9][0-9]{0,14}$ ]]; then
  printf 'Uso: bash test-homologacao.sh NUMERO_DPS (inteiro positivo de ate 15 digitos).\n'
  exit 1
fi
export NFSE_TEST_SCHEMAS=/mnt/c/ACBr/Exemplos/ACBrDFe/Schemas/NFSe/PadraoNacional/1.01
"$binary" --check-config
umask 077
attempt="$HOME/nfse-testes/homologacao/serie-900/dps-$number"
mkdir -p "$(dirname -- "$attempt")"
if ! mkdir "$attempt"; then
  printf 'Numero ja reservado neste computador. Verifique a tentativa anterior antes de reenviar: %s\n' "$attempt"
  exit 1
fi
export NFSE_TEST_SEND=HOMOLOGACAO NFSE_TEST_DPS=1 NFSE_TEST_DPS_NUMBER="$number"
export NFSE_TEST_SCHEMAS=/mnt/c/ACBr/Exemplos/ACBrDFe/Schemas/NFSe/PadraoNacional/1.01
export NFSE_TEST_OUTPUT="$attempt"
printf 'Transmissao para HOMOLOGACAO nacional: CNPJ 16783003000189, serie 900, DPS %s, R$ 100,00, sem tomador.\n' "$number"
bash "$test_dir/test-certificate.sh"
