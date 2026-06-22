# ScreenStocker

ScreenStocker는 macOS 화면 보호기에서 선택한 주식의 현재 가격 상태와 차트를 보여주는 가벼운 화면 보호기입니다. 별도의 ScreenStocker 앱에서 관심 종목과 표시 옵션을 관리하고, 화면 보호기는 앱에서 선택한 한 종목을 전체 화면으로 표시합니다.

## 주요 기능

- 관심 종목 목록 관리
- 화면 보호기에 표시할 종목 선택
- 현재가, 등락률, 거래소 정보, 업데이트 시각 표시
- 라인 차트 또는 캔들스틱 차트 표시
- Light, Dark, Auto 표시 모드 선택
- Toss Invest Open API 연동
- API 키와 Secret Key를 macOS Keychain에 저장

## 요구 사항

- macOS 13 Ventura 이상
- Toss Invest Open API 자격 증명
- 인터넷 연결

## 설치하기

배포 파일을 받은 경우 다음 두 파일을 설치합니다.

1. `ScreenStocker.app`을 `Applications` 또는 `~/Applications` 폴더로 옮깁니다.
2. `ScreenStocker.saver`를 열어 macOS 화면 보호기로 설치합니다.
3. macOS가 확인되지 않은 개발자 경고를 표시하면 `시스템 설정 > 개인정보 보호 및 보안`에서 실행을 허용합니다.
4. `ScreenStocker.app`을 한 번 실행해 화면 보호기 설정을 준비합니다.

소스 코드에서 직접 설치하려면 XcodeGen이 필요합니다.

```sh
brew install xcodegen
./Scripts/build.sh --refresh
```

이 명령은 `ScreenStocker.app`을 `~/Applications`에 설치하고, `ScreenStocker.saver`를 `~/Library/Screen Savers`에 설치합니다.

## 처음 설정하기

1. `ScreenStocker.app`을 엽니다.
2. 왼쪽 사이드바에서 `API`를 선택합니다.
3. Toss Invest Open API의 `API Key`와 `Secret Key`를 입력합니다.
4. `Save Credentials`를 누릅니다.
5. 왼쪽 사이드바에서 `Watchlist`를 선택합니다.
6. `Add Symbol`을 눌러 관심 종목을 추가합니다.
7. 표시할 종목을 선택합니다.
8. 왼쪽 사이드바에서 `Screen Saver`를 선택합니다.
9. 표시 모드와 차트 스타일을 고른 뒤 `Install Saver`를 누릅니다.

## 종목 추가하기

`Watchlist` 화면에서 `Add Symbol`을 누른 뒤 종목 코드를 입력합니다.

- 한국 주식: 6자리 KRX 코드, 예: `005930`
- 미국 주식: 티커, 예: `AAPL`

입력한 종목은 대문자로 정리되어 저장됩니다. 이미 추가된 종목은 중복으로 등록되지 않습니다.

## 표시할 종목 선택하기

화면 보호기에 표시되는 종목은 `ScreenStocker.app`에서 선택합니다.

1. `Watchlist` 또는 `Screen Saver` 화면으로 이동합니다.
2. 원하는 종목을 선택합니다.
3. `Apply` 또는 `Install Saver`를 눌러 화면 보호기에 적용합니다.

화면 보호기 설정 창에서는 종목을 직접 고르지 않습니다. macOS 화면 보호기 설정의 `Options...` 또는 `설정...` 버튼을 누르면 ScreenStocker 앱을 열 수 있습니다.

## 화면 보호기 켜기

1. macOS `시스템 설정`을 엽니다.
2. `화면 보호기`로 이동합니다.
3. 목록에서 `ScreenStocker`를 선택합니다.
4. 필요하면 `Options...` 또는 `설정...`을 눌러 ScreenStocker 앱을 엽니다.

## 화면 표시 옵션

`ScreenStocker.app > Screen Saver`에서 다음 옵션을 바꿀 수 있습니다.

- `Display`: 화면 보호기에 표시할 종목
- `Light`, `Dark`, `Auto`: 화면 배경과 글자색 모드
- `Chart Style`: 라인 차트 또는 캔들스틱 차트
- `Install Saver`: 현재 설정을 화면 보호기에 다시 적용

## API 키 관리

`API` 화면에서 Toss Invest Open API 자격 증명을 저장하거나 삭제할 수 있습니다.

- 저장된 키는 macOS Keychain에 보관됩니다.
- 키를 삭제하려면 `Remove`를 누릅니다.
- 자격 증명이 없거나 잘못된 경우 실시간 시세를 불러오지 못할 수 있습니다.

## 업데이트하기

새 버전을 설치할 때는 기존 앱과 화면 보호기를 새 파일로 교체한 뒤 `ScreenStocker.app`에서 `Install Saver`를 다시 누르세요. 화면 보호기 미리보기가 예전 화면을 계속 보여주면 macOS 시스템 설정을 닫았다가 다시 열면 됩니다.

소스 코드에서 업데이트하는 경우 다음 명령을 사용합니다.

```sh
./Scripts/build.sh --refresh
```

## 삭제하기

ScreenStocker를 제거하려면 다음 파일을 삭제합니다.

- `~/Applications/ScreenStocker.app`
- `~/Library/Screen Savers/ScreenStocker.saver`

저장된 API 키까지 지우려면 앱을 삭제하기 전에 `ScreenStocker.app > API > Remove`를 먼저 누르세요.

## 문제 해결

### ScreenStocker가 화면 보호기 목록에 보이지 않아요

`ScreenStocker.saver`가 `~/Library/Screen Savers`에 설치되어 있는지 확인한 뒤 시스템 설정을 다시 여세요.

### 시세가 표시되지 않아요

`ScreenStocker.app > API`에서 API 키가 저장되어 있는지 확인하세요. 그다음 `Watchlist`에서 종목을 선택하고 `Refresh`를 눌러 보세요.

### 원하는 종목을 추가할 수 없어요

한국 주식은 6자리 KRX 코드, 미국 주식은 티커 형식으로 입력해야 합니다. 예를 들어 삼성전자는 `005930`, Apple은 `AAPL`입니다.

### 화면 보호기가 예전 설정을 보여줘요

`ScreenStocker.app > Screen Saver`에서 `Install Saver`를 다시 누른 뒤 macOS 시스템 설정을 닫았다가 다시 여세요.
