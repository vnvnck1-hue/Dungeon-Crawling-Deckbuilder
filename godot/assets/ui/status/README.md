# 상태이상 아이콘 6종

제작 기준: `docs/art-requests/status-icons.md`. 참고 화면은 `godot/screenshots/capture/status_all.png`, 손그림 톤은 `godot/assets/cards/stone_wall.png` 및 `godot/assets/ui/cost_badge/`를 확인했다.

## 산출물

실사용 아이콘은 모두 **128×128, 8비트 RGBA PNG, 투명 배경**이다. 그림 중심은 캔버스의 **(64, 64)**이며 중요한 형태는 중앙에 배치했다. 원형 바탕·상태 테두리·쌓인 숫자는 아이콘에 포함하지 않았다. 도발의 작은 느낌표는 요청서의 글자 금지 조건에 따라 생략하고 나무 방패와 중앙 쇠 장식을 사용했다.

| 파일 | 상태 / 그림 | 주색 |
| --- | --- | --- |
| `status_mark.png` | 표식 / 동심원 조준경·네 방향 눈금·중앙 점 | #FF4538 |
| `status_burn.png` | 화상 / 주황·노랑 불꽃 | #FF8C1F |
| `status_chill.png` | 냉기 / 여섯 갈래 눈송이 | #8CD9FF |
| `status_freeze.png` | 빙결 / 금 간 각진 얼음 덩어리 | #B3F2FF |
| `status_fury.png` | 투지 / 붉은 세 줄 발톱 자국 | #FF4030 |
| `status_taunt.png` | 도발 / 주황빛 나무 방패·쇠 장식 | #FF9E33 |
| `preview.png` | 확인용 1120×688. 체커보드 위 128px 원본, 96px 확대 칩, **28px 글리프와 34px 칩의 실제 크기 한 줄**. 짙은 남보라 원·상태색 테두리·숫자 예시 3/6/2/1/4/2 포함 | 엔진에서 사용하지 않음 |
| `README.md` | 파일 목록·실측 반경·후처리·프롬프트 | 문서 |

## 그림이 차지하는 반경 (128px 기준)

픽셀 중심 `(x+0.5, y+0.5)`에서 캔버스 중심 `(64, 64)`까지의 거리로 측정했다. 알파 1 이상은 안티앨리어싱까지 포함한 실제 전체 반경이다. 여섯 아이콘 모두 **반경 52px(지름 104px) 안**에 들어간다.

| 파일 | 전체 반경, 알파 ≥1 (px) | 본체 반경, 알파 ≥128 (px) | 알파 경계 상자의 중심 오차 (x, y px) |
| --- | ---: | ---: | --- |
| `status_mark.png` | 51.56 | 49.52 | (0, 0) |
| `status_burn.png` | 51.91 | 49.42 | (0, 0) |
| `status_chill.png` | 50.32 | 49.44 | (0, 0) |
| `status_freeze.png` | 51.50 | 49.42 | (0, 0) |
| `status_fury.png` | 50.32 | 48.58 | (-0.5, -0.5) |
| `status_taunt.png` | 51.03 | 48.97 | (0, 0) |

## 제작·후처리

내장 `image_gen` 도구로 서로 다른 프롬프트를 사용해 아이콘을 1종씩 총 6회 생성했다. 모든 호출에서 `transparent_background=true`를 요청했다. 생성 원본은 실제 알파 채널이 있는 RGBA였으므로 원본 알파를 기준으로 배경을 분리했다. 얼음의 흰 하이라이트를 보존하기 위해 흰색 전체를 지우는 색상 키 방식은 사용하지 않았다.

**환경 제한:** 실행 가능한 Python에 Pillow(PIL)가 없고, 패키지 다운로드는 네트워크 제한으로 실패했다. 따라서 사용자가 지정한 PIL 대신 **Python 3.13 표준 라이브러리**로 PNG 필터 해제·알파 정리·중앙 정렬·축소·저장을 수행했다. PIL을 사용했다는 의미는 아니다.

후처리는 알파 8 이하의 미세한 잔여 배경 제거 → 알파 경계 상자 중심 정렬 → 프리멀티플라이드 알파 상태의 면적 축소와 Lanczos-3 리샘플링 → 28px에서 읽히도록 약 2px 검정 외곽선 보강 → 128×128 캔버스 중앙 배치 순서다. 알파가 0인 픽셀의 RGB는 모두 (0,0,0)으로 정리했다. 흰 매트나 배경색이 가장자리에 섞이지 않도록 원본 알파를 보존했다. 실제 중앙 정렬 오차는 최대 0.5px다.

`preview.png`의 원형 칩·테두리·숫자·문구는 확인용으로만 합성했다. 이 합성에는 Windows System.Drawing을 사용했다. 128px 체커보드 배경과 짙은 남보라 배경, 28px 축소본을 시각 확인했다.

이 제작 작업에서 쓰기 대상으로 삼은 Godot 경로는 `godot/assets/ui/status/`뿐이다. `.gd`, `.tscn`, 셰이더에는 쓰기를 수행하지 않았다. 기존 파일의 전후 해시 검사에서는 310개 중 306개가 동일하고, 이 작업에서 쓰지 않은 `dungeon/core/battle.gd`, `dungeon/shaders/dungeon_ground.gdshader`, `dungeon/view/forest_world.gd`, `dungeon/view/unit_view.gd` 네 파일의 동시 변경이 감지됐다. 해당 변경은 되돌리거나 수정하지 않았다. Godot 실행 검증은 수행하지 않았다.

## 최종 생성 프롬프트

각 호출의 실제 프롬프트는 아래 **공통 본문 + 해당 Subject 문장**이다. 내장 도구 모드를 사용했으며 CLI/API 폴백은 사용하지 않았다.

### 공통 본문

```text
Use case: stylized-concept. Asset type: single status-effect glyph for a hand-drawn winter forest expedition fantasy card game. Generate exactly ONE isolated icon on a genuinely transparent background, no background disk or badge, no border frame. Bold slightly irregular near-black ink outline, warm storybook hand-painted fills with sparse chunky shading. Designed to remain readable at 28px: strong simple silhouette, outline about 4-5% of symbol width, no micro-details, no shadows, no exterior glow, no detached specks. Center the whole symbol inside an imaginary 104px-diameter circle on a 128px square canvas (scaled up for generation), with ample transparent margin. Keep essential detail in center or upper-left; lower-right quadrant may be covered by a number. No text, numbers, letters, symbols resembling typography, watermark, props, scenery or UI. Produce crisp clean opaque colored fills and transparent negative space.
```

### mark / 표식

```text
Subject: a vivid vermilion red (#FF4538) hunting reticle: one bold circular sight ring plus an inner concentric ring, four short cardinal sight ticks, and a solid central red dot. Transparent spaces between red concentric rings, not a filled badge. Strong dark ink outlines around all red components. Restrained lighter red brush highlights. Whole reticle is the glyph itself.
```

### burn / 화상

```text
Subject: a single plump orange (#FF8C1F) flame silhouette with a slightly curling tall tip and two short side tongues, and one simple bright golden-yellow inner flame. Strict orange and yellow two-tone flame, bold black outline. No campfire logs, no embers. Rounded compact readable blaze.
```

### chill / 냉기

```text
Subject: one sky-blue (#8CD9FF) six-armed branched snowflake ice crystal, exactly six chunky arms at 60-degree spacing with one strong V-shaped branch pair on each arm. Icy white small highlights within blue arms. Open transparent gaps between arms. Bold dark outlines, simple radial silhouette; unmistakably a snowflake rather than a solid ice block.
```

### freeze / 빙결

```text
Subject: one chunky angular pale-cyan (#B3F2FF) hexagonal ice crystal block, broad solid faceted shape, dark-blue facet shadows, a small stark-white branching crack across its upper-left and center suggesting frozen imprisonment. Single solid ice block; no snowflake arms, no person or lettering inside. Bold dark ink perimeter and just a few faceted internal divisions.
```

### fury / 투지

```text
Subject: exactly THREE broad parallel red (#FF4030) claw slash marks, aggressive slightly curved diagonal tapered gouges running from upper-right toward lower-left. Separate opaque scarlet slash shapes with thick near-black outlines and one restrained warm red-orange highlight each. No hand, no flame, no background object. Group the three marks into a compact powerful silhouette; transparent gaps between marks.
```

### taunt / 도발

```text
Subject: one compact orange-brown (#FF9E33) wooden heater shield, flat top with gently angled shoulders, rounded pointed bottom, thick near-black ink perimeter, two or three broad wooden planks, a simple small pale steel central boss and steel rim. Warm orange wood is dominant. Shield alone: no exclamation mark or letters, no text, no numbers, no weapons, no extra icon. Upper-left metal highlight, restrained hand-painted texture.
```

