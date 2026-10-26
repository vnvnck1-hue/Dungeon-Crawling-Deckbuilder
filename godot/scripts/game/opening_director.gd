extends Node
## 도입 연출(첫 실행 플로우 보강, 사용자 결정 2026-10-17): 프롤로그 → 1일차 새벽 → '첫째 날' 타이틀 카드 + 마녀의 첫 혼잣말 →
## 시작 손패(멀리건, 지금처럼 교체 허용) → 첫 판이면 고용 튜토리얼(tutorial.gd).
## 도입이 도는 동안 게임은 멈춰 있고(hud.refresh_pause가 hold를 본다), 새벽빛은 이 노드가 직접 밀어 준다(day_cycle은 정지 중이라 스스로 돌지 않는다).
## 타이틀(Flow.start_game)에서 들어오거나 창을 띄운 실행에서만 켜진다. --script 검증이 main.tscn을 바로 열면 켜지지 않는다(기존 검증 호환).

signal done

const Flow := preload("res://scripts/game/flow.gd")
const PrologueScript := preload("res://scripts/ui/prologue.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const Extension := preload("res://scripts/ui/moon/moon_extension.gd")

const DAWN_RATE := 2.0        # 새벽 전환(12초)을 도입 동안 두 배로 밀어 6초에 끝낸다
const CURTAIN_FADE := 1.4     # 검은 막이 걷히는 시간
const CARD_AT := 1.0          # 막이 걷히기 시작한 뒤 타이틀 카드가 뜨는 시각
const CARD_HOLD := 2.0
const LINE_AT := 4.0          # 혼잣말이 뜨는 시각(타이틀 카드가 걷힌 뒤)
const LINE_HOLD := 2.6
const HAND_AT := 7.2          # 시작 손패를 여는 시각
## 마녀의 첫 혼잣말(내러티브 §4: 일상적인 행동으로 먼저 어떤 사람인지 보여 준다)
const FIRST_LINE := "(기지개를 켜며) 장작은 넉넉하고, 손님방은 비었고… 오늘 밤 숲이 조용하면 좋으련만."

var game
var active := false        # 도입이 아직 끝나지 않았다(1일차 '오늘 밤' 토스트·새벽음은 이 연출이 대신한다)
var hold := false          # 게임을 멈춰 둔다
var phase := ""            # prologue | dawn | hand | done
var with_prologue := true
var prologue
var curtain: ColorRect
var bubble: Label
var monologue_shown := ""
var _layer: CanvasLayer
var _t := 0.0
var _card_done := false
var _line_done := false


func _ready() -> void:
	name = "OpeningDirector"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_layer = CanvasLayer.new()
	_layer.layer = 29
	add_child(_layer)
	curtain = ColorRect.new()
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.color = Color(0.0, 0.0, 0.0, 0.0)
	curtain.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(curtain)
	bubble = Label.new()
	bubble.add_theme_font_override("font", MoonSkin.font(false))
	bubble.add_theme_font_size_override("font_size", 18)
	bubble.add_theme_color_override("font_color", MoonSkin.PAPER_INK)
	bubble.add_theme_stylebox_override("normal", Extension.paper(16))
	bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bubble.custom_minimum_size.x = 420
	bubble.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bubble.modulate.a = 0.0
	bubble.visible = false
	_layer.add_child(bubble)


## main._ready가 session.start() 전에 부른다(새벽음·'오늘 밤' 토스트를 이 연출이 맡는다는 표시).
func prepare(prologue_on: bool) -> void:
	active = true
	hold = true
	with_prologue = prologue_on
	curtain.color.a = 1.0


func begin() -> void:
	if game.hud != null:
		game.hud.refresh_pause()
	if with_prologue:
		phase = "prologue"
		prologue = PrologueScript.new()
		add_child(prologue)
		prologue.finished.connect(func(_skipped: bool): _start_dawn())
		prologue.play()
	else:
		_start_dawn()


## 프롤로그를 끝까지 건너뛴다(검증·Esc와 같은 경로).
func skip_prologue() -> void:
	if prologue != null and prologue.active:
		prologue.skip()


func _start_dawn() -> void:
	if phase == "dawn" or phase == "hand" or phase == "done":
		return
	phase = "dawn"
	_t = 0.0
	if prologue != null:
		prologue.dismiss()
	var dc = game.world.day_cycle
	if dc != null:
		dc._dawn_elapsed = 0.0
		dc.refresh()
	game.sounds.play("dawn")
	var tw := create_tween()
	tw.tween_property(curtain, "color:a", 0.0, CURTAIN_FADE).set_trans(Tween.TRANS_SINE)


func _process(delta: float) -> void:
	if phase == "dawn":
		_t += delta
		var dc = game.world.day_cycle
		if dc != null and dc._dawn_elapsed < 12.0:
			dc._dawn_elapsed = minf(dc._dawn_elapsed + delta * DAWN_RATE, 12.0)
			dc.refresh()
		if not _card_done and _t >= CARD_AT:
			_card_done = true
			if game.get("banner") != null:
				game.banner.day_card(game.session.day(), CARD_HOLD)
		if not _line_done and _t >= LINE_AT:
			_line_done = true
			_say(FIRST_LINE)
		if _t >= HAND_AT:
			_open_hand()
	elif phase == "hand":
		if game.mulligan_ui == null or not game.mulligan_ui.active:
			_finish()
	if bubble.visible:
		_place_bubble()


## 막·카드·혼잣말을 기다리지 않고 바로 시작 손패로(클릭·Esc).
func hurry() -> void:
	if phase != "dawn":
		return
	if not _card_done:
		_card_done = true
		if game.get("banner") != null:
			game.banner.day_card(game.session.day(), 0.8)
	var dc = game.world.day_cycle
	if dc != null:
		dc._dawn_elapsed = maxf(dc._dawn_elapsed, 9.0)
		dc.refresh()
	curtain.color.a = 0.0
	_open_hand()


func _say(text: String) -> void:
	monologue_shown = text
	bubble.text = "마녀 — " + text
	bubble.visible = true
	bubble.reset_size()
	_place_bubble()
	var tw := bubble.create_tween()
	tw.tween_property(bubble, "modulate:a", 1.0, 0.3)
	tw.tween_interval(LINE_HOLD)
	tw.tween_property(bubble, "modulate:a", 0.0, 0.5)
	tw.tween_callback(func(): bubble.visible = false)


## 혼잣말 말풍선은 마녀 머리 위에 붙는다.
func _place_bubble() -> void:
	var cam: Camera3D = game.world.camera
	var wp: Vector3 = game.player.global_position + Vector3(0, 2.6, 0)
	var vp := bubble.get_viewport_rect().size
	var at := Vector2(vp.x * 0.5, vp.y * 0.6)
	if cam != null and not cam.is_position_behind(wp):
		at = cam.unproject_position(wp)
	bubble.position = Vector2(clampf(at.x - bubble.size.x * 0.5, 16.0, vp.x - bubble.size.x - 16.0), clampf(at.y - bubble.size.y - 12.0, 16.0, vp.y - bubble.size.y - 16.0))


func _open_hand() -> void:
	if phase != "dawn":
		return
	phase = "hand"
	hold = false
	# 시작 손패 화면이 다시 게임을 멈춘다(mulligan_ui.active). 남은 새벽빛은 손패를 확정한 뒤 이어서 밝아진다.
	game.grant_starter_cards(true)
	if game.hud != null:
		game.hud.refresh_pause()


func _finish() -> void:
	phase = "done"
	active = false
	hold = false
	if game.hud != null:
		game.hud.refresh_pause()
	if game.get("tutorial") != null:
		game.tutorial.begin()
	done.emit()


func _unhandled_input(event: InputEvent) -> void:
	if phase != "dawn":
		return
	var k := event as InputEventKey
	var mb := event as InputEventMouseButton
	if (k != null and k.pressed and not k.echo and k.keycode in [KEY_ESCAPE, KEY_SPACE, KEY_ENTER]) or (mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		hurry()
		get_viewport().set_input_as_handled()
