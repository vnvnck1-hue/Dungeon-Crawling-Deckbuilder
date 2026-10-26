extends "res://scripts/game/card_module.gd"
## 언데드 — 플레이 스타일 덱 1호(희생). 기획: docs/deck-archetypes-v01.md §5 · 적용 기록: docs/race-cards-v01.md
## 진입(사용자 결정 2026-10-19): 묘지 확장 또는 제단 복구를 처음 하면 제물의 단검 1장. 단검을 처음 쓰면 언데드가 열리고,
## 그 뒤로는 새벽 보상에도 언데드 카드가 섞이며 쓰러진 용병이 자동으로 시체 카드를 남긴다(묻을까/일으킬까 묻지 않음).
## 시체는 하루 뒤 새벽에 썩는다. 해골·사냥개는 night_summon.gd, 뼈 방책은 card_facility.gd.

const Data := preload("res://scripts/game/race_card_data.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const Fx := preload("res://scripts/visual/fx.gd")

const CARD_IDS := ["sacrifice_dagger", "corpse", "rise_up", "bone_barricade", "soul_jar", "ghoul_feast", "death_march", "bone_hounds"]

var unlocked := false            # 제물의 단검을 한 번이라도 썼는지
var dagger_given := false
var sacrifices := 0
var ledger_count := 0            # 망자의 장부를 끼고 바친 수(5마다 보상)
var corpse_expire: Dictionary = {}   # 시체 카드 uid → 썩는 날(그날 새벽에 사라짐)
var rise_active := false         # 일어나라: 이 밤 쓰러진 용병이 해골로 일어난다
var fallen_tonight: Array = []   # 이 밤 쓰러진 용병 [{person, pos, risen}]
var feast_stacks := 0            # 구울의 만찬: 이 밤 언데드 아군 공격 +15% × 수
var stats := {"sacrificed": 0, "corpses": 0, "rotted": 0, "skeletons": 0, "hounds": 0, "marches": 0, "ledger_rewards": 0}


func _ready() -> void:
	name = "UndeadCards"
	if game.get("session") != null and game.session != null:
		game.session.state_changed.connect(_on_state)


func handles(id: String) -> bool:
	return id in CARD_IDS


func rc():
	return game.race_cards


# ───────────────────────── 진입 ─────────────────────────

## 묘지 확장·제단 복구를 처음 하면(lodge_economy·chapter_director 가 부른다) 제물의 단검 1장.
func grant_dagger(why: String) -> void:
	if dagger_given:
		return
	dagger_given = true
	game.cards.add("sacrifice_dagger")
	game.toast("%s — 어딘가에서 차가운 단검 한 자루가 나왔습니다 '제물의 단검'" % why, Color(0.8, 0.6, 1.0))
	game.sounds.play_or("dagger_found", "relic_get")


## 언데드 보상 후보(단검·망자의 장부). 악명이면 죽음의 행진도.
func undead_pool() -> Array:
	var pool: Array = Data.UNDEAD_POOL.duplicate()
	if _ledger_owned():
		pool.erase("ledger_of_dead")
	if game.get("reputation") != null and game.reputation.tier() == "infamy":
		pool.append_array(Data.UNDEAD_INFAMY)
	return pool.filter(func(id): return game.cards.defs.has(id))


func _ledger_owned() -> bool:
	if game.cards.count_of("ledger_of_dead") > 0:
		return true
	for e in game.cards.in_play + game.cards.discard:
		if e["id"] == "ledger_of_dead":
			return true
	return false


func undead_choices(n := Data.UNDEAD_CHOICES) -> Array:
	var pool := undead_pool()
	pool.shuffle()
	return pool.slice(0, mini(n, pool.size()))


## 새벽 보상(chapter_director.reward_choices): 언데드가 열렸으면 마지막 후보 하나를 언데드 카드로 바꾼다.
func mix_reward(choices: Array) -> Array:
	if not unlocked or choices.is_empty():
		return choices
	var pick := undead_choices(1)
	if pick.is_empty():
		return choices
	var out := choices.duplicate()
	out[out.size() - 1] = pick[0]
	return out


func _offer_undead(title: String, hint: String) -> void:
	var ids := undead_choices()
	if ids.is_empty():
		return
	var items: Array = ids.map(func(id): return {"id": id})
	rc().open_choice(title, hint, items, func(i: int) -> bool:
		game.cards.add(items[i]["id"])
		game.toast("'%s' 카드를 받았습니다" % rc().card_name(items[i]["id"]), Color(0.8, 0.65, 1.0))
		return true)


# ───────────────────────── 시체 ─────────────────────────

## 시체 카드 한 장(인물 이름을 기록). 낮에 얻으면 다음 새벽, 밤에 얻으면 그다음 새벽에 썩는다(하루만 유지).
func give_corpse(person: String) -> int:
	game.cards.add("corpse", 1, person)
	var uid := -1
	for e in game.cards.entries:
		if e["id"] == "corpse" and int(e["uid"]) > uid:
			uid = int(e["uid"])
	var day: int = game.session.day()
	var life := Data.CORPSE_LIFE_DAYS + (1 if game.session.state != SessionScript.State.PREP else 0)
	corpse_expire[uid] = day + life
	stats["corpses"] += 1
	return uid


## 시체 카드 목록(손패 먼저, 그다음 주머니; 각 구역 안에서는 빨리 썩는 순).
func corpse_entries(hand_only := false) -> Array:
	var out: Array = game.cards.entries.filter(func(e): return e["id"] == "corpse" and (not hand_only or e["zone"] == "hand"))
	out.sort_custom(func(a, b):
		if a["zone"] != b["zone"]:
			return a["zone"] == "hand"
		return int(corpse_expire.get(a["uid"], 0)) < int(corpse_expire.get(b["uid"], 0)))
	return out


func corpse_count(hand_only := false) -> int:
	return corpse_entries(hand_only).size()


## 시체 n구를 없앤다(버림패로 돌지 않음). 부족하면 아무것도 바꾸지 않는다.
func use_corpses(n: int, hand_only := false) -> bool:
	var list := corpse_entries(hand_only)
	if list.size() < n:
		return false
	for i in n:
		corpse_expire.erase(list[i]["uid"])
		game.cards.remove_uid(list[i]["uid"])
	return true


func _rot(day: int) -> void:
	var n := 0
	for uid in corpse_expire.keys():
		if day < int(corpse_expire[uid]):
			continue
		corpse_expire.erase(uid)
		if game.cards.remove_uid(uid) != "":
			n += 1
	if n > 0:
		stats["rotted"] += n
		game.toast("시체 %d구가 썩어 사라졌습니다" % n, Color(0.75, 0.7, 0.6))


# ───────────────────────── 해골 ─────────────────────────

func undead_allies() -> Array:
	return game.get_tree().get_nodes_in_group("undead_allies").filter(func(s): return not s.dead)


func raise_skeleton(pos: Vector3, who := ""):
	if undead_allies().size() >= Data.SKELETON_CAP:
		return null
	stats["skeletons"] += 1
	return rc().spawn_summon("skeleton", pos, "undead", who)


func feast_damage() -> float:
	return Data.FEAST_DAMAGE * feast_stacks


# ───────────────────────── 판정 ─────────────────────────

func evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var plan := _evaluate(entry, sp, r)
	if plan.get("ok", false):
		plan["action"] = "undead"
		plan["undead_card"] = entry["id"]
	return plan


func _evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var id: String = entry["id"]
	var cc := corpse_count()
	match id:
		"sacrifice_dagger":
			var a = r.merc_target(sp)
			if a == null:
				return _fail("바칠 용병에게 놓으세요")
			if a.person in rc().oath_persons:
				return _fail("피의 맹세를 맺은 용병은 바칠 수 없습니다", a.global_position)
			return {"ok": true, "pos": a.global_position, "ally": a, "title": "제물의 단검 — " + a.display_name(),
				"lines": ["%s을(를) 바치고 시체 1 + 언데드 카드 3장 중 1장" % a.display_name(), "산장의 소문 %d · 카드 1장 소비" % Data.SACRIFICE_REPUTATION]}
		"soul_jar":
			if cc < 1:
				return _fail("시체가 1구 필요합니다")
			if game.cards.eligible_pocket_empty():
				return _fail("주머니에 뽑을 카드가 없습니다")
			return {"ok": true, "pos": game.player.global_position, "title": "영혼 병",
				"lines": ["시체 1을 써서 주머니에서 %d장" % Data.SOUL_JAR_DRAW, "가진 시체 %d구 · 1개 소비" % cc]}
		"ghoul_feast":
			var hc := corpse_count(true)
			if hc < 1:
				return _fail("손패에 시체가 없습니다")
			if undead_allies().is_empty():
				return _fail("먹일 언데드 아군이 없습니다")
			return {"ok": true, "pos": game.player.global_position, "title": "구울의 만찬",
				"lines": ["손패의 시체 %d구를 모두 씀" % hc, "1구당 언데드 %d기 체력 %d%% 회복 · 공격 +%d%%" % [undead_allies().size(), int(Data.FEAST_HEAL * 100.0), int(Data.FEAST_DAMAGE * 100.0)]]}
		"rise_up":
			if not _night():
				return _fail("일어나라는 밤 전투 중에만 쓸 수 있습니다")
			if rise_active:
				return _fail("이미 망자들이 일어설 준비를 마쳤습니다")
			var waiting := fallen_tonight.filter(func(f): return not f["risen"]).size()
			return {"ok": true, "pos": game.player.global_position, "title": "일어나라",
				"lines": ["새벽까지 쓰러진 용병이 해골로 일어남", "지금 쓰러진 %d명이 바로 일어남 · 카드 1장 소비" % waiting]}
	var p = _point(sp, r)
	if p is String:
		return _fail(p)
	match id:
		"corpse":
			if not _night():
				return _fail("시체는 밤에 땅에 놓아 일으킵니다", p)
			return {"ok": true, "pos": p, "radius": 0.8, "title": "시체 — %s" % entry.get("person", ""),
				"lines": ["해골 병사 1 · 새벽에 무너짐", "시체 1구 소비"]}
		"bone_barricade":
			if cc < Data.BONE_BARRICADE_CORPSES:
				return _fail("시체가 %d구 필요합니다 (보유 %d)" % [Data.BONE_BARRICADE_CORPSES, cc], p)
			return {"ok": true, "pos": p, "title": "뼈 방책",
				"lines": ["체력 %d · 반경 %dm에서 적이 죽으면 +%d" % [int(Data.BONE_BARRICADE_HP), int(Data.BONE_BARRICADE_RADIUS), int(Data.BONE_BARRICADE_HEAL)], "시체 %d구 + 카드 1장 소비" % Data.BONE_BARRICADE_CORPSES]}
		"bone_hounds":
			if not _night():
				return _fail("뼈 사냥개는 밤 전투 중에 부릅니다", p)
			if cc < 1:
				return _fail("시체가 1구 필요합니다", p)
			return {"ok": true, "pos": p, "radius": 1.0, "title": "뼈 사냥개",
				"lines": ["빠른 사냥개 %d마리 · 겁먹은·약한 적부터 쫓음" % Data.HOUND_COUNT, "시체 1구 + 카드 1장 소비"]}
		"death_march":
			if not _night():
				return _fail("죽음의 행진은 밤 전투 중에만 쓸 수 있습니다", p)
			if cc < Data.MARCH_MIN:
				return _fail("시체가 %d구 이상 필요합니다 (보유 %d)" % [Data.MARCH_MIN, cc], p)
			return {"ok": true, "pos": p, "radius": 2.0, "title": "죽음의 행진",
				"lines": ["시체 %d구를 모두 써서 해골 %d기" % [cc, mini(cc, Data.MARCH_CAP)], "카드 1장 소비"]}
	return _fail("사용할 수 없는 카드입니다")


# ───────────────────────── 사용 ─────────────────────────

func commit(uid: int, plan: Dictionary, _r) -> Dictionary:
	var id: String = plan["undead_card"]
	var p: Vector3 = plan["pos"]
	if id == "corpse":
		corpse_expire.erase(uid)
		var person: String = game.cards.get_entry(uid).get("person", "")
		if game.cards.remove_uid(uid) == "":
			return _fail("카드가 없습니다")
		raise_skeleton(p, person)
		game.toast("%s의 시체가 해골 병사로 일어났습니다" % (person if person != "" else "이름 모를 자"), Color(0.8, 0.75, 1.0))
		game.sounds.play_or("skeleton_rise", "card_play")
		return plan
	if not game.cards.consume(uid):
		return _fail("카드가 없습니다")
	match id:
		"sacrifice_dagger":
			sacrifice(plan["ally"])
		"soul_jar":
			use_corpses(1)
			var got: Array = game.cards.draw(Data.SOUL_JAR_DRAW)
			Fx.soul(game.player.global_position + Vector3(0, 1.2, 0))
			game.toast("영혼 병 — %d장을 뽑았습니다" % got.size(), Color(0.75, 0.7, 1.0))
		"ghoul_feast":
			var n := corpse_count(true)
			use_corpses(n, true)
			feast_stacks += n
			for s in undead_allies():
				s.heal(s.max_hp * Data.FEAST_HEAL * n)
				Fx.heal(s.global_position + Vector3(0, 1.0, 0))
			game.toast("구울의 만찬 — 시체 %d구 · 언데드 공격 +%d%%" % [n, int(feast_damage() * 100.0)], Color(0.8, 0.6, 0.9))
		"rise_up":
			rise_active = true
			for f in fallen_tonight:
				if not f["risen"]:
					f["risen"] = true
					raise_skeleton(f["pos"], f["person"])
			game.toast("일어나라 — 오늘 밤 쓰러진 자들이 다시 일어납니다", Color(0.8, 0.7, 1.0))
		"bone_barricade":
			use_corpses(Data.BONE_BARRICADE_CORPSES)
			rc()._build("bone_barricade", p)
			game.toast("뼈 방책을 세웠습니다", Color(0.85, 0.8, 0.95))
		"bone_hounds":
			use_corpses(1)
			for i in Data.HOUND_COUNT:
				rc().spawn_summon("hound", p + Vector3(cos(PI * i), 0, sin(PI * i)) * 0.6, "undead")
			stats["hounds"] += Data.HOUND_COUNT
			game.toast("뼈 사냥개 %d마리가 냄새를 맡았습니다" % Data.HOUND_COUNT, Color(0.85, 0.8, 0.95))
		"death_march":
			var n := corpse_count()
			use_corpses(n)
			var made := 0
			for i in mini(n, Data.MARCH_CAP):
				var a := TAU * i / maxf(1.0, float(mini(n, Data.MARCH_CAP)))
				if raise_skeleton(p + Vector3(cos(a), 0, sin(a)) * (0.8 + 0.25 * (i % 3)), "") != null:
					made += 1
			stats["marches"] += 1
			Fx.soul(p + Vector3(0, 0.5, 0))
			game.toast("죽음의 행진 — 해골 %d기가 일어섰습니다" % made, Color(0.75, 0.6, 1.0))
	game.sounds.play_or("card_play", "card_play")
	return plan


## 제물: 용병을 바치고(계약 종료) 시체 1 + 언데드 카드 3장 중 1장. 소문이 어두워진다.
func sacrifice(a) -> void:
	var person: String = a.person
	var pos: Vector3 = a.global_position
	a.dismiss()
	sacrifices += 1
	stats["sacrificed"] += 1
	give_corpse(person)
	Fx.soul(pos + Vector3(0, 0.6, 0))
	if game.get("reputation") != null:
		game.reputation.shift(Data.SACRIFICE_REPUTATION, "제물")
	var first := not unlocked
	unlocked = true
	game.toast("%s을(를) 제물로 바쳤습니다 — 시체 1구%s" % [person, " · 이제 언데드 카드가 나타납니다" if first else ""], Color(0.8, 0.55, 0.95))
	game.sounds.play_or("sacrifice", "merc_die")
	_offer_undead("제물의 대가", "망자가 내미는 카드 세 장 — 한 장을 고르세요")
	if rc().witch_wears("ledger_of_dead"):
		ledger_count += 1
		if ledger_count % Data.LEDGER_EVERY == 0:
			stats["ledger_rewards"] += 1
			_offer_undead("망자의 장부", "장부에 %d번째 이름이 적혔습니다 — 한 장을 더 고르세요" % ledger_count)


# ───────────────────────── 쓰러짐·처치·낮밤 ─────────────────────────

## 용병이 쓰러짐(contracts.on_ally_died): 언데드가 열렸으면 자동으로 시체 카드. 일어나라 중이면 해골로.
func on_ally_died(a) -> void:
	if a.kind != "merc":
		return
	var f := {"person": a.person, "pos": a.global_position, "risen": false}
	fallen_tonight.append(f)
	if rise_active and _night():
		f["risen"] = true
		raise_skeleton(f["pos"], a.person)
	if unlocked:
		give_corpse(a.person)
		game.toast("%s이(가) 시체를 남겼습니다 — '시체' 카드" % a.person, Color(0.75, 0.7, 0.85))


## 적 처치: 근처 뼈 방책 회복.
func on_enemy_killed(enemy) -> void:
	for f in rc().facilities("bone_barricade"):
		if rc()._flat(f.global_position, enemy.global_position) <= Data.BONE_BARRICADE_RADIUS:
			f.repair(Data.BONE_BARRICADE_HEAL)


func _on_state(state: int) -> void:
	if state == SessionScript.State.PREP:
		on_dawn(game.session.day())


func on_dawn(day: int) -> void:
	rise_active = false
	fallen_tonight.clear()
	feast_stacks = 0
	_rot(day)
