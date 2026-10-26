extends RefCounted
## 전투 판정(화면과 무관한 순수 규칙). 화면(dungeon/main.gd)은 여기서 돌려받은 사건 목록을 차례로 연출한다.
## 규칙 문서: docs/card-concept-v01.md
##
## 덱·손패: 캐릭터마다 덱(카드 id 목록, 같은 카드 여럿 가능). 방에 들어서면 살아 있는 캐릭터의 덱을 모두 섞어 뽑을 패를 만들고
## HAND_SIZE 장을 뽑는다. 쓴 카드는 버림패로, 아군 턴마다 손패가 HAND_SIZE 가 될 때까지 뽑는다(뽑을 패가 비면 버림패를 섞는다).
## 손패·더미의 원소는 "카드id#번호" 키(D.base_id 로 카드 id).
##
## 경험치: 적이 쓰러지면 살아 있는 아군 모두가 그 적의 xp 를 얻고, 직접 처치한 캐릭터는 XP_KILL_BONUS 를 더 얻는다.
## 레벨업하면 pending_levelups 에 쌓이고, 화면이 pool 에서 셋을 보여 준 뒤 add_card() 로 덱에 넣는다.
##
## 사건(Dictionary, "type" 키):
##   cast {unit, card, cells, targets, center}   — 카드 사용(대상 칸·맞은 유닛 id). card 는 카드 id
##   damage {unit, amount, blocked, hp, src}      — 피해(방어로 막은 양 포함)
##   heal {unit, amount, hp}                      — 회복
##   block {unit, amount, total}                  — 방어 얻음
##   status {unit, status}                        — mark · freeze · taunt
##   push {unit, from, to, bumped}
##   death {unit}
##   xp {unit, amount, xp, level, next, killer}   — 경험치 얻음
##   level_up {unit, level}                       — 레벨업(카드 고르기는 화면이)
##   enemy {unit, action, target}                 — 적 행동 시작(action: attack · roar · frozen · idle)
##   room_clear {}  defeat {}

const D := preload("res://dungeon/data/defs.gd")


class Unit:
	var id := 0
	var kind := ""          # 캐릭터 id(warrior…) 또는 적 id(goblin…)
	var team := "ally"
	var cell := Vector2i.ZERO
	var hp := 1
	var max_hp := 1
	var block := 0
	var ap := 0
	var mark := 0           # 남은 아군 턴 끝 수(>0 이면 표식)
	var frozen := false
	var taunt := false
	var dead := false
	var acts := 0           # 적: 지금까지 한 적 턴 수(보스 포효 주기)
	var xp := 0             # 아군: 이 레벨에서 모은 경험치
	var level := 1
	var deck: Array = []    # 아군: 카드 id 목록(같은 카드 여럿 가능)

	func name() -> String:
		var def: Dictionary = D.HEROES.get(kind, D.ENEMIES.get(kind, {}))
		return String(def.get("name", kind))

	func def() -> Dictionary:
		return D.HEROES.get(kind, {}) if team == "ally" else D.ENEMIES.get(kind, {})

	func xp_next() -> int:
		return D.xp_to_next(level)


var units: Array = []       # Unit
var hand: Array = []        # 카드 키(손패)
var draw_pile: Array = []   # 카드 키(뽑을 패, 맨 뒤가 다음 카드)
var discard: Array = []     # 카드 키(버림패)
var pending_levelups: Array = []   # 레벨업한 캐릭터 id(순서대로 카드 고르기)
var turn := 0               # 이 방에서의 아군 턴 번호(1부터)
var room := -1
var phase := "idle"         # player · enemy · clear · defeat
var rng := RandomNumberGenerator.new()
var _next_id := 1
var _next_key := 1


# ───────────────────────── 원정대·방 ─────────────────────────

func setup_party(hero_ids: Array) -> void:
	units.clear()
	_next_id = 1
	for h in hero_ids:
		var def: Dictionary = D.HEROES[h]
		var u := Unit.new()
		u.id = _next_id
		_next_id += 1
		u.kind = h
		u.team = "ally"
		u.max_hp = int(def.hp)
		u.hp = u.max_hp
		u.cell = def.start
		u.deck = Array(def.cards).duplicate()
		units.append(u)


## 방 입장: 적 배치, 아군은 시작 진형으로, 턴 0, 모든 덱을 섞어 손패 HAND_SIZE 장. 처음 아군 턴은 begin_player_turn() 으로 연다.
func enter_room(index: int) -> void:
	room = index
	turn = 0
	phase = "idle"
	units = units.filter(func(u): return u.team == "ally")
	for u in allies(true):
		u.cell = D.HEROES[u.kind].start
		u.block = 0
		u.mark = 0
		u.frozen = false
		u.taunt = false
	for e in D.ROOMS[index].enemies:
		var def: Dictionary = D.ENEMIES[e[0]]
		var u := Unit.new()
		u.id = _next_id
		_next_id += 1
		u.kind = e[0]
		u.team = "enemy"
		u.max_hp = int(def.hp)
		u.hp = u.max_hp
		u.cell = e[1]
		units.append(u)
	build_piles()
	draw_to_hand()


## 살아 있는 캐릭터의 덱을 모두 모아 섞는다. 손패·버림패는 비운다.
func build_piles() -> void:
	hand.clear()
	discard.clear()
	draw_pile.clear()
	for u in allies():
		for c in u.deck:
			draw_pile.append("%s#%d" % [c, _next_key])
			_next_key += 1
	_shuffle(draw_pile)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## 손패가 HAND_SIZE 가 될 때까지 뽑는다. 뽑을 패가 비면 버림패를 섞어 넣는다. 쓰러진 동료의 카드는 건너뛴다. 뽑은 키 목록을 돌려준다.
func draw_to_hand() -> Array:
	var drawn: Array = []
	var skipped: Array = []
	var guard := 0
	while hand.size() < D.HAND_SIZE and guard < 200:
		guard += 1
		if draw_pile.is_empty():
			if discard.is_empty():
				break
			draw_pile = discard.duplicate()
			discard.clear()
			_shuffle(draw_pile)
		var key: String = draw_pile.pop_back()
		if card_owner(key) == null:
			skipped.append(key)
			continue
		hand.append(key)
		drawn.append(key)
	discard.append_array(skipped)
	return drawn


## 방을 넘어갈 때: 잃은 체력의 일부 회복, 쓰러진 동료는 일부 체력으로 일어난다. full(중간 보스 뒤 모닥불)이면 모두 가득.
func rest_between_rooms(full := false) -> void:
	for u in allies(true):
		if full:
			u.dead = false
			u.hp = u.max_hp
		elif u.dead:
			u.dead = false
			u.hp = maxi(1, int(round(u.max_hp * D.HEAL_BETWEEN)))
		else:
			u.hp = mini(u.max_hp, u.hp + int(round((u.max_hp - u.hp) * D.HEAL_BETWEEN)))


func room_is_boss(i := -1) -> bool:
	return bool(D.ROOMS[room if i < 0 else i].get("boss", false))


func allies(include_dead := false) -> Array:
	return units.filter(func(u): return u.team == "ally" and (include_dead or not u.dead))


func enemies(include_dead := false) -> Array:
	return units.filter(func(u): return u.team == "enemy" and (include_dead or not u.dead))


func unit(id: int) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func hero(kind: String) -> Unit:
	for u in units:
		if u.team == "ally" and u.kind == kind:
			return u
	return null


func at(c: Vector2i) -> Unit:
	for u in units:
		if not u.dead and u.cell == c:
			return u
	return null


# ───────────────────────── 경험치·레벨 ─────────────────────────

## 레벨업 때 보여 줄 카드 셋(pool 에서 무작위, 겹치지 않게).
func level_options(u: Unit) -> Array:
	var pool: Array = Array(D.HEROES[u.kind].get("pool", [])).duplicate()
	_shuffle(pool)
	return pool.slice(0, mini(D.LEVEL_OPTIONS, pool.size()))


## 고른 카드를 덱에 넣는다. 전투 중이면 뽑을 패에도 섞어 넣는다(이번 방에서 바로 나올 수 있게).
func add_card(u: Unit, card_id: String) -> void:
	u.deck.append(card_id)
	if phase in ["player", "enemy"]:
		var key := "%s#%d" % [card_id, _next_key]
		_next_key += 1
		draw_pile.insert(rng.randi_range(0, draw_pile.size()), key)


func _gain_xp(u: Unit, amount: int, killer: bool, ev: Array) -> void:
	if u.dead or amount <= 0:
		return
	u.xp += amount
	var leveled := false
	while u.xp >= u.xp_next():
		u.xp -= u.xp_next()
		u.level += 1
		leveled = true
	ev.append({"type": "xp", "unit": u.id, "amount": amount, "xp": u.xp, "level": u.level, "next": u.xp_next(), "killer": killer})
	if leveled:
		pending_levelups.append(u.id)
		ev.append({"type": "level_up", "unit": u.id, "level": u.level})


# ───────────────────────── 아군 턴 ─────────────────────────

## 아군 턴 시작: 모든 캐릭터 행동력 AP_MAX, 방어 초기화, 손패를 HAND_SIZE 까지 뽑는다.
func begin_player_turn() -> Array:
	turn += 1
	phase = "player"
	refill_ap()
	for u in allies():
		u.block = 0
	var drawn := draw_to_hand()
	return [{"type": "turn", "side": "player", "turn": turn, "drawn": drawn}]


## 행동력 규칙(한 곳): 매 아군 턴 모두 AP_MAX 로 가득 찬다.
func refill_ap() -> void:
	for u in allies():
		u.ap = D.AP_MAX


func total_ap() -> int:
	var n := 0
	for u in allies():
		n += u.ap
	return n


func card_owner(card_id: String) -> Unit:
	var h := hero(String(D.card(card_id).get("hero", "")))
	return h if h != null and not h.dead else null


## 손패의 이 카드를 지금 낼 수 있는가(행동력·주인 생존). 대상이 하나라도 있는지는 has_targets.
func affordable(card_id: String) -> bool:
	var o := card_owner(card_id)
	return phase == "player" and card_id in hand and o != null and o.ap >= int(D.card(card_id).cost)


func has_targets(card_id: String) -> bool:
	var t := String(D.card(card_id).target)
	if t == "none":
		return true
	for c in target_cells(card_id):
		if not cells_hit(card_id, c).is_empty():
			return true
	return false


func playable(card_id: String) -> bool:
	return affordable(card_id) and has_targets(card_id)


## 겨눌 수 있는 칸(마우스로 고르는 칸). none 은 빈 배열.
func target_cells(card_id: String) -> Array:
	var card := D.card(card_id)
	var o := card_owner(card_id)
	var out: Array = []
	if o == null:
		return out
	match String(card.target):
		"enemy_melee", "enemy_any":
			for e in enemies():
				out.append(e.cell)
		"row", "area3", "cross":
			for x in range(D.ALLY_COLS, D.COLS):
				for y in D.ROWS:
					out.append(Vector2i(x, y))
	return out


## 그 칸을 겨눴을 때 효과가 미치는 칸(미리보기). 대상 유닛은 units_in(cells).
func area_of(card_id: String, center: Vector2i) -> Array:
	var card := D.card(card_id)
	var out: Array = []
	match String(card.target):
		"enemy_melee", "enemy_any":
			out.append(center)
		"row":
			for x in range(D.ALLY_COLS, D.COLS):
				out.append(Vector2i(x, center.y))
		"area3":
			for dx in [-1, 0, 1]:
				for dy in [-1, 0, 1]:
					var c: Vector2i = center + Vector2i(dx, dy)
					if D.is_enemy_cell(c):
						out.append(c)
		"cross":
			for d in [Vector2i.ZERO, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var c: Vector2i = center + d
				if D.is_enemy_cell(c):
					out.append(c)
		"none":
			# 즉시 카드가 적을 치면(aura) 적 지역 앞 두 열
			if card.has("aura"):
				for x in range(D.ALLY_COLS, D.ALLY_COLS + 2):
					for y in D.ROWS:
						out.append(Vector2i(x, y))
	return out


func cells_hit(card_id: String, center: Vector2i) -> Array:
	if not center in target_cells(card_id):
		return []
	return units_in(area_of(card_id, center), "enemy")


func units_in(cells: Array, team: String) -> Array:
	var out: Array = []
	for u in units:
		if not u.dead and u.team == team and u.cell in cells:
			out.append(u)
	return out


## 카드 사용. 성공하면 사건 목록, 낼 수 없으면 빈 배열. card_key 는 손패의 키("id#n").
func play_card(card_key: String, center := Vector2i(-1, -1)) -> Array:
	if not affordable(card_key):
		return []
	var card := D.card(card_key)
	var card_id := D.base_id(card_key)
	var o := card_owner(card_key)
	var t := String(card.target)
	if t != "none" and cells_hit(card_key, center).is_empty():
		return []
	o.ap -= int(card.cost)
	hand.erase(card_key)
	discard.append(card_key)
	var ev: Array = []
	var cast := {"type": "cast", "unit": o.id, "card": card_id, "key": card_key, "center": center, "cells": area_of(card_key, center), "targets": []}
	ev.append(cast)
	if t == "none":
		cast.center = o.cell
	match card_id:
		"chain_lightning":
			var first: Unit = cells_hit(card_key, center)[0]
			var hit_ids: Array = []
			var cur := first
			var dmg := int(card.damage)
			for i in int(card.jumps) + 1:
				hit_ids.append(cur.id)
				cast.targets.append(cur.id)
				_hit(cur, dmg, o, ev)
				dmg -= int(card.falloff)
				cur = _nearest_enemy(cur.cell, hit_ids)
				if cur == null:
					break
		_:
			# 일반 카드: 자기·아군 효과 → 적 피해·상태
			if card.has("block_all"):
				for a in allies():
					_gain_block(a, int(card.block_all), ev)
			if card.has("block"):
				_gain_block(o, int(card.block), ev)
			if card.has("heal"):
				_heal(o, int(card.heal), ev)
			if card.has("heal_all"):
				for a in allies():
					_heal(a, int(card.heal_all), ev)
			if card.get("taunt", false):
				o.taunt = true
				ev.append({"type": "status", "unit": o.id, "status": "taunt"})
			var targets: Array = cells_hit(card_key, center) if t != "none" else units_in(area_of(card_key, o.cell), "enemy")
			for e in targets:
				cast.targets.append(e.id)
				var dmg := int(card.get("damage", card.get("aura", 0)))
				if card.has("mark_bonus") and e.mark > 0:
					dmg += int(card.mark_bonus)
				for k in int(card.get("hits", 1)):
					if e.dead:
						break
					_hit(e, dmg, o, ev)
				if e.dead:
					continue
				if card.get("mark", false):
					e.mark = 2
					ev.append({"type": "status", "unit": e.id, "status": "mark"})
				if card.get("freeze", false):
					e.frozen = true
					ev.append({"type": "status", "unit": e.id, "status": "freeze"})
				if card.has("push"):
					_push(e, Vector2i(1, 0), int(card.bump), o, ev)
	_check_end(ev)
	return ev


## 아군 턴 끝 → 적 턴(사건 목록). 끝나면 phase 는 enemy 로 남고, 화면이 연출을 마친 뒤 begin_player_turn().
func end_player_turn() -> Array:
	if phase != "player":
		return []
	phase = "enemy"
	for e in enemies():
		e.mark = maxi(0, e.mark - 1)
	var ev: Array = [{"type": "turn", "side": "enemy", "turn": turn}]
	var order := enemies()
	order.sort_custom(func(a, b): return a.cell.x < b.cell.x or (a.cell.x == b.cell.x and a.cell.y < b.cell.y))
	for e in order:
		if e.dead or allies().is_empty():
			continue
		_enemy_act(e, ev)
	for a in allies(true):
		a.taunt = false
	_check_end(ev)
	return ev


# ───────────────────────── 적 행동 ─────────────────────────

## 적의 다음 행동 예고(머리 위 의도 표시). {action, amount, target}. 적은 이동하지 않고 어디서든 바로 친다.
func intent(e: Unit) -> Dictionary:
	if e.dead:
		return {}
	if e.frozen:
		return {"action": "frozen"}
	var def := e.def()
	if def.has("roar_every") and (e.acts + 1) % int(def.roar_every) == 0:
		return {"action": "roar", "amount": int(def.roar), "name": String(def.get("roar_name", "포효"))}
	var target := _enemy_target(e)
	if target == null:
		return {"action": "idle"}
	return {"action": "attack", "amount": int(def.damage), "target": target.id}


func _enemy_act(e: Unit, ev: Array) -> void:
	var it := intent(e)
	e.acts += 1
	match String(it.get("action", "idle")):
		"frozen":
			e.frozen = false
			ev.append({"type": "enemy", "unit": e.id, "action": "frozen"})
		"roar":
			ev.append({"type": "enemy", "unit": e.id, "action": "roar"})
			for a in allies():
				_hit(a, int(it.amount), e, ev)
		"attack":
			var t := unit(int(it.target))
			ev.append({"type": "enemy", "unit": e.id, "action": "attack", "target": t.id})
			_hit(t, int(it.amount), e, ev)
		_:
			ev.append({"type": "enemy", "unit": e.id, "action": "idle"})


## 노릴 아군: 도발한 아군 → (투척꾼) 같은 줄의 아군 중 체력 낮은 쪽 → 가장 가까운 아군(같으면 체력 낮은 쪽).
func _enemy_target(e: Unit) -> Unit:
	var live := allies()
	if live.is_empty():
		return null
	for a in live:
		if a.taunt:
			return a
	if String(e.def().kind) == "ranged":
		var same := live.filter(func(a): return a.cell.y == e.cell.y)
		if not same.is_empty():
			same.sort_custom(func(a, b): return a.hp < b.hp)
			return same[0]
	live.sort_custom(func(a, b):
		var da := Vector2(a.cell - e.cell).length()
		var db := Vector2(b.cell - e.cell).length()
		return da < db or (is_equal_approx(da, db) and a.hp < b.hp))
	return live[0]


# ───────────────────────── 공용 ─────────────────────────

func _nearest_enemy(from: Vector2i, exclude: Array) -> Unit:
	var best: Unit = null
	var bd := INF
	for e in enemies():
		if e.id in exclude:
			continue
		var d := Vector2(e.cell - from).length()
		if d < bd:
			bd = d
			best = e
	return best


func _hit(u: Unit, amount: int, src: Unit, ev: Array) -> void:
	if u.dead:
		return
	if u.team == "enemy" and u.mark > 0:
		amount += D.MARK_BONUS
	var blocked := mini(u.block, amount)
	u.block -= blocked
	var dmg := amount - blocked
	u.hp = maxi(0, u.hp - dmg)
	ev.append({"type": "damage", "unit": u.id, "amount": dmg, "blocked": blocked, "hp": u.hp, "src": src.id if src != null else 0})
	if u.hp <= 0:
		u.dead = true
		u.taunt = false
		ev.append({"type": "death", "unit": u.id})
		if u.team == "enemy":
			var gain := int(u.def().get("xp", 0))
			for a in allies():
				_gain_xp(a, gain + (D.XP_KILL_BONUS if src != null and a.id == src.id else 0), src != null and a.id == src.id, ev)


func _heal(u: Unit, amount: int, ev: Array) -> void:
	if u.dead or amount <= 0:
		return
	var got := mini(amount, u.max_hp - u.hp)
	u.hp += got
	ev.append({"type": "heal", "unit": u.id, "amount": got, "hp": u.hp})


func _gain_block(u: Unit, amount: int, ev: Array) -> void:
	u.block += amount
	ev.append({"type": "block", "unit": u.id, "amount": amount, "total": u.block})


func _push(u: Unit, dir: Vector2i, bump: int, src: Unit, ev: Array) -> void:
	var to := u.cell + dir
	var free := D.is_enemy_cell(to) if u.team == "enemy" else D.is_ally_cell(to)
	if free and at(to) == null:
		ev.append({"type": "push", "unit": u.id, "from": u.cell, "to": to, "bumped": false})
		u.cell = to
	else:
		ev.append({"type": "push", "unit": u.id, "from": u.cell, "to": u.cell, "bumped": true})
		_hit(u, bump, src, ev)


func _check_end(ev: Array) -> void:
	if phase in ["clear", "defeat"]:
		return
	if enemies().is_empty():
		phase = "clear"
		ev.append({"type": "room_clear"})
	elif allies().is_empty():
		phase = "defeat"
		ev.append({"type": "defeat"})
