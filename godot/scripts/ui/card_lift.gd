extends Node
## 카드 고르기 화면(선택·새벽 보상·장날·시작 손패·보물상자·마법서)의 카드 버튼에 마우스를 올리면
## 손패처럼 살짝 들어 올린다: 위로 솟고 조금 커지며 마우스가 있는 쪽으로 살짝 기운다.
## - 버튼의 쉬는 자리(base)는 들려 있지 않을 때마다 버튼 위치를 따라가므로, 날아오는 연출 트윈과 다투지 않는다.
## - 들린 동안에도 쉬는 자리(+들린 만큼 위쪽) 안이면 호버를 유지해 카드 아래 가장자리에서 깜빡이지 않고,
##   들려서 비어 버린 아래 띠를 눌러도 그 카드를 누른 것으로 친다.
## - enabled 가 false 를 돌려주면(고른 뒤 연출 중) 즉시 손을 떼고 위치·크기를 건드리지 않는다.
## 사용: CardLift.attach(btn, func(): return _phase == "pick", func(): game.sounds.play("card_hover"))

const LIFT := 18.0        # 솟는 높이(px, 무대 좌표)
const GROW := 0.06        # 커지는 비율
const ROT_DEG := 2.5      # 마우스 쪽으로 기우는 최대 각도
const SPEED := 16.0       # 따라가는 빠르기

var btn: BaseButton
var enabled := Callable()
var on_hover := Callable()
var t := 0.0              # 0 쉼 ~ 1 들림
var rot := 0.0
var hovered := false
var forced := false       # 검증용: 마우스 없이 호버로 친다
var base := Vector2.ZERO
var _owned := false       # 지금 이 노드가 버튼 위치·크기·회전을 쓰고 있는지


static func attach(b: BaseButton, enabled_cb := Callable(), hover_cb := Callable()) -> Node:
	var n: Node = load("res://scripts/ui/card_lift.gd").new()
	n.name = "CardLift"
	n.btn = b
	n.enabled = enabled_cb
	n.on_hover = hover_cb
	n.base = b.position
	b.pivot_offset = b.size * 0.5
	b.add_child(n)
	return n


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## 쉬는 자리 + 들린 만큼 위로 늘린 영역(부모 좌표).
func zone() -> Rect2:
	return Rect2(base - Vector2(0, LIFT), btn.size + Vector2(0, LIFT))


func _mouse() -> Vector2:
	var p := btn.get_parent() as CanvasItem
	return p.get_local_mouse_position() if p != null else Vector2(-INF, -INF)


func _process(delta: float) -> void:
	step(preload("res://scripts/ui/hand_focus_time.gd").ui_delta(delta))   # 손패 고민 시간으로 세상이 늦춰져도 실제 시간으로


func step(delta: float) -> void:
	if not is_instance_valid(btn):
		return
	var on: bool = bool(enabled.call()) if enabled.is_valid() else true
	if not on or not btn.is_visible_in_tree():
		_release()
		base = btn.position
		return
	if not _owned:
		base = btn.position
	var m := _mouse()
	var now := not btn.disabled and (forced or zone().has_point(m))
	if now and not hovered and on_hover.is_valid():
		on_hover.call()
	hovered = now
	var goal := 1.0 if hovered else 0.0
	var k := 1.0 - exp(-delta * SPEED)
	t = lerpf(t, goal, k)
	var goal_rot := 0.0
	if hovered and not forced:
		var lx := (m.x - (base.x + btn.size.x * 0.5)) / btn.size.x
		goal_rot = clampf(lx * 2.0, -1.0, 1.0) * ROT_DEG
	rot = lerpf(rot, goal_rot, k)
	if not hovered and t < 0.004:
		if _owned:
			btn.position = base
			btn.scale = Vector2.ONE
			btn.rotation_degrees = 0.0
			btn.z_index = 0
		_owned = false
		t = 0.0
		rot = 0.0
		return
	_owned = true
	btn.position = base - Vector2(0, LIFT * t)
	btn.scale = Vector2.ONE * (1.0 + GROW * t)
	btn.rotation_degrees = rot * t
	btn.z_index = 1


## 연출에 넘겨줄 때: 지금 모습 그대로 두고 손만 뗀다(트윈이 그 자리에서 이어받는다).
func _release() -> void:
	_owned = false
	hovered = false
	t = 0.0
	rot = 0.0
	btn.z_index = 0


## 들려서 비어 버린 아래 띠(쉬는 자리 안이지만 버튼 밖)를 눌러도 이 카드를 누른 것으로 친다.
func _input(event: InputEvent) -> void:
	if not hovered or not _owned or btn.disabled:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if Rect2(Vector2.ZERO, btn.size).has_point(btn.get_local_mouse_position()):
		return  # 버튼이 직접 받는다
	get_viewport().set_input_as_handled()
	btn.pressed.emit()
