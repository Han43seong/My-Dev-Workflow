#!/bin/bash
# invoke-adversarial.sh — 제안 → 반박의 교차 검증
# Usage: invoke-adversarial.sh <proposer> <critic> "<question>"
# Example: invoke-adversarial.sh codex gemini "Redis 도입이 맞는가?"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

PROPOSER="${1:-codex}"
CRITIC="${2:-gemini}"
QUESTION="${3:-}"

if [ -z "$QUESTION" ]; then
  echo "Error: question is required" >&2
  echo "Usage: invoke-adversarial.sh <proposer> <critic> <question>" >&2
  exit 1
fi

echo "[Adversarial: $PROPOSER 제안 → $CRITIC 반박]" >&2

# Round 1: Proposer — 해결책/주장 제시
PROPOSAL_EXIT=0
PROPOSAL=$(bash "$SCRIPT_DIR/invoke-model.sh" "$PROPOSER" "$QUESTION") || PROPOSAL_EXIT=$?

if [ -z "$PROPOSAL" ] || [ $PROPOSAL_EXIT -ne 0 ]; then
  echo "[ERROR] $PROPOSER failed (exit:$PROPOSAL_EXIT) or returned empty proposal" >&2
  exit 1
fi

# Round 2: Critic — 적극적으로 반박/취약점 탐색
CRITIC_PROMPT="The following solution/proposal was made for this question:

Question: \"${QUESTION}\"

--- Proposal ---
${PROPOSAL}
--- End Proposal ---

Your task: Be a rigorous adversarial critic. Challenge every assumption. Find security flaws, edge cases, scalability issues, logical errors, or better alternatives. Do NOT validate the good parts — focus entirely on weaknesses and counterarguments. Be specific."

CRITIC_EXIT=0
CRITIQUE=$(bash "$SCRIPT_DIR/invoke-model.sh" "$CRITIC" "$CRITIC_PROMPT") || CRITIC_EXIT=$?

# 결과 출력
printf '=== %s (제안) ===\n' "$PROPOSER"
printf '%s\n' "$PROPOSAL"
echo ""
printf '=== %s (반박) ===\n' "$CRITIC"
printf '%s\n' "$CRITIQUE"
exit $CRITIC_EXIT
