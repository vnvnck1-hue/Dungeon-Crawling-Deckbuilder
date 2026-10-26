extends "res://scripts/game/card_module.gd"
## 전설 카드 5장 + 광석 v1(docs/legend-cards-v01.md, 카드 검토 승인 2026-10-25).
## 하스스톤 명카드에서 가져온 전설: 서리 여왕의 왕관(자락서스)·망자의 왕관(리치 왕)·폭주하는 마법서(요그사론)·
## 불의 정령 화로(라그나로스)·겨울의 끝 종(데스윙). 드워프 재료 광석(dwa-09).
## 왕관은 한 판에 하나(crown). 화로는 card_facility.gd 의 "fire_brazier", 얼음창은 actors/ice_lance.gd, 불덩이는 actors/fireball.gd.
## 수치는 모두 시험값이다.

const SessionScript := preload("res://scripts/game/game_session.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const FrostRuneScript := preload("res://scripts/actors/frost_rune.gd")
const FireballScript := preload("res://scripts/actors/fireball.gd")

const CARD_IDS := ["ore", "frost_crown", "lich_crown", "wild_grimoire", "fire_brazier", "winter_bell"]
const LEGENDS := ["frost_crown", "lich_crown", "wild_grimoire", "fire_brazier", "winter_bell"]

# ── 광석 ──
const ORE_FACILITY_HP := 0.4          # 카드 시설 최대 체력 +40% · 완전 수리
const ORE_FACILITY_MAX := 2           # 시설마다
const ORE_WEAPON_DAMAGE := 0.1        # 무기 피해 +10%
const ORE_WEAPON_MAX := 3             # 무기마다
# ── 서리 여왕 ──
const LANCE_PIERCE := 3
const LANCE_SLOW := 0.6
const LANCE_SLOW_TIME := 2.0
# ── 폭주하는 마법서 ──
const GRIMOIRE_MIN := 3               # 바닥선(요그사론 교훈: 결과의 바닥을 둔다)
const GRIMOIRE_MAX := 15
const GRIMOIRE_INTERVAL := 0.3
const GRIMOIRE_FIRE_DAMAGE := 30.0
const GRIMOIRE_FIRE_RADIUS := 1.5
const GRIMOIRE_VINE_RADIUS := 2.0
const GRIMOIRE_VINE_DAMAGE := 10.0
const GRIMOIRE_HEAL := 12.0
const GRIMOIRE_SPELLS := [["fire", 35], ["frost", 25], ["vine", 20], ["heal", 20]]
# ── 불의 정령 화로 ──
const BRAZIER_RANGE := 9.0            # 산장 중심에서 이 안의 땅에만
const BRAZIER_INTERVAL := 7.0
const BRAZIER_REACH := 14.0
const BRAZIER_DAMAGE := 40.0
const BRAZIER_RADIUS := 1.6
# ── 겨울의 끝 종 ──
const BELL_BOSS_DAMAGE := 0.3         # 보스는 최대 체력의 이 비율만
# ── 얻는 길 ──
const LEGEND_FROM_DAY := 3
const LEGEND_CHANCE := 0.14
const LICH_UNDEAD_WEIGHT := 3

var crown := ""                  # "" | "frost" | "lich" — 한 판에 하나
var spells_cast := 0             # 이번 판에 쓴 주문(kind spell) 카드 수(마법서 자신 제외)
var offered: Array = []          # 이번 판 새벽 보상에 이미 나온 전설
var forge: Dictionary = {}       # 무기 카드 uid → 광석 강화 횟수
var reinforced: Dictionary = {}  # 시설 instance id → 광석 보강 횟수
var grimoire_left := 0           # 남은 폭주 주문 수
var _grimoire_t := 0.0
var _grimoire_at := Vector3.ZERO
var _brazier_t: Dictionary = {}  # 화로 instance id → 다음 불덩이까지 남은 초
var _crown_node: Node3D
var _rng := RandomNumberGenerator.new()
var stats := {"crowns": 0, "frost_runes": 0, "lich_cards": 0, "grimoire_spells": 0, "brazier_fireballs": 0,
	"bell_kills": 0, "bell_facilities": 0, "bell_discarded": 0, "ore_sold": 0, "ore_facility": 0, "ore_weapon": 0, "legend_offers": 0}


func _ready() -> void:
	name = "LegendCards"
	_rng.randomize()
	if game.get("session") != null and game.session != null:
		game.session.state_changed.connect(_on_state)
	if game.get("cards") != null and game.cards != null and game.cards.has_signal("card_used"):
		game.cards.card_used.connect(on_card_used)


func handles(id: String) -> bool:
	return id in CARD_IDS


func rc():
	return game.race_cards


func _name(id: String) -> String:
	return game.cards.def(id).get("name", id)


# ───────────────────────── 주문 세기·얻는 길 ─────────────────────────

## 카드 사용 확정(card_inventory.card_used): 주문 카드면 센다.
func on_card_used(id: String) -> void:
	if id != "wild_grimoire" and str(game.cards.def(id).get("kind", "")) == "spell":
		spells_cast += 1


func grimoire_count() -> int:
	return clampi(spells_cast, GRIMOIRE_MIN, GRIMOIRE_MAX)


## 새벽 보상(chapter_director.reward_choices): 3일차부터 가끔 후보 하나가 이번 판에 아직 안 나온 전설로 바뀐다.
## 서리 여왕의 눈물이 있으면 서리 여왕의 왕관이 반드시 나온다. 언데드가 열렸으면 망자의 왕관이 잘 나온다.
func mix_reward(choices: Array, day := -1) -> Array:
	if choices.is_empty():
		return choices
	if day < 0:
		day = game.session.day()
	var pick := ""
	if crown == "" and not "frost_crown" in offered and game.get("relics") != null and game.relics.has("frost_queen_tear"):
		pick = "frost_crown"
	elif day >= LEGEND_FROM_DAY and _rng.randf() < LEGEND_CHANCE:
		pick = _roll_legend()
	if pick == "" or not game.cards.defs.has(pick):
		return choices
	offered.append(pick)
	stats["legend_offers"] += 1
	var out := choices.duplicate()
	out[0] = pick
	return out


func _roll_legend() -> String:
	var bag: Array = []
	for id in LEGENDS:
		if id in offered or (crown != "" and id.ends_with("_crown")):
			continue
		var w := 1
		if id == "lich_crown" and game.get("undead") != null and game.undead.unlocked:
			w = LICH_UNDEAD_WEIGHT
		for i in w:
			bag.append(id)
	return "" if bag.is_empty() else bag[_rng.randi_range(0, bag.size() - 1)]


# ───────────────────────── 광석 ─────────────────────────

## 광석 강화가 붙은 무기를 낀 착용자의 피해 배율(equipment.damage_mult 가 곱한다).
func forge_mult(holder) -> float:
	var gear = holder.get("gear") if holder != null else null
	if gear == null or not gear.has("weapon"):
		return 1.0
	return 1.0 + ORE_WEAPON_DAMAGE * int(forge.get(int(gear["weapon"].get("uid", -1)), 0))


func _facility_at(sp: Vector2, r):
	var cam: Camera3D = game.world.camera
	var best = null
	var best_d := 60.0
	for f in rc().facilities():
		var wp: Vector3 = f.global_position + Vector3(0, f.hp_offset * 0.5, 0)
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(sp)
		if d < best_d:
			best_d = d
			best = f
	return best


func _eval_ore(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	if r._lodge_hit(sp):
		return r._eval_wool(entry, sp)   # 산장 교역 판매(기존 판매 창)
	var f = _facility_at(sp, r)
	if f != null:
		var n := int(reinforced.get(f.get_instance_id(), 0))
		if n >= ORE_FACILITY_MAX:
			return _fail("이 시설은 이미 광석으로 %d번 보강했습니다" % ORE_FACILITY_MAX, f.global_position)
		return {"ok": true, "pos": f.global_position, "facility": f, "title": "광석 — %s 보강" % f.display_name(),
			"lines": ["최대 체력 +%d%% · 완전 수리 (%d → %d)" % [int(ORE_FACILITY_HP * 100.0), int(f.max_hp), int(f.max_hp * (1.0 + ORE_FACILITY_HP))],
				"보강 %d/%d · 광석 1개 소비" % [n + 1, ORE_FACILITY_MAX]]}
	var h = r.gear_target(sp)
	if h != null:
		var w: Dictionary = game.equipment.equipped(h, "weapon")
		if w.is_empty():
			return _fail("무기를 낀 마녀나 용병에게 놓아야 무기를 벼립니다", h.global_position)
		var k := int(forge.get(int(w["uid"]), 0))
		if k >= ORE_WEAPON_MAX:
			return _fail("이 무기는 이미 %d번 벼렸습니다" % ORE_WEAPON_MAX, h.global_position)
		return {"ok": true, "pos": h.global_position, "holder": h, "weapon_uid": int(w["uid"]),
			"title": "광석 — %s 벼리기" % _name(str(w["id"])),
			"lines": ["%s의 무기 피해 +%d%% (무기를 옮겨 끼어도 유지)" % [game.equipment.holder_name(h), int(ORE_WEAPON_DAMAGE * 100.0)],
				"벼림 %d/%d · 광석 1개 소비" % [k + 1, ORE_WEAPON_MAX]]}
	return _fail("산장(판매)·카드 시설(보강)·무기를 낀 마녀나 용병(벼리기)에 놓으세요")


# ───────────────────────── 판정 ─────────────────────────

func evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var plan := _evaluate(entry, sp, r)
	if plan.get("ok", false) and not plan.has("action"):
		plan["action"] = "legend"
		plan["legend_card"] = entry["id"]
	return plan


func _witch_target(sp: Vector2, r) -> bool:
	return r.player_hit(sp) or r.frame_holder_at(sp) == game.player


func _evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var id: String = entry["id"]
	match id:
		"ore":
			return _eval_ore(entry, sp, r)
		"frost_crown", "lich_crown":
			if not _witch_target(sp, r):
				return _fail("마녀에게 씌웁니다 (초상에 놓아도 됩니다)")
			if crown != "":
				return _fail("마녀는 이미 다른 왕관을 썼습니다 — 왕관은 한 판에 하나", game.player.global_position)
			if id == "frost_crown":
				return {"ok": true, "pos": game.player.global_position, "title": "서리 여왕의 왕관",
					"lines": ["이번 판 끝까지 마법탄이 얼음창 — 적 %d마리 관통 · %d초 둔화" % [LANCE_PIERCE, int(LANCE_SLOW_TIME)],
						"밤이 올 때마다 서리 룬 1장 · 왕관은 한 판에 하나"]}
			return {"ok": true, "pos": game.player.global_position, "title": "망자의 왕관",
				"lines": ["이번 판 끝까지 새벽마다 언데드 카드 1장",
					("언데드가 지금 열림 · " if game.get("undead") != null and not game.undead.unlocked else "") + "왕관은 한 판에 하나"]}
		"wild_grimoire":
			if not _night():
				return _fail("폭주하는 마법서는 밤 전투 중에만 펼칠 수 있습니다")
			if grimoire_left > 0:
				return _fail("마법서가 아직 폭주하고 있습니다")
			return {"ok": true, "pos": game.player.global_position, "title": "폭주하는 마법서",
				"lines": ["이번 판에 쓴 주문 %d장 → 무작위 주문 %d번 (최소 %d · 최대 %d)" % [spells_cast, grimoire_count(), GRIMOIRE_MIN, GRIMOIRE_MAX],
					"불덩이·서리·덩굴·치유 · 산장과 아군은 다치지 않음"]}
		"winter_bell":
			if not _night():
				return _fail("겨울의 끝 종은 밤 전투 중에만 울립니다")
			var foes: int = game.get_tree().get_nodes_in_group("enemies").filter(func(e): return not e.dead).size()
			return {"ok": true, "pos": game.player.global_position, "title": "겨울의 끝 종",
				"lines": ["적 %d마리 모두 쓰러짐 (보스는 체력 %d%%) · 우리 시설 %d개 무너짐" % [foes, int(BELL_BOSS_DAMAGE * 100.0), _our_structures().size()],
					"손패 %d장을 모두 버림 (침식 포함)" % (game.cards.hand().size() - 1)]}
		"fire_brazier":
			var p = _point(sp, r)
			if p is String:
				return _fail(p)
			if _flat(p, game.world.lodge.global_position) > BRAZIER_RANGE:
				return _fail("산장 가까이(%dm 안)에 세워야 합니다" % int(BRAZIER_RANGE), p)
			if not rc().facilities("fire_brazier").is_empty():
				return _fail("불의 정령 화로는 하나만 세울 수 있습니다", p)
			return {"ok": true, "pos": p, "title": "불의 정령 화로",
				"lines": ["체력 %d 시설 · 스스로 싸우지 않음" % int(preload("res://scripts/actors/card_facility.gd").SPECS["fire_brazier"]["hp"]),
					"밤에 %d초마다 %dm 안 무작위 적에게 큰 불덩이 (피해 %d) · 카드 1장 소비" % [int(BRAZIER_INTERVAL), int(BRAZIER_REACH), int(BRAZIER_DAMAGE)]]}
	return _fail("사용할 수 없는 카드입니다")


# ───────────────────────── 사용 ─────────────────────────

func commit(uid: int, plan: Dictionary, r) -> Dictionary:
	var id: String = plan["legend_card"]
	if not game.cards.consume(uid):
		return _fail("카드가 없습니다")
	match id:
		"ore":
			if plan.has("facility"):
				var f = plan["facility"]
				f.max_hp *= 1.0 + ORE_FACILITY_HP
				f.hp = f.max_hp
				reinforced[f.get_instance_id()] = int(reinforced.get(f.get_instance_id(), 0)) + 1
				stats["ore_facility"] += 1
				Fx.heal(f.global_position + Vector3(0, 1.0, 0))
				game.toast("광석으로 %s을(를) 보강했습니다 — 체력 %d" % [f.display_name(), int(f.max_hp)], Color(0.8, 0.88, 1.0))
			else:
				var wu: int = plan["weapon_uid"]
				forge[wu] = int(forge.get(wu, 0)) + 1
				stats["ore_weapon"] += 1
				Fx.celebrate(plan["holder"].global_position + Vector3(0, 1.4, 0), Color(0.75, 0.85, 1.0), 0.6)
				game.toast("광석으로 무기를 벼렸습니다 — 피해 +%d%%" % int(ORE_WEAPON_DAMAGE * 100.0 * int(forge[wu])), Color(0.8, 0.88, 1.0))
		"frost_crown", "lich_crown":
			put_on_crown("frost" if id == "frost_crown" else "lich")
		"wild_grimoire":
			grimoire_left = grimoire_count()
			_grimoire_t = 0.0
			_grimoire_at = game.player.global_position
			Fx.celebrate(game.player.global_position + Vector3(0, 1.6, 0), Color(0.8, 0.5, 1.0), 1.2)
			game.toast("폭주하는 마법서 — 주문 %d개가 터져 나옵니다!" % grimoire_left, Color(0.85, 0.65, 1.0))
		"fire_brazier":
			var b = rc()._build("fire_brazier", plan["pos"])
			_brazier_t[b.get_instance_id()] = 1.5
			game.toast("불의 정령 화로를 세웠습니다 — 밤이면 불덩이를 떨굽니다", Color(1.0, 0.7, 0.4))
		"winter_bell":
			ring_bell()
	game.sounds.play_or("card_play", "card_play")
	return plan


## 왕관 쓰기(한 판에 하나). 망자의 왕관은 언데드를 연다. 밤에 쓴 서리 여왕은 그 밤 서리 룬도 바로 받는다.
func put_on_crown(kind: String) -> void:
	crown = kind
	stats["crowns"] += 1
	_attach_crown_visual()
	var p = game.player
	if kind == "frost":
		Fx.celebrate(p.global_position + Vector3(0, 1.2, 0), Color(0.6, 0.85, 1.0), 1.2)
		game.toast("서리 여왕의 왕관 — 마녀가 서리 여왕이 되었습니다 · 마법탄이 얼음창이 됩니다", Color(0.7, 0.9, 1.0))
		if _night():
			_give_frost_rune()
	else:
		Fx.soul(p.global_position + Vector3(0, 1.2, 0))
		if game.get("undead") != null and not game.undead.unlocked:
			game.undead.unlocked = true
		game.toast("망자의 왕관 — 마녀가 망자의 군주가 되었습니다 · 새벽마다 언데드 카드", Color(0.8, 0.65, 1.0))
	game.sounds.play_or("crown_on", "relic_get")


func frost_queen() -> bool:
	return crown == "frost"


func lance_stats() -> Dictionary:
	return {"pierce": LANCE_PIERCE, "slow": LANCE_SLOW, "slow_time": LANCE_SLOW_TIME}


func _give_frost_rune() -> void:
	game.cards.add("frost_rune")
	stats["frost_runes"] += 1
	game.toast("서리 여왕 — 서리 룬 1장", Color(0.7, 0.9, 1.0))


func _give_lich_card() -> void:
	if game.get("undead") == null:
		return
	var pick: Array = game.undead.undead_choices(1)
	if pick.is_empty():
		return
	game.cards.add(pick[0])
	stats["lich_cards"] += 1
	game.toast("망자의 군주 — 새벽에 '%s' 카드가 손에 들려 있습니다" % _name(pick[0]), Color(0.8, 0.65, 1.0))


## 머리 위에 떠 도는 작은 왕관(블록아웃). 서리 = 얼음 가시, 망자 = 검은 뼈 가시와 보랏빛.
func _attach_crown_visual() -> void:
	var p = game.player
	if p == null or p.get("body") == null:
		return
	if _crown_node != null and is_instance_valid(_crown_node):
		_crown_node.queue_free()
	_crown_node = B.node(p.body, Vector3(0, 2.2, 0), Vector3.ZERO, "LegendCrown")
	var frost := crown == "frost"
	var band: Material = Mats.glow(Color(0.7, 0.9, 1.0), 2.5) if frost else Mats.solid(Color(0.16, 0.14, 0.18))
	var spike: Material = Mats.glow(Color(0.85, 0.97, 1.0), 3.0) if frost else Mats.solid(Color(0.86, 0.83, 0.72))
	B.torus(_crown_node, 0.15, 0.2, Vector3.ZERO, band)
	for i in 6:
		var a := TAU * i / 6.0
		B.prism(_crown_node, Vector3(0.06, 0.16 if i % 2 == 0 else 0.11, 0.06), Vector3(cos(a) * 0.18, 0.08, sin(a) * 0.18), spike)
	B.omni(_crown_node, Vector3(0, 0.1, 0), Color(0.6, 0.85, 1.0) if frost else Color(0.7, 0.45, 1.0), 0.9, 1.6, false, 1.0)


# ───────────────────────── 겨울의 끝 종 ─────────────────────────

func _our_structures() -> Array:
	var out: Array = rc().facilities()
	for g in ["junk_barricades", "ward_lanterns", "thorn_plants"]:
		for n in game.get_tree().get_nodes_in_group(g):
			if not n.get("dead"):
				out.append(n)
	return out


## 모든 적이 쓰러지고(보스는 일부만), 우리 시설이 무너지고, 손패를 전부 버린다. 마녀·용병·산장은 다치지 않는다.
func ring_bell() -> void:
	var kills := 0
	for e in game.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if e.get("is_boss") == true or e.is_in_group("bosses"):
			e.take_damage(float(e.max_hp) * BELL_BOSS_DAMAGE)
		else:
			e.take_damage(maxf(float(e.get("hp") if e.get("hp") != null else 0.0), 1.0) + 99999.0)
			if e.dead:
				kills += 1
		Fx.hit(e.global_position + Vector3(0, 0.7, 0), Color(0.85, 0.95, 1.0), true)
	var fell := 0
	for s in _our_structures():
		if s.has_method("collapse"):
			s.collapse()
		elif s.has_method("extinguish"):
			s.extinguish()
		elif s.has_method("take_damage"):
			s.take_damage(99999.0)
		fell += 1
	var dropped: int = game.cards.discard_hand()
	stats["bell_kills"] += kills
	stats["bell_facilities"] += fell
	stats["bell_discarded"] += dropped
	game.world.shake(0.35, 0.8)
	Fx.celebrate(game.world.lodge.global_position + Vector3(0, 3.0, 0), Color(0.85, 0.95, 1.0), 2.0)
	game.sounds.play_or("winter_bell", "boss_roar")
	game.toast("겨울의 끝 종 — 적 %d마리가 쓰러지고 시설 %d개가 무너졌습니다 · 손패 %d장을 버렸습니다" % [kills, fell, dropped], Color(0.85, 0.95, 1.0))


# ───────────────────────── 매 프레임: 마법서 폭주·화로 불덩이 ─────────────────────────

func _process(delta: float) -> void:
	if game == null or game.get("session") == null or game.session == null or game.get_tree().paused:
		return
	if grimoire_left > 0:
		if not _night():
			grimoire_left = 0
		else:
			_grimoire_t -= delta
			if _grimoire_t <= 0.0:
				_grimoire_t = GRIMOIRE_INTERVAL
				grimoire_left -= 1
				cast_random_spell()
	if _night():
		for f in rc().facilities("fire_brazier"):
			var k: int = f.get_instance_id()
			var t: float = float(_brazier_t.get(k, BRAZIER_INTERVAL)) - delta
			if t <= 0.0:
				t = BRAZIER_INTERVAL if brazier_fire(f) else 0.5
			_brazier_t[k] = t


func _alive_enemies(center := Vector3.INF, reach := INF) -> Array:
	return game.get_tree().get_nodes_in_group("enemies").filter(func(e):
		return not e.dead and (center == Vector3.INF or _flat(e.global_position, center) <= reach))


## 화로 하나가 불덩이 하나를 쏜다. 닿는 적이 없으면 false(잠시 뒤 다시 본다).
func brazier_fire(f) -> bool:
	var foes := _alive_enemies(f.global_position, BRAZIER_REACH)
	if foes.is_empty():
		return false
	var e = foes[_rng.randi_range(0, foes.size() - 1)]
	_throw_fireball(f.global_position + Vector3(0, 1.6, 0), e.global_position, BRAZIER_DAMAGE, BRAZIER_RADIUS, 1.25)
	stats["brazier_fireballs"] += 1
	return true


func _throw_fireball(from: Vector3, to: Vector3, damage: float, radius: float, size := 1.0) -> void:
	var fb := FireballScript.new()
	fb.game = game
	fb.start = from
	fb.target = Vector3(to.x, 0.0, to.z)
	fb.damage = damage
	fb.radius = radius
	fb.size = size
	game.actors.add_child(fb)


## 폭주 주문 하나. 대상은 무작위 적(없으면 마녀 둘레). 치유는 다친 아군이 없으면 다시 굴린다. 적만 다친다.
func cast_random_spell() -> String:
	var foes := _alive_enemies()
	var at: Vector3
	if foes.is_empty():
		var a := _rng.randf() * TAU
		at = _grimoire_at + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(2.0, 6.0)
	else:
		at = foes[_rng.randi_range(0, foes.size() - 1)].global_position
	at.y = 0.0
	var kind := _roll_spell()
	match kind:
		"fire":
			_throw_fireball(game.player.global_position + Vector3(0, 2.2, 0), at, GRIMOIRE_FIRE_DAMAGE, GRIMOIRE_FIRE_RADIUS)
		"frost":
			var rune := FrostRuneScript.new()
			rune.game = game
			rune.position = at
			game.actors.add_child(rune)
		"vine":
			game.resolver._root_burst(at, GRIMOIRE_VINE_RADIUS, GRIMOIRE_VINE_DAMAGE, preload("res://scripts/config.gd").VINE_SLOW, 2.5, Color(0.55, 0.9, 0.4), "grimoire_vine")
		"heal":
			for h in [game.player] + game.get_tree().get_nodes_in_group("allies").filter(func(x): return x.get("kind") == "merc" and not x.dead):
				if h.hp < h.max_hp:
					h.heal(GRIMOIRE_HEAL)
					Fx.heal(h.global_position + Vector3(0, 1.0, 0))
	stats["grimoire_spells"] += 1
	return kind


func _someone_hurt() -> bool:
	if game.player.hp < game.player.max_hp:
		return true
	for a in game.get_tree().get_nodes_in_group("allies"):
		if a.get("kind") == "merc" and not a.dead and a.hp < a.max_hp:
			return true
	return false


func _roll_spell() -> String:
	var hurt := _someone_hurt()
	var total := 0
	for s in GRIMOIRE_SPELLS:
		if s[0] != "heal" or hurt:
			total += int(s[1])
	var roll := _rng.randi_range(1, total)
	for s in GRIMOIRE_SPELLS:
		if s[0] == "heal" and not hurt:
			continue
		roll -= int(s[1])
		if roll <= 0:
			return s[0]
	return "fire"


# ───────────────────────── 낮밤 ─────────────────────────

func _on_state(state: int) -> void:
	if state == SessionScript.State.COMBAT:
		if crown == "frost":
			_give_frost_rune()
		for f in rc().facilities("fire_brazier"):
			_brazier_t[f.get_instance_id()] = 2.0
	elif state == SessionScript.State.PREP:
		grimoire_left = 0
		if crown == "lich":
			_give_lich_card()
