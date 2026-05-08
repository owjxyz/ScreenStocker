# ScreenStocker Agent Guide

이 프로젝트의 목표는 Apple SwiftUI와 macOS 기본 프레임워크를 최대한 활용해 가볍고 유지보수하기 쉬운 주식 현황 화면보호기를 구현하는 것이다. 새 기능을 만들 때는 외부 의존성을 추가하기 전에 SwiftUI, AppKit, ScreenSaver, Foundation, Combine/Observation, URLSession, UserDefaults/App Groups, Security Keychain 등 Apple이 제공하는 기본 라이브러리로 해결할 수 있는지 먼저 검토한다.

## Product Direction

- ScreenStocker는 macOS 화면보호기에서 선택한 종목의 주식 가격 현황과 그래프를 보여준다.
- 화면보호기는 5분에 한 번씩 주식 가격과 차트 데이터를 요청해 화면을 갱신한다.
- 화면보호기에 표시할 종목은 화면보호기 설정 옵션에서 선택한다.
- 선택 가능한 종목 목록은 별도 관리 앱에서 미리 설정한 watchlist를 기반으로 한다.
- 관리 앱은 watchlist 추가, 삭제, 종목 검색, API 인증 정보 저장 같은 준비 작업을 담당한다.
- 화면보호기 설정은 사용자가 watchlist 중 하나의 종목을 고르는 데 집중한다.

## Implementation Principles

- SwiftUI를 우선 사용한다. 화면, 설정 UI, 상태 표현, 리스트, 차트 주변 레이아웃은 가능한 한 SwiftUI 기본 컴포넌트로 구현한다.
- 화면보호기 진입점처럼 AppKit 또는 ScreenSaver.framework가 필요한 부분은 얇은 어댑터로 유지하고, 실제 UI와 상태 로직은 SwiftUI 뷰와 독립 모델로 분리한다.
- Apple 기본 프레임워크로 충분한 경우 외부 패키지를 추가하지 않는다.
- 렌더링은 단순하고 예측 가능하게 유지한다. 5분마다 갱신되는 금융 데이터 화면이므로 고비용 애니메이션, 복잡한 실시간 렌더 루프, 불필요한 백그라운드 작업을 피한다.
- 네트워크, 저장소, 화면 렌더링, 설정 UI 책임을 분리한다.
- 화면보호기는 장시간 실행될 수 있으므로 메모리 증가, 타이머 중복, 네트워크 요청 누수를 특히 경계한다.

## Preferred Apple APIs

- UI: SwiftUI
- Screen saver hosting: ScreenSaver.framework with a minimal AppKit bridge
- Charts: Swift Charts where available, or lightweight SwiftUI `Path` drawing when a custom saver-safe graph is simpler
- Networking: `URLSession`
- Scheduling: Swift concurrency `Task`, `Clock`, or a carefully owned `Timer`
- Persistence: `UserDefaults` with a shared suite when the app and saver need shared preferences
- Secrets: Keychain via Security.framework
- Formatting: Foundation `NumberFormatter`, `DateFormatter`, `FormatStyle`

## Data Refresh Rules

- The stock quote and graph data refresh interval is 5 minutes.
- Refresh immediately when the screen saver starts if a selected symbol is available.
- Avoid overlapping requests. If a previous refresh is still running, do not start another request for the same symbol.
- Cancel refresh work when the screen saver stops animating or is deallocated.
- Cache the last successful quote and chart data so the UI can continue showing useful information during transient network failures.
- If credentials are missing or the provider fails, use an explicit fallback state or demo data only where the current product behavior expects it.

## Watchlist And Selection

- The management app owns watchlist editing.
- The screen saver configuration UI reads the saved watchlist and lets the user choose from it.
- The screen saver should not require free-form ticker input in its configuration UI.
- If the watchlist is empty, show a clear empty state and guide the user to configure the list in the management app.
- Store the selected symbol separately from the watchlist so deleting a symbol can be handled gracefully.
- If the selected symbol no longer exists in the watchlist, fall back to the first available watchlist item or an empty state.

## Architecture Guidelines

- Keep shared domain models under `ScreenStocker/Sources/Stocks`.
- Keep shared preferences and app/saver settings under `ScreenStocker/Sources/Preferences`.
- Keep screen saver hosting code under `ScreenStocker/Sources/ScreenSaver`.
- Keep visual rendering components under `ScreenStocker/Sources/Rendering`.
- Keep the watchlist management app under `ScreenStockerApp/Sources`.
- Prefer small, testable services such as quote providers, time-series providers, watchlist stores, and selection stores.
- Avoid putting networking directly inside SwiftUI views.
- Avoid putting persistence directly inside rendering code.

## SwiftUI Style

- Use simple native controls: `List`, `Picker`, `Form`, `Toggle`, `Button`, `ProgressView`, and `Chart` or `Path` where appropriate.
- Keep view state minimal and derived from model state where possible.
- Prefer clear empty, loading, success, and error states over hidden implicit behavior.
- Use system colors, system fonts, and adaptive layout so the saver works in light/dark and across displays.
- Avoid ornamental UI that increases rendering cost without improving glanceability.

## Error Handling

- Network failures should not blank the screen if previous data exists.
- Missing credentials, empty watchlist, invalid selected symbol, and provider errors should be distinct states.
- Log useful diagnostics during development, but avoid noisy repeated logs during the 5-minute refresh loop.
- Never expose API secrets in logs, UI, crash messages, or test fixtures.

## Testing And Verification

- Add focused unit tests for parsing, provider response mapping, watchlist persistence, selected-symbol fallback, and refresh scheduling rules.
- For UI changes, verify the management app and screen saver configuration still read/write the same shared settings.
- Before finishing implementation work, run the project build script when practical:

```sh
./Scripts/build.sh
```

- If changing screen saver lifecycle or timer behavior, manually verify that refresh starts, repeats every 5 minutes, and stops cleanly when the saver is closed.

## Non-Goals

- Do not introduce a heavy cross-platform UI framework.
- Do not add a database unless watchlist and settings requirements outgrow simple shared preferences.
- Do not build a high-frequency trading dashboard. The intended cadence is a calm screen saver that updates every 5 minutes.
- Do not make the screen saver configuration responsible for full watchlist management unless the product direction changes.
