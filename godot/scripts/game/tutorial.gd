extends CanvasLayer
## 첫 판 튜토리얼과 단계형 목표(첫 실행 플로우 보강, 사용자 결정 2026-10-17).
## 강제 단계는 핵심 두 가지뿐이다 — 첫 고용(게임 정지·시간 제한 없음·손님 머리 위 화살표)과 계약 카드 배치(낮 시계 정지).
## 1일차 밤 난이도는 바꾸지 않는다. 나머지는 멈추지 않는 힌트(목표 문구 ①~④)다.
## 첫 판 여부는 Flow.tutorial_done()(user://ftue.cfg)으로 판정하고, 타이틀 설정의 '튜토리얼 다시 보기'로 되돌린다.
## 계약 카드 끌기는 일시 정지 중에 막혀 있으므로(card_hand.can_drag) 배치 단계는 트리를 멈추지 않고 낮 시계만 붙든다
## (game_session._process가 holds_clock()을 본다).

const Cfg := preload("res://scripts/config.gd")
const Flow := preload("res://scripts/game/flow.gd")
const Layout := preload("res://scripts/world/layout.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const Extension := preload("res://scripts/ui/moon/moon_extension.gd")

var place_spot := Layout.DOOR_FRONT + Vector3(1.5, 0, 1.5)   # 계약 카드를 놓을 자리(산장 문 앞 마당)

var game
var guide := false          # 단계형 목표 문구를 쓴다(도입이 켜진 실제 플레이)
var stage := "off"          # off | wait_offer | hire | place | done
var hold := false           # 고용 단계: 게임 정지(hud.refresh_pause가 본다)
var offer: Dictionary = {}
var stage_log: Array = []   # 검증용: 단계 전환 기록
var root: Control
var panel: PanelContainer
var panel_title: Label
var panel_body: Label
var hire_btn: Button
var marks: Control


func _ready() -> void:
	name = "Tutorial"
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = MoonSkin.make_theme()
	add_child(root)
	marks = Marks.new()
	marks.tut = self
	marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(marks)
	panel = PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MoonSkin.modal_box())
	# 오른쪽 가운데: 산장 문 앞(손님·배치 자리)과 아래 손패, 위쪽 알림을 가리지 않는 빈 숲 자리
	panel.anchor_left = 1.0
	panel.anchor_right = 1.0
	panel.anchor_top = 0.34
	panel.anchor_bottom = 0.34
	panel.offset_left = -540
	panel.offset_right = -36
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.visible = false
	root.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	panel.add_child(v)
	panel_title = Label.new()
	panel_title.add_theme_font_override("font", MoonSkin.font(true))
	panel_title.add_theme_font_size_override("font_size", 22)
	panel_title.add_theme_color_override("font_color", MoonSkin.CREAM)
	panel_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(panel_title)
	panel_body = Label.new()
	panel_body.add_theme_font_size_override("font_size", 16)
	panel_body.add_theme_color_override("font_color", Color(0.96, 0.93, 0.98))
	panel_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel_body.custom_minimum_size.x = 460
	v.add_child(panel_body)
	hire_btn = Button.new()
	hire_btn.custom_minimum_size = Vector2(0, 44)
	hire_btn.pressed.connect(hire_now)
	hire_btn.visible = false
	v.add_child(hire_btn)


## 도입이 끝나면(opening_director._finish) 부른다. 첫 판이면 강제 단계를 준비하고, 아니면 힌트만 켠다.
func begin() -> void:
	guide = true
	if Flow.tutorial_done():
		_set_stage("off")
	else:
		_set_stage("wait_offer")


func active() -> bool:
	return stage in ["wait_offer", "hire", "place"]


## 배치 단계에서는 낮 시계(손님 도착·숙박비·고용 만료·밤까지 남은 시간)를 멈춘다.
func holds_clock() -> bool:
	return stage == "place" or stage == "hire"


func _set_stage(s: String) -> void:
	stage = s
	stage_log.append({"stage": s, "t": snappedf(game.session.prep_elapsed, 0.1), "paused": game.get_tree().paused})
	match s:
		"hire":
			hold = true
			var who: String = offer.get("person", "손님")
			panel_title.text = "첫 고용 — %s" % who
			panel_body.text = "%s이(가) 일자리를 찾습니다. 밤이 되면 숲의 괴물이 산장 아래 봉인석을 노리고 몰려옵니다.\n머리 위 표시를 클릭하거나 아래 버튼으로 %dG에 고용하세요." % [who, Cfg.CONTRACT_COST]
			hire_btn.text = "%s 고용하기 · %dG" % [who, Cfg.CONTRACT_COST]
			hire_btn.visible = true
			panel.visible = true
			game.sounds.play("offer_open")
		"place":
			hold = false
			panel_title.text = "계약 카드를 산장 앞에 끌어 놓으세요"
			panel_body.text = "손패의 계약 카드를 빛나는 자리로 끌어 놓으면 용병이 나와 밤새 산장을 지킵니다.\n(배치할 때까지 낮 시간이 멈춥니다)"
			hire_btn.visible = false
			panel.visible = true
		"done":
			hold = false
			panel.visible = false
			Flow.set_tutorial_done(true)
			game.toast("용병이 산장 앞을 지킵니다 — 남은 낮 동안 손님을 맞고 밤에 대비하세요", Color(0.85, 1.0, 0.85))
		_:
			hold = false
			panel.visible = false
	if game.hud != null:
		game.hud.refresh_pause()


func _process(_delta: float) -> void:
	var s = game.session
	match stage:
		"wait_offer":
			if s.state == SessionScript.State.PREP and s.day() == 1 and not game.economy.offers.is_empty():
				offer = game.economy.offers[0]
				_set_stage("hire")
			elif s.state != SessionScript.State.PREP:
				_set_stage("off")
		"hire":
			if offer in game.economy.offers:
				# 시간 제한 없음: 만료 시각을 계속 뒤로 민다
				offer["expires"] = game.economy.prep_time + Cfg.HIRE_WAIT
			else:
				_set_stage("place" if _job_card_uid() >= 0 else "off")
		"place":
			if game.contracts.mercs_alive() > 0 and _job_card_uid() < 0:
				_set_stage("done")
			elif s.state != SessionScript.State.PREP:
				_set_stage("off")
	marks.queue_redraw()


func hire_now() -> void:
	if stage != "hire" or not offer in game.economy.offers:
		return
	if not game.economy.hire(offer):
		game.toast("고용할 수 없습니다 — " + game.economy.hire_block_reason(offer), Color(1.0, 0.7, 0.7))


func _job_card_uid() -> int:
	for e in game.cards.hand():
		if e["id"] in Cfg.JOB_CARDS:
			return e["uid"]
	return -1


## 강제 고용 단계: 게임이 멈춰 있어 main._unhandled_input이 손님 클릭을 받지 못하므로 여기서 받는다.
func _unhandled_input(event: InputEvent) -> void:
	if stage != "hire":
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	var g = offer.get("guest")
	if is_instance_valid(g) and guest_screen_pos(g).distance_to(mb.position) < 60.0:
		hire_now()
		get_viewport().set_input_as_handled()


func guest_screen_pos(g) -> Vector2:
	return game.world.camera.unproject_position(g.global_position + Vector3(0, 0.8, 0))


## 단계형 목표 문구(1일차 낮). 빈 문자열이면 moon_hud 기본 목표를 쓴다.
func objective_hint() -> String:
	if not guide:
		return ""
	var s = game.session
	if s.state != SessionScript.State.PREP or s.day() != 1:
		return ""
	if not game.economy.offers.is_empty():
		return "② 손님 머리 위를 눌러 고용"
	if _job_card_uid() >= 0:
		return "③ 계약 카드를 산장 앞에"
	if game.contracts.mercs_alive() > 0:
		return "④ 밤 대비 — 손패 확인"
	return "① 손님을 맞이하세요"


## 화살표·자리 표시(월드 좌표를 화면에 그린다).
class Marks extends Control:
	var tut

	func _draw() -> void:
		var game = tut.game
		var t := Time.get_ticks_msec() / 1000.0
		var bob := sin(t * 5.0) * 7.0
		var gold := Color(1.0, 0.86, 0.45)
		if tut.stage == "hire":
			var g = tut.offer.get("guest")
			if is_instance_valid(g):
				var head: Vector2 = game.world.camera.unproject_position(g.global_position + Vector3(0, 2.6, 0))
				var tip := head + Vector2(0, bob)
				draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-20, -30), tip + Vector2(-7, -30), tip + Vector2(-7, -58), tip + Vector2(7, -58), tip + Vector2(7, -30), tip + Vector2(20, -30)]), gold)
				var body: Vector2 = tut.guest_screen_pos(g)
				draw_arc(body, 46.0 + sin(t * 4.0) * 4.0, 0, TAU, 48, Color(gold, 0.85), 3.0)
		elif tut.stage == "place":
			var cam: Camera3D = game.world.camera
			var spot := cam.unproject_position(tut.place_spot)
			var r := 38.0 + sin(t * 4.0) * 5.0
			draw_arc(spot, r, 0, TAU, 48, Color(gold, 0.9), 4.0)
			draw_circle(spot, r * 0.55, Color(gold, 0.18))
			var uid: int = tut._job_card_uid()
			var hand = game.hud.card_hand if game.hud != null else null
			if uid >= 0 and hand != null and hand.views.has(uid):
				var from: Vector2 = hand.views[uid].get_global_rect().get_center() - Vector2(0, 60)
				var mid := (from + spot) * 0.5 - Vector2(0, 80)
				var prev := from
				var k := fmod(t * 0.8, 1.0)
				for i in range(1, 25):
					var u := i / 24.0
					var p := from.lerp(mid, u).lerp(mid.lerp(spot, u), u)
					if i % 2 == 0:
						draw_line(prev, p, Color(gold, 0.75), 4.0)
					prev = p
				var q := from.lerp(mid, k).lerp(mid.lerp(spot, k), k)
				draw_circle(q, 7.0, gold)
