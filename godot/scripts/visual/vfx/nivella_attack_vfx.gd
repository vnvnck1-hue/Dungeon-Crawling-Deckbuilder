extends Node3D
## 니벨라 공격 패턴 연출(표시 전용). 판정은 scripts/actors/nivella_boss.gd 가 하고, 여기서는 보이는 것만 만든다.
##  - 예고 장판(원·줄): nv_telegraph.gdshader 가 duration 동안 안쪽부터 차올라 다 차는 순간 공격이 떨어진다.
##  - 얼음 가시: 바닥에서 수정 송곳이 솟았다가 부서진다.
##  - 거미줄 덩이: 포물선으로 날아가 떨어지고, 떨어진 자리에 얼어붙은 거미줄이 잠깐 남는다.
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Kit := preload("res://scripts/visual/boss_room_kit.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const TELEGRAPH := preload("res://shaders/vfx/nivella/nv_telegraph.gdshader")

enum Kind { TELEGRAPH, SPIKE, GLOB, WEB }

var kind := Kind.TELEGRAPH
var duration := 1.0
var _t := 0.0
var _mat: ShaderMaterial
var _spike: Node3D
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _arc := 3.0
var _on_land: Callable
var _web: MeshInstance3D


static func _spawn(parent: Node, k: Kind, life: float) -> Node3D:
	var v := new()
	v.kind = k
	v.duration = life
	v.name = "NivellaAttack%s" % Kind.keys()[k].capitalize()
	parent.add_child(v)
	return v


static func _telegraph_mat(shape: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = TELEGRAPH
	m.set_shader_parameter("shape", shape)
	m.render_priority = 1
	return m


## 원형 예고: pos 중심 반경 radius, duration 초 동안 차오른다.
static func telegraph_circle(parent: Node, pos: Vector3, radius: float, life: float) -> Node3D:
	var v := _spawn(parent, Kind.TELEGRAPH, life)
	v.global_position = Vector3(pos.x, 0.06, pos.z)
	v._mat = _telegraph_mat(0)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	var m := B.mi(v, plane, Vector3.ZERO, v._mat)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return v


## 줄 예고: from 에서 dir 쪽으로 length 만큼, 폭 width. 보스 쪽부터 끝으로 차오른다.
static func telegraph_line(parent: Node, from: Vector3, dir: Vector3, length: float, width: float, life: float) -> Node3D:
	var v := _spawn(parent, Kind.TELEGRAPH, life)
	dir.y = 0.0
	dir = dir.normalized()
	v.global_position = Vector3(from.x, 0.07, from.z) + dir * length * 0.5
	v.rotation.y = atan2(dir.x, dir.z)
	v._mat = _telegraph_mat(1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(width, length)
	# PlaneMesh 의 UV.y 는 -Z 쪽이 0: 뒤집어 보스 쪽(-Z)이 0, 끝(+Z)이 1 이 되게 한다(로컬 +Z = dir)
	var m := B.mi(v, plane, Vector3.ZERO, v._mat)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return v


## 얼음 가시: 바닥에서 솟구쳐 잠깐 버티다 부서진다.
static func ice_spike(parent: Node, pos: Vector3, size := 1.0) -> Node3D:
	var v := _spawn(parent, Kind.SPIKE, 0.9)
	v.global_position = Vector3(pos.x, 0.0, pos.z)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	v._spike = B.node(v, Vector3.ZERO, Vector3(0, rng.randf() * 360.0, 0), "Spikes")
	Kit.crystal_shaft(v._spike, Vector3.ZERO, 2.2 * size, 0.32 * size, Vector3(rng.randf_range(-8, 8), 0, rng.randf_range(-8, 8)))
	for i in 3:
		var a := TAU * i / 3.0 + rng.randf()
		Kit.crystal_shaft(v._spike, Vector3(cos(a), 0, sin(a)) * 0.35 * size, rng.randf_range(0.9, 1.4) * size, 0.16 * size,
			Vector3(28.0 * sin(a), 0, -28.0 * cos(a)), true)
	v._spike.scale = Vector3(1, 0.01, 1)
	Fx.snow_kick(v.global_position + Vector3(0, 0.05, 0), Vector3.UP, 3, 1.6 * size)
	return v


## 거미줄 덩이: from → to 포물선 flight 초. 떨어지면 on_land(착지점) 를 부른다.
static func web_glob(parent: Node, from: Vector3, to: Vector3, flight: float, on_land: Callable) -> Node3D:
	var v := _spawn(parent, Kind.GLOB, flight)
	v._from = from
	v._to = Vector3(to.x, 0.2, to.z)
	v._arc = 2.5 + from.distance_to(to) * 0.18
	v._on_land = on_land
	v.global_position = from
	var ball := B.sphere(v, 0.42, Vector3.ZERO, Mats.solid(Color("e8f0ff"), {"emission_color": Color("9fc0ff"), "emission_energy": 0.5, "rim_strength": .8}), Vector3.ONE, 10, 6)
	ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return v


## 바닥에 얼어붙은 거미줄(life 초 동안 남았다가 녹는다). 판정(둔화)은 보스 모듈이 같은 자리·반경으로 한다.
static func web_patch(parent: Node, pos: Vector3, radius: float, life: float) -> Node3D:
	var v := _spawn(parent, Kind.WEB, life)
	v.global_position = Vector3(pos.x, 0.08, pos.z)
	var anchors: Array[Vector3] = []
	var rot := randf() * TAU
	for i in 5:
		var a := rot + TAU * i / 5.0
		anchors.append(Vector3(cos(a), 0.0, sin(a)) * radius)
	v._web = Kit.frozen_web(anchors, 3, 0.05)
	v.add_child(v._web)
	return v


func _process(delta: float) -> void:
	_t += delta
	var u := clampf(_t / maxf(duration, 0.01), 0.0, 1.0)
	match kind:
		Kind.TELEGRAPH:
			_mat.set_shader_parameter("fill", u)
			_mat.set_shader_parameter("alpha", minf(_t / 0.12, 1.0))
		Kind.SPIKE:
			# 0.08초에 솟고, 0.55초 버티다, 끝에 주저앉으며 부서진다
			var up := minf(_t / 0.08, 1.0)
			var down := smoothstep(0.6, 0.9, _t)
			_spike.scale = Vector3(1.0 + down * 0.3, maxf(up * (1.0 - down), 0.01), 1.0 + down * 0.3)
			if _t >= 0.6 and not has_meta("shattered"):
				set_meta("shattered", true)
				Fx.burst(get_parent(), global_position + Vector3(0, 0.8, 0), Color(0.78, 0.86, 1.0), 10, 3.0)
		Kind.GLOB:
			var p := _from.lerp(_to, u)
			p.y += sin(u * PI) * _arc
			global_position = p
			rotation.y += delta * 6.0
		Kind.WEB:
			var fade := 1.0 - smoothstep(duration - 0.6, duration, _t)
			_web.transparency = 1.0 - fade
			_web.scale = Vector3.ONE * (0.6 + 0.4 * minf(_t / 0.15, 1.0))
	if _t >= duration:
		if kind == Kind.GLOB and _on_land.is_valid():
			_on_land.call(_to)
		queue_free()
