# ScreenStocker

macOS용 서드파티 화면보호기 실험 프로젝트입니다. Aerial의 구조를 참고하되, 첫 버전은 주식 시세를 Core Animation 텍스트 레이어로 표시하는 작은 `.saver` 번들로 시작합니다.

## 기본 구조

- `ScreenStocker/Sources/ScreenSaver`: macOS ScreenSaver 진입점
- `ScreenStocker/Sources/Rendering`: 화면 렌더링 계층
- `ScreenStocker/Sources/Stocks`: 주식 시세 모델과 공급자 계층
- `ScreenStocker/Sources/Preferences`: 설정 저장과 configure sheet
- `ScreenStocker/Resources`: `.saver` 번들용 `Info.plist`
- `ScreenStockerApp`: 관심 종목 목록을 관리하는 macOS 앱
- `Docs`: Aerial 분석과 개발 계획
- `project.yml`: XcodeGen 기반 Xcode 프로젝트 선언

## 빌드 시작

```sh
brew install xcodegen
./Scripts/build.sh
```

`./Scripts/build.sh`는 `ScreenStocker.xcodeproj`를 생성하고, Debug 빌드를 수행한 뒤 `ScreenStocker.saver`를 `~/Library/Screen Savers`에 자동 설치합니다. 같은 빌드에서 관심 종목 관리 앱인 `ScreenStocker.app`도 생성하고 `~/Applications`에 설치합니다.

화면보호기 설정 화면이 기존 번들을 계속 들고 있어 변경사항이 바로 보이지 않으면 `--refresh` 옵션으로 System Settings와 화면보호기 미리보기 프로세스를 종료한 뒤 다시 열 수 있습니다.

```sh
./Scripts/build.sh --refresh
```

관심 종목 목록은 관리 앱에서 추가/삭제합니다.

```sh
open "$HOME/Applications/ScreenStocker.app"
```

관리 앱에서 한국투자증권 Open API App Key와 App Secret을 저장하면 화면보호기가 KIS Developers REST API로 국내 주식 현재가를 조회합니다. 관심 종목 입력창에는 `005930` 같은 6자리 종목코드를 넣고 `Search`를 눌러 종목명을 확인한 뒤 추가할 수 있습니다. 인증 정보가 비어 있거나 네트워크 응답이 실패하면 개발용 데모 시세로 표시됩니다.

화면보호기 설정 창에서는 문자열을 직접 입력하지 않고, 관리 앱에 등록된 첫 종목 또는 개별 종목을 드롭다운 메뉴에서 선택합니다. 화면보호기는 한 번에 한 종목의 현재가와 한국투자증권 국내주식 기간별 시세 기반 라인 차트를 화면 전체에 표시합니다.

설치 후 macOS 설정에서 바로 확인할 수 있습니다.

```sh
open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"
```
