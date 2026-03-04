#!/bin/bash
# invoke-parallel.sh — 여러 모델을 진짜 병렬로 실행
# Usage: invoke-parallel.sh "<prompt>" [model1 model2 model3]
# Default models: opus codex gemini
#
# 각 모델을 백그라운드(&)로 동시 실행하고 wait로 전부 완료 대기.
# 결과는 모델별 exit code와 함께 stdout에 출력.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT="${1:-}"
shift
MODELS="${*:-opus codex gemini}"

if [ -z "$PROMPT" ]; then
  echo "Error: prompt is required" >&2
  echo "Usage: invoke-parallel.sh \"<prompt>\" [model1 model2 ...]" >&2
  exit 1
fi

# fix: TMPDIR → PARALLEL_DIR (TMPDIR는 시스템 예약 환경변수)
PARALLEL_DIR=$(mktemp -d /tmp/parallel_XXXXXX)

# fix: cleanup trap — INT/TERM 시에도 임시 디렉토리 누수 없음
cleanup() { rm -rf "$PARALLEL_DIR"; }
trap cleanup EXIT INT TERM

# 각 모델을 백그라운드로 동시 실행 (PID 수집)
MODEL_PIDS=()
for MODEL in $MODELS; do
  (
    bash "$SCRIPT_DIR/invoke-model.sh" "$MODEL" "$PROMPT" > "$PARALLEL_DIR/$MODEL.out" 2>"$PARALLEL_DIR/$MODEL.err"
    echo $? > "$PARALLEL_DIR/$MODEL.exit"
  ) &
  MODEL_PIDS+=($!)
done

# 전체 타임아웃 watchdog — 개별 timeout이 실패해도 무한 대기 방지
# fix: kill 0 → 개별 PID kill (프로세스 그룹 전체 죽이는 문제 해결)
# fix: sleep을 서브프로세스로 실행 + trap EXIT으로 고아 방지
PARALLEL_TIMEOUT=${PARALLEL_TIMEOUT:-660}
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

# 모델 프로세스만 대기 (watchdog sleep은 대기하지 않음)
for PID in "${MODEL_PIDS[@]}"; do
  wait "$PID" 2>/dev/null || true
done
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true

# 결과 출력 (모델별 exit code 포함)
for MODEL in $MODELS; do
  STATUS=$(cat "$PARALLEL_DIR/$MODEL.exit" 2>/dev/null || echo "?")
  echo "=== $MODEL (exit:$STATUS) ==="
  cat "$PARALLEL_DIR/$MODEL.out"
  # stderr가 있으면 표시
  if [ -s "$PARALLEL_DIR/$MODEL.err" ]; then
    cat "$PARALLEL_DIR/$MODEL.err" >&2
  fi
  echo ""
done

# 전체 실패 감지 — 모든 모델이 실패하면 exit 1
FAIL_COUNT=0
TOTAL_COUNT=0
for MODEL in $MODELS; do
  STATUS=$(cat "$PARALLEL_DIR/$MODEL.exit" 2>/dev/null || echo "1")
  [ "$STATUS" != "0" ] && FAIL_COUNT=$((FAIL_COUNT + 1))
  TOTAL_COUNT=$((TOTAL_COUNT + 1))
done
[ "$FAIL_COUNT" -eq "$TOTAL_COUNT" ] && exit 1
exit 0
