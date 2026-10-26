extends Control
## 기다림 게이지: 고용 제안·대화 알림처럼 손님이 떠나기까지 남은 시간을 얇은 막대로 보여 준다.
## ratio 1 → 0 으로 줄고, 넉넉할 땐 촛불빛 금색, 반 아래로 내려가면 주황, 1/4 아래면 붉게 깜박인다.
## 글자 없이도 한눈에 알 수 있게 하는 보조 표시라 마우스 입력은 받지 않는다.

const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")

const C_FULL := Color8(240, 200, 116)
const C_HALF := Color8(232, 146, 72)
const C_LOW := Color8(222, 86, 74)
const C_TRACK := Color(0.06, 0.04, 0.12, 0.72)

var ratio := 1.0:
	set(v):
		v = clampf(v, 0.0, 1.0)
		if not is_equal_approx(v, ratio):
			ratio = v
			queue_redraw()
var _clock := 0.0
var _track: StyleBoxFlat   # 그릴 때마다 새로 만들지 않고 색·둥글기만 바꾼다
var _fill: StyleBoxFlat
var _radius := -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 6)


func fill_color() -> Color:
	if ratio > 0.5:
		return C_HALF.lerp(C_FULL, (ratio - 0.5) / 0.5)
	if ratio > 0.25:
		return C_LOW.lerp(C_HALF, (ratio - 0.25) / 0.25)
	return C_LOW


## 1/4 아래에서 깜박이는 중인가(검증용).
func urgent() -> bool:
	return ratio <= 0.25 and ratio > 0.0


func _process(delta: float) -> void:
	if urgent():
		_clock += delta
		queue_redraw()


func _draw() -> void:
	var r := int(ceil(size.y * 0.5))
	if _track == null:
		_track = StyleBoxFlat.new()
		_track.bg_color = C_TRACK
		_track.border_color = Color(MoonSkin.CREAM, 0.35)
		_track.set_border_width_all(1)
		_fill = StyleBoxFlat.new()
	if r != _radius:
		_radius = r
		_track.set_corner_radius_all(r)
		_fill.set_corner_radius_all(r)
	draw_style_box(_track, Rect2(Vector2.ZERO, size))
	if ratio <= 0.0:
		return
	var col := fill_color()
	if urgent():
		col.a = 0.55 + 0.45 * (0.5 + 0.5 * sin(_clock * 9.0))
	_fill.bg_color = col
	var w := maxf(size.x * ratio, size.y)  # 너무 짧아도 둥근 끝이 보이게
	draw_style_box(_fill, Rect2(Vector2.ZERO, Vector2(w, size.y)))
