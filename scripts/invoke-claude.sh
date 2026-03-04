#!/bin/bash
# invoke-claude.sh — Claude CLI one-shot wrapper with HOME isolation + tool access
#
# 문제: 여러 Claude Code 인스턴스가 ~/.claude/ 상태를 공유하면
# Windows mandatory file locking으로 인해 hang 발생.
#
# 해결: 워커마다 격리된 HOME 디렉토리를 생성하여 파일 경합 원천 차단.
# env -u CLAUDECODE (중첩 세션 차단 해제) + HOME 격리 (파일 격리) = 완전한 프로세스 격리.
#
# Usage: invoke-claude.sh <model> <prompt> [format] [timeout] [tools_mode]
#   tools_mode: none (default) | readonly | full
#     none     — 텍스트 응답만 (빠름, 120s)
#     readonly — 파일 읽기/탐색/git 허용 (코드 분석, 300s)
#     full     — bash/읽기/쓰기/웹 전체 허용 (구현 작업, 600s)
#
# ref: https://github.com/anthropics/claude-code/issues/26190

set -euo pipefail

MODEL="${1:-opus}"
PROMPT="${2:-}"
FORMAT="${3:-text}"
TOOLS_MODE="${5:-none}"   # 5번째 인자 먼저 읽어서 timeout 기본값 계산에 사용

# tools_mode에 따른 timeout 기본값 (4번째 인자로 오버라이드 가능)
case "$TOOLS_MODE" in
  readonly) DEFAULT_TIMEOUT=300 ;;
  full)     DEFAULT_TIMEOUT=600 ;;
  *)        DEFAULT_TIMEOUT=120 ;;
esac
TIMEOUT="${4:-$DEFAULT_TIMEOUT}"

if [ -z "$PROMPT" ]; then
  echo "Error: prompt is required" >&2
  echo "Usage: invoke-claude.sh <model> <prompt> [format] [timeout] [tools_mode]" >&2
  echo "tools_mode: none | readonly | full" >&2
  exit 1
fi

# --- tools_mode → --allowedTools 플래그 빌드 ---
case "$TOOLS_MODE" in
  readonly)
    # 읽기/탐색/분석 전용: 파일 수정 불가
    TOOL_FLAGS=(
      --allowedTools "Read,Glob,Grep,Bash(git:*),Bash(ls:*),Bash(find:*),Bash(cat:*)"
    )
    ;;
  full)
    # 전체 권한: 파일 쓰기, 웹 접근, 모든 bash 포함
    TOOL_FLAGS=(
      --allowedTools "Bash,Read,Write,Edit,Glob,Grep,WebFetch,WebSearch"
    )
    ;;
  *)
    # 도구 없음: 텍스트 응답만
    TOOL_FLAGS=()
    ;;
esac

# --- 설정 ---
REAL_HOME="$HOME"
WORKERS_BASE="$REAL_HOME/.claude-workers"
STALE_TTL_MINUTES=15  # full 모드 timeout(600s=10분)보다 충분히 여유 있게

# --- 고아 워커 정리 (15분 이상 된 것) ---
if [ -d "$WORKERS_BASE" ]; then
  find "$WORKERS_BASE" -maxdepth 1 -name "worker-*" -type d \
    -mmin +"$STALE_TTL_MINUTES" -exec rm -rf {} + 2>/dev/null || true
fi

# --- 격리 HOME 생성 ---
WORKER_HOME="$WORKERS_BASE/worker-$$"
mkdir -p "$WORKER_HOME/.claude"

# 필수 파일 복사
# .claude.json: 인증 토큰 + 온보딩 상태 + API 설정
# .credentials.json: OAuth 크리덴셜
# settings.json: 전역 설정
if [ -f "$REAL_HOME/.claude.json" ]; then
  cp "$REAL_HOME/.claude.json" "$WORKER_HOME/.claude.json"
else
  echo "[ERROR] $REAL_HOME/.claude.json not found — Claude auth missing" >&2
  exit 1
fi
if [ -f "$REAL_HOME/.claude/.credentials.json" ]; then
  cp "$REAL_HOME/.claude/.credentials.json" "$WORKER_HOME/.claude/"
fi
if [ -f "$REAL_HOME/.claude/settings.json" ]; then
  cp "$REAL_HOME/.claude/settings.json" "$WORKER_HOME/.claude/"
fi

# --- 정리 트랩 (정상 종료, 에러, 타임아웃, Ctrl+C 모두 처리) ---
cleanup() { rm -rf "$WORKER_HOME" 2>/dev/null; }
trap cleanup EXIT

# --- 격리 실행 ---
# env -u CLAUDECODE: 중첩 세션 차단 변수만 제거, 나머지 환경변수 전부 상속
# HOME만 워커 디렉토리로 교체 → 파일 경합 차단 + 모든 시스템 변수 보존
# < /dev/null: 부모 세션 stdin 상속 차단 (없으면 claude -p가 stdin 대기로 hang)
EXIT_CODE=0
timeout "$TIMEOUT" env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT HOME="$WORKER_HOME" \
  claude -p "$PROMPT" \
    --model "$MODEL" \
    --output-format "$FORMAT" \
    --no-session-persistence \
    ${TOOL_FLAGS[@]+"${TOOL_FLAGS[@]}"} \
    < /dev/null \
    2>"$WORKER_HOME/stderr.log" || EXIT_CODE=$?

if [ $EXIT_CODE -eq 124 ]; then
  echo "[ERROR] Claude $MODEL (tools=$TOOLS_MODE) timed out after ${TIMEOUT}s" >&2
elif [ $EXIT_CODE -ne 0 ]; then
  cat "$WORKER_HOME/stderr.log" >&2
fi
exit $EXIT_CODE
