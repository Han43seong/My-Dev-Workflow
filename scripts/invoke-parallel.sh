#!/bin/bash
# invoke-parallel.sh — 여러 모델을 진짜 병렬로 실행 + 파일 기반 결과 영속화
# Usage: invoke-parallel.sh "<prompt>" [model1 model2 model3]
# Default models: opus codex gemini
#
# 결과:
#   .orchestration/results/<timestamp>-parallel/combined.md  (통합 결과)
#   .orchestration/results/<timestamp>-parallel/<model>.md   (개별 결과)
#
# stdout으로 combined.md 경로를 출력하고, 결과 파일은 영속적으로 보존됨.
# Claude Code Bash 도구의 stdout 캡처 문제를 우회하기 위해
# 결과를 항상 파일에 저장하는 방식으로 동작.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT="${1:-}"
shift
MODELS="${*:-opus codex gemini}"

if [ -z "$PROMPT" ]; then
  echo "Error: prompt is required" >&2
  echo "Usage: invoke-parallel.sh \"<prompt>\" [model1 model2 ...]" >&2
  exit 1
fi

# --- 영속적 결과 디렉토리 생성 ---
LOG_BASE="${ORCH_LOG_DIR:-$PWD/.orchestration/results}"
mkdir -p "$LOG_BASE" 2>/dev/null
LOG_DIR="$(cd "$LOG_BASE" 2>/dev/null && pwd)"

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
RESULTS_DIR="$LOG_DIR/${TIMESTAMP}-parallel"
mkdir -p "$RESULTS_DIR"

# --- 세션 로그 ---
echo "[$(date '+%H:%M:%S')] [parallel] START: models=[$MODELS] prompt=${PROMPT:0:80}..." >> "$LOG_DIR/session-log.md"

# --- 각 모델을 백그라운드로 동시 실행 (Advisor, 텍스트 응답만) ---
MODEL_PIDS=()
for MODEL in $MODELS; do
  (
    ORCH_OUTPUT_FILE="$RESULTS_DIR/$MODEL.md" \
      bash "$SCRIPT_DIR/invoke-model.sh" "$MODEL" "$PROMPT" 2>"$RESULTS_DIR/$MODEL.err"
    echo $? > "$RESULTS_DIR/$MODEL.exit"
  ) &
  MODEL_PIDS+=($!)
done

# --- 전체 타임아웃 watchdog (Advisor는 빠르므로 180초로 축소) ---
PARALLEL_TIMEOUT=${PARALLEL_TIMEOUT:-180}
(
  SLEEP_PID=0
  trap 'kill $SLEEP_PID 2>/dev/null' EXIT
  sleep "$PARALLEL_TIMEOUT" &
  SLEEP_PID=$!
  wait "$SLEEP_PID" 2>/dev/null || exit 0
  echo "[ERROR] Parallel execution timed out after ${PARALLEL_TIMEOUT}s" >&2
  kill "${MODEL_PIDS[@]}" 2>/dev/null
) &
WATCHDOG_PID=$!

# --- 모델 프로세스만 대기 ---
for PID in "${MODEL_PIDS[@]}"; do
  wait "$PID" 2>/dev/null || true
done
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true

# --- combined.md 생성 ---
COMBINED="$RESULTS_DIR/combined.md"
{
  echo "# Parallel Results"
  echo ""
  echo "> Generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "> Models: $MODELS"
  echo ""
  for MODEL in $MODELS; do
    STATUS=$(cat "$RESULTS_DIR/$MODEL.exit" 2>/dev/null || echo "?")
    BYTES=$(wc -c < "$RESULTS_DIR/$MODEL.md" 2>/dev/null || echo "0")
    echo "---"
    echo ""
    echo "## $MODEL (exit:$STATUS, ${BYTES} bytes)"
    echo ""
    if [ -s "$RESULTS_DIR/$MODEL.md" ]; then
      cat "$RESULTS_DIR/$MODEL.md"
    else
      echo "*[empty result]*"
      if [ -s "$RESULTS_DIR/$MODEL.err" ]; then
        echo ""
        echo "**stderr:**"
        echo '```'
        head -20 "$RESULTS_DIR/$MODEL.err"
        echo '```'
      fi
    fi
    echo ""
  done
} > "$COMBINED"

# --- 세션 로그 완료 ---
COMBINED_SIZE=$(wc -c < "$COMBINED" 2>/dev/null || echo "0")
echo "[$(date '+%H:%M:%S')] [parallel] DONE: $COMBINED (${COMBINED_SIZE} bytes)" >> "$LOG_DIR/session-log.md"

# --- 전체 실패 감지 ---
FAIL_COUNT=0
TOTAL_COUNT=0
for MODEL in $MODELS; do
  STATUS=$(cat "$RESULTS_DIR/$MODEL.exit" 2>/dev/null || echo "1")
  [ "$STATUS" != "0" ] && FAIL_COUNT=$((FAIL_COUNT + 1))
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
done

# --- 결과 출력: 파일 경로 (Claude Code에서 Read 도구로 읽을 수 있음) ---
echo "ORCH_RESULT_FILE=$COMBINED"

[ "$FAIL_COUNT" -eq "$TOTAL_COUNT" ] && exit 1
exit 0
