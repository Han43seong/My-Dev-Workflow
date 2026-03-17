#!/bin/bash
# invoke-sequential.sh — A 결과를 B가 검증/확장하는 순차 실행 + 파일 기반 결과 영속화
# Usage: invoke-sequential.sh <model-A> <model-B> "<prompt>"
# Example: invoke-sequential.sh codex opus "이 API 설계 검토해줘"
#
# 결과:
#   .orchestration/results/<timestamp>-sequential/combined.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MODEL_A="${1:-codex}"
MODEL_B="${2:-opus}"
PROMPT="${3:-}"

if [ -z "$PROMPT" ]; then
  echo "Error: prompt is required" >&2
  echo "Usage: invoke-sequential.sh <model-A> <model-B> <prompt>" >&2
  exit 1
fi

# --- 영속적 결과 디렉토리 생성 ---
LOG_BASE="${ORCH_LOG_DIR:-$PWD/.orchestration/results}"
mkdir -p "$LOG_BASE" 2>/dev/null
LOG_DIR="$(cd "$LOG_BASE" 2>/dev/null && pwd)"

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
RESULTS_DIR="$LOG_DIR/${TIMESTAMP}-sequential"
mkdir -p "$RESULTS_DIR"

echo "[$(date '+%H:%M:%S')] [sequential] START: $MODEL_A → $MODEL_B, prompt=${PROMPT:0:80}..." >> "$LOG_DIR/session-log.md"
echo "[Sequential: $MODEL_A → $MODEL_B]" >&2

# --- Step 1: Model A Advisor 실행 (텍스트 응답만) ---
RESULT_A_EXIT=0
ORCH_OUTPUT_FILE="$RESULTS_DIR/$MODEL_A.md" \
  bash "$SCRIPT_DIR/invoke-model.sh" "$MODEL_A" "$PROMPT" 2>"$RESULTS_DIR/$MODEL_A.err" || RESULT_A_EXIT=$?

if [ ! -s "$RESULTS_DIR/$MODEL_A.md" ] || [ $RESULT_A_EXIT -ne 0 ]; then
  echo "[ERROR] $MODEL_A failed (exit:$RESULT_A_EXIT) or returned empty result" >&2
  # combined에 에러 기록
  {
    echo "# Sequential Results (ERROR)"
    echo ""
    echo "> $MODEL_A failed (exit:$RESULT_A_EXIT)"
    if [ -s "$RESULTS_DIR/$MODEL_A.err" ]; then
      echo '```'
      cat "$RESULTS_DIR/$MODEL_A.err"
      echo '```'
    fi
  } > "$RESULTS_DIR/combined.md"
  echo "ORCH_RESULT_FILE=$RESULTS_DIR/combined.md"
  exit 1
fi

RESULT_A=$(cat "$RESULTS_DIR/$MODEL_A.md")

# --- Step 2: Model B — A의 결과를 컨텍스트로 받아 검증/확장 ---
PROMPT_B="The following output was produced by a previous model (${MODEL_A}) for this task:

\"${PROMPT}\"

--- Previous Output ---
${RESULT_A}
--- End Output ---

Your task: Critically review the above. Find issues, gaps, errors, or missing considerations. Then provide an improved or verified conclusion."

RESULT_B_EXIT=0
ORCH_OUTPUT_FILE="$RESULTS_DIR/$MODEL_B.md" \
  bash "$SCRIPT_DIR/invoke-model.sh" "$MODEL_B" "$PROMPT_B" 2>"$RESULTS_DIR/$MODEL_B.err" || RESULT_B_EXIT=$?

# --- combined.md 생성 ---
COMBINED="$RESULTS_DIR/combined.md"
{
  echo "# Sequential Results"
  echo ""
  echo "> Generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "> Pipeline: $MODEL_A → $MODEL_B"
  echo ""
  echo "---"
  echo ""
  echo "## $MODEL_A (Step 1)"
  echo ""
  cat "$RESULTS_DIR/$MODEL_A.md"
  echo ""
  echo "---"
  echo ""
  echo "## $MODEL_B (Step 2: Review)"
  echo ""
  if [ -s "$RESULTS_DIR/$MODEL_B.md" ]; then
    cat "$RESULTS_DIR/$MODEL_B.md"
  else
    echo "*[empty result]*"
  fi
  echo ""
} > "$COMBINED"

COMBINED_SIZE=$(wc -c < "$COMBINED" 2>/dev/null || echo "0")
echo "[$(date '+%H:%M:%S')] [sequential] DONE: $COMBINED (${COMBINED_SIZE} bytes)" >> "$LOG_DIR/session-log.md"

echo "ORCH_RESULT_FILE=$COMBINED"
exit $RESULT_B_EXIT
