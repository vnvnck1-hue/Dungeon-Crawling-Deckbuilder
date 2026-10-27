# 카드 행동력 배지 — 컨셉 3종

[요청서](../../../docs/art-requests/cost-badge-concepts.md)를 기준으로 제작한 **방향 검토용 시안**이다. 세 이미지 모두 1536×1024 PNG이며, 내장 이미지 생성 도구 `image_gen`으로 생성하고 손패 축소 패널을 한 차례 수정했다.

참조: [카드 원본](../../../godot/assets/cards/stone_wall.png), [현재 손패](../../../godot/screenshots/capture/02_battle_fan.png).
굵은 검정 외곽선, 크림색 양피지, 따뜻한 목재, 보라색 테두리, 눈 덮인 겨울 원정대 장식을 공통으로 맞췄다.

각 장에는 카드 왼쪽 위 적용 확대, 숫자 없는 배지, 숫자 0~4 예시, 영웅 3색·행동력 부족 변형, 손패 크기 예시, 레이어 분리 설명이 들어 있다. 시안에 보이는 숫자는 합성 방향을 보여 주는 예시다. **추후 최종 에셋은 숫자 없는 투명 배지로 별도 제작하고 숫자는 엔진에서 올린다.** 이번 PNG는 배경과 설명을 포함한 보드이며 바로 사용하는 스프라이트나 실제 분리 레이어 파일은 아니다.

## A — 불씨 랜턴

[concept-a.png](concept-a.png)

눈이 살짝 쌓인 작은 랜턴의 어두운 유리창에 숫자를 얹는다. 하단 불씨와 유리 반사색으로 전사·궁수·마법사를 구분한다.

- 장점: 원정대의 랜턴과 직접 연결되고, 불이 켜짐/꺼짐으로 사용 가능 상태를 자연스럽게 표현한다. 어두운 유리창이 크림색 숫자를 받쳐 준다.
- 단점: 손잡이·지붕·눈이 숫자 공간을 줄인다. 34px에서는 측면 기둥과 불씨를 단순화해야 하며 주황색 랜턴 몸체와 전사 액센트의 구분이 약할 수 있다.
- 엔진 메모: 어두운 창 바탕 → 영웅색 불씨·반사 → 랜턴 몸체·눈 → 숫자 순서. 창 중앙을 가로지르는 철창은 두지 않는다. 비활성은 불씨·반사를 끄고 몸체를 차갑게 낮추며 숫자는 밝게 유지한다.

## B — 서리 룬 돌판

[concept-b.png](concept-b.png)

각진 석판에 눈과 짧은 밧줄을 붙이고, 넓고 어두운 면에 숫자를 얹는다. 측면·하단의 색 띠와 작은 룬 홈으로 영웅색을 표시한다.

- 장점: 세 안 중 숫자 면적과 대비가 가장 안정적이다. 카드 원본의 석벽·각인과 잘 이어지고, 발광 없이도 색 띠로 소속을 표시할 수 있다.
- 단점: 행동력보다는 방어력·방패로 읽힐 수 있다. 돌의 흠집·룬·밧줄을 모두 살리면 축소 시 복잡해지고, 색 띠가 손패 겹침에 가려질 수 있다.
- 엔진 메모: 무채색 석판 바탕 → 영웅색 띠·홈 마스크 → 돌 테두리·눈·밧줄 → 숫자 순서. 룬은 테두리에만 둔다. 비활성은 색 띠를 회색으로 바꾸고 석판을 어둡게 하되 숫자의 명도는 유지한다.

## C — 숲 보석 메달

[concept-c.png](concept-c.png)

따뜻한 나무 고리에 넓은 보석을 끼우고 눈·밧줄·솔가지로 프레임과 연결한다. 보석 둘레의 색 면이 영웅색을 담당하고 중심은 숫자를 위해 어둡게 비운다.

- 장점: 현재 원형 배지와 가까워 배치와 크기를 이어가기 쉽다. 보석의 넓은 색 면 덕분에 세 영웅의 구분이 가장 선명하다.
- 단점: 보석 반짝임이 숫자와 경쟁할 수 있다. 솔가지·열매·밧줄은 축소 시 덩어리로 뭉치므로 최종 소형 에셋에서는 줄이는 편이 좋다. 회색 보석만으로는 비활성이 약하게 보일 수 있다.
- 엔진 메모: 어두운 보석 바탕 → 영웅색 보석 면 → 나무 고리·눈·밧줄 → 숫자 순서. 중앙에는 강한 하이라이트를 넣지 않는다. 비활성은 보석을 연기 낀 회색으로 만들고 반짝임을 제거하며 목재·장식도 함께 낮춘다.

## 공통 엔진 구현 메모

아래는 시안 확정 후 적용할 제안이며, 이번 작업에서 엔진 코드는 수정하지 않았다.

| 항목 | 적용 메모 |
| --- | --- |
| 크기 | 카드 폭 약 110px, 배지 전체 외곽 약 34~40px, 기준 38px. 확대 그림의 디테일을 그대로 축소하지 말고 소형용으로 정리한다. |
| 색 | 전사 `#F28C52`, 궁수 `#73D973`, 마법사 `#B380FF`. 생성 그림의 조명색은 근사치이며 최종 마스크에는 정확한 값을 적용한다. |
| 숫자 | 중앙 안전 영역 약 20~24px 확보. 굵은 크림색 글자, 어두운 외곽선 약 1~2px, 글자 크기 약 22~26px부터 0~4를 확인한다. 크기는 실제 글꼴에 맞춰 조정한다. |
| 위치 | 카드 왼쪽 위를 기준으로 배지 중심을 고정한다. 살짝 돌출시키되 제목의 첫 글자를 가리지 않게 한다. 그림의 투명 여백과 배지의 실제 중심을 구분한다. |
| 겹침 | 배지는 해당 카드의 이동·회전·확대를 따라가게 하고, 돌출 부분이 잘리지 않도록 클리핑·그리기 순서를 확인한다. 장식은 인접 카드까지 넓게 뻗지 않게 한다. |
| 레이어 | 바탕·영웅색 마스크·전면 장식은 같은 캔버스와 피벗으로 제작한다. 숫자는 별도 Label로 최상단에 둔다. 전체 텍스처를 영웅색으로 물들이지 않는다. |
| 비활성 | 아트 레이어의 채도·명도와 발광만 조절한다. 부모 전체를 어둡게 해서 숫자까지 흐려지지 않도록 분리한다. 실제 사용 가능 여부는 기존 게임 판정에서 전달받는다. |
| 에셋 제작 | 방향 확정 후 숫자 없는 투명 PNG와 필요한 마스크를 별도 제작한다. 이번 보드에서 숫자 포함 그림을 잘라 최종 에셋으로 쓰지 않는다. |

손패 패널은 원본 1536×1024를 100% 배율로 열어 비교한다. 카드 폭 110px·배지 38px을 목표로 한 생성 목업이므로 픽셀 단위 실측 도면은 아니다. B의 오른쪽 원형 인셋은 확대 설명이다. 실제 인게임 가독성은 최종 에셋을 34/38/40px로 표시하고 손패 회전·겹침·행동력 부족 상태에서 확인해야 한다.

분위기를 우선하면 A, 숫자 가독성을 우선하면 B, 기존 원형 배지와 영웅색 구분을 우선하면 C가 적합하다.

## 생성 프롬프트 기록

내장 `image_gen` 사용. 최초 생성은 두 참조 이미지를 함께 입력했고, 수정은 각 생성 보드를 입력해 손패 패널만 축소하도록 요청했다. 아래는 실제 전달한 프롬프트다.

<details>
<summary>Concept A — 최초 생성</summary>

```text
Use case: ui-mockup. Create a polished landscape 1536x1024 game UI art direction concept board for a winter forest expedition card game's action-cost badge. Input image 1 is the supplied stone_wall card: use it as the card-frame compositing/style reference; input image 2 is the actual game screenshot: use it for scale, overlapping hand layout and purple snowy battlefield context. This is a concept presentation, not a final asset sheet. Match the card's hand-painted illustration, bold nearly black organic outlines, amber wooden beams, warm cream parchment, purple outer border, snow on pine sprigs, orange berries, rope and lantern warmth. Do not use generic modern flat UI, shiny sci-fi metal, photorealism or unrelated motifs.
Lay out a beautiful coherent design review board with restrained plum background, cream section titles, ample margins and clear aligned panels. Header identifies the concept letter and name. Upper left: one large crop of the supplied card's UPPER LEFT corner, showing the new badge straddling that corner, slightly protruding outside its frame. Keep the cream title panel largely clear. Upper right: a study of the badge silhouette and a genuinely EMPTY central face (no number, no rune pretending to be a number), alongside a labeled 0 1 2 3 4 number overlay test. Numerals must be bold warm ivory with very dark outlines, immediately legible, all five exactly.
Middle: four separate enlarged versions of precisely the same badge silhouette labeled WARRIOR, ARCHER, MAGE, INACTIVE. Warrior accent #F28C52, archer #73D973, mage #B380FF. Each carries example digit 2. Inactive is dark, desaturated, no emission, but numeral 2 remains readable. Do not obscure the digit with decoration.
Bottom: a compact mini hand over a strip of purple snowy battlefield resembling reference image 2. Show THREE small complete cards with wooden/cream/purple snowy frames, EACH approximately 110 screen pixels wide on the 1536px board; badges 34-40px across. Show example costs 1,2,3. Label HAND SCALE / CARD 110 PX / BADGE 38 PX. Small badges should be visibly small, not enlarged thumbnails. Include isolated blank badge study labeled EMPTY ART and separated dark-face / hero-accent / numeral layer miniatures if space permits. All text English, short correct labels only; no paragraph text, no Korean lettering required. Maintain reference illustration style everywhere, simple near-flat dark central numeral face for contrast, peripheral texture only. No watermark.
CONCEPT A — EMBER LANTERN. Compact squat lantern badge, about as wide as tall including its tiny top loop, chunky black contour, amber brass and wood-toned housing, little snow cap on roof. A large deep charcoal glass window holds the overlay number; the center is simple and uncluttered. Hero color is a restrained glowing flame sliver at the very bottom plus the glass side reflections, leaving the middle dark. No central flame behind the number, no cage bars crossing the number. Warm orange / vivid leafy green / violet flame variants, same warm wooden housing. Inactive: extinguished lantern, cool dark glass, gray wick at bottom, no glow, ivory number still visible. Silhouette recognizable at 38px, no long dangling chain, no sparks outside silhouette. The enlarged card corner example has digit 1. Design it as a tiny winter expedition lantern, clearly unlike a plain circular gem.
```

</details>

<details>
<summary>Concept B — 최초 생성</summary>

```text
Use case: ui-mockup. Create a polished landscape 1536x1024 game UI art direction concept board for a winter forest expedition card game's action-cost badge. Input image 1 is the supplied stone_wall card: use it as the card-frame compositing/style reference; input image 2 is the actual game screenshot: use it for scale, overlapping hand layout and purple snowy battlefield context. This is a concept presentation, not a final asset sheet. Match the card's hand-painted illustration, bold nearly black organic outlines, amber wooden beams, warm cream parchment, purple outer border, snow on pine sprigs, orange berries, rope and lantern warmth. Do not use generic modern flat UI, shiny sci-fi metal, photorealism or unrelated motifs.
Lay out a beautiful coherent design review board with restrained plum background, cream section titles, ample margins and clear aligned panels. Header identifies the concept letter and name. Upper left: one large crop of the supplied card's UPPER LEFT corner, showing the new badge straddling that corner, slightly protruding outside its frame. Keep the cream title panel largely clear. Upper right: a study of the badge silhouette and a genuinely EMPTY central face (no number, no rune pretending to be a number), alongside a labeled 0 1 2 3 4 number overlay test. Numerals must be bold warm ivory with very dark outlines, immediately legible, all five exactly.
Middle: four separate enlarged versions of precisely the same badge silhouette labeled WARRIOR, ARCHER, MAGE, INACTIVE. Warrior accent #F28C52, archer #73D973, mage #B380FF. Each carries example digit 2. Inactive is dark, desaturated, no emission, but numeral 2 remains readable. Do not obscure the digit with decoration.
Bottom: a compact mini hand over a strip of purple snowy battlefield resembling reference image 2. Show THREE small complete cards with wooden/cream/purple snowy frames, EACH approximately 110 screen pixels wide on the 1536px board; badges 34-40px across. Show example costs 1,2,3. Label HAND SCALE / CARD 110 PX / BADGE 38 PX. Small badges should be visibly small, not enlarged thumbnails. Include isolated blank badge study labeled EMPTY ART and separated dark-face / hero-accent / numeral layer miniatures if space permits. All text English, short correct labels only; no paragraph text, no Korean lettering required. Maintain reference illustration style everywhere, simple near-flat dark central numeral face for contrast, peripheral texture only. No watermark.
CONCEPT B — FROST RUNE SLAB. Compact vertical clipped-corner stone shield/slab with a stout dark charcoal slate face, warm sandy worn stone bevel matching the card's masonry, thick hand-inked black outline, a tiny snow patch only along the upper rim, one short rope fastening at top side. A wide EMPTY dark face is reserved for the engine numeral. Sparse small angular runic notches on the SIDE BEVEL only, never inside numeral safe area. Hero color appears as one broad inset stripe just inside the side/bottom bevel: orange #F28C52 / green #73D973 / violet #B380FF. Stone slab must look angular and heavy, with flat matte material; no round medallion, no fire and no central glowing rune. Inactive: the accent stripe is dull gray and stone cooler/darker, number remains ivory. Keep snow and chips coarse enough to survive 38px. Enlarged card corner example uses digit 2.
```

</details>

<details>
<summary>Concept C — 최초 생성</summary>

```text
Use case: ui-mockup. Create a polished landscape 1536x1024 game UI art direction concept board for a winter forest expedition card game's action-cost badge. Input image 1 is the supplied stone_wall card: use it as the card-frame compositing/style reference; input image 2 is the actual game screenshot: use it for scale, overlapping hand layout and purple snowy battlefield context. This is a concept presentation, not a final asset sheet. Match the card's hand-painted illustration, bold nearly black organic outlines, amber wooden beams, warm cream parchment, purple outer border, snow on pine sprigs, orange berries, rope and lantern warmth. Do not use generic modern flat UI, shiny sci-fi metal, photorealism or unrelated motifs.
Lay out a beautiful coherent design review board with restrained plum background, cream section titles, ample margins and clear aligned panels. Header identifies the concept letter and name. Upper left: one large crop of the supplied card's UPPER LEFT corner, showing the new badge straddling that corner, slightly protruding outside its frame. Keep the cream title panel largely clear. Upper right: a study of the badge silhouette and a genuinely EMPTY central face (no number, no rune pretending to be a number), alongside a labeled 0 1 2 3 4 number overlay test. Numerals must be bold warm ivory with very dark outlines, immediately legible, all five exactly.
Middle: four separate enlarged versions of precisely the same badge silhouette labeled WARRIOR, ARCHER, MAGE, INACTIVE. Warrior accent #F28C52, archer #73D973, mage #B380FF. Each carries example digit 2. Inactive is dark, desaturated, no emission, but numeral 2 remains readable. Do not obscure the digit with decoration.
Bottom: a compact mini hand over a strip of purple snowy battlefield resembling reference image 2. Show THREE small complete cards with wooden/cream/purple snowy frames, EACH approximately 110 screen pixels wide on the 1536px board; badges 34-40px across. Show example costs 1,2,3. Label HAND SCALE / CARD 110 PX / BADGE 38 PX. Small badges should be visibly small, not enlarged thumbnails. Include isolated blank badge study labeled EMPTY ART and separated dark-face / hero-accent / numeral layer miniatures if space permits. All text English, short correct labels only; no paragraph text, no Korean lettering required. Maintain reference illustration style everywhere, simple near-flat dark central numeral face for contrast, peripheral texture only. No watermark.
CONCEPT C — WOODLAND GEM SEAL. A compact ROUND hand-carved warm cedar medallion with a single faceted gemstone inset as its broad central face. Chunky organic black outline, amber endgrain wooden outer ring matching the frame beams, tiny rope lashing on lower left, one restrained snowy lip on upper right. Gem has a wide dark low-detail flat center reserved for numeral, with bright faceted HERO COLOR around its perimeter: orange #F28C52 / green #73D973 / violet #B380FF. No metallic filigree, no dangling ribbons. Keep the wood ring identical across all heroes. Inactive: stone-like smoky gray gem, dim facets, unchanged readable cream numeral. At 38px this reads as wood-ring gem, unlike lantern or stone slab. Enlarged card corner example uses digit 3.
```

</details>

<details>
<summary>A/B/C 공통 — 손패 크기 수정</summary>

```text
Use case: precise-object-edit. Edit this supplied 1536x1024 cost badge concept board with a single targeted correction: the bottom HAND SCALE panel currently exaggerates the cards, so correct its actual on-board pixel size. Preserve ALL other pixels, title, badge design, colors, layout, large card corner, number studies, hero variants and layer study exactly.
Inside the lower left hand-scale panel ONLY: preserve its snowy purple battlefield background but shrink the three-card hand so that each full card frame is approximately 110 pixels wide and 165 pixels tall in this 1536x1024 output, with a badge approximately 38 pixels across including outer silhouette. Center the small three-card hand group inside the panel, with a combined width approximately 330 pixels, leaving generous visible snowy background on both sides. The entire cards INCLUDING their bottom cream text panels must fit inside the panel without cropping. Place each badge over the upper-left card corner without covering most of the cream title band. Show costs 1, 2, 3 in cream with dark outline over warrior orange, archer green, mage violet accents respectively, matching the concept. Keep the top of this bottom panel clear for its existing label. Preserve the panel heading and CARD 110 PX / BADGE 38 PX labels where already present. The cards must look VERY SMALL relative to the enlarged studies above them, no zooming, no giant foreground hand. Do not add any new decorative elements. Correct scale is the ONLY change. Output the same 1536x1024 board.
```

</details>

