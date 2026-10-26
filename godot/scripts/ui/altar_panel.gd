extends CanvasLayer
## 마녀의 제단 창(볼륨 확장 E2 — 기획: docs/game-volume-expansion-plan.md §3.1).
## 제단 복구(손패 목재) → 하루 한 번 의식: 처음 완성하면 권능 카드, 그 뒤로는 오늘 밤 축복.
## 열려 있는 동안 게임은 멈춘다(hud.refresh_pause()가 active를 본다).

const Cfg := preload("res://scripts/config.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const OutsideClick := preload("res://scripts/ui/outside_click.gd")

var game
var active := false
var root: Control
var panel: PanelContainer
var status: Label
var restore_btn: Button
var ritual_btns: Dictionary = {}   # id -> Button
var close_btn: Button


func _ready() -> void:
	name = "AltarPanel"
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	root.theme = MoonSkin.make_theme()
	root.gui_input.connect(_on_root_input)
	root.resized.connect(func(): if active: _center())  # 창 크기·비율이 바뀌면 다시 가운데로
	add_child(root)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.02, 0.1, 0.6)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 0)
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "마녀의 제단"
	title.add_theme_font_override("font", MoonSkin.font(true))
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", MoonSkin.CREAM)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	status = Label.new()
	status.add_theme_font_override("font", MoonSkin.font(false))
	status.add_theme_font_size_override("font_size", 15)
	status.add_theme_color_override("font_color", MoonSkin.LAVENDER)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size = Vector2(600, 0)  # 자동 줄바꿈 글은 폭을 정해야 높이가 제대로 잡힌다
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(status)
	restore_btn = Button.new()
	restore_btn.custom_minimum_size = Vector2(600, 48)
	restore_btn.pressed.connect(func(): game.chapter.restore_altar(); _refresh())
	box.add_child(restore_btn)
	for id in Cfg.RITUALS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(600, 64)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(func(): perform(id))
		box.add_child(b)
		ritual_btns[id] = b
	close_btn = Button.new()
	close_btn.text = "닫기"
	close_btn.custom_minimum_size = Vector2(160, 40)
	close_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	close_btn.pressed.connect(close)
	box.add_child(close_btn)


func open() -> void:
	if active:
		return
	active = true
	root.visible = true
	_refresh()
	_center.call_deferred()
	if game.hud != null:
		game.hud.refresh_pause()
	game.sounds.play_or("panel_open", "card_shuffle")


func _center() -> void:
	panel.reset_size()
	panel.position = (root.get_viewport_rect().size - panel.size) * 0.5


## 의식을 치른다(검증 도구도 이것을 부른다). 반환: "power" | "blessing" | "".
func perform(id: String) -> String:
	var why: String = game.chapter.ritual_block_reason(id)
	if why != "":
		game.toast("의식을 치를 수 없습니다 — " + why, Color(1.0, 0.7, 0.7))
		return ""
	var r: String = game.chapter.perform_ritual(id)
	_refresh()
	return r


func _refresh() -> void:
	var ch = game.chapter
	restore_btn.visible = not ch.altar_restored
	if not ch.altar_restored:
		var why: String = ch.restore_block_reason()
		restore_btn.text = "제단 복구 — 손패의 목재 %d개" % Cfg.ALTAR_RESTORE_TIMBER + ("" if why == "" else "\n(" + why + ")")
		restore_btn.disabled = why != ""
		status.text = "무너진 돌 위에 괴물의 몸에 있던 것과 같은 문양이 떠 있습니다. 목재로 제단을 다시 세우면 공물을 바칠 수 있습니다."
	else:
		status.text = "하루에 한 번 의식을 치를 수 있습니다. 처음 완성하면 권능 카드를, 다시 치르면 오늘 밤 축복을 받습니다." + ("\n오늘은 이미 의식을 치렀습니다." if ch.ritual_today else "")
	for id in ritual_btns:
		var r: Dictionary = Cfg.RITUALS[id]
		var b: Button = ritual_btns[id]
		b.visible = ch.altar_restored
		var done: int = int(ch.rituals_done.get(id, 0))
		var why2: String = ch.ritual_block_reason(id)
		b.text = "%s %s\n%s%s" % [r["name"], "(완성 %d회 · 다음은 축복)" % done if done > 0 else "(첫 완성 시 권능)", r["desc"], "" if why2 == "" else "\n— " + why2]
		b.disabled = why2 != ""
	if active:
		_center.call_deferred()


func close() -> void:
	if not active:
		return
	active = false
	root.visible = false
	if game.hud != null:
		game.hud.refresh_pause()
	game.sounds.play("panel_close")


## 창 밖(어두운 막) 클릭이면 닫는다. 창 안 클릭은 패널이 먼저 받는다.
func _on_root_input(event: InputEvent) -> void:
	if active and OutsideClick.is_press(event) and not OutsideClick.hits(event.position, [panel]):
		root.accept_event()
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
	if event is InputEventMouseButton or event is InputEventKey:
		get_viewport().set_input_as_handled()
