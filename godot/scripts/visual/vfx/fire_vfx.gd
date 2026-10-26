@tool
class_name FireVfx
extends Node3D
## 몽글한 화염 VFX(표시 전용, 게임 판정과 무관). 레퍼런스: Unity VFX Graph "FX_Fire_Scalable" 구성을 Godot 로 옮긴 것.
## 세 겹의 GPUParticles3D 로 그린다 — 텍스처 없이 셰이더 노이즈(shaders/vfx/fire/)로 모양을 만든다.
##   Smoke   : 반투명 연기. 불빛을 머금은 tint → smoke 색으로 식으며 크게 퍼진다(먼저 그림)
##   Flame   : 가산 불꽃. 흰 심지 → core → mid → edge 로 식으며 노이즈에 깎여 덩어리로 흩어진다
##   Cinders : 가산 불티. 난류를 타고 높이 흩날린다
## 노드 원점 = 불 바닥 중심. 레퍼런스의 노출 파라미터(Size·Puffiness·Spawn Amount·Cinders On·색)를 그대로 둔다.
## size 를 바꾸면 반경·속도·중력·입자 크기·불빛 범위가 함께 늘어 비율이 유지된다.
## 색 조합은 PRESETS(hearth/toxic/arcane/witch)로 바꾸거나 각 색을 직접 지정한다.

const SHADER_FLAME := preload("res://shaders/vfx/fire/fire_flame.gdshader")
const SHADER_SMOKE := preload("res://shaders/vfx/fire/fire_smoke.gdshader")
const SHADER_CINDER := preload("res://shaders/vfx/fire/fire_cinder.gdshader")

## core·mid·edge = 불꽃 그라디언트, smoke·tint = 연기(식은 색·불빛 받은 색), cinder = 불티, light = 불빛
const PRESETS := {
	"hearth": {"core": Color(1.0, 0.92, 0.6), "mid": Color(1.0, 0.42, 0.1), "edge": Color(0.72, 0.06, 0.04),
		"smoke": Color(0.1, 0.1, 0.2), "tint": Color(0.5, 0.08, 0.06), "cinder": Color(1.0, 0.5, 0.16), "light": Color(1.0, 0.6, 0.28)},
	"toxic": {"core": Color(1.0, 0.97, 0.5), "mid": Color(0.6, 1.0, 0.16), "edge": Color(0.2, 0.66, 0.08), "energy": 1.5,
		"smoke": Color(0.4, 0.06, 0.36), "tint": Color(0.3, 0.6, 0.12), "cinder": Color(0.75, 1.0, 0.35), "light": Color(0.6, 1.0, 0.3)},
	"arcane": {"core": Color(0.6, 0.98, 1.0), "mid": Color(0.22, 0.75, 1.0), "edge": Color(0.12, 0.26, 0.85), "energy": 1.25,
		"smoke": Color(0.24, 0.1, 0.42), "tint": Color(0.16, 0.36, 0.7), "cinder": Color(0.45, 1.0, 0.95), "light": Color(0.4, 0.8, 1.0)},
	"witch": {"core": Color(1.0, 0.82, 1.0), "mid": Color(0.74, 0.32, 1.0), "edge": Color(0.36, 0.1, 0.75), "energy": 1.4,
		"smoke": Color(0.16, 0.08, 0.26), "tint": Color(0.42, 0.14, 0.6), "cinder": Color(0.95, 0.6, 1.0), "light": Color(0.75, 0.45, 1.0)},
}

# 크기 1 기준 입자 수(spawn_amount = 1 일 때)
const FLAME_AMOUNT := 84
const SMOKE_AMOUNT := 44
const CINDER_AMOUNT := 40

@export_enum("hearth", "toxic", "arcane", "witch") var preset := "hearth":
	set(v):
		preset = v
		_apply_preset()
## 이펙트 전체 배율(레퍼런스 Size)
@export_range(0.1, 6.0, 0.01) var size := 1.0:
	set(v):
		size = maxf(v, 0.05)
		_rebuild()
## 연기·불꽃을 덩어리로 나누는 정도(레퍼런스 Puffiness)
@export_range(0.0, 1.0, 0.01) var puffiness := 0.7:
	set(v):
		puffiness = v
		_apply_colors()
## 입자 생성량 배율(레퍼런스 Spawn Amount)
@export_range(0.1, 4.0, 0.01) var spawn_amount := 1.0:
	set(v):
		spawn_amount = v
		_rebuild()
## 불티 켜기/끄기(레퍼런스 Cinders On)
@export var cinders_on := true:
	set(v):
		cinders_on = v
		if cinders != null:
			cinders.emitting = v and lit
## 불 세기 0~1. 연료가 줄면 낮춘다(생성량·불꽃 높이·불빛이 함께 줄어든다)
@export_range(0.0, 1.0, 0.01) var intensity := 1.0:
	set(v):
		intensity = clampf(v, 0.0, 1.0)
		_apply_intensity()
## 켜짐/꺼짐. 끄면 새 입자만 멈추고 남은 입자는 자연스럽게 사라진다
@export var lit := true:
	set(v):
		lit = v
		_apply_intensity()
## 연기·불티를 미는 바람(월드, m/s²). 레퍼런스처럼 비스듬히 눕힌다. 매 프레임 바꿔도 입자를 다시 시작하지 않는다
@export var wind := Vector3(0.35, 0.0, 0.0):
	set(v):
		wind = v
		_apply_wind()
@export var with_light := true:
	set(v):
		with_light = v
		if light != null:
			light.visible = v and lit

@export_group("Colors")
@export var core_color := Color(1.0, 0.92, 0.6):
	set(v): core_color = v; _apply_colors()
@export var mid_color := Color(1.0, 0.42, 0.1):
	set(v): mid_color = v; _apply_colors()
@export var edge_color := Color(0.72, 0.06, 0.04):
	set(v): edge_color = v; _apply_colors()
@export var smoke_color := Color(0.1, 0.1, 0.2):
	set(v): smoke_color = v; _apply_colors()
@export var tint_color := Color(0.5, 0.08, 0.06):
	set(v): tint_color = v; _apply_colors()
@export var cinder_color := Color(1.0, 0.5, 0.16):
	set(v): cinder_color = v; _apply_colors()
@export var light_color := Color(1.0, 0.6, 0.28):
	set(v): light_color = v; _apply_colors()
@export_range(0.5, 6.0, 0.01) var flame_energy := 1.7:
	set(v): flame_energy = v; _apply_colors()
@export_range(0.0, 1.0, 0.01) var smoke_opacity := 0.7:
	set(v): smoke_opacity = v; _apply_colors()

var flame: GPUParticles3D
var smoke: GPUParticles3D
var cinders: GPUParticles3D
var light: OmniLight3D
var _flame_mat: ShaderMaterial
var _smoke_mat: ShaderMaterial
var _cinder_mat: ShaderMaterial
var _t := 0.0
var _seed := 0.0


func _init() -> void:
	name = "FireVfx"


func _ready() -> void:
	_seed = randf() * 100.0
	_build()


## 색 프리셋 이름으로 바꾼다(PRESETS 키). 개별 색 export 도 함께 갱신된다.
func set_preset(key: String) -> void:
	preset = key


func _build() -> void:
	for c in get_children():
		if c.has_meta("fire_vfx_part"):
			c.queue_free()
	_smoke_mat = _mat(SHADER_SMOKE, 0)
	_flame_mat = _mat(SHADER_FLAME, 1)
	_cinder_mat = _mat(SHADER_CINDER, 2)
	smoke = _particles("Smoke", _smoke_mat)
	flame = _particles("Flame", _flame_mat)
	cinders = _particles("Cinders", _cinder_mat)
	light = OmniLight3D.new()
	light.name = "FireLight"
	light.set_meta("fire_vfx_part", true)
	light.shadow_enabled = false
	add_child(light)
	_rebuild()


func _mat(shader: Shader, priority: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader
	m.render_priority = priority
	return m


func _particles(part: String, mat: ShaderMaterial) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.name = part
	p.set_meta("fire_vfx_part", true)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.draw_order = GPUParticles3D.DRAW_ORDER_VIEW_DEPTH
	var quad := QuadMesh.new()
	quad.material = mat
	p.draw_pass_1 = quad
	p.process_material = ParticleProcessMaterial.new()
	add_child(p)
	return p


func _apply_preset() -> void:
	if not PRESETS.has(preset):
		return
	var p: Dictionary = PRESETS[preset]
	core_color = p.core
	mid_color = p.mid
	edge_color = p.edge
	smoke_color = p.smoke
	tint_color = p.tint
	cinder_color = p.cinder
	light_color = p.light
	flame_energy = p.get("energy", 1.7)


func _apply_colors() -> void:
	if _flame_mat == null:
		return
	_flame_mat.set_shader_parameter("core_color", core_color)
	_flame_mat.set_shader_parameter("mid_color", mid_color)
	_flame_mat.set_shader_parameter("edge_color", edge_color)
	_flame_mat.set_shader_parameter("energy", flame_energy)
	_flame_mat.set_shader_parameter("puffiness", puffiness)
	_flame_mat.set_shader_parameter("soft_distance", 0.35 * size)
	_smoke_mat.set_shader_parameter("smoke_color", smoke_color)
	_smoke_mat.set_shader_parameter("tint_color", tint_color)
	_smoke_mat.set_shader_parameter("puffiness", puffiness)
	_smoke_mat.set_shader_parameter("opacity", smoke_opacity)
	_smoke_mat.set_shader_parameter("soft_distance", 0.6 * size)
	_cinder_mat.set_shader_parameter("cinder_color", cinder_color)
	_cinder_mat.set_shader_parameter("cinder_hot", cinder_color.lerp(Color.WHITE, 0.6))
	if light != null:
		light.light_color = light_color


## 크기·생성량·바람이 바뀌면 세 겹의 방출·운동 값을 size 비율로 다시 잡는다(레퍼런스 "Scale VFX").
func _rebuild() -> void:
	if flame == null:
		return
	var s := size
	var up := Vector3.UP

	# ── 불꽃: 바닥 원반에서 솟아 짧게 타오른다 ──
	_set_amount(flame, maxi(int(FLAME_AMOUNT * spawn_amount), 4))
	flame.lifetime = 1.45
	flame.preprocess = 1.0
	flame.randomness = 0.4
	flame.visibility_aabb = AABB(Vector3(-1.5, -0.3, -1.5) * s, Vector3(3.0, 3.6, 3.0) * s)
	var fm: ParticleProcessMaterial = flame.process_material
	fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	fm.emission_sphere_radius = 0.26 * s
	fm.emission_shape_scale = Vector3(1.0, 0.3, 1.0)
	fm.emission_shape_offset = Vector3(0.0, 0.18 * s, 0.0)
	fm.direction = up
	fm.spread = 14.0
	fm.initial_velocity_min = 0.9 * s
	fm.initial_velocity_max = 1.6 * s
	fm.damping_min = 0.4 * s
	fm.damping_max = 0.9 * s
	fm.angle_min = -180.0
	fm.angle_max = 180.0
	fm.angular_velocity_min = -40.0
	fm.angular_velocity_max = 40.0
	fm.scale_min = 0.65 * s
	fm.scale_max = 1.1 * s
	fm.scale_curve = _curve([Vector2(0.0, 0.7), Vector2(0.3, 1.0), Vector2(1.0, 0.45)])
	fm.anim_offset_min = 0.0
	fm.anim_offset_max = 1.0
	_turbulence(fm, 0.35, 1.6 / s, 1.2)

	# ── 연기: 불꽃 꼭대기에서 이어 피어 크게 퍼지며 바람에 눕는다 ──
	_set_amount(smoke, maxi(int(SMOKE_AMOUNT * spawn_amount), 4))
	smoke.lifetime = 3.2
	smoke.preprocess = 3.5
	smoke.randomness = 0.5
	# 바람이 매 프레임 바뀌어도 잘리지 않게 돌풍까지 덮는 넉넉한 상자
	smoke.visibility_aabb = AABB(Vector3(-6.0, -0.3, -6.0) * s, Vector3(12.0, 8.0, 12.0) * s)
	var sm: ParticleProcessMaterial = smoke.process_material
	sm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	sm.emission_sphere_radius = 0.25 * s
	sm.emission_shape_offset = Vector3(0.0, 1.3 * s, 0.0)
	sm.direction = up
	sm.spread = 22.0
	sm.initial_velocity_min = 0.45 * s
	sm.initial_velocity_max = 0.8 * s
	sm.damping_min = 0.08 * s
	sm.damping_max = 0.2 * s
	sm.angle_min = -180.0
	sm.angle_max = 180.0
	sm.angular_velocity_min = -18.0
	sm.angular_velocity_max = 18.0
	sm.scale_min = 0.9 * s
	sm.scale_max = 1.4 * s
	sm.scale_curve = _curve([Vector2(0.0, 0.5), Vector2(0.4, 1.2), Vector2(1.0, 2.1)])
	sm.anim_offset_min = 0.0
	sm.anim_offset_max = 1.0
	_turbulence(sm, 0.6, 0.9 / s, 0.5)

	# ── 불티: 빠르게 솟아 난류를 타고 흩날린다 ──
	_set_amount(cinders, maxi(int(CINDER_AMOUNT * spawn_amount), 2))
	cinders.lifetime = 3.2
	cinders.preprocess = 2.0
	cinders.randomness = 0.6
	cinders.visibility_aabb = smoke.visibility_aabb
	var cm: ParticleProcessMaterial = cinders.process_material
	cm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	cm.emission_sphere_radius = 0.28 * s
	cm.emission_shape_offset = Vector3(0.0, 0.25 * s, 0.0)
	cm.direction = up
	cm.spread = 30.0
	cm.initial_velocity_min = 1.8 * s
	cm.initial_velocity_max = 3.4 * s
	cm.damping_min = 0.5 * s
	cm.damping_max = 0.9 * s
	cm.scale_min = 0.07 * s
	cm.scale_max = 0.13 * s
	cm.anim_offset_min = 0.0
	cm.anim_offset_max = 1.0
	_turbulence(cm, 1.4, 1.2 / s, 0.8)

	if light != null:
		light.position = Vector3(0, 0.8 * s, 0)
		light.omni_range = 6.5 * s
	_apply_wind()
	_apply_colors()
	_apply_intensity()


## amount 를 다시 넣으면 입자가 처음부터 다시 시작되므로 값이 바뀔 때만 넣는다.
func _set_amount(p: GPUParticles3D, n: int) -> void:
	if p.amount != n:
		p.amount = n


## 중력 = 부력(위) + 바람. 불꽃은 덜, 불티는 더 바람을 탄다.
func _apply_wind() -> void:
	if flame == null:
		return
	var s := size
	(flame.process_material as ParticleProcessMaterial).gravity = (Vector3.UP * 2.0 + wind * 1.3) * s
	(smoke.process_material as ParticleProcessMaterial).gravity = (Vector3.UP * 0.35 + wind) * s
	(cinders.process_material as ParticleProcessMaterial).gravity = (Vector3.UP * 0.6 + wind * 1.4) * s


func _turbulence(m: ParticleProcessMaterial, strength: float, scale: float, speed: float) -> void:
	m.turbulence_enabled = true
	m.turbulence_noise_strength = strength
	m.turbulence_noise_scale = scale
	m.turbulence_noise_speed = Vector3(0.0, speed, 0.0)
	m.turbulence_noise_speed_random = 0.3
	m.turbulence_influence_min = 0.05
	m.turbulence_influence_max = 0.18


func _curve(points: Array) -> CurveTexture:
	var c := Curve.new()
	for p in points:
		c.add_point(p)
	var tex := CurveTexture.new()
	tex.curve = c
	return tex


func _apply_intensity() -> void:
	if flame == null:
		return
	var on := lit and intensity > 0.001
	# 세기는 생성 비율과 불꽃 크기로 함께 줄인다. 아주 약해도 불씨처럼 조금은 남게 바닥을 둔다
	var k := clampf(intensity, 0.0, 1.0)
	flame.amount_ratio = lerpf(0.35, 1.0, k)
	smoke.amount_ratio = lerpf(0.25, 1.0, k)
	cinders.amount_ratio = lerpf(0.2, 1.0, k)
	flame.speed_scale = lerpf(0.8, 1.0, k)
	flame.emitting = on
	smoke.emitting = on
	cinders.emitting = on and cinders_on
	if light != null:
		light.visible = on and with_light


func _process(delta: float) -> void:
	if light == null or not light.visible:
		return
	_t += delta
	var k := lerpf(0.4, 1.0, intensity)
	light.light_energy = (1.3 + sin(_t * 11.0 + _seed) * 0.12 + sin(_t * 27.0 + _seed * 2.0) * 0.06) * k
