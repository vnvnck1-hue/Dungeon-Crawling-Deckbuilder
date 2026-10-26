extends "res://scripts/game/card_module.gd"
## 종족·화합·브리지 카드 v1(카드 컨셉 검토 2라운드, 2026-10-19). 기획·적용 기록: docs/race-cards-v01.md
## CardUseResolver 가 이 카드들을 이 모듈로 넘긴다(handles → evaluate → commit). 장비는 공용 장비 경로(equipment.gd)로 끼우고,
## 장착 효과·밤 버프·영구 강화는 equipment·ally·night_summon 이 이 모듈의 배율 함수를 읽어 반영한다.
## 사건 카드(용병 이벤트의 merc:race:* 효과)도 여기서 처리한다. 언데드는 undead_cards.gd, 평판은 reputation.gd.

const Data := preload("res://scripts/game/race_card_data.gd")
const Cfg := preload("res://scripts/config.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")
const Races := preload("res://scripts/game/races.gd")
const ChapterData := preload("res://scripts/game/chapter_data.gd")
const Catalog := preload("res://scripts/ui/card_catalog.gd")
const SummonScript := preload("res://scripts/actors/night_summon.gd")
const FacilityScript := preload("res://scripts/actors/card_facility.gd")
const Fx := preload("res://scripts/visual/fx.gd")

## 이 모듈이 판정·사용을 맡는 카드(장비는 equipment.gd 경로).
const CARD_IDS := ["fae_swap", "dark_ale", "stone_wall", "mine_prop", "stone_song", "war_drum", "feast_table", "blood_oath",
	"victory_roar", "spit_roast", "guild_writ", "village_militia", "pilgrim_blessing", "battle_ration", "crest_banner"]
const EQUIP_IDS := ["dream_journal", "thistle_oath", "rune_hammer", "ancestor_shield", "ash_sigil", "pack_scent", "porter_pack",
	"interpreter_pen", "ledger_of_dead"]
const RACE_ORDER := ["human", "dwarf", "fairy", "goblin", "beastfolk", "orc"]

var night := {}                    # 새벽까지의 밤 버프: ale·ration·drum·roast·fate(bool), roar(int)
var _ale_hp: Dictionary = {}       # 흑맥주·전투 식량으로 늘린 최대 체력 {ally instance_id: 더한 값}
var person_buffs: Dictionary = {}  # 영구 강화 {person: {"hp_pct", "hp_flat", "dmg"}} — 피의 맹세·조상의 길·겨울잠·축제
var oath_persons: Array = []       # 피의 맹세를 건 인물(해고·제물 불가)
var lumber_ban_day := -1           # 숲의 약속: 이 날은 벌목 금지
var fairy_pause_day := -1          # 숲의 약속 거절: 이 날은 요정 이벤트 없음
var away: Array = []               # 떠난 용병 [{person, job, return_day, reward}]
var banner_up := false             # 여러 문장이 박힌 깃발을 걸었는지
var _sigil_used: Dictionary = {}   # 재로 그린 문양: 이번 밤에 터진 카드 uid
var _clock := 0.0                  # 밤 시간(일시 정지 반영)
var _song_until := -1.0
var _fear_until: Dictionary = {}   # 겁먹은 적 instance_id → _clock 시각(뼈 사냥개가 먼저 쫓는다)
var _pending: Array = []           # 열려 있는 창이 닫히면 띄울 선택 창
var _rng := RandomNumberGenerator.new()
var stats := {"swaps": 0, "hammer_repairs": 0, "wall_repairs": 0, "props_collapsed": 0, "songs": 0, "sigils": 0,
	"militia": 0, "writs": 0, "wagon_bought": 0, "cleaned": 0}


func _ready() -> void:
	name = "RaceCards"
	_rng.randomize()
	if game.get("session") != null and game.session != null:
		game.session.state_changed.connect(_on_state)


func handles(id: String) -> bool:
	return id in CARD_IDS


# ───────────────────────── 종족 수 ─────────────────────────

## 데리고 있는 용병 [{person, race, ally?, uid?}]: 활동 중인 용병 + 아직 쓰지 않은 계약 카드.
func roster() -> Array:
	var out: Array = []
	if game.get("contracts") != null:
		for a in game.contracts.allies:
			if is_instance_valid(a) and not a.dead and a.kind == "merc":
				out.append({"person": a.person, "race": race_of(a), "ally": a})
	if game.get("cards") != null:
		for e in game.cards.entries:
			if game.cards.is_job(e["id"]):
				out.append({"person": str(e.get("person", "")), "race": GuestProfiles.race_of(str(e.get("person", ""))), "uid": e["uid"]})
	return out


## 종족 N명(활동 + 계약 카드). 고블린과 같은 규칙.
func race_count(race: String) -> int:
	return roster().filter(func(r): return r["race"] == race).size()


## 서로 다른 종족 수. active_only 면 지금 싸우는 용병만(깃발).
func distinct_races(active_only := false) -> int:
	var seen := {}
	if active_only:   # 활동 용병만: 계약 카드까지 담는 roster() 를 만들지 않는다(용병 공격마다 불린다)
		if game.get("contracts") != null:
			for a in game.contracts.allies:
				if is_instance_valid(a) and not a.dead and a.kind == "merc":
					seen[race_of(a)] = true
		return seen.size()
	for r in roster():
		if active_only and not r.has("ally"):
			continue
		if r["race"] != "":
			seen[r["race"]] = true
	return seen.size()


func race_of(holder) -> String:
	if holder == null or holder.get("kind") != "merc":
		return ""
	var r := GuestProfiles.race_of(str(holder.get("person")))
	return r if r != "" else "human"


func is_race(holder, race: String) -> bool:
	return race_of(holder) == race


func mercs() -> Array:
	var out: Array = []
	for a in game.contracts.allies:
		if is_instance_valid(a) and not a.dead and a.kind == "merc":
			out.append(a)
	return out


func witch_wears(id: String) -> bool:
	return game.player != null and not _worn(game.player, id).is_empty()


func card_name(id: String) -> String:
	return str(game.cards.def(id).get("name", id))


# ───────────────────────── 배율(장비·용병·소환물이 읽는다) ─────────────────────────

## 용병 공격력 배율(equipment.damage_mult 가 곱한다).
func damage_mult(holder) -> float:
	if holder == null or holder.get("kind") != "merc":
		return 1.0
	var m := 1.0
	if night.get("drum", false):
		m += Data.DRUM_ORC_DAMAGE if is_race(holder, "orc") else Data.DRUM_DAMAGE
	if night.get("roast", false):
		m += Data.ROAST_DAMAGE
	if banner_up and distinct_races(true) >= Data.BANNER_RACES:
		m += Data.BANNER_DAMAGE
	m += float(person_buffs.get(holder.person, {}).get("dmg", 0.0))
	return m


## 용병 이동 배율(equipment.speed_mult 가 곱한다).
func speed_mult(holder) -> float:
	if holder == null or holder.get("kind") != "merc":
		return 1.0
	var m := 1.0
	if night.get("ale", false) and not night.get("ration", false) and not is_race(holder, "dwarf"):
		m *= Data.ALE_SLOW
	m *= 1.0 + _scent_bonus(holder)
	if not _worn(holder, "porter_pack").is_empty() and holder.job in ["gatherer", "hunter"] and holder.carry_total() > 0:
		m *= 1.0 + Data.PORTER_SPEED
	return m


## 용병 공격 간격 배율(작을수록 빠름). ally 가 공격 대기 시간에 곱한다.
func interval_mult(holder) -> float:
	if holder == null or holder.get("kind") != "merc":
		return 1.0
	var speed := 1.0 + _scent_bonus(holder)
	if is_race(holder, "orc"):
		speed += Data.ROAR_PER_KILL * int(night.get("roar", 0))
	return 1.0 / speed


## 받는 피해 배율(equipment.taken_mult 가 곱한다): 드워프가 낀 조상의 방패 곁의 아군.
func taken_mult(holder) -> float:
	if holder == null or holder.get("kind") != "merc":
		return 1.0
	for a in mercs():
		if a == holder or not is_race(a, "dwarf") or _worn(a, "ancestor_shield").is_empty():
			continue
		if _flat(a.global_position, holder.global_position) <= Data.SHIELD_AURA_RADIUS:
			return 1.0 - Data.SHIELD_AURA
	return 1.0


## 무리의 냄새: 수인 착용자 곁(8m)의 다른 수인 1명마다 +10%(최대 4명).
func _scent_bonus(holder) -> float:
	if _worn(holder, "pack_scent").is_empty() or not is_race(holder, "beastfolk"):
		return 0.0
	var n := 0
	for a in mercs():
		if a != holder and is_race(a, "beastfolk") and _flat(a.global_position, holder.global_position) <= Data.SCENT_RADIUS:
			n += 1
	return Data.SCENT_PER * mini(n, Data.SCENT_MAX)


## 짐꾼의 등짐: 채집가·사냥꾼이 줍는 양 2배(나무꾼의 목재는 그대로).
func carry_mult(holder, id: String) -> int:
	if holder == null or _worn(holder, "porter_pack").is_empty() or not holder.job in ["gatherer", "hunter"] or id == "timber":
		return 1
	return Data.PORTER_MULT


## 용병의 공격이 적에게 맞음: 엉겅퀴 맹세 둔화, 전쟁 북 오크 넉백.
func on_hit_from(holder, enemy) -> void:
	if enemy == null or not is_instance_valid(enemy) or enemy.dead:
		return
	if not _worn(holder, "thistle_oath").is_empty() and enemy.has_method("apply_slow"):
		enemy.apply_slow("thistle", Data.THISTLE_SLOW, Data.THISTLE_TIME)
	if night.get("drum", false) and is_race(holder, "orc"):
		var away_dir: Vector3 = enemy.global_position - holder.global_position
		away_dir.y = 0.0
		if away_dir.length() > 0.01:
			enemy.global_position += away_dir.normalized() * Data.DRUM_KNOCKBACK


# ── 소환물(night_summon.gd) ──

func _militia_passive(unit, key: String) -> float:
	if unit.get("kind") != "militia":
		return 0.0
	var best := 0.0
	for a in mercs():
		var r := race_of(a)
		if r == "human" or not Data.MILITIA_PASSIVE.has(r):
			continue
		if _flat(a.global_position, unit.global_position) <= Data.MILITIA_AURA:
			best = maxf(best, float(Data.MILITIA_PASSIVE[r].get(key, 0.0)))
	return best


func summon_damage_mult(unit) -> float:
	var m := 1.0 + _militia_passive(unit, "damage")
	if unit.get("kind") in ["skeleton", "hound"] and game.get("undead") != null:
		m += game.undead.feast_damage()
	return m


func summon_speed_mult(unit) -> float:
	return 1.0 + _militia_passive(unit, "speed")


func summon_taken_mult(unit) -> float:
	return 1.0 - _militia_passive(unit, "taken")


func on_summon_hit(unit, enemy) -> void:
	var slow := 0.0
	if unit.get("kind") == "militia":
		for a in mercs():
			var r := race_of(a)
			if Data.MILITIA_PASSIVE.has(r) and Data.MILITIA_PASSIVE[r].has("slow") and _flat(a.global_position, unit.global_position) <= Data.MILITIA_AURA:
				slow = float(Data.MILITIA_PASSIVE[r]["slow"])
	if slow > 0.0 and enemy != null and not enemy.dead and enemy.has_method("apply_slow"):
		enemy.apply_slow("militia_thistle", slow, Data.THISTLE_TIME)


func summons() -> Array:
	return game.get_tree().get_nodes_in_group("night_summons").filter(func(s): return not s.dead)


func spawn_summon(unit: String, pos: Vector3, source := "", who := ""):
	var s := SummonScript.new()
	s.setup(game, unit, pos, source, who)
	game.actors.add_child(s)
	return s


# ───────────────────────── 겁(재로 그린 문양) ─────────────────────────

## 적이 겁에 질려 달아난다: 반대쪽으로 밀리고 잠시 느려지며 공격을 멈춘다.
func scare(e, from: Vector3, time: float, push: float) -> void:
	if e == null or e.dead:
		return
	var d: Vector3 = e.global_position - from
	d.y = 0.0
	if d.length() < 0.01:
		d = Vector3(1, 0, 0)
	e.global_position += d.normalized() * push
	if e.has_method("apply_slow"):
		e.apply_slow("terror", 0.45, time)
	if e.get("attack_cd") != null:
		e.attack_cd = maxf(float(e.attack_cd), time)
	_fear_until[e.get_instance_id()] = _clock + time
	Fx.float_text(game.actors, e.global_position + Vector3(0, 1.6, 0), "겁먹음", Color(1.0, 0.75, 0.55))


func is_fleeing(e) -> bool:
	return e != null and float(_fear_until.get(e.get_instance_id(), -1.0)) > _clock


# ───────────────────────── 시설 ─────────────────────────

## 돌 속의 노래가 울리는 동안 모든 시설이 피해를 받지 않는다(산장·감시탑·방책·성벽·버팀목·가시나무).
func facility_shielded() -> bool:
	return _clock < _song_until


func facilities(kind := "") -> Array:
	return game.get_tree().get_nodes_in_group("card_facilities").filter(func(f): return not f.dead and (kind == "" or f.kind == kind))


func on_facility_collapsed(f, broken: bool) -> void:
	if f.kind == "mine_prop":
		var lodge = game.world.lodge
		lodge.max_hp -= Data.PROP_LODGE_HP
		lodge.hp = minf(lodge.hp, lodge.max_hp)
		if broken:
			var hit := 0
			for e in game.get_tree().get_nodes_in_group("enemies"):
				if not e.dead and _flat(e.global_position, f.global_position) <= Data.PROP_COLLAPSE_RADIUS:
					e.take_damage(Data.PROP_COLLAPSE_DAMAGE)
					hit += 1
			stats["props_collapsed"] += 1
			Fx.explosion(game.actors, f.global_position, Data.PROP_COLLAPSE_RADIUS * 0.5)
			game.toast("갱도 버팀목이 무너지며 적 %d마리를 덮쳤습니다" % hit, Color(1.0, 0.75, 0.5))
	elif f.kind == "bone_barricade" and game.get("undead") != null:
		pass


func _build(kind: String, p: Vector3):
	var f := FacilityScript.new()
	f.setup(game, kind, p)
	game.actors.add_child(f)
	if kind == "mine_prop":
		game.world.lodge.max_hp += Data.PROP_LODGE_HP
		game.world.lodge.hp += Data.PROP_LODGE_HP
	return f


# ───────────────────────── 판정(미리보기) ─────────────────────────

func evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var plan := _evaluate(entry, sp, r)
	if plan.get("ok", false):
		plan["action"] = "race"
		plan["race_card"] = entry["id"]
	return plan


func _evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var id: String = entry["id"]
	match id:
		"fae_swap":
			if _swap_candidates(entry["uid"]).is_empty():
				return _fail("맞바꿀 다른 카드가 손패에 없습니다")
			return {"ok": true, "pos": _anywhere(), "title": "요정의 맞바꿈",
				"lines": ["손패 1장을 골라 내고 다른 계열 종족 카드 1장", "%d%%는 침식 카드 · 카드 1장 소비" % int(Data.SWAP_CORRUPT_CHANCE * 100.0)]}
		"dark_ale":
			if night.get("ale", false):
				return _fail("오늘 밤은 이미 흑맥주를 돌렸습니다")
			return {"ok": true, "pos": _anywhere(), "title": "흑맥주 통",
				"lines": ["새벽까지 용병 전원 최대 체력 +%d%% · 이동 −%d%%(드워프 감속 없음)" % [int(Data.ALE_HP * 100.0), int(round((1.0 - Data.ALE_SLOW) * 100.0))], "용병 %d명 · 1개 소비" % mercs().size()]}
		"battle_ration":
			if night.get("ration", false):
				return _fail("오늘 밤은 이미 전투 식량을 나눴습니다")
			return {"ok": true, "pos": _anywhere(), "title": "전투 식량",
				"lines": ["새벽까지 용병 전원 최대 체력 +%d%% · 감속 없음" % int(Data.RATION_HP * 100.0), "지금 체력 %d%% 회복 · 1개 소비" % int(Data.RATION_HEAL * 100.0)]}
		"war_drum":
			if night.get("drum", false):
				return _fail("전쟁 북은 이미 울리고 있습니다")
			return {"ok": true, "pos": _anywhere(), "title": "전쟁 북",
				"lines": ["새벽까지 용병 공격 +%d%% · 오크 +%d%%와 넉백" % [int(Data.DRUM_DAMAGE * 100.0), int(Data.DRUM_ORC_DAMAGE * 100.0)], "오크 용병 %d명 · 카드 1장 소비" % race_count("orc")]}
		"feast_table":
			var n := _feast_count()
			return {"ok": true, "pos": _anywhere(), "title": "잔칫상",
				"lines": ["고기 스튜 %d개%s" % [n, " (오크 %d명 → +1)" % race_count("orc") if n > Data.FEAST_STEWS else ""], "1개 소비"]}
		"spit_roast":
			if game.cards.hand_count_of("raw_meat") < Data.ROAST_MEAT:
				return _fail("손패에 생고기 %d개가 필요합니다 (보유 %d)" % [Data.ROAST_MEAT, game.cards.hand_count_of("raw_meat")])
			return {"ok": true, "pos": _anywhere(), "title": "통구이",
				"lines": ["용병 전원 체력 완전 회복 · 새벽까지 공격 +%d%%" % int(Data.ROAST_DAMAGE * 100.0), "생고기 %d + 1개 소비" % Data.ROAST_MEAT]}
		"victory_roar":
			if not _night():
				return _fail("승리의 함성은 밤 전투 중에만 쓸 수 있습니다")
			return {"ok": true, "pos": _anywhere(), "title": "승리의 함성",
				"lines": ["새벽까지 처치마다 오크 용병 공격 속도 +%d%% (최대 %d중첩)" % [int(Data.ROAR_PER_KILL * 100.0), Data.ROAR_MAX_STACKS], "오크 용병 %d명 · 카드 1장 소비" % race_count("orc")]}
		"stone_song":
			if not _night():
				return _fail("돌 속의 노래는 밤 전투 중에만 쓸 수 있습니다")
			var t := _song_time()
			return {"ok": true, "pos": game.world.lodge.global_position, "title": "돌 속의 노래",
				"lines": ["%d초 동안 모든 시설이 피해를 받지 않음%s" % [int(t), " (드워프 %d명)" % race_count("dwarf") if t > Data.SONG_TIME else ""], "카드 1장 소비"]}
		"pilgrim_blessing":
			var c := _hand_corruptions().size()
			return {"ok": true, "pos": _anywhere(), "title": "순례자의 축복",
				"lines": ["손패의 침식 카드 %d장 정화 · 소문 +%d" % [c, Data.BLESSING_REPUTATION], "카드 1장 소비"]}
		"guild_writ":
			if game.session.state != SessionScript.State.PREP:
				return _fail("길드 증서는 낮에 씁니다")
			if _writ_targets().is_empty():
				return _fail("아직 쓰지 않은 계약 카드가 없습니다")
			return {"ok": true, "pos": _anywhere(), "title": "길드 증서",
				"lines": ["계약 카드 1장의 직업을 바꿉니다(인물·종족 유지)", "카드 1장 소비"]}
		"crest_banner":
			if banner_up:
				return _fail("깃발은 이미 산장에 걸려 있습니다")
			return {"ok": true, "pos": game.world.lodge.global_position, "title": "여러 문장이 박힌 깃발",
				"lines": ["산장에 영구히 겁니다", "서로 다른 종족 용병 %d명+ → 전원 피해 +%d%% (지금 %d종족)" % [Data.BANNER_RACES, int(Data.BANNER_DAMAGE * 100.0), distinct_races(true)]]}
		"blood_oath":
			var a = r.merc_target(sp)
			if a == null:
				return _fail("오크 용병에게 놓으세요")
			if not is_race(a, "orc"):
				return _fail("%s은(는) 오크가 아닙니다" % a.display_name(), a.global_position)
			if a.person in oath_persons:
				return _fail("이미 피의 맹세를 맺었습니다", a.global_position)
			return {"ok": true, "pos": a.global_position, "ally": a, "title": "피의 맹세 — " + a.display_name(),
				"lines": ["영구히 최대 체력 +%d%% · 공격 +%d%%" % [int(Data.OATH_HP * 100.0), int(Data.OATH_DAMAGE * 100.0)], "대신 계약 해지·제물 불가 · 카드 1장 소비"]}
	# 땅에 놓는 카드
	var p = _point(sp, r)
	if p is String:
		return _fail(p)
	match id:
		"stone_wall":
			return {"ok": true, "pos": p, "title": "돌 성벽 기초",
				"lines": ["체력 %d 돌벽 · 적이 먼저 두드림" % int(Data.WALL_HP), "드워프 %d명+면 새벽마다 +%d 수리 (지금 %d명) · 카드 1장 소비" % [Data.WALL_REPAIR_AT, int(Data.WALL_REPAIR), race_count("dwarf")]]}
		"mine_prop":
			if _flat(p, game.world.lodge.global_position) > Data.PROP_RANGE:
				return _fail("산장 가까이(%dm 안)에 세워야 합니다" % int(Data.PROP_RANGE), p)
			return {"ok": true, "pos": p, "title": "갱도 버팀목",
				"lines": ["서 있는 동안 산장 최대 체력 +%d" % int(Data.PROP_LODGE_HP), "부서지면 반경 %.1fm 적에게 피해 %d · 카드 1장 소비" % [Data.PROP_COLLAPSE_RADIUS, int(Data.PROP_COLLAPSE_DAMAGE)]]}
		"village_militia":
			if not _night():
				return _fail("마을 민병은 밤 전투 중에 부릅니다")
			return {"ok": true, "pos": p, "radius": 1.0, "title": "마을 민병",
				"lines": ["인간 민병 %d명 · 새벽에 돌아감" % Data.MILITIA_COUNT, "다른 종족 용병 곁에서 그 종족 패시브 절반 · 카드 1장 소비"]}
	return _fail("사용할 수 없는 카드입니다")


func _feast_count() -> int:
	return Data.FEAST_STEWS + (1 if race_count("orc") >= Data.FEAST_BONUS_AT else 0)


func _song_time() -> float:
	return Data.SONG_TIME_BONUS if race_count("dwarf") >= Data.SONG_BONUS_AT else Data.SONG_TIME


func _hand_corruptions() -> Array:
	return game.cards.hand().filter(func(e): return game.cards.is_corruption(e["id"]))


func _swap_candidates(exclude_uid: int) -> Array:
	return game.cards.hand().filter(func(e): return e["uid"] != exclude_uid and not game.cards.is_corruption(e["id"]))


func _writ_targets() -> Array:
	return game.cards.entries.filter(func(e): return game.cards.is_job(e["id"]))


# ───────────────────────── 사용 확정 ─────────────────────────

func commit(uid: int, plan: Dictionary, _r) -> Dictionary:
	var id: String = plan["race_card"]
	match id:
		"spit_roast":
			game.cards.begin_use()  # 통구이 카드 + 생고기 = 한 번의 사용(스택 1)
			var paid: bool = game.cards.consume_id("raw_meat", Data.ROAST_MEAT) and game.cards.consume(uid)
			game.cards.end_use()
			if not paid:
				return _fail("생고기가 부족합니다")
		_:
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
	match id:
		"fae_swap":
			_open_swap()
		"dark_ale":
			_ale(Data.ALE_HP, "ale")
			game.toast("흑맥주 통을 땄습니다 — 새벽까지 용병 최대 체력 +%d%%" % int(Data.ALE_HP * 100.0), Color(0.95, 0.8, 0.5))
		"battle_ration":
			_ale(Data.RATION_HP, "ration")
			for a in mercs():
				a.hp = minf(a.hp + a.max_hp * Data.RATION_HEAL, a.max_hp)
				Fx.heal(a.global_position + Vector3(0, 1.0, 0))
			game.toast("전투 식량 — 흑맥주와 스튜를 한 번에. 새벽까지 최대 체력 +%d%%" % int(Data.RATION_HP * 100.0), Color(0.95, 0.85, 0.55))
		"war_drum":
			night["drum"] = true
			game.sounds.play_or("war_drum", "card_play")
			game.toast("전쟁 북이 울립니다 — 새벽까지 용병 공격 +%d%%, 오크 +%d%%" % [int(Data.DRUM_DAMAGE * 100.0), int(Data.DRUM_ORC_DAMAGE * 100.0)], Color(1.0, 0.65, 0.5))
		"feast_table":
			var n := _feast_count()
			game.cards.add("meat_stew", n)
			game.toast("잔칫상을 차렸습니다 — 고기 스튜 %d개" % n, Color(1.0, 0.85, 0.55))
		"spit_roast":
			night["roast"] = true
			for a in mercs():
				a.hp = a.max_hp
				Fx.heal(a.global_position + Vector3(0, 1.0, 0))
			game.toast("통구이를 나눴습니다 — 용병 전원 회복 · 새벽까지 공격 +%d%%" % int(Data.ROAST_DAMAGE * 100.0), Color(1.0, 0.8, 0.5))
		"victory_roar":
			night["roar_on"] = true
			game.toast("승리의 함성 — 적을 쓰러뜨릴수록 오크가 빨라집니다", Color(1.0, 0.6, 0.45))
		"stone_song":
			var t := _song_time()
			_song_until = _clock + t
			stats["songs"] += 1
			Fx.celebrate(game.world.lodge.global_position + Vector3(0, 2.0, 0), Color(0.8, 0.85, 1.0), 1.2)
			game.sounds.play_or("stone_song", "card_play")
			game.toast("돌 속의 노래 — %d초 동안 시설이 피해를 받지 않습니다" % int(t), Color(0.8, 0.88, 1.0))
		"pilgrim_blessing":
			var gone := 0
			for e in _hand_corruptions():
				game.cards.remove_uid(e["uid"])
				gone += 1
			if game.get("reputation") != null:
				game.reputation.shift(Data.BLESSING_REPUTATION, "순례자의 축복")
			Fx.celebrate(game.player.global_position + Vector3(0, 1.2, 0), Color(1.0, 0.95, 0.75), 0.8)
			game.toast("순례자의 축복 — 침식 %d장을 정화하고 산장의 소문이 밝아졌습니다" % gone, Color(1.0, 0.95, 0.75))
		"guild_writ":
			_open_writ()
		"crest_banner":
			banner_up = true
			game.toast("여러 문장이 박힌 깃발을 산장에 걸었습니다", Color(1.0, 0.9, 0.6))
		"blood_oath":
			var a = plan["ally"]
			oath_persons.append(a.person)
			_add_person_buff(a.person, Data.OATH_HP, 0.0, Data.OATH_DAMAGE)
			Fx.celebrate(a.global_position + Vector3(0, 1.4, 0), Color(1.0, 0.4, 0.35), 0.8)
			game.toast("%s이(가) 피의 맹세를 맺었습니다 — 이제 떠나지도, 바쳐지지도 않습니다" % a.display_name(), Color(1.0, 0.55, 0.45))
		"stone_wall", "mine_prop":
			_build(id, plan["pos"])
			game.toast("%s을(를) 세웠습니다" % card_name(id), Color(0.85, 0.85, 0.9))
		"village_militia":
			var p: Vector3 = plan["pos"]
			for i in Data.MILITIA_COUNT:
				spawn_summon("militia", p + Vector3(cos(PI * i), 0, sin(PI * i)) * 0.7, "militia")
			stats["militia"] += Data.MILITIA_COUNT
			game.toast("마을 민병 %d명이 창을 들고 왔습니다" % Data.MILITIA_COUNT, Color(1.0, 0.9, 0.65))
	game.sounds.play_or("card_play", "card_play")
	return plan


## 흑맥주·전투 식량: 새벽까지 최대 체력 +pct(새벽에 되돌림).
func _ale(pct: float, key: String) -> void:
	night[key] = true
	for a in mercs():
		_ale_apply(a, pct)


func _ale_apply(a, pct: float) -> void:
	var add: float = a.max_hp * pct
	a.max_hp += add
	a.hp += add
	var k: int = a.get_instance_id()
	_ale_hp[k] = float(_ale_hp.get(k, 0.0)) + add
	Fx.heal(a.global_position + Vector3(0, 1.0, 0))


# ───────────────────────── 영구 강화(인물 단위) ─────────────────────────

func _add_person_buff(person: String, hp_pct: float, hp_flat: float, dmg: float) -> void:
	var b: Dictionary = person_buffs.get(person, {"hp_pct": 0.0, "hp_flat": 0.0, "dmg": 0.0})
	b["hp_pct"] = float(b["hp_pct"]) + hp_pct
	b["hp_flat"] = float(b["hp_flat"]) + hp_flat
	b["dmg"] = float(b["dmg"]) + dmg
	person_buffs[person] = b
	# 지금 활동 중이면 바로 반영(최대 체력 증가분만큼 체력도)
	for a in mercs():
		if a.person == person:
			var base := float(Cfg.JOB_HP.get(a.job, Cfg.MERC_HP))
			var add := base * hp_pct + hp_flat
			a.max_hp += add
			a.hp += add


## 용병이 월드에 나옴(ally._ready): 영구 강화와 그 밤의 흑맥주를 반영한다.
func on_ally_spawned(a) -> void:
	if a.kind != "merc":
		return
	var b: Dictionary = person_buffs.get(a.person, {})
	if not b.is_empty():
		var add: float = a.max_hp * float(b.get("hp_pct", 0.0)) + float(b.get("hp_flat", 0.0))
		a.max_hp += add
		a.hp += add
	if night.get("ration", false):
		_ale_apply(a, Data.RATION_HP)
	elif night.get("ale", false):
		_ale_apply(a, Data.ALE_HP)


func dismiss_block_reason(person: String) -> String:
	if person in oath_persons:
		return "피의 맹세를 맺은 용병은 떠나지 않음"
	return ""


# ───────────────────────── 처치·쓰러짐 ─────────────────────────

## 적 처치(kill_gold.on_enemy_killed 가 부른다): 승리의 함성 중첩.
func on_enemy_killed(_enemy) -> void:
	if night.get("roar_on", false):
		night["roar"] = mini(int(night.get("roar", 0)) + 1, Data.ROAR_MAX_STACKS)


## 처치 골드 배율(뼈 던지기 '운명을 받아들인다').
func kill_gold_mult() -> int:
	return Data.FATE_GOLD_MULT if night.get("fate", false) and _night() else 1


## 용병이 쓰러짐(contracts.on_ally_died, 장비가 풀리기 전): 재로 그린 문양.
func on_ally_died(a) -> void:
	var w := _worn(a, "ash_sigil")
	if w.is_empty() or _sigil_used.has(w["uid"]):
		return
	_sigil_used[w["uid"]] = true
	var n := 0
	for e in game.get_tree().get_nodes_in_group("enemies"):
		if not e.dead and _flat(e.global_position, a.global_position) <= Data.SIGIL_RADIUS:
			scare(e, a.global_position, Data.SIGIL_FEAR, Data.SIGIL_PUSH)
			n += 1
	stats["sigils"] += 1
	Fx.explosion(game.actors, a.global_position, 1.2)
	game.toast("재로 그린 문양이 타오릅니다 — 적 %d마리가 겁에 질려 달아납니다" % n, Color(1.0, 0.7, 0.45))


## 벌목 금지(숲의 약속): 오늘이 약속한 날이면 사유.
func lumber_block_reason() -> String:
	if game.get("session") != null and game.session.day() == lumber_ban_day:
		return "숲의 약속 — 오늘은 나무를 베지 않기로 했습니다"
	return ""


## 고용비 가감(검은 소문·평판).
func hire_cost_delta() -> int:
	var d := 0
	for e in game.cards.hand():
		if e["id"] == "black_rumor":
			d += Data.RUMOR_HIRE_COST
	if game.get("reputation") != null:
		d += game.reputation.hire_cost_delta()
	return d


# ───────────────────────── 꿈 기록장(아침 드로우) ─────────────────────────

## card_inventory.morning_draw 가 먼저 부른다. 마녀가 꿈 기록장을 끼고 있으면 2장 중 1장을 고르는 창을 띄우고 true.
func dream_draw() -> bool:
	if not witch_wears("dream_journal") or game.cards.hand_full():
		return false
	var choices: Array = game.cards.draw_choices(2)
	if choices.size() < 2:
		return false
	var items: Array = choices.map(func(e): return {"id": e["id"], "uid": e["uid"], "person": e.get("person", "")})
	open_choice("꿈 기록장", "간밤의 꿈에서 본 카드 두 장 — 하나를 손패로 가져옵니다", items, func(i: int) -> bool:
		var got: Dictionary = game.cards.draw_uid(int(items[i]["uid"]))
		if not got.is_empty():
			game.toast("꿈 기록장 — '%s'을(를) 골랐습니다" % card_name(got["id"]), Color(0.8, 0.95, 0.85))
		return true)
	return true


# ───────────────────────── 선택 창(공용) ─────────────────────────

## 카드 선택 창을 연다(다른 창·대화가 열려 있으면 닫힌 뒤). items: [{id, uid?, person?, price?, texture?, label?}]
## on_pick(i) -> bool: true 면 창을 닫는다(가게처럼 계속 고르는 창은 false). closable 이면 닫기 버튼이 있다.
func open_choice(title: String, hint: String, items: Array, on_pick: Callable, closable := false, close_text := "그만두기", on_close := Callable()) -> void:
	_pending.append({"title": title, "hint": hint, "items": items, "pick": on_pick, "closable": closable, "close_text": close_text, "close": on_close})
	_try_open()


func _modal_busy() -> bool:
	for k in ["offer_ui", "spellbook_ui", "mulligan_ui", "altar_ui", "chest_ui"]:
		var ui = game.get(k)
		if ui != null and ui.get("active") == true:
			return true
	var gu = game.get("guest_ui")
	if gu != null and int(gu.get("active_uid")) >= 0:
		return true
	return false


func _try_open() -> void:
	if _pending.is_empty() or _modal_busy() or game.get("offer_ui") == null:
		return
	var c: Dictionary = _pending.pop_front()
	game.offer_ui.open_choice(c["title"], c["hint"], c["items"], c["pick"], c["closable"], c["close_text"], c["close"])


func has_pending() -> bool:
	return not _pending.is_empty()


# ── 요정의 맞바꿈 ──

func _open_swap() -> void:
	var cands := _swap_candidates(-1)
	if cands.is_empty():
		return
	var items: Array = cands.map(func(e): return {"id": e["id"], "uid": e["uid"], "person": e.get("person", "")})
	open_choice("요정의 맞바꿈", "내놓을 카드 한 장을 고르세요 — 다른 계열의 카드가 돌아옵니다", items, func(i: int) -> bool:
		swap(int(items[i]["uid"]))
		return true)


## 손패 카드 uid 를 내고 다른 계열 카드 1장(10% 침식). 반환: 받은 카드 id.
func swap(uid: int) -> String:
	var e: Dictionary = game.cards.get_entry(uid)
	if e.is_empty():
		return ""
	var from := affinity_of(e["id"])
	if game.cards.is_job(e["id"]):
		game.cards.remove_uid(uid)   # 계약 카드는 버림패로 돌지 않고 떠난다
	else:
		game.cards.consume(uid, 1, false)  # 교환 재료는 요정 카드 사용의 일부라 스택에 따로 세지 않는다
	var got := ""
	if _rng.randf() < Data.SWAP_CORRUPT_CHANCE:
		got = Data.SWAP_CORRUPTIONS[_rng.randi_range(0, Data.SWAP_CORRUPTIONS.size() - 1)]
	else:
		got = random_card(Data.POOLS.keys().filter(func(k): return k != from))
	game.cards.add(got)
	stats["swaps"] += 1
	Fx.poof(game.player.global_position + Vector3(0, 1.2, 0), Color(0.7, 1.0, 0.7), 0.7)
	game.toast("요정의 맞바꿈 — '%s'을(를) 내주고 '%s'을(를) 받았습니다" % [card_name(e["id"]), card_name(got)], Color(0.75, 1.0, 0.75) if not game.cards.is_corruption(got) else Color(0.8, 0.55, 1.0))
	return got


## 카드의 계열(카탈로그 race). 기본 카드는 "".
func affinity_of(id: String) -> String:
	return str(game.cards.def(id).get("race", ""))


## 그 종족들 풀에서 무작위 카드 하나.
func random_card(races: Array) -> String:
	var pool: Array = []
	for r in races:
		pool.append_array(Data.POOLS.get(r, []))
	pool = pool.filter(func(id): return game.cards.defs.has(id))
	return pool[_rng.randi_range(0, pool.size() - 1)] if not pool.is_empty() else ""


func random_cards(races: Array, n: int) -> Array:
	var pool: Array = []
	for r in races:
		pool.append_array(Data.POOLS.get(r, []))
	pool = pool.filter(func(id): return game.cards.defs.has(id))
	pool.shuffle()
	return pool.slice(0, mini(n, pool.size()))


# ── 길드 증서 ──

func _open_writ() -> void:
	var targets := _writ_targets()
	var items: Array = targets.map(func(e): return {"id": e["id"], "uid": e["uid"], "person": e.get("person", ""), "label": "%s\n%s" % [e.get("person", ""), Cfg.JOB_NAMES.get(e["id"], "")]})
	open_choice("길드 증서", "직업을 바꿀 계약 카드를 고르세요", items, func(i: int) -> bool:
		var uid := int(items[i]["uid"])
		var cur: String = items[i]["id"]
		var person: String = items[i]["person"]
		var jobs: Array = Cfg.JOB_CARDS.filter(func(j): return j != cur)
		var job_items: Array = jobs.map(func(j): return {"id": j, "person": person, "label": Cfg.JOB_NAMES.get(j, j)})
		open_choice("길드 증서 — %s" % person, "새 직업을 고르세요", job_items, func(k: int) -> bool:
			rewrite_job(uid, job_items[k]["id"])
			return true)
		return true)


## 계약 카드 uid 의 직업을 바꾼다.
func rewrite_job(uid: int, job: String) -> bool:
	var e: Dictionary = game.cards.get_entry(uid)
	if e.is_empty() or not game.cards.is_job(e["id"]) or not job in Cfg.JOB_CARDS:
		return false
	var before: String = e["id"]
	# id 만 바꾸면 손패·주머니가 그 인물 종족의 새 직업 카드 그림으로 통째로 바뀐다(card_hand._reskin, card_catalog.race_texture).
	e["id"] = job
	stats["writs"] += 1
	game.cards.changed.emit()
	game.toast("길드 증서 — %s의 계약을 %s에서 %s(으)로 고쳐 썼습니다" % [e.get("person", ""), Cfg.JOB_NAMES.get(before, before), Cfg.JOB_NAMES.get(job, job)], Color(1.0, 0.92, 0.7))
	return true


# ───────────────────────── 사건(용병 이벤트 merc:race:*) ─────────────────────────

## 이벤트 대사의 %s 채우기(뼈 던지기 = 오늘 밤 적 구성).
func event_text(key: String) -> String:
	if key == "o_bones":
		return forecast_text(game.session.day())
	return ""


const KIND_NAMES := {"spider": "거미", "forest": "숲의 괴물", "insect": "맹독 곤충", "cultist": "침식된 자", "siege": "공성 괴물", "boss": "보스"}
const PREPARE_CARD := {"spider": "resin_torch", "forest": "vine_snare", "insect": "firefly_swarm", "cultist": "moss_bandage", "siege": "vine_snare", "boss": "frost_rune"}


## 그 밤 적 구성 {kind: 수}.
func forecast(day: int) -> Dictionary:
	var out := {}
	var cfg: Dictionary = ChapterData.day_cfg(day)
	for g in cfg.get("groups", []):
		var k := ChapterData.group_kind(g)
		out[k] = int(out.get(k, 0)) + int(g[1])
	return out


func forecast_text(day: int) -> String:
	var f := forecast(day)
	var parts: Array = []
	for k in f:
		parts.append("%s %d" % [KIND_NAMES.get(k, k), f[k]])
	return " · ".join(parts) if not parts.is_empty() else "고요한 밤"


## 대비 카드: 그 밤 가장 많은 적에 맞는 카드.
func prepare_card(day: int) -> String:
	var f := forecast(day)
	var best := ""
	var n := -1
	for k in f:
		if int(f[k]) > n:
			n = int(f[k])
			best = k
	var id: String = PREPARE_CARD.get(best, "vine_snare")
	return id if game.cards.defs.has(id) else "vine_snare"


## merc_events.apply_effect 가 넘긴다. speaker: 말을 건 용병 {person, id, race}. 실패면 false(fail_reply).
func event_effect(entry: Dictionary, what: String, speaker: Dictionary) -> bool:
	var day: int = game.session.day()
	match what:
		"promise":
			lumber_ban_day = day + 1
			for id in random_cards(["fairy"], Data.PROMISE_CARDS):
				game.cards.add(id)
			game.toast("숲의 약속 — 요정 카드 %d장을 받았습니다. 내일 하루는 벌목 금지" % Data.PROMISE_CARDS, Color(0.75, 1.0, 0.75))
		"promise_refuse":
			fairy_pause_day = day + 1
			game.toast("요정들이 토라졌습니다 — 내일은 요정 이야기가 없습니다", Color(0.8, 0.9, 0.8))
		"bone_prepare":
			var id := prepare_card(day)
			game.cards.add(id)
			game.toast("뼈 던지기 — 대비 카드 '%s'" % card_name(id), Color(1.0, 0.85, 0.6))
		"bone_fate":
			night["fate"] = true
			game.toast("운명을 받아들였습니다 — 오늘 밤 처치 골드 ×%d" % Data.FATE_GOLD_MULT, Color(1.0, 0.8, 0.45))
		"path_help":
			return send_away(str(speaker.get("person", "")), "path")
		"sleep":
			return send_away(str(speaker.get("person", "")), "sleep")
		"letter":
			_open_letter()
		"records_read":
			var ids := random_cards(Data.POOLS.keys(), Data.RECORDS_CHOICES)
			if ids.is_empty():
				return false
			_offer_cards("오래된 기록", "기록 속 카드 세 장 — 한 장을 고르세요", ids)
		"records_cover":
			var gone: String = game.chapter.purify_one() if game.get("chapter") != null else ""
			if gone != "":
				game.toast("오래된 기록을 덮었습니다 — '%s' 정화" % gone, Color(0.85, 0.75, 1.0))
			else:
				game.economy._add_gold(Data.RECORDS_NO_CORRUPTION_GOLD)
				game.toast("정화할 것이 없어 오스윈이 사례했습니다 +%dG" % Data.RECORDS_NO_CORRUPTION_GOLD, Color(1.0, 0.85, 0.45))
		"wagon":
			_open_wagon()
		"festival":
			if not game.economy.spend(Data.FESTIVAL_COST):
				return false
			var seen := {}
			for r in roster():
				if seen.has(r["person"]):
					continue
				seen[r["person"]] = true
				_add_person_buff(r["person"], 0.0, Data.FESTIVAL_HP, Data.FESTIVAL_DAMAGE)
			Fx.celebrate(game.world.lodge.global_position + Vector3(0, 2.0, 0), Color(1.0, 0.85, 0.5), 1.4)
			game.toast("산장의 축제 — 용병 %d명이 영구히 강해졌습니다(최대 체력 +%d · 공격 +%d%%)" % [seen.size(), int(Data.FESTIVAL_HP), int(Data.FESTIVAL_DAMAGE * 100.0)], Color(1.0, 0.88, 0.5))
		"gift":
			var hired := {}
			for r in roster():
				hired[r["race"]] = true
			var races: Array = Data.POOLS.keys().filter(func(k): return not hired.has(k))
			if races.is_empty():
				races = Data.POOLS.keys()
			var id := random_card(races)
			game.cards.add(id)
			game.toast("낯선 손님의 선물 — '%s'(%s)" % [card_name(id), Races.name_of(affinity_of(id))], Color(0.9, 0.95, 1.0))
		"cleanup":
			var pocket: Array = game.cards.pocket().filter(func(e): return not game.cards.is_job(e["id"]))
			if pocket.is_empty():
				return false
			var items: Array = pocket.map(func(e): return {"id": e["id"], "uid": e["uid"], "person": e.get("person", "")})
			open_choice("산장 대청소", "주머니에서 영구히 없앨 카드 한 장을 고르세요", items, func(i: int) -> bool:
				var gone_id: String = game.cards.remove_uid(int(items[i]["uid"]))
				stats["cleaned"] += 1
				game.toast("산장 대청소 — '%s'을(를) 치웠습니다" % card_name(gone_id), Color(0.95, 0.9, 0.8))
				return true)
		_:
			return false
	return true


func _offer_cards(title: String, hint: String, ids: Array) -> void:
	var items: Array = ids.map(func(id): return {"id": id})
	open_choice(title, hint, items, func(i: int) -> bool:
		game.cards.add(items[i]["id"])
		game.toast("'%s' 카드를 받았습니다" % card_name(items[i]["id"]), Color(1.0, 0.95, 0.75))
		return true)


func _open_letter() -> void:
	var items: Array = []
	for r in RACE_ORDER:
		var path := Catalog.race_texture_path("warrior", r)
		items.append({"id": "warrior", "race": r, "texture": path, "label": Races.name_of(r)})
	open_choice("소개장", "누구를 소개받을까요? 다음 고용 손님 한 명이 그 종족으로 옵니다", items, func(i: int) -> bool:
		write_letter(items[i]["race"])
		return true)


func write_letter(race: String) -> void:
	game.economy.forced_hire_race = race
	game.toast("소개장 — 다음 고용 손님은 %s입니다" % Races.name_of(race), Color(1.0, 0.92, 0.7))


func _open_wagon() -> void:
	var hired := {}
	for r in roster():
		hired[r["race"]] = true
	var races: Array = Data.POOLS.keys().filter(func(k): return not hired.has(k))
	if races.size() < 2:
		races = Data.POOLS.keys()
	var ids := random_cards(races, Data.WAGON_OFFERS)
	var items: Array = ids.map(func(id): return {"id": id, "price": Data.WAGON_PRICE, "sold": false})
	var on_buy := func(i: int) -> bool:
		buy_wagon(items[i])
		return false
	open_choice("상인 마차", "세라의 마차 — 다른 종족 카드를 장마다 %dG에 팝니다" % Data.WAGON_PRICE, items, on_buy, true, "마차를 보낸다")


func buy_wagon(item: Dictionary) -> bool:
	if item.get("sold", false):
		return false
	if not game.economy.spend(int(item["price"])):
		game.toast("골드가 부족합니다", Color(1.0, 0.7, 0.7))
		return false
	item["sold"] = true
	game.cards.add(item["id"])
	stats["wagon_bought"] += 1
	game.toast("상인 마차 — '%s'을(를) 샀습니다 (−%dG)" % [card_name(item["id"]), int(item["price"])], Color(1.0, 0.9, 0.6))
	return true


# ── 떠났다 돌아오는 용병(조상의 길·겨울잠) ──

## 이 인물을 다음 새벽까지 떠나보낸다. 활동 중이면 월드를 떠나고, 계약 카드면 카드가 빠진다. 돌아오면 계약 카드로 손패에.
func send_away(person: String, reward: String) -> bool:
	if person == "":
		return false
	var job := ""
	for a in mercs():
		if a.person == person:
			job = a.job
			a.dismiss()
			break
	if job == "":
		for e in game.cards.entries.duplicate():
			if game.cards.is_job(e["id"]) and e.get("person", "") == person:
				job = e["id"]
				game.cards.remove_uid(e["uid"])
				break
	if job == "":
		return false
	away.append({"person": person, "job": job, "return_day": game.session.day() + 1, "reward": reward})
	game.toast("%s이(가) %s — 내일 새벽에 돌아옵니다" % [person, "조상의 길을 떠났습니다" if reward == "path" else "깊은 겨울잠에 들었습니다"], Color(0.9, 0.85, 0.75))
	return true


func is_away(person: String) -> bool:
	return away.any(func(w): return w["person"] == person)


func _return_away(day: int) -> void:
	for w in away.duplicate():
		if day < int(w["return_day"]):
			continue
		away.erase(w)
		if w["reward"] == "path":
			_add_person_buff(w["person"], Data.PATH_HP, 0.0, Data.PATH_DAMAGE)
		else:
			_add_person_buff(w["person"], 0.0, Data.SLEEP_HP, 0.0)
		game.cards.add(w["job"], 1, w["person"])
		game.toast("%s이(가) 돌아왔습니다 — %s · 계약 카드가 손패로" % [w["person"], "조상의 힘을 얻음(최대 체력 +%d%% · 공격 +%d%%)" % [int(Data.PATH_HP * 100.0), int(Data.PATH_DAMAGE * 100.0)] if w["reward"] == "path" else "푹 자고 일어남(최대 체력 +%d)" % int(Data.SLEEP_HP)], Color(1.0, 0.9, 0.65))


# ───────────────────────── 낮밤 전환 ─────────────────────────

func _process(delta: float) -> void:
	if game == null or game.session == null:
		return
	if not game.get_tree().paused:
		_clock += delta
	if not _pending.is_empty():
		_try_open()


func _on_state(state: int) -> void:
	match state:
		SessionScript.State.CLEARING:
			for s in summons():
				s.leave("새벽")
		SessionScript.State.PREP:
			on_dawn(game.session.day())


## 새벽: 밤 버프 정리, 소환물 귀가, 망치 수리, 돌 성벽 자동 수리, 떠난 용병 귀환.
func on_dawn(day: int) -> void:
	for s in summons():
		s.leave("새벽")
	# 흑맥주·전투 식량으로 늘린 최대 체력 되돌리기
	for a in mercs():
		var k: int = a.get_instance_id()
		if _ale_hp.has(k):
			a.max_hp -= float(_ale_hp[k])
			a.hp = clampf(a.hp, 1.0, a.max_hp)
	_ale_hp.clear()
	night.clear()
	_sigil_used.clear()
	_fear_until.clear()
	_song_until = -1.0
	_hammer_repairs()
	if race_count("dwarf") >= Data.WALL_REPAIR_AT:
		for f in facilities("stone_wall"):
			if f.repair(Data.WALL_REPAIR) > 0.0:
				stats["wall_repairs"] += 1
	_return_away(day)
	if day == lumber_ban_day:
		game.toast("숲의 약속 — 오늘은 나무를 베지 않습니다", Color(0.75, 1.0, 0.75))


## 룬 새긴 망치: 착용자마다 손패 목재 1을 써서 가장 많이 상한 곳(산장·카드 시설·고물 방책)을 수리.
func _hammer_repairs() -> void:
	for a in mercs():
		if _worn(a, "rune_hammer").is_empty() or game.cards.hand_count_of("timber") < 1:
			continue
		var best = null
		var best_missing := 0.5
		var cands: Array = [game.world.lodge]
		cands.append_array(facilities())
		cands.append_array(game.get_tree().get_nodes_in_group("junk_barricades").filter(func(b): return not b.dead))
		for c in cands:
			var missing: float = float(c.max_hp) - float(c.hp)
			if missing > best_missing:
				best_missing = missing
				best = c
		if best == null:
			continue
		if not game.cards.consume_id("timber", 1):
			continue
		var amount := Data.HAMMER_REPAIR * (Data.HAMMER_DWARF_MULT if is_race(a, "dwarf") else 1.0)
		if best == game.world.lodge:
			amount *= Cfg.LODGE_REPAIR_EFFICIENCY
		var got := 0.0
		if best.has_method("repair"):
			got = best.repair(amount)
		else:
			got = minf(amount, best.max_hp - best.hp)
			best.hp += got
		stats["hammer_repairs"] += 1
		game.toast("%s의 룬 새긴 망치 — %s 체력 +%d (목재 1)" % [a.display_name(), "산장" if best == game.world.lodge else best.display_name(), int(got)], Color(1.0, 0.85, 0.6))
