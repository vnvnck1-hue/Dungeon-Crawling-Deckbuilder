extends CanvasLayer
## 새끼양 말풍선: 마녀가 새끼양 가까이 가면 그 새끼양 머리 위에 작은 말풍선으로 어른이 되기까지 남은 날을 알려 준다.
## 멀어지면 사라진다. 표시 전용이며 성장 판정은 pasture.grow_lambs()가 한다.

const SkinUI := preload("res://scripts/ui/moon/moon_skin.gd")
const Extension := preload("res://scripts/ui/moon/moon_extension.gd")

const RANGE := 2.4          # 마녀와 새끼양 사이 거리(m)
const FADE := 0.18

var game
var bubble: PanelContainer
var text: Label
var _target = null
var _alpha := 0.0


func _ready() -> void:
	name = "LambBubble"
	layer = 6
	bubble = Bubble.new()
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_theme_stylebox_override("panel", Extension.speech())
	bubble.modulate.a = 0.0
	add_child(bubble)
	text = Label.new()
	text.add_theme_font_override("font", SkinUI.font(true))
	text.add_theme_font_size_override("font_size", 15)
	text.add_theme_color_override("font_color", SkinUI.PAPER_INK)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.add_child(text)


func _process(delta: float) -> void:
	var near = _nearest_lamb()
	if near != null:
		_target = near
	var want := 1.0 if near != null else 0.0
	_alpha = move_toward(_alpha, want, delta / FADE)
	bubble.modulate.a = _alpha
	if _alpha <= 0.0 or _target == null or not is_instance_valid(_target) or _target.dead:
		bubble.visible = false
		return
	bubble.visible = true
	var left: int = _target.days_to_grow(game.session.day())
	text.text = "음매~ 내일이면 다 자라요" if left <= 1 else "음매~ %d일 뒤면 다 자라요" % left
	bubble.reset_size()
	var cam: Camera3D = game.world.camera
	var head: Vector3 = _target.global_position + Vector3(0, _target.hp_offset + 0.35, 0)
	if cam.is_position_behind(head):
		bubble.visible = false
		return
	# 꼬리 끝이 머리 위를 가리키도록 말풍선의 왼쪽 아래를 맞춘다.
	bubble.position = cam.unproject_position(head) - Vector2(10, bubble.size.y + 12)


func _nearest_lamb():
	if game.player == null or game.player.dead:
		return null
	var best = null
	var best_d := RANGE
	for s in game.world.pasture.slots:
		if not is_instance_valid(s) or s.dead or not s.is_lamb:
			continue
		var d: float = s.global_position.distance_to(game.player.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


class Bubble extends PanelContainer:
	func _draw() -> void:
		pass # The tail is included in the artwork.
