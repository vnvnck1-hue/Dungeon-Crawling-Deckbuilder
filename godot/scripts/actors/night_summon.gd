extends CharacterBody3D
## 밤 소환물(종족 카드 v1, docs/race-cards-v01.md): 해골 병사(시체·일어나라·죽음의 행진) · 뼈 사냥개 · 인간 마을 민병.
## 고블린 졸개(goblin_minion.gd)와 같은 방식이다: 가까운 적에게 달려가 치고, 적이 없으면 소환 자리 주변을 서성이며, 새벽에 사라진다.
## 외형은 블록아웃 — 해골·민병은 공용 여행자 모형을 색만 바꿔 쓰고, 사냥개는 원시 도형이다(사용자 결정 2026-10-19).
## 피해·받는 피해·속도 배율은 game.race_cards 가 준다(구울의 만찬·민병의 종족 패시브).

const Data := preload("res://scripts/game/race_card_data.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const SoftSep := preload("res://scripts/actors/soft_separation.gd")
const Models := preload("res://scripts/visual/models.gd")
const CharacterModels := preload("res://scripts/visual/character_models.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")

const SPECS := {
	"skeleton": {"hp": Data.SKELETON_HP, "damage": Data.SKELETON_DAMAGE, "interval": Data.SKELETON_INTERVAL, "speed": Data.SKELETON_SPEED,
		"reach": 1.1, "aggro": 14.0, "undead": true, "ring": Color(0.85, 0.85, 0.75, 0.7), "name": "해골 병사"},
	"hound": {"hp": Data.HOUND_HP, "damage": Data.HOUND_DAMAGE, "interval": Data.HOUND_INTERVAL, "speed": Data.HOUND_SPEED,
		"reach": 0.9, "aggro": 20.0, "undead": true, "ring": Color(0.8, 0.8, 0.7, 0.7), "name": "뼈 사냥개"},
	"militia": {"hp": Data.MILITIA_HP, "damage": Data.MILITIA_DAMAGE, "interval": Data.MILITIA_INTERVAL, "speed": Data.MILITIA_SPEED,
		"reach": 1.1, "aggro": 14.0, "undead": false, "ring": Color(0.95, 0.85, 0.6, 0.7), "name": "마을 민병"},
}
const C_BONE := Color(0.86, 0.84, 0.74)

var game
# "allies" 그룹을 훑는 다른 코드(분리 밀기·HUD·괴물 표적·안개)가 읽는 속성
var kind := "skeleton"
var job := "skeleton"
var person := ""
var dead := false
var hidden := false
var on_tower := false
var hp := 20.0
var max_hp := 20.0
var hp_offset := 1.6
var carry: Dictionary = {}
var gear: Dictionary = {}
var target = null
var priority = null

var spec: Dictionary = {}
var source := ""
var home := Vector3.ZERO
var agent: NavigationAgent3D
var visual: Node3D
## 민병·해골: 인간 공용 모델의 팔다리 애니메이터(사냥개는 null).
var rig: Node
var attack_cd := 0.0
var _repath_t := 0.0
var _wander_t := 0.0
var _wander_to := Vector3.ZERO
var _bob := 0.0


func setup(g, unit: String, pos: Vector3, from := "", who := "") -> void:
	game = g
	kind = unit
	job = unit
	spec = SPECS[unit]
	source = from
	person = who
	home = pos
	_wander_to = pos
	position = pos
	max_hp = float(spec["hp"])
	hp = max_hp
	hp_offset = 1.0 if unit == "hound" else 1.7


func is_undead() -> bool:
	return bool(spec.get("undead", false))


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.25
	cap.height = 0.9
	cs.shape = cap
	cs.position.y = 0.45
	add_child(cs)
	agent = NavigationAgent3D.new()
	agent.radius = 0.3
	agent.path_desired_distance = 0.3
	agent.target_desired_distance = 0.2
	add_child(agent)
	visual = _make_visual()
	add_child(visual)
	var ring := B.torus(self, 0.26, 0.34, Vector3(0, 0.03, 0), Mats.unshaded_shared(spec["ring"], true, true))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.15, 1.0)
	add_to_group("allies")
	add_to_group("show_hp")
	add_to_group("night_summons")
	SoftSep.register(self, 0.28)
	if is_undead():
		add_to_group("undead_allies")
	if kind == "militia":
		Fx.summon(global_position, Color(1.0, 0.85, 0.55))
		Sfx.play_or(self, "militia_spawn", "merc_spawn")
	else:
		Fx.poof(global_position + Vector3(0, 0.4, 0), Color(0.75, 0.7, 0.95), 0.7)
		Sfx.play_or(self, "skeleton_rise", "minion_spawn")


func _make_visual() -> Node3D:
	if kind == "hound":
		return _make_hound()
	# 사람 모양 소환수는 인간 공용 3D 모델(예전 겨울 여행자 모델은 쓰지 않는다 — 사용자 지시 2026-10-21).
	var made := CharacterModels.make(CharacterModels.FALLBACK_MODEL)
	var v: Node3D = made.root
	rig = made.anim
	if kind == "skeleton":
		_paint(v, Mats.solid(C_BONE))
		v.scale = Vector3.ONE * 0.95
		# 눈구멍의 희미한 넋 빛(머리 묶음에 붙여 고개를 따라 움직인다)
		var head: Node3D = v
		for n in v.find_children("*", "Node3D", true, false):
			if str(n.get_meta("part_group", "")) == "head": head = n
		B.sphere(head, 0.035, Vector3(-0.08, 0.13, 0.27), Mats.unshaded(Color(0.65, 0.55, 1.0)))
		B.sphere(head, 0.035, Vector3(0.08, 0.13, 0.27), Mats.unshaded(Color(0.65, 0.55, 1.0)))
	else:
		v.scale = Vector3.ONE * 1.02
		# 민병: 긴 창 하나
		B.cyl(v, 0.025, 0.025, 1.9, Vector3(0.32, 0.95, 0.05), Mats.solid(Color(0.45, 0.32, 0.2)))
		B.prism(v, Vector3(0.08, 0.18, 0.03), Vector3(0.32, 1.95, 0.05), Mats.solid(Color(0.7, 0.72, 0.75)))
	return v


func _make_hound() -> Node3D:
	var v := Node3D.new()
	var bone := Mats.solid(C_BONE)
	var dark := Mats.solid(Color(0.35, 0.33, 0.3))
	B.box(v, Vector3(0.24, 0.2, 0.62), Vector3(0, 0.5, 0), bone)            # 몸통(갈비)
	for i in 3:
		B.box(v, Vector3(0.28, 0.04, 0.05), Vector3(0, 0.48, -0.18 + i * 0.16), dark)
	B.box(v, Vector3(0.18, 0.17, 0.26), Vector3(0, 0.66, 0.42), bone)      # 머리
	B.box(v, Vector3(0.1, 0.08, 0.14), Vector3(0, 0.6, 0.6), bone)         # 주둥이
	for x in [-0.09, 0.09]:
		for z in [-0.22, 0.22]:
			B.box(v, Vector3(0.05, 0.42, 0.05), Vector3(x, 0.21, z), bone)
		B.sphere(v, 0.025, Vector3(x * 0.6, 0.7, 0.55), Mats.unshaded(Color(0.65, 0.55, 1.0)))
	B.box(v, Vector3(0.04, 0.04, 0.3), Vector3(0, 0.58, -0.42), bone, Vector3(deg_to_rad(-25), 0, 0))  # 꼬리
	return v


static func _paint(n: Node, mat: Material) -> void:
	if n is MeshInstance3D:
		n.material_override = mat
	for c in n.get_children():
		_paint(c, mat)


func display_name() -> String:
	return ""


func short_status() -> String:
	return ""


func status_text() -> String:
	return "%s — 새벽에 사라집니다" % spec.get("name", "")


func _valid_enemy(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead and e.is_in_group("enemies")


## 표적: 가까운 적. 사냥개는 겁먹어 달아나는 적·체력이 적은 적을 먼저 쫓는다.
func _find_enemy():
	var best = null
	var best_s := INF
	var aggro: float = spec["aggro"]
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d := ActorUtil.flat_dist(e.global_position, global_position)
		if d > aggro:
			continue
		var s := d
		if kind == "hound":
			if game != null and game.get("race_cards") != null and game.race_cards.is_fleeing(e):
				s -= 12.0
			s -= 6.0 * (1.0 - clampf(float(e.hp) / maxf(float(e.max_hp), 1.0), 0.0, 1.0))
		if s < best_s:
			best_s = s
			best = e
	return best


func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_cd = maxf(attack_cd - delta, 0.0)
	var vel := Vector3.ZERO
	if not _valid_enemy(target):
		target = _find_enemy()
	if target != null:
		var dist := ActorUtil.flat_dist(target.global_position, global_position)
		if dist <= float(spec["reach"]):
			_face(target.global_position - global_position, delta)
			if attack_cd <= 0.0:
				attack_cd = float(spec["interval"]) / _rc("summon_speed_mult", 1.0)
				_strike(target)
		else:
			vel = _steer(target.global_position)
	else:
		_wander_t -= delta
		if _wander_t <= 0.0:
			_wander_t = randf_range(1.5, 3.0)
			_wander_to = home + Vector3(randf_range(-1.5, 1.5), 0, randf_range(-1.5, 1.5))
		if ActorUtil.flat_dist(_wander_to, global_position) > 0.3:
			vel = _steer(_wander_to) * 0.5
	velocity = vel + SoftSep.push(self)
	if rig != null:
		rig.play("walk" if vel.length() > 0.05 else "idle")
	if vel.length() > 0.05:
		_face(vel, delta)
		_bob += delta * 12.0
		if visual != null:
			visual.position.y = absf(sin(_bob)) * 0.05
	move_and_slide()


## race_cards 의 배율 하나(모듈이 없으면 기본값).
func _rc(fn: String, fallback: float) -> float:
	if game == null or game.get("race_cards") == null:
		return fallback
	return float(game.race_cards.call(fn, self))


func _steer(p: Vector3) -> Vector3:
	_repath_t -= get_physics_process_delta_time()
	if _repath_t <= 0.0 or agent.target_position.distance_to(p) > 0.3:
		agent.target_position = p
		_repath_t = 0.4
	var next := agent.get_next_path_position()
	var d := next - global_position
	d.y = 0.0
	if d.length() <= 0.05 or not agent.is_target_reachable():
		d = p - global_position  # 길이 없으면(헤드리스·내비 미구움) 곧장 간다
		d.y = 0.0
	var speed := float(spec["speed"]) * _rc("summon_speed_mult", 1.0)
	return d.normalized() * speed if d.length() > 0.05 else Vector3.ZERO


func _face(dir: Vector3, delta: float) -> void:
	if visual != null:
		ActorUtil.face(visual, dir, delta, 12.0)


func _strike(e) -> void:
	var dmg := float(spec["damage"]) * _rc("summon_damage_mult", 1.0)
	Fx.slash(global_position + Vector3(0, 0.6, 0), e.global_position - global_position, Color(0.85, 0.82, 1.0) if is_undead() else Color(1.0, 0.92, 0.65))
	e.take_damage(dmg)
	if game != null and game.get("race_cards") != null:
		game.race_cards.on_summon_hit(self, e)
	Sfx.play_or(self, "skeleton_attack" if is_undead() else "ally_attack", "ally_attack")


func take_damage(amount: float) -> void:
	if dead or hidden:
		return
	amount *= _rc("summon_taken_mult", 1.0)
	hp = maxf(hp - amount, 0.0)
	Fx.flash(visual)
	Fx.damage_number(get_parent(), global_position + Vector3(0, hp_offset, 0), amount, Color(1.0, 0.5, 0.45))
	if hp <= 0.0:
		leave("쓰러져")


func heal(amount: float) -> float:
	var actual := minf(amount, max_hp - hp)
	hp += actual
	return actual


## 퇴장(쓰러짐·새벽). 해골은 뼈가 무너지듯 흩어진다.
func leave(_why := "") -> void:
	if dead:
		return
	dead = true
	velocity = Vector3.ZERO
	remove_from_group("allies")
	remove_from_group("show_hp")
	remove_from_group("night_summons")
	remove_from_group("undead_allies")
	if is_undead():
		Fx.poof(global_position + Vector3(0, 0.4, 0), Color(0.8, 0.78, 0.7), 0.6)
		Fx.vanish(self, Color(0.7, 0.65, 0.9, 0.8), 0.4)
	else:
		Fx.vanish(self, Color(1.0, 0.9, 0.65, 0.8), 0.4)
