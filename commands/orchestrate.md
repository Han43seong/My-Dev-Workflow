---
description: 복잡한 요청을 서브태스크로 분해 → 각각 최적 모델 자동 배정 → 병렬/순차 실행 → 통합 보고서
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-model.sh:*)", "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-parallel.sh:*)", "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-sequential.sh:*)", "Read(*/.orchestration/results/*)"]
---
# /orchestrate — 복잡한 태스크를 자동으로 분해 & 실행

여러 단계가 얽힌 복잡한 요청을 서브태스크로 쪼개고, 각각에 Advisor를 배정합니다.

**패턴**: `분해 → [Advisor 병렬/순차] → Opus 종합 → [Executor 실행]`

## 사용법
```
/orchestrate <복잡한 요청>
```

## 실행 흐름 (v3.1: Non-Blocking)

### Phase 0: 분해 & 라우팅 (메인)
1. `$ARGUMENTS`의 복합 태스크 분석
2. 독립적인 서브태스크로 분해
3. 각 서브태스크에 카테고리 → 모델 배정
4. 사용자에게 분해 결과 보고 + 승인 대기

### Phase 1: Advisory (비동기)
5. 승인 후 독립 서브태스크별 Task(background, sonnet) 생성:
   - 각 서브에이전트가 해당 Advisor 스크립트 실행
   - 병렬 가능한 것은 동시 디스패치
6. 사용자와 대화 계속 가능

### Phase 2: Synthesis (각 완료 시)
7. 각 서브태스크 완료 시 결과 수집
8. 전체 결과 종합 → 통합 실행 계획 수립
9. 사용자에게 보고

### Phase 3: Execution (비동기)
10. 코드 변경이 필요한 서브태스크별 Task(background, sonnet) 생성
11. 각 Executor가 구체적 수정 지시를 기계적으로 적용
12. 전체 완료 시 통합 결과 보고

## 카테고리 → 모델 라우팅
| 카테고리 | 모델 |
|---------|------|
| backend, security, architecture, debug | codex |
| frontend, research, design | gemini |
| review, quick | opus |
