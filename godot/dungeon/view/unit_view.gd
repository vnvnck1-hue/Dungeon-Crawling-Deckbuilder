extends Node3D
## 전장의 유닛 하나(아군 영웅 또는 적)의 3D 표현. 판정은 core/battle.gd, 이 노드는 모양·애니메이션만.
## 모델·애니메이션은 마녀산장 그대로: CharacterModels(Tripo 파츠 묶음) + RigAnim(걷기·베기·활 당기기·시전·움찔),
## 소품(검·방패·활·화살통)은 용병 ally.gd 의 조립을 따랐다. 캐릭터 가독성(림·외곽선)·적 강조 외곽선도 같은 모듈.

const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const CharacterModels := preload("res://scripts/visual/character_models.gd")
const Readability := preload("res://scripts/visual/character_readability.gd")
const EnemyOutline := preload("res://scripts/visual/enemy_outline.gd")
const D := preload("res://dungeon/data/defs.gd")
const StatusFx := preload("res://dungeon/view/status_fx.gd")

signal arrived

## 쿼터뷰 전장에서 읽히도록 마녀산장 크기보다 조금 키운다
const UNIT_SCALE := 1.2

var unit_id := 0
var kind := ""
var team := "ally"
var visual: Node3D            # EnemyOutline·Readability 가 읽는 이름
var jolt: Node3D              # visual 의 부모. 맞았을 때 밀려났다 돌아오는 넉백 오프셋(이동·돌진 트윈과 겹치지 않게 따로 둔다)
var body: Node3D
var rig: Node
var model: Node3D
var hp_offset := 1.9          # 체력 막대를 띄울 높이(m)
var tip: Node3D               # 마법사 지팡이 끝 / 궁수 활 / 전사 검
var hand_r: Node3D
var hand_l: Node3D
var facing := Vector3.ZERO    # 서서 바라보는 방향(진영)
var _route: Array = []
var _speed := 3.4
var _walking := false
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _taunt_ring: MeshInstance3D
var status_fx: Node3D            # 쌓이는 상태(표식·냉기·화상·빙결·투지) 3D 표시. view/status_fx.gd
var _cast_t := -1.0
var _dead := false
var _hover := false
var _walk_style: Dictionary = {}   # 뛰기 전 걸음 값(되돌릴 때)
var _running := false
var _stride := 0.0
var _foot_side := 1.0
var _breath_t := randf_range(0.5, 2.0)
var _mouth: Node3D
var breath                         # forest_world.breath(BreathVapor). main 이 넣는다
var weather                        # forest_world.weather(바람)


func setup(kind_: String, team_: String, id: int, face_dir: Vector3) -> void:
	kind = kind_
	team = team_
	unit_id = id
	facing = face_dir
	var def: Dictionary = D.HEROES.get(kind, {}) if team == "ally" else D.ENEMIES.get(kind, {})
	var model_id := String(def.get("model", "human_common"))
	var made: Dictionary
	if model_id == "witch_north":
		made = CharacterModels.make_player_witch()
		tip = made.get("tip")
		hand_r = made.get("hand_r")
	else:
		made = CharacterModels.make(model_id)
	visual = made.root
	body = made.body
	rig = made.anim
	model = body.get_child(0)
	jolt = Node3D.new()
	jolt.name = "Jolt"
	add_child(jolt)
	jolt.add_child(visual)
	visual.scale = Vector3.ONE * base_scale()
	hp_offset = float(def.get("hp_h", 1.75 * visual.scale.x * (1.12 if model_id == "orc_common" else 1.0) + 0.15))
	for n in visual.find_children("Mouth", "Node3D", true, false):
		_mouth = n
	_add_props(String(def.get("props", "")))
	# 발밑 진영 고리: 아군 = 따뜻한 금빛, 적 = 붉은빛
	var ring_col := Color(1.0, 0.82, 0.45, 0.75) if team == "ally" else Color(1.0, 0.3, 0.35, 0.7)
	_ring_mat = Mats.unshaded(ring_col, true, true)
	_ring = B.torus(self, 0.42, 0.54, Vector3(0, 0.05, 0), _ring_mat)
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ring.scale = Vector3(1.0, 0.15, 1.0)
	add_to_group("readable_characters")
	Readability.apply(self, "rim_shadow")
	status_fx = StatusFx.new()
	status_fx.name = "StatusFx"
	add_child(status_fx)
	status_fx.setup(self)
	face(facing, true)


## 손에 쥔 소품(마녀산장 ally._add_held_props 의 조립을 그대로).
## 마법사(마녀 모델)는 플레이어처럼 1.3배(마녀산장 player.gd 기준), 적은 데이터의 scale.
func base_scale() -> float:
	var def: Dictionary = D.HEROES.get(kind, {}) if team == "ally" else D.ENEMIES.get(kind, {})
	var s := 1.3 if String(def.get("model", "")) == "witch_north" else float(def.get("scale", 1.0))
	return s * UNIT_SCALE


func _add_props(kind_props: String) -> void:
	if model == null:
		return
	if hand_r == null:
		hand_r = CharacterModels._hand(model, "arm_r")
	hand_l = CharacterModels._hand(model, "arm_l")
	var torso: Node3D = null
	for n in model.find_children("*", "Node3D", true, false):
		if str(n.get_meta("part_group", "")) == "torso":
			torso = n
	if hand_r == null or hand_l == null or torso == null:
		return
	var inv := Vector3.ONE / model.scale.x
	var back_box: AABB = (torso.get_node("Mesh") as MeshInstance3D).mesh.get_aabb()
	var back := Vector3(0, back_box.get_center().y + back_box.size.y * 0.1, back_box.position.z)
	match kind_props:
		"warrior":
			var sword := B.node(hand_r, Vector3.ZERO, Vector3(105, 0, 0), "Sword")
			sword.scale = inv
			B.cyl(sword, 0.018, 0.02, 0.14, Vector3(0, 0.0, 0), Mats.solid(Color("5c3a22")), 6)
			B.box(sword, Vector3(0.16, 0.03, 0.035), Vector3(0, 0.08, 0), Mats.solid(Color("8e8a80")))
			B.box(sword, Vector3(0.06, 0.44, 0.016), Vector3(0, 0.31, 0), Mats.solid(Color("c8ccd8")))
			var shield := B.node(hand_l, Vector3(0.05, 0.12, 0.0) / model.scale.x, Vector3(0, 0, 0), "Shield")
			shield.scale = inv
			B.cyl(shield, 0.2, 0.2, 0.035, Vector3.ZERO, Mats.solid(Color("7b4a2e")), 12, Vector3(0, 0, 90))
			B.sphere(shield, 0.05, Vector3(0.03, 0, 0), Mats.solid(Color("aeb4c4")), Vector3(0.5, 1, 1), 8, 4)
			rig.props["sword"] = sword
			rig.props["shield"] = shield
			tip = B.node(sword, Vector3(0, 0.45, 0), Vector3.ZERO, "Tip")
		"archer":
			var bow := B.node(hand_l, Vector3(0, 0, 0.02), Vector3.ZERO, "Bow")
			bow.scale = inv
			var wood := Mats.solid(Color("7a4f2a"))
			for seg in [[Vector3(0, 0.24, 0.05), Vector3(28, 0, 0)], [Vector3(0, 0, 0.1), Vector3(0, 0, 0)], [Vector3(0, -0.24, 0.05), Vector3(-28, 0, 0)]]:
				B.cyl(bow, 0.016, 0.02, 0.26, seg[0], wood, 6, seg[1])
			var string := B.node(bow, Vector3(0, 0, -0.01), Vector3.ZERO, "BowString")
			string.set_meta("rest_z", -0.01)
			string.set_meta("pull", 0.2)
			B.box(string, Vector3(0.006, 0.62, 0.006), Vector3.ZERO, Mats.solid(Color("e8e2d0")))
			var arrow := B.node(bow, Vector3(0, 0, -0.12), Vector3(90, 0, 0), "Arrow")
			B.cyl(arrow, 0.007, 0.007, 0.6, Vector3(0, 0.12, 0), Mats.solid(Color("d8d2c0")), 4)
			B.cyl(arrow, 0.0, 0.02, 0.06, Vector3(0, 0.44, 0), Mats.solid(Color("8e939e")), 4)
			arrow.visible = false
			var quiver := B.node(torso, back + Vector3(0.06, 0.02, -0.03), Vector3(15, 0, 20), "Quiver")
			quiver.scale = inv
			B.cyl(quiver, 0.05, 0.06, 0.34, Vector3.ZERO, Mats.solid(Color("5c3a22")), 8)
			for i in 3:
				B.cyl(quiver, 0.006, 0.006, 0.22, Vector3(-0.02 + 0.02 * i, 0.26, 0.015 * (i - 1)), Mats.solid(Color("d8d2c0")), 4)
			rig.props["bow"] = bow
			rig.props["bow_string"] = string
			rig.props["arrow"] = arrow
			tip = bow
		"club":
			var club := B.node(hand_r, Vector3.ZERO, Vector3(150, 0, 0), "Club")
			club.scale = inv
			B.cyl(club, 0.03, 0.06, 0.5, Vector3(0, 0.22, 0), Mats.solid(Color("6b4a2c")), 7)
			B.sphere(club, 0.08, Vector3(0, 0.46, 0), Mats.solid(Color("5a3b22")), Vector3.ONE, 8, 5)
			tip = club
		"bone":
			var bone := B.node(hand_r, Vector3.ZERO, Vector3(120, 0, 0), "Bone")
			bone.scale = inv
			B.cyl(bone, 0.025, 0.025, 0.3, Vector3(0, 0.14, 0), Mats.solid(Color("e6dcc4")), 6)
			B.sphere(bone, 0.045, Vector3(0, 0.3, 0), Mats.solid(Color("e6dcc4")), Vector3(1.4, 1, 1), 6, 4)
			var pouch := B.node(torso, back + Vector3(0, 0, -0.04), Vector3(-8, 0, 0), "Pouch")
			pouch.scale = inv
			B.sphere(pouch, 0.13, Vector3.ZERO, Mats.solid(Color("7b5a3a")), Vector3(1, 1.1, 0.8), 8, 5)
			tip = bone
		"axe":
			var axe := B.node(hand_r, Vector3.ZERO, Vector3(155, 0, 0), "Axe")
			axe.scale = inv
			B.cyl(axe, 0.025, 0.03, 0.66, Vector3(0, 0.24, 0), Mats.solid(Color("6b4a2c")), 6)
			B.box(axe, Vector3(0.05, 0.2, 0.26), Vector3(0, 0.5, 0.09), Mats.solid(Color("aeb4c4")))
			B.box(axe, Vector3(0.055, 0.04, 0.05), Vector3(0, 0.5, -0.03), Mats.solid(Color("4a4e58")))
			rig.props["axe"] = axe
			tip = axe


func face(dir: Vector3, instant := false) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	var yaw := atan2(dir.x, dir.z)
	if instant:
		visual.rotation.y = yaw
	else:
		var tw := create_tween()
		tw.tween_property(visual, "rotation:y", visual.rotation.y + wrapf(yaw - visual.rotation.y, -PI, PI), 0.18)


## 뛰기: 마녀산장 RigAnim 걸음 값을 키워(빠른 보폭·큰 팔 흔들기·앞으로 숙임) 달리는 자세로 경로를 따라간다.
func run(route: Array, speed := 9.0) -> void:
	_set_run(true)
	walk(route, speed)
	arrived.connect(func() -> void: _set_run(false), CONNECT_ONE_SHOT)


func _set_run(on: bool) -> void:
	if rig == null:
		return
	if on and not _running:
		_running = true
		_walk_style = rig.style
		var st: Dictionary = rig.style.duplicate()
		st["walk_freq"] = float(st.get("walk_freq", 9.0)) * 1.85
		st["leg_swing"] = float(st.get("leg_swing", 30.0)) * 1.5
		st["arm_swing"] = float(st.get("arm_swing", 24.0)) * 1.8
		st["staff_arm_swing"] = float(st.get("staff_arm_swing", st.get("arm_swing", 24.0))) * 1.6
		st["walk_lean"] = float(st.get("walk_lean", 6.0)) + 14.0
		st["walk_bounce"] = maxf(float(st.get("walk_bounce", 0.045)), 0.03) * 1.7
		rig.style = st
	elif not on and _running:
		_running = false
		rig.style = _walk_style


## 대상 쪽으로 순식간에 내달린다(돌진 공격). to 까지 time 초.
func dash(to: Vector3, time := 0.2) -> void:
	face(to - global_position)
	_set_run(true)
	rig.play("walk")
	Fx.snow_kick(global_position, (global_position - to).normalized(), 3, 1.0)
	var tw := create_tween()
	tw.tween_property(self, "global_position", Vector3(to.x, global_position.y, to.z), time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	await tw.finished
	_set_run(false)
	rig.play("idle")


## 경로(세계 좌표 목록)를 따라 걷는다. 다 오면 arrived.
func walk(route: Array, speed := 3.4) -> void:
	_route = route.duplicate()
	_speed = speed
	_walking = not _route.is_empty()
	if _walking:
		rig.play("walk")
	else:
		arrived.emit()


func is_walking() -> bool:
	return _walking


func _process(delta: float) -> void:
	if _walking:
		var target: Vector3 = _route[0]
		var to := target - global_position
		to.y = 0.0
		var step := _speed * delta
		if to.length() <= step:
			global_position = Vector3(target.x, global_position.y, target.z)
			_route.pop_front()
			if _route.is_empty():
				_walking = false
				rig.play("idle")
				face(facing)
				arrived.emit()
		else:
			global_position += to.normalized() * step
			visual.rotation.y = lerp_angle(visual.rotation.y, atan2(to.x, to.z), clampf(delta * 10.0, 0.0, 1.0))
			# 눈 위 발자국 + 걸음마다 튀는 눈(마녀산장 actor_vfx 와 같은 Fx)
			_stride += step
			if _stride >= 0.55:
				_stride = 0.0
				_foot_side = -_foot_side
				var side := to.normalized().cross(Vector3.UP) * 0.13 * _foot_side
				Fx.footprint(global_position + side, atan2(to.x, to.z), 0.32, Fx.C_PRINT, 5.0)
				Fx.snow_kick(global_position, -to.normalized(), 2 if _speed > 6.0 else 1, 0.7)
	# 차가운 공기 속 입김
	_breath_t -= delta
	if _breath_t <= 0.0 and not _dead:
		_breath_t = randf_range(1.4, 2.2)
		var fwd := visual.global_basis.z
		var mouth: Vector3 = _mouth.global_position if _mouth != null else chest() + Vector3(0, hp_offset * 0.3, 0) + fwd * 0.25
		var wind: Vector3 = weather.wind_vector() if weather != null else Vector3.ZERO
		var col := Color(1, 1, 1, 0.6) if team == "ally" else Color(0.62, 0.42, 0.85, 0.55)
		if breath != null and breath.is_ready():
			breath.exhale(mouth, fwd + wind * 0.4, col, 1.0)
		else:
			Fx.breath(mouth, fwd + wind * 0.4, col, 1.0)
	if _cast_t >= 0.0:
		_cast_t += delta
		rig.amount = clampf(_cast_t / 0.32, 0.0, 1.0)
	if _taunt_ring != null and _taunt_ring.visible:
		var k := 1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.008)
		_taunt_ring.scale = Vector3(k, 0.15, k)


## 공격 동작 시작. 임팩트(투사체 발사·타격)까지 걸리는 시간(초)을 돌려준다.
## style: slash(베기) · draw(활) · cast(지팡이) · stab(들이받기) · throw(던지기)
func attack(style: String, toward: Vector3) -> float:
	face(toward - global_position)
	match style:
		"cast":
			rig.play("windup")
			_cast_t = 0.0
			get_tree().create_timer(0.34).timeout.connect(func() -> void:
				_cast_t = -1.0
				rig.play("cast")
				get_tree().create_timer(0.45).timeout.connect(func() -> void:
					if not _walking and rig.state == "cast":
						rig.play("idle")))
			return 0.36
		"throw":
			return rig.action("slash")
		_:
			return rig.action(style)


## 피격 타격감. strength: 0.6(약한 피해) ~ 1.6(큰 피해·처치). from: 때린 쪽 위치(그 반대로 밀려난다, INF 면 뒤로).
## 움찔(RigAnim flinch) + 자세 얼림(히트스탑) + 하얗게 번쩍(hit_flash 셰이더) + 납작 스쿼시(Fx.flash) + 넉백·튕김.
## 화면 흔들림·전체 시간 멈춤은 main.gd 가 같이 건다.
func hurt(strength := 1.0, from := Vector3.INF) -> void:
	rig.flinch()
	rig.freeze(0.05 + 0.05 * strength)
	Fx.flash(visual, 1.0 + 0.8 * strength)
	# 넉백: 때린 쪽 반대로 밀려났다가 스프링처럼 돌아온다. 큰 피해는 살짝 떠오른다.
	var away: Vector3 = (global_position - from) if from.is_finite() else -facing
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else -facing
	var push: float = 0.22 + 0.2 * strength
	var hop: float = 0.1 * maxf(strength - 0.9, 0.0)
	var tw := create_tween()
	tw.tween_property(jolt, "position", away * push + Vector3(0, hop, 0), 0.05).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(jolt, "position", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	# 발밑 눈가루
	Fx.snow_kick(global_position, -away, 2 if strength < 1.2 else 4, 0.8 + 0.4 * strength)


func die() -> void:
	if _dead:
		return
	_dead = true
	_ring.visible = false
	set_status("taunt", false)
	status_fx.clear()
	Fx.flash(visual, 1.4)
	var tw := create_tween()
	tw.tween_property(visual, "rotation:x", -PI * 0.5, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(visual, "position:y", -0.1, 0.45)
	tw.tween_interval(0.35)
	if team == "enemy":
		tw.tween_callback(func() -> void: Fx.vanish(visual, Color(0.35, 0.28, 0.6, 0.8), 0.45))
		tw.tween_interval(0.6)
		tw.tween_callback(queue_free)
	else:
		tw.tween_callback(func() -> void: Fx.poof(chest(), Color(0.6, 0.55, 0.8), 0.6))


## 쓰러진 아군이 다음 방에서 일어난다.
func revive() -> void:
	_dead = false
	_ring.visible = true
	visual.rotation.x = 0.0
	visual.position.y = 0.0
	jolt.position = Vector3.ZERO
	visual.visible = true
	visual.scale = Vector3.ONE * base_scale()
	Fx.summon(global_position, Color(1.0, 0.82, 0.45))


func is_dead() -> bool:
	return _dead


## 상태 표시. mark · chill · burn · fury 는 쌓인 수, freeze · taunt 는 1/0. delta > 0 이면 막 걸린 순간의 연출을 같이 낸다.
## 쌓이는 상태는 status_fx(몸 껍질·발밑·주변 입자), 도발은 발밑 주황 고리.
func set_stack(status: String, value: int, delta := 0) -> void:
	if status == "taunt":
		set_status("taunt", value > 0)
	else:
		status_fx.set_value(status, value, delta)


## 켜고 끄기(예전 호출 호환): taunt 는 고리, 나머지는 set_stack.
func set_status(status: String, on: bool) -> void:
	if status != "taunt":
		set_stack(status, 1 if on else 0)
		return
	if _taunt_ring == null:
		if not on:
			return
		_taunt_ring = B.torus(self, 0.62, 0.74, Vector3(0, 0.07, 0), Mats.unshaded(Color(1.0, 0.6, 0.2, 0.8), true, true))
		_taunt_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_taunt_ring.visible = on


## 마우스 강조(적: 마녀산장 롤식 붉은 외곽선, 아군: 금빛 고리 밝게).
func set_hover(on: bool, targeted := false) -> void:
	_hover = on
	if team == "enemy":
		EnemyOutline.apply(self, (EnemyOutline.TARGET if targeted else EnemyOutline.HOVER) if on else EnemyOutline.NONE)
	else:
		_ring_mat.albedo_color.a = 1.0 if on else 0.75
		_ring.scale = Vector3(1.25, 0.15, 1.25) if on else Vector3(1.0, 0.15, 1.0)


## 행동을 마친(행동력 0) 아군은 발밑 고리가 흐려진다.
func set_spent(spent: bool) -> void:
	if team == "ally" and not _hover:
		_ring_mat.albedo_color.a = 0.25 if spent else 0.75


func chest() -> Vector3:
	return global_position + Vector3(0, hp_offset * 0.55, 0)


func tip_pos() -> Vector3:
	return tip.global_position if tip != null and is_instance_valid(tip) else chest()
