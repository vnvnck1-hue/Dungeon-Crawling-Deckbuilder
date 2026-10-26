extends Node
## ChapterDirector: 12일 챕터의 하루 사건(볼륨 확장 E0~E3 — 기획: docs/game-volume-expansion-plan.md).
## - 밤 규칙 알림·안개의 밤 시야
## - 오늘 밤 축복(제단 의식·권능 카드·전리품 카드): 수의(치명타 1회 버팀), 가시(방책 강화), 붉은 만찬(흡혈), 털가죽(산장 피해 절반)
## - 침식 카드: 적이 주머니에 넣는다(한 밤 상한). 새벽에 손패의 독 포자·저주의 속삭임이 작용한다. 정화로 없앤다
## - 마녀의 제단: 4일차 해금 → 목재로 복구 → 하루 한 번 의식(첫 완성 = 권능 카드, 반복 = 오늘 밤 축복)
## - 새벽 보상(3장 중 1장)·장날(카드 구매·정화)을 낮 시작에 차례로 띄운다

const Cfg := preload("res://scripts/config.gd")
const ChapterData := preload("res://scripts/game/chapter_data.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")

signal blessings_changed
signal altar_changed

var game
var blessings: Dictionary = {}       # id -> true (오늘 밤까지)
var _wards_used: Dictionary = {}     # 수의 축복을 이미 쓴 유닛(instance id)
var corruption_tonight := 0
var altar_unlocked := false
var altar_restored := false
var rituals_done: Dictionary = {}    # 의식 id -> 완성 횟수
var ritual_today := false
var screen_queue: Array = []         # 낮 시작에 띄울 화면 [{"type": "reward"|"market"}]
var stats := {"corruption_in": 0, "purified": 0, "rituals": 0, "rewards": 0, "bought": 0, "spent": 0}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "ChapterDirector"
	_rng.randomize()


func total_days() -> int:
	return ChapterData.total_days()


func day_cfg(d: int) -> Dictionary:
	return ChapterData.day_cfg(d)


# ───────────────────────── 하루 흐름 ─────────────────────────

## 새 낮 시작(GameSession._enter_prep). 반환: 아침 드로우를 막을지(저주의 속삭임).
func on_prep_start(day: int) -> bool:
	ritual_today = false
	var cfg := day_cfg(day)
	var block_draw := false
	if day > 1:
		block_draw = _dawn_corruption()
	if cfg.get("unlock", "") == "altar" and not altar_unlocked:
		altar_unlocked = true
		altar_changed.emit()
		game.sounds.play_or("altar_awaken", "relic_get")
		game.toast("달빛 돌 제단의 문양이 괴물의 몸에 새겨진 것과 같습니다 — 제단을 복구할 수 있습니다", Color(0.75, 0.85, 1.0))
	if bool(cfg.get("reward", false)):
		screen_queue.append({"type": "reward"})
	if bool(cfg.get("market", false)):
		screen_queue.append({"type": "market"})
		game.toast("장날입니다 — 떠돌이 행상이 산장 앞에 짐을 풀었습니다", Color(1.0, 0.9, 0.6))
	var next := ChapterData.rule(day)
	# 1일차 예고는 도입 연출의 '첫째 날' 타이틀 카드가 맡는다(멀리건 뒤에 가려지던 토스트)
	if not (day == 1 and game.get("opening") != null and game.opening.active):
		game.toast("%d일차 — 오늘 밤: %s" % [day, next["name"]], Color(0.9, 0.85, 1.0))
	return block_draw


## 밤 시작(GameSession.start_wave).
func on_wave_start(n: int) -> void:
	corruption_tonight = 0
	var cfg := day_cfg(n)
	var rule: Dictionary = ChapterData.rule(n)
	# 밤 규칙 이름·설명은 GameSession.start_wave의 가운데 배너가 함께 보여 준다(중복 토스트 제거)
	if game.get("banner") == null:
		game.toast("%s — %s" % [rule["name"], rule["desc"]], Color(1.0, 0.75, 0.7))
	_set_fog(cfg.get("night", "") == "fog")


## 밤 정리(GameSession._on_wave_cleared): 오늘 밤의 축복과 안개를 거둔다.
func on_combat_end() -> void:
	if not blessings.is_empty():
		blessings.clear()
		blessings_changed.emit()
	_wards_used.clear()
	_set_fog(false)


func _set_fog(on: bool) -> void:
	var fog = game.world.get("fog_of_war") if game.get("world") != null else null
	if fog != null:
		fog.sight_mult = Cfg.FOG_NIGHT_SIGHT if on else 1.0


func _process(_delta: float) -> void:
	if screen_queue.is_empty() or game.session.state != SessionScript.State.PREP or game.get_tree().paused:
		return
	var ui = game.get("offer_ui")
	if ui == null or ui.active:
		return
	var next: Dictionary = screen_queue.pop_front()
	if next["type"] == "reward":
		ui.open_reward(reward_choices())
	else:
		ui.open_market(market_offers())


# ───────────────────────── 축복 ─────────────────────────

func bless(id: String) -> void:
	blessings[id] = true
	blessings_changed.emit()


func blessed(id: String) -> bool:
	return blessings.has(id)


## 수의: 치명타를 한 번 버틴다. 축복이 있고 이 유닛이 아직 쓰지 않았으면 true(호출 쪽이 체력 1로 남긴다).
func try_ward(unit) -> bool:
	if not blessed("shroud") or unit == null:
		return false
	var key: int = unit.get_instance_id()
	if _wards_used.has(key):
		return false
	_wards_used[key] = true
	game.toast("수의가 치명타를 막았습니다", Color(0.9, 0.9, 1.0))
	return true


func lodge_damage_mult() -> float:
	return Cfg.PELT_LODGE_MULT if blessed("pelt") else 1.0


func thorn_mult() -> float:
	return Cfg.BLESS_THORN_MULT if blessed("thorn") else 1.0


func lifesteal() -> float:
	return Cfg.BLESS_LIFESTEAL if blessed("red_feast") else 0.0


# ───────────────────────── 침식 ─────────────────────────

## 적이 침식 카드를 주머니에 넣는다. 한 밤 상한을 넘으면 넣지 않는다. 반환: 넣었는지.
func add_corruption(card_id: String, why := "") -> bool:
	if not card_id in Cfg.CORRUPTION_CARDS or corruption_tonight >= Cfg.CORRUPTION_PER_NIGHT:
		return false
	corruption_tonight += 1
	stats["corruption_in"] += 1
	game.cards.add(card_id, 1, "", "pocket")
	game.toast("%s — 주머니에 '%s'(침식)" % [why if why != "" else "침식", game.cards.def(card_id).get("name", card_id)], Color(0.8, 0.55, 1.0))
	game.sounds.play_or("corruption_gain", "card_deny")
	return true


func corruption_count() -> int:
	var n := 0
	for e in game.cards.entries:
		if game.cards.is_corruption(e["id"]):
			n += 1
	return n


## 정화: 손패의 침식 카드를 먼저, 없으면 주머니의 것을 하나 없앤다. 반환: 없앤 카드 이름(없으면 빈 문자열).
func purify_one() -> String:
	var pick := {}
	for zone in ["hand", "pocket"]:
		for e in game.cards.entries:
			if e["zone"] == zone and game.cards.is_corruption(e["id"]):
				pick = e
				break
		if not pick.is_empty():
			break
	if pick.is_empty():
		return ""
	var id: String = game.cards.remove_uid(pick["uid"])
	stats["purified"] += 1
	return game.cards.def(id).get("name", id)


## 새벽: 손패의 독 포자는 마녀 체력을, 저주의 속삭임은 아침 드로우를 빼앗는다.
func _dawn_corruption() -> bool:
	var spores := 0
	var whisper := false
	for e in game.cards.hand():
		if e["id"] == "poison_spore":
			spores += 1
		elif e["id"] == "cursed_whisper":
			whisper = true
	if spores > 0 and game.player != null and not game.player.dead:
		var paid: float = game.player.pay_hp(Cfg.SPORE_DAWN_HP * spores)
		game.toast("독 포자 — 새벽에 마녀 체력 -%d" % int(paid), Color(0.75, 1.0, 0.4))
	if whisper:
		game.toast("저주의 속삭임 — 오늘은 아침 드로우를 하지 못했습니다", Color(0.8, 0.55, 1.0))
	return whisper


# ───────────────────────── 제단 ─────────────────────────

func altar_pos() -> Vector3:
	for l in preload("res://scripts/world/layout.gd").LANDMARKS:
		if l["id"] == "shrine":
			return Vector3(l["pos"].x, 0, l["pos"].y)
	return Vector3.ZERO


func player_near_altar() -> bool:
	var p = game.player
	if p == null or p.dead:
		return false
	var a := altar_pos()
	return Vector2(p.global_position.x - a.x, p.global_position.z - a.z).length() <= Cfg.ALTAR_USE_RANGE


func restore_block_reason() -> String:
	if not altar_unlocked:
		return "아직 제단의 문양을 읽을 수 없습니다 (%d일차부터)" % Cfg.ALTAR_UNLOCK_DAY
	if altar_restored:
		return "이미 복구했습니다"
	if game.session.state != SessionScript.State.PREP:
		return "제단은 낮에만 돌볼 수 있습니다"
	if game.cards.hand_count_of("timber") < Cfg.ALTAR_RESTORE_TIMBER:
		return "손패의 목재 %d개가 필요합니다 (보유 %d)" % [Cfg.ALTAR_RESTORE_TIMBER, game.cards.hand_count_of("timber")]
	return ""


func restore_altar() -> bool:
	if restore_block_reason() != "":
		return false
	if not game.cards.consume_id("timber", Cfg.ALTAR_RESTORE_TIMBER):
		return false
	altar_restored = true
	altar_changed.emit()
	if game.get("undead") != null:
		game.undead.grant_dagger("제단 아래 돌 틈")  # 언데드 진입(종족 카드 v1)
	game.toast("마녀의 제단을 복구했습니다 — 공물을 바쳐 의식을 치를 수 있습니다", Color(0.75, 0.85, 1.0))
	game.sounds.play_or("altar_awaken", "relic_get")
	return true


## 의식 공물을 손패(또는 목장)에서 갖췄는지. 부족하면 사유.
func _cost_reason(cost: Dictionary) -> String:
	for k in cost:
		var need: int = int(cost[k])
		if k == "sheep":
			if game.world.pasture.adult_count() < need:
				return "목장에 어른 양 %d마리가 필요합니다" % need
		elif game.cards.hand_count_of(k) < need:
			return "손패의 '%s' %d장이 필요합니다 (보유 %d)" % [game.cards.def(k).get("name", k), need, game.cards.hand_count_of(k)]
	return ""


func ritual_block_reason(id: String) -> String:
	if not Cfg.RITUALS.has(id):
		return "알 수 없는 의식입니다"
	if not altar_restored:
		return "먼저 제단을 복구하세요"
	if game.session.state != SessionScript.State.PREP:
		return "의식은 낮에만 치를 수 있습니다"
	if ritual_today:
		return "오늘은 이미 의식을 치렀습니다"
	return _cost_reason(Cfg.RITUALS[id]["cost"])


## 의식: 공물을 바친다. 처음이면 권능 카드, 그 뒤로는 오늘 밤 축복. 반환: "power" | "blessing" | ""(실패).
func perform_ritual(id: String) -> String:
	if ritual_block_reason(id) != "":
		return ""
	var r: Dictionary = Cfg.RITUALS[id]
	game.cards.begin_use()  # 공물이 여러 종류여도 의식 한 번 = 스택 1
	for k in r["cost"]:
		var need: int = int(r["cost"][k])
		if k == "sheep":
			for i in need:
				game.world.pasture.sacrifice_sheep()
		else:
			game.cards.consume_id(k, need)  # 손패의 같은 id 카드 need장(재화는 소멸, 그 밖은 버림패)
	game.cards.end_use()
	ritual_today = true
	stats["rituals"] += 1
	var first: bool = int(rituals_done.get(id, 0)) == 0
	rituals_done[id] = int(rituals_done.get(id, 0)) + 1
	altar_changed.emit()
	game.sounds.play_or("ritual_done", "relic_get")
	if first:
		game.cards.add(r["power"])
		game.toast("%s 완성 — 권능 '%s' 카드를 얻었습니다" % [r["name"], game.cards.def(r["power"]).get("name", r["power"])], Color(0.75, 0.85, 1.0))
		return "power"
	bless(r["blessing"])
	game.toast("%s — 오늘 밤 축복이 내렸습니다" % r["name"], Color(0.75, 0.85, 1.0))
	return "blessing"


# ───────────────────────── 새벽 보상·장날 ─────────────────────────

func reward_choices() -> Array:
	var pool: Array = ChapterData.REWARD_POOL.duplicate()
	_shuffle(pool)
	var out := pool.slice(0, ChapterData.REWARD_CHOICES)
	# 언데드가 열렸으면 후보 하나가 언데드 카드(종족 카드 v1)
	if game.get("undead") != null:
		out = game.undead.mix_reward(out)
	# 3일차부터 가끔 첫 후보가 전설 카드(docs/legend-cards-v01.md)
	return game.legend.mix_reward(out) if game.get("legend") != null else out


func market_offers() -> Array:
	var pool: Array = ChapterData.MARKET_POOL.duplicate()
	_shuffle(pool)
	var out: Array = []
	for id in pool.slice(0, ChapterData.MARKET_OFFERS):
		out.append({"id": id, "price": int(ChapterData.MARKET_PRICES.get(id, 20)), "sold": false})
	return out


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func take_reward(id: String) -> void:
	stats["rewards"] += 1
	game.cards.add(id)


func buy_block_reason(offer: Dictionary) -> String:
	if offer.get("sold", false):
		return "이미 샀습니다"
	if game.economy.gold < int(offer["price"]):
		return "골드가 부족합니다 (%dG 필요)" % int(offer["price"])
	return ""


func buy(offer: Dictionary) -> bool:
	if buy_block_reason(offer) != "":
		return false
	if not game.economy.spend(int(offer["price"])):
		return false
	offer["sold"] = true
	stats["bought"] += 1
	stats["spent"] += int(offer["price"])
	game.cards.add(offer["id"])
	game.sounds.play_or("gold_spend", "card_play")
	return true


func purify_block_reason() -> String:
	if corruption_count() == 0:
		return "정화할 침식 카드가 없습니다"
	if game.economy.gold < ChapterData.PURIFY_PRICE:
		return "골드가 부족합니다 (%dG 필요)" % ChapterData.PURIFY_PRICE
	return ""


func buy_purify() -> String:
	if purify_block_reason() != "":
		return ""
	if not game.economy.spend(ChapterData.PURIFY_PRICE):
		return ""
	stats["spent"] += ChapterData.PURIFY_PRICE
	return purify_one()
