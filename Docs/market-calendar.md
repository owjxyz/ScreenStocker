# Market calendar integration

ScreenStocker uses Toss's `/api/v1/market-calendar/KR` and `/api/v1/market-calendar/US` endpoints for chart sessions. The official contract is available at https://developers.tossinvest.com/docs/market-info and https://openapi.tossinvest.com/openapi-docs/latest/openapi.json.

## Fetch and cache

The existing market-data client reuses its OAuth token, URLSession, and ISO 8601 decoder. The KR query date uses Seoul time; the US query date uses New York time. Both endpoints return timestamps with offsets, which are decoded directly into absolute dates.

Calendars are requested when a chart is loaded, then shared across symbols. A cached response is revalidated after one hour or when the query date changes. Concurrent requests for the same market/date are coalesced. Failures back off for five minutes; successful schedules remain available. The calendar uses separate keys in the existing shared market-data cache, including its app/saver host mirroring. Retention is bounded to dates within 14 days of the query day.

## Session selection and rendering

The previous, requested, and next business days are searched together. The latest started chart session determines the display, including a US day market that starts before New York midnight. Chart cache writes and the `Data` label use the API business date. Existing candle caches can still be read by their timestamps.

Korean charts use the combined KRX/NXT schedule. This is not a statement that an individual stock trades in every session. US charts retain separate day-market and pre/regular/after-market presentations. Null sessions are closed; a missing or failed calendar request is unknown. With no usable calendar, prices continue refreshing and existing candle data remains visible without invented market hours. If there are no cached candles, the chart stays empty until a calendar and candles are available.

Session gaps and auction intervals are excluded from continuous-candle gap checks. During a break, freshness is measured against the preceding session's end. After close, it is measured against the actual calendar end. One-minute refresh and ten-minute candle aggregation are unchanged. A last partial ten-minute candle is capped at the reported session end.

The app preview and installed saver share the provider, chart model, and renderer. No calendar networking or persistence is performed by views.

## Verification

`StockMarketCalendarTests` covers date boundaries, response offsets, closures, partial closures, early close, validation, persistence, coalescing, expiration, and failure backoff. `TossInvestMarketDataClientCacheTests` exercises the HTTP integration, cross-symbol sharing, business-date labels, cache recovery, and prior-session fallback.

```sh
xcodegen generate
xcodebuild -project ScreenStocker.xcodeproj -scheme ScreenStockerTests \
  -destination 'platform=macOS' -derivedDataPath build/DerivedData test
./Scripts/build.sh --refresh
```

On the development machine, two unrelated tests also fail on the unchanged baseline: `StockQuoteTests/testPreferencesFallBackToDefaultSymbols` reads existing host preferences, and `StockChartSeriesCacheStoreTests/testLoadedEntriesRemainAvailableFromMemoryCache` uses historical dates pruned at initialization. Excluding those two tests, all 52 tests passed on 2026-09-18. The app and saver built and installed successfully.
