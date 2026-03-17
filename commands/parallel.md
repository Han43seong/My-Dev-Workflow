---
description: opus·codex·gemini 3개 모델이 동시에 같은 질문에 답변 → 공통점·차이점 비교 합성
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-parallel.sh:*)", "Read(*/.orchestration/results/*)"]
---
# /parallel — 여러 모델이 동시에 같은 질문에 답변

opus, codex, gemini 3개 Advisor 모델이 동시에 실행되어 각자의 관점을 제시합니다.

**패턴**: `질문 → [Advisor 3개 병렬] → 메인(Opus) 비교 & 합성`

## 사용법
```
/parallel <질문 또는 태스크>
```

## 실행 방법 (v3.1: Non-Blocking)

### Phase 1: Advisory (비동기)
1. `$ARGUMENTS`를 태스크로 사용
2. 사용자에게 "3개 모델에 의견을 요청합니다." 안내
3. Task 도구로 백그라운드 서브에이전트 생성:
   - subagent_type: general-purpose
   - model: sonnet
   - run_in_background: true
   - prompt: |
       다음 명령을 실행하고 결과를 반환하라:
       1. bash "~/.claude/orchestration/scripts/invoke-parallel.sh" "<태스크>" opus codex gemini
       2. 출력에서 ORCH_RESULT_FILE= 뒤의 경로를 추출
       3. 해당 파일을 Read로 읽어서 전체 내용을 반환
4. 사용자와 대화 계속 가능

### Phase 2: Synthesis (완료 알림 후)
5. 서브에이전트 완료 시 결과를 수신
6. 3개 모델 결과를 비교 분석:
   - 각 모델 핵심 요약 (모델명 표시)
   - **공통점**: 모두 동의하는 부분
   - **차이점**: 의견이 갈리는 부분
   - **합성 결론**: 최종 판단 제시
7. 사용자에게 종합 결과 전달
