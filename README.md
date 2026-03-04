# Multi-Model Orchestrator

Claude Code 플러그인 — **opus(Claude), codex(OpenAI), gemini(Google)** 3개 AI 모델을 CLI subprocess로 호출하여 병렬/순차/합의 패턴으로 조율합니다.

하나의 모델에 의존하지 않고, 여러 모델의 관점을 조합하여 더 정확하고 균형 잡힌 결과를 얻을 수 있습니다.

## 설치

### 1. 필수 CLI 도구 설치

이 플러그인은 3개 AI CLI가 모두 설치되어 있어야 동작합니다:

```bash
npm install -g @anthropic-ai/claude-code
npm install -g @openai/codex
npm install -g @google/gemini-cli
```

설치 후 각 CLI에 로그인하세요:
```bash
claude         # Anthropic 계정 로그인
codex auth     # OpenAI 계정 로그인
gemini         # Google 계정 로그인
```

### 2. 플러그인 설치

```bash
claude plugin add Han43seong/multi-model-orchestrator
```

설치 완료 후 Claude Code에서 `/`를 입력하면 6개의 오케스트레이션 커맨드가 표시됩니다.

---

## 슬래시 커맨드

### `/delegate` — 특정 모델에 1:1 위임

원하는 모델을 직접 지정하여 작업을 맡기는 가장 단순한 패턴입니다.
어떤 모델이 적합한지 이미 알고 있을 때 사용합니다.

```
/delegate <모델> <태스크>
```

**모델별 적합한 작업:**

| 모델 | 적합한 작업 |
|------|------------|
| `opus` | 코드 리뷰, 복잡한 추론, 범용 코딩, 아키텍처 판단 |
| `codex` | 백엔드 구현, 디버깅, 보안 분석, 성능 최적화 |
| `gemini` | 리서치, UI/UX 설계, 기술 비교, 대용량 컨텍스트 처리 |

**예시:**
```
/delegate codex 이 API의 보안 취약점 찾아줘
/delegate gemini REST vs GraphQL 장단점 비교해줘
/delegate opus 이 함수의 시간복잡도 분석해줘
```

---

### `/parallel` — 3개 모델 동시 실행 + 비교

opus, codex, gemini 3개 모델이 **동시에** 같은 질문에 답변합니다.
오케스트레이터(Opus)가 3개 결과의 공통점과 차이점을 분석하여 합성된 결론을 제시합니다.

```
/parallel <질문 또는 태스크>
```

**언제 쓰나:**
- 중요한 설계 결정에서 다양한 관점이 필요할 때
- 어떤 모델이 더 잘 답하는지 비교하고 싶을 때
- 하나의 모델만으로는 확신이 서지 않을 때

**예시:**
```
/parallel 이 데이터베이스 스키마 설계 리뷰해줘
/parallel 마이크로서비스 도입 시 주요 고려사항은?
/parallel 이 코드에서 성능 병목 지점 찾아줘
```

**출력 형식:**
```
=== opus (exit:0) ===
[opus 응답]

=== codex (exit:0) ===
[codex 응답]

=== gemini (exit:0) ===
[gemini 응답]
```
이후 오케스트레이터가 공통점/차이점/합성 결론을 정리합니다.

---

### `/sequential` — A가 작업 → B가 검증

첫 번째 모델(A)이 결과물을 만들고, 두 번째 모델(B)이 그 결과를 **비판적으로 검증/보완**합니다.
단계별 파이프라인이 필요하거나, 한 모델의 결과를 다른 모델이 교차 검증할 때 사용합니다.

```
/sequential <모델A> <모델B> <태스크>
```

**추천 조합:**

| 시나리오 | 조합 | 이유 |
|---------|------|------|
| 구현 → 리뷰 | `codex → opus` | codex가 코드 작성, opus가 품질 검증 |
| 설계 → 보안 검토 | `gemini → codex` | gemini가 아키텍처 제안, codex가 보안 분석 |
| 리서치 → 사실 검증 | `gemini → opus` | gemini가 정보 수집, opus가 정확성 검증 |
| 코드 작성 → 버그 탐색 | `opus → codex` | opus가 구현, codex가 디버깅 관점 검토 |

**예시:**
```
/sequential codex opus 이 결제 모듈 구현해줘
/sequential gemini codex 이 마이크로서비스 아키텍처 검토해줘
```

---

### `/adversarial` — 제안 vs 반박 (논쟁)

제안자 모델이 해결책을 주장하고, 반박자 모델이 **약점만 집중 공격**합니다.
일반적인 리뷰가 아닌, 의도적으로 반대 입장에서 문제를 찾는 방식입니다.
중요한 기술 결정 전에 숨겨진 리스크를 발굴할 때 효과적입니다.

```
/adversarial <제안자> <반박자> <검토할 주제>
```

**언제 쓰나:**
- 새로운 기술/라이브러리 도입 전 리스크 점검
- "이 설계가 정말 최선인가?" 의구심이 들 때
- 보안 설계의 허점 탐색
- 팀 내 기술 결정에 대한 객관적 반론이 필요할 때

**예시:**
```
/adversarial codex gemini Redis를 캐시 레이어로 도입해야 하는가?
/adversarial gemini codex 이 마이크로서비스 분리가 올바른가?
/adversarial codex opus 이 인증 설계에 취약점이 없는가?
```

**출력 형식:**
```
=== codex (제안) ===
[해결책/주장]

=== gemini (반박) ===
[약점/리스크/대안]
```
이후 오케스트레이터가 어느 쪽이 더 설득력 있는지 종합 판단합니다.

---

### `/consensus` — 다수결 투표

3개 모델이 동일한 질문에 **각자 독립적으로** 판단을 내립니다.
2/3 이상이 같은 결론이면 승인, 의견이 분분하면 쟁점을 정리합니다.

```
/consensus <결정 또는 질문>
```

**판정 기준:**
- **2/3 이상 동의** → **APPROVED** — 합의된 결론 제시
- **과반 미달** → **DISPUTED** — 쟁점 정리 + 각 근거 + 추가 논의 제안

**언제 쓰나:**
- "이렇게 해도 되나?" 확신이 서지 않을 때
- 리팩토링/마이그레이션의 안전성 확인
- 기술 스택 또는 라이브러리 선택 검증
- 배포 전 최종 점검

**예시:**
```
/consensus 이 리팩토링이 안전한가?
/consensus TypeScript 마이그레이션 지금 진행해도 되는가?
/consensus Redis를 캐시 레이어로 도입해야 하는가?
/consensus 이 인증 방식에 보안 문제가 없는가?
```

---

### `/orchestrate` — 복합 태스크 자동 분해

여러 단계가 얽힌 복잡한 요청을 **서브태스크로 자동 분해**하고,
각각에 최적의 모델을 배정하여 병렬/순차로 실행한 뒤 통합 보고서를 생성합니다.

```
/orchestrate <복잡한 요청>
```

**실행 흐름:**
1. **분석** — 복합 태스크를 독립 서브태스크로 분해
2. **라우팅** — 각 서브태스크에 카테고리 배정 → 최적 모델 결정
3. **사용자 확인** — 분해 결과를 보여주고 승인 대기
4. **실행** — 독립 태스크는 병렬, 의존성 있는 태스크는 순차 실행
5. **합성** — 전체 결과를 취합하여 통합 보고서 작성

**카테고리 → 모델 자동 라우팅:**

| 카테고리 | 모델 |
|---------|------|
| backend, security, architecture, debug | codex |
| frontend, research, design | gemini |
| review, quick | opus |

**예시:**
```
/orchestrate 새로운 결제 API를 설계하고 보안 검토까지 해줘
/orchestrate 이 레거시 모듈 리팩토링 계획 세우고 코드 리뷰까지
/orchestrate 현재 파이프라인 버그 찾고 수정 방안 제시해줘
```

---

## 아키텍처

```
Claude Code (Opus) = 오케스트레이터
    │
    ├─ /delegate ──────→ invoke-model.sh ──→ invoke-{claude,codex,gemini}.sh
    │                          │
    │                          ├─ 에이전트 프롬프트 자동 주입
    │                          ├─ 실패 시 fallback 모델로 재시도
    │                          └─ 실행 로그 기록
    │
    ├─ /parallel ──────→ invoke-parallel.sh
    │                          │
    │                          ├─ 3개 모델 백그라운드 동시 실행
    │                          ├─ 전체 타임아웃 watchdog
    │                          └─ 모델별 exit code + 결과 수집
    │
    ├─ /sequential ────→ invoke-sequential.sh
    │                          │
    │                          ├─ 모델A 실행 → 결과 캡처
    │                          └─ 모델B에 A 결과 + 검증 프롬프트 전달
    │
    ├─ /adversarial ───→ invoke-adversarial.sh
    │                          │
    │                          ├─ 제안자 실행 → 주장 캡처
    │                          └─ 반박자에 주장 + 공격 프롬프트 전달
    │
    ├─ /consensus ─────→ invoke-parallel.sh → 합의 판정
    │
    └─ /orchestrate ───→ 분해 → 라우팅 → 혼합 실행 → 통합
```

### Claude 워커 격리

Claude(opus) 워커는 부모 세션과의 충돌을 방지하기 위해 격리 환경에서 실행됩니다:

- **HOME 격리**: 워커마다 `~/.claude-workers/worker-<PID>/` 생성
- **환경변수 격리**: `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT`
- **stdin 격리**: `< /dev/null` (부모 세션 stdin 상속 차단)
- **자동 정리**: EXIT trap + 15분 TTL 고아 워커 정리

## 커스텀 모델 설정

플러그인 설치 후 `models.env`를 수정하여 기본 모델을 변경할 수 있습니다:

```bash
# 플러그인 디렉토리에서
CODEX_MODEL="gpt-5.3-codex"
GEMINI_MODEL="gemini-3-pro-preview"
```

## 라이선스

MIT
