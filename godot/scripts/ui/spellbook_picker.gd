extends CanvasLayer
## 오래된 마법서적 선택 화면(기획 §6, 확정 규칙 10): 어두운 막 위에 주머니의 카드 최대 3장(부족하면 있는 만큼)이
## 앞면으로 펼쳐지고, 플레이어가 한 장을 고르면 그 카드의 복제본이 손패로 간다. 원본을 포함해 펼친 카드는 모두 주머니에 남는다.
## 열려 있는 동안 게임은 멈춘다(hud.refresh_pause()가 active를 본다). Esc로는 닫을 수 없다(반드시 하나를 고른다).

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
var stage: Control          # 화면 가운데 무대 — 카드·제목은 가운데 기준 좌표(창 비율이 바뀌어도 가운데 유지)
var dim: ColorRect
var title: Label
var hint: Label
var cards: Array = []       # [{node, uid, id}]
var choices: Array = []     # 주머니 entry 목록
var _phase := ""            # spread | pick | done
var _picked := -1
var _spawned := false


func _ready() -> void:
	name = "SpellbookPicker"
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


## 서적을 펼친다. 후보는 CardInventory.draw_choices()에서 뽑는다(주머니에 실제로 있는 카드).
func open() -> void:
	if active:
		return
	choices = game.cards.draw_choices(Cfg.SPELLBOOK_CHOICES)
	if choices.is_empty():
		return
	active = true
	_phase = "spread"
	_picked = -1
	_spawned = false
	root.visible = true
	dim.color.a = 0.0
	var vp := Stage.view(stage)
	var center := Vector2.ZERO  # 무대 좌표의 원점이 화면 가운데다
	for c in cards:
		c["node"].queue_free()
	cards.clear()
	title.text = "오래된 마법서적"
	title.size = Vector2(vp.x, 40)
	title.position = Vector2(-vp.x * 0.5, center.y - 300)
	hint.text = "주머니에서 %d장을 펼칩니다…" % choices.size()
	hint.size = Vector2(vp.x, 30)
	hint.position = Vector2(-vp.x * 0.5, center.y + 230)
	if game.hud != null:
		game.hud.refresh_pause()
	game.sounds.play_or("book_open", "panel_open")
	game.sounds.play("card_shuffle")
	var tw := create_tween()
	tw.tween_property(dim, "color:a", 0.72, 0.3)
	tw.tween_callback(_spawn_cards)


func _spawn_cards() -> void:
	if _spawned:
		return
	_spawned = true
	var vp := Stage.view(stage)
	var center := Vector2.ZERO
	var n := choices.size()
	var total := n * CARD.x + (n - 1) * GAP
	var x0 := center.x - total * 0.5
	var from := Vector2(-vp.x * 0.5, vp.y * 0.5) + Vector2(80, -80)  # 좌하단 주머니 자리에서 날아온다
	for i in n:
		var e: Dictionary = choices[i]
		var id: String = e["id"]
		var btn := TextureButton.new()
		btn.texture_normal = Catalog.texture(id, false)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.size = CARD
		btn.pivot_offset = CARD * 0.5
		btn.position = from - CARD * 0.5
		btn.scale = Vector2(0.2, 0.2)
		btn.modulate = Color(1, 1, 1, 0)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.pressed.connect(_on_pick.bind(i))
		CardLift.attach(btn, func(): return _phase == "pick", func(): game.sounds.play("card_hover"))
		stage.add_child(btn)
		var d: Dictionary = game.cards.def(id)
		var nm := Label.new()
		nm.text = d.get("name", id) + ("  ×%d (1개 복제)" % e["count"] if game.cards.stackable(id) and int(e["count"]) > 1 else "")
		nm.add_theme_font_override("font", MoonSkin.font(true))
		nm.add_theme_font_size_override("font_size", 18)
		nm.add_theme_color_override("font_color", MoonSkin.CREAM)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.size = Vector2(CARD.x + 60, 26)
		nm.position = Vector2(-30, CARD.y + 8)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(nm)
		var desc := Label.new()
		desc.text = d.get("category", "")
		desc.add_theme_font_override("font", MoonSkin.font(false))
		desc.add_theme_font_size_override("font_size", 13)
		desc.add_theme_color_override("font_color", MoonSkin.LAVENDER)
		desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.size = Vector2(CARD.x + 60, 40)
		desc.position = Vector2(-30, CARD.y + 34)
		desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(desc)
		cards.append({"node": btn, "uid": e["uid"], "id": id})
		var target := Vector2(x0 + i * (CARD.x + GAP), center.y - CARD.y * 0.5 - 20)
		var tw := create_tween().set_parallel(true)
		tw.tween_property(btn, "modulate:a", 1.0, 0.2).set_delay(i * 0.12)
		tw.tween_property(btn, "position", target, 0.5).set_delay(i * 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(btn, "scale", Vector2(1, 1), 0.5).set_delay(i * 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var tw2 := create_tween()
	tw2.tween_interval(0.5 + n * 0.12)
	tw2.tween_callback(func():
		_phase = "pick"
		title.text = "한 장을 골라 복제하세요"
		hint.text = "고른 카드의 복제본이 손패로 갑니다. 원본은 주머니에 그대로 남습니다")


## 검증 도구용: 후보 i번을 바로 고른다(연출 생략).
func pick(i: int) -> bool:
	if not active or i < 0 or i >= choices.size():
		return false
	_spawn_cards()
	_phase = "pick"
	_on_pick(i)
	return true


func _on_pick(i: int) -> void:
	if _phase != "pick":
		return
	_phase = "done"
	_picked = i
	game.sounds.play("card_target")
	var got: Dictionary = game.cards.copy_uid(cards[i]["uid"])
	var d: Dictionary = game.cards.def(cards[i]["id"])
	if got.is_empty():
		title.text = "손패가 가득 찼습니다"
		hint.text = "'%s'을(를) 복제하지 못했습니다" % d.get("name", "")
	else:
		title.text = d.get("name", "") + " — 복제본을 손패로"
		hint.text = "원본은 주머니에 그대로 남습니다"
		game.sounds.play("card_draw")
	for k in cards.size():
		var btn: TextureButton = cards[k]["node"]
		btn.disabled = true
		var tw := create_tween()
		if k == _picked and not got.is_empty():
			tw.tween_property(btn, "scale", Vector2(1.12, 1.12), 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		else:
			tw.tween_property(btn, "modulate", Color(0.55, 0.5, 0.65, 1.0), 0.2)
	var done := create_tween()
	done.tween_interval(0.9)
	done.tween_callback(close)


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
	if event is InputEventMouseButton or event is InputEventKey:
		get_viewport().set_input_as_handled()
