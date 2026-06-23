# ScreenStocker Agent Guide

## Critical Language Rule

- Always conduct reasoning, analysis, code investigation, implementation planning, and tool-oriented work in English.
- The final user-facing briefing at the end of a task must be written in Korean.
- Treat this as a high-priority collaboration rule for this repository. Intermediate notes, code comments, commit messages, and documentation may remain English unless the user explicitly requests Korean.

## Project Goal

The goal of this project is to build a lightweight, maintainable stock-status screen saver by using Apple SwiftUI and native macOS frameworks as much as possible. When adding new features, first check whether the requirement can be handled with Apple-provided libraries such as SwiftUI, AppKit, ScreenSaver, Foundation, Combine/Observation, URLSession, UserDefaults/App Groups, and Security Keychain before adding external dependencies.

## Product Direction

- ScreenStocker displays stock price status and market visualizations for selected symbols inside a macOS screen saver.
- The screen saver refreshes stock quotes and any visualization data every 1 minute.
- The symbol shown in the screen saver is selected in the management app, not in the screen saver configuration sheet.
- The selectable symbol list is based on a watchlist prepared in a separate management app.
- The management app owns preparation tasks such as adding and removing watchlist items, choosing the displayed symbol, searching symbols, and storing API credentials.
- The screen saver configuration should stay lightweight. It should not duplicate watchlist or symbol-selection controls; it should provide a clear path to open the management app when the user needs to change ScreenStocker settings.

## Implementation Principles

- Prefer SwiftUI. Screens, configuration UI, state presentation, lists, and visualization-adjacent layout should use native SwiftUI components whenever practical.
- Keep AppKit or ScreenSaver.framework entry points as thin adapters where they are required, and separate actual UI and state logic into SwiftUI views and independent models.
- Do not add external packages when Apple native frameworks are sufficient.
- Keep rendering simple and predictable. This is a financial data screen that refreshes every 1 minute, so avoid expensive animations, complex real-time render loops, and unnecessary background work.
- Separate responsibilities for networking, persistence, screen rendering, and configuration UI.
- The screen saver may run for long periods, so be especially careful about memory growth, duplicated timers, and leaked network requests.

## Preferred Apple APIs

- UI: SwiftUI
- Screen saver hosting: ScreenSaver.framework with a minimal AppKit bridge
- Market visualizations: Swift Charts where available, or lightweight SwiftUI `Path`/shape drawing when a custom saver-safe visualization is simpler
- Networking: `URLSession`
- Scheduling: Swift concurrency `Task`, `Clock`, or a carefully owned `Timer`
- Persistence: `UserDefaults` with a shared suite when the app and saver need shared preferences
- Secrets: Keychain via Security.framework
- Formatting: Foundation `NumberFormatter`, `DateFormatter`, and `FormatStyle`

## Data Refresh Rules

- The stock quote and market visualization data refresh interval is 1 minute.
- Refresh immediately when the screen saver starts if a selected symbol is available.
- Avoid overlapping requests. If a previous refresh is still running, do not start another request for the same symbol.
- Cancel refresh work when the screen saver stops animating or is deallocated.
- Cache the last successful quote and visualization data so the UI can continue showing useful information during transient network failures.
- If credentials are missing or the provider fails, use an explicit fallback state or demo data only where the current product behavior expects it.

## Watchlist And Selection

- The management app owns watchlist editing.
- The management app owns displayed-symbol selection.
- The screen saver configuration UI should not read and present the watchlist as a selection control.
- The screen saver configuration UI should not require free-form ticker input or expose a symbol picker.
- The screen saver configuration UI may provide an "Open ScreenStocker" action that launches the management app through `NSWorkspace`.
- If the watchlist is empty or the selected symbol is invalid, guide the user to configure the list in the management app rather than adding watchlist-management controls to the screen saver configuration sheet.
- Store the selected symbol separately from the watchlist so deleting a symbol can be handled gracefully.
- If the selected symbol no longer exists in the watchlist, fall back to the first available watchlist item or an empty state.

## Architecture Guidelines

- Keep shared domain models under `ScreenStocker/Sources/Stocks`.
- Keep shared preferences and app/saver settings under `ScreenStocker/Sources/Preferences`.
- Keep screen saver hosting code under `ScreenStocker/Sources/ScreenSaver`.
- Keep visual rendering components under `ScreenStocker/Sources/Rendering`.
- Keep chart and visualization style decisions separate from data-fetching and persistence code so additional presentation types can be added without changing provider behavior.
- Treat the management-app preview and the actual screen saver as one rendering contract. When changing screen saver data mapping, chart geometry, colors, timestamps, chart style handling, or fallback states, update the management-app preview in the same task so it reflects the installed saver behavior.
- Keep the watchlist management app under `ScreenStockerApp/Sources`.
- Prefer small, testable services such as quote providers, time-series providers, watchlist stores, and selection stores.
- Avoid putting networking directly inside SwiftUI views.
- Avoid putting persistence directly inside rendering code.

## SwiftUI Style

- Use simple native controls: `List`, `Picker`, `Form`, `Toggle`, `Button`, `ProgressView`, and `Chart`, `Path`, or purpose-built SwiftUI views where appropriate.
- Keep view state minimal and derived from model state where possible.
- Prefer clear empty, loading, success, and error states over hidden implicit behavior.
- Use system colors, system fonts, and adaptive layout so the saver works in light/dark mode and across displays.
- Avoid ornamental UI that increases rendering cost without improving glanceability.

## Error Handling

- Network failures should not blank the screen if previous data exists.
- Missing credentials, empty watchlist, invalid selected symbol, and provider errors should be distinct states.
- Log useful diagnostics during development, but avoid noisy repeated logs during the 1-minute refresh loop.
- Never expose API secrets in logs, UI, crash messages, or test fixtures.

## Testing And Verification

- Add focused unit tests for parsing, provider response mapping, watchlist persistence, selected-symbol fallback, and refresh scheduling rules.
- For UI changes, verify the management app owns selected-symbol writes and the screen saver configuration does not duplicate symbol selection.
- For any rendering or market-data change, verify both the management-app preview and the actual installed screen saver path. The preview should use the same quote, time-series, chart style, timestamp, empty/error, and fallback behavior as the screen saver unless there is an explicit product reason to diverge.
- When changing the screen saver configuration sheet, verify that the "Open ScreenStocker" action can launch the management app and that status messages do not shift, clip, or overlap the sheet controls.
- Before finishing implementation work, run the project build script when practical. When the task affects installed app behavior, screen saver rendering, configuration UI, preferences, or anything that must be observed through macOS System Settings or ScreenSaverEngine, use the refresh option so stale host processes reload the newly installed bundle:

```sh
./Scripts/build.sh --refresh
```

- Use plain `./Scripts/build.sh` only when a compile check is sufficient and no installed app or screen saver host needs to be refreshed.

- If changing screen saver lifecycle or timer behavior, manually verify that refresh starts, repeats every 1 minute, and stops cleanly when the saver is closed.

## Non-Goals

- Do not introduce a heavy cross-platform UI framework.
- Do not add a database unless watchlist and settings requirements outgrow simple shared preferences.
- Do not build a high-frequency trading dashboard. The intended cadence is a calm screen saver that updates every 1 minute.
- Do not make the screen saver configuration responsible for watchlist management or symbol selection unless the product direction changes.
