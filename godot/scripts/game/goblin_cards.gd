extends "res://scripts/game/card_module.gd"
## 고블린 카드 v1(1차 검수 2026-10-19). 기획: docs/deck-archetypes-v01.md §4.1 · 적용 기록: docs/goblin-cards-v01.md
## CardUseResolver 가 고블린 카드를 이 모듈로 넘긴다(handles → evaluate → commit). 장비 4종은 공용 장비 경로(equipment.gd)로 끼우고,
## 장착 효과(호루라기 졸개·냄비 투구 감쇠)만 여기서 처리한다. 졸개·미끼·덫·방책의 수명과 새벽 정리도 여기서 한다.

const GoblinData := preload("res://scripts/game/goblin_data.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")
const MinionScript := preload("res://scripts/actors/goblin_minion.gd")
const LureScript := preload("res://scripts/actors/goblin_lure.gd")
const TrapScript := preload("res://scripts/actors/goblin_trap.gd")
const BarricadeScript := preload("res://scripts/actors/junk_barricade.gd")
const Fx := preload("res://scripts/visual/fx.gd")

## 이 모듈이 판정·사용을 맡는 카드(장비 4종은 equipment.gd 경로).
const CARD_IDS := ["goblin_gang", "goblin_firecracker", "dud_bomb", "goblin_rush", "shiny_lure",
	"junk_barricade", "pikl_traps", "junk_sack", "scrap"]
const EQUIP_IDS := ["graz_whistle", "pot_helmet", "mala_coin_scale", "mala_monocle"]

var helmets: Dictionary = {}       # 냄비 투구 카드 uid → {"hits": 받은 횟수, "worn": 고블린이 10%로 버티는 중}
var debts: Array = []              # 빚 문서 [{person, due_day, amount}]
var _whistle_t: Dictionary = {}    # 호루라기 착용자 instance_id → 남은 시간
var _rng := RandomNumberGenerator.new()
var stats := {"minions": 0, "firecrackers": 0, "duds_given": 0, "rushes": 0, "lures": 0, "traps_sprung": 0, "helmets_broken": 0}


func _ready() -> void:
	name = "GoblinCards"
	_rng.randomize()
	if game.get("session") != null and game.session != null:
		game.session.state_changed.connect(_on_state)


func handles(id: String) -> bool:
	return id in CARD_IDS


# ───────────────────────── 고블린 용병 수(종족 시너지) ─────────────────────────

## 데리고 있는 고블린 용병 수: 활동 중인 고블린 용병 + 아직 쓰지 않은 고블린 계약 카드.
func goblin_count() -> int:
	var n := 0
	if game.get("contracts") != null:
		for a in game.contracts.allies:
			if is_instance_valid(a) and not a.dead and a.kind == "merc" and GuestProfiles.race_of(a.person) == GoblinData.RACE:
				n += 1
	if game.get("cards") != null:
		for e in game.cards.entries:
			if game.cards.is_job(e["id"]) and GuestProfiles.race_of(str(e.get("person", ""))) == GoblinData.RACE:
				n += 1
	return n


func is_goblin(holder) -> bool:
	return holder != null and holder.get("kind") == "merc" and GuestProfiles.race_of(str(holder.get("person"))) == GoblinData.RACE


# ───────────────────────── 졸개 ─────────────────────────

func minions() -> Array:
	return game.get_tree().get_nodes_in_group("goblin_minions").filter(func(m): return not m.dead)


func spawn_minion(pos: Vector3, source: String, by = null):
	if minions().size() >= GoblinData.MINION_CAP:
		return null
	var m := MinionScript.new()
	m.setup(game, pos, source, by)
	game.actors.add_child(m)
	stats["minions"] += 1
	return m


## 졸개 피해 배율: 반짝이 미끼 반경 안의 적이면 +50%.
func minion_damage_mult(enemy) -> float:
	for l in game.get_tree().get_nodes_in_group("allies"):
		if l.get("kind") == "goblin_lure" and l.covers(enemy.global_position):
			return GoblinData.LURE_MINION_BONUS
	return 1.0


# ───────────────────────── 적 제어 공용 ─────────────────────────

## 기절: 이동을 멈추고 공격 대기 시간을 늘린다(적 스크립트를 바꾸지 않는 방식).
func stun(e, time: float) -> void:
	if e == null or e.dead:
		return
	if e.has_method("apply_slow"):
		e.apply_slow("goblin_stun", 0.0, time)
	if e.get("attack_cd") != null:
		e.attack_cd = maxf(float(e.attack_cd), time)
	Fx.float_text(game.actors, e.global_position + Vector3(0, 1.6, 0), "기절", Color(1.0, 0.95, 0.6))


## 범위 안 적에게 피해 + 기절. 반환: 맞은 수.
func stun_area(center: Vector3, radius: float, time: float, damage: float) -> int:
	var n := 0
	for e in game.get_tree().get_nodes_in_group("enemies"):
		if e.dead or _flat(e.global_position, center) > radius:
			continue
		if damage > 0.0:
			e.take_damage(damage)
		if not e.dead:
			stun(e, time)
		n += 1
	return n


func _enemies_within(center: Vector3, radius: float) -> int:
	var n := 0
	for e in game.get_tree().get_nodes_in_group("enemies"):
		if not e.dead and _flat(e.global_position, center) <= radius:
			n += 1
	return n


# ───────────────────────── 판정(미리보기) ─────────────────────────

func _night_only(title: String):
	if game.session.state != SessionScript.State.COMBAT:
		return _fail("%s은(는) 밤 전투 중에만 쓸 수 있습니다" % title)
	return null


func evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var id: String = entry["id"]
	if id == "scrap":
		return r._eval_wool(entry, sp)  # 쇠붙이는 양털·가죽과 같은 판매 경로(action "sell")
	var plan := _evaluate(entry, sp, r)
	if plan.get("ok", false):
		plan["action"] = "goblin"
		plan["goblin"] = id
	return plan


func _evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var id: String = entry["id"]
	var gc := goblin_count()
	match id:
		"junk_sack":
			if game.session.state != SessionScript.State.PREP:
				return _fail("잡동사니 자루는 낮에 엽니다")
			return {"ok": true, "pos": game.player.global_position, "title": "잡동사니 자루",
				"lines": ["무작위 자원 %d~%d개 · 가끔 쇠붙이" % [GoblinData.SACK_MIN, GoblinData.SACK_MAX], "자루 1개 소비"]}
	var night := ["goblin_gang", "goblin_firecracker", "dud_bomb", "goblin_rush", "shiny_lure"]
	if id in night:
		var f = _night_only(game.cards.def(id).get("name", id))
		if f != null:
			return f
	var p = _point(sp, r)
	if p is String:
		return _fail(p)
	match id:
		"goblin_gang":
			var n := GoblinData.GANG_COUNT_BONUS if gc >= GoblinData.GANG_BONUS_AT else GoblinData.GANG_COUNT
			return {"ok": true, "pos": p, "radius": 1.2, "title": "사촌 패거리",
				"lines": ["졸개 %d마리 소환 · 새벽에 돌아감%s" % [n, " (고블린 용병 %d명 → +1)" % gc if gc >= GoblinData.GANG_BONUS_AT else ""],
					"지금 졸개 %d / 최대 %d · 카드 1장 소비" % [minions().size(), GoblinData.MINION_CAP]]}
		"goblin_firecracker":
			var duds := gc >= GoblinData.FIRECRACKER_DUD_AT
			return {"ok": true, "pos": p, "radius": GoblinData.FIRECRACKER_RADIUS, "title": "고블린 폭죽",
				"lines": ["반경 %.1fm · 피해 %d · 적이 %.1f초 겁먹어 물러남" % [GoblinData.FIRECRACKER_RADIUS, int(GoblinData.FIRECRACKER_DAMAGE), GoblinData.FIRECRACKER_FEAR],
					"%d%% 확률로 범위 안 아군도 피해 %d" % [int(GoblinData.FIRECRACKER_BACKFIRE * 100.0), int(GoblinData.FIRECRACKER_BACKFIRE_DAMAGE)],
					("고블린 용병 %d명 → 불발탄 %d장 획득" % [gc, GoblinData.FIRECRACKER_DUDS]) if duds else "범위 안의 적 %d마리 · 카드 1장 소비" % _enemies_within(p, GoblinData.FIRECRACKER_RADIUS)]}
		"dud_bomb":
			return {"ok": true, "pos": p, "radius": GoblinData.DUD_RADIUS, "title": "불발탄",
				"lines": ["반경 %.1fm · 피해 %d · %d초 기절" % [GoblinData.DUD_RADIUS, int(GoblinData.DUD_DAMAGE), int(GoblinData.DUD_STUN)],
					"범위 안의 적 %d마리 · 카드 1장 소비" % _enemies_within(p, GoblinData.DUD_RADIUS)]}
		"goblin_rush":
			var m := minions().size()
			if m == 0:
				return _fail("돌격할 졸개가 없습니다 — 사촌 패거리나 호루라기로 먼저 부르세요", p)
			return {"ok": true, "pos": p, "radius": GoblinData.RUSH_RADIUS, "title": "떼거리 돌격",
				"lines": ["졸개 %d마리가 돌진 · 반경 %.1fm 피해 %d" % [m, GoblinData.RUSH_RADIUS, int(GoblinData.RUSH_DAMAGE_PER * m)],
					"범위 안의 적 %d마리 · 카드 1장 소비" % _enemies_within(p, GoblinData.RUSH_RADIUS)]}
		"shiny_lure":
			return {"ok": true, "pos": p, "radius": GoblinData.LURE_PULL, "title": "반짝이 미끼",
				"lines": ["%d초 동안 반경 %dm 적이 미끼로 몰림" % [int(GoblinData.LURE_TIME), int(GoblinData.LURE_PULL)],
					"끝나면 터져 반경 %dm 적 %d초 눈부심 · 미끼 근처 졸개 피해 +50%%" % [int(GoblinData.LURE_BLIND_RADIUS), int(GoblinData.LURE_BLIND)], "카드 1장 소비"]}
		"junk_barricade":
			if game.cards.hand_count_of("timber") < GoblinData.BARRICADE_TIMBER:
				return _fail("손패에 목재가 %d개 필요합니다" % GoblinData.BARRICADE_TIMBER, p)
			return {"ok": true, "pos": p, "title": "고물 방책",
				"lines": ["체력 %d의 허술한 방책 · 적이 먼저 두드림" % int(GoblinData.BARRICADE_HP),
					"%d일 뒤 새벽에 무너짐 · 카드 1장 + 목재 %d 소비" % [GoblinData.BARRICADE_DAYS, GoblinData.BARRICADE_TIMBER]]}
		"pikl_traps":
			return {"ok": true, "pos": p, "radius": GoblinData.TRAP_SPREAD, "title": "피클의 덫 꾸러미",
				"lines": ["작은 덫 %d개 · 밟은 적 피해 %d, %.1f초 멈춤" % [GoblinData.TRAP_COUNT, int(GoblinData.TRAP_DAMAGE), GoblinData.TRAP_STUN],
					("고블린 용병이 있어 새벽마다 다시 깖" if gc > 0 else "터진 덫은 새벽에 치움(고블린 용병이 있으면 다시 깖)"), "카드 1장 소비"]}
	return _fail("사용할 수 없는 카드입니다")


# ───────────────────────── 사용 확정 ─────────────────────────

func commit(uid: int, plan: Dictionary, r) -> Dictionary:
	var id: String = plan["goblin"]
	var p: Vector3 = plan["pos"]
	match id:
		"junk_sack":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			_open_sack()
		"goblin_gang":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			var n := GoblinData.GANG_COUNT_BONUS if goblin_count() >= GoblinData.GANG_BONUS_AT else GoblinData.GANG_COUNT
			var made := 0
			for i in n:
				var a := TAU * i / n
				if spawn_minion(p + Vector3(cos(a), 0, sin(a)) * 0.9, "gang") != null:
					made += 1
			game.toast("사촌 패거리 — 고블린 졸개 %d마리가 달려왔습니다" % made, Color(0.75, 1.0, 0.5))
		"goblin_firecracker":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			_firecracker(p)
		"dud_bomb":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			var hit := stun_area(p, GoblinData.DUD_RADIUS, GoblinData.DUD_STUN, GoblinData.DUD_DAMAGE)
			Fx.hit(p + Vector3(0, 0.4, 0), Color(0.9, 0.85, 0.6), true)
			game.sounds.play_or("goblin_dud", "card_burn")
			game.toast("불발탄 — 적 %d마리 기절" % hit, Color(1.0, 0.92, 0.6))
		"goblin_rush":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			_rush(p)
		"shiny_lure":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			var lure := LureScript.new()
			lure.game = game
			lure.position = p
			game.actors.add_child(lure)
			stats["lures"] += 1
			game.toast("반짝이 미끼 — 적들이 반짝임에 홀려 몰려듭니다", Color(1.0, 0.9, 0.55))
		"junk_barricade":
			if game.cards.hand_count_of("timber") < GoblinData.BARRICADE_TIMBER:
				return _fail("목재가 부족합니다")
			game.cards.begin_use()  # 방책 카드 + 목재 = 한 번의 사용(스택 1)
			var paid: bool = game.cards.consume(uid) and game.cards.consume_id("timber", GoblinData.BARRICADE_TIMBER)
			game.cards.end_use()
			if not paid:
				return _fail("카드가 없습니다")
			var b := BarricadeScript.new()
			b.game = game
			b.built_day = game.session.day()
			b.position = p
			b.rotation.y = atan2(p.x, p.z)  # 산장(원점) 쪽을 등지고 바깥을 향한다
			game.actors.add_child(b)
			game.toast("고물 방책을 세웠습니다 — %d일 뒤 새벽에 무너집니다" % GoblinData.BARRICADE_DAYS, Color(0.95, 0.82, 0.55))
		"pikl_traps":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			for i in GoblinData.TRAP_COUNT:
				var a := TAU * i / GoblinData.TRAP_COUNT + 0.5
				var t := TrapScript.new()
				t.game = game
				t.position = p + Vector3(cos(a), 0, sin(a)) * GoblinData.TRAP_SPREAD * 0.6
				game.actors.add_child(t)
			game.toast("피클의 덫 %d개를 깔았습니다" % GoblinData.TRAP_COUNT, Color(0.85, 0.95, 0.65))
		_:
			return _fail("사용할 수 없는 카드입니다")
	game.sounds.play_or("card_play", "card_play")
	return plan


func _open_sack() -> void:
	var n := _rng.randi_range(GoblinData.SACK_MIN, GoblinData.SACK_MAX)
	var got: Dictionary = {}
	for i in n:
		var id: String = "scrap" if _rng.randf() < GoblinData.SACK_SCRAP_CHANCE else GoblinData.SACK_POOL[_rng.randi_range(0, GoblinData.SACK_POOL.size() - 1)]
		got[id] = int(got.get(id, 0)) + 1
	var parts: Array = []
	for id in got:
		game.cards.add(id, got[id])
		parts.append("%s %d" % [game.cards.def(id).get("name", id), got[id]])
	Fx.celebrate(game.player.global_position + Vector3(0, 1.0, 0), Color(0.85, 0.75, 0.5), 0.6)
	game.toast("잡동사니 자루를 털었습니다 — %s" % ", ".join(parts), Color(0.95, 0.88, 0.65))


func _firecracker(p: Vector3) -> void:
	stats["firecrackers"] += 1
	var hit := 0
	for e in game.get_tree().get_nodes_in_group("enemies"):
		if e.dead or _flat(e.global_position, p) > GoblinData.FIRECRACKER_RADIUS:
			continue
		e.take_damage(GoblinData.FIRECRACKER_DAMAGE)
		hit += 1
		if e.dead:
			continue
		# 겁먹어 물러남: 폭발 반대쪽으로 밀리고 잠시 느려지며 공격을 멈춘다
		var away: Vector3 = e.global_position - p
		away.y = 0.0
		if away.length() < 0.01:
			away = Vector3(1, 0, 0)
		e.global_position += away.normalized() * GoblinData.FIRECRACKER_PUSH
		if e.has_method("apply_slow"):
			e.apply_slow("goblin_fear", 0.35, GoblinData.FIRECRACKER_FEAR)
		if e.get("attack_cd") != null:
			e.attack_cd = maxf(float(e.attack_cd), GoblinData.FIRECRACKER_FEAR)
	Fx.explosion(game.actors, p, GoblinData.FIRECRACKER_RADIUS * 0.6)
	game.sounds.play_or("goblin_firecracker", "card_burn")
	var backfire := ""
	if _rng.randf() < GoblinData.FIRECRACKER_BACKFIRE:
		var burnt := 0
		for a in game.get_tree().get_nodes_in_group("allies"):
			if a.dead or a.hidden or not a.has_method("take_damage") or a.get("kind") == "goblin_lure":
				continue
			if _flat(a.global_position, p) <= GoblinData.FIRECRACKER_RADIUS:
				a.take_damage(GoblinData.FIRECRACKER_BACKFIRE_DAMAGE)
				burnt += 1
		if burnt > 0:
			backfire = " · 앗, 아군 %d명도 그을렸습니다" % burnt
	var duds := ""
	if goblin_count() >= GoblinData.FIRECRACKER_DUD_AT:
		game.cards.add("dud_bomb", GoblinData.FIRECRACKER_DUDS)
		stats["duds_given"] += GoblinData.FIRECRACKER_DUDS
		duds = " · 불발탄 %d장 획득" % GoblinData.FIRECRACKER_DUDS
	game.toast("고블린 폭죽 — 적 %d마리%s%s" % [hit, backfire, duds], Color(1.0, 0.75, 0.4))


func _rush(p: Vector3) -> void:
	var ms := minions()
	var dmg := GoblinData.RUSH_DAMAGE_PER * ms.size()
	for m in ms:
		m.rush_to = p + Vector3(randf_range(-0.6, 0.6), 0, randf_range(-0.6, 0.6))
		m.target = null
	var hit := 0
	for e in game.get_tree().get_nodes_in_group("enemies"):
		if not e.dead and _flat(e.global_position, p) <= GoblinData.RUSH_RADIUS:
			e.take_damage(dmg)
			hit += 1
	stats["rushes"] += 1
	Fx.celebrate(p + Vector3(0, 0.4, 0), Color(0.7, 1.0, 0.45), GoblinData.RUSH_RADIUS / 2.5)
	game.sounds.play_or("goblin_rush", "ally_attack")
	game.toast("떼거리 돌격 — 졸개 %d마리 · 적 %d마리에게 피해 %d" % [ms.size(), hit, int(dmg)], Color(0.75, 1.0, 0.5))


# ───────────────────────── 장비 효과 ─────────────────────────

## 찌그러진 냄비 투구: equipment.taken_mult() 가 피격 순간마다 부른다. 회차별로 막고, 6회차에 부서진다(고블린은 10%로 남음).
func on_hit_taken_mult(holder) -> float:
	var w := _worn(holder, "pot_helmet")
	if w.is_empty():
		return 1.0
	var st: Dictionary = helmets.get(w["uid"], {"hits": 0, "worn": false})
	helmets[w["uid"]] = st
	if st["worn"]:
		return 1.0 - GoblinData.HELMET_GOBLIN_FLOOR
	var i: int = st["hits"]
	st["hits"] = i + 1
	if i < GoblinData.HELMET_BLOCK.size():
		var block: float = GoblinData.HELMET_BLOCK[i]
		Fx.float_text(game.actors, holder.global_position + Vector3(0, 2.2, 0), "투구 %d%%" % int(block * 100.0), Color(0.85, 0.9, 1.0))
		return 1.0 - block
	# 6번째 피해: 고블린은 펴서 버티고(10%), 다른 용병의 투구는 부서진다
	if is_goblin(holder):
		st["worn"] = true
		Fx.float_text(game.actors, holder.global_position + Vector3(0, 2.2, 0), "찌그러짐 10%", Color(0.8, 0.8, 0.75))
		return 1.0 - GoblinData.HELMET_GOBLIN_FLOOR
	holder.gear.erase(w["slot"])
	game.cards.release(w["uid"])
	helmets.erase(w["uid"])
	stats["helmets_broken"] += 1
	if game.get("equipment") != null:
		game.equipment.changed.emit()
	Fx.splinters(holder.global_position + Vector3(0, 1.6, 0))
	game.toast("%s의 찌그러진 냄비 투구가 부서졌습니다" % holder.display_name(), Color(1.0, 0.7, 0.55))
	return 1.0


func _process(delta: float) -> void:
	if game == null or game.session == null or game.session.state != SessionScript.State.COMBAT:
		return
	# 그라즈의 호루라기: 고블린 착용자가 살아 있는 밤 동안 20초마다 졸개 1마리(호루라기 하나당 최대 3마리)
	for a in game.contracts.allies:
		if not is_instance_valid(a) or a.dead or a.hidden or _worn(a, "graz_whistle").is_empty() or not is_goblin(a):
			continue
		var key: int = a.get_instance_id()
		var t: float = float(_whistle_t.get(key, 0.0)) - delta
		if t <= 0.0:
			t = GoblinData.WHISTLE_INTERVAL
			var mine := minions().filter(func(m): return m.source == "whistle" and m.owner_ally == a).size()
			if mine < GoblinData.WHISTLE_MAX and spawn_minion(a.global_position + Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)), "whistle", a) != null:
				game.sounds.play_or("goblin_whistle", "minion_spawn")
		_whistle_t[key] = t


# ───────────────────────── 낮밤 전환 ─────────────────────────

func _on_state(state: int) -> void:
	match state:
		SessionScript.State.COMBAT:
			_whistle_t.clear()  # 밤이 시작되면 첫 호루라기는 바로 분다
		SessionScript.State.CLEARING:
			for m in minions():
				m.leave("새벽")
		SessionScript.State.PREP:
			on_dawn(game.session.day())


## 새벽: 졸개 귀가, 덫 다시 깔기/치우기, 냄비 투구 수리, 고물 방책 붕괴, 빚 정산.
func on_dawn(day: int) -> void:
	for m in minions():
		m.leave("새벽")
	var gc := goblin_count()
	var rearmed := 0
	for t in game.get_tree().get_nodes_in_group("goblin_traps"):
		if t.armed:
			continue
		if gc > 0:
			t.rearm()
			rearmed += 1
		else:
			t.queue_free()
	if rearmed > 0:
		game.toast("고블린 용병이 터진 덫 %d개를 다시 깔았습니다" % rearmed, Color(0.85, 0.95, 0.65))
	for uid in helmets.keys():
		var holder = _helmet_holder(uid)
		if holder != null and is_goblin(holder):
			helmets[uid] = {"hits": 0, "worn": false}
	for b in game.get_tree().get_nodes_in_group("junk_barricades"):
		if day - int(b.built_day) >= GoblinData.BARRICADE_DAYS:
			b.collapse()
			game.toast("고물 방책이 저절로 무너졌습니다", Color(0.9, 0.8, 0.6))
	_settle_debts(day)


func _helmet_holder(uid: int):
	for a in game.contracts.allies:
		if is_instance_valid(a) and not a.dead:
			var w := _worn(a, "pot_helmet")
			if not w.is_empty() and w["uid"] == uid:
				return a
	return null


# ───────────────────────── 빚 문서 ─────────────────────────

func add_debt(person: String) -> void:
	debts.append({"person": person, "due_day": game.session.day() + GoblinData.DEBT_DAYS, "amount": GoblinData.DEBT_AMOUNT})


func _settle_debts(day: int) -> void:
	for d in debts.duplicate():
		if day < int(d["due_day"]):
			continue
		debts.erase(d)
		if game.economy.spend(int(d["amount"])):
			game.sounds.play("gold_spend")
			game.toast("빚 문서 — %dG를 갚았습니다. %s은(는) 계속 함께합니다" % [d["amount"], d["person"]], Color(1.0, 0.88, 0.55))
			continue
		# 못 갚음: 그 용병이 떠난다(활동 중이면 떠나고, 계약 카드면 없어진다)
		var gone := false
		for a in game.contracts.allies.duplicate():
			if is_instance_valid(a) and not a.dead and a.person == d["person"]:
				a.dismiss()
				gone = true
		for e in game.cards.entries.duplicate():
			if game.cards.is_job(e["id"]) and e.get("person", "") == d["person"]:
				game.cards.remove_uid(e["uid"])
				gone = true
		game.toast("빚 문서 — %dG를 갚지 못해 %s이(가) 떠났습니다" % [d["amount"], d["person"]] if gone else "빚 문서 — 갚지 못했지만 %s은(는) 이미 떠난 뒤였습니다" % d["person"], Color(1.0, 0.6, 0.55))
