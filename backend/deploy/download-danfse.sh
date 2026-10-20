#!/usr/bin/env bash
set -euo pipefail
umask 077
xml="$1"
out="$2"
key="$3"
document="$4"
[[ "$key" =~ ^[0-9]{50}$ && "$document" =~ ^[0-9]{14}$ ]] || exit 10
chmod 700 "$out"
# A API nacional de PDF foi suspensa em 03/08/2026 (NT 008 v1.02).
# Somente renderizacao local: nao usa certificado, rede ou operacoes de emissao.
renderer="$(dirname -- "${BASH_SOURCE[0]}")/render-danfse.py"
python3 "$renderer" "$xml" "$out/danfse.pdf" --key "$key" --document "$document" \
  > "$out/renderer-status.txt" 2> "$out/renderer-error.txt"
