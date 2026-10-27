# 궁수 전용 원화 10장

요청서: `docs/art-requests/synergy-cards.md`. 이번 작업 범위는 궁수 10장과 이 문서다.

## 파일

모두 **1024 × 1536, RGB, PNG**. 제목·분류·규칙 칸은 기준 원본처럼 글자 없는 상태다.

| 파일 | 이름 |
|---|---|
| [expose.png](expose.png) | 약점 노출 |
| [finisher.png](finisher.png) | 마무리 사격 |
| [hunt_signal.png](hunt_signal.png) | 사냥 신호 |
| [arrow_bundle.png](arrow_bundle.png) | 화살 뭉치 |
| [quick_shot.png](quick_shot.png) | 속사 |
| [arrow_storm.png](arrow_storm.png) | 화살 폭풍 |
| [steady_aim.png](steady_aim.png) | 정조준 |
| [fire_tips.png](fire_tips.png) | 불붙은 화살촉 |
| [scout.png](scout.png) | 정찰 |
| [arrow.png](arrow.png) | 화살 |

## 프레임 합성 방식

- 기준은 `godot/assets/cards/stone_wall.png` 원본 1024 × 1536이다. 전체 카드를 생성 모델로 다시 그리지 않았다.
- 내장 `image_gen` 도구를 카드마다 한 번씩 호출해 **그림 창 일러스트만** 새로 생성했다. 정사각형 원화의 손그림 검정 윤곽선·눈 덮인 밤 숲·초록 궁수 액센트를 통일했다. 표식은 붉은색, 불붙은 화살촉의 불꽃은 주황색이다.
- Python 3.12.14 / Pillow 12.3.0으로 기준 카드의 그림 창 경계를 마스크로 지정했다. 같은 마스크를 10장 모두에 사용했다. 마스크 경계 상자는 `(112, 366, 914, 1089)`이다(오른쪽·아래 제외).
- 그림 창 모양은 단순 직사각형이 아니다. 나무 기둥·상단 곡선 받침·하단 검정 분리선을 따라 잘랐다. 경계의 기존 검정 잉크 픽셀은 원본에서 보존했다.
- 9장은 `ImageOps.fit(..., (802, 723), LANCZOS, centering=(0.5, 0.5))`로 비율을 유지하며 중앙 크롭했다. `arrow`는 화살촉과 깃 끝이 양쪽 모서리에 가려지지 않도록 원화 전체를 `resize((802, 723), LANCZOS)`로 맞췄다.
- `Image.composite(새 그림 레이어, 기준 카드, 마스크)`로 합성했다. 마스크 밖은 재그림·색 보정·리사이즈 없이 **원본 픽셀 그대로**다. 보라 테두리, 지붕, 나무 기둥, 눈 덮인 솔가지·열매, 상단 판과 하단 양피지 판의 위치와 모양을 유지한다.
- `arrow`의 반투명 초록 빛은 그림 창 안에 있다. 바깥 프레임은 다른 9장과 동일하다.

### 마스크 재현

다음은 실제 사용한 마스크 알고리즘이다. 좌표는 기준 PNG의 픽셀 좌표다.

```python
from PIL import Image, ImageDraw, ImageFilter, ImageChops, ImageOps

base = Image.open("godot/assets/cards/stone_wall.png").convert("RGB")
outline = [
    (191,361),(831,361),(838,373),(851,383),(870,391),(899,395),
    (900,428),(906,439),(919,449),(919,953),(906,965),(900,981),
    (900,1022),(890,1028),(887,1042),(887,1074),(866,1077),
    (836,1084),(790,1091),(730,1096),(650,1100),(550,1102),
    (450,1102),(350,1099),(270,1095),(210,1088),(171,1081),
    (139,1078),(137,1041),(132,1030),(125,1021),(125,982),
    (121,970),(108,956),(106,950),(106,444),(118,435),(125,425),
    (127,396),(151,391),(171,382),(184,372)
]
mask = Image.new("L", base.size, 0)
ImageDraw.Draw(mask).polygon(outline, fill=255)
band = ImageChops.subtract(
    mask.filter(ImageFilter.MaxFilter(21)),
    mask.filter(ImageFilter.MinFilter(21)),
)
px, m, b = base.load(), mask.load(), band.load()
for y in range(350, 1115):
    for x in range(90, 935):
        if b[x, y] and max(px[x, y]) < 70:
            m[x, y] = 0

# 하단 분리선 위에서 멈춰 양피지를 완전히 보존한다.
for x in range(130, 901):
    y = 1120
    while y > 1040 and max(px[x, y]) >= 70:
        y -= 1
    if y <= 1040:
        continue
    while y > 1040 and max(px[x, y]) < 70:
        y -= 1
    for yy in range(y + 1, 1121):
        m[x, yy] = 0

x0, y0, x1, y1 = mask.getbbox()
# source_path에는 아래 표의 생성 원화 경로를 넣는다.
art = Image.open(source_path).convert("RGB")
size = (x1 - x0, y1 - y0)
panel = (
    art.resize(size, Image.Resampling.LANCZOS)
    if card_id == "arrow"
    else ImageOps.fit(
        art, size, method=Image.Resampling.LANCZOS,
        centering=(0.5, 0.5),
    )
)
layer = base.copy()
layer.paste(panel, (x0, y0))
result = Image.composite(layer, base, mask)
result.save(f"godot/assets/cards/synergy/{card_id}.png", optimize=True)
```

## 검증

- 10장 모두 1024 × 1536 PNG로 다시 열어 크기와 디코딩을 확인했다.
- 합성 마스크 밖 픽셀을 기준 카드와 비교했으며 **10장 모두 차이 0픽셀**이다.
- 카드 상단 `(0, 0, 1024, 355)`, 하단 `(0, 1110, 1024, 1536)` 영역을 따로 비교해 동일함을 확인했다. 텍스트나 별도 분류 글자를 추가하지 않았다.
- 각 완성본을 축소해 육안으로 확인했다. 붉은 표식, 두 발 속사, 다수의 화살 폭풍, 한쪽 눈을 감은 정조준, 송진 화살촉 점화, 나뭇가지 정찰, 단일 화살 구분을 확인했다.
- 기존 카드 PNG와 `text_layout.json`의 SHA-256이 작업 시작 시점과 동일함을 확인했다. 이 작업에서는 `.gd`, `.tscn`, 셰이더를 편집하지 않았다. 병행 작업의 코드 변경은 수정하거나 되돌리지 않았다.
- 전사·마법사 원화, `contact_sheet.png`, 공용 `README.md`는 이 작업에서 만들지 않았다.

## 생성 원화와 프롬프트

생성 방식은 내장 이미지 도구이며 CLI/API 우회 방식은 사용하지 않았다. 원화는 도구 기본 저장 위치에 남아 있다. 카드 프레임은 프롬프트에 포함하지 않았다.

원화 디렉터리: `C:\Users\Loadcomplete\.codex\generated_images\01a17be9-b991-7b23-b7a4-a9d14552b79b\`

| 카드 | 원화 파일 |
|---|---|
| `expose` | `exec-adaabdb1-c2f2-426e-82b3-744ea2e99f7b.png` |
| `finisher` | `exec-f800ec0f-5255-498a-be62-9f28bbbfa5b9.png` |
| `hunt_signal` | `exec-b2b9f379-c21c-4d3b-8e79-5ffbca9e64eb.png` |
| `arrow_bundle` | `exec-329e8c0b-dba2-454c-b907-90b2f4003849.png` |
| `quick_shot` | `exec-9653041c-f3a1-4f25-8d90-fb259a0da796.png` |
| `arrow_storm` | `exec-04b79cf2-3c2a-47ef-9108-f084050bd766.png` |
| `steady_aim` | `exec-092b60e6-a138-4d35-983e-b4e3349df32f.png` |
| `fire_tips` | `exec-8543e0ed-c137-4e51-89df-5ff5f9da0b33.png` |
| `scout` | `exec-049f8df8-8181-4ae1-9636-802002668b65.png` |
| `arrow` | `exec-316548ba-6d88-46a2-be1a-a3397fc4184f.png` |

아래는 실제 전달한 최종 프롬프트다.

<details>
<summary>expose</summary>

```text
Use case: illustration-story. Asset type: ONLY a square full-bleed illustration for the interior window of a winter fantasy deckbuilding card; no card frame. Primary request: EXPOSE / reveal weakness: a dark enemy goblin silhouette in a snowy midnight fir forest, several overlapping bright RED concentric bullseye target marks float over its torso, a watchful hunter's narrowed eye visible in the upper-left foreground under a fur hood. Bold hand-drawn black ink contours, richly painted textured storybook comic illustration, crisp shapes, midnight blue snowy forest, warm brown leather and cream fur, subtle archer green #73D973 glint in the hunter eye. Large immediately readable enemy silhouette and red overlapping targets as focal point. Square composition, important subjects inside central 80 percent, edge-to-edge forest background. No text, no letters, no numbers, no typography, no UI, no border, no parchment, no watermark, no logos. This is standalone illustration art, not a complete card.
```

</details>

<details>
<summary>finisher</summary>

```text
Use case: illustration-story. Asset type: standalone square full-bleed painted illustration ONLY, to be composited into a winter fantasy game card. Style: bold hand-drawn BLACK contours, richly textured storybook comic art, crisp readable forms, snowy midnight blue fir forest, brown leather and cream fur, subtle archer green #73D973 accents. Composition: large readable focal motif, important elements inside central 80 percent, forest artwork continues to all edges. No text, letters, numbers, typography, UI, card frame, borders, parchment, watermark or logos. Primary request: FINISHER SHOT. One and only one luminous green-tinted arrow plunges diagonally through the exact middle of a bright RED concentric bullseye hovering on a shadowy goblin silhouette. A sharp dramatic burst of red target shards and green light at the point of impact, speed streaks. Snow and tall dark firs behind. Single powerful projectile, no bow or person in foreground.
```

</details>

<details>
<summary>hunt_signal</summary>

```text
Use case: illustration-story. Asset type: standalone square full-bleed painted illustration ONLY, to be composited into a winter fantasy game card. Style: bold hand-drawn BLACK contours, richly textured storybook comic art, crisp readable forms, snowy midnight blue fir forest, brown leather and cream fur, subtle archer green #73D973 accents. Composition: large readable focal motif, important elements inside central 80 percent, forest artwork continues to all edges. No text, letters, numbers, typography, UI, card frame, borders, parchment, watermark or logos. Primary request: HUNT SIGNAL. A rugged fur-hooded archer in green wool and brown leather blows a curved animal-horn hunting trumpet, both gloved hands holding the horn at mouth level. Radiant translucent GREEN soundwave rings expand from the bell through a snowy blue nighttime pine forest. Three-quarter waist-up composition, readable profile and horn silhouette, purposeful expedition mood.
```

</details>

<details>
<summary>arrow_bundle</summary>

```text
Use case: illustration-story. Asset type: standalone square full-bleed painted illustration ONLY, to be composited into a winter fantasy game card. Style: bold hand-drawn BLACK contours, richly textured storybook comic art, crisp readable forms, snowy midnight blue fir forest, brown leather and cream fur, subtle archer green #73D973 accents. Composition: large readable focal motif, important elements inside central 80 percent, forest artwork continues to all edges. No text, letters, numbers, typography, UI, card frame, borders, parchment, watermark or logos. Primary request: ARROW BUNDLE. A leather quiver tipped on its side, a bundle of many wooden arrows bound together with coarse twine spills outward from its opening onto fresh snow. Pale feather fletchings, broad steel points, green thread wraps #73D973. Close view still life, diagonal arrangement, magical green glimmer reflecting lightly on the snowy foreground, dark blue frosty fir forest behind.
```

</details>

<details>
<summary>quick_shot</summary>

```text
Use case: illustration-story. Asset type: standalone square full-bleed painted illustration ONLY, to be composited into a winter fantasy game card. Style: bold hand-drawn BLACK contours, richly textured storybook comic art, crisp readable forms, snowy midnight blue fir forest, brown leather and cream fur, subtle archer green #73D973 accents. Composition: large readable focal motif, important elements inside central 80 percent, forest artwork continues to all edges. No text, letters, numbers, typography, UI, card frame, borders, parchment, watermark or logos. Primary request: QUICK SHOT. A fur-hooded archer rapidly releasing exactly TWO arrows from a curved wooden longbow, two arrows flying side by side across the central picture from left toward right. Strong drawn motion afterimages of the bow limb and gloved drawing hand show successive string pulls. Green #73D973 luminous speed trails; snowy midnight fir forest behind, dynamic three-quarter medium shot. Clear bowstring mechanics, legible two distinct arrows, thick ink edges.
```

</details>

<details>
<summary>arrow_storm</summary>

```text
Use case: illustration-story. Asset type: standalone square full-bleed painted illustration ONLY, to be composited into a winter fantasy game card. Style: bold hand-drawn BLACK contours, richly textured storybook comic art, crisp readable forms, snowy midnight blue fir forest, brown leather and cream fur, subtle archer green #73D973 accents. Composition: large readable focal motif, important elements inside central 80 percent, forest artwork continues to all edges. No text, letters, numbers, typography, UI, card frame, borders, parchment, watermark or logos. Primary request: ARROW STORM. Dozens of sharply readable wooden arrows with pale fletchings rain downward from the night sky, arcing together in a sweeping vortex of icy wind over a snowy fir forest. Wide dramatic view from below into the storm, dense arrow silhouettes across the sky, subtle GREEN #73D973 magical wind spirals, no people close up, no bow. The sky is filled with many arrows plunging toward the ground.
```

</details>

<details>
<summary>steady_aim</summary>

```text
Use case: illustration-story. Asset type: standalone square full-bleed painted illustration ONLY, to be composited into a winter fantasy game card. Style: bold hand-drawn BLACK contours, richly textured storybook comic art, crisp readable forms, snowy midnight blue fir forest, brown leather and cream fur, subtle archer green #73D973 accents. Composition: large readable focal motif, important elements inside central 80 percent, forest artwork continues to all edges. No text, letters, numbers, typography, UI, card frame, borders, parchment, watermark or logos. Primary request: STEADY AIM. Tight portrait of a fur-hooded green-clad archer with one eye CLOSED and the other narrowed with calm focus, pausing the breath. Gloved hand draws back an arrow on a wooden bow; single arrow lined up at eye level, large steel arrowhead glowing a small focused GREEN #73D973 light in foreground. Snow-dusted cream fur, brown leather, blue midnight fir forest. Serene stillness, no explosive trails, crisp black contours, readable eye and arrow tip.
```

</details>

<details>
<summary>fire_tips</summary>

```text
Use case: illustration-story. Asset type: standalone square full-bleed painted illustration ONLY, to be composited into a winter fantasy game card. Style: bold hand-drawn BLACK contours, richly textured storybook comic art, crisp readable forms, snowy midnight blue fir forest, brown leather and cream fur, subtle archer green #73D973 accents. Composition: large readable focal motif, important elements inside central 80 percent, forest artwork continues to all edges. No text, letters, numbers, typography, UI, card frame, borders, parchment, watermark or logos. Primary request: FIRE TIPS. Close-up of two leather-gloved archer hands preparing a resin-coated steel arrowhead, lighting it with a small flaming wooden taper. ONE visible arrow shaft crosses diagonally; sticky amber pine resin on the triangular steel point ignites in vivid ORANGE fire. Warm orange firelight on leather and snow, small green #73D973 wrist wrap. Snowy blue midnight pine forest behind. Strong bold ink outline, legible hands, resin and orange flame focal point. No giant explosion, no glowing green fire.
```

</details>

<details>
<summary>scout</summary>

```text
Use case: illustration-story. Asset type: standalone square full-bleed painted illustration ONLY, to be composited into a winter fantasy game card. Style: bold hand-drawn BLACK contours, richly textured storybook comic art, crisp readable forms, snowy midnight blue fir forest, brown leather and cream fur, subtle archer green #73D973 accents. Composition: large readable focal motif, important elements inside central 80 percent, forest artwork continues to all edges. No text, letters, numbers, typography, UI, card frame, borders, parchment, watermark or logos. Primary request: SCOUT. A fur-hooded green-cloaked archer crouches high on a thick snow-covered pine branch, holding a small warm amber lantern out in one gloved hand and looking out over a vast snowy midnight fir forest. Longbow strapped on back. Medium-wide view, branch runs diagonally under the archer, distant moonlit forest valley gives depth. Muted archer green #73D973 cloth and small lantern glass glint, adventurous watchful mood, chunky ink contours.
```

</details>

<details>
<summary>arrow</summary>

```text
Use case: illustration-story. Asset type: standalone square full-bleed painted illustration ONLY, to be composited into a winter fantasy game card. Style: bold hand-drawn BLACK contours, richly textured storybook comic art, crisp readable forms, snowy midnight blue fir forest, brown leather and cream fur, subtle archer green #73D973 accents. Composition: large readable focal motif, important elements inside central 80 percent, forest artwork continues to all edges. No text, letters, numbers, typography, UI, card frame, borders, parchment, watermark or logos. Primary request: ARROW, temporary conjured projectile. One single complete wooden arrow ONLY, isolated diagonally from lower left to upper right against a simple deep-blue snowy forest atmosphere. Steel broadhead, pale feather fletching, green #73D973 thread bindings, clear uncomplicated silhouette. A delicate translucent GREEN ethereal glow runs around the periphery of the ILLUSTRATION area and lightly around the arrow to imply an ephemeral generated card. Keep the central arrow large, straight, fully visible including tip and fletching. No bow, no person, no quiver, no extra arrows. No physical border or card frame. Clean simple composition with restrained airy glow.
```

</details>

