extends Node
## CardUseResolver: 드래그 중인 카드의 대상·조건 판정과 사용 확정(기획서 v0.3 §6·9).
## evaluate()는 미리보기용, commit()은 놓는 순간 같은 판정을 다시 수행한 뒤 소비와 임무 등록을 함께 확정한다.
## 무효 대상·조건 미충족은 소비하지 않는다. 화면 좌표를 그대로 소환 위치로 쓰지 않는다.

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const FrostRuneScript := preload("res://scripts/actors/frost_rune.gd")
const WardLanternScript := preload("res://scripts/actors/ward_lantern.gd")
const ThornSeedScript := preload("res://scripts/actors/thorn_seed.gd")
const ResinFireScript := preload("res://scripts/actors/resin_fire.gd")
const FireflyScript := preload("res://scripts/actors/firefly_swarm.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const EquipmentScript := preload("res://scripts/game/equipment.gd")

const PICK_ENEMY_PX := 46.0
const PICK_TREE_PX := 70.0
const PICK_PLAYER_PX := 48.0

var game


func _ready() -> void:
	name = "CardUseResolver"


# ───────────────────────── 대상 찾기 ─────────────────────────

func _ground_at(sp: Vector2):
	var cam: Camera3D = game.world.camera
	var from := cam.project_ray_origin(sp)
	var dir := cam.project_ray_normal(sp)
	if absf(dir.y) < 0.001:
		return null
	return from + dir * (-from.y / dir.y)


func _lodge_hit(sp: Vector2) -> bool:
	var cam: Camera3D = game.world.camera
	var from := cam.project_ray_origin(sp)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(sp) * 400.0, Cfg.L_OBSTACLE)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	return not hit.is_empty() and hit["collider"] == game.world.lodge


func enemy_at(sp: Vector2):
	var cam: Camera3D = game.world.camera
	var best = null
	var best_d := PICK_ENEMY_PX
	for e in game.get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if game.world.fog_of_war != null and not game.world.fog_of_war.is_visible_at(e.global_position): continue
		var d := cam.unproject_position(e.global_position + Vector3(0, 0.7, 0)).distance_to(sp)
		if d < best_d:
			best_d = d
			best = e
	return best


func tree_at(sp: Vector2):
	var t: Dictionary = game.world.tree_near_screen(sp, PICK_TREE_PX)
	return null if t.is_empty() else t


func player_hit(sp: Vector2) -> bool:
	var cam: Camera3D = game.world.camera
	var p = game.player
	if p == null or p.dead or cam.is_position_behind(p.global_position):
		return false
	return cam.unproject_position(p.global_position + Vector3(0, 1.0, 0)).distance_to(sp) < PICK_PLAYER_PX


const PICK_CAMPFIRE_PX := 60.0
const PICK_ALLY_PX := 48.0


## 화면 지점이 앞마당 모닥불을 가리키는가(불 근처 지면 또는 불꽃의 화면 위치).
func campfire_hit(sp: Vector2) -> bool:
	var yard = game.world.yard
	if yard == null or yard.campfire == null:
		return false
	var cam: Camera3D = game.world.camera
	var fire: Vector3 = yard.campfire.global_position + Vector3(0, 0.6, 0)
	if not cam.is_position_behind(fire) and cam.unproject_position(fire).distance_to(sp) < PICK_CAMPFIRE_PX:
		return true
	var g = _ground_at(sp)
	return g != null and yard.contains_ground(g)


## 화면 지점 가까이의 살아 있는 용병(하수인 제외). 없으면 null.
func merc_at(sp: Vector2):
	var cam: Camera3D = game.world.camera
	var best = null
	var best_d := PICK_ALLY_PX
	for a in game.get_tree().get_nodes_in_group("allies"):
		if a.dead or a.hidden or a.kind != "merc":
			continue
		var wp: Vector3 = a.global_position + Vector3(0, a.hp_offset * 0.5, 0)
		if cam.is_position_behind(wp):
			continue
		var d := cam.unproject_position(wp).distance_to(sp)
		if d < best_d:
			best_d = d
			best = a
	return best


## HUD 용병 초상(파티 프레임) 위의 착용자: 마녀 또는 용병. 없으면 null.
func frame_holder_at(sp: Vector2):
	var hud = game.get("hud")
	if hud == null or hud.get("party_frame") == null or hud.party_frame == null:
		return null
	return hud.party_frame.holder_at(sp)


## 용병 대상: 초상 프레임 위면 그 용병, 아니면 월드에서 가까운 용병.
func merc_target(sp: Vector2):
	var h = frame_holder_at(sp)
	if h != null and h != game.player:
		return h
	return merc_at(sp)


## 장비 대상: 초상 프레임 → 마녀(월드) → 용병(월드) 순.
func gear_target(sp: Vector2):
	var h = frame_holder_at(sp)
	if h != null:
		return h
	if player_hit(sp):
		return game.player
	return merc_at(sp)


## 지면 위치를 이동 가능한 가까운 아군 위치로 보정. 불가능하면 사유 문자열.
func valid_ground(p: Vector3):
	var nav = NavUtil.walkable_from(game.get_world_3d().navigation_map, Layout.DOOR_FRONT, p, 1.2)
	if nav == null:
		return "이동할 수 없는 곳입니다"
	var c := Vector2(Layout.CAMERA_TARGET.x, Layout.CAMERA_TARGET.z)
	if Vector2(nav.x, nav.z).distance_to(c) > Layout.BOUNDARY_RADIUS - 0.8 and not Layout.in_boss_nest(Vector2(nav.x, nav.z)):
		return "아직 발견하지 않은 숲입니다"
	if game.world.lodge.distance_to(nav) < 0.4:
		return "건물 안에는 소환할 수 없습니다"
	if game.world.pasture.inside(nav, 0.2):
		return "목장 안에는 소환할 수 없습니다"
	return nav


func work_position(tree: Dictionary) -> Vector3:
	var to: Vector3 = Layout.CAMERA_TARGET - tree["pos"]
	to.y = 0.0
	var p: Vector3 = tree["pos"] + to.normalized() * 1.0
	# 섬·포켓이 아닌, 현관에서 닿는 지면 점. 없으면 밑동 주변에서 다시 찾는다.
	var map: RID = game.get_world_3d().navigation_map
	var nav = NavUtil.walkable_from(map, Layout.DOOR_FRONT, p, Cfg.TREE_ACCESS_NAV + 0.5, 0.9)
	if nav != null: return nav
	for i in 8:
		var a := TAU * i / 8.0
		nav = NavUtil.walkable_from(map, Layout.DOOR_FRONT, tree["pos"] + Vector3(cos(a), 0, sin(a)) * 1.0, Cfg.TREE_ACCESS_NAV + 0.5, 0.9)
		if nav != null: return nav
	return NavUtil.ground_or_near(map, p)


# ───────────────────────── 판정 ─────────────────────────

## 카드 묶음 모듈: [game 의 필드 이름, 계획 action]. 판정은 이 순서로 묻는다.
## 고블린(docs/goblin-cards-v01.md) · 종족/언데드/화합(docs/race-cards-v01.md) · 에린 주점(docs/tavern-cards-v01.md) · 전설·광석(docs/legend-cards-v01.md) · 용병 고유 키트(docs/mercenary-unique-kit-v04.md)
const CARD_MODULES := [["goblin", "goblin"], ["race_cards", "race"], ["undead", "undead"], ["tavern", "tavern"], ["legend", "legend"], ["merc_kit", "merc"]]


func _fail(reason: String, where = null) -> Dictionary:
	return {"ok": false, "reason": reason, "pos": where}


## 반환: {ok, reason, action, pos, tree, enemy, title, lines}
func evaluate(uid: int, sp: Vector2) -> Dictionary:
	var entry: Dictionary = game.cards.get_entry(uid)
	if entry.is_empty():
		return _fail("카드가 없습니다")
	var s = game.session
	if s.is_over():
		return _fail("게임이 끝났습니다")
	if game.get_tree().paused:
		return _fail("일시 정지 중에는 사용할 수 없습니다")
	# 보름달 늑대는 카드를 쓸 수 없다(손패 잠김, 사용자 확정 2026-10-18)
	if game.player != null and game.player.wolf:
		return _fail("늑대는 카드를 쓸 수 없습니다")
	# 모닥불에 태우기: 목재(장작)·생고기(스튜)는 본래 쓰임이 우선이고, 그 밖의 카드는 태워 1장 뽑는다
	if campfire_hit(sp) and entry["id"] != "timber" and entry["id"] != "raw_meat":
		return _eval_burn(entry)
	# 시간대가 맞지 않는 카드(손패 전환 전에 남아 있을 수 없지만 안전장치)
	var ph: String = game.cards.phase_of(entry["id"])
	if (ph == "day" or ph == "night") and not game.cards.usable_now(entry["id"]):
		return _fail("%s에만 쓰는 카드입니다" % ("낮" if ph == "day" else "밤"))
	if EquipmentScript.is_equipment(entry["id"]):
		return _eval_equip(entry, sp)
	# 카드 묶음 모듈(고블린·종족·언데드·주점)이 맡는 카드는 판정·사용을 그 모듈에 넘긴다
	for m in CARD_MODULES:
		var module = game.get(m[0])
		if module != null and module.handles(entry["id"]):
			return module.evaluate(entry, sp, self)
	match entry["id"]:
		"lumberjack":
			return _eval_lumberjack(entry, sp)
		"hunter", "warrior", "forest_monster":
			return _eval_summon(entry, sp)
		"gatherer":
			return _eval_gatherer(entry, sp)
		"wool", "rabbit_pelt":
			return _eval_wool(entry, sp)
		"raw_meat":
			return _eval_meat(entry, sp)
		"meat_stew":
			return _eval_stew(sp)
		"treasure_chest":
			return _eval_chest(sp)
		"timber":
			return _eval_timber(entry, sp)
		"frost_rune":
			return _eval_frost(sp)
		"ward_lantern":
			return _eval_lantern(sp)
		"guest_invitation":
			return _eval_invite(sp)
		"lamb":
			return _eval_lamb(sp)
		"sleeping_thorn_seed":
			return _eval_thorn(sp)
		"black_sheep":
			return _eval_black_sheep(sp)
		"black_wool":
			return _eval_black_wool(sp)
		"poison_mushroom":
			return _eval_mushroom(sp)
		"old_spellbook":
			return _eval_spellbook(sp)
		"moss_bandage":
			return _eval_moss(sp)
		"wolf_blood":
			return _eval_wolf_blood(sp)
		"crescent_moon", "half_moon", "full_moon":
			return _eval_moon(entry, sp)
		"resin_torch":
			return _eval_ground_spell(sp, true, Cfg.RESIN_RADIUS, "resin", "송진 횃불",
				["반경 %.1fm에 %d초 동안 불길 · 초당 피해 %d" % [Cfg.RESIN_RADIUS, int(Cfg.RESIN_TIME), int(Cfg.RESIN_DPS)], "카드 1장 소비"])
		"vine_snare":
			return _eval_ground_spell(sp, true, Cfg.VINE_RADIUS, "vine", "덩굴 덫",
				["반경 %.1fm · 피해 %d · %d초 동안 거의 묶임(속도 %d%%)" % [Cfg.VINE_RADIUS, int(Cfg.VINE_DAMAGE), int(Cfg.VINE_TIME), int(Cfg.VINE_SLOW * 100.0)], "카드 1장 소비"])
		"thorn_bind":
			return _eval_ground_spell(sp, true, Cfg.THORN_BIND_RADIUS, "thorn_bind", "가시 속박 (권능)",
				["반경 %.1fm · 피해 %d · %d초 동안 속박(속도 %d%%)" % [Cfg.THORN_BIND_RADIUS, int(Cfg.THORN_BIND_DAMAGE), int(Cfg.THORN_BIND_TIME), int(Cfg.THORN_BIND_SLOW * 100.0)], "카드 1장 소비"])
		"firefly_swarm":
			return _eval_firefly(sp)
		"winter_firewood":
			return _eval_firewood(sp)
		"shroud_cloth":
			return _eval_blessing(sp, "shroud", "수의 (권능)", "오늘 밤 마녀와 아군이 치명타를 한 번씩 버팀", "ground")
		"red_chalice":
			return _eval_blessing(sp, "red_feast", "붉은 잔 (권능)", "오늘 밤 마녀의 마법탄이 피해의 %d%%만큼 회복" % int(Cfg.BLESS_LIFESTEAL * 100.0), "player")
		"hibernation_pelt":
			return _eval_blessing(sp, "pelt", "겨울잠 털가죽 (전리품)", "오늘 밤 산장이 받는 피해 %d%%" % int(Cfg.PELT_LODGE_MULT * 100.0), "lodge")
		"dragon_scale":
			return _eval_dragon_scale(sp)
	if game.cards.is_corruption(entry["id"]):
		return _fail("침식 카드는 쓸 수 없습니다 — 이끼 붕대·장날 정화로 없애세요")
	return _fail("사용할 수 없는 카드입니다")


## 나무꾼: 벌목 가능한 나무에만. 둘러싸인 나무·베인 나무·작업 중인 나무는 거부.
func _eval_lumberjack(entry: Dictionary, sp: Vector2) -> Dictionary:
	var s = game.session
	var who: String = entry["person"]
	var tree = tree_at(sp)
	if tree == null:
		return _fail("벌목할 나무에 놓으세요")
	var wp := work_position(tree)
	if s.state != SessionScript.State.PREP:
		return _fail("벌목은 평상시 낮에만 시작합니다", wp).merged({"tree": tree})
	if game.get("race_cards") != null and game.race_cards.lumber_block_reason() != "":
		return _fail(game.race_cards.lumber_block_reason(), wp).merged({"tree": tree})
	var why: String = game.world.tree_access(tree)
	if why != "":
		return _fail(why, wp).merged({"tree": tree})
	if tree["reserved"] != null:
		return _fail("다른 나무꾼이 작업 중인 나무입니다", wp).merged({"tree": tree})
	if game.contracts.active_count() >= Cfg.ACTIVE_LIMIT:
		return _fail("활동 상한 %d명에 도달했습니다" % Cfg.ACTIVE_LIMIT, wp).merged({"tree": tree})
	var per := Cfg.CHOP_YIELD
	var t_chop := Cfg.CHOP_TIME
	if game.relics.has("old_tree_heart"):
		t_chop = Cfg.RELIC_CHOP_TIME
	return {"ok": true, "action": "chop", "pos": wp, "tree": tree, "title": "벌목 — " + who,
		"lines": ["%s초마다 목재 %d · 이 나무에 %d 남음 (다 베면 사라짐)" % [String.num(t_chop, 1).trim_suffix(".0"), per, tree["remaining"]],
			"계약 1장 소비 · 목재는 최대 %d개까지 들고 있다가 마녀가 다가오면 건넴" % Cfg.LUMBERJACK_CARRY,
			"가득 차면 산장 주변에서 쉼 · 밤에는 산장 안으로 대피, 다음 낮에 재개"]}


## 사냥꾼·전투용병·하수인: 지면 또는 적에 놓는다.
func _eval_summon(entry: Dictionary, sp: Vector2) -> Dictionary:
	var s = game.session
	var id: String = entry["id"]
	var merc: bool = id != "forest_monster"
	var who: String = ("%s(%s)" % [entry["person"], Cfg.JOB_NAMES[id]]) if merc else "큰 숲의 괴물 하수인"
	var spend := "계약 1장 소비" if merc else "카드 1장 소비"
	var enemy = enemy_at(sp)
	var cap_full: bool = merc and game.contracts.active_count() >= Cfg.ACTIVE_LIMIT  # 숲의 괴물 하수인은 상한에 들지 않는다
	if s.state == SessionScript.State.CLEARING:
		return _fail("밤 전투를 정리하는 중입니다")
	var after := ""
	if merc:
		after = "적이 없으면 산장 주변을 정찰 · 낮에는 사냥" if id == "hunter" else "적이 없으면 산장 주변을 정찰"
	if enemy != null:
		var lodge_dir: Vector3 = Layout.DOOR_FRONT - enemy.global_position
		lodge_dir.y = 0.0
		var spot = valid_ground(enemy.global_position + lodge_dir.normalized() * (4.5 if id == "hunter" else 1.2))
		if spot is String:
			spot = valid_ground(enemy.global_position)
		if spot is String:
			return _fail(spot)
		if cap_full:
			return _fail("활동 상한 %d명에 도달했습니다" % Cfg.ACTIVE_LIMIT, spot)
		return {"ok": true, "action": "guard", "pos": spot, "enemy": enemy, "title": "전투 — " + who,
			"lines": ["이 적을 먼저 공격한 뒤 주변 적을 상대", spend, after if merc else "이번 밤이 끝나면 시들어 목재 1개가 됨"]}
	var g = _ground_at(sp)
	if g == null:
		return _fail("대상을 찾지 못했습니다")
	if _lodge_hit(sp):
		return _fail("산장에는 사용할 수 없습니다")
	var spot2 = valid_ground(g)
	if spot2 is String:
		return _fail(spot2, g)
	if cap_full:
		return _fail("활동 상한 %d명에 도달했습니다" % Cfg.ACTIVE_LIMIT, spot2)
	if merc:
		var first := "원거리(활 %dm)로 적을 쏘고, 낮에는 토끼·사슴을 사냥" % int(Cfg.HUNTER_RANGE) if id == "hunter" else "근접 전투 · 산장이 공격받으면 공격자를 먼저 추적"
		return {"ok": true, "action": "guard", "pos": spot2, "title": "배치 — " + who,
			"lines": [first, spend, after + " · 쓰러질 때까지 산장에 남음"]}
	var until := "오늘 밤 전투가 끝날 때까지 이 자리를 방어" if s.state == SessionScript.State.PREP else "이번 밤 적이 정리될 때까지 이 자리를 방어"
	return {"ok": true, "action": "guard", "pos": spot2, "title": ("방어 배치 — " if s.state == SessionScript.State.PREP else "전투 — ") + who,
		"lines": [until, spend, "끝나면 시들어 목재 1개가 됨 (쓰러져도 동일)"]}


## 채집가: 낮에 지면에 놓으면 바로 탐색을 떠난다(준비 시간이 충분할 때만).
func _eval_gatherer(entry: Dictionary, sp: Vector2) -> Dictionary:
	var s = game.session
	var who: String = entry["person"]
	var g = _ground_at(sp)
	if g == null:
		return _fail("대상을 찾지 못했습니다")
	if _lodge_hit(sp):
		return _fail("산장에는 사용할 수 없습니다")
	var spot = valid_ground(g)
	if spot is String:
		return _fail(spot, g)
	if s.state != SessionScript.State.PREP:
		return _fail("채집은 낮에만 떠날 수 있습니다", spot)
	if s.prep_remaining() < Cfg.GATHER_MIN_PREP:
		return _fail("저녁이 가까워 오늘은 떠날 수 없습니다 (남은 시간 %d초 이상 필요)" % int(Cfg.GATHER_MIN_PREP), spot)
	if game.contracts.active_count() >= Cfg.ACTIVE_LIMIT:
		return _fail("활동 상한 %d명에 도달했습니다" % Cfg.ACTIVE_LIMIT, spot)
	return {"ok": true, "action": "gather", "pos": spot, "title": "채집 — " + who,
		"lines": ["숲의 랜드마크를 돌며 목재·고기·가죽을 줍고, 드물게 보물상자를 찾음", "저녁 %d초 전에 돌아와 마당에서 기다림 · 계약 1장 소비" % int(Cfg.GATHER_RETURN_MARGIN), "밤에는 산장 안으로 대피"]}


## 보물상자: 지면에 놓으면 열린다(낮·밤 모두).
func _eval_chest(sp: Vector2) -> Dictionary:
	var g = _ground_at(sp)
	if g == null:
		return _fail("땅에 놓으면 상자가 열립니다")
	var spot = valid_ground(g)
	if spot is String:
		return _fail(spot, g)
	if game.chest_ui != null and game.chest_ui.active:
		return _fail("이미 상자를 여는 중입니다")
	var n: int = game.relics.choices().size()
	if n == 0:
		return {"ok": true, "action": "chest", "pos": spot, "title": "보물상자",
			"lines": ["유물을 모두 모았습니다 — 상자에서 목재 %d" % Cfg.CHEST_FALLBACK_TIMBER, "카드 1장 소비"]}
	return {"ok": true, "action": "chest", "pos": spot, "title": "보물상자 열기",
		"lines": ["물음표 카드 %d장 중 하나를 골라 유물을 얻습니다" % n, "유물은 영구 패시브 · 카드 1장 소비"]}


## 생고기: 산장에 놓으면 판매, 마녀에게 놓으면 한 덩이 먹어 회복, 켜진 모닥불에 놓으면 스튜를 끓인다.
func _eval_meat(entry: Dictionary, sp: Vector2) -> Dictionary:
	if player_hit(sp):
		var p = game.player
		if p.hp >= p.max_hp:
			return _fail("마녀의 체력이 최대입니다", p.global_position)
		var gain := minf(Cfg.MEAT_HEAL, p.max_hp - p.hp)
		return {"ok": true, "action": "eat", "pos": p.global_position, "title": "생고기 — 마녀 회복",
			"lines": ["생고기 1개 사용 · 체력 +%d" % int(gain), "%d → %d" % [int(ceil(p.hp)), int(ceil(p.hp + gain))]]}
	if campfire_hit(sp):
		var yard = game.world.yard
		var at: Vector3 = yard.campfire.global_position
		if not yard.is_lit():
			return _fail("모닥불이 꺼져 있습니다 — 목재를 넣어 불을 피우세요", at)
		return {"ok": true, "action": "cook_stew", "pos": at, "title": "모닥불 — 고기 스튜 끓이기",
			"lines": ["생고기 1개 → 고기 스튜 카드 1장", "스튜를 다친 용병에게 놓으면 최대 체력의 %d%% 회복" % int(Cfg.STEW_HEAL_RATIO * 100.0)]}
	return _eval_wool(entry, sp)


## 고기 스튜: 다친 용병 한 명에게 놓으면 크게 회복(낮·밤 모두).
## 장비: 마녀·용병(월드 또는 초상 프레임)에 놓아 해당 칸에 끼운다. 같은 칸의 장비는 손패로 돌아온다.
func _eval_equip(entry: Dictionary, sp: Vector2) -> Dictionary:
	var id: String = entry["id"]
	var eq = game.equipment
	var who: String = Cfg.EQUIPMENT[id].get("who", "any")
	var h = gear_target(sp)
	if h == null:
		return _fail({"witch": "마녀에게 놓아 장착합니다", "merc": "용병에게 놓아 장착합니다"}.get(who, "마녀나 용병에게 놓아 장착합니다") + " (초상에 놓아도 됩니다)")
	var why: String = eq.block_reason(h, id)
	if why != "":
		return _fail(why, h.global_position)
	var slot := EquipmentScript.slot_of(id)
	var nm: String = game.cards.def(id).get("name", id)
	var lines: Array = ["%s 칸 · %s" % [Cfg.EQUIP_SLOT_NAMES[slot], EquipmentScript.effect_text(id)]]
	var cur: Dictionary = eq.equipped(h, slot)
	if not cur.is_empty():
		lines.append("지금 끼운 '%s'은(는) 손패로 돌아옵니다" % game.cards.def(cur["id"]).get("name", ""))
	else:
		lines.append("카드는 착용하는 동안 손패에서 빠집니다")
	return {"ok": true, "action": "equip", "holder": h, "pos": h.global_position, "title": "%s 장착 — %s" % [nm, eq.holder_name(h)], "lines": lines}


func _eval_stew(sp: Vector2) -> Dictionary:
	var a = merc_target(sp)
	if a == null:
		return _fail("다친 용병에게 놓으면 체력을 회복합니다")
	var who: String = a.display_name()
	if a.hp >= a.max_hp:
		return _fail("%s의 체력이 가득합니다" % who, a.global_position)
	var gain := minf(a.max_hp * Cfg.STEW_HEAL_RATIO, a.max_hp - a.hp)
	return {"ok": true, "action": "stew", "ally": a, "pos": a.global_position, "title": "고기 스튜 — " + who,
		"lines": ["체력 +%d" % int(gain), "%d → %d · 카드 1장 소비" % [int(ceil(a.hp)), int(ceil(a.hp + gain))]]}


func _eval_wool(entry: Dictionary, sp: Vector2) -> Dictionary:
	var nm: String = game.cards.def(entry["id"]).get("name", entry["id"])
	if not _lodge_hit(sp):
		return _fail("산장에 놓으면 판매합니다" if entry["id"] != "raw_meat" else "산장에 놓으면 판매, 마녀에게 놓으면 먹습니다")
	var lodge_pos: Vector3 = game.world.lodge.global_position
	if game.session.state != SessionScript.State.PREP:
		return _fail("판매는 준비 시간에만 가능합니다", lodge_pos)
	var price: int = Cfg.SALE_PRICES.get(entry["id"], Cfg.WOOL_PRICE)
	return {"ok": true, "action": "sell", "pos": lodge_pos, "title": "산장 교역 — %s 판매" % nm,
		"lines": ["보유 %d개 · 1개 %dG" % [entry["count"], price], "놓은 뒤 판매 수량을 고릅니다"]}


## 화면 지점이 가리키는 감시탑(탑 몸체 충돌 또는 공터 지면). 없으면 null.
func tower_at(sp: Vector2):
	var cam: Camera3D = game.world.camera
	var from := cam.project_ray_origin(sp)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(sp) * 400.0, Cfg.L_OBSTACLE)
	var hit: Dictionary = game.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit["collider"] in game.world.towers:
		return hit["collider"]
	var g = _ground_at(sp)
	if g != null:
		for t in game.world.towers:
			if t.contains_ground(g):
				return t
	# 높은 탑은 화면에서 공터 위쪽에 그려진다: 탑 몸통 높이의 화면 위치로도 고른다
	for t in game.world.towers:
		if t.level > 0 and not cam.is_position_behind(t.global_position):
			var top := cam.unproject_position(t.global_position + Vector3(0, t.hp_offset * 0.5, 0))
			if top.distance_to(sp) < 60.0:
				return t
	return null


## 목재를 감시탑 공터에: 수리(체력이 깎였으면) 또는 다음 단계 적립. 준비 시간에만.
func _eval_timber_tower(tower) -> Dictionary:
	var at: Vector3 = tower.global_position
	if game.session.state != SessionScript.State.PREP:
		return _fail("감시탑 적립·수리는 준비 시간에만 가능합니다", at)
	match tower.timber_action():
		"repair":
			var gain := minf(Cfg.TOWER_REPAIR_AMOUNT, tower.max_hp - tower.hp)
			return {"ok": true, "action": "tower_repair", "tower": tower, "pos": at, "title": "재료 수리 — " + tower.display_name(),
				"lines": ["목재 1장 사용 · 탑 체력 +%d" % int(gain), "%d → %d%s" % [int(ceil(tower.hp)), int(ceil(tower.hp + gain)), " · 다시 세움" if tower.collapsed else ""]]}
		"deposit":
			var step: Dictionary = tower.next_step()
			var what := "감시탑 건설" if tower.level == 0 else "감시탑 2단계"
			return {"ok": true, "action": "tower_deposit", "tower": tower, "pos": at, "title": "목재 적립 — " + what,
				"lines": ["목재 %d → %d / %d" % [tower.stock, tower.stock + 1, tower.stock_needed()], "다 모이면 산장 관리창에서 %dG로 %s" % [int(step["gold"]), "건설" if tower.level == 0 else "업그레이드"]]}
	return _fail(tower.timber_block_reason(), at)


## 손패 카드를 켜진 모닥불에 태우기(손패 흐름 v1): 재화 1개 소멸·그 밖은 버림패, 지금 시간대 카드 1장 드로우. 하루 BURN_DRAW_PER_DAY회.
## 침식 카드는 태우면 정화되지만 드로우가 없고 연기로 체력 BURN_CORRUPTION_HP를 잃는다.
func _eval_burn(entry: Dictionary) -> Dictionary:
	var yard = game.world.yard
	var at: Vector3 = yard.campfire.global_position
	if not yard.is_lit():
		return _fail("모닥불이 꺼져 있습니다 — 목재를 넣어 불을 피우세요", at)
	var why: String = game.cards.burn_block_reason(entry["uid"])
	if why != "":
		return _fail(why, at)
	var name: String = game.cards.def(entry["id"]).get("name", entry["id"])
	var left: int = Cfg.BURN_DRAW_PER_DAY - game.cards.burns_today
	if game.cards.is_corruption(entry["id"]):
		if game.player.hp <= Cfg.BURN_CORRUPTION_HP:
			return _fail("체력이 %d 이하라 침식 카드를 태울 수 없습니다" % int(Cfg.BURN_CORRUPTION_HP), at)
		return {"ok": true, "action": "burn", "pos": at, "title": "모닥불 — '%s' 태우기" % name,
			"lines": ["침식 카드가 연기와 함께 사라짐 · 드로우 없음", "연기로 마녀 체력 -%d · 오늘 남은 태우기 %d회" % [int(Cfg.BURN_CORRUPTION_HP), left]]}
	var n: int = game.cards.eligible_pocket().size()
	var what := "재화 1개 소멸" if game.cards.is_resource(entry["id"]) else "카드는 버림패로"
	return {"ok": true, "action": "burn", "pos": at, "title": "모닥불 — '%s' 태우기" % name,
		"lines": [what + (" · 주머니에서 지금 쓸 수 있는 카드 1장 드로우 (후보 %d장)" % n if n > 0 else " · 주머니에 지금 뽑을 카드가 없음"), "오늘 남은 태우기 %d회" % left]}


## 목재를 모닥불에: 연료 +60초(최대 180초). 꺼진 불은 다시 켜진다. 낮·밤 모두.
func _eval_timber_campfire() -> Dictionary:
	var yard = game.world.yard
	var at: Vector3 = yard.campfire.global_position
	var why: String = yard.timber_block_reason()
	if why != "":
		return _fail(why, at)
	var after := minf(yard.fuel + Cfg.CAMPFIRE_FUEL_PER_TIMBER, yard.max_fuel())
	return {"ok": true, "action": "campfire_fuel", "pos": at, "title": "모닥불 — 장작 넣기" if yard.is_lit() else "모닥불 — 불 피우기",
		"lines": ["목재 1개 사용 · 남은 시간 %d초 → %d초" % [int(ceil(yard.fuel)), int(ceil(after))],
			"켜져 있으면 생고기로 스튜를 끓이고, 낮에는 곁의 용병이 천천히 회복"]}


func _eval_timber(entry: Dictionary, sp: Vector2) -> Dictionary:
	if not _lodge_hit(sp):
		if campfire_hit(sp):
			return _eval_timber_campfire()
		var tower = tower_at(sp)
		if tower != null:
			return _eval_timber_tower(tower)
		return _fail("산장에 놓으면 수리, 모닥불에 놓으면 장작, 감시탑 공터에 놓으면 적립합니다")
	var lodge = game.world.lodge
	if game.session.state != SessionScript.State.PREP:
		return _fail("수리는 준비 시간에만 가능합니다", lodge.global_position)
	if lodge.hp >= lodge.max_hp:
		return _fail("산장 체력이 최대입니다", lodge.global_position)
	if game.cards.hand_count_of("timber") < Cfg.TIMBER_REPAIR_COST:
		return _fail("목재가 %d개 필요합니다 (손패 %d개)" % [Cfg.TIMBER_REPAIR_COST, game.cards.hand_count_of("timber")], lodge.global_position)
	var gain := minf(Cfg.TIMBER_REPAIR_AMOUNT, lodge.max_hp - lodge.hp)
	return {"ok": true, "action": "repair", "pos": lodge.global_position, "title": "재료 수리 — 산장",
		"lines": ["목재 %d개 사용 · 산장 체력 +%d" % [Cfg.TIMBER_REPAIR_COST, int(gain)], "%d → %d" % [int(ceil(lodge.hp)), int(ceil(lodge.hp + gain))]]}


func _enemies_within(center: Vector3, radius: float) -> int:
	var n := 0
	for e in game.get_tree().get_nodes_in_group("enemies"):
		if not e.dead and Vector2(e.global_position.x - center.x, e.global_position.z - center.z).length() <= radius:
			n += 1
	return n


func _eval_frost(sp: Vector2) -> Dictionary:
	if game.session.state != SessionScript.State.COMBAT:
		return _fail("서리 룬은 밤 전투 중에만 새길 수 있습니다")
	var enemy = enemy_at(sp)
	var center
	if enemy != null:
		center = enemy.global_position
		center.y = 0.0
	else:
		var g = _ground_at(sp)
		if g == null:
			return _fail("대상을 찾지 못했습니다")
		if _lodge_hit(sp):
			return _fail("산장에는 새길 수 없습니다")
		center = valid_ground(g)
		if center is String:
			return _fail(center, g)
	var n := _enemies_within(center, Cfg.FROST_RADIUS)
	return {"ok": true, "action": "frost", "pos": center, "radius": Cfg.FROST_RADIUS, "title": "서리 룬",
		"lines": ["반경 %.1fm · 피해 %d · %d초 동안 이동 속도 %d%%" % [Cfg.FROST_RADIUS, int(Cfg.FROST_DAMAGE), int(Cfg.FROST_SLOW_TIME), int(Cfg.FROST_SLOW * 100.0)],
			"범위 안의 적 %d마리 · 카드 1장 소비" % n]}


func _eval_lantern(sp: Vector2) -> Dictionary:
	var st: int = game.session.state
	if st != SessionScript.State.PREP and st != SessionScript.State.COMBAT:
		return _fail("밤 전투를 정리하는 중입니다")
	var g = _ground_at(sp)
	if g == null:
		return _fail("대상을 찾지 못했습니다")
	if _lodge_hit(sp):
		return _fail("산장에는 세울 수 없습니다")
	var spot = valid_ground(g)
	if spot is String:
		return _fail(spot, g)
	if game.get_tree().get_nodes_in_group("ward_lanterns").size() >= Cfg.LANTERN_LIMIT:
		return _fail("등불은 동시에 %d개까지 켤 수 있습니다" % Cfg.LANTERN_LIMIT, spot)
	var until := "오늘 밤 전투가 끝날 때까지 켜짐" if st == SessionScript.State.PREP else "이번 밤 전투가 끝날 때까지 켜짐"
	return {"ok": true, "action": "lantern", "pos": spot, "radius": Cfg.LANTERN_RADIUS, "title": "수호 등불",
		"lines": ["반경 %.1fm 안의 적 이동 속도 %d%% · 안개를 걷어 냄" % [Cfg.LANTERN_RADIUS, int(Cfg.LANTERN_SLOW * 100.0)], until + " · 카드 1장 소비"]}


func _eval_invite(sp: Vector2) -> Dictionary:
	if not _lodge_hit(sp):
		return _fail("산장에 놓으면 손님을 부릅니다")
	var lodge_pos: Vector3 = game.world.lodge.global_position
	var why: String = game.economy.invite_block_reason()
	if why != "":
		return _fail(why, lodge_pos)
	var n: int = game.economy.capacity
	return {"ok": true, "action": "invite", "pos": lodge_pos, "title": "숙박 초대장 — 손님 초대",
		"lines": ["손님 %d명이 바로 도착 · %d초 뒤 숙박비 +%dG" % [n, int(Cfg.GUEST_STAY), n * Cfg.GUEST_FEE], "정산 후 한 명이 고용 제안 · 카드 1장 소비"]}


func _eval_lamb(sp: Vector2) -> Dictionary:
	var pasture = game.world.pasture
	var center := Vector3(pasture.rect.get_center().x, 0, pasture.rect.get_center().y)
	var g = _ground_at(sp)
	if g == null or not pasture.inside(g, 0.4):
		return _fail("목장에 놓으면 새끼양을 들입니다")
	if game.session.state != SessionScript.State.PREP:
		return _fail("가축 입식은 준비 시간에만 가능합니다", center)
	if not pasture.has_empty_slot():
		return _fail("목장에 빈자리가 없습니다 (%d/%d)" % [pasture.alive_count(), pasture.capacity()], center)
	var d: int = game.session.day()
	return {"ok": true, "action": "lamb", "pos": center, "title": "새끼양 입식",
		"lines": ["목장 %d/%d → %d/%d · 새끼양은 털을 만들지 않음" % [pasture.alive_count(), pasture.capacity(), pasture.alive_count() + 1, pasture.capacity()],
			"%d일차 낮에 어른 양으로 자라 바로 털 수확 · 카드 1장 소비" % (d + Cfg.LAMB_GROW_DAYS)]}


# ───────────────────────── 확정 ─────────────────────────

func _eval_thorn(sp: Vector2) -> Dictionary:
	if game.session.state != SessionScript.State.PREP:
		return _fail("가시 씨앗은 낮 준비 시간에만 심을 수 있습니다")
	var ground = _ground_at(sp)
	if ground == null or _lodge_hit(sp):
		return _fail("산장 밖의 이동 가능한 땅에 심어 주세요")
	var spot = valid_ground(ground)
	if spot is String:
		return _fail(spot, ground)
	if game.world.fog_of_war != null and not game.world.fog_of_war.is_visible_at(spot):
		return _fail("보이는 땅에만 심을 수 있습니다", spot)
	var plants: Array = game.get_tree().get_nodes_in_group("thorn_plants")
	if plants.size() >= Cfg.THORN_LIMIT:
		return _fail("가시 방책은 동시에 %d개까지 기를 수 있습니다" % Cfg.THORN_LIMIT, spot)
	for plant in plants:
		if plant.global_position.distance_to(spot) < Cfg.THORN_SPACING:
			return _fail("다른 가시 씨앗과 조금 떨어뜨려 주세요", spot)
	return {"ok": true, "action": "plant_thorn", "pos": spot, "radius": Cfg.THORN_RADIUS, "title": "잠자는 가시 씨앗 심기",
		"lines": ["낮 %d초 동안 성장 · 밤에는 주변 적 공격·속박" % int(Cfg.THORN_GROW_TIME), "덜 자라면 공격력 절반 · 살아남으면 다음 날에도 유지", "검은 털을 바치면 완전히 성장하고 강화·회복 · 카드 1장 소비"]}


func _eval_black_sheep(sp: Vector2) -> Dictionary:
	var pasture = game.world.pasture
	var ground = _ground_at(sp)
	var center := Vector3(pasture.rect.get_center().x, 0, pasture.rect.get_center().y)
	if ground == null or not pasture.inside(ground, 0.4):
		return _fail("목장에 놓으면 검은 양을 들입니다")
	if game.session.state != SessionScript.State.PREP:
		return _fail("가축 입식은 준비 시간에만 가능합니다", center)
	if not pasture.has_empty_slot():
		return _fail("목장에 빈자리가 없습니다 (%d/%d)" % [pasture.alive_count(), pasture.capacity()], center)
	return {"ok": true, "action": "black_sheep", "pos": center, "title": "목장의 검은 양 입식",
		"lines": ["목장 자리 1칸 사용 · 다음 날부터 검은 털 생산", "양을 클릭해 수확 · 검은 털로 가시 방책 강화·회복", "카드 1장 소비"]}


func _eval_black_wool(sp: Vector2) -> Dictionary:
	if game.session.state not in [SessionScript.State.PREP, SessionScript.State.COMBAT]:
		return _fail("지금은 의식을 치를 수 없습니다")
	var ground = _ground_at(sp)
	var best = null
	var distance := 65.0
	for plant in game.get_tree().get_nodes_in_group("thorn_plants"):
		var screen_distance: float = game.world.camera.unproject_position(plant.global_position + Vector3(0, 0.4, 0)).distance_to(sp)
		var ground_hit: bool = ground != null and ground.distance_to(plant.global_position) <= 0.9
		if screen_distance < distance or ground_hit:
			best = plant
			distance = screen_distance
	if best == null:
		return _fail("심어 둔 가시 씨앗이나 가시 방책에 바쳐 주세요")
	if not best.can_receive_offering():
		return _fail("이미 강화되었고 체력도 가득 찼습니다", best.global_position)
	return {"ok": true, "action": "offer_black_wool", "plant": best, "pos": best.global_position, "radius": Cfg.THORN_RADIUS, "title": "검은 털 봉헌",
		"lines": ["즉시 완전 성장 · 최대 체력 %d · 체력 전체 회복" % int(Cfg.THORN_RITUAL_HP), "가시 공격력 %d → %d · 검은 털 1개 소비" % [int(Cfg.THORN_DAMAGE), int(Cfg.THORN_RITUAL_DAMAGE)]]}

# ───────────────────────── 볼륨 확장 카드(E2·E3) ─────────────────────────

## 지면(또는 적)에 쓰는 범위 카드. combat_only면 밤 전투 중에만.
func _eval_ground_spell(sp: Vector2, combat_only: bool, radius: float, action: String, title: String, lines: Array) -> Dictionary:
	if combat_only and game.session.state != SessionScript.State.COMBAT:
		return _fail("%s은(는) 밤 전투 중에만 쓸 수 있습니다" % title.split(" (")[0])
	var enemy = enemy_at(sp)
	var center
	if enemy != null:
		center = enemy.global_position
		center.y = 0.0
	else:
		var g = _ground_at(sp)
		if g == null:
			return _fail("대상을 찾지 못했습니다")
		if _lodge_hit(sp):
			return _fail("산장에는 쓸 수 없습니다")
		center = valid_ground(g)
		if center is String:
			return _fail(center, g)
	var n := _enemies_within(center, radius)
	var out: Array = lines.duplicate()
	out[out.size() - 1] = "범위 안의 적 %d마리 · %s" % [n, out[out.size() - 1]]
	return {"ok": true, "action": action, "pos": center, "radius": radius, "title": title, "lines": out}


## 이끼 붕대: 마녀에게. 체력 회복 + 침식 카드 1장 정화.
func _eval_moss(sp: Vector2) -> Dictionary:
	var p = game.player
	if not player_hit(sp):
		return _fail("마녀에게 놓아야 합니다")
	var st: int = game.session.state
	if st != SessionScript.State.PREP and st != SessionScript.State.COMBAT:
		return _fail("지금은 쓸 수 없습니다", p.global_position)
	var bad: int = game.chapter.corruption_count()
	if p.hp >= p.max_hp and bad == 0:
		return _fail("체력이 가득하고 정화할 침식 카드도 없습니다", p.global_position)
	return {"ok": true, "action": "moss", "pos": p.global_position, "title": "이끼 붕대",
		"lines": ["마녀 체력 +%d" % int(minf(Cfg.MOSS_HEAL, p.max_hp - p.hp)), "침식 카드 1장 정화(손패 우선) · 지금 %d장" % bad]}


func _eval_firefly(sp: Vector2) -> Dictionary:
	var st: int = game.session.state
	if st != SessionScript.State.PREP and st != SessionScript.State.COMBAT:
		return _fail("밤 전투를 정리하는 중입니다")
	var g = _ground_at(sp)
	if g == null:
		return _fail("대상을 찾지 못했습니다")
	if _lodge_hit(sp):
		return _fail("산장에는 풀 수 없습니다")
	var spot = valid_ground(g)
	if spot is String:
		return _fail(spot, g)
	return {"ok": true, "action": "firefly", "pos": spot, "radius": Cfg.FIREFLY_SIGHT, "title": "반딧불이 떼",
		"lines": ["반경 %dm의 안개를 걷어 냄(안개의 밤에 특히 유용)" % int(Cfg.FIREFLY_SIGHT), "오늘 밤 전투가 끝날 때까지 · 카드 1장 소비"]}


func _eval_firewood(sp: Vector2) -> Dictionary:
	if not _lodge_hit(sp):
		return _fail("산장에 놓으면 장작으로 벽을 보강합니다")
	var lodge = game.world.lodge
	var st: int = game.session.state
	if st != SessionScript.State.PREP and st != SessionScript.State.COMBAT:
		return _fail("지금은 쓸 수 없습니다", lodge.global_position)
	if lodge.hp >= lodge.max_hp:
		return _fail("산장 체력이 최대입니다", lodge.global_position)
	var gain := minf(Cfg.FIREWOOD_REPAIR, lodge.max_hp - lodge.hp)
	return {"ok": true, "action": "firewood", "pos": lodge.global_position, "title": "겨울 장작 — 산장 보강",
		"lines": ["산장 체력 +%d (밤에도 사용 가능)" % int(gain), "카드 1장 소비"]}


## 오늘 밤 축복 카드(권능·전리품). target: "ground" | "player" | "lodge".
func _eval_blessing(sp: Vector2, bless_id: String, title: String, effect: String, target: String) -> Dictionary:
	var st: int = game.session.state
	if st != SessionScript.State.PREP and st != SessionScript.State.COMBAT:
		return _fail("지금은 쓸 수 없습니다")
	var pos: Vector3
	match target:
		"player":
			if not player_hit(sp):
				return _fail("마녀에게 놓아야 합니다")
			pos = game.player.global_position
		"lodge":
			if not _lodge_hit(sp):
				return _fail("산장에 놓아야 합니다")
			pos = game.world.lodge.global_position
		_:
			var g = _ground_at(sp)
			if g == null:
				return _fail("땅에 놓으세요")
			pos = g
	if game.chapter.blessed(bless_id):
		return _fail("오늘 밤 이미 같은 축복이 있습니다", pos)
	return {"ok": true, "action": "bless", "bless": bless_id, "pos": pos, "title": title,
		"lines": [effect, "밤 전투가 끝나면 사라짐 · 카드 1장 소비"]}


## 용비늘(2026-10-24): 밤 전투 중 산장에. 지붕에 용이 내려와 불덩이를 쏜다. 웨이브당 한 번.
func _eval_dragon_scale(sp: Vector2) -> Dictionary:
	var why: String = game.dragon.block_reason()
	if why != "":
		return _fail(why)
	if not _lodge_hit(sp):
		return _fail("산장에 놓아야 합니다")
	return {"ok": true, "action": "dragon", "pos": game.world.lodge.global_position, "title": "용비늘",
		"lines": ["지붕에 용이 내려와 %d초마다 가장 밀집한 적에게 불덩이(피해 %d)" % [int(Cfg.DRAGON_FIRE_INTERVAL), int(Cfg.FIREBALL_DAMAGE)], "웨이브가 끝나면 떠남 · 카드 1장 소비"]}


## 늑대의 피(docs/wolf-blood-event-design.md §3): 낮·밤 마녀에게. 마녀가 괴로워한 뒤 달 카드 세 장이 주머니로.
func _eval_wolf_blood(sp: Vector2) -> Dictionary:
	var st: int = game.session.state
	if st != SessionScript.State.PREP and st != SessionScript.State.COMBAT:
		return _fail("지금은 쓸 수 없습니다")
	if not player_hit(sp):
		return _fail("마녀에게 놓아야 합니다")
	if game.player.suffering > 0.0:
		return _fail("지금은 쓸 수 없습니다")
	return {"ok": true, "action": "wolf_blood", "pos": game.player.global_position, "title": "늑대의 피",
		"lines": ["마녀가 잠시 괴로워한 뒤 달 카드 3장이 주머니로", "카드 1장 소비"]}


## 달 카드(초승달·상현달·보름달): 밤 전투 중 마녀에게. 한 밤에 한 장, 1회용.
func _eval_moon(entry: Dictionary, sp: Vector2) -> Dictionary:
	var why: String = game.moon_powers.block_reason(entry["id"])
	if why != "":
		return _fail(why)
	if not player_hit(sp):
		return _fail("마녀에게 놓아야 합니다")
	var effect: String = {
		"crescent_moon": "오늘 밤 마법탄 간격 %d%%" % int(round(Cfg.MOON_CRESCENT_ATTACK * 100.0)),
		"half_moon": "오늘 밤 마법탄 간격 %d%% · 이동 속도 +%d%%" % [int(round(Cfg.MOON_HALF_ATTACK * 100.0)), int(round((Cfg.MOON_HALF_MOVE - 1.0) * 100.0))],
		"full_moon": "오늘 밤 늑대로 변신 — 근접 물기 · Q 할퀴기 · E 덮치기 · 손패 잠김",
	}[entry["id"]]
	return {"ok": true, "action": "moon", "pos": game.player.global_position, "title": game.cards.def(entry["id"]).get("name", ""),
		"lines": [effect, "밤 전투가 끝나면 사라짐 · 카드 1장 소비"]}


## 즉시 범위 효과(덩굴 덫·가시 속박): 피해 + 강한 감속.
func _root_burst(center: Vector3, radius: float, damage: float, slow: float, time: float, color: Color, source: String) -> int:
	var n := 0
	for e in game.get_tree().get_nodes_in_group("enemies"):
		if e.dead or Vector2(e.global_position.x - center.x, e.global_position.z - center.z).length() > radius:
			continue
		e.take_damage(damage)
		if not e.dead and e.has_method("apply_slow"):
			e.apply_slow(source, slow, time)
		n += 1
	Fx.celebrate(center, color, radius / 3.0)
	return n


## 놓는 순간 호출. 반환: 판정 결과(ok=false면 카드는 손패로 돌아간다).
func commit(uid: int, sp: Vector2) -> Dictionary:
	var plan := evaluate(uid, sp)
	if not plan["ok"]:
		return plan
	var entry: Dictionary = game.cards.get_entry(uid)
	for m in CARD_MODULES:
		if plan["action"] == m[1]:
			var done: Dictionary = game.get(m[0]).commit(uid, plan, self)
			# 흑맥주 통·전투 식량도 술이다: 에린 방문 조건을 센다
			if m[1] == "race" and done.get("ok", false) and game.get("tavern") != null:
				game.tavern.on_card_used(str(plan["race_card"]))
			return done
	match plan["action"]:
		"burn":
			var r: Dictionary = game.cards.burn(uid)
			if not r.get("ok", false):
				return _fail("태울 수 없습니다")
			var burned: String = game.cards.def(r["id"]).get("name", r["id"])
			game.sounds.play_or("card_burn", "card_consume")
			Fx.celebrate(plan["pos"] + Vector3(0, 0.6, 0), Color(1.0, 0.6, 0.3), 0.7)
			if r["corruption"]:
				game.player.pay_hp(Cfg.BURN_CORRUPTION_HP)
				game.toast("'%s'을(를) 태웠습니다 — 침식이 연기로 흩어지고 체력 -%d" % [burned, int(Cfg.BURN_CORRUPTION_HP)], Color(0.85, 0.7, 1.0))
			elif r["drew"].is_empty():
				game.toast("'%s'을(를) 태웠습니다 — 주머니에 지금 뽑을 카드가 없습니다" % burned, Color(1.0, 0.8, 0.6))
			else:
				game.toast("'%s'을(를) 태우고 '%s' 드로우" % [burned, game.cards.def(r["drew"]["id"]).get("name", "")], Color(1.0, 0.9, 0.7))
				game.sounds.play("card_draw")
		"plant_thorn":
			if not game.cards.activate(uid):
				return _fail("카드가 없습니다")
			var plant := ThornSeedScript.new()
			plant.game = game
			plant.card_uid = uid
			plant.position = plan["pos"]
			game.actors.add_child(plant)
			game.toast("가시 씨앗을 심었습니다 — 낮에 자라 밤에는 산장을 지킵니다", Color(0.75, 1, 0.55))
		"black_sheep":
			if not game.world.pasture.add_black_sheep():
				return _fail("목장에 빈자리가 없습니다")
			game.cards.activate(uid)
			game.world.pasture.slots.back().card_uid = uid
			game.toast("검은 양을 들였습니다 — 다음 날부터 검은 털을 수확합니다", Color(0.82, 0.68, 1))
		"offer_black_wool":
			if not game.cards.consume(uid):
				return _fail("검은 털이 없습니다")
			plan["plant"].offer_black_wool()
			game.toast("검은 털을 바쳤습니다 — 가시 방책 강화·체력 회복", Color(0.82, 0.68, 1))
		"sell":
			return plan  # 판매 수량 선택 창에서 확정한다(여기서는 소비하지 않음). 재화 묶음 복원(2026-10-18)
		"repair":
			# 끌어다 놓은 카드를 먼저 쓰고, 비용이 여러 장이면 손패의 같은 목재를 더 쓴다
			game.cards.begin_use()  # 비용이 여러 장이어도 한 번의 사용
			var paid: bool = game.cards.consume(uid, 1) and game.cards.consume_id("timber", Cfg.TIMBER_REPAIR_COST - 1)
			game.cards.end_use()
			if not paid:
				return _fail("목재가 부족합니다")
			var r: float = game.world.lodge.repair(Cfg.TIMBER_REPAIR_AMOUNT)
			game.toast("목재 %d개로 산장 수리 +%d" % [Cfg.TIMBER_REPAIR_COST, int(r)], Color(0.95, 0.85, 0.6))
		"tower_repair":
			if not game.cards.consume(uid, 1):
				return _fail("목재가 부족합니다")
			var rt: float = plan["tower"].repair(Cfg.TOWER_REPAIR_AMOUNT)
			game.toast("목재 1장으로 %s 수리 +%d" % [plan["tower"].display_name(), int(rt)], Color(0.95, 0.85, 0.6))
		"tower_deposit":
			if not game.cards.consume(uid, 1):
				return _fail("목재가 부족합니다")
			var tw = plan["tower"]
			tw.deposit(1)
			game.sounds.play_or("timber_stack", "card_play")
			if tw.stock_full():
				game.sounds.play("stack_gain")
			if tw.stock_full():
				game.toast("%s 목재 준비 완료 — 산장 관리창에서 %dG로 %s" % [tw.display_name(), int(tw.next_step()["gold"]), "건설" if tw.level == 0 else "업그레이드"], Color(0.75, 1.0, 0.7))
			else:
				game.toast("%s 목재 적립 %d/%d" % [tw.display_name(), tw.stock, tw.stock_needed()], Color(0.95, 0.85, 0.6))
		"frost":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			var rune := FrostRuneScript.new()
			rune.game = game
			rune.position = plan["pos"]
			game.actors.add_child(rune)
			game.toast("서리 룬이 터졌습니다 — 적 %d마리 결빙" % rune.hits, Color(0.7, 0.88, 1.0))
		"lantern":
			if not game.cards.activate(uid):
				return _fail("카드가 없습니다")
			var lantern := WardLanternScript.new()
			lantern.game = game
			lantern.card_uid = uid
			lantern.position = plan["pos"]
			game.actors.add_child(lantern)
			game.toast("수호 등불을 밝혔습니다", Color(1.0, 0.85, 0.6))
		"invite":
			if not game.economy.invite_batch():
				return _fail(game.economy.invite_block_reason())
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			game.sounds.play_or("letter_send", "card_play")
			game.toast("초대장을 보냈습니다 — 손님이 곧 도착합니다", Color(1.0, 0.9, 0.7))
		"lamb":
			if not game.world.pasture.add_lamb():
				return _fail("목장에 빈자리가 없습니다")
			if not game.cards.activate(uid):
				return _fail("카드가 없습니다")
			game.world.pasture.slots.back().card_uid = uid
			game.toast("새끼양을 들였습니다 — %d일차 낮에 어른 양이 됩니다" % (game.session.day() + Cfg.LAMB_GROW_DAYS), Color(1.0, 0.97, 0.85))
		"chop":
			var person: String = entry["person"]
			if not game.cards.activate(uid):
				return _fail("카드가 없습니다")
			game.contracts.spawn_chop(person, plan["tree"], plan["pos"]).card_uid = uid
		"guard":
			var job: String = entry["id"]
			var merc: bool = job != "forest_monster"
			var person2: String = entry["person"]
			if not game.cards.activate(uid):
				return _fail("카드가 없습니다")
			game.contracts.spawn_guard("merc" if merc else "minion", person2, plan["pos"], plan.get("enemy"), job if merc else "minion").card_uid = uid
			if merc:
				game.toast("%s — %s 계약을 맺고 산장을 지킵니다" % [person2, Cfg.JOB_NAMES[job]], Color(1.0, 0.85, 0.6))
			else:
				game.toast("큰 숲의 괴물 하수인을 소환했습니다", Color(0.7, 1.0, 0.7))
		"gather":
			var person3: String = entry["person"]
			if not game.cards.activate(uid):
				return _fail("카드가 없습니다")
			game.contracts.spawn_gatherer(person3, plan["pos"]).card_uid = uid
			# 채집가의 추가 효과: 카드 한 장 드로우(주머니가 비면 드로우만 생략 — 확정 규칙 7)
			_draw_extra("채집가 " + person3)
		"campfire_fuel":
			if not game.cards.consume(uid, 1):
				return _fail("목재가 부족합니다")
			var lit_before: bool = game.world.yard.is_lit()
			game.world.yard.add_timber()
			game.sounds.play_or("fire_stoke", "card_play")
			game.toast("모닥불에 장작을 넣었습니다 — %d초 동안 탑니다" % int(ceil(game.world.yard.fuel)) if lit_before
				else "모닥불을 다시 피웠습니다 — %d초 동안 탑니다" % int(ceil(game.world.yard.fuel)), Color(1.0, 0.78, 0.45))
		"cook_stew":
			if not game.cards.consume(uid, 1):
				return _fail("생고기가 없습니다")
			var zone: String = game.cards.add("meat_stew", 1)
			game.sounds.play_or("stew_cook", "card_play")
			Fx.celebrate(plan["pos"] + Vector3(0, 0.6, 0), Color(1.0, 0.72, 0.4), 0.5)
			game.toast("고기 스튜를 끓였습니다%s — 다친 용병에게 놓아 회복" % (" (손패가 가득 차 주머니로)" if zone == "pocket" else ""), Color(1.0, 0.85, 0.6))
		"equip":
			var r: Dictionary = game.equipment.equip(plan["holder"], uid)
			if not r["ok"]:
				return _fail(r["reason"])
			var nm: String = game.cards.def(entry["id"]).get("name", "")
			game.sounds.play_or("equip", "card_play")
			var back := ""
			if r["replaced"] != "":
				back = " · '%s'은(는) 손패로" % game.cards.def(r["replaced"]).get("name", "")
			game.toast("%s — '%s' 장착%s" % [game.equipment.holder_name(plan["holder"]), nm, back], Color(1.0, 0.9, 0.65))
		"stew":
			var ally = plan["ally"]
			if not game.cards.consume(uid, 1):
				return _fail("고기 스튜가 없습니다")
			var before: float = ally.hp
			ally.hp = minf(ally.hp + ally.max_hp * Cfg.STEW_HEAL_RATIO, ally.max_hp)
			game.sounds.play("eat_meat")
			Fx.celebrate(ally.global_position + Vector3(0, 0.8, 0), Color(0.75, 1.0, 0.6), 0.5)
			game.toast("%s — 고기 스튜를 먹었습니다 · 체력 +%d" % [ally.display_name(), int(ally.hp - before)], Color(0.9, 1.0, 0.85))
		"eat":
			if not game.cards.consume(uid, 1):
				return _fail("생고기가 없습니다")
			game.sounds.play("eat_meat")
			var h: float = game.player.heal(Cfg.MEAT_HEAL)
			game.toast("생고기를 먹었습니다 — 마녀 체력 +%d" % int(h), Color(0.9, 1.0, 0.85))
		"chest":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			if game.relics.choices().is_empty():
				game.cards.add("timber", Cfg.CHEST_FALLBACK_TIMBER)
				game.toast("상자 안에는 목재 %d개가 들어 있었습니다" % Cfg.CHEST_FALLBACK_TIMBER, Color(0.95, 0.85, 0.6))
			else:
				game.chest_ui.open(plan["pos"])
		"mushroom":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			game.player.pay_hp(Cfg.MUSHROOM_HP_COST)
			var got: Array = game.cards.draw(1)
			if got.is_empty():
				game.toast("독버섯 — 체력 -%d, 주머니가 비어 뽑을 카드가 없습니다" % int(Cfg.MUSHROOM_HP_COST), Color(0.8, 0.6, 0.9))
			else:
				game.toast("독버섯 — 체력 -%d, '%s' 드로우" % [int(Cfg.MUSHROOM_HP_COST), game.cards.def(got[0]["id"]).get("name", "")], Color(0.8, 0.6, 0.9))
				game.sounds.play("card_draw")
		"spellbook":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			game.spellbook_ui.open()
		"moss":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			var healed: float = game.player.heal(Cfg.MOSS_HEAL)
			var gone: String = game.chapter.purify_one()
			if gone != "":
				game.sounds.play_or("purify", "witch_heal")
			game.toast("이끼 붕대 — 체력 +%d%s" % [int(healed), (" · '%s' 정화" % gone) if gone != "" else ""], Color(0.75, 1.0, 0.7))
		"resin":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			var fire := ResinFireScript.new()
			fire.game = game
			fire.position = plan["pos"]
			game.actors.add_child(fire)
			game.toast("송진 불길이 번졌습니다", Color(1.0, 0.7, 0.4))
		"vine", "thorn_bind":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			var vine: bool = plan["action"] == "vine"
			var caught := _root_burst(plan["pos"], Cfg.VINE_RADIUS if vine else Cfg.THORN_BIND_RADIUS,
				Cfg.VINE_DAMAGE if vine else Cfg.THORN_BIND_DAMAGE, Cfg.VINE_SLOW if vine else Cfg.THORN_BIND_SLOW,
				Cfg.VINE_TIME if vine else Cfg.THORN_BIND_TIME, Color(0.55, 0.9, 0.4) if vine else Color(0.7, 0.4, 0.9), "vine" if vine else "thorn_bind")
			game.sounds.play_or("vine_bind", "slow_apply")
			game.toast("%s — 적 %d마리를 묶었습니다" % ["덩굴 덫" if vine else "가시 속박", caught], Color(0.7, 1.0, 0.6))
		"firefly":
			if not game.cards.activate(uid):
				return _fail("카드가 없습니다")
			var swarm := FireflyScript.new()
			swarm.game = game
			swarm.card_uid = uid
			swarm.position = plan["pos"]
			game.actors.add_child(swarm)
			game.sounds.play_or("firefly_release", "card_play")
			game.toast("반딧불이 떼가 안개를 밝힙니다", Color(0.9, 1.0, 0.55))
		"firewood":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			var r2: float = game.world.lodge.repair(Cfg.FIREWOOD_REPAIR)
			game.toast("겨울 장작으로 산장 보강 +%d" % int(r2), Color(0.95, 0.85, 0.6))
		"bless":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			game.chapter.bless(plan["bless"])
			game.sounds.play_or("ritual_done", "relic_get")
			game.toast("%s — %s" % [plan["title"], plan["lines"][0]], Color(0.8, 0.85, 1.0))
		"wolf_blood":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			game.moon_powers.drink_blood()
			game.sounds.play_or("wolf_blood_drink", "witch_hurt")
			game.toast("늑대의 피 — 마녀가 괴로워합니다…", Color(0.95, 0.6, 0.75))
		"dragon":
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			game.dragon.summon()
			game.toast("용비늘을 지붕에 올렸습니다 — 용이 내려옵니다!", Color(1.0, 0.6, 0.3))
		"moon":
			var moon_id: String = entry["id"]
			if not game.cards.consume(uid):
				return _fail("카드가 없습니다")
			if not game.moon_powers.use(moon_id):
				return _fail("오늘 밤은 이미 달의 힘을 썼습니다")
			game.sounds.play_or("moon_cast", "card_play")
			game.toast("%s — %s" % [plan["title"], plan["lines"][0]], Color(0.85, 0.8, 1.0))
	game.sounds.play("card_play")
	return plan


## 카드의 추가 효과로 한 장 드로우. 주머니가 비었거나 손패가 가득 차면 조용히 생략한다.
func _draw_extra(who: String) -> void:
	if game.cards.eligible_pocket_empty():
		return
	if game.cards.hand_full():
		game.toast("%s — 손패가 가득 차 드로우를 건너뜁니다" % who, Color(0.85, 0.8, 0.95))
		return
	var got: Array = game.cards.draw(1)
	if not got.is_empty():
		game.toast("%s — '%s' 드로우" % [who, game.cards.def(got[0]["id"]).get("name", "")], Color(1.0, 0.95, 0.8))
		game.sounds.play("card_draw")


## 독버섯: 마녀에게 놓으면 체력을 깎고 주머니에서 한 장 뽑는다. 드로우 전용이므로 주머니가 비면 사용 불가·비용 없음.
func _eval_mushroom(sp: Vector2) -> Dictionary:
	var p = game.player
	if not player_hit(sp):
		return _fail("마녀에게 놓아야 합니다")
	if game.cards.eligible_pocket_empty():
		return _fail("주머니에 지금 뽑을 카드가 없습니다 (비용도 치르지 않음)", p.global_position)
	if p.hp <= Cfg.MUSHROOM_HP_COST:
		return _fail("체력이 %d 이하라 독버섯을 먹을 수 없습니다" % int(Cfg.MUSHROOM_HP_COST), p.global_position)
	return {"ok": true, "action": "mushroom", "pos": p.global_position, "title": "독버섯 — 체력을 대가로 드로우",
		"lines": ["마녀 체력 -%d (%d → %d)" % [int(Cfg.MUSHROOM_HP_COST), int(ceil(p.hp)), int(ceil(p.hp - Cfg.MUSHROOM_HP_COST))], "주머니에서 무작위 1장 드로우 · 독버섯은 버림패로"]}


## 오래된 마법서적: 어디에 놓아도 된다. 주머니에서 최대 3장을 펼쳐 한 장을 고른다(선택 중 시간 정지).
func _eval_spellbook(sp: Vector2) -> Dictionary:
	if game.cards.eligible_pocket_empty():
		return _fail("주머니에 지금 펼칠 카드가 없습니다 (비용도 치르지 않음)")
	if game.spellbook_ui == null or game.spellbook_ui.active:
		return _fail("이미 서적을 펼치고 있습니다")
	var n: int = mini(Cfg.SPELLBOOK_CHOICES, game.cards.eligible_pocket().size())
	var g = _ground_at(sp)
	var pos: Vector3 = g if g is Vector3 else game.player.global_position
	return {"ok": true, "action": "spellbook", "pos": pos, "title": "오래된 마법서적 — 세 장 중 한 장",
		"lines": ["주머니의 카드 %d장을 무작위로 펼침 · 한 장을 골라 손패로" % n, "고르지 않은 카드는 주머니에 남음 · 고르는 동안 시간 정지"]}
