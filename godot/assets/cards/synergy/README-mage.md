# 마법사 시너지 카드 원화 8장

`docs/art-requests/synergy-cards.md`의 마법사 표만 제작했다. 아래 PNG는 모두 **1024×1536, RGBA**이며 제목·분류·규칙용 빈 판에 글자를 추가하지 않았다.

| 파일 | 그림 |
|---|---|
| `ember.png` | 보라 보석 지팡이 끝에서 떨어지는 작은 주황 불씨 |
| `shatter_strike.png` | 얼음에 갇힌 고블린과 사방으로 터지는 하늘색 파편 |
| `glacier_armor.png` | 마법사·전사·궁수를 함께 감싸는 반투명 얼음 방벽 |
| `chill_aura.png` | 보라 망토 마법사 주위를 도는 찬 안개와 서리 결정 |
| `spread.png` | 눈밭에서 주변 적들에게 번지는 원형 주황 불길 |
| `combust.png` | 불타는 고블린의 몸에서 치솟는 주황 불기둥 |
| `wildfire.png` | 붉은 하늘 아래 불타는 숲과 붉은 과녁 문양 |
| `meditate.png` | 눈을 감은 마녀, 떠 있는 펼친 책과 보라 기하학 마법 문양 |

## 생성과 합성 방식

그림 창 일러스트는 내장 **image_gen** 도구로 카드별로 한 번씩 생성했다. 생성물은 프레임·리본·양피지·글자 없이 그림만 있는 1315×1196 이미지다. 겨울 밤 눈 덮인 숲, 손그림 질감, 굵은 검정 외곽선과 보라색(`#B380FF`) 마법사 액센트를 공통으로 요청했다. 화염은 주황, 냉기·빙결은 하늘색, 표식은 붉은색으로 구분했다. 아래에 사용한 최종 프롬프트를 기록했다.

공통 프레임은 `../stone_wall.png`를 **크기·위치·색 변경 없이** 그대로 복사했다. 이 기준 카드에 있는 나무 기둥·박공 지붕·보라 바깥 테두리·눈 덮인 솔가지·주황 열매·빈 양피지 판을 재생성하거나 그리지 않았다. 다른 기준 카드들은 프레임 모양이 달라 혼합하지 않았다. 분류용 판이나 띠를 별도로 새로 그리지 않고 기준 카드의 빈 글자 영역을 유지했다.

Python 3.12.14 / Pillow 12.3.0으로 아래 순서대로 합성했다.

1. 기준 이미지의 그림 창에서 검정 프레임 안쪽 경계를 추적해 공통 1비트 마스크를 만들었다. 검정 기준은 `max(R,G,B) <= 45`, 연결 탐색 시작점은 `(500,1000)`, 탐색 범위는 `100 <= x < 924`, `350 <= y < 1116`이다.
2. 기존 그림의 검정 선이 프레임에 닿아 생긴 마스크의 움푹 팬 부분은 외곽의 볼록 포락선과 기둥 안쪽 경계 보정으로 메웠다. 상단 기둥 곡선 `y=402..481`은 추적값을 유지하고, `y=482..514`는 왼쪽 `117→113`, 오른쪽 `909→912`로 선형 연결했다. `y=515..949`는 `x=113..912`, 하단 기둥 `y=950..1070`은 추적값을 사용하되 `y=964..1012`의 오른쪽 경계를 `x=897`로 보정했다.
3. 마스크 가장자리 4픽셀 띠(`MinFilter(9)`로 얻은 내부와의 차이)에서는 기존의 검정 경계 픽셀을 보존했다. 완성 마스크의 경계 상자는 Pillow의 오른쪽·아래 제외 좌표로 **`(112,366,913,1089)`**, 교체 영역은 **561,621픽셀**이다. 8장 모두 동일한 마스크를 사용했다.
4. 생성 그림만 `ImageOps.fit(..., (801,723), method=LANCZOS, centering=(0.5,0.5))`로 비율을 유지해 중앙 크롭했다. 그림 창 마스크에만 삽입하고, 나머지는 기준 이미지의 원본 픽셀을 복사했다. 카드 전체를 리사이즈하거나 프레임 위치를 옮기지 않았다.
5. PNG로 저장한 뒤 다시 열어 1024×1536 크기와 RGBA 형식을 확인했다. 마스크 바깥 전체 RGBA 픽셀, 제목 영역 `(205,60)-(818,320)`, 규칙 영역 `(106,1164)-(916,1460)`을 기준 카드와 비교했다. **8장 모두 보존 영역의 변경 픽셀은 0**이다. 8장 합성 결과를 축소해 시각적으로 확인했다.

합성 핵심은 다음과 같다. `mask`는 위 방식으로 만든 공통 그림 창 마스크다.

```python
base = Image.open('godot/assets/cards/stone_wall.png').convert('RGBA')
bounds = mask.getbbox()  # (112, 366, 913, 1089)
art = ImageOps.fit(source.convert('RGBA'), (801, 723),
                   method=Image.Resampling.LANCZOS, centering=(0.5, 0.5))
layer = Image.new('RGBA', base.size)
layer.paste(art, bounds[:2])
card = Image.composite(layer, base, mask)
card.save(output_path)
```

기준 카드 SHA-256: `f14f6f7c033c22eff4a6085e0b1ce32d842c31e02261258d587c8f9b036ae672`.

이 작업은 전사·궁수 카드, `contact_sheet.png`, 공용 `README.md`를 생성하지 않았다. 기존 카드 PNG와 `.gd`, `.tscn`, 셰이더, `text_layout.json`도 수정하지 않았다.

## 최종 생성 프롬프트

### `ember`

```text
Use case: stylized-concept. Asset type: finished standalone illustration to be cropped into an existing fantasy card's art window, near-square landscape 1.10:1 aspect ratio. Paint ONLY the scene, full bleed all the way to every edge; no card layout. Style: rich hand-painted winter-night forest expedition storybook game art, thick confident BLACK ink outlines on characters, objects and elemental shapes, textured gouache colors and deliberate hatching, crisp readable silhouettes, snowy indigo evergreen forest, cobalt moonlight, warm glowing orange fire where relevant, subtle mage violet #B380FF accents. Art must feel like rustic illustrated fantasy rather than photorealism or 3D. Strong focused central composition with complete focal subject and comfortable cropping margins. No border, no frame, no UI, no banners, no parchment, no card title, no letters, numbers, readable text, watermark or logo. Magic symbols may be simple abstract geometric nonlinguistic marks only. Scene: EMBER: a close-up of a gnarled wooden wizard staff tip reaching diagonally from the upper right, a modest violet gemstone in its fork, releasing ONE small orange ember that has just detached and floats at center. The tiny ember is the main focal point and lights up snowflakes and the grain of the wood in the dark. Intimate quiet warmth against a dark snowy pine forest, no giant blaze, no extra fireballs. Strong black outlines.
```

### `shatter_strike`

```text
Use case: stylized-concept. Asset type: finished standalone illustration to be cropped into an existing fantasy card's art window, near-square landscape 1.10:1 aspect ratio. Paint ONLY the scene, full bleed all the way to every edge; no card layout. Style: rich hand-painted winter-night forest expedition storybook game art, thick confident BLACK ink outlines on characters, objects and elemental shapes, textured gouache colors and deliberate hatching, crisp readable silhouettes, snowy indigo evergreen forest, cobalt moonlight, warm glowing orange fire where relevant, subtle mage violet #B380FF accents. Art must feel like rustic illustrated fantasy rather than photorealism or 3D. Strong focused central composition with complete focal subject and comfortable cropping margins. No border, no frame, no UI, no banners, no parchment, no card title, no letters, numbers, readable text, watermark or logo. Magic symbols may be simple abstract geometric nonlinguistic marks only. Scene: SHATTER STRIKE: a single hostile goblin silhouette completely encased in translucent pale SKY-BLUE ice is bursting apart in an explosive clean magical fracture; readable angular icy shell with the frozen goblin silhouette visible within it, shards flying radially in every direction. Show frozen ice breaking, NO flesh wounds, blood or gore. A slender violet spell trail strikes the central ice from lower left. Snowy night pines behind, extremely clear bright cyan jagged shards and dramatic motion.
```

### `glacier_armor`

```text
Use case: stylized-concept. Asset type: finished standalone illustration to be cropped into an existing fantasy card's art window, near-square landscape 1.10:1 aspect ratio. Paint ONLY the scene, full bleed all the way to every edge; no card layout. Style: rich hand-painted winter-night forest expedition storybook game art, thick confident BLACK ink outlines on characters, objects and elemental shapes, textured gouache colors and deliberate hatching, crisp readable silhouettes, snowy indigo evergreen forest, cobalt moonlight, warm glowing orange fire where relevant, subtle mage violet #B380FF accents. Art must feel like rustic illustrated fantasy rather than photorealism or 3D. Strong focused central composition with complete focal subject and comfortable cropping margins. No border, no frame, no UI, no banners, no parchment, no card title, no letters, numbers, readable text, watermark or logo. Magic symbols may be simple abstract geometric nonlinguistic marks only. Scene: GLACIER ARMOR: three ALLIED winter forest adventurers grouped protectively inside a single curved translucent fortress-like barrier of thick glacial ICE. Central violet-cloaked witch with staff, sturdy warrior to one side, hooded archer to other, entire small party clearly sheltered. Focus is the protective faceted half-dome wall surrounding them with sky-blue inner glow reflected on their faces, solid upright crystal ice slabs like armor plates; snow and wind outside. Not an explosion, calm resilient protection. Heavy black ink outlines, hand-painted colors.
```

### `chill_aura`

```text
Use case: stylized-concept. Asset type: finished standalone illustration to be cropped into an existing fantasy card's art window, near-square landscape 1.10:1 aspect ratio. Paint ONLY the scene, full bleed all the way to every edge; no card layout. Style: rich hand-painted winter-night forest expedition storybook game art, thick confident BLACK ink outlines on characters, objects and elemental shapes, textured gouache colors and deliberate hatching, crisp readable silhouettes, snowy indigo evergreen forest, cobalt moonlight, warm glowing orange fire where relevant, subtle mage violet #B380FF accents. Art must feel like rustic illustrated fantasy rather than photorealism or 3D. Strong focused central composition with complete focal subject and comfortable cropping margins. No border, no frame, no UI, no banners, no parchment, no card title, no letters, numbers, readable text, watermark or logo. Magic symbols may be simple abstract geometric nonlinguistic marks only. Scene: CHILL AURA: a lone dark-haired witch in a thick violet winter cloak and pointed hood stands still in the center of snowy pine woods. Wide graceful spirals of cold pale SKY-BLUE mist circle around her at several heights, many distinct six-point frost crystals hover in the air, fresh white frost blooms on nearby branches. Her calm half-shadowed face is visible. Recurring icy aura, not impact or ice armor. The magical swirling mist has bold ink contours and translucent painted interiors, legible at small size. Subtle violet clasp and staff glow.
```

### `spread`

```text
Use case: stylized-concept. Asset type: finished standalone illustration to be cropped into an existing fantasy card's art window, near-square landscape 1.10:1 aspect ratio. Paint ONLY the scene, full bleed all the way to every edge; no card layout. Style: rich hand-painted winter-night forest expedition storybook game art, thick confident BLACK ink outlines on characters, objects and elemental shapes, textured gouache colors and deliberate hatching, crisp readable silhouettes, snowy indigo evergreen forest, cobalt moonlight, warm glowing orange fire where relevant, subtle mage violet #B380FF accents. Art must feel like rustic illustrated fantasy rather than photorealism or 3D. Strong focused central composition with complete focal subject and comfortable cropping margins. No border, no frame, no UI, no banners, no parchment, no card title, no letters, numbers, readable text, watermark or logo. Magic symbols may be simple abstract geometric nonlinguistic marks only. Scene: SPREAD: high three-quarter overhead view of a snowy forest clearing, ONE bright orange ignition point at center sends a circular expanding wave of ORANGE flame out in all directions across the snow, like branching wildfire. Three small hostile goblin silhouettes at separate positions around the circumference are just catching orange flames from the expanding ring, visually showing fire spreading to neighbors. The radial spreading ring is the dominant central silhouette. Dark cobalt snow and pines, small violet magical glimmer at the original center, bold black ink shapes, strong readability, no huge vertical explosion.
```

### `combust`

```text
Use case: stylized-concept. Asset type: finished standalone illustration to be cropped into an existing fantasy card's art window, near-square landscape 1.10:1 aspect ratio. Paint ONLY the scene, full bleed all the way to every edge; no card layout. Style: rich hand-painted winter-night forest expedition storybook game art, thick confident BLACK ink outlines on characters, objects and elemental shapes, textured gouache colors and deliberate hatching, crisp readable silhouettes, snowy indigo evergreen forest, cobalt moonlight, warm glowing orange fire where relevant, subtle mage violet #B380FF accents. Art must feel like rustic illustrated fantasy rather than photorealism or 3D. Strong focused central composition with complete focal subject and comfortable cropping margins. No border, no frame, no UI, no banners, no parchment, no card title, no letters, numbers, readable text, watermark or logo. Magic symbols may be simple abstract geometric nonlinguistic marks only. Scene: COMBUST: one hostile goblin at the center of a snowy forest path, dark intact silhouette with arms recoiling, already burning, suddenly a concentrated violent plume of ORANGE flame erupts upward from its torso and shoulders, doubling into two huge curling tongues of fire; bright yellow-orange core, black-edged flame shapes, showers of embers, outward pressure curls in snow. A small violet magical spark ignites the core. Dramatic VERTICAL burst focused on a single burning enemy, not a spreading ground ring, no target symbol, NO gore, no wounds, no exposed bone. Snowy indigo pines visible around the flame.
```

### `wildfire`

```text
Use case: stylized-concept. Asset type: finished standalone illustration to be cropped into an existing fantasy card's art window, near-square landscape 1.10:1 aspect ratio. Paint ONLY the scene, full bleed all the way to every edge; no card layout. Style: rich hand-painted winter-night forest expedition storybook game art, thick confident BLACK ink outlines on characters, objects and elemental shapes, textured gouache colors and deliberate hatching, crisp readable silhouettes, snowy indigo evergreen forest, cobalt moonlight, warm glowing orange fire where relevant, subtle mage violet #B380FF accents. Art must feel like rustic illustrated fantasy rather than photorealism or 3D. Strong focused central composition with complete focal subject and comfortable cropping margins. No border, no frame, no UI, no banners, no parchment, no card title, no letters, numbers, readable text, watermark or logo. Magic symbols may be simple abstract geometric nonlinguistic marks only. Scene: WILDFIRE: a snowy pine forest burning with vivid ORANGE flames under a deep RED smoke-filled night sky, fierce spreading fire seen between black tree silhouettes. The key identifying element is a clearly visible luminous RED bullseye target sigil, clean two concentric red circles with four short cardinal ticks, floating in front of the central blaze; a second smaller red target appears deeper among flames. These are magical target icons, no text. A few violet sparks subtly mingle in the embers. Snow remains on foreground dark pines, dramatic firelit winter woodland, heavy black ink outlines, central red bullseye must remain distinct from orange flames. No HUD or interface.
```

### `meditate`

```text
Use case: stylized-concept. Asset type: finished standalone illustration to be cropped into an existing fantasy card's art window, near-square landscape 1.10:1 aspect ratio. Paint ONLY the scene, full bleed all the way to every edge; no card layout. Style: rich hand-painted winter-night forest expedition storybook game art, thick confident BLACK ink outlines on characters, objects and elemental shapes, textured gouache colors and deliberate hatching, crisp readable silhouettes, snowy indigo evergreen forest, cobalt moonlight, warm glowing orange fire where relevant, subtle mage violet #B380FF accents. Art must feel like rustic illustrated fantasy rather than photorealism or 3D. Strong focused central composition with complete focal subject and comfortable cropping margins. No border, no frame, no UI, no banners, no parchment, no card title, no letters, numbers, readable text, watermark or logo. Magic symbols may be simple abstract geometric nonlinguistic marks only. Scene: MEDITATE: a peaceful dark-haired witch in a warm violet fur-trimmed cloak seated in meditation on a snow-dusted fallen log in a quiet winter-night evergreen grove, eyes gently CLOSED, calm relaxed face, both hands at rest. An OPEN spellbook floats before her chest, pages visibly BLANK with no writing, surrounded by a few glowing VIOLET abstract geometric magical marks (diamonds, circles and stars, NOT letters or an alphabet). Soft violet light illuminates her face, book and snow. Composed stillness, restorative focus, dominant clear witch-and-floating-book grouping, no fire or enemies, bold black outlines and rich painted textures.
```

