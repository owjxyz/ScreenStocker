<div align="center">
  <a href="https://github.com/owjxyz/ScreenStocker/">
    <img src="https://github.com/owjxyz/ScreenStocker/blob/main/Docs/screenstocker-dynamic-glass.svg" width="256">
  </a>
  
  # 📈 ScreenStocker
</div>

ScreenStocker is a lightweight macOS screen saver that shows the current price status and chart for stocks you care about.

Use the companion app to manage your watchlist and display settings.

[한국어 README 보기](README.ko.md)

## Key Features

- Display line charts or candlestick charts
- Show the current price, percentage change, and last update time
- Choose Light, Dark, or Auto display modes
- Integrate with the Toss Invest Open API
- Store your API Key and Secret Key in macOS Keychain

## Requirements

- macOS 13 Ventura or later
- [Toss Invest Open API](https://corp.tossinvest.com/ko/open-api) credentials
- Internet connection

## Installation

XcodeGen is required if you want to build directly from source.

```sh
brew install xcodegen
./Scripts/build.sh --refresh
```

## 🖥️ Applying the Screen Saver

1. Open macOS `System Settings`
2. Go to `Screen Saver`
3. Select `ScreenStocker` from the list
4. If needed, click `Options...` or `Settings...` to open the ScreenStocker app

## ⚙️ Initial Setup

`API`: Enter your Toss Invest Open API `API Key` and `Secret Key`, then click `Save Credentials`.

`Watchlist`: Click `Add Symbol` to add stocks to your watchlist, then choose the symbol to display.

`Screen Saver`: Choose the display mode and chart style, then click `Install Saver` to apply the settings.

## 📋 Adding Symbols

On the `Watchlist` screen, click `Add Symbol` and enter a stock symbol.

- Korean stocks: 6-digit KRX code, for example `005930`
- U.S. stocks: ticker symbol, for example `AAPL`

Symbols are normalized to uppercase before they are saved. Symbols that already exist in the watchlist will not be added again.

## ✅ Choosing the Displayed Symbol

The symbol shown in the screen saver is selected in `ScreenStocker.app`.

1. Go to the `Watchlist` or `Screen Saver` screen.
2. Select the symbol you want to display.
3. Click `Apply` or `Install Saver` to apply it to the screen saver.

You do not choose symbols directly from the screen saver settings sheet. Clicking `Options...` or `Settings...` in macOS Screen Saver settings opens the ScreenStocker app.

## 📺 Display Options

You can change these options in `ScreenStocker.app > Screen Saver`.

- `Display`: Symbol to show in the screen saver
- `Light`, `Dark`, `Auto`: Screen saver background mode
- `Chart Style`: Line chart or candlestick chart
- `Install Saver`: Apply the current settings to the screen saver

## 🔑 API Key Management

You can save or remove Toss Invest Open API credentials on the `API` screen.

- Saved keys are stored in macOS Keychain.
- Click `Remove` to delete stored keys.
- If credentials are missing or invalid, ScreenStocker may not be able to load real-time quote data.
