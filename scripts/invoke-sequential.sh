#!/bin/bash
# invoke-sequential.sh — A 결과를 B가 검증/확장하는 순차 실행
# Usage: invoke-sequential.sh <model-A> <model-B> "<prompt>"
# Example: invoke-sequential.sh codex opus "이 API 설계 검토해줘"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

MODEL_A="${1:-codex}"
MODEL_B="${2:-opus}"
PROMPT="${3:-}"

if [ -z "$PROMPT" ]; then
  echo "Error: prompt is required" >&2
  echo "Usage: invoke-sequential.sh <model-A> <model-B> <prompt>" >&2
  exit 1
fi

echo "[Sequential: $MODEL_A → $MODEL_B]" >&2

# Step 1: Model A 실행
RESULT_A_EXIT=0
RESULT_A=$(bash "$SCRIPT_DIR/invoke-model.sh" "$MODEL_A" "$PROMPT") || RESULT_A_EXIT=$?

if [ -z "$RESULT_A" ] || [ $RESULT_A_EXIT -ne 0 ]; then
  echo "[ERROR] $MODEL_A failed (exit:$RESULT_A_EXIT) or returned empty result" >&2
  exit 1
fi

# Step 2: Model B — A의 결과를 컨텍스트로 받아 검증/확장
PROMPT_B="The following output was produced by a previous model (${MODEL_A}) for this task:

\"${PROMPT}\"

--- Previous Output ---
${RESULT_A}
--- End Output ---

Your task: Critically review the above. Find issues, gaps, errors, or missing considerations. Then provide an improved or verified conclusion."

# 결과 출력
RESULT_B_EXIT=0
RESULT_B=$(bash "$SCRIPT_DIR/invoke-model.sh" "$MODEL_B" "$PROMPT_B") || RESULT_B_EXIT=$?

printf '=== %s ===\n' "$MODEL_A"
printf '%s\n' "$RESULT_A"
echo ""
printf '=== %s (검증) ===\n' "$MODEL_B"
printf '%s\n' "$RESULT_B"
exit $RESULT_B_EXIT
