#!/bin/bash
# stress-test.sh — 하네스 컴포넌트 제거 스트레스 테스트
# Usage:
#   stress-test.sh --bypass <component> --task "작업 설명" [--runs <N>]
#
# 컴포넌트: contract, evaluator, review, policy
#
# 동일 작업을 2회 실행:
#   Run A: 모든 컴포넌트 활성 (정상)
#   Run B: 지정 컴포넌트 bypass
# 결과 비교하여 recommendation 출력
#
# 출력: .orchestration/stress-test/<timestamp>-<component>.json

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.json"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
LOG_DIR="${ORCH_LOG_DIR:-$PROJECT_ROOT/.orchestration/results}"
mkdir -p "$LOG_DIR" 2>/dev/null

# --- 인자 파싱 ---
BYPASS_COMPONENT=""
TASK=""
RUNS=2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --bypass)    BYPASS_COMPONENT="$2"; shift 2 ;;
    --task)      TASK="$2"; shift 2 ;;
    --runs)      RUNS="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [ -z "$BYPASS_COMPONENT" ] || [ -z "$TASK" ]; then
  echo '{"error": "required: --bypass <component> --task \"description\""}' >&2
  echo "Components: contract, evaluator, review, policy" >&2
  exit 1
fi

# 유효성 검사
VALID_COMPONENTS="contract evaluator review policy"
if ! echo "$VALID_COMPONENTS" | grep -qw "$BYPASS_COMPONENT"; then
  echo "{\"error\": \"invalid component: $BYPASS_COMPONENT. Valid: $VALID_COMPONENTS\"}" >&2
  exit 1
fi

# config에서 stress_test 활성화 확인
ENABLED=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE',encoding='utf-8')); print(c.get('stress_test',{}).get('enabled',False))" 2>/dev/null)
if [ "$ENABLED" = "False" ]; then
  echo '{"error": "stress_test.enabled=false in config. Set to true to run."}' >&2
  exit 1
fi

# --- 결과 디렉토리 ---
STRESS_DIR="$PROJECT_ROOT/.orchestration/stress-test"
mkdir -p "$STRESS_DIR" 2>/dev/null
TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
RESULT_FILE="$STRESS_DIR/${TIMESTAMP}-${BYPASS_COMPONENT}.json"

echo "[$(date '+%H:%M:%S')] [stress-test] START component=$BYPASS_COMPONENT task=\"$TASK\"" >> "$LOG_DIR/session-log.md"

# --- bypass 환경변수 매핑 ---
get_bypass_env() {
  case "$1" in
    contract)  echo "BYPASS_CONTRACT" ;;
    evaluator) echo "BYPASS_EVALUATOR" ;;
    review)    echo "BYPASS_REVIEW" ;;
    policy)    echo "BYPASS_POLICY" ;;
  esac
}

BYPASS_VAR=$(get_bypass_env "$BYPASS_COMPONENT")

# --- Run A: 정상 실행 ---
echo "[$(date '+%H:%M:%S')] [stress-test] Run A (normal) starting..." >> "$LOG_DIR/session-log.md"
RUN_A_START=$(date +%s)

RUN_A_EVAL=""
if [ "$BYPASS_COMPONENT" = "evaluator" ] || [ "$BYPASS_COMPONENT" = "contract" ]; then
  # evaluate.sh 실행
  RUN_A_EVAL=$(bash "$SCRIPT_DIR/evaluate.sh" 2>/dev/null)
fi

RUN_A_END=$(date +%s)
RUN_A_DURATION=$((RUN_A_END - RUN_A_START))

RUN_A_JUDGMENT=$(echo "$RUN_A_EVAL" | python3 -c "import json,sys; print(json.load(sys.stdin).get('judgment','N/A'))" 2>/dev/null || echo "N/A")
RUN_A_ISSUES=0

# --- Run B: bypass 실행 ---
echo "[$(date '+%H:%M:%S')] [stress-test] Run B (bypass=$BYPASS_COMPONENT) starting..." >> "$LOG_DIR/session-log.md"
RUN_B_START=$(date +%s)

RUN_B_EVAL=""
if [ "$BYPASS_COMPONENT" = "evaluator" ]; then
  export BYPASS_EVALUATOR=1
  RUN_B_EVAL=$(bash "$SCRIPT_DIR/evaluate.sh" 2>/dev/null)
  unset BYPASS_EVALUATOR
elif [ "$BYPASS_COMPONENT" = "contract" ]; then
  export BYPASS_CONTRACT=1
  RUN_B_EVAL=$(bash "$SCRIPT_DIR/evaluate.sh" 2>/dev/null)
  unset BYPASS_CONTRACT
elif [ "$BYPASS_COMPONENT" = "review" ]; then
  export BYPASS_REVIEW=1
  RUN_B_EVAL='{"status": "bypassed", "judgment": "PASS"}'
  unset BYPASS_REVIEW
elif [ "$BYPASS_COMPONENT" = "policy" ]; then
  export BYPASS_POLICY=1
  RUN_B_EVAL=$(bash "$SCRIPT_DIR/evaluate.sh" 2>/dev/null)
  unset BYPASS_POLICY
fi

RUN_B_END=$(date +%s)
RUN_B_DURATION=$((RUN_B_END - RUN_B_START))

RUN_B_JUDGMENT=$(echo "$RUN_B_EVAL" | python3 -c "import json,sys; print(json.load(sys.stdin).get('judgment','N/A'))" 2>/dev/null || echo "N/A")

# --- 비교 결과 생성 ---
TMPPY=$(mktemp /tmp/stress_compare_XXXXXX.py)
cat > "$TMPPY" << 'PYEOF'
import json, sys
from datetime import datetime

component = sys.argv[1]
task = sys.argv[2]
run_a_judgment = sys.argv[3]
run_a_duration = int(sys.argv[4])
run_b_judgment = sys.argv[5]
run_b_duration = int(sys.argv[6])
result_file = sys.argv[7]

# 품질 차이 판정
if run_a_judgment == run_b_judgment:
    quality_diff = "equivalent"
elif run_b_judgment in ("bypassed", "PASS") and run_a_judgment != "PASS":
    quality_diff = "inflated"  # bypass가 더 관대
else:
    quality_diff = "degraded"

time_saved = run_a_duration - run_b_duration

# recommendation 판정
if quality_diff == "equivalent":
    recommendation = "REMOVE"
    reason = "component makes no difference in outcome"
elif quality_diff == "inflated":
    recommendation = "KEEP"
    reason = "bypass inflates results, component catches real issues"
elif quality_diff == "degraded":
    recommendation = "KEEP"
    reason = "quality degrades without component"
else:
    recommendation = "CONDITIONAL"
    reason = "mixed results, needs more data"

result = {
    "timestamp": datetime.now().astimezone().isoformat(),
    "component_tested": component,
    "task": task,
    "run_a": {
        "mode": "normal",
        "judgment": run_a_judgment,
        "duration_sec": run_a_duration
    },
    "run_b": {
        "mode": f"bypass_{component}",
        "judgment": run_b_judgment,
        "duration_sec": run_b_duration
    },
    "delta": {
        "quality_diff": quality_diff,
        "time_saved_sec": time_saved
    },
    "recommendation": recommendation,
    "reason": reason
}

with open(result_file, 'w', encoding='utf-8') as f:
    json.dump(result, f, indent=2, ensure_ascii=False)

print(json.dumps(result, indent=2, ensure_ascii=False))
PYEOF

COMPARE_RESULT=$(python3 "$TMPPY" "$BYPASS_COMPONENT" "$TASK" "$RUN_A_JUDGMENT" "$RUN_A_DURATION" "$RUN_B_JUDGMENT" "$RUN_B_DURATION" "$RESULT_FILE" 2>&1)
rm -f "$TMPPY"

echo "$COMPARE_RESULT"

RECOMMENDATION=$(echo "$COMPARE_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('recommendation','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
echo "[$(date '+%H:%M:%S')] [stress-test] DONE component=$BYPASS_COMPONENT recommendation=$RECOMMENDATION" >> "$LOG_DIR/session-log.md"
