# Aerial Architecture Notes

## What Aerial Uses

Aerial is a native macOS screen saver bundle. Its principal class is a Swift
`ScreenSaverView` subclass named in `Info.plist` with `NSPrincipalClass`.

The core layers are:

- Screen saver entry: `AerialView` subclasses `ScreenSaverView`, owns lifecycle,
  preview handling, player setup, configure sheet, display matching, and teardown.
- Rendering: `AVPlayer` plus `AVPlayerLayer` provide video playback. Additional
  `CALayer` and `CATextLayer` overlays render clock, weather, location, and
  metadata.
- Models and services: video catalog, cache, downloads, preferences, display
  detection, battery, brightness, weather, location, and media helpers.
- Preferences UI: an AppKit configure sheet is returned from
  `ScreenSaverView.configureSheet`.
- Debug companion app: Aerial also has an app target so the saver view can be
  exercised outside the macOS Screen Saver host.

## ScreenStocker Plan

ScreenStocker keeps the same architectural spine, but starts much smaller:

- `ScreenStockerView`: the `ScreenSaverView` principal class and lifecycle owner.
- `StockTickerRenderer`: Core Animation rendering for text-based stock tiles.
- `StockQuoteProvider`: protocol boundary for demo, polling, cache, and future
  network providers.
- `StockerPreferences`: `ScreenSaverDefaults` wrapper for user settings.
- `ConfigurationWindowController`: AppKit settings sheet.

The first production step after this scaffold is replacing
`DemoStockQuoteProvider` with a real quote provider, then adding a timed refresh
loop and offline fallback cache.

