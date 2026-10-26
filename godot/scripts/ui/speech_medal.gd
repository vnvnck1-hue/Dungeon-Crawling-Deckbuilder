extends Control
## 말 걸기 알림의 초상 메달(사용자 선택 시안 03, 2026-10-22).
## 승인 틀 그림 medal_frame.png(리벳 박힌 나무·놋쇠 둥근 틀) 안에 손님 컷아웃 초상을 크게 넣는다.
## 시안처럼 **아래쪽(가슴·어깨)은 틀 안쪽 원으로 깔끔하게 자르고, 위쪽(머리·모자·무기)은 틀 밖으로 살짝 넘친다**:
## 초상을 두 조각으로 그린다 — 가름선 아래는 원으로 잘라 틀 밑에, 가름선 위는 자르지 않고 틀 위에.
## 테두리 게이지(남은 시간 호)는 사용자 요청으로 뺐다(2026-10-22). ratio 는 툴팁·검증용 값으로만 남는다.
## 게임 상태를 갖지 않는다. 입력도 받지 않는다(클릭은 부모 알림 버튼이 받는다).

const Extension := preload("res://scripts/ui/moon/moon_extension.gd")

const SEGMENTS := 64
const RIM := 15.0                   # 초상 가장자리에서 바깥 테까지 = 틀 띠 두께(그림 512px 기준 54px/492px)
const FRAME_FILL := 0.96            # 틀 그림에서 바깥 지름이 차지하는 비율(한 변 대비)
## 인물 배치는 컷아웃마다 재는 '머리'를 기준으로 한다(치켜든 무기 같은 가는 돌출부는 머리로 치지 않는다):
## 머리 꼭대기 = 위에서 내려오며 불투명 가로 폭이 처음 전체 폭의 HEAD_MIN 을 넘는 줄, 머리 폭 = 그 아래 HEAD_BAND 구간의 최대 폭.
const HEAD_MIN := 0.30
const HEAD_BAND := 0.22
const ZOOM := 1.10                  # 인물 크기: 머리 폭(귀·모자 포함)이 원 지름의 몇 배가 되나
const EYE_Y := 0.17                 # 머리 꼭대기에서 눈높이까지 = 불투명 높이의 이 비율
const EYE_AT := -0.38               # 눈높이를 원 중심보다 이만큼(반지름 배) 위에 둔다
const SPLIT_AT := -0.55             # 가름선 높이(원 중심 기준, 반지름 배). 이 위는 틀 밖으로 넘친다
## 메달 전용 컷아웃(*_medal.png, 시안 인물 그대로 그린 것)은 머리 측정 없이 규격대로 놓는다:
## 불투명 상자를 가로 중심에, 꼭대기(칼끝)는 틀 바깥 테 위 MEDAL_TOP_OVER 위에, 높이는 원 지름의 MEDAL_FIT 배.
const MEDAL_FIT := 1.38
const MEDAL_TOP_OVER := 3.0
const OVERFLOW_W := 40.0            # 가름선 위 조각이 바깥 테보다 좌우로 더 보이는 폭(치켜든 무기 끝)
const C_BACK := Color8(40, 24, 56)  # 초상 뒤 바탕
const C_FRAME := Color(0.86, 0.69, 0.4)       # 틀 그림이 없을 때의 대체 고리 색
const C_RIM := Color8(58, 34, 64)

var radius := 58.0                  # 초상 원 반지름. 바깥 테 반지름 = radius + RIM = 70 (시안 픽셀 실측 틀 지름 153/1.109 = 138)
var ratio := 1.0:                   # 남은 시간 비율 1 → 0 (그리지 않음, 값만 유지)
	set(v):
		ratio = clampf(v, 0.0, 1.0)
var show_arc := false               # 호를 그리지 않으므로 항상 false(옛 검증 호환용 필드)
var portrait_path := ""
var dedicated := false              # *_medal.png — 메달 전용 규격 컷아웃
var _tex: Texture2D
var _bbox := Rect2()                # 컷아웃 불투명 영역(텍스처 px)
var _face_x := 0.0                  # 머리 가로 중심(텍스처 px)
var _head_top := 0.0                # 머리 꼭대기(텍스처 px)
var _head_w := 1.0                  # 머리 폭(텍스처 px)
var _circle := PackedVector2Array()
var _frame: Texture2D = Extension.tex("medal_frame")


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in SEGMENTS:
		var t := TAU * i / SEGMENTS
		_circle.append(Vector2(cos(t), sin(t)))


func outer_radius() -> float:
	return radius + RIM


func has_frame() -> bool:
	return _frame != null


## 컷아웃 초상을 바꾼다. 같은 그림이면 아무것도 하지 않는다.
func set_portrait(path: String) -> void:
	if path == portrait_path:
		return
	portrait_path = path
	dedicated = path.ends_with("_medal.png")
	_tex = load(path) as Texture2D if ResourceLoader.exists(path) else null
	if _tex != null:
		var m := measure(_tex)
		_bbox = m["bbox"]
		_face_x = m["face_x"]
		_head_top = m["head_top"]
		_head_w = m["head_w"]
	queue_redraw()


## 컷아웃(투명 배경 상반신)의 불투명 영역, 머리 꼭대기·폭·가로 중심을 잰다(텍스처 px).
static func measure(tex: Texture2D) -> Dictionary:
	var img := tex.get_image()
	var w := tex.get_width()
	var h := tex.get_height()
	var fallback := {"bbox": Rect2(w * 0.15, 0, w * 0.7, h * 0.9), "face_x": w * 0.5, "head_top": h * 0.05, "head_w": w * 0.5}
	if img == null:
		return fallback
	if img.is_compressed():
		img.decompress()
	var step := maxi(1, w / 128)
	var rows: Array = []   # [y, 왼끝, 오른끝] 불투명 줄만
	var top := h
	var bottom := 0
	var left := w
	var right := 0
	for y in range(0, h, step):
		var l := -1
		var r := -1
		for x in range(0, w, step):
			if img.get_pixel(x, y).a > 0.5:
				if l < 0: l = x
				r = x
		if l >= 0:
			rows.append([y, l, r])
			top = mini(top, y)
			bottom = maxi(bottom, y)
			left = mini(left, l)
			right = maxi(right, r)
	if top >= bottom:
		return fallback
	var bh := float(bottom - top)
	var full_w := float(right - left)
	# 머리 꼭대기: 가로 폭이 처음 전체 폭의 HEAD_MIN 을 넘는 줄(치켜든 칼끝 같은 가는 돌출은 건너뛴다)
	var head_top := float(top)
	for row in rows:
		if float(row[2] - row[1]) >= full_w * HEAD_MIN:
			head_top = float(row[0])
			break
	var head_w := 1.0
	var sx := 0.0
	var sn := 0.0
	for row in rows:
		if row[0] >= head_top and row[0] <= head_top + bh * HEAD_BAND:
			head_w = maxf(head_w, float(row[2] - row[1]))
			sx += (row[1] + row[2]) * 0.5
			sn += 1.0
	return {"bbox": Rect2(left, top, right - left, bh), "face_x": sx / sn if sn > 0.0 else w * 0.5,
		"head_top": head_top, "head_w": head_w}


## 초상 텍스처 1px 이 화면 몇 px 인가.
func portrait_scale() -> float:
	if dedicated:
		return radius * 2.0 * MEDAL_FIT / maxf(_bbox.size.y, 1.0)
	return radius * 2.0 * ZOOM / maxf(_head_w, 1.0)


## 텍스처 좌표계의 원점(텍스처 (0,0)이 놓이는 로컬 좌표).
func portrait_origin() -> Vector2:
	var c := size * 0.5
	var s := portrait_scale()
	if dedicated:
		return Vector2(c.x - _bbox.get_center().x * s, c.y - outer_radius() - MEDAL_TOP_OVER - _bbox.position.y * s)
	var eye_y := _head_top + _bbox.size.y * EYE_Y
	return Vector2(c.x - _face_x * s, c.y + radius * EYE_AT - eye_y * s)


## 초상의 위쪽 끝(틀 밖으로 넘치는 머리 끝)이 로컬 좌표 어디에 오나(검증·배치용).
func portrait_top() -> float:
	return portrait_origin().y + _bbox.position.y * portrait_scale()


func _uv_of(p: Vector2, origin: Vector2, s: float) -> Vector2:
	return Vector2((p.x - origin.x) / (s * _tex.get_width()), (p.y - origin.y) / (s * _tex.get_height()))


func _draw_portrait_piece(pts: PackedVector2Array) -> void:
	var origin := portrait_origin()
	var s := portrait_scale()
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(_uv_of(p, origin, s))
	draw_colored_polygon(pts, Color.WHITE, uvs, _tex)


func _draw() -> void:
	var c := size * 0.5
	var outer := radius + RIM
	var inner := radius + (2.0 if _frame != null else -0.5)   # 틀 띠 안쪽 선 밑으로 조금 들어가게
	if _frame == null:
		draw_circle(c, outer, C_RIM)
	draw_circle(c, inner, C_BACK)
	var split_y := c.y + radius * SPLIT_AT
	if _tex != null:
		# 1) 가름선 아래: 원으로 자른 조각(틀 밑). 가름선에서 원과 만나는 각도부터 아래 반원을 돈다.
		var a0 := asin(clampf((split_y - c.y) / inner, -1.0, 1.0))   # 오른쪽 교점 각(아래가 +)
		var lower := PackedVector2Array()
		var steps := 40
		for i in steps + 1:
			var t := a0 + (PI - 2.0 * a0) * float(i) / steps
			lower.append(c + Vector2(cos(t), sin(t)) * inner)
		_draw_portrait_piece(lower)
	if _frame != null:
		var side := outer * 2.0 / FRAME_FILL
		draw_texture_rect(_frame, Rect2(c - Vector2.ONE * side * 0.5, Vector2.ONE * side), false)
	else:
		draw_arc(c, radius, 0, TAU, SEGMENTS, C_FRAME, 2.0, true)
		draw_arc(c, outer, 0, TAU, SEGMENTS, C_RIM, 2.5, true)
	if _tex != null:
		# 2) 가름선 위: 자르지 않은 조각(틀 위). 좌우는 바깥 테 폭까지, 위는 머리 끝까지.
		var half_w := outer + OVERFLOW_W
		var top_y := minf(portrait_top() - 4.0, split_y - 1.0)
		var upper := PackedVector2Array([
			Vector2(c.x - half_w, split_y), Vector2(c.x - half_w, top_y),
			Vector2(c.x + half_w, top_y), Vector2(c.x + half_w, split_y)])
		_draw_portrait_piece(upper)
