# Multi-Model Orchestrator

Claude Code 플러그인 — **opus(Claude), codex(OpenAI), gemini(Google)** 3개 AI 모델을 CLI subprocess로 호출하여 병렬/순차/합의 패턴으로 조율합니다.

하나의 모델에 의존하지 않고, 여러 모델의 관점을 조합하여 더 정확하고 균형 잡힌 결과를 얻을 수 있습니다.

## v3.1 — Advisor + Synthesizer + Async Executor

### 핵심 변경

| 항목 | v1 (이전) | v3.1 (현재) |
|------|-----------|-------------|
| 외부 모델 역할 | **Worker** (도구 사용, 직접 작업) | **Advisor** (텍스트 응답만, 분석/제안) |
| 도구 접근 | `tools=full` (600s 타임아웃) | `tools=none` (120s 타임아웃) |
| 메인 에이전트 | 대기 (blocking) | **Non-Blocking** (계속 대화 가능) |
| 코드 수정 | 외부 모델이 직접 수정 | **Sonnet 서브에이전트**가 계획대로 실행 |
| 결과 저장 | stdout 캡처 (유실 위험) | **파일 기반 영속화** (.orchestration/results/) |

### 3-Phase Non-Blocking 패턴

모든 스킬이 동일한 실행 흐름을 따릅니다:

```
Phase 1: Advisory (비동기)
  └─ Task(background, sonnet) → invoke-*.sh → 모델 응답 → 결과 파일
  └─ 사용자와 메인 에이전트는 계속 대화 가능

Phase 2: Synthesis (완료 알림 후)
  └─ 메인 에이전트(Opus)가 Advisor 결과를 종합
  └─ 공통점/차이점 분석, 최종 결론 도출, 실행 계획 수립

Phase 3: Execution (코드 변경 시, 비동기)
  └─ Task(background, sonnet) → 구체적 수정 지시 기반 코드 적용
  └─ 완료 시 변경 사항 보고
```

### Advisor 규칙

모든 외부 모델은 Advisor로서 다음 규칙을 따릅니다:

- 도구를 사용하지 않음 (텍스트 응답만)
- 코드 수정 제안 시 `파일경로:라인번호` + before/after 코드블록 형식
- 주어진 코드/컨텍스트만으로 분석 (파일 탐색 없음)
- 실행은 별도 Executor(Sonnet)가 담당

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

원하는 모델을 직접 지정하여 분석/제안을 받는 가장 단순한 패턴입니다.

```
/delegate <모델> <태스크>
```

**모델별 적합한 작업:**

| 모델 | 적합한 작업 |
|------|------------|
| `opus` | 코드 리뷰, 복잡한 추론, 범용 분석 |
| `codex` | 백엔드, 디버깅, 보안 분석, 아키텍처 설계 |
| `gemini` | 리서치, UI/UX, 기술 비교, 대용량 컨텍스트 |

**예시:**
```
/delegate codex 이 API의 보안 취약점 찾아줘
/delegate gemini REST vs GraphQL 장단점 비교해줘
/delegate opus 이 함수의 시간복잡도 분석해줘
```

---

### `/parallel` — 3개 모델 동시 실행 + 비교

opus, codex, gemini 3개 모델이 **동시에** 같은 질문에 답변합니다.
메인 에이전트(Opus)가 3개 결과의 공통점과 차이점을 분석하여 합성된 결론을 제시합니다.

```
/parallel <질문 또는 태스크>
```

**예시:**
```
/parallel 이 데이터베이스 스키마 설계 리뷰해줘
/parallel 마이크로서비스 도입 시 주요 고려사항은?
/parallel 이 코드에서 성능 병목 지점 찾아줘
```

---

### `/sequential` — A가 제안 → B가 검증

첫 번째 Advisor(A)가 분석/제안하고, 두 번째 Advisor(B)가 A의 결과를 **비판적으로 검증/보완**합니다.

```
/sequential <모델A> <모델B> <태스크>
```

**추천 조합:**

| 시나리오 | 조합 | 이유 |
|---------|------|------|
| 구현 → 리뷰 | `codex → opus` | codex가 설계 제안, opus가 품질 검증 |
| 설계 → 보안 검토 | `gemini → codex` | gemini가 아키텍처 제안, codex가 보안 분석 |
| 리서치 → 사실 검증 | `gemini → opus` | gemini가 정보 수집, opus가 정확성 검증 |

**예시:**
```
/sequential codex opus 이 결제 모듈의 설계를 분석해줘
/sequential gemini codex 이 마이크로서비스 아키텍처 검토해줘
```

---

### `/adversarial` — 제안 vs 반박 (논쟁)

제안자 Advisor가 해결책을 주장하고, 반박자 Advisor가 **약점만 집중 공격**합니다.
메인 에이전트가 양측의 논거를 종합하여 최종 판단합니다.

```
/adversarial <제안자> <반박자> <검토할 주제>
```

**예시:**
```
/adversarial codex gemini Redis를 캐시 레이어로 도입해야 하는가?
/adversarial gemini codex 이 마이크로서비스 분리가 올바른가?
/adversarial codex opus 이 인증 설계에 취약점이 없는가?
```

---

### `/consensus` — 다수결 투표

3개 모델이 동일한 질문에 **각자 독립적으로** 판단을 내립니다.

```
/consensus <결정 또는 질문>
```

**판정 기준:**
- **2/3 이상 동의** → **APPROVED** — 합의된 결론 제시
- **과반 미달** → **DISPUTED** — 쟁점 정리 + 각 근거 + 추가 논의 제안

**예시:**
```
/consensus 이 리팩토링이 안전한가?
/consensus TypeScript 마이그레이션 지금 진행해도 되는가?
/consensus 이 인증 방식에 보안 문제가 없는가?
```

---

### `/orchestrate` — 복합 태스크 자동 분해

여러 단계가 얽힌 복잡한 요청을 **서브태스크로 자동 분해**하고,
각각에 최적의 모델을 배정하여 병렬/순차로 실행한 뒤 통합 보고서를 생성합니다.

```
/orchestrate <복잡한 요청>
```

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
```

---

## 아키텍처

```
Claude Code (Opus) = 오케스트레이터 + 종합 판단자
    │
    ├─ Phase 1: Advisory (비동기, Non-Blocking)
    │   │
    │   ├─ Task(background, sonnet) ─→ invoke-model.sh
    │   │       │
    │   │       ├─ invoke-claude.sh  (opus Advisor, tools=none, 120s)
    │   │       ├─ invoke-codex.sh   (codex Advisor, sandbox, 600s)
    │   │       └─ invoke-gemini.sh  (gemini Advisor, text-only, 600s)
    │   │
    │   ├─ 에이전트 프롬프트 자동 주입 (prompts/*.md)
    │   ├─ 결과를 파일로 영속화 (.orchestration/results/)
    │   └─ 사용자는 메인 에이전트와 계속 대화 가능
    │
    ├─ Phase 2: Synthesis (메인 에이전트)
    │   │
    │   └─ Advisor 결과 수신 → 종합 분석 → 실행 계획 수립
    │
    └─ Phase 3: Execution (비동기, 코드 변경 시)
        │
        └─ Task(background, sonnet) → 구체적 수정 지시 기계적 적용
```

### 스킬별 스크립트 매핑

| 스킬 | 스크립트 | 설명 |
|------|---------|------|
| `/delegate` | `invoke-model.sh` | 단일 모델 Advisor 호출 |
| `/parallel` | `invoke-parallel.sh` | 3개 모델 백그라운드 동시 실행 |
| `/sequential` | `invoke-sequential.sh` | A 실행 → B에 A 결과 전달하여 검증 |
| `/adversarial` | `invoke-adversarial.sh` | 제안자 → 반박자 교차 검증 |
| `/consensus` | `invoke-parallel.sh` | 3개 모델 투표 → 합의 판정 |
| `/orchestrate` | 혼합 | 분해 → 라우팅 → 병렬/순차 → 통합 |

### Claude 워커 격리

Claude(opus) 워커는 부모 세션과의 충돌을 방지하기 위해 격리 환경에서 실행됩니다:

- **HOME 격리**: 워커마다 `~/.claude-workers/worker-<PID>/` 생성
- **환경변수 격리**: `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT`
- **stdin 격리**: `< /dev/null` (부모 세션 stdin 상속 차단)
- **자동 정리**: EXIT trap + 5분 TTL 고아 워커 정리

## 커스텀 모델 설정

플러그인 설치 후 `models.env`를 수정하여 기본 모델을 변경할 수 있습니다:

```bash
CODEX_MODEL="gpt-5.3-codex"
GEMINI_MODEL="gemini-3-pro-preview"
```

## 라이선스

MIT
