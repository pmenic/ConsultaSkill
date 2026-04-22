#!/usr/bin/env bash
# ConsultaSkill Watcher — monitora una inbox per nuovi messaggi JSON
# Uso: bash watcher.sh <inbox-dir> <ready-file> [poll-seconds] [heartbeat-seconds]
#
# Output: una riga "NEW:<filename>" per ogni nuovo file rilevato
# Il file .ready viene creato all'avvio e rimosso alla chiusura (trap EXIT)
# Il timestamp del .ready viene aggiornato ogni heartbeat-seconds (heartbeat)

set -uo pipefail
shopt -s nullglob

INBOX_DIR="${1:?Uso: watcher.sh <inbox-dir> <ready-file> [poll-seconds] [heartbeat-seconds]}"
READY_FILE="${2:?Uso: watcher.sh <inbox-dir> <ready-file> [poll-seconds] [heartbeat-seconds]}"
POLL_SECONDS="${3:-3}"
HEARTBEAT_SECONDS="${4:-30}"

# Crea directory se non esistono
mkdir -p "$INBOX_DIR" "$(dirname "$READY_FILE")"

# Determina nome agente dal path inbox
AGENT_NAME="unknown"
if [[ "$INBOX_DIR" == *claude* ]]; then
  AGENT_NAME="claude"
elif [[ "$INBOX_DIR" == *gemini* ]]; then
  AGENT_NAME="gemini"
fi

# Registra presenza
cat > "$READY_FILE" <<EOJSON
{
  "agent": "$AGENT_NAME",
  "pid": $$,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "session_mode": "active",
  "listening_inbox": "$INBOX_DIR"
}
EOJSON

# Cleanup alla chiusura
cleanup() {
  rm -f "$READY_FILE" 2>/dev/null
}
trap cleanup EXIT INT TERM

# Cataloga i file gia' presenti nella inbox
declare -A KNOWN
for f in "$INBOX_DIR"/*.json; do
  if [ -f "$f" ]; then
    KNOWN["$(basename "$f")"]=1
  fi
done

LAST_HEARTBEAT=$(date +%s)

echo "WATCHER:STARTED:$AGENT_NAME:$$"

while true; do
  sleep "$POLL_SECONDS"

  # Heartbeat: aggiorna il timestamp del file .ready
  NOW=$(date +%s)
  if (( NOW - LAST_HEARTBEAT >= HEARTBEAT_SECONDS )); then
    touch "$READY_FILE" 2>/dev/null
    LAST_HEARTBEAT=$NOW
  fi

  # Controlla nuovi file nella inbox
  for f in "$INBOX_DIR"/*.json; do
    [ -f "$f" ] || continue
    BASENAME="$(basename "$f")"
    if [ -z "${KNOWN[$BASENAME]+x}" ]; then
      # Attendi che il file sia un JSON valido (completamente scritto)
      RETRIES=0
      while [ $RETRIES -lt 5 ]; do
        if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
          break
        fi
        sleep 0.3
        RETRIES=$((RETRIES + 1))
      done
      echo "NEW:$BASENAME"
      KNOWN["$BASENAME"]=1
    fi
  done
done
