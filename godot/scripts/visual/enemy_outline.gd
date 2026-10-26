extends RefCounted
## 롤식 적 강조: 마우스오버한 적은 밝은 붉은 외곽선, 공격 대상으로 잡힌 적은 더 진하고 두꺼운 붉은 외곽선(+옅은 붉은 덧칠).
## 적 visual 아래 모든 MeshInstance3D 의 material_overlay 에 외곽선 재질을 건다(스킨·IK를 그대로 따라감). 표시 전용.

const SHADER := preload("res://shaders/target_outline.gdshader")

enum { NONE, HOVER, TARGET }

const HOVER_COLOR := Color(1.0, 0.22, 0.16)
const TARGET_COLOR := Color(0.72, 0.0, 0.02)
const HOVER_WIDTH := 2.6
const TARGET_WIDTH := 4.2

static var _mats: Dictionary = {}


static func material(state: int) -> ShaderMaterial:
	if _mats.has(state):
		return _mats[state]
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.render_priority = 4
	if state == TARGET:
		m.set_shader_parameter("line_color", TARGET_COLOR)
		m.set_shader_parameter("width_px", TARGET_WIDTH)
		m.set_shader_parameter("pulse", 1.0)
		# 대상: 몸 전체에 아주 옅은 붉은 가산 덧칠을 한 번 더 얹어 멀리서도 눈에 띄게
		var tint := ShaderMaterial.new()
		var sh := Shader.new()
		sh.code = "shader_type spatial;\nrender_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;\nvoid fragment() { float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0); ALBEDO = vec3(0.5, 0.02, 0.0) * (0.05 + 0.4 * rim); ALPHA = 1.0; }"
		tint.shader = sh
		tint.render_priority = 5
		m.next_pass = tint
	else:
		m.set_shader_parameter("line_color", HOVER_COLOR)
		m.set_shader_parameter("width_px", HOVER_WIDTH)
		m.set_shader_parameter("pulse", 0.0)
	_mats[state] = m
	return m


static func meshes(enemy) -> Array:
	var root = enemy.get("visual") if enemy != null and is_instance_valid(enemy) else null
	if root == null or not is_instance_valid(root):
		return []
	var out: Array = []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if mi.visible:
			out.append(mi)
	return out


## 적 하나의 강조 상태를 바꾼다. 같은 상태면 아무것도 하지 않는다.
static func apply(enemy, state: int) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if int(enemy.get_meta("lol_outline", NONE)) == state:
		return
	enemy.set_meta("lol_outline", state)
	var mat: Material = null if state == NONE else material(state)
	for mi in meshes(enemy):
		mi.material_overlay = mat


static func state_of(enemy) -> int:
	if enemy == null or not is_instance_valid(enemy):
		return NONE
	return int(enemy.get_meta("lol_outline", NONE))
