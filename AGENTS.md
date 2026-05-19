# ScreenStocker Agent Guide

## Critical Language Rule

- Always conduct reasoning, analysis, code investigation, implementation planning, and tool-oriented work in English.
- The final user-facing briefing at the end of a task must be written in Korean.
- Treat this as a high-priority collaboration rule for this repository. Intermediate notes, code comments, commit messages, and documentation may remain English unless the user explicitly requests Korean.

## Project Goal

The goal of this project is to build a lightweight, maintainable stock-status screen saver by using Apple SwiftUI and native macOS frameworks as much as possible. When adding new features, first check whether the requirement can be handled with Apple-provided libraries such as SwiftUI, AppKit, ScreenSaver, Foundation, Combine/Observation, URLSession, UserDefaults/App Groups, and Security Keychain before adding external dependencies.

## Product Direction

- ScreenStocker displays stock price status and charts for selected symbols inside a macOS screen saver.
- The screen saver refreshes stock quotes and chart data every 5 minutes.
- The symbol shown in the screen saver is selected from the screen saver configuration options.
- The selectable symbol list is based on a watchlist prepared in a separate management app.
- The management app owns preparation tasks such as adding and removing watchlist items, searching symbols, and storing API credentials.
- The screen saver configuration should focus on choosing one symbol from the existing watchlist.

## Implementation Principles

- Prefer SwiftUI. Screens, configuration UI, state presentation, lists, and chart-adjacent layout should use native SwiftUI components whenever practical.
- Keep AppKit or ScreenSaver.framework entry points as thin adapters where they are required, and separate actual UI and state logic into SwiftUI views and independent models.
- Do not add external packages when Apple native frameworks are sufficient.
- Keep rendering simple and predictable. This is a financial data screen that refreshes every 5 minutes, so avoid expensive animations, complex real-time render loops, and unnecessary background work.
- Separate responsibilities for networking, persistence, screen rendering, and configuration UI.
- The screen saver may run for long periods, so be especially careful about memory growth, duplicated timers, and leaked network requests.

## Preferred Apple APIs

- UI: SwiftUI
- Screen saver hosting: ScreenSaver.framework with a minimal AppKit bridge
- Charts: Swift Charts where available, or lightweight SwiftUI `Path` drawing when a custom saver-safe graph is simpler
- Networking: `URLSession`
- Scheduling: Swift concurrency `Task`, `Clock`, or a carefully owned `Timer`
- Persistence: `UserDefaults` with a shared suite when the app and saver need shared preferences
- Secrets: Keychain via Security.framework
- Formatting: Foundation `NumberFormatter`, `DateFormatter`, and `FormatStyle`

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
- Use system colors, system fonts, and adaptive layout so the saver works in light/dark mode and across displays.
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
