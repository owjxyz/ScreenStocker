# ScreenStocker

macOS용 서드파티 화면보호기 프로젝트입니다. 관리 앱에서 관심 종목을 고르고, 화면보호기에서 선택한 종목의 가격 상태와 차트를 표시합니다.

## 기본 구조

- `ScreenStocker/Sources/ScreenSaver`: macOS ScreenSaver 진입점
- `ScreenStocker/Sources/Rendering`: 화면 렌더링 계층
- `ScreenStocker/Sources/Stocks`: 주식 시세 모델과 시장 데이터
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

관리 앱에서 관심 종목과 화면보호기 표시 옵션을 관리합니다.

```sh
open "$HOME/Applications/ScreenStocker.app"
```

화면보호기 설정 창에서는 관리 앱을 바로 열 수 있습니다. 표시할 종목 선택과 관심 종목 관리는 `ScreenStocker.app`에서 수행하며, 화면보호기는 앱에서 선택한 한 종목의 현재가와 라인 차트를 화면 전체에 표시합니다.

설치 후 macOS 설정에서 바로 확인할 수 있습니다.

```sh
open "x-apple.systempreferences:com.apple.ScreenSaver-Settings.extension"
```
