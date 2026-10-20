#!/usr/bin/env bash
set -euo pipefail
test_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
binary="$test_dir/AcbrLinuxProbe"
if [[ ! -f "$binary" ]] || [[ "$(env -u NFSE_TEST_PFX "$binary" --capabilities-query)" != 'VEEV_NFSE_CONSULTA_V1' ]]; then
  printf 'Executavel de consulta desatualizado. Recompile AcbrLinuxProbe para Linux.\n'
  exit 1
fi
umask 077
source_result="$HOME/nfse-testes/homologacao/serie-900/dps-5/resultado.json"
key="${1:-}"
if [[ -z "$key" && -f "$source_result" ]]; then
  key="$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1],encoding="utf-8-sig")); assert d.get("ambiente")=="homologacao" and d.get("sucesso_acbr") is True; print(d["chave_acesso"])' "$source_result")"
fi
if [[ -z "$key" ]]; then
  read -r -p 'Chave de acesso da NFS-e de homologacao (50 digitos): ' key
fi
if [[ ! "$key" =~ ^[0-9]{50}$ ]]; then
  printf 'Chave invalida: esperados 50 digitos.\n'
  exit 1
fi
export NFSE_TEST_QUERY=1 NFSE_TEST_ACCESS_KEY="$key"
unset NFSE_TEST_SEND NFSE_TEST_DPS NFSE_TEST_DPS_NUMBER
export NFSE_TEST_SCHEMAS=/mnt/c/ACBr/Exemplos/ACBrDFe/Schemas/NFSe/PadraoNacional/1.01
mkdir -p "$HOME/nfse-testes/consultas"
NFSE_TEST_OUTPUT="$(mktemp -d "$HOME/nfse-testes/consultas/consulta-XXXXXXXX")"
export NFSE_TEST_OUTPUT
printf 'Consulta em HOMOLOGACAO da chave salva na emissao DPS 5 (ou da chave informada). Nao emite notas.\n'
bash "$test_dir/test-certificate.sh"
