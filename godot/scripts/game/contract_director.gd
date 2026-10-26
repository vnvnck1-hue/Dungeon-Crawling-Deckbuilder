extends Node
## ContractDirector: 카드로 소환한 용병·하수인의 임무·대기·사망과 활동 상한(기획서 v0.3 §5·6·8, 직업 분화 v1).
## 소유 카드(미사용 계약)는 CardInventory가, 월드에 나온 인물은 이 모듈이 관리한다.
## 나무꾼에게 다음 나무를 맡기고, 채집가의 하루 경로와 귀환 시각을 정하며, 산장 공격자를 전투직에게 알린다.
## 쓰러진 용병은 산장 뒤편 묘지에 묻힌다. 하수인은 쓰러지거나 낮이 되면 목재 1개가 된다.

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const AllyScript := preload("res://scripts/actors/ally.gd")

var game
var allies: Array = []
var stats := {"died": 0, "minions": 0, "withered": 0, "hunted": 0, "gathered": 0, "trees_felled": 0}
var lodge_threat = null       # 산장을 마지막으로 공격한 적(전투직이 우선 추적)
var _assign_t := 0.0
var _chests_today := 0
var _books_today := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "ContractDirector"
	_rng.randomize()


func bind_lodge() -> void:
	if game.world.lodge != null and not game.world.lodge.attacked.is_connected(_on_lodge_attacked):
		game.world.lodge.attacked.connect(_on_lodge_attacked)


func _on_lodge_attacked(attacker) -> void:
	if attacker != null and is_instance_valid(attacker) and not attacker.dead:
		lodge_threat = attacker


## 용병 동행 출발(docs/merc-escort-v01.md): 같은 순간 여러 명이 나서면 토스트 한 번으로 묶는다.
var _escort_toast_t := 0.0
var _escort_toast_n := 0
var escort_departures := 0   # 검증용: 출발 토스트 횟수


func note_escort_start(a) -> void:
	_escort_toast_n += 1
	if _escort_toast_t > 0.0:
		return
	_escort_toast_t = 0.3
	get_tree().create_timer(_escort_toast_t).timeout.connect(func():
		var n := _escort_toast_n
		_escort_toast_n = 0
		_escort_toast_t = 0.0
		escort_departures += 1
		if n <= 1 and is_instance_valid(a) and not a.dead:
			game.toast("%s — 마녀를 따라 숲으로 나섭니다" % a.person, Color(0.8, 0.95, 0.85))
		else:
			game.toast("용병 %d명이 마녀를 따라 숲으로 나섭니다" % n, Color(0.8, 0.95, 0.85)))


## 활동 상한(Cfg.ACTIVE_LIMIT)에 드는 수: 임무 수행·대기·귀가 중인 용병만 센다.
## 미사용 카드와 숲의 괴물 하수인(밤이 지나면 시드는 소환물)은 포함하지 않는다.
func active_count() -> int:
	return mercs_alive()


func mercs_alive() -> int:
	return allies.filter(func(a): return is_instance_valid(a) and not a.dead and a.kind == "merc").size()


## 비어 있는 대기 자리(다른 용병이 쓰지 않는 곳).
## A안(2026-10-17): 대기 용병은 직업 구분 없이 앞마당 모닥불 쉼터 둘레(Layout.rest_slots)에 모인다. 회복·버프는 없다.
func yard_spot(for_ally) -> Vector3:
	var used: Array = []
	for a in allies:
		if a != for_ally and is_instance_valid(a) and not a.dead and a.kind == "merc" and a.state == AllyScript.State.IDLE:
			used.append(a.guard_point)
	for p in Layout.rest_slots():
		if not p in used:
			return p
	return Layout.CAMPFIRE + Vector3(randf_range(-2.2, 2.2), 0, randf_range(-2.2, 2.2))


func persons_active() -> Array:
	var out: Array = []
	for a in allies:
		if is_instance_valid(a) and not a.dead and a.person != "":
			out.append(a.person)
	return out


# ───────────────────────── 소환 ─────────────────────────

func spawn_chop(person: String, tree: Dictionary, work_pos: Vector3):
	var a := AllyScript.new()
	a.setup(game, "merc", person, "lumberjack", work_pos)
	a.position = work_pos
	a.tree = tree
	a.work_pos = work_pos
	tree["reserved"] = a
	_register(a)
	game.toast("%s — 벌목을 시작합니다 (목재 %d 남은 나무)" % [person, int(tree["remaining"])], Color(1.0, 0.88, 0.6))
	return a


## 전투직(사냥꾼·전투용병)과 하수인. priority는 카드로 지정한 적.
func spawn_guard(kind: String, person: String, pos: Vector3, priority = null, job := "warrior"):
	var a := AllyScript.new()
	a.setup(game, kind, person, job, pos)
	a.position = pos
	a.priority = priority
	if kind == "merc":
		a.patrol_point = pos
		if priority != null:
			a.target = priority
			a.state = AllyScript.State.ENGAGE
	_register(a)
	if kind == "minion":
		stats["minions"] += 1
	return a


func spawn_gatherer(person: String, pos: Vector3):
	var a := AllyScript.new()
	a.setup(game, "merc", person, "gatherer", pos)
	a.position = pos
	_register(a)
	game.toast("%s — 숲 탐색을 떠납니다" % person, Color(0.9, 0.85, 1.0))
	return a


func _register(a) -> void:
	game.actors.add_child(a)
	allies.append(a)


# ───────────────────────── 나무꾼 ─────────────────────────

## 벌목 1회 목재(항상 Cfg.CHOP_YIELD = 1개). 고목의 심장은 수확량이 아니라 벌목 시간을 줄인다.
func _chop_yield() -> int:
	return Cfg.CHOP_YIELD


## 나무꾼이 목재를 더 들 수 없는가(Cfg.LUMBERJACK_CARRY).
func lumberjack_full(a) -> bool:
	return int(a.carry.get("timber", 0)) >= Cfg.LUMBERJACK_CARRY


## 벌목 1회 완료: 목재를 나무꾼이 들고 있고, 나무가 바닥나면 쓰러져 사라진다. 같은 나무가 남았으면 계속 벤다.
## 들고 있는 목재가 가득 차면 나무를 놓고 산장 마당에서 쉬며 마녀가 받아 가기를 기다린다.
func finish_chop(a) -> void:
	if a.dead or a.job != "lumberjack" or a.state != AllyScript.State.WORKING:
		return
	var tree: Dictionary = a.tree
	var amount := mini(_chop_yield(), int(tree["remaining"]))
	amount = mini(amount, Cfg.LUMBERJACK_CARRY - int(a.carry.get("timber", 0)))
	tree["remaining"] -= amount
	a.add_carry("timber", amount)
	a.progress = 0.0
	game.sounds.play("chop_done")
	if lumberjack_full(a):
		if tree["remaining"] <= 0:
			stats["trees_felled"] += 1
			game.world.deplete_tree(tree)
		if tree.get("reserved") == a:
			tree["reserved"] = null
		a.become_idle(yard_spot(a))
		game.toast("%s — 목재 %d개가 가득 찼습니다. 산장 주변에서 쉬며 기다립니다" % [a.person, Cfg.LUMBERJACK_CARRY], Color(0.95, 0.8, 0.55))
		return
	if tree["remaining"] <= 0:
		stats["trees_felled"] += 1
		tree["reserved"] = null
		game.world.deplete_tree(tree)
		game.toast("%s — 나무를 다 베었습니다 (목재 %d 보관)" % [a.person, a.carry.get("timber", 0)], Color(0.95, 0.8, 0.55))
		assign_next_tree(a)
	else:
		game.toast("%s — 목재 +%d 보관 (나무에 %d 남음)" % [a.person, amount, int(tree["remaining"])], Color(0.95, 0.8, 0.55))


## 가장 가까운 벌목 가능한 나무(접근 가능·미예약)를 맡긴다. 없으면 마당에서 쉰다.
func assign_next_tree(a) -> bool:
	if a.dead:
		return false
	if a.tree != null and a.tree.get("reserved") == a:
		a.tree["reserved"] = null
	# 숲의 약속(종족 카드 v1): 약속한 날은 나무를 베지 않고 마당에서 쉰다
	if game.get("race_cards") != null and game.race_cards.lumber_block_reason() != "":
		a.become_idle(yard_spot(a))
		return false
	if lumberjack_full(a):
		a.become_idle(yard_spot(a))
		return false
	var best = null
	var best_d := 1e9
	for t in game.world.harvest_trees:
		if t.get("removed", false) or t["remaining"] <= 0 or t["reserved"] != null or t == a.failed_tree:
			continue
		if game.world.tree_access(t) != "":
			continue
		var d: float = a.global_position.distance_to(t["pos"])
		if d < best_d:
			best_d = d
			best = t
	if best == null:
		a.become_idle(yard_spot(a))
		return false
	var wp: Vector3 = game.resolver.work_position(best)
	best["reserved"] = a
	a.set_chop(best, wp)
	return true


# ───────────────────────── 채집가 ─────────────────────────

## 하루 채집 경로: 랜드마크 하나와 그 주변 지점들. 산장에서 왕복 시간과 귀환 여유를 고려해 지점 수를 줄인다.
func plan_gathering(a) -> void:
	if a.dead or a.job != "gatherer" or game.session.state != 0:
		return
	var remaining: float = game.session.prep_remaining()
	if remaining < Cfg.GATHER_MIN_PREP:
		return
	var marks: Array = Layout.LANDMARKS.duplicate()
	marks.shuffle()
	var nav_map: RID = game.get_world_3d().navigation_map
	for mark in marks:
		var center: Vector2 = mark["pos"]
		var dist := Vector2(a.global_position.x, a.global_position.z).distance_to(center)
		var travel := dist * 2.0 / Cfg.MERC_SPEED
		var stops_fit := int(floor((remaining - Cfg.GATHER_RETURN_MARGIN - travel) / (Cfg.GATHER_PICK_TIME + 4.0)))
		if stops_fit < 1:
			continue
		var n := mini(Cfg.GATHER_STOPS, stops_fit)
		var stops: Array = []
		for i in n:
			var ang := _rng.randf_range(0.0, TAU)
			var r := 0.0 if i == 0 else _rng.randf_range(2.0, 4.5)
			var p := Vector3(center.x + cos(ang) * r, 0, center.y + sin(ang) * r)
			# 지면 내비 점이고 지금 자리에서 닿는 곳만 채집 지점으로(섬·막힌 포켓 제외)
			var nav = NavUtil.walkable_from(nav_map, a.global_position, p, 2.0)
			if nav == null: nav = NavUtil.walkable_from(nav_map, a.global_position, Vector3(center.x, 0, center.y), 2.0)
			if nav != null: stops.append(nav)
		a.set_gathering(stops)
		return
	a.become_idle(yard_spot(a))


## 지금 돌아서야 준비 시간 안에 산장에 닿는가.
func gather_must_return(a) -> bool:
	if game.session.state != 0:
		return true
	var home := Layout.DOOR_FRONT
	var dist: float = Vector2(a.global_position.x - home.x, a.global_position.z - home.z).length()
	return game.session.prep_remaining() <= dist / Cfg.MERC_SPEED + Cfg.GATHER_RETURN_MARGIN


## 지점 하나에서 줍기: 표에서 1회 굴린다. 보물상자는 하루 한 개까지.
func gather_pick(a) -> void:
	var roll := _rng.randf()
	var acc := 0.0
	for row in Cfg.GATHER_TABLE:
		acc += float(row[1])
		if roll <= acc:
			var id: String = row[0]
			if id == "":
				game.toast("%s — 이곳엔 쓸 만한 게 없네요" % a.person, Color(0.8, 0.8, 0.9))
				return
			if id == "treasure_chest" and _chests_today >= Cfg.GATHER_CHEST_PER_DAY:
				id = "timber"
			if id == "old_spellbook" and _books_today >= Cfg.GATHER_BOOK_PER_DAY:
				id = "poison_mushroom"
			var n := _rng.randi_range(int(row[2]), int(row[3]))
			if id == "treasure_chest":
				_chests_today += 1
				n = 1
			if id == "old_spellbook":
				_books_today += 1
				n = 1
			a.add_carry(id, n)
			stats["gathered"] += n
			game.toast("%s — %s +%d 발견 (들고 있음)" % [a.person, game.cards.def(id).get("name", id), n],
				Color(1.0, 0.9, 0.5) if id == "treasure_chest" else Color(0.9, 0.95, 0.8))
			if id == "treasure_chest":
				game.sounds.play("mon_drop")
			return


# ───────────────────────── 낮 자동 배정 ─────────────────────────

## 낮 동안 쉬는 나무꾼에게 남은 나무를 맡기고, 쉬는 채집가를 내보낸다.
func _process(delta: float) -> void:
	if game == null or game.session == null:
		return
	if lodge_threat != null and (not is_instance_valid(lodge_threat) or lodge_threat.dead):
		lodge_threat = null
	if game.session.state != 0:
		return
	_assign_t -= delta
	if _assign_t > 0.0:
		return
	_assign_t = 1.0
	for a in allies:
		if not is_instance_valid(a) or a.dead or a.kind != "merc" or a.state != AllyScript.State.IDLE:
			continue
		if a.job == "lumberjack":
			if assign_next_tree(a):
				game.toast("%s — 다음 나무를 벌목하러 갑니다" % a.person, Color(1.0, 0.88, 0.6))
				return
		elif a.job == "gatherer" and a.carry.is_empty() and game.session.prep_remaining() >= Cfg.GATHER_MIN_PREP and a.gather_stops.is_empty():
			plan_gathering(a)
			return


func on_ally_died(a) -> void:
	stats["died"] += 1
	# 종족·언데드 카드 v1: 재로 그린 문양(장비가 풀리기 전), 언데드의 시체·일어나라
	if game.get("race_cards") != null:
		game.race_cards.on_ally_died(a)
	if game.get("undead") != null:
		game.undead.on_ally_died(a)
	if a.tree != null and a.tree.get("reserved") == a:
		a.tree["reserved"] = null
	var lost := ""
	if a.carry_total() > 0:
		lost = " (들고 있던 자원 %d개 손실)" % a.carry_total()
		a.carry.clear()
	game.world.graveyard.bury(a.person, game.session.day())
	game.toast("%s %s이(가) 쓰러졌습니다 — 산장 뒤편에 묻혔습니다%s" % [Cfg.JOB_NAMES.get(a.job, "용병"), a.person, lost], Color(1.0, 0.6, 0.6))


## 하수인이 쓰러지거나 낮이 됨: 시들어 목재 1개로 손패에 들어온다.
func wither_minion(a, why: String) -> void:
	if a.dead:
		return
	stats["withered"] += 1
	if why == "쓰러져":
		stats["died"] += 1
	game.cards.add("timber", Cfg.MINION_TIMBER)
	game.toast("숲의 괴물이 %s 시들었습니다 — 목재 +%d" % [why, Cfg.MINION_TIMBER], Color(0.85, 0.95, 0.6))
	a.wither_out()


func on_ally_removed(a) -> void:
	allies.erase(a)
	if a.kind == "merc" and game.get("merc_kit") != null:
		game.merc_kit.on_merc_gone(a)  # 고유 카드도 덱에서 빠진다 · 오크 둘
	# 활동이 끝난 계약·소환 카드는 버림패로(확정 규칙 5)
	if a.card_uid >= 0:
		game.cards.retire(a.card_uid)
		a.card_uid = -1


# ───────────────────────── 낮밤 전환(GameSession이 호출) ─────────────────────────

func on_wave_start() -> void:
	lodge_threat = null
	for a in allies.duplicate():
		if is_instance_valid(a):
			a.interrupt()


## 밤의 적이 모두 정리됨(낮이 밝음): 전투직은 정찰로, 하수인은 시들어 목재가 된다.
func on_combat_end() -> void:
	lodge_threat = null
	for a in allies.duplicate():
		if is_instance_valid(a):
			a.end_combat(yard_spot(a))


func on_prep_start() -> void:
	_chests_today = 0
	_books_today = 0
	for a in allies.duplicate():
		if is_instance_valid(a):
			a.gather_stops = []
			a.resume()
