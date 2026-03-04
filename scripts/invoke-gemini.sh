#!/bin/bash
# invoke-gemini.sh — Gemini CLI one-shot wrapper
# Usage: invoke-gemini.sh <model> <prompt> [timeout]
# Example: invoke-gemini.sh gemini-3-pro-preview "분석해줘"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/../models.env" ] && source "$SCRIPT_DIR/../models.env"

MODEL="${1:-${GEMINI_MODEL:-gemini-3-pro-preview}}"
PROMPT="${2:-}"
TIMEOUT="${3:-120}"

if [ -z "$PROMPT" ]; then
  echo "Error: prompt is required" >&2
  echo "Usage: invoke-gemini.sh <model> <prompt> [timeout]" >&2
  exit 1
fi

EXIT_CODE=0
timeout "$TIMEOUT" gemini "$PROMPT" -m "$MODEL" || EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  echo "[ERROR] Gemini timed out after ${TIMEOUT}s" >&2
fi
exit $EXIT_CODE
