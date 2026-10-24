# DIY LLM Subscription Management Hub Toolkit (`diy-llm-subscription-management-hub-toolkit`)

Universal DIY LLM subscription & session management hub — proxy router, quota tracker, and menu bar dashboard.

여러 AI/LLM 구독 계정(OpenAI ChatGPT/Codex, Anthropic Claude Pro/Team, xAI Grok, Cursor, Gemini 등)의 세션과 라우팅을 중앙 허브에서 안정적으로 관리하고, macOS 메뉴바를 통해 실시간 잔여 쿼터와 사용량을 직관적으로 모니터링할 수 있는 모노레포 툴킷입니다.

---

## 🏛 모노레포 구성 (Architecture)

```text
diy-llm-subscription-management-hub-toolkit/
├── apps/
│   └── codexbar/          # macOS 메뉴바 쿼터 & 사용량 모니터링 대시보드 (Swift / AppKit)
├── packages/
│   └── opencodex/         # 범용 LLM 프로바이더 프록시, 세션 관리 및 인증 라우팅 코어 (Bun / TypeScript)
├── LICENSE                # 루트 MIT 라이선스
└── README.md
```

### 1. `packages/opencodex` (중앙 프록시 및 세션 라우팅 허브)
* OpenAI Codex, Claude Code, Cursor 등 다양한 AI 코딩 도구의 요청을 하나의 로컬/원격 허브(`:10100`)로 집결
* 다중 프로바이더(Anthropic, OpenAI, xAI, Google 등)의 OAuth 구독 및 API 키 투명 라우팅
* 자동 페일오버, 사용량 추적 및 요청 큐잉
* macOS `launchd` 연동을 통한 무중단 상시 구동 및 자가 치유 Watchdog 제공

### 2. `apps/codexbar` (macOS 메뉴바 사용량 대시보드)
* 로그인 없이도 OpenAI Codex 및 Claude Code 잔여 쿼터/사용량 실시간 시각화
* 5시간 주기 리셋, 주간/월간 한도 및 소진 예측 페이스 알림
* 다중 프로바이더 상태 및 세션 헬스체크 메뉴 제공
* 계정마다 별도 사용량 미니 바 표시, 중지된 허브 등록 항목은 카드와 바에서 함께 제외
* 프로바이더 전환과 메뉴 캐시 재사용 시 실제 메뉴 폭에 맞춰 카드·탭 정렬
* Codex 설정의 **Provider URL**로 공개 리셋 소식 제공자 지정, 프로바이더당 한 번 표시

CodexBar 변경은 이 저장소의 `apps/codexbar`에서 관리합니다. 자세한 동작은
[계정별 바](apps/codexbar/docs/provider-switcher-accounts.md)와
[공개 리셋 소식](apps/codexbar/docs/reset-announcements.md)을 참고하세요.

---

## 🚀 빠른 시작 (Quick Start)

### 1. OpenCodex Hub 실행
```bash
cd packages/opencodex

# Bun 런타임으로 프록시 시작
bun run src/cli/index.ts start --port 10100

# 또는 백그라운드 서비스로 등록/복구
bun run src/cli/index.ts service repair
```

### 2. CodexBar 빌드 및 실행
```bash
cd apps/codexbar

# Swift Package Manager를 통한 빌드 및 테스트
swift build -c release
# 메모리 설정·합성 홈·Keychain 접근 억제를 적용하는 저장소 테스트 실행기
make test
make check
```

---

## 🛡️ 고가용성 & 자가 치유 (Self-Healing)

본 툴킷은 macOS 환경에서 Mac 잠자기/깨어남, 백그라운드 재부팅, 일시적 타임아웃 상황에서도 세션이 끊기지 않도록 **이중 방어 체계**를 지원합니다:

1. **`KeepAlive: true` 무조건 재기동**: 프로세스가 어떤 상태(정상 종료 코드 0 포함)로 내려가더라도 `launchd`가 즉각 프로세스를 재기동합니다.
2. **1분 주기 Watchdog 데몬**: 로컬 헬스체크 엔드포인트를 주기적으로 찔러 응답 지연이나 먹통(Hang) 발생 시 자동으로 서비스를 복구합니다.

---

## 📄 라이선스 (License)

본 모노레포의 모든 코드는 **[MIT License](LICENSE)** 하에 배포됩니다.

- `packages/opencodex`: MIT License (Copyright (c) 2026 opencodex contributors)
- `apps/codexbar`: MIT License (Copyright (c) 2026 Peter Steinberger, CodexBar contributors)
