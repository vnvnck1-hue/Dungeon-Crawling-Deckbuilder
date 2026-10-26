extends RefCounted
## 달빛 마법 UI 배치 기준(docs/ui-moon-runes-functional-spec.md §3).
## 좌표는 1600×800 디자인 캔버스 px. 실제 화면은 s = min(W/1600, H/800)로 균등 스케일하고,
## 각 그룹은 자기 앵커(좌/중/우 · 상/하) 기준으로 붙는다. 1920×1080이면 남는 높이에 월드가 보인다.

const DESIGN := Vector2(1600, 800)

## 중앙 플레이 영역. 여기에 상시 패널을 두지 않는다.
const CENTER_CLEAR := Rect2(350, 225, 900, 395)

## id -> 슬롯(디자인 px), 앵커(가로 0/0.5/1, 세로 0/1), 원본 아틀라스 영역(px)
const SLOTS := {
	"player_status": {"slot": Rect2(18, 16, 312, 108), "anchor": Vector2(0, 0), "atlas": Rect2(6, 6, 577, 195)},
	"objective": {"slot": Rect2(22, 132, 238, 89), "anchor": Vector2(0, 0), "atlas": Rect2(5, 197, 398, 148)},
	"phase": {"slot": Rect2(640, 16, 320, 100), "anchor": Vector2(0.5, 0), "atlas": Rect2(625, 7, 526, 175)},
	"resources": {"slot": Rect2(1140, 25, 350, 85), "anchor": Vector2(1, 0), "atlas": Rect2(1197, 29, 468, 143)},
	"pause": {"slot": Rect2(1510, 30, 64, 72), "anchor": Vector2(1, 0), "atlas": Rect2(1668, 34, 105, 116)},
	"hand": {"slot": Rect2(540, 622, 520, 176), "anchor": Vector2(0.5, 1), "atlas": Rect2(460, 539, 856, 340)},
	"storage": {"slot": Rect2(24, 681, 106, 109), "anchor": Vector2(0, 1), "atlas": Rect2(3, 694, 195, 185)},
	"actions": {"slot": Rect2(1310, 687, 265, 107), "anchor": Vector2(1, 1), "atlas": Rect2(1315, 696, 458, 183)},
}

const ORDER := ["player_status", "objective", "phase", "resources", "pause", "hand", "storage", "actions"]


static func ui_scale(view: Vector2) -> float:
	return minf(view.x / DESIGN.x, view.y / DESIGN.y)


## 디자인 좌표 한 점을 화면 좌표로. anchor는 그 점이 붙는 화면 기준(0=왼/위, 0.5=가운데, 1=오른/아래).
static func to_view(p: Vector2, anchor: Vector2, view: Vector2) -> Vector2:
	var s := ui_scale(view)
	return Vector2(view.x * anchor.x + (p.x - DESIGN.x * anchor.x) * s,
		view.y * anchor.y + (p.y - DESIGN.y * anchor.y) * s)


static func slot_rect(id: String, view: Vector2) -> Rect2:
	var d: Dictionary = SLOTS[id]
	var r: Rect2 = d["slot"]
	return Rect2(to_view(r.position, d["anchor"], view), r.size * ui_scale(view))


## KEEP_ASPECT_CENTERED와 같은 맞춤: 아틀라스 영역 크기 원본을 슬롯 안에 비율 유지·가운데 배치.
## 반환: [위치, 배율]. 이 배율로 그룹 내부를 원본 아틀라스 px 좌표 그대로 작성한다.
static func fit(id: String, view: Vector2) -> Array:
	var d: Dictionary = SLOTS[id]
	var slot := slot_rect(id, view)
	var src: Vector2 = (d["atlas"] as Rect2).size
	var k := minf(slot.size.x / src.x, slot.size.y / src.y)
	var drawn := src * k
	return [slot.position + (slot.size - drawn) * 0.5, k]
