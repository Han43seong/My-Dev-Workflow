#!/bin/bash
# invoke-claude.sh — Claude CLI Advisor wrapper (text-only, no tools)
#
# Advisor 전용: 도구 없이 텍스트 응답만. 120초 타임아웃.
# HOME 격리로 Windows 파일 잠금 방지.
#
# Usage: invoke-claude.sh <model> <prompt> [format] [timeout]

set -euo pipefail

MODEL="${1:-opus}"
PROMPT="${2:-}"
FORMAT="${3:-text}"
TIMEOUT="${4:-120}"

if [ -z "$PROMPT" ]; then
  echo "Error: prompt is required" >&2
  echo "Usage: invoke-claude.sh <model> <prompt> [format] [timeout]" >&2
  exit 1
fi

# --- 설정 ---
REAL_HOME="$HOME"
WORKERS_BASE="$REAL_HOME/.claude-workers"

# --- 고아 워커 정리 (5분 이상 된 것) ---
if [ -d "$WORKERS_BASE" ]; then
  find "$WORKERS_BASE" -maxdepth 1 -name "worker-*" -type d \
    -mmin +5 -exec rm -rf {} + 2>/dev/null || true
fi

# --- 격리 HOME 생성 ---
WORKER_HOME="$WORKERS_BASE/worker-$$"
mkdir -p "$WORKER_HOME/.claude"

if [ -f "$REAL_HOME/.claude.json" ]; then
  cp "$REAL_HOME/.claude.json" "$WORKER_HOME/.claude.json"
else
  echo "[ERROR] $REAL_HOME/.claude.json not found — Claude auth missing" >&2
  exit 1
fi
[ -f "$REAL_HOME/.claude/.credentials.json" ] && cp "$REAL_HOME/.claude/.credentials.json" "$WORKER_HOME/.claude/"
[ -f "$REAL_HOME/.claude/settings.json" ] && cp "$REAL_HOME/.claude/settings.json" "$WORKER_HOME/.claude/"

# --- 정리 트랩 ---
FAIL_LOG_DIR="${ORCH_LOG_DIR:-$PWD/.orchestration/results}/worker-logs"
cleanup() {
  if [ -f "$WORKER_HOME/stderr.log" ] && [ "$EXIT_CODE" -ne 0 ]; then
    mkdir -p "$FAIL_LOG_DIR" 2>/dev/null
    cp "$WORKER_HOME/stderr.log" "$FAIL_LOG_DIR/$(date '+%Y%m%d-%H%M%S')-${MODEL}-exit${EXIT_CODE}.log" 2>/dev/null
  fi
  rm -rf "$WORKER_HOME" 2>/dev/null
}
trap cleanup EXIT

# --- Advisor 실행 (도구 없음, 텍스트 응답만) ---
EXIT_CODE=0
timeout "$TIMEOUT" env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT HOME="$WORKER_HOME" \
  claude -p "$PROMPT" \
    --model "$MODEL" \
    --output-format "$FORMAT" \
    --no-session-persistence \
    < /dev/null \
    2>"$WORKER_HOME/stderr.log" || EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  echo "[ERROR] Claude $MODEL timed out after ${TIMEOUT}s" >&2
elif [ $EXIT_CODE -ne 0 ]; then
  cat "$WORKER_HOME/stderr.log" >&2
fi
exit $EXIT_CODE
