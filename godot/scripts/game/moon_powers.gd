extends Node
## MoonPowers: 늑대의 피와 달 카드 3종의 단일 기록(docs/wolf-blood-event-design.md).
## - 늑대의 피는 파르그의 대화 이벤트로 한 판에 한 번만 받는다(blood_given).
## - 늑대의 피를 마녀에게 쓰면 마녀가 괴로워한 뒤 달 카드 세 장이 주머니로 들어온다(grant_moons).
## - 달 카드는 밤 전투 중 마녀에게 쓴다. 한 밤에 한 장(used_tonight), 1회용(사용자 확정 2026-10-18).
## - 오늘 밤 효과(tonight): "crescent" 공격 속도, "half" 공격·이동 속도, "full" 늑대 변신. 밤 전투가 끝나면 풀린다.

const Cfg := preload("res://scripts/config.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")

signal changed

var game
var blood_given := false        # 파르그에게 늑대의 피를 받았는가(한 판 한 번)
var blood_used := false         # 늑대의 피를 썼는가(달 카드가 나왔는가)
var tonight := ""               # "" | "crescent" | "half" | "full"
var used_tonight := false       # 이 밤에 달 카드를 썼는가
var stats := {"moons_used": 0, "wolf_nights": 0}
var _pending_grant := false


func _ready() -> void:
	name = "MoonPowers"
	game.session.state_changed.connect(_on_state)


func _on_state(state: int) -> void:
	if state == SessionScript.State.COMBAT:
		used_tonight = false
		return
	# 밤 전투가 끝나면(정리·새벽·승패) 달의 힘이 풀린다
	if tonight != "":
		end_night()
	used_tonight = false


func kind_of(card_id: String) -> String:
	return Cfg.MOON_KIND.get(card_id, "")


## 달 카드를 지금 마녀에게 쓸 수 있는가. 빈 문자열이면 가능, 아니면 거부 사유.
func block_reason(card_id: String) -> String:
	if kind_of(card_id) == "":
		return "달 카드가 아닙니다"
	if game.session.state != SessionScript.State.COMBAT:
		return "달 카드는 밤 전투 중에만 쓸 수 있습니다"
	if used_tonight or tonight != "":
		return "오늘 밤은 이미 달의 힘을 썼습니다"
	if game.player == null or game.player.dead or game.player.suffering > 0.0:
		return "지금은 쓸 수 없습니다"
	return ""


## 달 카드 사용 확정(카드 소비는 resolver가 한다).
func use(card_id: String) -> bool:
	if block_reason(card_id) != "":
		return false
	tonight = kind_of(card_id)
	used_tonight = true
	stats["moons_used"] += 1
	if tonight == "full":
		stats["wolf_nights"] += 1
	game.player.apply_moon(tonight)
	changed.emit()
	return true


func end_night() -> void:
	if tonight == "":
		return
	tonight = ""
	if game.player != null and is_instance_valid(game.player):
		game.player.apply_moon("")
	changed.emit()


func attack_interval_mult() -> float:
	match tonight:
		"crescent":
			return Cfg.MOON_CRESCENT_ATTACK
		"half":
			return Cfg.MOON_HALF_ATTACK
	return 1.0


func move_mult() -> float:
	match tonight:
		"half":
			return Cfg.MOON_HALF_MOVE
		"full":
			return Cfg.WOLF_MOVE_MULT
	return 1.0


## 늑대의 피 사용: 마녀가 괴로워하고, WOLF_SUFFER_CARDS_AT 뒤에 달 카드 세 장이 주머니로 들어온다.
func drink_blood() -> void:
	blood_used = true
	game.player.suffer(Cfg.WOLF_SUFFER_TIME)
	_pending_grant = true
	# 게임이 멈추면(일시 정지) 타이머도 멈춘다(process_always = false)
	game.get_tree().create_timer(Cfg.WOLF_SUFFER_CARDS_AT, false).timeout.connect(grant_moons)
	changed.emit()


func grant_moons() -> void:
	if not _pending_grant:
		return
	_pending_grant = false
	if game.session.is_over():
		return
	for id in Cfg.MOON_CARDS:
		game.cards.add(id, 1, "", "pocket")
	if game.hud != null and game.hud.card_hand != null and game.hud.card_hand.has_method("fly_to_pocket"):
		game.hud.card_hand.fly_to_pocket(Cfg.MOON_CARDS, game.player.global_position + Vector3(0, 1.6, 0))
	game.toast("달의 힘 세 가지 — 초승달·상현달·보름달 카드가 주머니에 들어왔습니다 (밤에 한 장씩)", Color(0.85, 0.8, 1.0))
	game.sounds.play("card_draw")
	changed.emit()
