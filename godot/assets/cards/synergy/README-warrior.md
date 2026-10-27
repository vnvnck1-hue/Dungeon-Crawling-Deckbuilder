# 전사 시너지 카드 원화 9장

요청: `docs/art-requests/synergy-cards.md`의 전사 표만 제작. 출력은 모두 **1024 × 1536, RGB, PNG**이며 제목·분류·규칙 영역에 문자를 넣지 않았다.

## 파일 목록

- `shield_throw.png`
- `blood_oath.png`
- `thorn_armor.png`
- `bulwark.png`
- `shoulder_charge.png`
- `sweep.png`
- `pull.png`
- `wall_drive.png`
- `regroup.png`

## 생성 및 합성 방식

- 원화는 내장 `image_gen.imagegen` 도구로 카드별로 각각 생성했다. CLI/API 대체 경로는 사용하지 않았다.
- `godot/assets/cards/stone_wall.png`를 원화 생성의 **화풍 참조**로 제공했다. 프레임은 생성 도구로 다시 그리지 않았다.
- 완성 카드의 바탕은 기준 파일을 RGB로 연 원본 픽셀이다. 크기 변경·이동·회전·색 보정 없이 사용했다.
- PIL로 기준 카드의 굵은 검정 안쪽 경계를 추출했다. 밝기 조건 `max(R,G,B) >= 45`로 통과 영역을 만들고, 그림 속 먹선이 창을 가르지 않도록 안전한 내부 사각형 4개를 통과 영역으로 지정했다. 중앙에서 flood fill한 뒤 각 행의 내부 구멍만 채워 1비트 마스크를 만들었다.
- 마스크 범위는 `(112, 366, 914, 1089)` (PIL 좌표, 오른쪽·아래 미포함), 포함 면적은 **563,374픽셀**이다. 외곽의 곡선과 기둥 돌출부를 따라가므로 단순 사각형으로 프레임을 덮지 않는다.
- 생성 원화만 `ImageOps.fit` / LANCZOS / 중앙 기준으로 **802 × 723**에 맞췄다. 종횡비는 유지하고 넘치는 위·아래를 중앙 크롭했다.
- `Image.composite(layer, base, mask)`로 그림 창 내부만 교체했다. 마스크를 흐리거나 프레임과 섞지 않았다. 검정 외곽선·보라색 테두리·나무 기둥·박공·눈 덮인 솔가지·열매 장식·빈 양피지는 기준 카드 픽셀을 그대로 유지한다.
- 아홉 카드 모두 동일한 마스크와 합성 절차를 적용했다.

기준 PNG SHA-256: `f14f6f7c033c22eff4a6085e0b1ce32d842c31e02261258d587c8f9b036ae672`

### 사용한 PIL 코드

프로젝트 루트에서 실행하는 코드이며, 아래 `compose`에 각 원화 경로와 결과 PNG 경로를 전달한다.

```python
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps, ImageChops

base = Image.open("godot/assets/cards/stone_wall.png").convert("RGB")
walk = Image.new("L", base.size)
walk.putdata([255 if max(p) >= 45 else 0 for p in base.getdata()])
draw = ImageDraw.Draw(walk)
# 그림 속 먹선은 내부로 취급한다. 아래 네 영역은 모두 그림 창 안쪽이다.
for rect in [(240, 367, 780, 1075), (150, 410, 880, 1065),
             (140, 450, 890, 1014), (115, 500, 910, 949)]:
    draw.rectangle(rect, fill=255)
ImageDraw.floodfill(walk, (512, 700), 128, thresh=0)
mask = walk.point(lambda value: 255 if value == 128 else 0)
pixels = mask.load()
for y in range(base.height):
    xs = [x for x in range(base.width) if pixels[x, y]]
    if xs:
        for x in range(min(xs), max(xs) + 1):
            pixels[x, y] = 255

box = mask.getbbox()  # (112, 366, 914, 1089), 오른쪽·아래쪽은 미포함
size = (box[2] - box[0], box[3] - box[1])  # 802 × 723

def compose(source_path, destination):
    art = Image.open(source_path).convert("RGB")
    art = ImageOps.fit(art, size, method=Image.Resampling.LANCZOS,
                       centering=(0.5, 0.5))
    layer = base.copy()
    layer.paste(art, box[:2])
    result = Image.composite(layer, base, mask)
    result.save(destination)
    saved = Image.open(destination).convert("RGB")
    diff = ImageChops.difference(saved, base)
    diff.paste((0, 0, 0), (0, 0), mask)
    assert diff.getbbox() is None  # 그림 창 바깥 차이 0
    assert saved.size == (1024, 1536)
```

## 확인 결과

- PNG를 저장한 뒤 다시 열어 **9장 모두 1024 × 1536**인지 검사했다.
- 카드별 기준 카드와의 `ImageChops.difference`에서 그림 창 마스크 내부를 제외한 결과는 전부 **변경 픽셀 0**이었다.
- 상단 `y < 366`, 하단 `y >= 1089`, 좌측 `x < 112`, 우측 `x >= 914`도 개별 비교했다. 제목·분류·규칙 영역은 기준의 빈 상태와 동일하다.
- 원본 카드 PNG 50개와 `text_layout.json`의 작업 전후 SHA-256을 비교해 동일함을 확인했다.
- 전체 크기 대표 카드와 각 카드 축소 미리보기로 구도·주요 소품·경계·빈 글자 칸을 검수했다.
- 이 작업은 `.gd`, `.tscn`, 셰이더, `text_layout.json`을 수정하지 않았다. 궁수·마법사 원화, `contact_sheet.png`, 공용 `README.md`도 제작하지 않았다.

## 생성 원본 추적

원본은 이미지 도구의 기본 저장소에 두었고 최종 합성물은 이 디렉터리에 저장했다.

공통 원본 경로: `C:\Users\Loadcomplete\.codex\generated_images\01a17be9-b5de-7da1-9350-e2ffa4dc667f\`

| 카드 ID | 생성 원본 PNG |
|---|---|
| `shield_throw` | `exec-0a7e61fe-30c3-47e5-b8e9-b5b90690e8c7.png` |
| `blood_oath` | `exec-7277560b-4546-4963-a67d-53b06c13bd2f.png` |
| `thorn_armor` | `exec-397f0474-7a04-420b-bb2f-d304b5d900f2.png` |
| `bulwark` | `exec-3239f2ed-cd7c-4f0d-a000-53cb006304ee.png` |
| `shoulder_charge` | `exec-ab63ddb7-11b8-409b-a0db-f61975438276.png` |
| `sweep` | `exec-ac12f083-9f5f-47e5-ab72-ae97dc28c9a7.png` |
| `pull` | `exec-4a725593-6e4d-432d-88a7-49d5f9d9c47f.png` |
| `wall_drive` | `exec-6aa0dd58-28d5-4006-a1cf-c38c49b700b0.png` |
| `regroup` | `exec-b055244c-c285-45ee-846a-fee0f79037aa.png` |

## 실제 생성 프롬프트

각 호출은 다음 공통 프롬프트에 해당 카드 프롬프트를 이어 붙였다. 모든 호출은 `transparent_background=false`이고 `stone_wall.png`를 참조 이미지로 제공했다. 출력 크기는 도구가 결정하며 최종 카드 크기는 PIL 합성에서 확정했다.

### 공통 프롬프트

```text
Use case: stylized-concept. Asset type: one standalone game card illustration, NOT a whole card. Reference image stone_wall.png is STYLE REFERENCE ONLY: match its hand-painted winter-night fairy-tale expedition art, bold heavy black ink contours, richly textured wood/iron/snow, deep blue snowy fir forest, warm orange lantern light. Generate ONLY a square 1024x1024 full-bleed illustration, no frame or UI, no panels or border, no text, letters, numbers, labels, signature or watermark. Clear large readable central subject, essential action contained within central 85% of image for minor cropping. Warrior accent #F28C52 warm orange in equipment or lighting; deep navy and icy blue shadows.
```

### shield_throw

```text
A spinning round wooden warrior shield with dark iron rim and central iron boss hurtles through a snowstorm, seen at dynamic three-quarter angle. A single sweeping curved trail of wind and orange sparks behind it shows the path from lower left toward upper right. Large shield dominates center; snowy fir forest in background, no people needed.
```

### blood_oath

```text
Close view of a winter warrior's two hands making a blood oath. One hand is clenched resolutely with a small superficial red line across the palm, beside a plain steel dagger just used to mark it; restrained crimson resolve wisps rise around the fist. Thick leather wrist wraps and orange cloth cuff, snowy night forest background. Symbolic, non-graphic: tiny blood only, no gore, no severed parts; anatomically coherent hands and clear blade placement.
```

### thorn_armor

```text
A large rugged steel breastplate displayed on a wooden armor stand in a snowy night forest camp. Thorny dark vines curl tightly around the chest and shoulders, long sharp thorns tipped with delicate pale sky-blue frost. Warm orange firelight catches the iron edges and a small orange strap. Armor is the sole central focal object, readable silhouette, no character inside.
```

### bulwark

```text
A gigantic broad tall iron tower shield planted deeply in snow, seen from a low angle like an immovable fortress. Heavy rivets, thick battered iron plates, angular abstract golden rune-like luminous geometry (nonalphabetic, no readable writing), warm gold and orange highlights. Snow banks around base; snowy fir trees rise behind in blue night. Entire shield central and strong, no castle or extra shields.
```

### shoulder_charge

```text
A sturdy armored winter warrior silhouette charging from left toward right with ONE shoulder lowered forward, orange scarf trailing, powerful body diagonal and boots blasting snow. Direct shoulder impact sends a small green goblin ahead of him flying backward to the right, separated and clearly visible, surprised face. Non-graphic action, no blood. Snowy midnight fir forest, energetic orange impact arc, readable two-figure composition.
```

### sweep

```text
A powerful winter warrior swings one gigantic iron warhammer horizontally across the scene, long shaft held firmly in both hands. A broad bright orange crescent motion arc sweeps through a row of three small green goblins and bowls them sideways through spraying snow. Clearly readable hammer head at end of shaft and one continuous sweeping action. Snowy fir forest at night, non-graphic and playful battle, no blood.
```

### pull

```text
A winter warrior at left hauls a taut iron chain with both hands, pulling a small startled green goblin toward him from the right. At the other end a large curved iron grappling hook is firmly snagged around the goblin's broad leather waist belt, never through flesh. Show the full taut diagonal chain connecting hand and hook with clear spatial continuity; goblin skids heels through snow toward warrior. Orange scarf and warm orange glint, dark snowy fir forest. Non-graphic, no blood.
```

### wall_drive

```text
A small armored green goblin is slammed back against a massive dark rocky cliff in a snowy forest, arms flung sideways and back making the clear contact point. A powerful circular orange and crimson impact shockwave spreads from the contact; large branching cracks in rock and flying stone chips dominate the scene. Clear rock wall behind, snow below, icy blue night shadows. Non-graphic fantasy action, no blood or injury.
```

### regroup

```text
Quiet close-up of a winter warrior regrouping beside a small orange campfire. In foreground, two coherent hands carefully wrap a clean cream linen bandage around a bruised wrist while a loosened leather armor strap and iron buckle await tightening beside them. A parchment map lies open on a snowy log in lower middle, with simple unlabeled paths and terrain marks only, absolutely no writing. Armor and orange scarf visible at edge, peaceful blue midnight snowy fir camp, warm firelight, no battle.
```

