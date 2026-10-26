extends CharacterBody3D
## 고블린 졸개(고블린 카드 v1): 밤 동안만 있는 작고 약한 고블린. 사촌 패거리·그라즈의 호루라기가 부른다.
## 가까운 적에게 달려가 짧게 찌르고, 적이 없으면 소환 자리 주변을 서성인다. 밤이 끝나면 숲으로 돌아간다(목재 없음).
## 외형은 고블린 니브의 파츠 모델을 줄여 쓴다(없으면 공용 여행자 모형). 적이 노리는 "allies" 그룹에 든다.

const GoblinData := preload("res://scripts/game/goblin_data.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const SoftSep := preload("res://scripts/actors/soft_separation.gd")
const CharacterModels := preload("res://scripts/visual/character_models.gd")
const Models := preload("res://scripts/visual/models.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")

var game
# "allies" 그룹을 훑는 다른 코드(분리 밀기·HUD·괴물 표적·안개)가 읽는 속성
var kind := "goblin_minion"
var job := "goblin_minion"
var person := ""
var dead := false
var hidden := false
var on_tower := false
var hp := GoblinData.MINION_HP
var max_hp := GoblinData.MINION_HP
var hp_offset := 1.0
var carry: Dictionary = {}
var gear: Dictionary = {}
var target = null
var priority = null

var source := ""            # gang | whistle — 어디서 불렀는지
var owner_ally = null       # 호루라기를 분 용병(호루라기 졸개 상한을 셀 때)
var home := Vector3.ZERO
var rush_to = null          # 떼거리 돌격 목적지(Vector3) — 도착하면 범위 피해는 카드가 이미 줬으므로 바로 교전
var agent: NavigationAgent3D
var visual: Node3D
var rig = null
var attack_cd := 0.0
var _repath_t := 0.0
var _wander_t := 0.0
var _wander_to := Vector3.ZERO


func setup(g, pos: Vector3, from: String, by = null) -> void:
	game = g
	home = pos
	_wander_to = pos
	source = from
	owner_ally = by
	position = pos


func _ready() -> void:
	collision_layer = 0
	collision_mask = 0
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2
	cap.height = 0.6
	cs.shape = cap
	cs.position.y = 0.3
	add_child(cs)
	agent = NavigationAgent3D.new()
	agent.radius = 0.25
	agent.path_desired_distance = 0.3
	agent.target_desired_distance = 0.2
	add_child(agent)
	var made := CharacterModels.make("nib")
	if made.is_empty(): made = CharacterModels.make("goblin_common")
	visual = made.root
	rig = made.anim
	visual.scale = Vector3.ONE * GoblinData.MINION_SCALE
	add_child(visual)
	var ring := B.torus(self, 0.2, 0.27, Vector3(0, 0.03, 0), Mats.unshaded_shared(Color(0.62, 0.86, 0.35, 0.7), true, true))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.15, 1.0)
	add_to_group("allies")
	add_to_group("show_hp")
	add_to_group("goblin_minions")
	SoftSep.register(self, 0.22, 0.6)
	Fx.poof(global_position + Vector3(0, 0.3, 0), Color(0.6, 0.85, 0.35), 0.6)
	Sfx.play_or(self, "goblin_minion_spawn", "minion_spawn")


## 머리 위 이름표는 비운다(졸개가 여럿이면 글자가 화면을 덮는다 — 체력 막대와 초록 발밑 고리로 구별)
func display_name() -> String:
	return ""


func short_status() -> String:
	return ""


func status_text() -> String:
	return "밤 동안만 싸우는 고블린 졸개"


func _valid_enemy(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead and e.is_in_group("enemies")


func _find_enemy():
	var best = null
	var best_d := GoblinData.MINION_AGGRO
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d := ActorUtil.flat_dist(e.global_position, global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func _physics_process(delta: float) -> void:
	if dead:
		return
	attack_cd = maxf(attack_cd - delta, 0.0)
	var vel := Vector3.ZERO
	if rush_to != null:
		var to: Vector3 = rush_to
		if ActorUtil.flat_dist(to, global_position) <= 0.5:
			rush_to = null
		else:
			var d := to - global_position
			d.y = 0.0
			vel = d.normalized() * GoblinData.MINION_SPEED * 2.2
	if rush_to == null:
		if not _valid_enemy(target):
			target = _find_enemy()
		if target != null:
			var dist := ActorUtil.flat_dist(target.global_position, global_position)
			if dist <= GoblinData.MINION_REACH:
				_face(target.global_position - global_position, delta)
				if attack_cd <= 0.0:
					attack_cd = GoblinData.MINION_INTERVAL
					_stab(target)
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
	if vel.length() > 0.05:
		_face(vel, delta)
	move_and_slide()
	if rig != null:
		rig.play("walk" if vel.length() > 0.1 else "idle")


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
	return d.normalized() * GoblinData.MINION_SPEED if d.length() > 0.05 else Vector3.ZERO


func _face(dir: Vector3, delta: float) -> void:
	if visual != null:
		ActorUtil.face(visual, dir, delta, 12.0)


## 짧은 찌르기. 반짝이 미끼 근처의 적에게는 피해가 늘어난다.
func _stab(e) -> void:
	var dmg := GoblinData.MINION_DAMAGE
	if game != null and game.get("goblin") != null:
		dmg *= game.goblin.minion_damage_mult(e)
	Fx.slash(global_position + Vector3(0, 0.4, 0), e.global_position - global_position, Color(0.75, 1.0, 0.5))
	e.take_damage(dmg)
	Sfx.play_or(self, "goblin_minion_attack", "ally_attack")


func take_damage(amount: float) -> void:
	if dead or hidden:
		return
	hp = maxf(hp - amount, 0.0)
	Fx.flash(visual)
	Fx.damage_number(get_parent(), global_position + Vector3(0, 1.1, 0), amount, Color(1.0, 0.5, 0.45))
	if hp <= 0.0:
		leave("쓰러져")


## 퇴장(쓰러짐·새벽). 목재를 남기지 않는다.
func leave(_why := "") -> void:
	if dead:
		return
	dead = true
	velocity = Vector3.ZERO
	remove_from_group("allies")
	remove_from_group("show_hp")
	remove_from_group("goblin_minions")
	Fx.poof(global_position + Vector3(0, 0.3, 0), Color(0.55, 0.7, 0.35), 0.5)
	Fx.vanish(self, Color(0.55, 0.75, 0.4, 0.8), 0.4)
