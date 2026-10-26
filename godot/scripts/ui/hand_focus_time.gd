extends Node
## 손패 고민 시간(2026-10-21): 손패 카드에 마우스를 올리거나 끌고 있는 동안 세상의 시간을 1초에 걸쳐 천천히 늦춘다.
## 카드를 쓸지 고민할 시간을 주는 장치다. 손을 떼면 0.35초 만에 다시 흐른다.
## 프리셋(F12 · 일시정지 메뉴 '손패 고민 시간'): 멈춤(완전 정지) · 거의 멈춤(1/40 속도, 시간이 거의 흐르지 않는 듯) · 끔.
## 값은 user://settings.cfg [cards] hand_time 에 저장된다.
##
## 세상은 Engine.time_scale 로 늦추고, 손패·카드 연출·소리 페이드·카메라 같은 UI 쪽 _process 는
## ui_delta()(실제 경과 시간)로 움직여 멈춘 세상 위에서도 평소처럼 가볍게 반응한다.
## UI 트윈은 set_ignore_time_scale(true), UI 타이머는 create_timer(…, ignore_time_scale = true) 로 같은 효과를 낸다.
## 일시정지(get_tree().paused)·판 종료·창(주머니·판매)이 열리면 즉시 원래 속도로 돌려 다른 정지 장치와 겹치지 않는다.

const SETTINGS_PATH := "user://settings.cfg"
const KEY := KEY_F12
const IDS := ["freeze", "crawl", "off"]
const NAMES := ["멈춤", "거의 멈춤", "끔"]
const NAMES_EN := ["Freeze", "Near freeze", "Off"]
const DEFAULT_ID := "freeze"
## 프리셋별 목표 속도(1 = 평소). 거의 멈춤은 1/40 — 화살이 허공에 거의 걸린 채 아주 조금씩 나아간다.
const TARGETS := {"freeze": 0.0, "crawl": 0.025, "off": 1.0}
const SLOW_IN := 1.0      # 손을 올린 뒤 완전히 늦어지기까지(초, 실제 시간)
const SPEED_OUT := 0.35   # 손을 뗀 뒤 평소 속도로 돌아오기까지(초, 실제 시간)

static var current_id := ""
static var engaged := false   # 지금 Engine.time_scale 을 쥐고 있는가(ui_delta 가 실제 시간을 돌려줄 조건)
## 검증·캡처 도구(--script)는 호버를 강제한 채 물리 프레임·타이머를 기다리므로 기본으로 늦추지 않는다. 이 기능을 보는 도구만 true 로 켠다.
static var tool_allowed := false
static var _tool_run := -1
static var real_delta := 1.0 / 60.0
static var _frame := -1
static var _last_usec := 0

var hand                       # card_hand.gd — hover_uid·drag_uid·modal_open() 을 본다
var settings_path := SETTINGS_PATH   # 검증에서는 다른 파일을 쓴다
var pos := 0.0                 # 0 평소 ~ 1 완전히 늦어짐(실제 시간으로 직선 진행, 속도는 smoothstep 곡선)
var base_scale := 1.0          # 쥐기 시작할 때의 Engine.time_scale(촬영 도구가 3배로 돌리는 중이면 그 위에 곱한다)
var _toast = preload("res://scripts/ui/top_toast.gd").new(190)


## 지금 프리셋 id(처음 부를 때 저장된 값을 읽는다).
static func id() -> String:
	if current_id == "":
		var cfg := ConfigFile.new()
		var v := DEFAULT_ID
		if cfg.load(SETTINGS_PATH) == OK:
			v = str(cfg.get_value("cards", "hand_time", DEFAULT_ID))
		current_id = v if v in IDS else DEFAULT_ID
	return current_id


static func apply(new_id: String) -> bool:
	if not new_id in IDS:
		return false
	current_id = new_id
	return true


## 이번 프레임의 실제 경과 시간(초). Engine.time_scale 과 무관하며 어느 노드가 먼저 불러도 같은 값이다.
static func real() -> float:
	var f := Engine.get_process_frames()
	if f != _frame:
		var now := Time.get_ticks_usec()
		real_delta = clampf(float(now - _last_usec) / 1_000_000.0, 0.0, 0.1) if _last_usec > 0 else 1.0 / 60.0
		_last_usec = now
		_frame = f
	return real_delta


## UI _process 에서: 세상이 늦춰진 동안에는 실제 경과 시간을, 평소에는 받은 delta 를 그대로 돌려준다.
static func ui_delta(delta: float) -> float:
	return real() if engaged else delta


## 지금 세상 속도 배율(1 = 평소). 검증·HUD 표시용.
func factor() -> float:
	var t := pos * pos * (3.0 - 2.0 * pos)   # smoothstep: 천천히 느려지기 시작해 부드럽게 멈춘다
	return lerpf(1.0, float(TARGETS[id()]), t)


## --script 로 띄운 도구 실행인가(게임 실행파일·에디터 실행은 아니다).
static func is_tool_run() -> bool:
	if _tool_run < 0:
		_tool_run = 1 if "--script" in OS.get_cmdline_args() else 0
	return _tool_run == 1


## 지금 늦춰야 하는 상황인가: 손패 카드 위에 손이 있거나 끌고 있고, 다른 정지 장치가 없을 때.
func wants_slow() -> bool:
	if hand == null or not is_instance_valid(hand) or id() == "off":
		return false
	if is_tool_run() and not tool_allowed:
		return false
	if get_tree().paused or hand.modal_open():
		return false
	if hand.game != null and hand.game.session != null and hand.game.session.is_over():
		return false
	return hand.hover_uid != -1 or hand.drag_uid != -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	id()


func _process(_delta: float) -> void:
	var dt := real()
	var want := wants_slow()
	if hand != null and is_instance_valid(hand) and get_tree().paused:
		pos = 0.0   # 일시정지 창은 이미 세상을 멈췄다 — 메뉴 연출이 늦어지지 않게 바로 놓는다
	elif want:
		pos = minf(pos + dt / SLOW_IN, 1.0)
	else:
		pos = maxf(pos - dt / SPEED_OUT, 0.0)
	_apply_scale()


func _apply_scale() -> void:
	if pos <= 0.0:
		if engaged:
			Engine.time_scale = base_scale
			engaged = false
		return
	if not engaged:
		base_scale = Engine.time_scale
		engaged = true
	Engine.time_scale = base_scale * factor()


## 검증용: 실제 시간 대신 주어진 초만큼 진행시킨다.
func step(dt: float) -> void:
	var want := wants_slow()
	if want:
		pos = minf(pos + dt / SLOW_IN, 1.0)
	else:
		pos = maxf(pos - dt / SPEED_OUT, 0.0)
	_apply_scale()


func _exit_tree() -> void:
	pos = 0.0
	_apply_scale()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY:
		return
	cycle()
	get_viewport().set_input_as_handled()


## 다음 프리셋으로. 바꾼 id 를 돌려준다.
func cycle() -> String:
	var next: String = IDS[(IDS.find(id()) + 1) % IDS.size()]
	set_preset(next)
	return next


func set_preset(new_id: String, save := true) -> void:
	if not apply(new_id):
		return
	if save:
		var cfg := ConfigFile.new()
		cfg.load(settings_path)   # 다른 구역(언어·소리·디스플레이)은 그대로 둔다
		cfg.set_value("cards", "hand_time", new_id)
		cfg.save(settings_path)
	if is_inside_tree():
		var i := IDS.find(new_id)
		var en := preload("res://scripts/ui/card_face.gd").language() == "en"
		_toast.show_text(self, ("Hand focus time: " + NAMES_EN[i] if en else "손패 고민 시간: " + NAMES[i]) + "  (F12)")
