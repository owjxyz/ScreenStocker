# ScreenStocker

macOS용 서드파티 화면보호기 실험 프로젝트입니다. Aerial의 구조를 참고하되, 첫 버전은 주식 시세를 Core Animation 텍스트 레이어로 표시하는 작은 `.saver` 번들로 시작합니다.

## 기본 구조

- `ScreenStocker/Sources/ScreenSaver`: macOS ScreenSaver 진입점
- `ScreenStocker/Sources/Rendering`: 화면 렌더링 계층
- `ScreenStocker/Sources/Stocks`: 주식 시세 모델과 공급자 계층
- `ScreenStocker/Sources/Preferences`: 설정 저장과 configure sheet
- `ScreenStocker/Resources`: `.saver` 번들용 `Info.plist`
- `Docs`: Aerial 분석과 개발 계획
- `project.yml`: XcodeGen 기반 Xcode 프로젝트 선언

## 빌드 시작

```sh
brew install xcodegen
./Scripts/build.sh
```

생성된 빌드 산출물은 Xcode에서 `ScreenStocker` 타깃을 빌드해 확인하고, 최종적으로 `ScreenStocker.saver`를 `~/Library/Screen Savers`에 설치하는 흐름으로 확장합니다.
