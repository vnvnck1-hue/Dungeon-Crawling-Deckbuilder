extends CharacterBody3D
## Territorial resident. Lives outside the night wave roster; a leash always wins over aggro.
const Cfg := preload("res://scripts/config.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const SoftSep := preload("res://scripts/actors/soft_separation.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const Kit := preload("res://scripts/visual/toxic_kit.gd")
const Venom := preload("res://scripts/visual/venom_vfx.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const FrostVfx := preload("res://scripts/visual/vfx/frost_rune_vfx.gd")
enum State { IDLE, CHASE, RETURN, DEAD }
const SIGHT := 7.5
const LOSE_SIGHT := 10.5
const LEASH := 10.5
var game
var site: Dictionary
var home := Vector3.ZERO
var flying := false
var state := State.IDLE
var hp := 60.0
var max_hp := 60.0
var dead := false
var hp_offset := 1.9
var aim_height := .85
var damage := 7.0
var speed := 2.9
var target = null
var visual: Node3D
var body: Node3D
var agent: NavigationAgent3D
var path_failed := false
var card_drop := "" # existing world HUD's optional enemy-card marker interface
var attack_cd := .7
var _roam := Vector3.ZERO
var _roam_t := 1.0
var _scan_t := 0.0
var _repath_t := 0.0
var _phase := 0.0
var _lunge := 0.0
var _hurt_t := -1.0     # 피격 반동: 맞은 뒤 경과 초(음수면 없음)
var _slows: Dictionary = {}
var _frost_mark: MeshInstance3D
var _legs: Array[Node3D] = []
var _wings: Array[Node3D] = []
var _rng := RandomNumberGenerator.new()
var _buzz_id := ""  # 날갯짓 반복음 id(매 틱 문자열을 만들지 않게 _ready 에서 한 번 만든다)

func setup(g, habitat: Dictionary, spawn_at: Vector3, airborne: bool, index: int) -> void:
	game=g
	site=habitat
	home=spawn_at
	position=spawn_at
	flying=airborne
	_rng.seed=int(site.seed)+index*83
	_phase=_rng.randf()*TAU
	if flying:
		speed=3.25
		hp=48.0
		max_hp=hp
		hp_offset=3.0
		aim_height=2.0

func _ready() -> void:
	_buzz_id = "insect_%d" % get_instance_id()
	name="VenomFlyer" if flying else "VenomCrawler"
	collision_layer=0
	collision_mask=Cfg.L_OBSTACLE|Cfg.L_BOUNDARY
	var cs:=CollisionShape3D.new()
	var shape:=CapsuleShape3D.new()
	shape.radius=.34
	shape.height=1.0
	cs.shape=shape
	cs.position.y=.5
	add_child(cs)
	agent=NavigationAgent3D.new()
	agent.radius=.42
	agent.path_desired_distance=.4
	agent.target_desired_distance=.3
	add_child(agent)
	visual=Kit.insect()
	visual.scale=Vector3.ONE*(.82 if flying else .88)
	add_child(visual)
	body=visual.get_node("Body")
	for child in body.get_children():
		if child.has_meta("front"):
			if "Wing" in str(child.name): _wings.append(child)
			else: _legs.append(child)
	add_to_group("enemies")
	add_to_group("hazard_insects")
	SoftSep.register(self, 0.3)
	add_to_group("show_hp")
	_roam=home
	_animate(0.0)

func _flat_to(p: Vector3) -> float:
	return ActorUtil.flat_dist(p, global_position)

func _from_center(p: Vector3) -> float:
	return Vector2(p.x,p.z).distance_to(site.center)

func _valid(candidate) -> bool:
	return is_instance_valid(candidate) and not candidate.dead

func _visible(candidate) -> bool:
	return ActorUtil.has_los(self, candidate)

func _find_target():
	var candidates: Array=get_tree().get_nodes_in_group("allies")
	candidates.append(game.player)
	var best=null
	var distance:=SIGHT
	for candidate in candidates:
		if not _valid(candidate) or _from_center(candidate.global_position)>LEASH: continue
		var d:=_flat_to(candidate.global_position)
		if d<distance and _visible(candidate):
			distance=d
			best=candidate
	return best

func _return_home() -> void:
	state=State.RETURN
	target=null
	_repath_t=0.0
	attack_cd=.7

func _physics_process(delta: float) -> void:
	if dead: return
	_tick_slows(delta)
	if flying:
		Sfx.loop(self, _buzz_id, "insect_buzz", Sfx.near_player(self, 2.0, 9.0) * 0.8)
	_scan_t-=delta
	if state==State.CHASE:
		if not _valid(target) or _from_center(global_position)>LEASH or _from_center(target.global_position)>LEASH or _flat_to(target.global_position)>LOSE_SIGHT:
			_return_home()
	elif state==State.IDLE and _scan_t<=0.0:
		_scan_t=.22
		target=_find_target()
		if target!=null:
			state=State.CHASE
			_repath_t=0.0
			Sfx.play(self, "insect_aggro")
	var destination:=home
	if state==State.CHASE:
		destination=target.global_position
	elif state==State.IDLE:
		_roam_t-=delta
		if _roam_t<=0.0:
			_roam_t=_rng.randf_range(2.0,5.0)
			var angle:=_rng.randf()*TAU
			var desired:=home+Vector3(cos(angle),0,sin(angle))*_rng.randf_range(.4,1.6)
			_roam=NavUtil.ground_or_near(get_world_3d().navigation_map,desired,1.6)
		destination=_roam
	velocity=Vector3.ZERO
	attack_cd=maxf(0.0,attack_cd-delta)
	if state==State.CHASE and _flat_to(destination)<1.35:
		_face(destination-global_position,delta)
		if attack_cd<=0.0 and _visible(target):
			attack_cd=1.35
			_lunge=.32
			target.take_damage(damage)
			Fx.claw(global_position+Vector3(0,aim_height,0),destination-global_position)
			Sfx.play(self, "insect_aggro")
	elif _flat_to(destination)>.35:
		_repath_t-=delta
		if _repath_t<=0.0:
			agent.target_position=destination
			_repath_t=.28
		if NavigationServer3D.map_get_iteration_id(get_world_3d().navigation_map)>0:
			var next:=agent.get_next_path_position()
			var direction:=next-global_position
			direction.y=0.0
			if direction.length()>.05: velocity=direction.normalized()*speed*slow_factor()*(.4 if state==State.IDLE else 1.0)
			path_failed=agent.is_navigation_finished() and _flat_to(destination)>1.0
		_face(velocity,delta)
	velocity+=SoftSep.push(self)
	move_and_slide()
	global_position.y=0.0
	if state==State.RETURN and _flat_to(home)<.55:
		state=State.IDLE
		_roam=home
		_roam_t=1.4
		_scan_t=1.25 # finish the retreat before considering a new target
	_animate(delta)

func _face(direction: Vector3, delta: float) -> void:
	if direction.length_squared()<.001: return
	visual.rotation.y=lerp_angle(visual.rotation.y,atan2(direction.x,direction.z),minf(1.0,delta*9.0))

func _animate(delta: float) -> void:
	_phase+=delta
	var walking:=velocity.length()>.1
	var gait:=_phase*(10.0 if walking else 2.0)
	visual.position.y=(1.25+sin(_phase*2.8)*.12) if flying else absf(sin(gait))*(.045 if walking else .012)
	body.rotation.z=sin(gait)*.025
	for leg in _legs:
		var side: float=leg.get_meta("side")
		var front: bool=leg.get_meta("front")
		var wave:=sin(gait+(PI if front==(side<0) else 0.0))
		leg.rotation.x=-.35 if flying else wave*(.35 if walking else .02)
		leg.rotation.z=side*(.22 if flying else maxf(0.0,wave)*.13)
	for wing in _wings:
		var side: float=wing.get_meta("side")
		var front: bool=wing.get_meta("front")
		wing.rotation.z=side*((.22+sin(_phase*34.0+(0 if front else .8))*.46) if flying else (.13+sin(_phase*3.2)*.07))
		wing.rotation.y=side*(0.0 if front else .05)
	_lunge=maxf(0.0,_lunge-delta)
	body.position.z=sin(_lunge/.32*PI)*.24
	body.rotation.x=0.0
	body.scale=Vector3.ONE
	if _hurt_t>=0.0:
		# 피격 반동: 머리를 쳐들며 뒤로 튕기고 몸이 눌렸다 출렁, 날개가 확 펼쳐진다
		_hurt_t+=delta
		var t:=_hurt_t
		var snap:=minf(t/.04,1.0)
		var recoil:=snap*exp(-maxf(t-.04,0.0)*9.0)*cos(maxf(t-.04,0.0)*24.0)
		body.rotation.x=-.42*recoil
		body.position.z+=-.2*recoil
		body.rotation.z+=sin(t*60.0)*.12*exp(-t*10.0)
		var squash:=snap*exp(-maxf(t-.04,0.0)*14.0)
		body.scale=Vector3(1.0+.14*squash,1.0-.18*squash,1.0+.14*squash)
		for wing in _wings:
			wing.rotation.z+=float(wing.get_meta("side"))*.6*squash
		if t>=.42: _hurt_t=-1.0

func apply_slow(source: String, factor: float, duration: float) -> void:
	if not dead: _slows[source]=[clampf(factor,.05,1.0),duration]
	_sync_frost_mark()

func slow_factor() -> float:
	var factor:=1.0
	for key in _slows: factor=minf(factor,float(_slows[key][0]))
	return factor

func _tick_slows(delta: float) -> void:
	if _slows.is_empty(): return   # 마지막 둔화가 끝난 프레임에 아래 _sync_frost_mark 가 이미 표시를 껐다
	for key in _slows.keys():
		_slows[key][1]-=delta
		if _slows[key][1]<=0.0: _slows.erase(key)
	_sync_frost_mark()

## Slowed: frost rime spreads under the body, melts away when it ends (display only).
func _sync_frost_mark() -> void:
	var on:=not _slows.is_empty() and not dead
	if on and _frost_mark==null: _frost_mark=FrostVfx.slow_mark(self)
	if _frost_mark!=null: FrostVfx.set_slow_mark(_frost_mark,on)

func take_damage(amount: float) -> void:
	if dead or amount<=0.0: return
	hp=maxf(0.0,hp-amount)
	var dir: Vector3=global_position-game.player.global_position
	dir.y=0.0
	Venom.spray(game.world,global_position+Vector3(0,aim_height,0),dir.normalized(),hp<=0.0)
	Fx.flash(visual)
	Fx.damage_number(get_parent(),global_position+Vector3(0,hp_offset,0),amount,Color(.65,1.0,.3))
	Sfx.play(self, "insect_hit")
	if hp>0.0: _hurt_t=0.0  # 피격 반동(_animate)
	if hp<=0.0:
		die()
	elif state!=State.RETURN:
		var attacker=_find_target()
		if attacker!=null:
			target=attacker
			state=State.CHASE
			_repath_t=0.0

func die() -> void:
	if dead: return
	dead=true
	hp=0.0
	state=State.DEAD
	target=null
	velocity=Vector3.ZERO
	collision_mask=0
	remove_from_group("enemies")
	remove_from_group("hazard_insects")
	remove_from_group("show_hp")
	# 처치 골드(scripts/game/kill_gold.gd)
	if game.get("kill_gold") != null:
		game.kill_gold.on_enemy_killed(self)
	# A flyer falls before its curled corpse settles into the ichor.
	var tw:=create_tween().set_parallel(true)
	tw.tween_property(visual,"position:y",.06,.48).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(body,"rotation:z",1.65,.5)
	for leg in _legs: tw.tween_property(leg,"rotation:x",-1.15,.42)
	for wing in _wings: tw.tween_property(wing,"rotation:z",float(wing.get_meta("side"))*.65,.42)
	tw.chain().tween_interval(12.0)
	tw.chain().tween_property(visual,"scale",Vector3.ZERO,2.0)
	tw.chain().tween_callback(queue_free)
