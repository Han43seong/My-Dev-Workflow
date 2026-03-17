---
description: 원하는 모델을 직접 지정해서 작업 위임 (codex=코딩/보안, gemini=리서치, opus=판단/리뷰)
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-model.sh:*)", "Read(*/.orchestration/results/*)"]
---
# /delegate — 특정 모델에 1:1 자문 위임

원하는 Advisor 모델을 지정해서 분석/제안을 받습니다.
실제 코드 수정이 필요하면 메인 에이전트가 Advisor 제안을 기반으로 실행합니다.

| 모델 | 적합한 작업 |
|------|------------|
| opus | 코드 리뷰, 복잡한 추론, 범용 분석 |
| codex | 코딩, 디버깅, 보안 분석, 아키텍처 설계 |
| gemini | 리서치, UI, 비교 분석, 대용량 처리 |

## 사용법
```
/delegate <모델> <태스크>
```

## 실행 방법 (v3.1: Non-Blocking)

### Phase 1: Advisory (비동기)
1. `$ARGUMENTS`에서 첫 단어를 모델 alias로, 나머지를 태스크로 분리
2. 코드 분석 태스크인 경우, 관련 파일을 Read로 읽어 컨텍스트 확보
3. 사용자에게 "<모델> Advisor에게 의견을 요청합니다." 안내
4. Task 도구로 백그라운드 서브에이전트 생성:
   - subagent_type: general-purpose
   - model: sonnet
   - run_in_background: true
   - prompt: |
       다음 명령을 실행하고 결과를 반환하라:
       bash "~/.claude/orchestration/scripts/invoke-model.sh" "<alias>" "<코드 컨텍스트 + 태스크>"
       결과 텍스트를 그대로 반환하라.
5. 사용자와 대화 계속 가능

### Phase 2: Synthesis (완료 알림 후)
6. 서브에이전트 완료 시 Advisor 결과를 수신
7. Advisor 응답을 분석하고 핵심 인사이트를 사용자에게 전달
8. 코드 수정이 필요한 경우 → 구체적 실행 계획 수립

### Phase 3: Execution (코드 변경 시, 비동기)
9. 코드 수정이 필요하면 Task(background, sonnet)로 실행:
   - prompt에 구체적 수정 지시 포함 (파일 경로, before/after 코드)
   - "실행을 시작했습니다. 계속 대화하세요." 안내
10. 완료 시 변경 사항을 사용자에게 보고
