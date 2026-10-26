extends CanvasLayer
## 시작 손패 고르기(멀리건, 기획 §6 시작 구성 — 사용자 결정 2026-10-16): 게임이 시작되면 주머니에서 카드 3장이
## 좌하단 주머니에서 날아와 화면 가운데에 펼쳐진다. 마음에 들지 않는 카드를 하나 골라 표시하면 그 카드는 주머니로
## 돌아가고 다른 카드 한 장을 새로 뽑는다(교체는 1장). 확정하면 세 장이 손패로 내려가 오른쪽부터 쌓인다.
## 열려 있는 동안 게임은 멈춘다(hud.refresh_pause()가 active를 본다). Esc로 닫을 수 없고 반드시 확정한다.

const Cfg := preload("res://scripts/config.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const Catalog := preload("res://scripts/ui/card_catalog.gd")
const FX := preload("res://scripts/ui/card_fx.gd")
const Stage := preload("res://scripts/ui/center_stage.gd")
const CardLift := preload("res://scripts/ui/card_lift.gd")

const CARD := Vector2(230, 345)
const GAP := 44.0

var game
var active := false
var root: Control
var stage: Control          # 화면 가운데 무대 — 카드·제목·버튼은 가운데 기준 좌표(창 비율이 바뀌어도 가운데 유지)
var dim: ColorRect
var title: Label
var hint: Label
var confirm_btn: Button
var fx
var cards: Array = []       # [{node, uid, id, mark, slot}]
var offered: Array = []     # 주머니 entry 3장
var marked := -1            # 교체 표시한 후보 번호
var replaced_uid := -1
var replacement: Dictionary = {}
var _phase := ""            # deal | pick | swap | deliver
var _slots: Array = []      # 각 후보의 화면 위치(왼쪽 위)


func _ready() -> void:
	name = "MulliganScreen"
	layer = 13
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	root.theme = MoonSkin.make_theme()
	add_child(root)
	dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.04, 0.02, 0.09, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	stage = Stage.make(root)
	title = Label.new()
	title.add_theme_font_override("font", MoonSkin.font(true))
	title.add_theme_font_size_override("font_size", 32)
	title.add_theme_color_override("font_color", MoonSkin.CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(title)
	hint = Label.new()
	hint.add_theme_font_override("font", MoonSkin.font(false))
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", MoonSkin.LAVENDER)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(hint)
	confirm_btn = Button.new()
	confirm_btn.text = "이대로 시작"
	confirm_btn.custom_minimum_size = Vector2(220, 48)
	confirm_btn.pressed.connect(confirm)
	confirm_btn.visible = false
	stage.add_child(confirm_btn)
	fx = FX.new()
	fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(fx)


func _s() -> float:
	return root.get_viewport_rect().size.y / 900.0


## 좌하단 주머니 자리(무대 좌표).
func _pocket_point() -> Vector2:
	if game.hud != null and game.hud.moon != null:
		return Stage.to_stage(stage, game.hud.moon.storage_btn.get_global_rect().get_center())
	var vp := Stage.view(stage)
	return Vector2(80 - vp.x * 0.5, vp.y * 0.5 - 80)


## 시작 손패 고르기 시작. 후보는 주머니에 실제로 있는 카드다.
func open() -> void:
	if active:
		return
	offered = game.cards.draw_choices(Cfg.STARTER_DRAW)
	if offered.is_empty():
		return
	active = true
	_phase = "deal"
	marked = -1
	replaced_uid = -1
	replacement = {}
	root.visible = true
	dim.color.a = 0.0
	for c in cards:
		c["node"].queue_free()
	cards.clear()
	var vp := Stage.view(stage)
	var center := Vector2.ZERO  # 무대 좌표의 원점이 화면 가운데다
	title.text = "마녀의 주머니에서 시작 손패를 뽑습니다"
	title.size = Vector2(vp.x, 44)
	title.position = Vector2(-vp.x * 0.5, center.y - 320)
	hint.text = ""
	hint.size = Vector2(vp.x, 30)
	hint.position = Vector2(-vp.x * 0.5, center.y + 225)
	confirm_btn.visible = false
	confirm_btn.position = Vector2(center.x - 110, center.y + 262)
	var n := offered.size()
	var total := n * CARD.x + (n - 1) * GAP
	var x0 := center.x - total * 0.5
	_slots.clear()
	for i in n:
		_slots.append(Vector2(x0 + i * (CARD.x + GAP), center.y - CARD.y * 0.5 - 10))
	if game.hud != null:
		game.hud.refresh_pause()
	game.sounds.play("card_shuffle")
	var tw := create_tween()
	tw.tween_property(dim, "color:a", 0.74, 0.35)
	tw.tween_callback(_deal)


func _make_card(e: Dictionary, i: int) -> Dictionary:
	var btn := TextureButton.new()
	btn.texture_normal = Catalog.texture(e["id"], false)
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.size = CARD
	btn.pivot_offset = CARD * 0.5
	btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	btn.pressed.connect(toggle.bind(i))
	CardLift.attach(btn, func(): return _phase == "pick", func(): game.sounds.play("card_hover"))
	stage.add_child(btn)
	var mark := Label.new()
	mark.text = "교체"
	mark.add_theme_font_override("font", MoonSkin.font(true))
	mark.add_theme_font_size_override("font_size", 40)
	mark.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	mark.add_theme_color_override("font_outline_color", Color(0.12, 0.03, 0.1))
	mark.add_theme_constant_override("outline_size", 12)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.set_anchors_preset(Control.PRESET_FULL_RECT)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mark.visible = false
	mark.rotation_degrees = -12.0
	btn.add_child(mark)
	var nm := Label.new()
	nm.text = game.cards.def(e["id"]).get("name", e["id"]) + ("  ×%d" % e["count"] if game.cards.stackable(e["id"]) and int(e["count"]) > 1 else "")
	nm.add_theme_font_override("font", MoonSkin.font(true))
	nm.add_theme_font_size_override("font_size", 18)
	nm.add_theme_color_override("font_color", MoonSkin.CREAM)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	nm.size = Vector2(CARD.x + 60, 26)
	nm.position = Vector2(-30, CARD.y + 8)
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(nm)
	return {"node": btn, "uid": e["uid"], "id": e["id"], "mark": mark, "slot": i}


## 주머니에서 세 장이 날아와 뒤집히며 펼쳐진다.
func _deal() -> void:
	var from := _pocket_point()
	for i in offered.size():
		var c := _make_card(offered[i], i)
		cards.append(c)
		var btn: TextureButton = c["node"]
		btn.position = from - CARD * 0.5
		btn.scale = Vector2(0.18, 0.18)
		btn.rotation_degrees = -30.0
		btn.modulate = Color(1, 1, 1, 0)
		var tw := create_tween().set_parallel(true)
		var d := 0.18 * i
		tw.tween_property(btn, "modulate:a", 1.0, 0.18).set_delay(d)
		tw.tween_property(btn, "position", _slots[i], 0.62).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.62).set_delay(d).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "rotation_degrees", 0.0, 0.62).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.chain().tween_callback(func():
			var cpos: Vector2 = _slots[i] + CARD * 0.5
			fx.burst(cpos, _s(), 28, [FX.CREAM, FX.GOLD], 200.0)
			fx.card_glow(cpos, CARD)
			game.sounds.play("card_draw"))
	fx.burst(from, _s(), 24, [FX.CREAM, FX.TEAL], 180.0, true)
	var done := create_tween()
	done.tween_interval(0.62 + 0.18 * offered.size() + 0.15)
	done.tween_callback(func():
		_phase = "pick"
		title.text = "시작 손패 — 바꿀 카드가 있으면 한 장 고르세요"
		hint.text = "카드를 클릭하면 교체 표시가 붙습니다(1장). 교체한 카드는 주머니로 돌아가고 새 카드를 뽑습니다"
		confirm_btn.visible = true
		confirm_btn.grab_focus())


## 후보 i의 교체 표시를 켜고 끈다(최대 Cfg.MULLIGAN_SWAPS장 = 1장).
func toggle(i: int) -> bool:
	if _phase != "pick" or i < 0 or i >= cards.size():
		return false
	if marked == i:
		marked = -1
	else:
		if marked != -1:
			cards[marked]["mark"].visible = false
			cards[marked]["node"].modulate = Color(1, 1, 1, 1)
		marked = i
	for k in cards.size():
		var on: bool = k == marked
		cards[k]["mark"].visible = on
		cards[k]["node"].modulate = Color(0.6, 0.55, 0.68, 1.0) if on else Color(1, 1, 1, 1)
	confirm_btn.text = "한 장 바꾸고 시작" if marked != -1 else "이대로 시작"
	game.sounds.play("card_target")
	return true


## 확정: 표시한 카드는 주머니로 돌아가며 다른 카드를 새로 뽑아 보여준 뒤, 세 장이 손패로 내려간다.
func confirm() -> void:
	if _phase != "pick":
		return
	confirm_btn.visible = false
	hint.text = ""
	if marked == -1:
		_phase = "deliver"
		title.text = "시작 손패"
		_deliver()
		return
	_phase = "swap"
	replaced_uid = cards[marked]["uid"]
	var exclude: Array = offered.map(func(e): return e["uid"])
	replacement = game.cards.peek_random_pocket(exclude)
	var old: TextureButton = cards[marked]["node"]
	var slot: int = marked
	var pocket := _pocket_point()
	title.text = "한 장을 주머니에 돌려보내고 새로 뽑습니다"
	game.sounds.play("card_stash")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(old, "position", pocket - CARD * 0.5, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(old, "scale", Vector2(0.18, 0.18), 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.tween_property(old, "rotation_degrees", -30.0, 0.45)
	tw.tween_property(old, "modulate:a", 0.0, 0.45)
	tw.chain().tween_callback(func():
		fx.burst(pocket, _s(), 20, [FX.CREAM, FX.TEAL], 160.0, true)
		old.queue_free()
		if replacement.is_empty():
			cards.remove_at(slot)
			_phase = "deliver"
			_deliver()
			return
		var c := _make_card(replacement, slot)
		c["node"].pressed.disconnect(toggle)
		cards[slot] = c
		var btn: TextureButton = c["node"]
		btn.position = pocket - CARD * 0.5
		btn.scale = Vector2(0.18, 0.18)
		btn.rotation_degrees = -30.0
		btn.modulate = Color(1, 1, 1, 0)
		var tw2 := create_tween().set_parallel(true)
		tw2.tween_property(btn, "modulate:a", 1.0, 0.18)
		tw2.tween_property(btn, "position", _slots[slot], 0.62).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw2.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.62).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw2.tween_property(btn, "rotation_degrees", 0.0, 0.62).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw2.chain().tween_callback(func():
			var cpos: Vector2 = _slots[slot] + CARD * 0.5
			fx.burst(cpos, _s(), 36, [Color(1, 1, 0.9), FX.GOLD, FX.TEAL], 240.0)
			fx.card_glow(cpos, CARD, 0.0, FX.CREAM, FX.GOLD, FX.TEAL, 1.2, 0.9)
			game.sounds.play("card_inspect")
			title.text = "새로 뽑은 카드 — " + game.cards.def(replacement["id"]).get("name", ""))
		tw2.chain().tween_interval(1.0)
		tw2.chain().tween_callback(func():
			_phase = "deliver"
			_deliver()))


## 세 장이 차례로 손패 자리(아래 가운데)로 내려가며 실제 손패에 들어간다. 왼쪽 카드부터 내려가 손패에서는 오른쪽부터 쌓인다.
func _deliver() -> void:
	var hand = game.hud.card_hand if game.hud != null else null
	var vp := Stage.view(stage)
	var land := Vector2(0, vp.y * 0.5 - 40.0 * _s())
	var order := cards.duplicate()
	order.sort_custom(func(a, b): return a["slot"] < b["slot"])
	var last := create_tween()
	for k in order.size():
		var c: Dictionary = order[k]
		var btn: TextureButton = c["node"]
		var uid: int = c["uid"]
		var id: String = c["id"]
		var tw := create_tween().set_parallel(true)
		var d := 0.16 * k
		var target := land + Vector2((k - (order.size() - 1) * 0.5) * 60.0 * _s(), 0) - CARD * Vector2(0.5, 1.0)
		tw.tween_property(btn, "position", target, 0.5).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(btn, "scale", Vector2(0.62, 0.62), 0.5).set_delay(d).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
		tw.tween_property(btn, "modulate:a", 0.0, 0.16).set_delay(d + 0.4)
		tw.chain().tween_callback(func():
			# 실제 손패 진입: 손패는 이 자리에서 카드를 받아 부채꼴로 정렬한다(가운데 공개는 생략)
			if hand != null:
				hand.arrival_hint[id] = stage.get_global_transform() * (target + CARD * Vector2(0.5, 1.0) * 0.62)
			game.cards.draw_uid(uid)
			game.sounds.play("card_shuffle"))
	last.tween_interval(0.5 + 0.16 * order.size() + 0.2)
	last.tween_callback(close)


func close() -> void:
	if not active:
		return
	active = false
	_phase = ""
	game.cards.last_drawn.clear()
	var tw := create_tween()
	tw.tween_property(dim, "color:a", 0.0, 0.3)
	tw.tween_callback(func():
		root.visible = false
		for c in cards:
			if is_instance_valid(c["node"]):
				c["node"].queue_free()
		cards.clear())
	if game.hud != null:
		game.hud.refresh_pause()
	game.toast("시작 손패 %d장 — 주머니에 %d장이 남아 아침마다 한 장씩 옵니다" % [game.cards.hand().size(), game.cards.pocket().size()], Color(1.0, 0.95, 0.8))


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_SPACE):
		confirm()
	if event is InputEventMouseButton or event is InputEventKey:
		get_viewport().set_input_as_handled()
