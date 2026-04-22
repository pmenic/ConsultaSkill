#!/usr/bin/env bash
# ConsultaSkill — Attende UN nuovo messaggio nella inbox e restituisce il nome
# Uso: bash wait-for-message.sh <inbox-dir> [timeout-seconds] [poll-seconds]
#
# Blocca finche' un nuovo file .json appare nella inbox.
# Output: il nome del file (es: "gleif-003-evaluate.json")
# Exit 0: file trovato. Exit 1: timeout raggiunto.
#
# Questo script e' pensato per Gemini CLI che non ha un tool Monitor push.
# Gemini lo esegue come comando sincrono: blocca, riceve il nome, processa, rilancia.

set -uo pipefail
shopt -s nullglob

INBOX_DIR="${1:?Uso: wait-for-message.sh <inbox-dir> [timeout-seconds] [poll-seconds]}"
TIMEOUT_SECONDS="${2:-300}"
POLL_SECONDS="${3:-3}"

# Cataloga file gia' presenti
declare -A KNOWN
for f in "$INBOX_DIR"/*.json; do
  if [ -f "$f" ]; then
    KNOWN["$(basename "$f")"]=1
  fi
done

ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT_SECONDS" ]; do
  sleep "$POLL_SECONDS"
  ELAPSED=$((ELAPSED + POLL_SECONDS))

  # Controlla nuovi file
  for f in "$INBOX_DIR"/*.json; do
    [ -f "$f" ] || continue
    BASENAME="$(basename "$f")"
    if [ -z "${KNOWN[$BASENAME]+x}" ]; then
      # Verifica che il JSON sia valido (file completamente scritto)
      RETRIES=0
      while [ $RETRIES -lt 5 ]; do
        if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
          echo "$BASENAME"
          exit 0
        fi
        sleep 0.3
        RETRIES=$((RETRIES + 1))
      done
      # Anche se il JSON non e' valido, segnala il file
      echo "$BASENAME"
      exit 0
    fi
  done
done

echo "TIMEOUT"
exit 1
