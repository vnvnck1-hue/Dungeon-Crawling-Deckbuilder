extends Control
## 머리 위 상태 칩 하나(표시 전용): 상태 색의 둥근 판 + 상태 그림 + 쌓인 수. hud.gd 가 유닛마다 줄지어 놓는다.
## 그림은 assets/ui/status/status_<id>.png 가 있으면 그것을, 없으면 여기서 벡터로 그린다(Codex 아이콘 요청: docs/art-requests/status-icons.md).
## 냉기는 빙결까지 남은 칸(CHILL_FREEZE)을 아래 눈금으로, 값이 오르면 튕기듯 커졌다 돌아온다.

const CardFace := preload("res://scripts/ui/card_face.gd")
const D := preload("res://dungeon/data/defs.gd")

const SIZE := 34.0
const INFO := {
	"mark": {"color": Color(1.0, 0.27, 0.22), "name": "표식"},
	"burn": {"color": Color(1.0, 0.55, 0.12), "name": "화상"},
	"chill": {"color": Color(0.55, 0.85, 1.0), "name": "냉기"},
	"freeze": {"color": Color(0.7, 0.95, 1.0), "name": "빙결"},
	"fury": {"color": Color(1.0, 0.25, 0.18), "name": "투지"},
	"taunt": {"color": Color(1.0, 0.62, 0.2), "name": "도발"},
}

var status := ""
var value := 0
var _tex: Texture2D
var _num: Label
var _pop := 0.0


func setup(status_: String) -> void:
	status = status_
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	pivot_offset = size * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var path := "res://assets/ui/status/status_%s.png" % status
	if ResourceLoader.exists(path):
		_tex = load(path)
	_num = Label.new()
	_num.add_theme_font_override("font", CardFace.font())
	_num.add_theme_font_size_override("font_size", 19)
	_num.add_theme_color_override("font_color", Color(1, 1, 1))
	_num.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.1))
	_num.add_theme_constant_override("outline_size", 6)
	_num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_num.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_num.position = Vector2(SIZE * 0.2, SIZE * 0.36)
	_num.size = Vector2(SIZE * 0.95, SIZE * 0.8)
	_num.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_num)


func set_value(v: int) -> void:
	if v > value:
		_pop = 1.0
	value = v
	_num.text = "" if status in ["freeze", "taunt"] else str(v)
	queue_redraw()


func _process(delta: float) -> void:
	if _pop > 0.0:
		_pop = move_toward(_pop, 0.0, delta * 2.6)
		scale = Vector2.ONE * (1.0 + 0.55 * _pop * _pop)
		queue_redraw()
	elif status in ["burn", "freeze"]:
		queue_redraw()


func _draw() -> void:
	var col: Color = INFO[status].color
	var c := size * 0.5
	var r := SIZE * 0.5
	var t := Time.get_ticks_msec() * 0.001
	# 판: 짙은 바탕 + 상태 색 테두리(막 오르면 하얗게)
	draw_circle(c, r, Color(0.07, 0.04, 0.12, 0.92))
	draw_circle(c, r - 3.0, col.darkened(0.55))
	draw_arc(c, r - 1.5, 0, TAU, 32, col.lerp(Color.WHITE, _pop), 3.0, true)
	if _tex != null:
		draw_texture_rect(_tex, Rect2(Vector2(3, 3), size - Vector2(6, 6)), false)
	else:
		_glyph(c, r * 0.62, col, t)
	# 냉기: 빙결까지 칸(아래 눈금)
	if status == "chill":
		var n := D.CHILL_FREEZE
		for i in n:
			var x := c.x + (i - (n - 1) * 0.5) * 11.0
			draw_rect(Rect2(x - 5.5, SIZE - 1.0, 10.0, 6.0), Color(0.06, 0.03, 0.1, 0.95))
			draw_rect(Rect2(x - 4.5, SIZE, 8.0, 4.0), col.lightened(0.3) if i < value else Color(0.18, 0.24, 0.36))


func _glyph(c: Vector2, s: float, col: Color, t: float) -> void:
	var light := col.lightened(0.45)
	match status:
		"mark":
			# 조준경: 원 + 네 갈래 + 가운데 점
			draw_arc(c, s * 0.75, 0, TAU, 28, light, 2.5, true)
			for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
				draw_line(c + d * s * 0.45, c + d * s * 1.05, light, 2.5, true)
			draw_circle(c, s * 0.18, light)
		"burn":
			# 불꽃: 바깥 주황 + 안쪽 노랑, 살짝 일렁인다
			var sway := sin(t * 9.0) * s * 0.08
			var outer := PackedVector2Array([c + Vector2(0, s * 0.95), c + Vector2(-s * 0.7, s * 0.3), c + Vector2(-s * 0.45, -s * 0.35),
				c + Vector2(-s * 0.1, -s * 0.1), c + Vector2(sway, -s * 1.05), c + Vector2(s * 0.45, -s * 0.3), c + Vector2(s * 0.7, s * 0.3)])
			draw_colored_polygon(outer, Color(1.0, 0.45, 0.1))
			var inner := PackedVector2Array([c + Vector2(0, s * 0.85), c + Vector2(-s * 0.35, s * 0.35), c + Vector2(sway * 0.6, -s * 0.45), c + Vector2(s * 0.35, s * 0.35)])
			draw_colored_polygon(inner, Color(1.0, 0.88, 0.35))
		"chill":
			# 눈송이: 세 줄 + 가지
			for k in 3:
				var a := k * PI / 3.0
				var d := Vector2(cos(a), sin(a))
				draw_line(c - d * s, c + d * s, light, 2.4, true)
				for sgn in [-1.0, 1.0]:
					var p: Vector2 = c + d * s * 0.6 * sgn
					var b1: Vector2 = d.rotated(PI * 0.75) * s * 0.28 * sgn
					var b2: Vector2 = d.rotated(-PI * 0.75) * s * 0.28 * sgn
					draw_line(p, p + b1, light, 2.0, true)
					draw_line(p, p + b2, light, 2.0, true)
		"freeze":
			# 얼음 결정: 육각 판 + 빛나는 테두리
			var pts := PackedVector2Array()
			for k in 6:
				var a := k * TAU / 6.0 + PI / 6.0
				pts.append(c + Vector2(cos(a), sin(a)) * s)
			draw_colored_polygon(pts, Color(0.75, 0.93, 1.0, 0.85))
			pts.append(pts[0])
			draw_polyline(pts, Color(1, 1, 1, 0.9 + 0.1 * sin(t * 5.0)), 2.0, true)
			draw_line(c + Vector2(-s * 0.4, -s * 0.2), c + Vector2(s * 0.1, s * 0.35), Color(1, 1, 1, 0.8), 2.0, true)
		"fury":
			# 투지: 세 줄 발톱 자국
			for k in 3:
				var o := Vector2((k - 1) * s * 0.5, 0)
				draw_line(c + o + Vector2(-s * 0.35, s * 0.8), c + o + Vector2(s * 0.35, -s * 0.8), light, 3.0, true)
		"taunt":
			# 방패
			var sh := PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.8), c + Vector2(s * 0.8, -s * 0.8), c + Vector2(s * 0.7, s * 0.2), c + Vector2(0, s * 0.95), c + Vector2(-s * 0.7, s * 0.2)])
			draw_colored_polygon(sh, light)
