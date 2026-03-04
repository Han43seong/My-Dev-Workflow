---
description: 3개 모델이 각자 판단 → 2/3 이상 동의 시 APPROVED, 의견 분분 시 DISPUTED
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/invoke-parallel.sh:*)"]
---
# /consensus — 다수결 투표로 결정

3개 모델이 동일한 질문에 각자 판단을 내리고 2/3 이상 동의하면 승인합니다.
확신이 서지 않는 기술 결정을 객관적으로 검증할 때 사용.

**패턴**: `[opus | codex | gemini] 각자 판단 → 2/3 동의 = APPROVED / 분분 = DISPUTED`

## 사용법
```
/consensus <결정 또는 질문>
```

## 언제 쓰나
- "이렇게 해도 되나?" 확신이 서지 않을 때
- 리팩토링 / 마이그레이션의 안전성 확인
- 기술 스택 또는 라이브러리 선택
- 배포 전 최종 검증

## 예시
```
/consensus 이 리팩토링이 안전한가?
/consensus TypeScript 마이그레이션 지금 진행해도 되는가?
/consensus Redis를 캐시 레이어로 도입해야 하는가?
/consensus 이 인증 방식에 보안 문제가 없는가?
```

## 실행 방법
1. `$ARGUMENTS`를 질문으로 사용
2. 병렬 실행:
   ```
   bash "${CLAUDE_PLUGIN_ROOT}/scripts/invoke-parallel.sh" "<질문>" opus codex gemini
   ```
3. 각 모델 입장 정리 (찬성/반대/조건부)
4. 판정:
   - **2/3 이상 동의** → APPROVED — 합성된 결론 제시
   - **과반 미달** → DISPUTED — 쟁점 정리 + 각 근거 + 추가 논의 제안
