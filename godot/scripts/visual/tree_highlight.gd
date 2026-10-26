extends RefCounted
## 나무꾼 카드를 끄는 동안 마우스 아래 나무를 강조한다: 모델 전체를 황금빛(불가면 회색)으로 물들이고 외곽선을 두른다.
## 바닥 고리는 쓰지 않는다. 표시 전용이며 판정은 CardUseResolver가 한다.

const HULL := preload("res://shaders/inverted_hull.gdshader")

static var _current: Dictionary = {}
static var _hulls: Array = []
static var _overlay_ok: ShaderMaterial
static var _overlay_bad: ShaderMaterial
static var _hull_ok: ShaderMaterial
static var _hull_bad: ShaderMaterial


static func _materials() -> void:
	if _overlay_ok != null:
		return
	_overlay_ok = _tint(Color(1.0, 0.72, 0.2, 0.2))
	_overlay_bad = _tint(Color(0.35, 0.3, 0.45, 0.22))
	_hull_ok = ShaderMaterial.new()
	_hull_ok.shader = HULL
	_hull_ok.set_shader_parameter("line_color", Color(1.0, 0.85, 0.35, 1.0))
	_hull_bad = ShaderMaterial.new()
	_hull_bad.shader = HULL
	_hull_bad.set_shader_parameter("line_color", Color(0.55, 0.5, 0.6, 1.0))
	_hull_bad.set_shader_parameter("pulse", 0.0)


## 모델 위에 덧칠하는 반투명 색(가산). 바람 셰이더 위에 덧그려지므로 모양을 바꾸지 않는다.
static func _tint(c: Color) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;\nuniform vec4 tint : source_color;\nvoid fragment() { float k = 0.8 + 0.2 * sin(TIME * 5.0); ALBEDO = tint.rgb * tint.a * k; ALPHA = 1.0; }"
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("tint", c)
	m.render_priority = 5
	return m


## 강조 대상 설정. tree가 빈 사전이면 해제. ok=false면 지정 불가(회색).
static func set_target(tree: Dictionary, ok: bool) -> void:
	_materials()
	if tree == _current and not tree.is_empty():
		_apply(ok)
		return
	clear()
	if tree.is_empty():
		return
	_current = tree
	var v: Node3D = tree["visual"]
	if v == null or not is_instance_valid(v):
		_current = {}
		return
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		var hull := MeshInstance3D.new()
		hull.name = "__outline"
		hull.mesh = mi.mesh
		hull.material_override = _hull_ok if ok else _hull_bad
		hull.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hull.transform = mi.transform
		mi.get_parent().add_child(hull)
		_hulls.append(hull)
	_apply(ok)


static func _apply(ok: bool) -> void:
	if _current.is_empty():
		return
	var v: Node3D = _current["visual"]
	if v == null or not is_instance_valid(v):
		return
	for mi in v.find_children("*", "MeshInstance3D", true, false):
		if mi.name == "__outline":
			mi.material_override = _hull_ok if ok else _hull_bad
		else:
			mi.material_overlay = _overlay_ok if ok else _overlay_bad


static func clear() -> void:
	if not _current.is_empty():
		var v = _current.get("visual")
		if v != null and is_instance_valid(v):
			for mi in v.find_children("*", "MeshInstance3D", true, false):
				if mi.name != "__outline":
					mi.material_overlay = null
	for h in _hulls:
		if is_instance_valid(h):
			if h.get_parent() != null:
				h.get_parent().remove_child(h)
			h.queue_free()
	_hulls.clear()
	_current = {}


static func current() -> Dictionary:
	return _current
