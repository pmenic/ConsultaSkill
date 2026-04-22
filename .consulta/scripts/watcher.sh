#!/usr/bin/env bash
# ConsultaSkill Watcher — monitors an inbox for new JSON messages
# Usage: bash watcher.sh <inbox-dir> <ready-file> [poll-seconds] [heartbeat-seconds]
#
# Output: one line "NEW:<filename>" for each new file detected
# The .ready file is created at startup and removed on exit (trap EXIT)
# The .ready timestamp is updated every heartbeat-seconds (heartbeat)

set -uo pipefail
shopt -s nullglob

INBOX_DIR="${1:?Usage: watcher.sh <inbox-dir> <ready-file> [poll-seconds] [heartbeat-seconds]}"
READY_FILE="${2:?Usage: watcher.sh <inbox-dir> <ready-file> [poll-seconds] [heartbeat-seconds]}"
POLL_SECONDS="${3:-3}"
HEARTBEAT_SECONDS="${4:-30}"

# Create directories if they don't exist
mkdir -p "$INBOX_DIR" "$(dirname "$READY_FILE")"

# Determine agent name from inbox path
AGENT_NAME="unknown"
if [[ "$INBOX_DIR" == *claude* ]]; then
  AGENT_NAME="claude"
elif [[ "$INBOX_DIR" == *gemini* ]]; then
  AGENT_NAME="gemini"
fi

# Register presence
cat > "$READY_FILE" <<EOJSON
{
  "agent": "$AGENT_NAME",
  "pid": $$,
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "session_mode": "active",
  "listening_inbox": "$INBOX_DIR"
}
EOJSON

# Cleanup on exit
cleanup() {
  rm -f "$READY_FILE" 2>/dev/null
}
trap cleanup EXIT INT TERM

# Catalog files already present in inbox
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

  # Heartbeat: update .ready file timestamp
  NOW=$(date +%s)
  if (( NOW - LAST_HEARTBEAT >= HEARTBEAT_SECONDS )); then
    touch "$READY_FILE" 2>/dev/null
    LAST_HEARTBEAT=$NOW
  fi

  # Check for new files in inbox
  for f in "$INBOX_DIR"/*.json; do
    [ -f "$f" ] || continue
    BASENAME="$(basename "$f")"
    if [ -z "${KNOWN[$BASENAME]+x}" ]; then
      # Wait for the file to be valid JSON (fully written)
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
