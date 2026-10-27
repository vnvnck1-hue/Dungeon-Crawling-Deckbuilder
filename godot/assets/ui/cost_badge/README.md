# 행동력 배지 — C안 Woodland Gem Seal

확정 시안: `art/concepts/cost-badge/concept-c.png`  
카드 스타일: `godot/assets/cards/stone_wall.png`  
제작 기준: `docs/art-requests/cost-badge-final-c.md`

## 파일과 합성 순서

모든 PNG는 **256×256, 8비트 RGBA, 투명 배경**이다. 실사용 세 레이어는 이동·개별 크롭 없이 같은 사각형에 그대로 겹친다. 원 중심은 **(128, 128)**, UV 중심은 **(0.5, 0.5)**이다. 픽셀 좌표 계산에서는 픽셀 중심 `(x + 0.5, y + 0.5)`를 사용했다.

| 순서 | 파일 | 내용 |
| --- | --- | --- |
| 1 | `badge_face.png` | 짙은 남보라·숯색 숫자 받침. 거의 단색이며 가장자리만 은은하게 어둡다. |
| 2 | `badge_gem.png` | 중앙이 투명한 보석 링. RGB의 R=G=B인 완전한 회색조 패싯. 이 레이어에만 영웅색을 적용한다. |
| 3 | `badge_frame.png` | 검정 외곽선, 따뜻한 나무 고리, 얇은 윗눈, 왼쪽 아래의 작은 밧줄, 왼쪽 위 솔가지와 열매. 중앙은 투명하다. |
| 확인용 | `badge_preview.png` | face → 보라색 gem → frame → 크림색 숫자 2. 왼쪽 192px 축소 합성본과 오른쪽 **34px** 축소본을 같은 256×256 투명 캔버스에 배치했다. 엔진 텍스처로 사용하지 않는다. |

실사용 세 레이어에는 숫자와 글자가 없다. 숫자는 엔진 Label로 별도 표시한다. 비활성 전용 이미지는 없다.

## 반경 — 256px 캔버스 기준

| 영역 | 제작 반경(px) | UV 반경(반경 ÷ 256) |
| --- | --- | --- |
| 나무 본체 기준 원 | **112** | 0.4375 |
| 전체 실루엣 최대 — 알파가 1 이상인 픽셀 중심 실측 | **125.11 이하** | 0.48871 이하 |
| face 바깥 | **63** | 0.24609375 |
| gem 안쪽 | **61** | **0.23828125** |
| gem 바깥 | **84** | **0.328125** |
| frame 기본 중앙 구멍 | **82** | 0.3203125 |

- 장식 돌출은 본체 기준 원에서 최대 **13.11px**, 캔버스 폭의 약 **5.12%**로, 요청한 6%(15.36px) 이내다. 오른쪽으로 뻗는 솔가지나 열매는 없다.
- face와 gem은 **r=61~63**, gem과 frame은 **r=82~84**에서 겹친다. 밧줄이 놓이는 왼쪽 아래에서는 frame의 일부가 약 r=71.73까지 들어온다. 보석 링과 face의 중심은 변하지 않는다.
- 위 표의 제작 반경은 원 경계다. 안티앨리어싱 때문에 알파가 조금 남는 픽셀은 경계에서 약 1px까지 생길 수 있다. gem의 실측 알파 범위는 **r=60.37~84.62**, 알파 128 이상인 바깥 반경은 **84.04px** 이하다.
- 셰이더의 링 기준에는 **안쪽 61px / 바깥 84px**를 사용하고, 텍스처 알파를 보존한다. 프레임 전체 실루엣 반경을 보석 링 반경으로 사용하지 않는다.

## 색과 확인 결과

미리보기의 gem은 회색조 원본 RGB에 마법사색 **#B380FF**를 채널별 곱셈으로 적용했다. 엔진에서 사용할 영웅색은 전사 **#F28C52**, 궁수 **#73D973**, 마법사 **#B380FF**다. 나무·눈·열매와 숫자 받침은 보석 착색에서 제외한다.

4배 해상도에서 중심 정렬·원형 마스킹·레이어 분리 후 알파를 고려해 축소했다. 보석 아래에 남는 밧줄 무늬를 제거했고, 완전 투명 픽셀의 RGB는 0으로 정리했다. 체커보드와 어두운 배경에서 경계를 확인했다.

검증: PNG 네 장의 크기·RGBA·투명 배경, gem의 모든 픽셀에서 R=G=B, 원 중심 정렬, 반경 108px 안의 합성 알파에 구멍 없음, 34/38/40px 축소 가독성, 원본 카드 폭 110px에서 제목 옆 배치. Godot 코드·씬·셰이더 303개 파일은 작업 전후 SHA-256이 같다. 엔진 적용은 포함하지 않는다.

## 제작 출처와 최종 생성 프롬프트

내장 `image_gen`으로 참조 원화를 생성한 뒤 .NET System.Drawing으로 레이어 분리, 정확한 회색조 변환, 원형 정렬, 알파 정리, 미리보기 합성을 수행했다. 아래 프롬프트는 원화 생성에 사용한 원문이다. 최종 반경은 위 표의 후처리 결과를 따른다.

```text
Use case: precise-object-edit. Create one production game UI sprite from the first reference, Concept C Woodland Gem Seal medal. Reference 2 is style reference only. Output a single large centered front-facing, perfectly circular medal on a genuinely transparent square canvas, preferably 1024x1024. NO text, numbers, labels, sheet, background, cast shadow or extra specimens. Preserve Concept C's hand-painted chunky black outlines, warm segmented golden orange wooden hoop, black bevel seams, tiny rope knot at lower left, narrow white blue-tinted snow cap resting tightly on the top arc, a tiny tucked sprig of dark green pine and 2 orange berries only on upper LEFT. Compress decorations into circular silhouette: the main circular body occupies 84% canvas width, centered at exact canvas center, tiny ornament protrusions at most 4% canvas width beyond it; no branches on right, no dangling tassels. Rightmost outline must be clean circular wood. Radial construction: outer black wooden hoop radius 42% of canvas, inner edge wood radius 33%; inside it a thick faceted GEM ANNULUS extending from radius 23% to radius 33%; the central face inside radius 23% is nearly uniform deep charcoal-indigo, very subtle inset shadow and NO facets inside this face. Gem ring MUST BE NEUTRAL GRAYSCALE, with angular triangular polygon facets in MID GRAY through near-white, no purple tint, no gold, no color on gem, no dark central gemstone filling. Frame and snow remain colored naturally. Uniform concentric circular boundaries, orthographic without perspective or ellipse. Crisp rich hand-painted polished fantasy card art matching reference C and the winter wooden card. This is source art to be precisely separated into registered center, gem annulus, wooden frame with transparent holes. Make the gem and wood separation strictly circular, with no snow, rope or sprigs overlapping the gemstone ring. Clean generous transparent margins. Numeral area must be large and calm. Thick black silhouette. Avoid extremely fine texture that disappears at 34 pixels.
```
