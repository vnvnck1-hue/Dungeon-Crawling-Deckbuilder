extends CharacterBody3D
## 야생 동물(토끼·사슴): 숲을 짧게 배회하며 풀을 뜯다가 마녀·적·용병이 가까이 오면 달아난다.
## 사냥꾼의 화살에 쓰러지면 전리품(토끼: 가죽 또는 생고기 / 사슴: 생고기 2)을 쏜 사냥꾼이 들고 있게 된다.
## 수명이 다하거나 밤이 되면 숲으로 사라진다. 토끼는 Codex의 GLB(없으면 블록아웃), 사슴은 사용자 제공 GLB +
## 뼈대 모션(visual/deer_visual.gd: 걷기·달아나기·풀 뜯기·경계·움찔)을 쓴다.
const DeerVisual := preload("res://scripts/visual/deer_visual.gd")

const Cfg := preload("res://scripts/config.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const SoftSep := preload("res://scripts/actors/soft_separation.gd")
const Layout := preload("res://scripts/world/layout.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

var game
var kind := "rabbit"          # rabbit | deer
var hp := Cfg.RABBIT_HP
var max_hp := Cfg.RABBIT_HP
var dead := false
var hp_offset := 0.6
var speed := Cfg.RABBIT_SPEED
var life := Cfg.ANIMAL_LIFETIME
var last_hunter = null
var visual: Node3D
var body: Node3D
var head: Node3D
var agent: NavigationAgent3D
var _target := Vector3.ZERO
var _wait := 0.0
var _anim_t := 0.0
var _fleeing := false
var _repath_t := 0.0
var _rng := RandomNumberGenerator.new()


func setup(g, animal_kind: String) -> void:
	game = g
	kind = animal_kind
	if kind == "deer":
		hp = Cfg.DEER_HP
		max_hp = Cfg.DEER_HP
		speed = Cfg.DEER_SPEED
		hp_offset = 1.75
	else:
		hp = Cfg.RABBIT_HP
		max_hp = Cfg.RABBIT_HP
		speed = Cfg.RABBIT_SPEED
		hp_offset = 0.6


func _ready() -> void:
	_rng.randomize()
	collision_layer = 0
	collision_mask = Cfg.L_OBSTACLE | Cfg.L_BOUNDARY
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.2 if kind == "rabbit" else 0.35
	cap.height = 0.5 if kind == "rabbit" else 1.1
	cs.shape = cap
	cs.position.y = cap.height * 0.5
	add_child(cs)
	agent = NavigationAgent3D.new()
	agent.radius = 0.3
	agent.path_desired_distance = 0.3
	agent.target_desired_distance = 0.2
	add_child(agent)
	visual = _make_visual()
	body = visual.get_node_or_null("Body")
	if body == null:
		body = visual
	head = body.get_node_or_null("Head")
	add_child(visual)
	visual.rotation.y = _rng.randf_range(0, TAU)
	add_to_group("animals")
	SoftSep.register(self, 0.2 if kind == "rabbit" else 0.36, 0.6 if kind == "rabbit" else 1.0)
	add_to_group("show_hp")
	_target = global_position
	_wait = _rng.randf_range(0.5, 2.0)
	_anim_t = _rng.randf() * 10.0
	Fx.poof(global_position + Vector3(0, 0.3, 0), Color(0.9, 0.9, 1.0, 0.6), 0.5)


func _make_visual() -> Node3D:
	if kind == "deer":
		return DeerVisual.new()
	var path := "res://scenes/props/nature/%s.tscn" % kind
	if ResourceLoader.exists(path):
		var scene: PackedScene = load(path)
		var n: Node3D = scene.instantiate()
		if n.get_node_or_null("Body") != null:
			return n
		# Body 노드가 없는 납품본은 래퍼로 감싼다
		var wrap := Node3D.new()
		var b := Node3D.new()
		b.name = "Body"
		wrap.add_child(b)
		b.add_child(n)
		return wrap
	return _blockout()


## 납품 전 블록아웃: 토끼(둥근 몸·긴 귀) / 사슴(긴 다리·뿔).
func _blockout() -> Node3D:
	var root := Node3D.new()
	var b := B.node(root, Vector3.ZERO, Vector3.ZERO, "Body")
	if kind == "rabbit":
		var fur := Mats.solid(Color("8f7a66"), {"rim_strength": 0.3})
		var belly := Mats.solid(Color("e8e0d2"))
		B.sphere(b, 0.16, Vector3(0, 0.17, 0), fur, Vector3(1.0, 0.85, 1.35))
		B.sphere(b, 0.1, Vector3(0, 0.12, -0.02), belly, Vector3(1.0, 0.6, 1.2))
		B.sphere(b, 0.06, Vector3(0, 0.2, -0.24), belly, Vector3.ONE, 6, 3)
		var h := B.node(b, Vector3(0, 0.3, 0.2), Vector3.ZERO, "Head")
		B.sphere(h, 0.11, Vector3.ZERO, fur, Vector3(0.9, 0.9, 1.1), 8, 4)
		for x: float in [-0.05, 0.05]:
			B.cyl(h, 0.025, 0.035, 0.22, Vector3(x, 0.17, -0.03), fur, 6, Vector3(-10, 0, x * 200.0))
			B.sphere(h, 0.02, Vector3(x * 1.4, 0.03, 0.09), Mats.solid(Color("2a2024")), Vector3.ONE, 6, 3)
	else:
		var fur := Mats.solid(Color("8a5a36"), {"rim_strength": 0.3})
		var belly := Mats.solid(Color("e3d6c4"))
		var horn := Mats.solid(Color("eadcb8"))
		B.sphere(b, 0.3, Vector3(0, 0.78, 0), fur, Vector3(0.75, 0.7, 1.4))
		B.sphere(b, 0.2, Vector3(0, 0.66, 0), belly, Vector3(0.7, 0.55, 1.3))
		B.sphere(b, 0.05, Vector3(0, 0.86, -0.42), belly, Vector3.ONE, 6, 3)
		for x: float in [-0.12, 0.12]:
			for z: float in [-0.28, 0.28]:
				B.cyl(b, 0.035, 0.04, 0.62, Vector3(x, 0.31, z), fur, 6)
		var neck := B.node(b, Vector3(0, 0.95, 0.35), Vector3(35, 0, 0))
		B.cyl(neck, 0.08, 0.11, 0.42, Vector3(0, 0.15, 0), fur, 8)
		var h := B.node(b, Vector3(0, 1.3, 0.52), Vector3.ZERO, "Head")
		B.sphere(h, 0.12, Vector3(0, 0, 0.02), fur, Vector3(0.8, 0.8, 1.35), 8, 4)
		B.sphere(h, 0.035, Vector3(0, -0.02, 0.18), Mats.solid(Color("2a2024")), Vector3.ONE, 6, 3)
		for x: float in [-0.06, 0.06]:
			B.cyl(h, 0.02, 0.03, 0.14, Vector3(x * 1.3, 0.1, -0.06), fur, 5, Vector3(0, 0, x * 350.0))
			var a := B.node(h, Vector3(x, 0.14, -0.04), Vector3(-15, 0, x * 260.0))
			B.cyl(a, 0.012, 0.02, 0.32, Vector3(0, 0.16, 0), horn, 5)
			B.cyl(a, 0.008, 0.014, 0.16, Vector3(x * 0.6, 0.24, 0.02), horn, 5, Vector3(0, 0, x * 400.0))
	return root


func _flat(p: Vector3) -> float:
	return ActorUtil.flat_dist(p, global_position)


func _threat():
	# 후보 배열을 만들지 않고 마녀 → 적 → 동료 순서로 바로 견준다(먼저 나온 쪽이 같은 거리에서 이긴다)
	_best = null
	_best_d = Cfg.ANIMAL_FLEE_RADIUS
	if game.player != null and not game.player.dead:
		_consider(game.player)
	for e in get_tree().get_nodes_in_group("enemies"):
		_consider(e)
	for a in get_tree().get_nodes_in_group("allies"):
		if not a.hidden:
			_consider(a)
	return _best


var _best = null
var _best_d := 0.0

func _consider(c) -> void:
	if c.get(&"dead") == true:
		return
	var d := _flat(c.global_position)
	if d < _best_d:
		_best_d = d
		_best = c


func _pick_target(away_from = null) -> void:
	var p: Vector3
	if away_from != null:
		var dir: Vector3 = global_position - away_from
		dir.y = 0.0
		if dir.length() < 0.05:
			dir = Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
		p = global_position + dir.normalized() * _rng.randf_range(4.0, 6.0) + Vector3(_rng.randf_range(-1, 1), 0, _rng.randf_range(-1, 1))
	else:
		var a := _rng.randf_range(0.0, TAU)
		p = global_position + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(1.0, 3.0)
	p = Layout.clamp_to_map(p, 2.0)
	var nav = NavUtil.walkable_from(get_world_3d().navigation_map, global_position, p, 2.0)
	_target = nav if nav != null else global_position


func _physics_process(delta: float) -> void:
	if dead:
		return
	life -= delta
	if life <= 0.0 or (game.session != null and game.session.state != 0 and not _fleeing):
		leave()
		return
	var threat = _threat()
	var vel := Vector3.ZERO
	var running := false
	if threat != null:
		if not _fleeing:
			_fleeing = true
			_wait = 0.0
			Sfx.play_or(self, "animal_flee", "sheep_flee")
		if _wait <= 0.0 or _flat(_target) < 0.4:
			_pick_target(threat.global_position)
			_wait = 0.6
		_wait -= delta
		vel = _steer(_target, speed)
		running = true
	else:
		_fleeing = false
		if _wait > 0.0:
			_wait -= delta
			if _wait <= 0.0:
				_pick_target()
		elif _flat(_target) < 0.15:
			_wait = _rng.randf_range(1.5, 4.0)
		else:
			vel = _steer(_target, speed * 0.35)
	velocity = vel + SoftSep.push(self)
	move_and_slide()
	global_position.y = 0.0
	if vel.length() > 0.05:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(vel.x, vel.z), clampf(delta * 8.0, 0.0, 1.0))
	if visual is DeerVisual:
		# 사슴은 비주얼이 직접 움직인다: 속도·풀 뜯기(멈춰 기다리는 중)·경계(달아나는 중)만 넘긴다
		visual.speed = vel.length()
		visual.grazing = vel.length() <= 0.05 and not running
		visual.alarmed = running
	else:
		_animate(delta, vel.length() > 0.05, running)


func _steer(p: Vector3, spd: float) -> Vector3:
	_repath_t -= get_physics_process_delta_time()
	if _repath_t <= 0.0 or agent.target_position.distance_to(p) > 0.3:
		agent.target_position = p
		_repath_t = 0.35
	var next := agent.get_next_path_position()
	var d := next - global_position
	d.y = 0.0
	return d.normalized() * spd if d.length() > 0.05 else Vector3.ZERO


func _animate(delta: float, walking: bool, running: bool) -> void:
	_anim_t += delta * (14.0 if running else (7.0 if walking else 2.0))
	if kind == "rabbit":
		body.position.y = absf(sin(_anim_t)) * (0.14 if running else (0.06 if walking else 0.0))
	else:
		body.position.y = absf(sin(_anim_t)) * (0.08 if running else (0.03 if walking else 0.0))
	if head != null:
		head.rotation.x = 0.0 if walking else 0.45 + sin(_anim_t) * 0.08


func take_damage(amount: float) -> void:
	if dead:
		return
	hp = maxf(hp - amount, 0.0)
	Fx.flash(visual)
	if visual is DeerVisual:
		visual.flinch()
	Fx.damage_number(get_parent(), global_position + Vector3(0, hp_offset + 0.3, 0), amount, Color(1.0, 0.8, 0.6))
	if hp <= 0.0:
		die()
	else:
		_fleeing = false
		_wait = 0.0


## 전리품. 토끼: 가죽 또는 생고기(50:50) / 사슴: 생고기 2.
func loot() -> Dictionary:
	if kind == "deer":
		return {"raw_meat": Cfg.DEER_MEAT}
	return {"rabbit_pelt": 1} if _rng.randf() < 0.5 else {"raw_meat": 1}


func die() -> void:
	dead = true
	velocity = Vector3.ZERO
	remove_from_group("animals")
	remove_from_group("show_hp")
	collision_mask = 0
	Sfx.play_or(self, "animal_hurt", "sheep_hurt")
	if last_hunter != null and is_instance_valid(last_hunter) and not last_hunter.dead:
		last_hunter.receive_loot(loot())
	Fx.poof(global_position + Vector3(0, 0.4, 0), Color(0.95, 0.9, 0.85), 0.8)
	Fx.vanish(self, Color(0.9, 0.85, 0.8, 0.8), 0.5)


## 밤·수명 종료: 숲으로 사라진다(전리품 없음).
func leave() -> void:
	if dead:
		return
	dead = true
	velocity = Vector3.ZERO
	remove_from_group("animals")
	remove_from_group("show_hp")
	collision_mask = 0
	Fx.vanish(self, Color(0.8, 0.85, 1.0, 0.6), 0.7)
