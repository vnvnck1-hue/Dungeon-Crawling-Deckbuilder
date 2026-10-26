extends RefCounted
## 전투 판정(화면과 무관한 순수 규칙). 화면(dungeon/main.gd)은 여기서 돌려받은 사건 목록을 차례로 연출한다.
## 규칙 문서: docs/card-concept-v01.md
##
## 사건(Dictionary, "type" 키):
##   cast {unit, card, cells, targets, center}   — 카드 사용(대상 칸·맞은 유닛 id)
##   damage {unit, amount, blocked, hp, src}      — 피해(방어로 막은 양 포함)
##   block {unit, amount, total}                  — 방어 얻음
##   status {unit, status}                        — mark · freeze · taunt
##   move {unit, from, to}  push {unit, from, to, bumped}
##   death {unit}
##   enemy {unit, action, target}                 — 적 행동 시작(action: attack · move · roar · frozen · idle)
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

	func name() -> String:
		var def: Dictionary = D.HEROES.get(kind, D.ENEMIES.get(kind, {}))
		return String(def.get("name", kind))

	func def() -> Dictionary:
		return D.HEROES.get(kind, {}) if team == "ally" else D.ENEMIES.get(kind, {})


var units: Array = []       # Unit
var hand: Array = []        # 카드 id(손패)
var discard: Array = []     # 카드 id(버림패)
var turn := 0               # 이 방에서의 아군 턴 번호(1부터)
var room := -1
var phase := "idle"         # player · enemy · clear · defeat
var _next_id := 1


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
		units.append(u)


## 방 입장: 적 배치, 아군은 시작 진형으로, 턴 0. 처음 아군 턴은 begin_player_turn() 으로 연다.
func enter_room(index: int) -> void:
	room = index
	turn = 0
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
	hand.clear()
	discard.clear()


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


# ───────────────────────── 아군 턴 ─────────────────────────

## 아군 턴 시작: 행동력 = min(3, 턴 번호), 방어 초기화, 버림패의 카드가 모두 손패로.
func begin_player_turn() -> Array:
	turn += 1
	phase = "player"
	refill_ap()
	for u in allies():
		u.block = 0
	hand.clear()
	discard.clear()
	for u in allies():
		for c in D.HEROES[u.kind].cards:
			hand.append(c)
	return [{"type": "turn", "side": "player", "turn": turn}]


## 행동력 규칙(한 곳): 최대치가 턴마다 1씩 자라고(최대 3) 매 턴 가득 찬다.
func refill_ap() -> void:
	for u in allies():
		u.ap = mini(D.AP_MAX, turn)


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
			# 불굴의 포효: 적 지역 앞 두 열
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


## 카드 사용. 성공하면 사건 목록, 낼 수 없으면 빈 배열.
func play_card(card_id: String, center := Vector2i(-1, -1)) -> Array:
	if not affordable(card_id):
		return []
	var card := D.card(card_id)
	var o := card_owner(card_id)
	var t := String(card.target)
	if t != "none" and cells_hit(card_id, center).is_empty():
		return []
	o.ap -= int(card.cost)
	hand.erase(card_id)
	discard.append(card_id)
	var ev: Array = []
	var cast := {"type": "cast", "unit": o.id, "card": card_id, "center": center, "cells": area_of(card_id, center), "targets": []}
	ev.append(cast)
	match card_id:
		"war_cry":
			cast.center = o.cell
			for a in allies():
				_gain_block(a, int(card.block_all), ev)
			for e in units_in(area_of(card_id, o.cell), "enemy"):
				cast.targets.append(e.id)
				_hit(e, int(card.aura), o, ev)
			o.taunt = true
			ev.append({"type": "status", "unit": o.id, "status": "taunt"})
		"chain_lightning":
			var first: Unit = cells_hit(card_id, center)[0]
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
			var targets := cells_hit(card_id, center)
			for e in targets:
				cast.targets.append(e.id)
				var dmg := int(card.damage)
				if card.has("mark_bonus") and e.mark > 0:
					dmg += int(card.mark_bonus)
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
			if card.has("block"):
				_gain_block(o, int(card.block), ev)
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

## 적의 다음 행동 예고(머리 위 의도 표시). {action, amount, target}
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
	if _can_strike(e, target):
		return {"action": "attack", "amount": int(def.damage), "target": target.id}
	return {"action": "move"}


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
		"move":
			var to := _step_toward(e, _enemy_target(e))
			if to != e.cell:
				ev.append({"type": "enemy", "unit": e.id, "action": "move"})
				ev.append({"type": "move", "unit": e.id, "from": e.cell, "to": to})
				e.cell = to
			else:
				ev.append({"type": "enemy", "unit": e.id, "action": "idle"})
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


## 원거리는 언제나, 근접은 적 지역 맨 앞 열에 섰거나 대상 바로 옆이면 칠 수 있다.
func _can_strike(e: Unit, target: Unit) -> bool:
	if String(e.def().kind) == "ranged":
		return true
	return e.cell.x == D.ALLY_COLS or _adjacent(e.cell, target.cell)


## 근접 적의 한 걸음: 앞(왼쪽)으로, 막히면 대상 줄 쪽으로 비켜 선다. 적 지역 밖으로는 나가지 않는다.
func _step_toward(e: Unit, target: Unit) -> Vector2i:
	var tries: Array = [e.cell + Vector2i.LEFT]
	if target != null and target.cell.y != e.cell.y:
		var dy := signi(target.cell.y - e.cell.y)
		tries.append(e.cell + Vector2i(-1, dy))
		tries.append(e.cell + Vector2i(0, dy))
	for c in tries:
		if D.is_enemy_cell(c) and at(c) == null:
			return c
	return e.cell


# ───────────────────────── 공용 ─────────────────────────

func _adjacent(a: Vector2i, b: Vector2i) -> bool:
	return maxi(absi(a.x - b.x), absi(a.y - b.y)) == 1


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
