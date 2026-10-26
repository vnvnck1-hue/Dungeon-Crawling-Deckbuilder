extends Node
## 산장의 소문(평판) v1 — docs/race-cards-v01.md §3, 기획 docs/deck-archetypes-v01.md §6.
## −100(악명)~+100(환대). 제물로 어두워지고, 순례자의 축복·검은 소문 정화로 밝아진다. 화면 막대는 scripts/ui/reputation_bar.gd.
## 구간 효과: 환대 고용비 −5G · 음산 새벽 50%로 검은 소문 · 악명 검은 소문 매 새벽 + 죽음의 행진이 언데드 보상 후보에.

const SessionScript := preload("res://scripts/game/game_session.gd")

signal changed(value: int)

const MIN := -100
const MAX := 100
const WELCOME_AT := 30
const GLOOM_AT := -30
const INFAMY_AT := -70
const WELCOME_HIRE_DISCOUNT := 5
const GLOOM_RUMOR_CHANCE := 0.5

var game
var value := 0
var history: Array = []          # [{day, delta, why}] 검증·기록용
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "Reputation"
	_rng.randomize()
	if game.get("session") != null and game.session != null:
		game.session.state_changed.connect(_on_state)


## 구간: "welcome" | "normal" | "gloom" | "infamy"
func tier() -> String:
	if value >= WELCOME_AT:
		return "welcome"
	if value <= INFAMY_AT:
		return "infamy"
	if value <= GLOOM_AT:
		return "gloom"
	return "normal"


static func tier_name(t: String) -> String:
	return {"welcome": "환대", "normal": "보통", "gloom": "음산", "infamy": "악명"}.get(t, "보통")


func is_dark() -> bool:
	return value <= GLOOM_AT


func shift(delta: int, why := "") -> void:
	if delta == 0:
		return
	var before := tier()
	value = clampi(value + delta, MIN, MAX)
	history.append({"day": game.session.day() if game.get("session") != null else 0, "delta": delta, "why": why})
	changed.emit(value)
	var after := tier()
	if after != before and game.has_method("toast"):
		var col := Color(0.85, 0.7, 1.0) if delta < 0 else Color(1.0, 0.92, 0.65)
		game.toast("산장의 소문이 '%s'(으)로 바뀌었습니다%s" % [tier_name(after), _tier_hint(after)], col)


func _tier_hint(t: String) -> String:
	match t:
		"welcome": return " — 손님들이 반깁니다(고용비 −%dG)" % WELCOME_HIRE_DISCOUNT
		"gloom": return " — 어두운 소문이 주머니에 섞여 듭니다"
		"infamy": return " — 마을에서 이 산장 이름을 낮게 부릅니다"
	return ""


## 고용비 가감(환대 할인). 검은 소문 추가비는 race_cards 가 더한다.
func hire_cost_delta() -> int:
	return -WELCOME_HIRE_DISCOUNT if tier() == "welcome" else 0


func _on_state(state: int) -> void:
	if state == SessionScript.State.PREP:
		on_dawn(game.session.day())


## 새벽: 소문이 어두우면 검은 소문이 주머니로 섞여 든다(하루 최대 1장).
func on_dawn(day: int) -> void:
	if day <= 1 or not is_dark():
		return
	if tier() == "gloom" and _rng.randf() >= GLOOM_RUMOR_CHANCE:
		return
	add_rumor()


func add_rumor() -> void:
	game.cards.add("black_rumor", 1, "", "pocket")
	game.toast("검은 소문이 돌기 시작했습니다 — 주머니에 '검은 소문'(침식)", Color(0.75, 0.55, 0.95))
	game.sounds.play_or("corruption_gain", "card_deny")


## 검은 소문을 정화하면(태우기·이끼 붕대·장날 정화·순례자의 축복) 소문이 조금 밝아진다. card_inventory.remove_uid 가 부른다.
func on_rumor_purified() -> void:
	shift(5, "검은 소문 정화")
