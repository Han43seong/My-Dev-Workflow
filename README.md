# Multi-Model Orchestrator

Claude Code 플러그인 — opus, codex, gemini 3개 모델을 CLI subprocess로 병렬/순차/합의 패턴으로 조율합니다.

## 필수 조건

다음 CLI 도구가 설치되어 있어야 합니다:

| CLI | 설치 |
|-----|------|
| `claude` | `npm install -g @anthropic-ai/claude-code` |
| `codex` | `npm install -g @openai/codex` |
| `gemini` | `npm install -g @google/gemini-cli` |

## 설치

```bash
claude plugin add <github-user>/<repo-name>
```

## 슬래시 커맨드

| 커맨드 | 설명 |
|--------|------|
| `/delegate <모델> <태스크>` | 특정 모델에 1:1 위임 |
| `/parallel <태스크>` | 3개 모델 동시 실행 + 비교 합성 |
| `/sequential <A> <B> <태스크>` | A 실행 → B 검증 |
| `/adversarial <제안자> <반박자> <주제>` | 제안 → 반박 논쟁 |
| `/consensus <질문>` | 3개 모델 다수결 투표 (2/3 합의) |
| `/orchestrate <복합 태스크>` | 자동 분해 → 라우팅 → 실행 → 통합 |

## 모델 라우팅

| 의도 | 모델 |
|------|------|
| 코드 리뷰, 복잡한 판단 | opus |
| 백엔드, 보안, 디버깅 | codex |
| UI, 리서치, 대용량 | gemini |

## 커스텀 모델 설정

`models.env`를 수정하여 기본 모델을 변경할 수 있습니다:

```bash
CODEX_MODEL="gpt-5.3-codex"
GEMINI_MODEL="gemini-3-pro-preview"
```

## 아키텍처

```
Claude Code (Opus) = 오케스트레이터
    ├─ /delegate → invoke-model.sh → invoke-{claude,codex,gemini}.sh
    ├─ /parallel → invoke-parallel.sh → 3개 동시 실행
    ├─ /sequential → invoke-sequential.sh → A→B 순차
    ├─ /adversarial → invoke-adversarial.sh → 제안→반박
    ├─ /consensus → invoke-parallel.sh → 합의 판정
    └─ /orchestrate → 분해 → 라우팅 → 혼합 실행
```

## 라이선스

MIT
