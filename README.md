# Sniq

<p align="center"><strong>Snap your windows into place</strong> · 창을 딱 맞게 배치</p>

<p align="center">
  <img src="Resources/sniq_icon.svg" width="128" alt="Sniq icon">
</p>

> 드래그로 원하는 위치에 창을 놓고, 그 위치를 **단축키로 저장해 재사용**하는 macOS 윈도우 스냅 유틸리티

macOS 기본 스냅은 화면 반반 정도만 지원합니다. Sniq 은 **두 개의 레이아웃을 미리 정의해두고 드래그 중 키 하나로 즉시 전환**하며 창을 배치하고, **드래그로 만든 배치를 단축키로 저장**해서 다음부터는 키만 눌러 같은 자리로 보냅니다.

## 특징

- **두 레이아웃 즉시 전환** — Primary / Secondary, 각각 독립 행·열 (1–10)
- **창 어디든 드래그** — 타이틀바/바디 구분 없음. 드래그 중 그리드 오버레이에서 커서 위치 셀이 파란 채움으로 강조됨
- **드래그 중 레이아웃 스왑** — Flip 키 토글로 Primary ↔ Secondary 실시간 전환
- **다중 셀 스냅** — Stretch 키로 여러 셀을 묶어 직사각형 영역에 스냅
- **Snaps (단축키로 저장된 창 배치)** — 드래그로 만든 배치에 단축키를 할당해서 다음부터는 키 하나로 창 이동. 1×n / n×1 그리드에선 같은 키 연타로 창이 한 칸씩 순환
- **`.sniq` 파일 Import / Export** — 사람이 읽을 수 있는 INI 포맷. 드래그앤드롭으로도 가져올 수 있음
- **기본 단축키 세트 내장** — 빈 Snaps 창에서 **Load default shortcuts** 클릭 한 번으로 14종 등록 (Rectangle / Magnet 기본 단축키와 동일한 스킴)
- **Modifier 재바인딩** — 기본값 (Grip=⌃ / Flip=⌥ / Stretch=⌘) 이 불편하면 Settings 에서 자유롭게 교체
- **메뉴바 앱** — Dock 아이콘 없음. 다크/라이트 메뉴바 자동 대응
- **로그인 시 자동 실행** 지원
- 외부 의존성 없음 (순수 Swift + AppKit + SwiftUI)

## 설치

### Homebrew (추천)

```bash
brew install --cask oh-research/tap/sniq
```

### 수동 설치

1. [Releases](https://github.com/oh-research/Sniq/releases) 에서 `.dmg` 다운로드
2. `Sniq.app` 을 `/Applications` 로 드래그
3. 앱 실행 → **How to Use...** 창이 사용법과 권한 설정을 안내합니다

## 사용법

아래 키 표기는 기본 바인딩 (Grip=⌃ / Flip=⌥ / Stretch=⌘) 기준입니다. Settings 에서 역할별로 바꿀 수 있습니다.

### 드래그로 스냅

1. 창 **어디든** 마우스를 누르면서 **Ctrl (Grip)** 를 함께 눌러 드래그
2. Primary 레이아웃 그리드 오버레이가 뜨고 커서 아래 셀이 하이라이트
3. 손을 떼면 창이 해당 셀 크기·위치로 스냅

### Secondary 레이아웃 (Flip)

드래그 중 **Opt (Flip)** 를 함께 누르거나, 처음부터 `Ctrl+Opt+drag` 로 시작하면 Secondary 레이아웃으로 전환됩니다. 드래그 중 Opt 를 눌렀다 뗐다 하면 Primary ↔ Secondary 가 실시간 전환됩니다 (다중 셀 선택 중에는 무시).

### 다중 셀 스냅 (Stretch)

Ctrl+drag 중 **Cmd (Stretch)** 를 추가로 누르면, 그 시점의 셀이 앵커가 되고 커서 이동에 따라 직사각형 영역이 하이라이트됩니다. 놓으면 직사각형 전체 크기로 스냅됩니다.

### Snaps — 단축키로 창 배치 저장

드래그로 만든 배치는 자동으로 **히스토리 (최근 10개)** 에 쌓입니다. 그 중 자주 쓰는 배치에 단축키를 부여해두면 다음부터는 키 한 번으로 포커스 창을 그 자리로 보냅니다. 처음이라면 빈 Saved 목록의 **Load default shortcuts** 버튼으로 Rectangle 호환 14종을 한 번에 등록할 수도 있습니다.

1. 메뉴바 아이콘 → **Snaps…**
2. **Recent** 섹션에서 원하는 배치 옆 `Assign shortcut…` 클릭 → 원하는 키 조합 누름
3. 그 배치가 **Saved** 섹션으로 이동하고, 이후 어디서든 그 단축키를 누르면 포커스 창이 해당 자리로 이동

1×n / n×1 (스트립) 그리드의 단축키는 **연타하면 창이 정박 방향으로 한 칸씩 순환**합니다 (끝에서 반대편으로 wrap).

Saved 항목은:

- 단축키 키캡을 클릭하면 **다른 단축키로 재할당** (Esc 로 취소)
- 왼쪽 **chevron** 을 펼치면 행·열 / from·to 좌표를 직접 편집
- 휴지통 아이콘으로 삭제

### `.sniq` 파일 공유

Snaps 창에서 **Export…** 로 현재 Saved 목록을 `.sniq` 파일로 저장하고, **Import…** 또는 **파일을 창에 드래그앤드롭** 해서 가져올 수 있습니다. Import 시 `Append` (충돌하는 단축키는 건너뜀) 또는 `Replace` 선택.

`.sniq` 는 사람이 직접 편집 가능한 INI 형식:

```ini
[snap]
grid     = 3x2
region   = 0,0 -> 0,1
shortcut = ctrl+opt+shift+L
```

기본 14종 세트 (Rectangle / Magnet 기본 단축키와 동일한 스킴) 는 빈 Snaps 창의 **Load default shortcuts** 버튼으로 바로 등록할 수 있습니다.

## 권한

Sniq 은 두 가지 macOS 권한이 필요합니다:

- **손쉬운 사용 (Accessibility)** — 창 이동/크기 조절
- **입력 모니터링 (Input Monitoring)** — modifier+드래그·키 감지

첫 실행 시 **How to Use...** 창이 안내합니다.

## 메뉴

- **Pause Sniq / Resume Sniq** — Grip+드래그 / Snap 단축키 감지 일시 정지·재개. pause 중엔 메뉴바 아이콘이 흐려지며, 재시작하면 항상 활성 상태로 시작
- **Snaps…** — Recent / Saved 목록, Export / Import 가 있는 전용 창
- **Settings...** — 레이아웃 · Modifier 바인딩 · 로그인 자동 실행
- **How to Use...** — 사용법 + 권한 안내
- **About Sniq** — 버전·빌드·저자·GitHub 링크
- **Quit Sniq** — 종료 (⌘Q)

## 설정 (Settings)

- **Primary layout (Grip)** / **Secondary layout (Grip + Flip)** — 행·열 (1–10) + 선택 영역 미리보기
- **Modifier bindings** — Grip / Flip / Stretch 역할을 `⇧ / ⌃ / ⌥ / ⌘` 중 하나로 각각 할당. 역할별 아이콘·설명과 함께 키캡 토글로 조작. Reset 로 기본값 복원
- **Launch at login** — 로그인 시 자동 실행

> `fn` 은 바인딩 불가능합니다. macOS 가 화살표 키 입력에 fn 비트를 자동으로 세트하기 때문에, 어떤 역할에 할당하든 매칭이 과도하게 느슨해집니다. Snap 단축키에도 fn 비트는 저장 시점에 자동 제거됩니다.

### 레이아웃 예시

| 사용 환경 | Primary | Secondary |
|---|---|---|
| 일반 노트북 | 2×1 (좌우 반반) | 2×2 (사분할) |
| 울트라와이드 | 3×1 | 3×2 |
| 세로 모니터 | 1×2 | 1×3 |
| 개발 | 3×1 (코드·브라우저·터미널) | 2×2 |

## 소스에서 빌드

macOS 15+ 및 Swift 6 이 필요합니다.

빠른 개발 실행 (SPM):

```bash
git clone https://github.com/oh-research/Sniq.git
cd Sniq/Sniq
swift run
```

릴리스 빌드 + DMG (`brew install xcodegen` 필요):

```bash
./scripts/local-build.sh       # build/Sniq.app + build/sniq-X.Y.Z.dmg
./scripts/local-install.sh     # /Applications 설치 + 실행
./scripts/local-uninstall.sh   # 제거 (사용자 설정은 보존)
```

버전은 `Sniq/project.yml` 의 `MARKETING_VERSION` 한 곳에서 관리됩니다.

## 요구 사항

- macOS 15.0 (Sequoia) 이상

## 삭제

### Homebrew

```bash
brew uninstall --cask sniq
```

### 수동 삭제

```bash
rm -rf /Applications/Sniq.app
```

## 기술 스택

- **Swift 6 + AppKit** — 이벤트 감지, 오버레이, 창 조작
- **SwiftUI** — Settings · Snaps · How to Use · About 창
- **CGEventTap (active)** — 마우스/modifier/keyDown 이벤트 수신. Grip 홀드 중 mouseDown 만 suppress 해서 OS 네이티브 드래그/선택을 가로채지 않고 창 어디든 스냅을 활성화. Snap 단축키는 키 매칭 시 suppress
- **AXUIElement** — 커서 아래 창 획득 및 크기/위치 변경. Electron 앱 (VS Code 등) 은 system-wide AX 쿼리 대신 pid 기반 폴백 경로 사용
- **UserDefaults JSON** — Snap 영구 저장소. 이벤트 탭 스레드 조회용 nonisolated mirror 와 SwiftUI 관찰용 `@Observable` store 를 분리
- **SPM + XcodeGen** — 개발(SPM)·배포(XcodeGen+xcodebuild) 이중 경로

## 라이선스

MIT License
