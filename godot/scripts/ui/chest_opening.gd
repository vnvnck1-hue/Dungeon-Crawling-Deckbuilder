extends CanvasLayer
## 보물상자 연출(기획 §7): 어두운 막 위에 상자가 열리고, 물음표 카드 3장이 튀어나와 가운데 늘어선다.
## 플레이어가 한 장을 클릭하면 세 장이 모두 뒤집혀 공개되고(고른 것 강조) 잠시 뒤 유물이 지급된다.
## 열려 있는 동안 게임은 멈춘다(hud.refresh_pause()가 active를 본다). 상자 그림은 Codex 납품(assets/ui/chest_*.png)을 쓰고, 없으면 그린다.

const Cfg := preload("res://scripts/config.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const Catalog := preload("res://scripts/ui/card_catalog.gd")
const Stage := preload("res://scripts/ui/center_stage.gd")
const CardLift := preload("res://scripts/ui/card_lift.gd")

const CARD := Vector2(220, 330)
const GAP := 40.0

var game
var active := false
var root: Control
var stage: Control          # 화면 가운데 무대 — 상자·카드·제목은 가운데 기준 좌표(창 비율이 바뀌어도 가운데 유지)
var dim: ColorRect
var chest: TextureRect
var chest_draw: Control
var title: Label
var hint: Label
var cards: Array = []       # [{node, id, face, back, label, desc}]
var choices: Array = []
var _phase := ""            # open | pick | reveal
var _picked := -1
var _t := 0.0


func _ready() -> void:
	name = "ChestOpening"
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	root.theme = MoonSkin.make_theme()
	add_child(root)
	dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.02, 0.1, 0.0)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	stage = Stage.make(root)
	chest = TextureRect.new()
	chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	chest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chest.pivot_offset = Vector2(160, 160)
	chest.size = Vector2(320, 320)
	stage.add_child(chest)
	chest_draw = ChestSketch.new()
	chest_draw.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chest_draw.size = Vector2(320, 320)
	chest_draw.pivot_offset = Vector2(160, 160)
	stage.add_child(chest_draw)
	title = Label.new()
	title.add_theme_font_override("font", MoonSkin.font(true))
	title.add_theme_font_size_override("font_size", 30)
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


func _chest_tex(open_state: bool) -> Texture2D:
	var path := "res://assets/ui/chest_open.png" if open_state else "res://assets/ui/chest_closed.png"
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 상자 열기 시작. 유물 선택지는 Relics.choices()에서 뽑는다.
func open(_world_pos: Vector3) -> void:
	if active:
		return
	choices = game.relics.choices()
	if choices.is_empty():
		return
	active = true
	_phase = "open"
	_picked = -1
	_t = 0.0
	root.visible = true
	dim.color.a = 0.0
	var vp := Stage.view(stage)
	var center := Vector2.ZERO  # 무대 좌표의 원점이 화면 가운데다
	for c in cards:
		c["node"].queue_free()
	cards.clear()
	var closed := _chest_tex(false)
	chest.texture = closed
	chest.visible = closed != null
	chest_draw.visible = closed == null
	chest_draw.set("open_state", false)
	for n in [chest, chest_draw]:
		n.position = center - Vector2(160, 160) + Vector2(0, 40)
		n.scale = Vector2(0.2, 0.2)
		n.modulate = Color(1, 1, 1, 1)
	title.text = "보물상자"
	title.size = Vector2(vp.x, 40)
	title.position = Vector2(-vp.x * 0.5, center.y - 300)
	hint.text = ""
	hint.size = Vector2(vp.x, 30)
	hint.position = Vector2(-vp.x * 0.5, center.y + 230)
	if game.hud != null:
		game.hud.refresh_pause()
	game.sounds.play("panel_open")
	var tw := create_tween().set_parallel(true)
	tw.tween_property(dim, "color:a", 0.72, 0.35)
	for n in [chest, chest_draw]:
		tw.tween_property(n, "scale", Vector2(1, 1), 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(_shake_and_open)


func _shake_and_open() -> void:
	var tw := create_tween()
	for i in 4:
		var off := Vector2(randf_range(-8, 8), randf_range(-4, 4))
		tw.tween_property(chest, "position", chest.position + off, 0.06)
		tw.parallel().tween_property(chest_draw, "position", chest_draw.position + off, 0.06)
		tw.tween_property(chest, "position", chest.position, 0.06)
		tw.parallel().tween_property(chest_draw, "position", chest_draw.position, 0.06)
	tw.tween_callback(_lid_open)


func _lid_open() -> void:
	var opened := _chest_tex(true)
	if opened != null:
		chest.texture = opened
	chest_draw.set("open_state", true)
	chest_draw.queue_redraw()
	game.sounds.play_or("chest_open", "mon_drop")
	game.sounds.play("card_shuffle")
	var tw := create_tween()
	for n in [chest, chest_draw]:
		tw.parallel().tween_property(n, "scale", Vector2(1.12, 1.12), 0.12).set_trans(Tween.TRANS_QUAD)
	tw.chain()
	for n in [chest, chest_draw]:
		tw.parallel().tween_property(n, "scale", Vector2(1.0, 1.0), 0.18)
	tw.tween_callback(_spawn_cards)


func _spawn_cards() -> void:
	var center := Vector2.ZERO
	var n := choices.size()
	var total := n * CARD.x + (n - 1) * GAP
	var x0 := center.x - total * 0.5
	var unknown: Texture2D = Catalog.texture("relic_unknown", false)
	for i in n:
		var id: String = choices[i]
		var btn := TextureButton.new()
		btn.texture_normal = unknown
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.size = CARD
		btn.pivot_offset = CARD * 0.5
		btn.position = center - CARD * 0.5 + Vector2(0, 60)
		btn.scale = Vector2(0.2, 0.2)
		btn.modulate = Color(1, 1, 1, 0)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_on_pick.bind(i))
		CardLift.attach(btn, func(): return _phase == "pick", func(): game.sounds.play("card_hover"))
		stage.add_child(btn)
		var face := TextureRect.new()
		face.texture = Catalog.texture(id, false)
		face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		face.set_anchors_preset(Control.PRESET_FULL_RECT)
		face.mouse_filter = Control.MOUSE_FILTER_IGNORE
		face.visible = false
		btn.add_child(face)
		var q := Label.new()
		q.text = "?"
		q.add_theme_font_override("font", MoonSkin.font(true))
		q.add_theme_font_size_override("font_size", 96)
		q.add_theme_color_override("font_color", Color(1.0, 0.88, 0.5))
		q.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.16))
		q.add_theme_constant_override("outline_size", 10)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		# 미공개 유물 원화가 아직 없을 때만 물음표 글자를 덧그린다
		q.visible = not ResourceLoader.exists(Catalog.find("relic_unknown").get("texture", ""))
		btn.add_child(q)
		var nm := Label.new()
		nm.text = Cfg.RELIC_NAMES[id]
		nm.add_theme_font_override("font", MoonSkin.font(true))
		nm.add_theme_font_size_override("font_size", 18)
		nm.add_theme_color_override("font_color", MoonSkin.CREAM)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.size = Vector2(CARD.x + 60, 26)
		nm.position = Vector2(-30, CARD.y + 8)
		nm.visible = false
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(nm)
		var desc := Label.new()
		desc.text = Cfg.RELIC_DESC[id]
		desc.add_theme_font_override("font", MoonSkin.font(false))
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", MoonSkin.LAVENDER)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size = Vector2(CARD.x + 60, 60)
		desc.position = Vector2(-30, CARD.y + 34)
		desc.visible = false
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(desc)
		cards.append({"node": btn, "id": id, "face": face, "q": q, "label": nm, "desc": desc})
		var target := Vector2(x0 + i * (CARD.x + GAP), center.y - CARD.y * 0.5 - 20)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(btn, "modulate:a", 1.0, 0.2).set_delay(i * 0.12)
		tw.tween_property(btn, "position", target, 0.5).set_delay(i * 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(1, 1), 0.5).set_delay(i * 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw2 := create_tween().set_parallel(true)
	for n2 in [chest, chest_draw]:
		tw2.tween_property(n2, "modulate:a", 0.0, 0.4).set_delay(0.3)
		tw2.tween_property(n2, "position:y", n2.position.y + 160, 0.5).set_delay(0.3)
	tw2.chain().tween_callback(func():
		_phase = "pick"
		title.text = "유물 하나를 고르세요"
		hint.text = "물음표 카드를 클릭하면 세 장이 모두 공개되고, 고른 유물을 얻습니다")


func _on_pick(i: int) -> void:
	if _phase != "pick":
		return
	_phase = "reveal"
	_picked = i
	game.sounds.play("card_target")
	title.text = Cfg.RELIC_NAMES[choices[i]]
	hint.text = "선택한 유물: " + Cfg.RELIC_DESC[choices[i]]
	for k in cards.size():
		var c: Dictionary = cards[k]
		var btn: TextureButton = c["node"]
		btn.disabled = true
		var tw := create_tween()
		tw.tween_property(btn, "scale:x", 0.0, 0.16).set_delay(k * 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			c["face"].visible = true
			c["q"].visible = false
			c["label"].visible = true
			c["desc"].visible = true
			if k != _picked:
				btn.modulate = Color(0.55, 0.5, 0.65, 1.0))
		tw.tween_property(btn, "scale:x", 1.0 if k != _picked else 1.1, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if k == _picked:
			tw.parallel().tween_property(btn, "scale:y", 1.1, 0.2)
	var done := create_tween()
	done.tween_interval(1.8)
	done.tween_callback(_finish)


func _finish() -> void:
	if _picked >= 0 and _picked < choices.size():
		game.relics.grant(choices[_picked])
	close()


func close() -> void:
	if not active:
		return
	active = false
	_phase = ""
	var tw := create_tween()
	tw.tween_property(dim, "color:a", 0.0, 0.25)
	for c in cards:
		tw.parallel().tween_property(c["node"], "modulate:a", 0.0, 0.25)
	tw.tween_callback(func():
		root.visible = false
		for c in cards:
			c["node"].queue_free()
		cards.clear())
	if game.hud != null:
		game.hud.refresh_pause()
	game.sounds.play("panel_close")


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	# 열려 있는 동안 월드 입력을 삼킨다. Esc로는 닫을 수 없다(반드시 하나를 고른다).
	if event is InputEventMouseButton or event is InputEventKey:
		get_viewport().set_input_as_handled()


## 상자 그림이 아직 없을 때 쓰는 간단한 스케치(닫힘/열림).
class ChestSketch extends Control:
	var open_state := false

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var wood := Color(0.45, 0.28, 0.14)
		var wood_dark := Color(0.3, 0.18, 0.09)
		var iron := Color(0.55, 0.55, 0.6)
		var gold := Color(1.0, 0.85, 0.4)
		var body := Rect2(w * 0.18, h * 0.45, w * 0.64, h * 0.35)
		if open_state:
			draw_rect(Rect2(body.position.x + 6, body.position.y - 70, body.size.x - 12, 80), Color(gold, 0.35))
			draw_rect(Rect2(body.position.x + 20, body.position.y - 110, body.size.x - 40, 120), Color(gold, 0.18))
		draw_rect(body, wood)
		draw_rect(Rect2(body.position, Vector2(body.size.x, 10)), wood_dark)
		draw_rect(Rect2(body.position.x + body.size.x * 0.5 - 5, body.position.y, 10, body.size.y), iron)
		draw_rect(Rect2(body.position.x + 12, body.position.y, 10, body.size.y), iron)
		draw_rect(Rect2(body.end.x - 22, body.position.y, 10, body.size.y), iron)
		var lid := Rect2(body.position.x, body.position.y - h * 0.16, body.size.x, h * 0.16)
		if open_state:
			lid = Rect2(body.position.x, body.position.y - h * 0.26, body.size.x, h * 0.08)
		draw_rect(lid, wood_dark)
		draw_rect(Rect2(lid.position.x + lid.size.x * 0.5 - 5, lid.position.y, 10, lid.size.y), iron)
		draw_circle(Vector2(body.position.x + body.size.x * 0.5, body.position.y + 12), 12, gold)
