extends RefCounted
## 재질 팩토리. 같은 색·파라미터는 하나의 재질을 공유한다.

const STYLIZED := preload("res://shaders/stylized.gdshader")

static var _cache: Dictionary = {}


static func solid(color: Color, params: Dictionary = {}) -> ShaderMaterial:
	var key := "s" + color.to_html() + str(params)
	if _cache.has(key):
		return _cache[key]
	var m := ShaderMaterial.new()
	m.shader = STYLIZED
	m.set_shader_parameter("albedo", color)
	for k in params:
		m.set_shader_parameter(k, params[k])
	_cache[key] = m
	return m


## 창문·등불·눈처럼 스스로 빛나는 면. 글로우를 위해 HDR 발광을 쓴다.
static func glow(color: Color, energy := 3.0) -> StandardMaterial3D:
	var key := "g" + color.to_html() + str(energy)
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.roughness = 1.0
	m.metallic_specular = 0.0
	_cache[key] = m
	return m


static var _unshaded_cache := {}

## unshaded() 를 같은 인자끼리 같이 쓴다. 돌려받은 재질을 고치지 않는 곳(액터 발밑 고리 등)에서만 쓴다.
static func unshaded_shared(color: Color, transparent := false, additive := false) -> StandardMaterial3D:
	var key := [color, transparent, additive]
	var m: StandardMaterial3D = _unshaded_cache.get(key)
	if m == null:
		m = unshaded(color, transparent, additive)
		_unshaded_cache[key] = m
	return m


static func unshaded(color: Color, transparent := false, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = color
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shadow_to_opacity = false
	return m


## 파티클용 둥근 소프트 텍스처.
static func soft_dot() -> GradientTexture2D:
	if _cache.has("soft_dot"):
		return _cache["soft_dot"]
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.45, Color(1, 1, 1, 0.75))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	_cache["soft_dot"] = t
	return t


static func particle(color: Color, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.albedo_color = color
	m.albedo_texture = soft_dot()
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m
