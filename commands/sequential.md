---
description: 모델A가 분석/제안 → 모델B가 비판적 검증 → 메인이 종합하여 실행
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-sequential.sh:*)", "Read(*/.orchestration/results/*)"]
---
# /sequential — A가 제안 → B가 검증 → 메인이 실행

첫 번째 Advisor가 분석/제안하고, 두 번째 Advisor가 검증합니다.
메인 에이전트가 두 의견을 종합하여 최종 계획을 세웁니다.

**패턴**: `[Advisor A 제안] → [Advisor B 검증] → Opus 종합 → 실행`

## 사용법
```
/sequential <모델A> <모델B> <태스크>
```

## 실행 방법 (v3.1: Non-Blocking)

### Phase 1: Advisory (비동기)
1. `$ARGUMENTS`에서 모델A, 모델B, 태스크 분리
2. 사용자에게 "<A> → <B> 순차 자문을 요청합니다." 안내
3. Task 도구로 백그라운드 서브에이전트 생성:
   - subagent_type: general-purpose
   - model: sonnet
   - run_in_background: true
   - prompt: |
       다음 명령을 실행하고 결과를 반환하라:
       1. bash "~/.claude/orchestration/scripts/invoke-sequential.sh" "<A>" "<B>" "<태스크>"
       2. 출력에서 ORCH_RESULT_FILE= 뒤의 경로를 추출
       3. 해당 파일을 Read로 읽어서 전체 내용을 반환
4. 사용자와 대화 계속 가능

### Phase 2: Synthesis (완료 알림 후)
5. 서브에이전트 완료 시 결과 수신
6. A의 제안 + B의 검증 결과를 종합 분석:
   - A의 핵심 결론
   - B가 발견한 이슈/개선점
   - 최종 통합 결론 + 실행 계획

### Phase 3: Execution (코드 변경 시, 비동기)
7. 코드 수정이 필요하면 Task(background, sonnet)로 실행
8. 완료 시 변경 사항을 사용자에게 보고
