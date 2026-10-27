extends RefCounted
## 전투 판정(화면과 무관한 순수 규칙). 화면(dungeon/main.gd)은 여기서 돌려받은 사건 목록을 차례로 연출한다.
## 규칙 문서: docs/card-concept-v01.md · 직업 시너지: docs/card-synergy-design-v01.md
##
## 덱·손패: 캐릭터마다 덱(카드 id 목록, 같은 카드 여럿 가능). 방에 들어서면 살아 있는 캐릭터의 덱을 모두 섞어 뽑을 패를 만들고
## HAND_SIZE 장을 뽑는다. 쓴 카드는 버림패로(소멸 카드는 이번 방에서 사라짐), 아군 턴마다 손패가 HAND_SIZE 가 될 때까지 뽑는다.
## 생성·뽑기 카드는 HAND_MAX 까지 손패를 늘린다. 손패·더미의 원소는 "카드id#번호" 키(D.base_id 로 카드 id).
##
## 쌓이는 상태: 전사 투지(fury) · 적 표식(mark) · 냉기(chill) · 화상(burn) + 빙결(frozen)·도발(taunt).
## 교차 반응: 파쇄(빙결 + 충돌/파쇄 카드) · 증기 폭발(냉기 + 화상) · 충돌(밀린 적과 부딪힌 적 모두) · 전도(연쇄 번개가 상태를 옮김).
## 연계: 카드의 combo.hero 가 이번 턴 직전에 낸 카드의 주인과 같으면 combo 의 효과를 더한다.
## 지속(power): 이번 방이 끝날 때까지 powers 에 남는다.
##
## 경험치: 적이 쓰러지면 살아 있는 아군 모두가 그 적의 xp 를 얻고, 직접 처치한 캐릭터는 XP_KILL_BONUS 를 더 얻는다.
## 레벨업하면 pending_levelups 에 쌓이고, 화면이 level_options()·upgrade_option() 을 보여 준 뒤 add_card()/upgrade_card() 로 덱을 바꾼다.
##
## 사건(Dictionary, "type" 키):
##   cast {unit, card, key, cells, targets, center, combo}  — 카드 사용(대상 칸·맞은 유닛 id). card 는 강화 전 카드 id
##   damage {unit, amount, blocked, hp, src, kind}  — 피해. kind: attack · burn · collide · reflect · reaction · self
##   heal {unit, amount, hp}  block {unit, amount, total}
##   status {unit, status, value, delta}           — mark · chill · burn · fury(값=쌓인 수) · freeze · taunt(1/0)
##   reaction {unit, kind, amount, with}           — shatter · steam · collide · conduct
##   push {unit, from, to, bumped}                 — 밀림/당김(bumped 면 제자리에서 충돌)
##   power {unit, power, value}                    — 지속 효과 켜짐
##   ap {unit, amount, ap}                         — 행동력 되찾음(표식 적 처치)
##   create {keys} · draw {keys} · discard {keys} · exhaust {keys} — 손패 변화(화면은 battle.hand 와 맞춘다)
##   death {unit}  xp {unit, amount, xp, level, next, killer}  level_up {unit, level}
##   enemy {unit, action, target}                  — 적 행동 시작(action: attack · roar · frozen · idle · burn(화상 피해))
##   aura {power, unit}                            — 턴 시작 지속 효과(한기)
##   turn {side, turn, drawn}  room_clear {}  defeat {}

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
	var mark := 0           # 표식 수(적). 아군에게 맞을 때마다 피해 +mark, 아군 턴 끝마다 −1
	var chill := 0          # 냉기(적). CHILL_FREEZE 가 되면 빙결
	var burn := 0           # 화상(적). 적이 행동하기 직전 burn 피해, 그 뒤 −1
	var fury := 0           # 투지(전사). 전사 카드 피해 +fury
	var frozen := false
	var taunt := false
	var dead := false
	var acts := 0           # 적: 지금까지 한 적 턴 수(보스 포효 주기)
	var xp := 0             # 아군: 이 레벨에서 모은 경험치
	var level := 1
	var picks := 0          # 아군: 레벨업으로 고른 횟수(첫 레벨업은 두 축·공용을 하나씩 보장)
	var deck: Array = []    # 아군: 카드 id 목록(같은 카드 여럿 가능, 강화하면 "id+")

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
var exhausted: Array = []   # 카드 키(이번 방에서 사라진 카드)
var pending_levelups: Array = []   # 레벨업한 캐릭터 id(순서대로 카드 고르기)
var powers: Dictionary = {}        # 지속 효과 id → 값(이번 방)
var last_hero := ""                # 이번 턴 직전에 낸 카드의 주인(연계)
var played: Dictionary = {}        # 캐릭터 id → 이번 턴 낸 카드 수
var cost_cut: Dictionary = {}      # 캐릭터 id → 이번 턴 다음 카드 비용 감소(명상)
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
## 투지·지속 효과·소멸 카드는 방마다 처음부터.
func enter_room(index: int) -> void:
	room = index
	turn = 0
	phase = "idle"
	powers.clear()
	last_hero = ""
	played.clear()
	cost_cut.clear()
	units = units.filter(func(u): return u.team == "ally")
	for u in allies(true):
		u.cell = D.HEROES[u.kind].start
		u.block = 0
		u.mark = 0
		u.chill = 0
		u.burn = 0
		u.fury = 0
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


## 살아 있는 캐릭터의 덱을 모두 모아 섞는다. 손패·버림패·소멸은 비운다.
func build_piles() -> void:
	hand.clear()
	discard.clear()
	draw_pile.clear()
	exhausted.clear()
	for u in allies():
		for c in u.deck:
			draw_pile.append(_new_key(c))
	_shuffle(draw_pile)


func _new_key(card_id: String) -> String:
	var k := "%s#%d" % [card_id, _next_key]
	_next_key += 1
	return k


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


## 손패가 HAND_SIZE 가 될 때까지 뽑는다. 뽑은 키 목록을 돌려준다.
func draw_to_hand() -> Array:
	return _draw(D.HAND_SIZE - hand.size())


## n 장 뽑는다(HAND_MAX 까지). 뽑을 패가 비면 버림패를 섞어 넣는다. 쓰러진 동료의 카드는 건너뛴다.
func _draw(n: int) -> Array:
	var drawn: Array = []
	var skipped: Array = []
	var guard := 0
	while drawn.size() < n and hand.size() < D.HAND_MAX and guard < 200:
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

## 레벨업 때 보여 줄 새 카드 셋. 첫 레벨업은 A축·B축·공용을 하나씩, 이후는 등급·이미 가진 축으로 가중치를 둔 무작위(겹치지 않게).
func level_options(u: Unit) -> Array:
	var pool: Array = Array(D.HEROES[u.kind].get("pool", [])).filter(func(c):
		return String(D.card(c).get("rarity", "common")) != "rare" or u.level >= D.RARE_FROM_LEVEL)
	if pool.is_empty():
		return []
	if u.picks == 0:
		var out: Array = []
		for tag in ["A", "B", "core"]:
			var group := pool.filter(func(c): return String(D.card(c).get("tag", "core")) == tag and not c in out)
			if not group.is_empty():
				out.append(group[rng.randi_range(0, group.size() - 1)])
		for c in _weighted(pool.filter(func(x): return not x in out), u, D.LEVEL_OPTIONS - out.size()):
			out.append(c)
		return out
	return _weighted(pool, u, D.LEVEL_OPTIONS)


func _weighted(pool: Array, u: Unit, n: int) -> Array:
	var owned := {}
	for c in u.deck:
		var t := String(D.card(c).get("tag", "core"))
		if t != "core":
			owned[t] = true
	var left := pool.duplicate()
	var out: Array = []
	while out.size() < n and not left.is_empty():
		var total := 0.0
		var ws: Array = []
		for c in left:
			var card := D.card(c)
			var w: float = float(D.RARITY_WEIGHT.get(String(card.get("rarity", "common")), 1.0))
			if owned.has(String(card.get("tag", "core"))):
				w *= D.TAG_WEIGHT
			ws.append(w)
			total += w
		var r := rng.randf() * total
		var pick := 0
		for i in ws.size():
			r -= ws[i]
			if r <= 0.0:
				pick = i
				break
		out.append(left[pick])
		left.remove_at(pick)
	return out


## 레벨업 때 함께 보여 줄 강화 후보(덱에서 아직 강화하지 않은 카드 하나). 없으면 "".
func upgrade_option(u: Unit) -> String:
	var cands := u.deck.filter(func(c): return not String(c).ends_with("+") and D.can_upgrade(c))
	if cands.is_empty():
		return ""
	return cands[rng.randi_range(0, cands.size() - 1)]


## 덱의 카드 하나를 강화한다("id" → "id+"). 전투 중이면 더미(뽑을 패 → 버림패 → 손패 순)의 같은 카드 하나도 바꾼다.
func upgrade_card(u: Unit, card_id: String) -> void:
	var i := u.deck.find(card_id)
	if i < 0:
		return
	u.deck[i] = card_id + "+"
	for pile in [draw_pile, discard, hand]:
		for j in pile.size():
			if D.base_id(pile[j]) == card_id:
				pile[j] = _new_key(card_id + "+")
				return


## 고른 카드를 덱에 넣는다. 전투 중이면 뽑을 패에도 섞어 넣는다(이번 방에서 바로 나올 수 있게).
func add_card(u: Unit, card_id: String) -> void:
	u.deck.append(card_id)
	u.picks += 1
	if phase in ["player", "enemy"]:
		draw_pile.insert(rng.randi_range(0, draw_pile.size()), _new_key(card_id))


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

## 아군 턴 시작: 모든 캐릭터 행동력 AP_MAX, 방어 초기화(굳건함이면 전사는 유지), 연계 초기화, 한기, 손패를 HAND_SIZE 까지.
func begin_player_turn() -> Array:
	turn += 1
	phase = "player"
	refill_ap()
	last_hero = ""
	played.clear()
	cost_cut.clear()
	for u in allies():
		if not (u.kind == "warrior" and powers.has("barricade")):
			u.block = 0
	var ev: Array = []
	var drawn := draw_to_hand()
	ev.append({"type": "turn", "side": "player", "turn": turn, "drawn": drawn})
	if powers.has("chill_aura"):
		var src := hero("mage")
		ev.append({"type": "aura", "power": "chill_aura", "unit": src.id if src != null else 0})
		for e in enemies():
			_add_chill(e, int(powers.chill_aura), src, ev)
		_check_end(ev)
	return ev


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


## 지금 낼 때의 비용(명상으로 줄어든 비용 포함).
func cost_of(card_key: String) -> int:
	var card := D.card(card_key)
	return maxi(0, int(card.cost) - int(cost_cut.get(String(card.hero), 0)))


## 이 카드의 연계 조건(직전 카드의 주인)이 맞는가.
func combo_active(card_key: String) -> bool:
	var card := D.card(card_key)
	return card.has("combo") and last_hero != "" and String(card.combo.hero) == last_hero


## 연계가 맞으면 combo 효과를 입힌 카드 정의(숫자는 더하고 참/거짓은 덮어쓴다).
func card_eff(card_key: String) -> Dictionary:
	var card := D.card(card_key)
	if not combo_active(card_key):
		return card
	var c := card.duplicate()
	for k in card.combo:
		if k == "hero":
			continue
		var v = card.combo[k]
		if typeof(v) == TYPE_INT and c.has(k):
			c[k] = int(c[k]) + v
		else:
			c[k] = v
	return c


## 손패의 이 카드를 지금 낼 수 있는가(행동력·주인 생존). 대상이 하나라도 있는지는 has_targets.
func affordable(card_id: String) -> bool:
	var o := card_owner(card_id)
	return phase == "player" and card_id in hand and o != null and o.ap >= cost_of(card_id)


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
	var combo := combo_active(card_key)
	var card := card_eff(card_key)
	var card_id := D.root_id(card_key)
	var o := card_owner(card_key)
	var t := String(card.target)
	if t != "none" and cells_hit(card_key, center).is_empty():
		return []
	var h := String(card.hero)
	o.ap -= cost_of(card_key)
	cost_cut.erase(h)   # 명상의 비용 감소는 다음 한 장에만(이 카드가 명상이면 아래에서 새로 건다)
	hand.erase(card_key)
	if card.get("exhaust", false) or card.has("power"):
		exhausted.append(card_key)
	else:
		discard.append(card_key)
	var ev: Array = []
	var cast := {"type": "cast", "unit": o.id, "card": card_id, "key": card_key, "center": center,
		"cells": area_of(card_key, center), "targets": [], "combo": combo}
	ev.append(cast)
	if t == "none":
		cast.center = o.cell
	# 자기·아군 효과
	if card.has("self_damage"):
		_hit(o, int(card.self_damage), null, ev, "self")
	if card.has("block_all"):
		for a in allies():
			_gain_block(a, int(card.block_all), ev)
	if card.has("block"):
		_gain_block(o, int(card.block), ev)
	if card.has("block_per_frozen"):
		var w := hero("warrior")
		var n := enemies().filter(func(e): return e.frozen).size()
		if w != null and not w.dead and n > 0:
			_gain_block(w, n * int(card.block_per_frozen), ev)
	if card.has("heal"):
		_heal(o, int(card.heal), ev)
	if card.has("heal_all"):
		for a in allies():
			_heal(a, int(card.heal_all), ev)
	if card.get("taunt", false):
		o.taunt = true
		ev.append({"type": "status", "unit": o.id, "status": "taunt", "value": 1, "delta": 1})
	if card.has("fury"):
		_add_fury(o, int(card.fury), ev)
	if card.has("power"):
		for p in card.power:
			powers[p] = int(powers.get(p, 0)) + int(card.power[p])
			ev.append({"type": "power", "unit": o.id, "power": p, "value": powers[p]})
	if card.has("cost_cut"):
		cost_cut[h] = int(cost_cut.get(h, 0)) + int(card.cost_cut)
	if card.has("create"):
		var made: Array = []
		for i in int(card.create.n):
			if hand.size() >= D.HAND_MAX:
				break
			var k := _new_key(String(card.create.card))
			hand.append(k)
			made.append(k)
		ev.append({"type": "create", "unit": o.id, "keys": made})
	# 적 효과
	match card_id:
		"chain_lightning":
			_chain(cells_hit(card_key, center)[0], card, o, cast, ev)
		"arrow_storm":
			var n := int(played.get(h, 0)) + int(card.storm)
			for i in n:
				var live := enemies()
				if live.is_empty():
					break
				var e: Unit = live[rng.randi_range(0, live.size() - 1)]
				cast.targets.append(e.id)
				_card_hit(e, int(card.damage), o, card, ev)
		_:
			var targets: Array = cells_hit(card_key, center) if t != "none" else units_in(area_of(card_key, o.cell), "enemy")
			# 밀치는 카드는 앞(아군 쪽) 적부터: 앞의 적이 뒤의 적에 부딪혀 충돌이 이어진다
			if card.has("push"):
				targets.sort_custom(func(a, b): return a.cell.x < b.cell.x)
			for e in targets:
				cast.targets.append(e.id)
				_card_effects(e, card, o, center, ev)
	if card.has("discard"):
		_auto_discard(int(card.discard), ev)
	if card.has("draw"):
		var got := _draw(int(card.draw))
		ev.append({"type": "draw", "keys": got})
	played[h] = int(played.get(h, 0)) + 1
	last_hero = h
	_check_end(ev)
	return ev


## 일반 카드가 적 하나에게 주는 효과: 피해(hits 번) → 표식 → 냉기 → 화상 → 파쇄 → 밀침/당김 → 처치 보상.
func _card_effects(e: Unit, card: Dictionary, o: Unit, center: Vector2i, ev: Array) -> void:
	var base := 0
	if card.get("block_dmg", false):
		base = o.block
	elif card.has("damage") or card.has("aura"):
		base = int(card.get("damage", card.get("aura", 0)))
	if card.has("mark_scale"):
		base += e.mark * int(card.mark_scale)
	if base > 0 or card.get("block_dmg", false):
		for k in int(card.get("hits", 1)):
			if e.dead:
				break
			_card_hit(e, base, o, card, ev)
	if e.dead:
		if card.has("kill_draw"):
			ev.append({"type": "draw", "keys": _draw(int(card.kill_draw))})
		return
	if card.has("mark_if") and e.mark > 0:
		_add_mark(e, int(card.mark_if), ev)
	if card.get("mark_double", false) and e.mark > 0:
		_add_mark(e, e.mark, ev)
	if card.has("mark_add"):
		_add_mark(e, int(card.mark_add), ev)
	if card.get("mark_clear", false) and e.mark > 0:
		e.mark = 0
		_status(e, "mark", 0, ev)
	if card.has("chill"):
		_add_chill(e, int(card.get("chill_center", card.chill)) if e.cell == center else int(card.chill), o, ev)
	if card.has("burn"):
		_add_burn(e, int(card.burn), o, ev)
	if card.get("burn_double", false) and e.burn > 0:
		_add_burn(e, e.burn, o, ev)
	if card.get("burn_spread", false) and e.burn > 0:
		for n in enemies():
			if n != e and absi(n.cell.x - e.cell.x) <= 1 and absi(n.cell.y - e.cell.y) <= 1:
				_add_burn(n, e.burn, o, ev)
	if card.get("shatter", false) and not e.dead:
		_shatter(e, o, ev)
	if card.has("push") and not e.dead:
		_shove(e, Vector2i(1, 0), int(card.push), int(card.get("bump", D.BUMP_DAMAGE)) + int(card.get("collide_bonus", 0)), o, ev)
	if card.has("pull") and not e.dead:
		_shove(e, Vector2i(-1, 0), int(card.pull), int(card.get("bump", D.BUMP_DAMAGE)) + int(card.get("collide_bonus", 0)), o, ev)
	if e.dead and card.has("kill_draw"):
		ev.append({"type": "draw", "keys": _draw(int(card.kill_draw))})


## 카드 한 타: 전사는 투지(× fury_mult), 화살은 정조준을 더한다. 맞은 뒤 사냥 신호·불붙은 화살촉.
func _card_hit(e: Unit, base: int, o: Unit, card: Dictionary, ev: Array) -> void:
	var amount := base
	if o.kind == "warrior":
		amount += o.fury * int(card.get("fury_mult", 1))
	if card.get("token", false) and powers.has("steady_aim"):
		amount += int(powers.steady_aim)
	var marked := e.mark > 0
	_hit(e, amount, o, ev, "attack")
	if marked and powers.has("hunt_signal") and not o.dead:
		_gain_block(o, int(powers.hunt_signal), ev)
	if not e.dead and o.kind == "archer" and e.burn > 0 and powers.has("fire_tips"):
		_add_burn(e, int(powers.fire_tips), o, ev)


## 연쇄 번개: 맞힌 적에서 가장 가까운 적으로(상태가 있는 적을 먼저) 튕긴다. 전도: 첫 적의 표식·냉기·화상을 1씩 다음 적에게.
func _chain(first: Unit, card: Dictionary, o: Unit, cast: Dictionary, ev: Array) -> void:
	var carry := {"mark": first.mark > 0, "chill": first.chill > 0, "burn": first.burn > 0}
	var hit_ids: Array = []
	var cur := first
	var dmg := int(card.damage)
	for i in int(card.jumps) + 1:
		hit_ids.append(cur.id)
		cast.targets.append(cur.id)
		_card_hit(cur, dmg, o, card, ev)
		if i > 0 and not cur.dead and (carry.mark or carry.chill or carry.burn):
			ev.append({"type": "reaction", "unit": cur.id, "kind": "conduct", "amount": 0, "with": first.id})
			if carry.mark:
				_add_mark(cur, 1, ev)
			if carry.chill:
				_add_chill(cur, 1, o, ev)
			if carry.burn:
				_add_burn(cur, 1, o, ev)
		dmg -= int(card.falloff)
		cur = _nearest_enemy(cur.cell, hit_ids, true)
		if cur == null:
			break


## 낼 수 없는 카드부터(주인이 쓰러졌거나 행동력이 모자람 → 비싼 카드) n 장을 버림패로.
func _auto_discard(n: int, ev: Array) -> void:
	var order := hand.duplicate()
	order.sort_custom(func(a, b):
		var pa := 0 if affordable(a) else 1
		var pb := 0 if affordable(b) else 1
		if pa != pb:
			return pa > pb
		return cost_of(a) > cost_of(b))
	var gone: Array = []
	for k in order.slice(0, mini(n, order.size())):
		hand.erase(k)
		if D.card(k).get("token", false):
			exhausted.append(k)
		else:
			discard.append(k)
		gone.append(k)
	ev.append({"type": "discard", "keys": gone})


## 아군 턴 끝 → 적 턴(사건 목록). 표식 −1, 휘발 카드 소멸, 적마다 화상 피해 → 행동.
## 끝나면 phase 는 enemy 로 남고, 화면이 연출을 마친 뒤 begin_player_turn().
func end_player_turn() -> Array:
	if phase != "player":
		return []
	phase = "enemy"
	var ev: Array = [{"type": "turn", "side": "enemy", "turn": turn}]
	var gone: Array = []
	for k in hand.duplicate():
		if D.card(k).get("ethereal", false):
			hand.erase(k)
			exhausted.append(k)
			gone.append(k)
	if not gone.is_empty():
		ev.append({"type": "exhaust", "keys": gone})
	for e in enemies():
		if e.mark > 0:
			e.mark -= 1
			_status(e, "mark", e.mark, ev, -1)
	var order := enemies()
	order.sort_custom(func(a, b): return a.cell.x < b.cell.x or (a.cell.x == b.cell.x and a.cell.y < b.cell.y))
	for e in order:
		if e.dead or allies().is_empty():
			continue
		if e.burn > 0:
			_burn_tick(e, ev)
			if e.dead:
				continue
		_enemy_act(e, ev)
	for a in allies(true):
		a.taunt = false
	_check_end(ev)
	return ev


## 화상: burn 만큼 피해(방어·표식 무시) 후 −1. 들불이면 표식 +1.
func _burn_tick(e: Unit, ev: Array) -> void:
	ev.append({"type": "enemy", "unit": e.id, "action": "burn"})
	var amount := e.burn
	e.burn -= 1
	_status(e, "burn", e.burn, ev, -1)
	_hit(e, amount, null, ev, "burn")
	if not e.dead and powers.has("wildfire"):
		_add_mark(e, int(powers.wildfire), ev)


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
			_status(e, "freeze", 0, ev)
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


# ───────────────────────── 상태·반응 ─────────────────────────

func _status(u: Unit, status: String, value: int, ev: Array, delta := 0) -> void:
	ev.append({"type": "status", "unit": u.id, "status": status, "value": value, "delta": delta})


func _add_fury(u: Unit, n: int, ev: Array) -> void:
	if u.dead or n <= 0 or u.fury >= D.FURY_MAX:
		return
	var before := u.fury
	u.fury = mini(D.FURY_MAX, u.fury + n)
	_status(u, "fury", u.fury, ev, u.fury - before)


func _add_mark(e: Unit, n: int, ev: Array) -> void:
	if e.dead or n <= 0 or e.mark >= D.MARK_MAX:
		return
	var before := e.mark
	e.mark = mini(D.MARK_MAX, e.mark + n)
	_status(e, "mark", e.mark, ev, e.mark - before)


## 냉기: 쌓는다. 화상이 있으면 증기 폭발, 아니면 CHILL_FREEZE 가 되는 순간 빙결(냉기 0).
func _add_chill(e: Unit, n: int, src: Unit, ev: Array) -> void:
	if e.dead or n <= 0:
		return
	e.chill += n
	_status(e, "chill", e.chill, ev, n)
	if e.burn > 0:
		_steam(e, src, ev)
	elif e.chill >= D.CHILL_FREEZE:
		e.chill = 0
		_status(e, "chill", 0, ev)
		if not e.frozen:
			e.frozen = true
			_status(e, "freeze", 1, ev, 1)


## 화상: 쌓는다. 냉기가 있으면 증기 폭발.
func _add_burn(e: Unit, n: int, src: Unit, ev: Array) -> void:
	if e.dead or n <= 0:
		return
	e.burn += n
	_status(e, "burn", e.burn, ev, n)
	if e.chill > 0:
		_steam(e, src, ev)


## 증기 폭발: (냉기 + 화상) × 배율 피해, 둘 다 사라진다. 마법사가 일으키면 배율이 크다.
func _steam(e: Unit, src: Unit, ev: Array) -> void:
	var mult := D.STEAM_MULT_MAGE if src != null and src.kind == "mage" else D.STEAM_MULT
	var amount := (e.chill + e.burn) * mult
	e.chill = 0
	e.burn = 0
	ev.append({"type": "reaction", "unit": e.id, "kind": "steam", "amount": amount, "with": 0})
	_status(e, "chill", 0, ev)
	_status(e, "burn", 0, ev)
	_hit(e, amount, src, ev, "reaction")


## 파쇄: 빙결된 적이면 빙결을 깨고 추가 피해.
func _shatter(e: Unit, src: Unit, ev: Array) -> void:
	if e.dead or not e.frozen:
		return
	e.frozen = false
	ev.append({"type": "reaction", "unit": e.id, "kind": "shatter", "amount": D.SHATTER_DAMAGE, "with": 0})
	_status(e, "freeze", 0, ev, -1)
	_hit(e, D.SHATTER_DAMAGE, src, ev, "reaction")


## 밀침(dir +x)·당김(dir −x)을 steps 칸. 막히면(벽·다른 적) 그 자리에서 충돌: 밀린 적과 부딪힌 적 모두 bump 피해(+벽 몰이),
## 빙결된 쪽은 파쇄. 벽 몰이면 충돌마다 전사 투지 +1. 당김은 아군 지역 경계에서 그냥 멈춘다.
func _shove(u: Unit, dir: Vector2i, steps: int, bump: int, src: Unit, ev: Array) -> void:
	for s in steps:
		if u.dead:
			return
		var to := u.cell + dir
		var other := at(to)
		if D.is_enemy_cell(to) and other == null:
			ev.append({"type": "push", "unit": u.id, "from": u.cell, "to": to, "bumped": false})
			u.cell = to
			continue
		if dir.x < 0 and not D.is_enemy_cell(to):
			return
		var dmg := bump + int(powers.get("wall_drive", 0))
		ev.append({"type": "push", "unit": u.id, "from": u.cell, "to": u.cell, "bumped": true})
		ev.append({"type": "reaction", "unit": u.id, "kind": "collide", "amount": dmg, "with": other.id if other != null else 0})
		_hit(u, dmg, src, ev, "collide")
		if other != null and other.team == "enemy":
			_hit(other, dmg, src, ev, "collide")
			_shatter(other, src, ev)
		_shatter(u, src, ev)
		if powers.has("wall_drive"):
			_add_fury(hero("warrior"), 1, ev)
		return


# ───────────────────────── 공용 ─────────────────────────

## 가장 가까운 적. prefer_status 면 상태(표식·냉기·화상·빙결)가 있는 적을 먼저.
func _nearest_enemy(from: Vector2i, exclude: Array, prefer_status := false) -> Unit:
	var best: Unit = null
	var bd := INF
	for e in enemies():
		if e.id in exclude:
			continue
		var d := Vector2(e.cell - from).length()
		if prefer_status and (e.mark > 0 or e.chill > 0 or e.burn > 0 or e.frozen):
			d -= 100.0
		if d < bd:
			bd = d
			best = e
	return best


## 피해. 적의 표식은 화상을 뺀 모든 아군 피해에 붙는다. 화상·자해는 방어를 무시한다.
## 전사가 적에게 맞으면 투지 +1, 가시 갑옷이면 반사. 궁수가 표식 적을 처치하면 행동력 +1.
func _hit(u: Unit, amount: int, src: Unit, ev: Array, kind := "attack") -> void:
	if u == null or u.dead:
		return
	var marked := u.mark > 0
	if u.team == "enemy" and marked and kind != "burn":
		amount += u.mark
	var blocked := 0 if kind in ["burn", "self"] else mini(u.block, amount)
	u.block -= blocked
	var dmg := amount - blocked
	u.hp = maxi(0, u.hp - dmg)
	ev.append({"type": "damage", "unit": u.id, "amount": dmg, "blocked": blocked, "hp": u.hp, "src": src.id if src != null else 0, "kind": kind})
	if u.team == "ally" and u.kind == "warrior" and src != null and src.team == "enemy" and u.hp > 0:
		_add_fury(u, 1, ev)
		if powers.has("thorns") and not src.dead:
			_hit(src, int(powers.thorns), u, ev, "reflect")
	if u.hp <= 0:
		u.dead = true
		u.taunt = false
		ev.append({"type": "death", "unit": u.id})
		if u.team == "enemy":
			var gain := int(u.def().get("xp", 0))
			for a in allies():
				_gain_xp(a, gain + (D.XP_KILL_BONUS if src != null and a.id == src.id else 0), src != null and a.id == src.id, ev)
			if marked and src != null and src.kind == "archer" and not src.dead and phase == "player":
				src.ap += 1
				ev.append({"type": "ap", "unit": src.id, "amount": 1, "ap": src.ap})


func _heal(u: Unit, amount: int, ev: Array) -> void:
	if u.dead or amount <= 0:
		return
	var got := mini(amount, u.max_hp - u.hp)
	u.hp += got
	ev.append({"type": "heal", "unit": u.id, "amount": got, "hp": u.hp})


func _gain_block(u: Unit, amount: int, ev: Array) -> void:
	u.block += amount
	ev.append({"type": "block", "unit": u.id, "amount": amount, "total": u.block})


func _check_end(ev: Array) -> void:
	if phase in ["clear", "defeat"]:
		return
	if enemies().is_empty():
		phase = "clear"
		ev.append({"type": "room_clear"})
	elif allies().is_empty():
		phase = "defeat"
		ev.append({"type": "defeat"})
