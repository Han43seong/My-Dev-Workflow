#!/bin/bash
# evaluate.sh — v6 Evaluator: 프로젝트 검증 실행 + 판정
# Usage: evaluate.sh [--project-type <default|unity|...>]
#
# 결과: .orchestration/eval/<timestamp>-eval.json + latest-eval.json

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config.json"
PROJECT_ROOT="${PROJECT_ROOT:-$(pwd)}"
PROJECT_OVERRIDE="$PROJECT_ROOT/.orchestration/eval-config.json"

# --- bypass 체크 ---
if [ "${BYPASS_EVALUATOR:-0}" = "1" ]; then
  LOG_DIR_BP="${PROJECT_ROOT:-$(pwd)}/.orchestration/results"
  mkdir -p "$LOG_DIR_BP" 2>/dev/null
  echo "[$(date '+%H:%M:%S')] [evaluate] BYPASSED (stress_test)" >> "$LOG_DIR_BP/session-log.md"
  echo '{"status": "bypassed", "reason": "stress_test", "judgment": "PASS"}'
  exit 0
fi

PROJECT_TYPE="default"
CONTRACT_FILE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-type) PROJECT_TYPE="$2"; shift 2 ;;
    --contract)     CONTRACT_FILE="$2"; shift 2 ;;
    *) shift ;;
  esac
done

EVAL_DIR="$PROJECT_ROOT/.orchestration/eval"
mkdir -p "$EVAL_DIR" 2>/dev/null

TIMESTAMP=$(date '+%Y%m%d-%H%M%S')
EXEC_ID="exec-${TIMESTAMP}"

STATE_FILE="$PROJECT_ROOT/.orchestration/state.json"
CURRENT_STATE="UNKNOWN"
if [ -f "$STATE_FILE" ]; then
  CURRENT_STATE=$(python3 -c "import json; print(json.load(open('$STATE_FILE',encoding='utf-8')).get('current_state','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
fi

# --- 임시 Python 파일 (MSYS heredoc 우회) ---
TMPPY=$(mktemp /tmp/evaluate_XXXXXX.py)
trap "rm -f '$TMPPY'" EXIT INT TERM

cat > "$TMPPY" << 'PYEOF'
import json, sys, subprocess, os, glob
from datetime import datetime, timezone, timedelta

config_path = sys.argv[1]
project_override = sys.argv[2]
project_type = sys.argv[3]
project_root = sys.argv[4]
eval_dir = sys.argv[5]
timestamp = sys.argv[6]
exec_id = sys.argv[7]
current_state = sys.argv[8]
contract_path = sys.argv[9] if len(sys.argv) > 9 else ''

config = json.load(open(config_path, encoding='utf-8'))
evaluator = config.get('evaluator', {})

# 프로젝트 override (partial patch)
if os.path.exists(project_override):
    override = json.load(open(project_override, encoding='utf-8'))
    if 'commands' in override:
        target = evaluator.get('commands', {}).get(project_type,
                 evaluator.get('commands', {}).get('default', {}))
        for k, v in override['commands'].items():
            target[k] = v
    if 'rules' in override:
        override_rules = {r['id']: r for r in override['rules'] if 'id' in r}
        for i, rule in enumerate(evaluator.get('rules', [])):
            if rule.get('id') in override_rules:
                evaluator['rules'][i].update(override_rules[rule['id']])
    if 'thresholds' in override:
        evaluator.setdefault('thresholds', {}).update(override['thresholds'])

commands = evaluator.get('commands', {}).get(project_type,
           evaluator.get('commands', {}).get('default', {}))
thresholds = evaluator.get('thresholds', {})
test_crit = thresholds.get('test_critical_threshold', 5)
rules = evaluator.get('rules', [])
priority_order = evaluator.get('priority', ['ROLLBACK', 'ESCALATE', 'RETRY', 'PASS'])

# 각 검증 항목 실행
results = {}
checks = ['build', 'lint', 'typecheck', 'test', 'security']

for check in checks:
    cmd = commands.get(check)
    if cmd is None:
        results[check] = {'status': 'skip', 'detail': 'command not configured'}
        continue
    try:
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True,
                              timeout=300, cwd=project_root)
        if proc.returncode == 0:
            results[check] = {'status': 'pass', 'detail': None}
            output = (proc.stdout + proc.stderr).lower()
            warn_count = output.count('warning')
            if warn_count > 0:
                results[check]['detail'] = {'warning_count': warn_count}
        else:
            detail = proc.stderr.strip()[:200] if proc.stderr.strip() else proc.stdout.strip()[:200]
            results[check] = {'status': 'fail', 'detail': detail}

            if check == 'test':
                try:
                    tj = json.loads(proc.stdout)
                    if 'numFailedTests' in tj:
                        results[check]['detail'] = {
                            'passed': tj.get('numPassedTests', 0),
                            'failed': tj.get('numFailedTests', 0)
                        }
                except Exception:
                    pass

            if check == 'security':
                try:
                    sj = json.loads(proc.stdout)
                    vulns = sj.get('metadata', {}).get('vulnerabilities', {})
                    if vulns.get('critical', 0) > 0 or vulns.get('high', 0) > 0:
                        results[check]['status'] = 'critical'
                    else:
                        results[check]['status'] = 'warning'
                except Exception:
                    results[check]['status'] = 'warning'
    except subprocess.TimeoutExpired:
        results[check] = {'status': 'fail', 'detail': 'timeout (300s)'}
    except Exception as e:
        results[check] = {'status': 'fail', 'detail': str(e)[:200]}

# 판정 로직
judgments = []
test_failed = 0
if isinstance(results.get('test', {}).get('detail'), dict):
    test_failed = results['test']['detail'].get('failed', 0)
elif results.get('test', {}).get('status') == 'fail':
    test_failed = 1

for rule in rules:
    rid = rule.get('id', '')
    jdg = rule.get('judgment', 'RETRY')
    matched = False
    if rid == 'build_fail' and results.get('build', {}).get('status') == 'fail':
        matched = True
    elif rid == 'security_crit' and results.get('security', {}).get('status') == 'critical':
        matched = True
    elif rid == 'test_mass_fail' and test_failed > test_crit:
        matched = True
    elif rid == 'typecheck_fail' and results.get('typecheck', {}).get('status') == 'fail':
        matched = True
    elif rid == 'test_minor_fail' and test_failed > 0 and test_failed <= test_crit:
        matched = True
    elif rid == 'lint_fail' and results.get('lint', {}).get('status') == 'fail':
        matched = True
    elif rid == 'security_warn' and results.get('security', {}).get('status') == 'warning':
        matched = True
    if matched:
        judgments.append((jdg, rid))

if not judgments:
    final = 'PASS'
    reason = 'all checks passed or skipped'
else:
    best_j = None
    triggered = []
    for j, rid in judgments:
        if best_j is None or priority_order.index(j) < priority_order.index(best_j):
            best_j = j
    final = best_j
    triggered = [rid for j, rid in judgments if j == final]
    reason = ', '.join(triggered)

# warning_count 합산
total_warnings = 0
for r in results.values():
    if isinstance(r.get('detail'), dict) and 'warning_count' in r['detail']:
        total_warnings += r['detail']['warning_count']

# Contract 판정 (있으면)
contract_evaluation = None
if contract_path and os.path.exists(contract_path):
    try:
        cdata = json.load(open(contract_path, encoding='utf-8'))
        if cdata.get('status') == 'agreed':
            criteria = cdata.get('criteria', [])
            # 기계적 테스트 결과 기반으로 criteria 자동 판정
            # build/test가 실패하면 기능 검증 자체가 불가 → 전부 FAIL
            all_mechanical_pass = all(
                r.get('status') in ('pass', 'skip')
                for r in results.values()
            )
            criteria_results = []
            for cr in criteria:
                if not all_mechanical_pass:
                    criteria_results.append({
                        'id': cr['id'],
                        'verdict': 'FAIL',
                        'evidence': 'mechanical checks failed, cannot verify'
                    })
                else:
                    # build/test PASS 시: criteria는 잠정 PASS (실제 기능 검증은 review-loop에서)
                    criteria_results.append({
                        'id': cr['id'],
                        'verdict': 'PENDING',
                        'evidence': 'mechanical checks passed, awaiting functional review'
                    })

            failed_criteria = [cr['id'] for cr in criteria_results if cr['verdict'] == 'FAIL']
            pending_criteria = [cr['id'] for cr in criteria_results if cr['verdict'] == 'PENDING']

            contract_judgment = 'contract_fail' if failed_criteria else ('contract_pending' if pending_criteria else 'contract_pass')

            contract_evaluation = {
                'contract_id': cdata.get('task_id', ''),
                'criteria_results': criteria_results,
                'contract_judgment': contract_judgment,
                'failed_criteria': failed_criteria
            }

            # judgment 결합: 기계적 PASS + contract_fail → RETRY
            if final == 'PASS' and contract_judgment == 'contract_fail':
                final = 'RETRY'
                reason = f'{reason}, contract_fail ({len(failed_criteria)} criteria)'
    except Exception:
        pass

# 결과 생성
eval_result = {
    'timestamp': datetime.now().astimezone().isoformat(),
    'execution_id': exec_id,
    'state': current_state,
    'results': results,
    'warning_count': total_warnings,
    'judgment': final,
    'reason': reason
}
if contract_evaluation:
    eval_result['contract_evaluation'] = contract_evaluation

ts_file = os.path.join(eval_dir, f'{timestamp}-eval.json')
latest_file = os.path.join(eval_dir, 'latest-eval.json')

with open(ts_file, 'w', encoding='utf-8') as f:
    json.dump(eval_result, f, indent=2, ensure_ascii=False)
with open(latest_file, 'w', encoding='utf-8') as f:
    json.dump(eval_result, f, indent=2, ensure_ascii=False)

# 이력 관리
max_hist = evaluator.get('max_history', 10)
old_files = sorted(glob.glob(os.path.join(eval_dir, '*-eval.json')))
old_files = [f for f in old_files if 'latest' not in f]
while len(old_files) > max_hist:
    os.remove(old_files.pop(0))

print(json.dumps(eval_result, indent=2, ensure_ascii=False))
PYEOF

EVAL_RESULT=$(python3 "$TMPPY" "$CONFIG_FILE" "$PROJECT_OVERRIDE" "$PROJECT_TYPE" "$PROJECT_ROOT" "$EVAL_DIR" "$TIMESTAMP" "$EXEC_ID" "$CURRENT_STATE" "$CONTRACT_FILE" 2>&1)
EVAL_EXIT=$?

echo "$EVAL_RESULT"

# 세션 로그
LOG_DIR="$PROJECT_ROOT/.orchestration/results"
mkdir -p "$LOG_DIR" 2>/dev/null
JUDGMENT=$(echo "$EVAL_RESULT" | python3 -c "import json,sys; print(json.load(sys.stdin).get('judgment','UNKNOWN'))" 2>/dev/null || echo "UNKNOWN")
echo "[$(date '+%H:%M:%S')] [evaluate] $JUDGMENT ($PROJECT_TYPE)" >> "$LOG_DIR/session-log.md"

exit $EVAL_EXIT
