#!/usr/bin/env bash
# ConsultaSkill — Waits for ONE new message in inbox and returns its filename
# Usage: bash wait-for-message.sh <inbox-dir> [timeout-seconds] [poll-seconds]
#
# Blocks until a new .json file appears in the inbox.
# Output: the filename (e.g., "gleif-20260422T054500Z-gemini-evaluate.json")
# Exit 0: file found. Exit 1: timeout reached.
#
# Designed for Gemini CLI which lacks a push Monitor tool.
# Gemini runs it synchronously: blocks, receives filename, processes, relaunches.

set -uo pipefail
shopt -s nullglob

INBOX_DIR="${1:?Usage: wait-for-message.sh <inbox-dir> [timeout-seconds] [poll-seconds]}"
TIMEOUT_SECONDS="${2:-300}"
POLL_SECONDS="${3:-3}"

# Catalog files already present
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

  # Check for new files
  for f in "$INBOX_DIR"/*.json; do
    [ -f "$f" ] || continue
    BASENAME="$(basename "$f")"
    if [ -z "${KNOWN[$BASENAME]+x}" ]; then
      # Verify JSON is valid (file fully written)
      RETRIES=0
      while [ $RETRIES -lt 5 ]; do
        if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$f" 2>/dev/null; then
          echo "$BASENAME"
          exit 0
        fi
        sleep 0.3
        RETRIES=$((RETRIES + 1))
      done
      # Even if JSON is invalid, report the file
      echo "$BASENAME"
      exit 0
    fi
  done
done

echo "TIMEOUT"
exit 1
