extends Node
## 카드 질감 프리셋: F9 로 기존(마법처럼 일렁임) → 단단하게 → 아주 단단하게 를 돌려 본다(2026-10-20).
## 기존 값은 "magic" 에 그대로 두고, 나머지 둘은 card_view.gd 의 휨·둥실거림·물결·출렁임에 배율을 곱해 줄인다.
## 핑그르 도는 회전(yaw 연출)과 두루마리 말림은 카드가 판처럼 도는 동작이라 그대로 둔다 — 줄이는 것은 '종이가 흐물거리는' 쪽뿐이다.
## 값은 user://settings.cfg [cards] feel 에 저장되어 다음 실행에 그대로 쓴다.

const SETTINGS_PATH := "user://settings.cfg"
const KEY := KEY_F9
const IDS := ["magic", "firm", "solid"]
const NAMES := ["기존 · 마법 일렁임", "단단하게", "아주 단단하게"]
const NAMES_EN := ["Original · magic sway", "Firm", "Solid"]
const DEFAULT_ID := "magic"

## motion: 움직임에 따라 돌고 휘는 반응 · bend: 휨·비틀림(움직임·연출 모두) · float: 가만히 둥실 떠다님 ·
## flutter: 표면 물결 · warp_z: 휨 스프링 감쇠비(높을수록 출렁이지 않고 바로 선다) · spring: 위치·회전 스프링 감쇠를 1 쪽으로 당기는 정도
const PROFILES := {
	"magic": {"motion": 1.0, "bend": 1.0, "float": 1.0, "flutter": 1.0, "magic": 1.0, "warp_z": 0.3, "spring": 0.0},
	"firm": {"motion": 0.8, "bend": 0.65, "float": 0.6, "flutter": 0.5, "magic": 0.85, "warp_z": 0.42, "spring": 0.2},
	"solid": {"motion": 0.6, "bend": 0.45, "float": 0.35, "flutter": 0.25, "magic": 0.65, "warp_z": 0.6, "spring": 0.45},
}

static var current_id := ""
static var _cur := {}

var settings_path := SETTINGS_PATH   # 검증에서는 다른 파일을 쓴다
var _toast = preload("res://scripts/ui/top_toast.gd").new(190)


## 지금 프리셋의 값(처음 부를 때 저장된 값을 읽는다).
static func p() -> Dictionary:
	if current_id == "":
		var cfg := ConfigFile.new()
		var id := DEFAULT_ID
		if cfg.load(SETTINGS_PATH) == OK:
			id = str(cfg.get_value("cards", "feel", DEFAULT_ID))
		apply(id if id in IDS else DEFAULT_ID)
	return _cur


static func apply(id: String) -> bool:
	if not id in IDS:
		return false
	current_id = id
	_cur = PROFILES[id]
	return true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	p()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY:
		return
	cycle()
	get_viewport().set_input_as_handled()


## 다음 프리셋으로. 바꾼 id 를 돌려준다.
func cycle() -> String:
	p()
	var next: String = IDS[(IDS.find(current_id) + 1) % IDS.size()]
	set_feel(next)
	return next


func set_feel(id: String, save := true) -> void:
	if not apply(id):
		return
	if save:
		var cfg := ConfigFile.new()
		cfg.load(settings_path)   # 다른 구역(언어·소리·디스플레이)은 그대로 둔다
		cfg.set_value("cards", "feel", id)
		cfg.save(settings_path)
	var i := IDS.find(id)
	var en := preload("res://scripts/ui/card_face.gd").language() == "en"
	_show(("Card feel: " + NAMES_EN[i] if en else "카드 질감: " + NAMES[i]) + "  (F9)")


## 화면 위쪽 가운데에 잠깐 뜨는 알림(TopToast, card_language.gd 와 같은 방식).
func _show(text: String) -> void:
	_toast.show_text(self, text)
