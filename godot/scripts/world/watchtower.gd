extends StaticBody3D
## 감시탑(docs/watchtower-v01.md). 앞마당 감시탑 공터(Layout.TOWER_SITE_LEFT/RIGHT)마다 하나씩 있다.
##  - level 0: 빈 공터. 준비 시간에 목재 카드를 공터에 끌어 놓아 적립한다(stock). 다 모이면 산장 관리창에서 골드를 내고 짓는다.
##  - level 1: 사냥꾼 1명이 밤에 올라가 긴 사거리·강한 화살로 쏜다. 주변 안개를 걷어 낸다.
##  - level 2: 1단계 위에 다시 목재를 적립하고 더 많은 골드로 업그레이드한다. 사냥꾼 3명.
##  - 괴물은 지나가다 탑을 공격한다(monster._pick_foe 의 "watchtowers" 그룹). 체력이 0이면 무너져(collapsed)
##    사냥꾼이 내려오고 시야·사격이 멈춘다. 산장처럼 목재 카드로 수리하며, 무너진 탑도 수리하면 다시 선다.
## 충돌은 지은 뒤에만 켜고(L_OBSTACLE) 내비를 다시 굽는다.

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const Model := preload("res://scripts/visual/watchtower_model.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")

signal attacked(attacker)

var game
var site_id := "left"            # left | right
var site_center := Vector2.ZERO
var level := 0
var stock := 0                   # 다음 단계를 위해 적립한 목재
var hp := 0.0
var max_hp := 0.0
var dead := false                # 무너짐(또는 아직 없음). 체력 바·적 표적에서 빠진다
var collapsed := false
var hp_offset := 3.6
var foe_radius := Cfg.TOWER_FOE_RADIUS
var sight_radius := 0.0
var climb_point := Vector3.ZERO  # 사다리 아래(이동 가능 지면)
var perched: Array = []          # 올라가 있거나 올라가는 중인 사냥꾼
var last_attacker = null
var visual: Node3D
var _model: Node3D
var _shape: CollisionShape3D
var _label: Label3D
var _shake_t := 0.0


func setup(g, id: String, center: Vector2) -> void:
	game = g
	site_id = id
	site_center = center
	name = "Watchtower_" + id
	position = Vector3(center.x, 0, center.y)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	_shape = CollisionShape3D.new()
	_shape.disabled = true
	add_child(_shape)
	_label = Label3D.new()
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 30
	_label.pixel_size = 0.007
	_label.outline_size = 9
	_label.no_depth_test = true
	add_child(_label)
	add_to_group("watchtower_sites")
	_refresh()


# ───────────────────────── 상태 질의 ─────────────────────────

func display_name() -> String:
	return ("왼쪽" if site_id == "left" else "오른쪽") + " 감시탑"


func is_standing() -> bool:
	return level > 0 and not collapsed


func max_level() -> int:
	return Cfg.TOWER_LEVELS.size()


## 다음 단계 정보(최대 단계면 빈 사전).
func next_step() -> Dictionary:
	return Cfg.TOWER_LEVELS[level] if level < max_level() else {}


func stock_needed() -> int:
	return int(next_step().get("timber", 0))


func stock_full() -> bool:
	return level < max_level() and stock >= stock_needed()


func slots() -> int:
	return int(Cfg.TOWER_LEVELS[level - 1]["slots"]) if level > 0 else 0


func needs_repair() -> bool:
	return level > 0 and hp < max_hp


## 지면·탑을 가리키는 판정 영역(공터 사각형 + 여유).
func site_rect() -> Rect2:
	return Layout.tower_site_rect(site_center).grow(0.4)


func contains_ground(p: Vector3) -> bool:
	return site_rect().has_point(Vector2(p.x, p.z))


## 목재 1장을 공터에 놓았을 때 할 일: "repair" | "deposit" | "" (사유는 timber_block_reason).
func timber_action() -> String:
	if needs_repair():
		return "repair"
	if level < max_level() and not stock_full():
		return "deposit"
	return ""


func timber_block_reason() -> String:
	if level >= max_level():
		return display_name() + " 체력이 최대입니다"
	if stock_full():
		return "목재가 다 모였습니다 — 산장 관리창에서 %d골드로 %s" % [int(next_step()["gold"]), "건설" if level == 0 else "업그레이드"]
	return ""


# ───────────────────────── 적립·건설·수리 ─────────────────────────

func deposit(n := 1) -> int:
	var add := mini(n, stock_needed() - stock)
	if add <= 0:
		return 0
	stock += add
	Fx.celebrate(global_position + Vector3(0, 0.4, 0), Color(0.95, 0.8, 0.5), 0.7)
	Sfx.play(self, "lodge_repair")
	_refresh()
	return add


## 경제(lodge_economy.buy)가 골드를 받은 뒤 부른다. 적립 목재를 쓰고 한 단계 올린다.
func construct() -> bool:
	if not stock_full():
		return false
	stock = 0
	level += 1
	var step: Dictionary = Cfg.TOWER_LEVELS[level - 1]
	max_hp = float(step["hp"])
	hp = max_hp
	collapsed = false
	dead = false
	sight_radius = float(step["sight"])
	_build_visual(true)
	_enable_body()
	add_to_group("watchtowers")
	add_to_group("show_hp")
	add_to_group("sight_sources")
	Fx.celebrate(global_position + Vector3(0, 1.0, 0), Fx.C_GOLD, 1.6)
	Sfx.play(self, "room_build")
	_refresh()
	return true


func repair(amount: float) -> float:
	if level == 0:
		return 0.0
	var actual := minf(amount, max_hp - hp)
	if actual <= 0.0:
		return 0.0
	hp += actual
	if collapsed:
		collapsed = false
		dead = false
		_build_visual(true)
		add_to_group("watchtowers")
		add_to_group("show_hp")
		add_to_group("sight_sources")
	Fx.heal(global_position + Vector3(0, 1.5, 0))
	Fx.celebrate(global_position + Vector3(0, 1.0, 0), Color(0.95, 0.8, 0.5))
	Sfx.play(self, "lodge_repair")
	_refresh()
	return actual


func take_damage(amount: float, attacker = null) -> void:
	if not is_standing():
		return
	if game != null and game.get("race_cards") != null and game.race_cards.facility_shielded():
		return  # 돌 속의 노래(종족 카드 v1): 시설이 피해를 받지 않는다
	hp = maxf(hp - amount, 0.0)
	if attacker != null:
		last_attacker = attacker
		attacked.emit(attacker)
	Fx.flash(visual, 0.45)
	Fx.splinters(global_position + Vector3(randf_range(-0.8, 0.8), randf_range(0.6, 2.2), randf_range(-0.8, 0.8)))
	Sfx.play(self, "lodge_hit")
	_shake_t = 0.18
	if hp <= 0.0:
		_collapse()
	_refresh()


func _collapse() -> void:
	collapsed = true
	dead = true
	release_all()
	remove_from_group("watchtowers")
	remove_from_group("show_hp")
	remove_from_group("sight_sources")
	Sfx.play(self, "lodge_fall")
	Fx.splinters(global_position + Vector3(0, 1.5, 0))
	if _model != null:
		var tw := _model.create_tween()
		tw.tween_property(_model, "rotation_degrees", Vector3(14, 0, -9), 0.5).set_trans(Tween.TRANS_BACK)
		tw.parallel().tween_property(_model, "position:y", -0.9, 0.5)
	if game != null:
		game.toast("%s이(가) 무너졌습니다 — 목재로 수리하면 다시 섭니다" % display_name(), Color(1.0, 0.6, 0.5))


# ───────────────────────── 사냥꾼 자리 ─────────────────────────

func has_free_slot() -> bool:
	_prune()
	return is_standing() and perched.size() < slots()


func claim(hunter) -> bool:
	if not has_free_slot() or perched.has(hunter):
		return false
	perched.append(hunter)
	return true


func release(hunter) -> void:
	perched.erase(hunter)


## 무너지거나 새벽이 되면 모두 내려보낸다.
func release_all() -> void:
	for h in perched.duplicate():
		if is_instance_valid(h) and h.has_method("leave_tower"):
			h.leave_tower()
	perched.clear()


## 올라간 사냥꾼의 발판 위 위치(월드).
func perch_position(hunter) -> Vector3:
	var i := maxi(perched.find(hunter), 0)
	var spots: Array = Model.PERCHES[clampi(level - 1, 0, 1)]
	return global_position + spots[i % spots.size()] + Vector3(0, Model.floor_height(), 0)


func _prune() -> void:
	# 매 틱 불리므로 복사본을 만들지 않고 뒤에서부터 지운다
	for i in range(perched.size() - 1, -1, -1):
		var h = perched[i]
		if not is_instance_valid(h) or h.dead or h.get("tower") != self:
			perched.remove_at(i)


# ───────────────────────── 모양·충돌 ─────────────────────────

func _build_visual(pop: bool) -> void:
	if _model != null:
		_model.queue_free()
	_model = Model.build(level)
	visual.add_child(_model)
	hp_offset = Model.size_of(level).y + 0.4
	_label.position.y = hp_offset + 0.35
	if pop:
		_model.scale = Vector3(1, 0.05, 1)
		var tw := _model.create_tween()
		tw.tween_property(_model, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _enable_body() -> void:
	var size := Model.size_of(level)
	var box := BoxShape3D.new()
	# 기둥 사이를 다 막아 괴물·마녀가 탑을 통과하지 않게 한다(사다리 쪽은 climb_point 로 접근).
	box.size = Vector3(size.x * 0.72, maxf(Cfg.OBSTACLE_MIN_HEIGHT, 2.0), size.z * 0.72)
	_shape.shape = box
	_shape.position.y = box.size.y * 0.5
	_shape.disabled = false
	collision_layer = Cfg.L_OBSTACLE
	if game != null and game.world != null:
		game.world.bake_nav()
	_find_climb_point(size)


## 사다리 아래 지점: 공터에서 마당 중심(모닥불) 쪽 가장자리의 이동 가능 지면.
func _find_climb_point(size: Vector3) -> void:
	var to_yard := Vector2(Layout.CAMPFIRE.x, Layout.CAMPFIRE.z) - site_center
	var dir := to_yard.normalized() if to_yard.length() > 0.01 else Vector2(0, 1)
	var reach := maxf(size.x, size.z) * 0.36 + 0.7
	var p := Vector3(site_center.x + dir.x * reach, 0, site_center.y + dir.y * reach)
	climb_point = p


## 사냥꾼이 걸어갈 사다리 아래 지점. 탑을 지은 뒤 굽힌 내비 위의 가까운 지면으로 맞춘다.
func climb_spot() -> Vector3:
	if not is_inside_tree():
		return climb_point
	var q := NavUtil.ground_or_near(get_world_3d().navigation_map, climb_point)
	q.y = 0.0
	return q


func _refresh() -> void:
	if _label == null:
		return
	var text := ""
	var col := Color(1.0, 0.9, 0.65)
	if level == 0:
		var need := stock_needed()
		text = "감시탑 공터 · 목재 %d/%d" % [stock, need]
		if stock_full():
			text = "감시탑 준비 완료 · 관리창에서 %dG" % int(next_step()["gold"])
			col = Color(0.75, 1.0, 0.7)
		_label.position.y = 1.2
	elif collapsed:
		text = "무너진 %s · 목재로 수리" % display_name()
		col = Color(1.0, 0.55, 0.5)
	elif level < max_level() and stock > 0:
		text = "2단계 목재 %d/%d" % [stock, stock_needed()] if not stock_full() else "2단계 준비 완료 · 관리창에서 %dG" % int(next_step()["gold"])
	_label.text = text
	_label.modulate = col
	_label.visible = text != "" and (game == null or game.session == null or game.session.state == SessionScript.State.PREP or collapsed)


func _process(delta: float) -> void:
	if _label != null:
		_refresh()
	if _shake_t > 0.0 and visual != null:
		_shake_t -= delta
		visual.position = Vector3(randf_range(-0.04, 0.04), 0, randf_range(-0.04, 0.04)) if _shake_t > 0.0 else Vector3.ZERO
