#!/bin/bash
# invoke-adversarial.sh — 제안 → 반박의 교차 검증 + 파일 기반 결과 영속화
# Usage: invoke-adversarial.sh <proposer> <critic> "<question>"
# Example: invoke-adversarial.sh codex gemini "Redis 도입이 맞는가?"
#
# 결과:
#   .orchestration/results/<timestamp>-adversarial/combined.md

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROPOSER="${1:-codex}"
CRITIC="${2:-gemini}"
QUESTION="${3:-}"

if [ -z "$QUESTION" ]; then
  echo "Error: question is required" >&2
  echo "Usage: invoke-adversarial.sh <proposer> <critic> <question>" >&2
  exit 1
fi

# --- 영속적 결과 디렉토리 생성 ---
LOG_BASE="${ORCH_LOG_DIR:-$PWD/.orchestration/results}"
mkdir -p "$LOG_BASE" 2>/dev/null
LOG_DIR="$(cd "$LOG_BASE" 2>/dev/null && pwd)"

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
RESULTS_DIR="$LOG_DIR/${TIMESTAMP}-adversarial"
mkdir -p "$RESULTS_DIR"

echo "[$(date '+%H:%M:%S')] [adversarial] START: $PROPOSER vs $CRITIC, question=${QUESTION:0:80}..." >> "$LOG_DIR/session-log.md"
echo "[Adversarial: $PROPOSER 제안 → $CRITIC 반박]" >&2

# --- Round 1: Proposer Advisor — 해결책/주장 제시 (텍스트만) ---
PROPOSAL_EXIT=0
ORCH_OUTPUT_FILE="$RESULTS_DIR/$PROPOSER.md" \
  bash "$SCRIPT_DIR/invoke-model.sh" "$PROPOSER" "$QUESTION" 2>"$RESULTS_DIR/$PROPOSER.err" || PROPOSAL_EXIT=$?

if [ ! -s "$RESULTS_DIR/$PROPOSER.md" ] || [ $PROPOSAL_EXIT -ne 0 ]; then
  echo "[ERROR] $PROPOSER failed (exit:$PROPOSAL_EXIT) or returned empty proposal" >&2
  {
    echo "# Adversarial Results (ERROR)"
    echo ""
    echo "> $PROPOSER failed (exit:$PROPOSAL_EXIT)"
    if [ -s "$RESULTS_DIR/$PROPOSER.err" ]; then
      echo '```'
      cat "$RESULTS_DIR/$PROPOSER.err"
      echo '```'
    fi
  } > "$RESULTS_DIR/combined.md"
  echo "ORCH_RESULT_FILE=$RESULTS_DIR/combined.md"
  exit 1
fi

PROPOSAL=$(cat "$RESULTS_DIR/$PROPOSER.md")

# --- Round 2: Critic — 적극적으로 반박/취약점 탐색 ---
CRITIC_PROMPT="The following solution/proposal was made for this question:

Question: \"${QUESTION}\"

--- Proposal ---
${PROPOSAL}
--- End Proposal ---

Your task: Be a rigorous adversarial critic. Challenge every assumption. Find security flaws, edge cases, scalability issues, logical errors, or better alternatives. Do NOT validate the good parts — focus entirely on weaknesses and counterarguments. Be specific."

CRITIC_EXIT=0
ORCH_OUTPUT_FILE="$RESULTS_DIR/$CRITIC.md" \
  bash "$SCRIPT_DIR/invoke-model.sh" "$CRITIC" "$CRITIC_PROMPT" 2>"$RESULTS_DIR/$CRITIC.err" || CRITIC_EXIT=$?

# --- combined.md 생성 ---
COMBINED="$RESULTS_DIR/combined.md"
{
  echo "# Adversarial Results"
  echo ""
  echo "> Generated: $(date '+%Y-%m-%d %H:%M:%S')"
  echo "> Proposer: $PROPOSER / Critic: $CRITIC"
  echo ""
  echo "---"
  echo ""
  echo "## $PROPOSER (Proposal)"
  echo ""
  cat "$RESULTS_DIR/$PROPOSER.md"
  echo ""
  echo "---"
  echo ""
  echo "## $CRITIC (Critique)"
  echo ""
  if [ -s "$RESULTS_DIR/$CRITIC.md" ]; then
    cat "$RESULTS_DIR/$CRITIC.md"
  else
    echo "*[empty result]*"
  fi
  echo ""
} > "$COMBINED"

COMBINED_SIZE=$(wc -c < "$COMBINED" 2>/dev/null || echo "0")
echo "[$(date '+%H:%M:%S')] [adversarial] DONE: $COMBINED (${COMBINED_SIZE} bytes)" >> "$LOG_DIR/session-log.md"

echo "ORCH_RESULT_FILE=$COMBINED"
exit $CRITIC_EXIT
