---
description: 3개 모델이 각자 판단 → 2/3 이상 동의 시 APPROVED, 의견 분분 시 DISPUTED
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-parallel.sh:*)", "Read(*/.orchestration/results/*)"]
---
# /consensus — 다수결 투표로 결정

3개 Advisor가 동일한 질문에 각자 판단을 내리고, 메인이 2/3 합의 여부를 판정합니다.

**패턴**: `[3개 Advisor 투표] → Opus 집계 → APPROVED / DISPUTED`

## 사용법
```
/consensus <결정 또는 질문>
```

## 실행 방법 (v3.1: Non-Blocking)

### Phase 1: Advisory (비동기)
1. `$ARGUMENTS`를 질문으로 사용
2. 사용자에게 "3개 모델에 투표를 요청합니다." 안내
3. Task 도구로 백그라운드 서브에이전트 생성:
   - subagent_type: general-purpose
   - model: sonnet
   - run_in_background: true
   - prompt: |
       다음 명령을 실행하고 결과를 반환하라:
       1. bash "~/.claude/orchestration/scripts/invoke-parallel.sh" "<질문>" opus codex gemini
       2. 출력에서 ORCH_RESULT_FILE= 뒤의 경로를 추출
       3. 해당 파일을 Read로 읽어서 전체 내용을 반환
4. 사용자와 대화 계속 가능

### Phase 2: Synthesis (완료 알림 후)
5. 서브에이전트 완료 시 결과 수신
6. 각 모델 입장 정리 (찬성/반대/조건부)
7. 판정:
   - **2/3 이상 동의** → APPROVED — 합성된 결론 제시
   - **과반 미달** → DISPUTED — 쟁점 정리 + 각 근거 + 추가 논의 제안
