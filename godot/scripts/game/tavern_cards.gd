extends "res://scripts/game/card_module.gd"
## 술 주정뱅이 에린과 주점 카드 v1(사용자 확정 2026-10-20). 기획 요약: docs/tavern-cards-v01.md
## - 술 카드(흑맥주 통·전투 식량·불꽃 에일·금빛 꿀술·도깨비불 독주·망각의 이슬주)를 ERIN_AT 장 쓰면
##   술에 취한 에린이 가장 가까운 손님 차례에 맨 먼저 와 바로 말을 걸고, 대화로 '술 주정뱅이 에린' 카드를 준다(거절해도 준다).
##   그 뒤 에린은 판이 끝날 때까지 산장에 머물며 잡담을 나누고, 다시 ERIN_AT 장을 채우면 카드가 대화 없이 바로 손패로 온다.
## - 에린 카드를 쓰면 술 4종 + [술주정] 5장 가운데 3장을 가중치로 무작위(중복 가능) 받는다. 술주정은 술로 세지 않는다.
## CardUseResolver 가 이 카드들을 이 모듈로 넘긴다(handles → evaluate → commit).
## 용병 배율·불붙이기는 ally 가, 아침 드로우 감소는 card_inventory 가, 손님 재방문은 lodge_economy 가 이 모듈을 읽는다.

const Cfg := preload("res://scripts/config.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Dialogues := preload("res://scripts/game/guest_dialogues.gd")

## 이 모듈이 판정·사용을 맡는 카드.
const CARD_IDS := ["drunken_erin", "fire_ale", "golden_mead", "wisp_spirit", "dew_of_forgetting", "drunk_rant"]
## 에린 방문 조건으로 세는 술 카드. 술주정·에린 카드는 술이 아니라 세지 않는다.
const DRINK_IDS := ["dark_ale", "battle_ration", "fire_ale", "golden_mead", "wisp_spirit", "dew_of_forgetting"]
const ERIN_ID := "erin"
const ERIN_AT := 3                    # 술 카드를 이만큼 쓰면 에린이 찾아온다(받으면 0부터 다시)

## 에린 카드 한 장당 3번 독립 추첨(중복 가능). 가중치 합 100.
const ERIN_DRAWS := 3
const ERIN_WEIGHTS := {"drunk_rant": 40, "fire_ale": 20, "wisp_spirit": 15, "dew_of_forgetting": 15, "golden_mead": 10}

const FIRE_DAMAGE := 0.4              # 불꽃 에일: 그 밤 공격력 +40%
const FIRE_IGNITES := 3               # 처음 3번의 공격에 불이 붙는다
const IGNITE_DPS := 3.0               # 불붙은 적이 초당 받는 피해
const IGNITE_TIME := 3.0
const IGNITE_TICK := 0.5
const HANGOVER_TIME := 30.0           # 다음 날 낮 처음 30초(준비 시간 90초의 1/3) 동안 숙취로 일하지 않는다

const MEAD_FEE_BONUS := 0.5           # 금빛 꿀술: 그 손님의 숙박비 +50%(바로 받음)
const WISP_CHANCE := 0.5              # 도깨비불 독주: 50% 한 장 더 / 50% 주머니로
const WISP_PICK := 3                  # 도깨비불 독주: 손패에서 무작위로 이만큼 뽑아 그 중 1장을 고른다(사용자 확정 2026-10-21, 에린·계약·침식 카드도 포함)
const DEW_PEEK := 3                   # 망각의 이슬주: 주머니에서 3장을 보고 1장 제거
const RANT_STASH := 2                 # 술주정: 손패 2장을 주머니로 섞어 넣고
const RANT_DRAW := 1                  # 1장을 새로 뽑는다

signal drinks_changed                 # 술 카운트가 바뀜(산장 관리 · 에린 칸의 술잔 표시)

var drinks := 0                       # 다음 에린 카드까지 센 술 카드 수
var erin_waiting := false             # 첫 조건을 채워 에린이 첫 대화(카드)를 기다리는 중
var erin_arrived := false             # 에린이 산장에 와 있음(한 번 오면 판이 끝날 때까지 머문다)
var erin_met := false                 # 첫 대화를 마쳐 에린 카드를 받음. 이후 조건을 채우면 카드가 바로 손패로 온다
var erin_seen_day := -1               # 에린이 처음 찾아온 날
var erin_given := 0                   # 에린 카드를 받은 횟수
var _chat_bag: Array = []             # 에린 잡담 순서(다 듣기 전에는 같은 이야기를 되풀이하지 않는다)
var fire: Dictionary = {}             # 불꽃 에일을 마신 용병 person → 남은 불붙이기 횟수(새벽까지)
var hangover: Dictionary = {}         # person → 남은 숙취 시간(낮에만 줄어든다)
var draw_penalty := 0                 # 다음 아침 드로우에서 뺄 장수(망각의 이슬주)
var mead_returns: Array = []          # 꿀술 대접 손님의 재방문 [{id, day}]
var favor: Dictionary = {}            # 손님 character_id → 꿀술 호감 단계
var _burns: Array = []                # 불붙은 적 [{enemy, left, tick}]
var _rng := RandomNumberGenerator.new()
var stats := {"drinks": 0, "erin_visits": 0, "erin_used": 0, "ignites": 0, "meads": 0, "gifts": 0,
	"wisp_doubled": 0, "wisp_failed": 0, "forgotten": 0, "rants": 0}


func _ready() -> void:
	name = "TavernCards"
	_rng.randomize()
	if game.get("session") != null and game.session != null:
		game.session.state_changed.connect(_on_state)
	if game.get("guest_events") != null:
		game.guest_events.admitted.connect(_on_admitted)


func handles(id: String) -> bool:
	return id in CARD_IDS


func card_name(id: String) -> String:
	return str(game.cards.def(id).get("name", id))


# ───────────────────────── 판정 ─────────────────────────

func evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var plan := _evaluate(entry, sp, r)
	if plan.get("ok", false):
		plan["action"] = "tavern"
		plan["tavern_card"] = entry["id"]
	return plan


func _evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var uid: int = entry["uid"]
	match entry["id"]:
		"drunken_erin":
			return {"ok": true, "pos": _anywhere(), "title": "술 주정뱅이 에린",
				"lines": ["술 4종·술주정 가운데 %d장을 무작위로 받습니다(중복 가능)" % ERIN_DRAWS, "카드 1장 소비"]}
		"fire_ale":
			var a = r.merc_target(sp)
			if a == null:
				return _fail("용병에게 놓으세요")
			if fire.has(a.person):
				return _fail("%s은(는) 이미 불꽃 에일을 마셨습니다" % a.display_name(), a.global_position)
			return {"ok": true, "pos": a.global_position, "ally": a, "title": "불꽃 에일 — " + a.display_name(),
				"lines": ["새벽까지 공격력 +%d%% · 처음 %d번의 공격에 불" % [int(FIRE_DAMAGE * 100.0), FIRE_IGNITES], "다음 날 낮 %d초 숙취 · 1개 소비" % int(HANGOVER_TIME)]}
		"golden_mead":
			if game.session.state != SessionScript.State.PREP:
				return _fail("금빛 꿀술은 손님이 묵는 낮에 대접합니다")
			var n := mead_guests().size()
			if n == 0:
				return _fail("대접할 손님이 산장에 없습니다")
			return {"ok": true, "pos": _anywhere(), "title": "금빛 꿀술",
				"lines": ["손님 한 명에게 대접 — 숙박비 +%d%% · 호감 +1" % int(MEAD_FEE_BONUS * 100.0), "내일 다시 찾아와 선물 카드 · 묵는 손님 %d명" % n]}
		"wisp_spirit":
			if wisp_candidates(uid).is_empty():
				return _fail("독주를 부을 다른 카드가 손패에 없습니다")
			return {"ok": true, "pos": _anywhere(), "title": "도깨비불 독주",
				"lines": ["손패에서 무작위로 뽑힌 %d장 중 1장을 골라 %d%%로 한 장 더(효과 두 번)" % [WISP_PICK, int(WISP_CHANCE * 100.0)], "실패하면 그 카드는 주머니로 · 1개 소비"]}
		"dew_of_forgetting":
			if dew_candidates().is_empty():
				return _fail("주머니에 지울 카드가 없습니다")
			return {"ok": true, "pos": _anywhere(), "title": "망각의 이슬주",
				"lines": ["주머니에서 %d장을 보고 1장을 이번 판에서 영구히 제거" % DEW_PEEK, "다음 날 아침 드로우 −1 · 1개 소비"]}
		"drunk_rant":
			var others := rant_candidates(uid).size()
			if others == 0 and game.cards.eligible_pocket_empty():
				return _fail("섞어 넣을 카드도, 뽑을 카드도 없습니다")
			return {"ok": true, "pos": _anywhere(), "title": "술주정",
				"lines": ["손패 %d장을 무작위로 주머니에 섞어 넣고 %d장을 새로 뽑습니다" % [mini(RANT_STASH, others), RANT_DRAW], "카드 1장 소비"]}
	return _fail("사용할 수 없는 카드입니다")


## 금빛 꿀술을 받을 수 있는 손님(입실해 묵는 중, 오늘 아직 대접받지 않음, 에린 제외).
func mead_guests() -> Array:
	if game.get("guest_events") == null:
		return []
	var today: int = game.session.day()
	var out: Array = []
	for v in game.guest_events.current_guests():
		if v.admitted and str(v.profile.get("character_id", "")) != ERIN_ID and int(v.get("mead_day", -1)) != today:
			out.append(v)
	return out


## 도깨비불 독주를 부을 수 있는 손패 카드: 자신만 제외. 에린·계약(용병)·침식 카드도 모두 포함(사용자 확정 2026-10-21).
func wisp_candidates(exclude_uid: int) -> Array:
	return game.cards.hand().filter(func(e): return e["uid"] != exclude_uid)


## 고르는 창에 올릴 카드: 후보 가운데 무작위 WISP_PICK 장(후보가 그보다 적으면 전부). 손패 전체가 대상이 아니다.
func wisp_pool(exclude_uid: int) -> Array:
	var cands := wisp_candidates(exclude_uid)
	for i in range(cands.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = cands[i]
		cands[i] = cands[j]
		cands[j] = t
	return cands.slice(0, mini(WISP_PICK, cands.size()))


## 망각의 이슬주로 지울 수 있는 주머니 카드(계약 카드는 사람이라 지우지 않는다).
func dew_candidates() -> Array:
	return game.cards.pocket().filter(func(e): return not game.cards.is_job(e["id"]))


## 술주정으로 주머니에 섞어 넣을 손패 카드(자신 제외).
func rant_candidates(exclude_uid: int) -> Array:
	return game.cards.hand().filter(func(e): return e["uid"] != exclude_uid)


# ───────────────────────── 사용 확정 ─────────────────────────

func commit(uid: int, plan: Dictionary, _r) -> Dictionary:
	var id: String = plan["tavern_card"]
	if not game.cards.consume(uid):
		return _fail("카드가 없습니다")
	match id:
		"drunken_erin":
			game.sounds.play_or("erin_card", "card_play")  # 에린 카드 사용 전용: Laura "히끅! 아껴 마셔~!" / "내 비밀 주머니이~!!" 무작위
			use_erin()
		"fire_ale":
			var a = plan["ally"]
			fire[a.person] = FIRE_IGNITES
			Fx.burst(game.actors, a.global_position + Vector3(0, 1.4, 0), Color(1.0, 0.55, 0.2), 14, 2.5)
			game.toast("%s이(가) 불꽃 에일을 들이켰습니다 — 새벽까지 공격 +%d%%, 처음 %d번 불을 붙입니다" % [a.display_name(), int(FIRE_DAMAGE * 100.0), FIRE_IGNITES], Color(1.0, 0.65, 0.35))
		"golden_mead":
			_open_mead()
		"wisp_spirit":
			_open_wisp()
		"dew_of_forgetting":
			_open_dew()
		"drunk_rant":
			game.sounds.play_or("voice_erin", "card_play")  # 술주정: 에린 목소리 8개 중 무작위(사용 전용음 제외)
			rant()
	on_card_used(id)
	game.sounds.play_or("card_play", "card_play")
	return plan


## 카드를 쓴 뒤(이 모듈·종족 카드 공통): 술이면 에린 조건을 센다.
## 처음 채우면 에린이 가장 가까운 손님 차례에 맨 먼저 찾아와 바로 말을 건다(첫 대화 전까지는 더 세지 않는다).
## 첫 대화를 마친 뒤로는 대화·알림 없이 에린 카드가 바로 손패로 들어온다.
func on_card_used(id: String) -> void:
	if not id in DRINK_IDS:
		return
	stats["drinks"] += 1
	if erin_waiting:
		return
	drinks += 1
	if drinks >= ERIN_AT:
		drinks = 0
		if erin_met:
			_grant_erin()
		else:
			erin_waiting = true
			game.toast("어디선가 술 냄새를 맡은 손님이 산장으로 비틀비틀 오고 있습니다…", Color(1.0, 0.8, 0.55))
			call_erin()
	drinks_changed.emit()


## 에린 카드 1장을 손패(가득 차면 주머니)로 바로 넣는다. 반환: 들어간 곳.
func _grant_erin() -> String:
	erin_given += 1
	return game.cards.add("drunken_erin")


## 첫 방문: 낮(준비 시간)이면 지금 바로 혼자 찾아오고, 밤이면 다음 날 첫 손님 무리의 맨 앞에 선다.
func call_erin() -> void:
	if not erin_waiting or erin_arrived:
		return
	if game.session.state == SessionScript.State.PREP and game.economy.has_method("spawn_extra"):
		var lead := lead_guests()
		if not lead.is_empty():
			game.economy.spawn_extra(lead)


## 에린 카드: 가중치로 3장(중복 가능)을 받는다. 반환: 받은 카드 id.
func use_erin() -> Array:
	var got: Array = []
	for i in ERIN_DRAWS:
		got.append(roll_erin())
	for id in got:
		game.cards.add(id)
	stats["erin_used"] += 1
	Fx.celebrate(_anywhere() + Vector3(0, 1.2, 0), Color(1.0, 0.75, 0.4), 0.8)
	game.toast("에린이 술병을 쏟아 놓았습니다 — %s" % " · ".join(got.map(func(x): return card_name(x))), Color(1.0, 0.8, 0.5))
	return got


func roll_erin() -> String:
	var total := 0
	for k in ERIN_WEIGHTS:
		total += int(ERIN_WEIGHTS[k])
	var pick := _rng.randi_range(1, total)
	for k in ERIN_WEIGHTS:
		pick -= int(ERIN_WEIGHTS[k])
		if pick <= 0:
			return k
	return "drunk_rant"


## 술주정: 손패에서 무작위 2장을 주머니로 섞어 넣고 1장을 뽑는다. 반환: {stashed, drawn}.
func rant() -> Dictionary:
	var cands := rant_candidates(-1)
	cands.shuffle()
	var stashed: Array = []
	for e in cands.slice(0, mini(RANT_STASH, cands.size())):
		stashed.append(e["id"])
		game.cards.stash_uid(e["uid"])
	var got: Array = game.cards.draw(RANT_DRAW)
	stats["rants"] += 1
	var names_in: Array = got.map(func(e): return card_name(e["id"]))
	game.toast("술주정 — %s을(를) 주머니에 던져 넣고 %s" % [" · ".join(stashed.map(func(x): return card_name(x))) if not stashed.is_empty() else "아무것도 못",
		("'%s'을(를) 뽑았습니다" % " · ".join(names_in)) if not names_in.is_empty() else "새로 뽑을 카드는 없었습니다"], Color(0.95, 0.8, 0.6))
	if not got.is_empty():
		game.sounds.play("card_draw")
	return {"stashed": stashed, "drawn": got.map(func(e): return e["id"])}


# ── 금빛 꿀술 ──

func _open_mead() -> void:
	var guests := mead_guests()
	if guests.is_empty():
		return
	var items: Array = guests.map(func(v): return {"id": "golden_mead", "texture": str(v.profile.get("portrait", "")),
		"label": "%s\n%s · %s" % [v.profile.get("person", ""), v.profile.get("race_name", ""), v.profile.get("role", "")]})
	var uids: Array = guests.map(func(v): return int(v.uid))
	game.race_cards.open_choice("금빛 꿀술", "누구에게 대접할까요? — 숙박비를 더 내고, 내일 선물을 들고 다시 찾아옵니다", items, func(i: int) -> bool:
		serve_mead(uids[i])
		return true)


## 손님 방문 uid 에게 꿀술 대접: 숙박비 +50%, 호감 +1, 내일 선물을 들고 재방문.
func serve_mead(visit_uid: int) -> bool:
	var v: Dictionary = game.guest_events.visit(visit_uid)
	if v.is_empty():
		return false
	var cid := str(v.profile.get("character_id", ""))
	v["mead_day"] = game.session.day()
	favor[cid] = int(favor.get(cid, 0)) + 1
	var bonus := int(round(Cfg.GUEST_FEE * MEAD_FEE_BONUS))
	game.economy._add_gold(bonus)
	mead_returns.append({"id": cid, "day": game.session.day() + 1})
	stats["meads"] += 1
	game.toast("%s에게 금빛 꿀술을 대접했습니다 — 숙박비 +%dG · 내일 다시 찾아온답니다" % [v.profile.get("person", ""), bonus], Color(1.0, 0.85, 0.45))
	return true


## 꿀술 손님의 선물: 그 손님 종족의 카드 1장(종족 카드가 없으면 인간 카드).
func gift_for(profile: Dictionary) -> String:
	if game.get("race_cards") == null:
		return ""
	var race := str(profile.get("race", "human"))
	var id: String = game.race_cards.random_card([race])
	if id == "":
		id = game.race_cards.random_card(["human"])
	return id


func _give_gift(profile: Dictionary, by_letter := false) -> void:
	var id := gift_for(profile)
	if id == "":
		return
	game.cards.add(id)
	stats["gifts"] += 1
	game.sounds.play("mon_drop")
	game.toast("%s이(가) 어제 꿀술의 답례로 '%s' 카드를 %s" % [profile.get("person", "손님"), card_name(id), "편지와 함께 보냈습니다" if by_letter else "두고 갔습니다"], Color(1.0, 0.9, 0.55))


# ── 도깨비불 독주 ──

func _open_wisp() -> void:
	var cands := wisp_pool(-1)
	if cands.is_empty():
		return
	var items: Array = cands.map(func(e): return {"id": e["id"], "uid": e["uid"], "person": e.get("person", ""), "art": int(e.get("art", -1))})
	game.race_cards.open_choice("도깨비불 독주", "손패에서 무작위로 뽑힌 %d장 — 한 장을 고르면 반은 한 장 더, 반은 주머니로 굴러갑니다" % cands.size(), items, func(i: int) -> bool:
		wisp(int(items[i]["uid"]))
		return true)


## 손패 카드 uid 에 독주: 성공이면 같은 카드 한 장 더, 실패면 그 카드는 주머니로. 반환: 성공 여부.
func wisp(uid: int, force := -1) -> bool:
	var e: Dictionary = game.cards.get_entry(uid)
	if e.is_empty():
		return false
	var ok := _rng.randf() < WISP_CHANCE if force < 0 else force == 1
	var nm := card_name(e["id"])
	if ok:
		game.cards.add(e["id"], 1, str(e.get("person", "")))  # 계약 카드는 같은 사람의 계약이 한 장 더
		stats["wisp_doubled"] += 1
		Fx.celebrate(_anywhere() + Vector3(0, 1.2, 0), Color(0.55, 0.85, 1.0), 0.7)
		game.toast("도깨비불이 춤춥니다 — '%s'이(가) 한 장 더 생겼습니다" % nm, Color(0.6, 0.9, 1.0))
	else:
		game.cards.stash_uid(uid)
		stats["wisp_failed"] += 1
		Fx.poof(_anywhere() + Vector3(0, 1.2, 0), Color(0.45, 0.55, 0.9), 0.6)
		game.toast("도깨비불이 꺼졌습니다 — '%s'은(는) 주머니로 굴러갔습니다" % nm, Color(0.7, 0.75, 0.95))
	return ok


# ── 망각의 이슬주 ──

func _open_dew() -> void:
	var cands := dew_candidates()
	cands.shuffle()
	cands = cands.slice(0, mini(DEW_PEEK, cands.size()))
	if cands.is_empty():
		return
	draw_penalty += 1
	var items: Array = cands.map(func(e): return {"id": e["id"], "uid": e["uid"], "person": e.get("person", ""), "art": int(e.get("art", -1))})
	game.race_cards.open_choice("망각의 이슬주", "잊고 싶은 카드 한 장 — 이번 판에서 영원히 사라집니다", items, func(i: int) -> bool:
		forget(int(items[i]["uid"]))
		return true)


## 주머니 카드 한 장(묶음이면 1개)을 이번 판에서 영구히 지운다.
func forget(uid: int) -> String:
	var e: Dictionary = game.cards.get_entry(uid)
	if e.is_empty():
		return ""
	var id: String = e["id"]
	if int(e["count"]) > 1:
		e["count"] -= 1
		game.cards.changed.emit()
	else:
		game.cards.remove_uid(uid)
	stats["forgotten"] += 1
	Fx.poof(_anywhere() + Vector3(0, 1.2, 0), Color(0.75, 0.8, 0.9), 0.7)
	game.toast("망각의 이슬주 — '%s'을(를) 잊었습니다. 내일 아침은 머리가 멍할 겁니다(드로우 −1)" % card_name(id), Color(0.8, 0.85, 0.95))
	return id


## 아침 드로우 직전(card_inventory.morning_draw): 망각의 이슬주 숙취가 있으면 한 장을 덜 뽑는다. 반환: 뺄 장수.
func take_draw_penalty() -> int:
	if draw_penalty <= 0:
		return 0
	var n := mini(draw_penalty, Cfg.MORNING_DRAW)
	draw_penalty = 0
	game.toast("어제 무슨 일이 있었더라… 망각의 이슬주 탓에 아침 드로우를 %d장 덜 뽑습니다" % n, Color(0.8, 0.85, 0.95))
	return n


# ───────────────────────── 불꽃 에일 — 배율·불·숙취 ─────────────────────────

## 용병 공격력 배율(ally._damage_mult 가 곱한다).
func damage_mult(holder) -> float:
	if holder == null or holder.get("kind") != "merc" or not fire.has(holder.person):
		return 1.0
	return 1.0 + FIRE_DAMAGE


## 용병의 공격이 적에게 맞음(ally.on_hit): 불꽃 에일의 남은 횟수만큼 불을 붙인다.
func on_hit_from(holder, enemy) -> void:
	if holder == null or holder.get("kind") != "merc" or int(fire.get(holder.person, 0)) <= 0:
		return
	if enemy == null or not is_instance_valid(enemy) or enemy.dead:
		return
	fire[holder.person] = int(fire[holder.person]) - 1
	stats["ignites"] += 1
	_burns.append({"enemy": enemy, "left": IGNITE_TIME, "tick": IGNITE_TICK})
	Fx.burst(game.actors, enemy.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.5, 0.15), 10, 2.0)


## 오늘 낮 숙취로 일하지 못하는 용병인가(ally 가 낮마다 묻는다).
func hungover(holder) -> bool:
	return holder != null and game.session.state == SessionScript.State.PREP and float(hangover.get(holder.person, 0.0)) > 0.0


func hangover_left(holder) -> float:
	return float(hangover.get(holder.person, 0.0)) if holder != null else 0.0


func _process(delta: float) -> void:
	if game == null or game.session == null or game.get_tree().paused:
		return
	if game.session.state == SessionScript.State.PREP and not hangover.is_empty():
		for p in hangover.keys():
			hangover[p] = float(hangover[p]) - delta
			if hangover[p] <= 0.0:
				hangover.erase(p)
	for b in (_burns.duplicate() if not _burns.is_empty() else _burns):
		var e = b["enemy"]
		if not is_instance_valid(e) or e.dead:
			_burns.erase(b)
			continue
		b["left"] -= delta
		b["tick"] -= delta
		if b["tick"] <= 0.0:
			b["tick"] += IGNITE_TICK
			e.take_damage(IGNITE_DPS * IGNITE_TICK)
		if b["left"] <= 0.0:
			_burns.erase(b)


# ───────────────────────── 낮밤·손님 ─────────────────────────

func _on_state(state: int) -> void:
	if state != SessionScript.State.PREP:
		return
	# 새벽: 불꽃 에일을 마신 용병은 오늘 낮 숙취, 불은 꺼진다
	for p in fire.keys():
		hangover[p] = HANGOVER_TIME
	if not fire.is_empty():
		game.toast("불꽃 에일을 마신 용병 %d명이 숙취에 시달립니다 — 낮 %d초 동안 쉽니다" % [fire.size(), int(HANGOVER_TIME)], Color(0.9, 0.75, 0.6))
	fire.clear()
	_burns.clear()
	# 산장에 못 오는 꿀술 손님(계약 중인 용병)은 편지로 선물을 보낸다
	var today: int = game.session.day()
	for r in mead_returns.duplicate():
		if int(r["day"]) <= today and str(r["id"]) in _persons_unavailable_ids():
			mead_returns.erase(r)
			_give_gift(GuestProfiles.character(str(r["id"])), true)


func _persons_unavailable_ids() -> Array:
	var out: Array = []
	var busy: Array = game.cards.persons_in_use() + game.contracts.persons_active()
	for c in GuestProfiles.CATALOG:
		if c["person"] in busy:
			out.append(c["id"])
	return out


## lodge_economy._spawn_batch 가 묶음마다 맨 먼저 묻는다: 이 묶음 맨 앞에 설 손님(첫 방문 에린).
## 에린은 정원·숙박비·퇴실에 들지 않는 상주 손님(resident)이라 묶음과 함께 떠나지 않는다.
func lead_guests() -> Array:
	if not erin_waiting or erin_arrived:
		return []
	var p := GuestProfiles.guest_profile(ERIN_ID)
	if p.is_empty():
		return []
	erin_arrived = true
	erin_seen_day = game.session.day()
	stats["erin_visits"] += 1
	p["resident"] = true
	return [p]


## lodge_economy._spawn_batch 가 묶음마다 묻는다: 오늘 이 묶음 끝에 덧붙여 올 특별 손님 프로필(꿀술 재방문).
## taken: 이 묶음에 이미 고른 인물 id.
func extra_guests(taken: Array) -> Array:
	var out: Array = []
	var today: int = game.session.day()
	var present: Array = []
	for v in game.guest_events.current_guests():
		present.append(str(v.profile.get("character_id", "")))
	var busy := _persons_unavailable_ids()
	for r in mead_returns.duplicate():
		var id := str(r["id"])
		if int(r["day"]) > today or id in taken or id in present or id in busy:
			continue
		mead_returns.erase(r)
		var p := GuestProfiles.guest_profile(id)
		if p.is_empty():
			continue
		p["mead_gift"] = true
		p["line"] = "어제 그 꿀술… 아직도 혀끝이 달아요.\n빈손으로 올 수 있나요. 이거 받아요."
		out.append(p)
	return out


## 손님 입실(guest_events.admitted): 꿀술 재방문 손님이면 선물을 건넨다.
func _on_admitted(profile: Dictionary) -> void:
	if profile.get("mead_gift", false) and not profile.get("mead_gift_given", false):
		profile["mead_gift_given"] = true
		_give_gift(profile)


## 에린의 대화를 지금 들려줄 차례인가(guest_events._process).
func erin_story_available(entry: Dictionary) -> bool:
	return not entry.is_empty() and str(entry.profile.get("character_id", "")) == ERIN_ID and erin_waiting


## 대화 선택지 효과 "tavern:erin": 에린 카드를 받는다.
func apply_effect(_entry: Dictionary, effect: String) -> bool:
	if effect != "tavern:erin" or not erin_waiting:
		return false
	erin_waiting = false
	erin_met = true
	drinks = 0
	var zone: String = _grant_erin()
	game.toast("에린에게서 '술 주정뱅이 에린' 카드를 받았습니다%s" % (" (손패가 가득 차 주머니로)" if zone == "pocket" else ""), Color(1.0, 0.8, 0.5))
	game.sounds.play("mon_drop")
	drinks_changed.emit()
	return true


func is_erin(entry: Dictionary) -> bool:
	return not entry.is_empty() and str(entry.profile.get("character_id", "")) == ERIN_ID


## 첫 대화를 마친 뒤 직접 말을 걸면: 에린 잡담 가운데 하나(다 듣기 전에는 되풀이하지 않는다).
func next_erin_chat() -> Dictionary:
	if _chat_bag.is_empty():
		for i in Dialogues.ERIN_CHATS.size():
			_chat_bag.append(i)
		_chat_bag.shuffle()
	return Dialogues.erin_chat(int(_chat_bag.pop_front()))


## 디버그(F1) '에린 방문 부르기': 첫 만남 전이면 조건을 채운 것으로 치고 바로 부른다. 이미 만났으면 카드가 바로 손패로.
## 반환: 결과를 알리는 한 줄.
func debug_call() -> String:
	if erin_met:
		drinks = ERIN_AT - 1
		on_card_used(DRINK_IDS[0])
		stats["drinks"] -= 1
		return "에린은 이미 산장에 머뭅니다 — 술 %d잔을 채운 것으로 쳐 에린 카드를 손패로 넣었습니다" % ERIN_AT
	if erin_arrived:
		return "에린이 이미 산장에 와서 말을 걸려고 기다립니다"
	drinks = 0
	erin_waiting = true
	drinks_changed.emit()
	if game.session.state == SessionScript.State.PREP:
		call_erin()
		return "에린이 지금 바로 찾아옵니다"
	return "에린이 내일 첫 손님 무리의 맨 앞에 섭니다"
