#!/bin/bash
# invoke-model.sh — Unified model dispatcher
# Usage: invoke-model.sh <alias> <prompt>
# Example: invoke-model.sh opus "리뷰해줘"
#
# Aliases: opus, codex, gemini
#
# Tools mode (Claude 워커 전용):
#   기본값: opus → full
#   환경변수로 오버라이드: CLAUDE_TOOLS=none|readonly|full bash invoke-model.sh opus "..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
[ -f "$SCRIPT_DIR/../models.env" ] && source "$SCRIPT_DIR/../models.env"

ALIAS="$1"
PROMPT="${2:-}"
# 로그는 실행 디렉토리 기준 (전역 스크립트이므로 $SCRIPT_DIR 기반 X)
LOG_BASE="${ORCH_LOG_DIR:-$PWD/.orchestration/results}"
mkdir -p "$LOG_BASE" 2>/dev/null
LOG_DIR="$(cd "$LOG_BASE" 2>/dev/null && pwd)"

if [ -z "$ALIAS" ] || [ -z "$PROMPT" ]; then
  echo "Error: alias and prompt are required" >&2
  echo "Usage: invoke-model.sh <alias> <prompt>" >&2
  echo "Aliases: opus, codex, gemini" >&2
  exit 1
fi

# --- Agent prompt injection ---
# 모델 alias에 맞는 에이전트 페르소나를 프롬프트 앞에 주입
PROMPTS_DIR="$SCRIPT_DIR/../prompts"
get_agent_prompt_file() {
  case "$1" in
    codex)         echo "$PROMPTS_DIR/debugger.md" ;;
    gemini)        echo "$PROMPTS_DIR/researcher.md" ;;
    opus)          echo "$PROMPTS_DIR/code-reviewer.md" ;;
    *)             echo "" ;;
  esac
}

AGENT_FILE=$(get_agent_prompt_file "$ALIAS")
if [ -n "$AGENT_FILE" ] && [ -f "$AGENT_FILE" ]; then
  AGENT_SYSTEM=$(cat "$AGENT_FILE")
  FULL_PROMPT="${AGENT_SYSTEM}

---

${PROMPT}"
else
  FULL_PROMPT="$PROMPT"
fi

# --- Claude 워커 tools mode 결정 ---
# 우선순위: 환경변수 CLAUDE_TOOLS > 모델별 기본값
# opus: full — 전체 도구 허용 (구현 작업, 코드 분석)
get_default_tools() {
  case "$1" in
    opus)        echo "full" ;;
    *)           echo "none" ;;
  esac
}

CLAUDE_TOOLS="${CLAUDE_TOOLS:-}"  # 환경변수 미설정 시 모델별 기본값 사용

# --- Fallback mapping ---
get_fallback() {
  case "$1" in
    codex)  echo "opus" ;;
    gemini) echo "opus" ;;
    *)      echo "" ;;
  esac
}

# --- Log start ---
if [ -n "$LOG_DIR" ]; then
  echo "[$(date '+%H:%M:%S')] [$ALIAS] START: ${PROMPT:0:80}..." >> "$LOG_DIR/session-log.md"
fi

# --- Dispatch ---
dispatch() {
  local MODEL_ALIAS="$1"
  local MODEL_PROMPT="$2"
  local TOOLS_MODE

  # 환경변수 우선, 없으면 모델별 기본값
  if [ -n "$CLAUDE_TOOLS" ]; then
    TOOLS_MODE="$CLAUDE_TOOLS"
  else
    TOOLS_MODE=$(get_default_tools "$MODEL_ALIAS")
  fi

  case "$MODEL_ALIAS" in
    opus)
      # tools_mode를 5번째 인자로 전달 (format=text, timeout=기본값은 빈 문자열로 skip)
      bash "$SCRIPT_DIR/invoke-claude.sh" "opus"   "$MODEL_PROMPT" "text" "" "$TOOLS_MODE"
      ;;
    codex)
      bash "$SCRIPT_DIR/invoke-codex.sh"  "${CODEX_MODEL:-gpt-5.3-codex}"        "$MODEL_PROMPT"
      ;;
    gemini)
      bash "$SCRIPT_DIR/invoke-gemini.sh" "${GEMINI_MODEL:-gemini-3-pro-preview}" "$MODEL_PROMPT"
      ;;
    *)
      echo "Unknown model alias: $MODEL_ALIAS" >&2
      echo "Available: opus, codex, gemini" >&2
      return 1
      ;;
  esac
}

DISPATCH_EXIT=0
RESULT=$(dispatch "$ALIAS" "$FULL_PROMPT") || DISPATCH_EXIT=$?

# --- Fallback on empty result or non-zero exit ---
if [ -z "$RESULT" ] || [ $DISPATCH_EXIT -ne 0 ]; then
  FALLBACK=$(get_fallback "$ALIAS")
  if [ -n "$FALLBACK" ]; then
    echo "[WARN] $ALIAS returned empty or failed (exit:$DISPATCH_EXIT), retrying with fallback: $FALLBACK" >&2
    DISPATCH_EXIT=0
    RESULT=$(dispatch "$FALLBACK" "$FULL_PROMPT") || DISPATCH_EXIT=$?
  fi
fi

# --- Log end ---
if [ -n "$LOG_DIR" ]; then
  echo "[$(date '+%H:%M:%S')] [$ALIAS] DONE (${#RESULT} chars)" >> "$LOG_DIR/session-log.md"
fi

printf '%s\n' "$RESULT"
exit $DISPATCH_EXIT
