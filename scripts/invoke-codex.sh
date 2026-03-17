#!/bin/bash
# invoke-codex.sh — Codex CLI one-shot wrapper
# Usage: invoke-codex.sh <model> <prompt> [sandbox] [timeout]
# Example: invoke-codex.sh gpt-5.3-codex "설계해줘" read-only

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/../models.env" ] && source "$SCRIPT_DIR/../models.env"

MODEL="${1:-${CODEX_MODEL:-gpt-5.3-codex}}"
PROMPT="${2:-}"
SANDBOX="${3:-read-only}"
TIMEOUT="${4:-600}"

if [ -z "$PROMPT" ]; then
  echo "Error: prompt is required" >&2
  echo "Usage: invoke-codex.sh <model> <prompt> [sandbox] [timeout]" >&2
  exit 1
fi

# fix: 생성 직후 trap 등록 — INT/TERM 시에도 누수 없음
TMPFILE=$(mktemp /tmp/codex_out_XXXXXX.txt)
cleanup() { rm -f "$TMPFILE"; }
trap cleanup EXIT INT TERM

# fix: 2>&1 제거 → stderr는 호출자에게 전달 (실패 원인 추적 가능)
EXIT_CODE=0
timeout "$TIMEOUT" codex exec "$PROMPT" -m "$MODEL" --sandbox "$SANDBOX" --skip-git-repo-check -o "$TMPFILE" >/dev/null || EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  echo "[ERROR] Codex timed out after ${TIMEOUT}s" >&2
fi

cat "$TMPFILE"
# fix: exit code 전파 — rm이 마지막 명령이 되면 항상 0 반환하던 버그 수정
exit $EXIT_CODE
