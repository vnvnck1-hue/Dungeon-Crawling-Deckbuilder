extends Node3D
## 니벨라 포효 눈보라 폭발. 보스 발밑에서 휘몰아친 눈 띠가 고리로 밀려 나가고(바닥 VisualShader),
## 고리를 따라 눈보라 벽이 솟았다 흩어지며(원통 VisualShader), 얼음 파편·눈뭉치가 바깥으로 튄다.
## 그래프: shaders/vfx/nivella/*.tres (tools/build_nivella_roar_shaders.gd 로 다시 만든다).
## 강도: 사용자 요청(2026-10-22) "참고 이미지보다 약하게" — 화면 전체를 덮지 않고 보스 둘레에서 1.8초 안에 걷힌다.
const Mats := preload("res://scripts/visual/mats.gd")
const Web := preload("res://scripts/visual/vfx/nivella_web.gd")
const SH_GROUND := preload("res://shaders/vfx/nivella/nv_roar_ground_burst.tres")
const SH_WALL := preload("res://shaders/vfx/nivella/nv_roar_snow_wall.tres")

## 퍼지는 시간·수명은 burst() 의 spread 로 정한다(멀리 퍼지는 첫 포효는 더 길게).
var spread_time := 0.95      # 눈 띠가 끝까지 퍼지는 시간
var life := 1.8              # 전체 수명(초) = 퍼짐 + 흩어짐
var fade_from := 0.55        # 이때부터 흩어지기 시작

var radius := 14.0
var intensity := 0.8
var ground_mat: ShaderMaterial
var wall_mat: ShaderMaterial
var wall: MeshInstance3D
var progress := 0.0          # 검증용
var fade := 1.0
var _t := 0.0


## pos 는 바닥 높이의 보스 위치. radius = 눈 띠가 멈추는 반경(m).
static func burst(parent: Node, pos: Vector3, burst_radius := 14.0, strength := 0.8, spread := 0.95) -> Node3D:
	var v := new()
	v.name = "NivellaRoarBlizzard"
	v.radius = burst_radius
	v.intensity = strength
	v.spread_time = spread
	# 멀리 퍼지는 눈보라(첫 포효)는 화면 끝에 닿을 때까지 짙게 남았다가 흩어진다
	var far := burst_radius > 20.0
	v.life = spread + (0.75 if far else 0.85)
	v.fade_from = spread * (0.9 if far else 0.58)
	parent.add_child(v)
	v.global_position = Vector3(pos.x, pos.y, pos.z)
	v._build()
	# 둥지의 서리 거미줄이 이 충격파에 출렁인다(멀리·세게 퍼질수록 크게)
	Web.shock(pos, strength * clampf(burst_radius / 14.0, 0.45, 1.3))
	return v


func _build() -> void:
	var noise_seed := randf() * 10.0
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = SH_GROUND
	ground_mat.render_priority = 2
	ground_mat.set_shader_parameter("seed", noise_seed)
	ground_mat.set_shader_parameter("intensity", intensity)
	if radius > 20.0:
		# 멀리 퍼지는 연속 눈보라: 얇고 또렷한 고리, 안쪽 안개는 옅게
		ground_mat.set_shader_parameter("band_width", 0.68)
		ground_mat.set_shader_parameter("haze", 0.2)
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * radius * 2.0
	var g := MeshInstance3D.new()
	g.name = "GroundBurst"
	g.mesh = plane
	g.material_override = ground_mat
	g.position.y = 0.14
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)
	wall_mat = ShaderMaterial.new()
	wall_mat.shader = SH_WALL
	wall_mat.render_priority = 3
	wall_mat.set_shader_parameter("seed", noise_seed + 3.0)
	wall_mat.set_shader_parameter("intensity", intensity)
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.0
	cyl.bottom_radius = 1.0
	cyl.height = 1.0
	cyl.radial_segments = 64
	cyl.rings = 1
	cyl.cap_top = false
	cyl.cap_bottom = false
	wall = MeshInstance3D.new()
	wall.name = "SnowWall"
	wall.mesh = cyl
	wall.material_override = wall_mat
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	_debris()
	_step()


## 얼음 파편과 눈뭉치: 한 번에 바깥으로 튀어 나간다(수평 원반으로 퍼짐).
func _debris() -> void:
	var shards := CPUParticles3D.new()
	shards.name = "IceShards"
	shards.one_shot = true
	shards.explosiveness = 0.95
	shards.amount = int(28 * intensity)
	shards.lifetime = 1.3
	shards.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	shards.emission_sphere_radius = radius * 0.12
	shards.direction = Vector3(1, 0.45, 0)
	shards.spread = 180.0
	shards.flatness = 0.75
	shards.initial_velocity_min = radius * 0.55
	shards.initial_velocity_max = radius * 0.95
	shards.gravity = Vector3(0, -16, 0)
	shards.damping_min = 2.0
	shards.damping_max = 4.0
	shards.angular_velocity_min = -360
	shards.angular_velocity_max = 360
	shards.scale_amount_min = 0.6
	shards.scale_amount_max = 1.5
	var prism := PrismMesh.new()
	prism.size = Vector3(0.45, 0.85, 0.3)
	prism.material = Mats.solid(Color("c6d4ff"), {"emission_color": Color("7f9cff"), "emission_energy": .5, "rim_strength": .8})
	shards.mesh = prism
	shards.position.y = 0.6
	add_child(shards)
	shards.emitting = true
	var puffs := CPUParticles3D.new()
	puffs.name = "SnowPuffs"
	puffs.one_shot = true
	puffs.explosiveness = 0.9
	puffs.amount = int(46 * intensity)
	puffs.lifetime = 1.5
	puffs.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	puffs.emission_sphere_radius = radius * 0.1
	puffs.direction = Vector3(1, 0.15, 0)
	puffs.spread = 180.0
	puffs.flatness = 0.9
	puffs.initial_velocity_min = radius * 0.6
	puffs.initial_velocity_max = radius * 1.05
	puffs.damping_min = radius * 0.25
	puffs.damping_max = radius * 0.4
	puffs.gravity = Vector3(0, 0.3, 0)
	puffs.scale_amount_min = 1.8
	puffs.scale_amount_max = 3.6
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.0))
	ramp.add_point(0.12, Color(1, 1, 1, 0.75))
	ramp.add_point(0.55, Color(1, 1, 1, 0.45))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	puffs.color_ramp = ramp
	puffs.color = Color(0.92, 0.95, 1.0, 0.7)
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	quad.material = Mats.particle(Color.WHITE)
	puffs.mesh = quad
	puffs.position.y = 0.5
	add_child(puffs)
	puffs.emitting = true


func _process(delta: float) -> void:
	_t += delta
	_step()
	if _t >= life:
		queue_free()


func _step() -> void:
	var u := clampf(_t / spread_time, 0.0, 1.0)
	progress = 1.0 - pow(1.0 - u, 2.2)
	fade = 1.0 - smoothstep(fade_from, life, _t)
	ground_mat.set_shader_parameter("progress", progress)
	ground_mat.set_shader_parameter("fade", fade)
	# 벽은 바닥 띠 앞머리(반경의 93%)를 따라가며 솟았다가 먼저 흩어진다
	var front := lerpf(0.06, 0.93, progress) * radius
	var h := lerpf(1.6, 5.2, progress) * (0.6 + intensity * 0.5)
	wall.scale = Vector3(front, h, front)
	wall.position.y = h * 0.5
	wall_mat.set_shader_parameter("progress", progress)
	wall_mat.set_shader_parameter("fade", 1.0 - smoothstep(spread_time * 0.37, spread_time * 1.37, _t))
