---
description: 제안자 모델이 주장 → 반박자 모델이 약점·리스크 집중 공격 → 숨겨진 문제 발굴
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-adversarial.sh:*)", "Read(*/.orchestration/results/*)"]
---
# /adversarial — 제안 vs 반박 (논쟁으로 약점 찾기)

제안자 Advisor가 주장을 펼치고, 반박자 Advisor가 적극적으로 약점을 공격합니다.

**패턴**: `[제안자 주장] → [반박자 공격] → Opus 종합 판단`

## 사용법
```
/adversarial <제안자> <반박자> <검토할 주제>
```

## 실행 방법 (v3.1: Non-Blocking)

### Phase 1: Advisory (비동기)
1. `$ARGUMENTS`에서 제안자, 반박자, 주제 분리
2. 사용자에게 "<제안자> vs <반박자> 논쟁을 시작합니다." 안내
3. Task 도구로 백그라운드 서브에이전트 생성:
   - subagent_type: general-purpose
   - model: sonnet
   - run_in_background: true
   - prompt: |
       다음 명령을 실행하고 결과를 반환하라:
       1. bash "~/.claude/orchestration/scripts/invoke-adversarial.sh" "<제안자>" "<반박자>" "<주제>"
       2. 출력에서 ORCH_RESULT_FILE= 뒤의 경로를 추출
       3. 해당 파일을 Read로 읽어서 전체 내용을 반환
4. 사용자와 대화 계속 가능

### Phase 2: Synthesis (완료 알림 후)
5. 서브에이전트 완료 시 결과 수신
6. 찬반 의견 종합:
   - **제안** (제안자): 핵심 주장과 근거
   - **반박** (반박자): 발견된 취약점/문제점
   - **종합**: 어느 쪽이 더 설득력 있는가? 최종 판단
