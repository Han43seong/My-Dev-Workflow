---
description: 복잡한 요청을 서브태스크로 분해 → 각각 최적 모델 자동 배정 → 병렬/순차 실행 → 통합 보고서
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-model.sh:*)", "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-parallel.sh:*)", "Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-sequential.sh:*)"]
---
# /orchestrate — 복잡한 태스크를 자동으로 분해 & 실행

여러 단계가 얽힌 복잡한 요청을 서브태스크로 쪼개고,
각각에 가장 적합한 모델을 배정해서 자동으로 실행합니다.

**패턴**: `복합 태스크 → 서브태스크 분해 → [병렬/순차 실행] → 통합 보고서`

## 사용법
```
/orchestrate <복잡한 요청>
```

## 언제 쓰나
- "설계 + 구현 + 리뷰"처럼 여러 단계가 묶인 요청
- 어떤 모델에게 맡길지 모를 때 자동 라우팅 원할 때
- 대형 태스크 전체 파이프라인 자동화

## 예시
```
/orchestrate 새로운 결제 API를 설계하고 보안 검토까지 해줘
/orchestrate 이 레거시 모듈 리팩토링 계획 세우고 코드 리뷰까지
/orchestrate 현재 파이프라인 버그 찾고 수정 방안 제시해줘
```

## 실행 흐름

### Phase 1: 분석 & 분해
1. `$ARGUMENTS`의 복합 태스크 분석
2. 독립적인 서브태스크로 분해
3. 각 서브태스크에 카테고리 배정 → 모델 결정
4. 의존 관계 파악 (병렬 가능 vs 순차 필요)

### Phase 2: 사용자 확인
5. 분해 결과 표시:
   ```
   서브태스크 1: [설명] → [모델] (카테고리: xxx)
   서브태스크 2: [설명] → [모델] (카테고리: xxx)
   서브태스크 3: [설명] → [모델] ← 1번 결과 필요
   ```
6. 사용자 승인 대기

### Phase 3: 실행
7. 독립 태스크 → `bash "${CLAUDE_PLUGIN_ROOT}/scripts/invoke-parallel.sh"` 또는 개별 `invoke-model.sh`
8. 의존성 있는 태스크 → `bash "${CLAUDE_PLUGIN_ROOT}/scripts/invoke-sequential.sh"` 또는 선행 결과 포함 순차 실행

### Phase 4: 합성
9. 전체 결과 취합
10. 통합 보고서: 각 서브태스크 요약 + 전체 결론 + 다음 단계 제안

## 카테고리 → 모델 라우팅
| 카테고리 | 모델 |
|---------|------|
| backend, security, architecture, debug | codex |
| frontend, research, design | gemini |
| review, quick | opus |
