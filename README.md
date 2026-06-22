# 📈 ScreenStocker

macOS 화면 보호기에서 관심 있는 주식의 현재 가격 상태와 차트를 보여주는 가벼운 화면 보호기입니다. 앱을 통해 관심 종목 리스트와 표시 방식을 관리합니다.

## 주요 기능

- 라인 차트 or 캔들스틱 차트 표시
- 현재가, 등락률, 업데이트 시각 표시
- Light, Dark, Auto 표시 모드 선택
- Toss Invest Open API 연동
- API Key와 Secret Key를 macOS Keychain에 저장

## 요구 사항

- macOS 13 Ventura 이상
- [Toss Invest Open API](https://corp.tossinvest.com/ko/open-api) 자격 증명
- 인터넷 연결

## 설치

소스 코드를 통해 직접 빌드하려면 XcodeGen이 필요합니다.

```sh
brew install xcodegen
./Scripts/build.sh --refresh
```

## 🖥️ 화면 보호기 적용

1. macOS `시스템 설정` 열기
2. `화면 보호기`로 이동
3. 목록에서 `ScreenStocker` 선택
4. 필요시, `Options...` 또는 `설정...`을 눌러 ScreenStocker 앱 열기

## ⚙️ 초기 설정

`API` : Toss Invest Open API의 `API Key`와 `Secret Key`를 입력 - `Save Credentials` 눌러 저장

`Watchlist` : `Add Symbol`을 눌러 관심 종목을 추가 - 표시할 종목 선택

`Screen Saver` : 표시 모드와 차트 스타일을 선택 - `Install Saver` 눌러 반영

## 📋 종목 추가하기

`Watchlist` 화면에서 `Add Symbol`을 누른 뒤 종목 코드를 입력합니다.

- 한국 주식: 6자리 KRX 코드, 예: `005930`
- 미국 주식: 티커, 예: `AAPL`

입력한 종목은 대문자로 정리되어 저장됩니다. 이미 추가된 종목은 중복으로 등록되지 않습니다.

## ✅ 표시할 종목 선택하기

화면 보호기에 표시되는 종목은 `ScreenStocker.app`에서 선택합니다.

1. `Watchlist` 또는 `Screen Saver` 화면으로 이동합니다.
2. 원하는 종목을 선택합니다.
3. `Apply` 또는 `Install Saver`를 눌러 화면 보호기에 적용합니다.

화면 보호기 설정 창에서는 종목을 직접 고르지 않습니다. macOS 화면 보호기 설정의 `Options...` 또는 `설정...` 버튼을 누르면 ScreenStocker 앱을 열 수 있습니다.

## 📺 화면 표시 옵션

`ScreenStocker.app > Screen Saver`에서 다음 옵션을 바꿀 수 있습니다.

- `Display`: 화면 보호기에 표시할 종목
- `Light`, `Dark`, `Auto`: 화면 보호기 배경 모드
- `Chart Style`: 라인 차트 또는 캔들스틱 차트
- `Install Saver`: 현재 설정을 화면 보호기에 적용

## 🔑 API 키 관리

`API` 화면에서 Toss Invest Open API 자격 증명을 저장하거나 삭제할 수 있습니다.

- 저장된 키는 macOS Keychain에 보관됩니다.
- 키를 삭제하려면 `Remove`를 누릅니다.
- 자격 증명이 없거나 잘못된 경우 실시간 시세를 불러오지 못할 수 있습니다.
