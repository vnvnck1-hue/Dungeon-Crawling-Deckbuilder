extends MeshInstance3D
## 투사체 꼬리 리본(카메라를 향하는 띠). 따라가던 대상이 사라지면 남은 꼬리가 줄어들며 스스로 지워진다.
## 표시 전용 — 투사체의 판정과 무관하다.

const SHADER := preload("res://shaders/vfx/vfx_ribbon.gdshader")

var target: Node3D
var width := 0.3
var duration := 0.28        # 꼬리 한 점이 사라지기까지의 시간
var _pts: Array = []        # [position, age]
var _im := ImmediateMesh.new()
var _mat := ShaderMaterial.new()


static func follow(parent: Node, node: Node3D, edge: Color, core := Color(1, 0.97, 1), w := 0.3,
		dur := 0.28, intensity := 1.6) -> MeshInstance3D:
	var r = load("res://scripts/visual/vfx/ribbon_trail.gd").new()
	r.target = node
	r.width = w
	r.duration = dur
	r._mat.set_shader_parameter("edge_color", edge)
	r._mat.set_shader_parameter("core_color", core)
	r._mat.set_shader_parameter("intensity", intensity)
	parent.add_child(r)
	return r


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	_mat.shader = SHADER
	mesh = _im
	material_override = _mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))


func _process(delta: float) -> void:
	for p in _pts:
		p[1] += delta
	while not _pts.is_empty() and _pts[_pts.size() - 1][1] > duration:
		_pts.pop_back()
	var alive := target != null and is_instance_valid(target) and target.is_inside_tree()
	if alive:
		var head := target.global_position
		if _pts.is_empty() or (_pts[0][0] as Vector3).distance_to(head) > 0.04:
			_pts.push_front([head, 0.0])
		else:
			_pts[0][0] = head
	elif _pts.is_empty():
		queue_free()
		return
	_rebuild()


func _rebuild() -> void:
	_im.clear_surfaces()
	if _pts.size() < 2:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var view := -cam.global_basis.z
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var n := _pts.size()
	for i in n:
		var p: Vector3 = _pts[i][0]
		var a: float = _pts[i][1]
		var nxt: Vector3 = _pts[mini(i + 1, n - 1)][0]
		var prv: Vector3 = _pts[maxi(i - 1, 0)][0]
		var dir := (prv - nxt)
		if dir.length_squared() < 1e-6:
			dir = Vector3.RIGHT
		var side := dir.cross(view).normalized()
		var k := clampf(a / duration, 0.0, 1.0)
		var u := maxf(float(i) / float(n - 1), k)
		var w := width * (1.0 - u * 0.85)
		_im.surface_set_color(Color(1, 1, 1, 1.0 - k))
		_im.surface_set_uv(Vector2(u, 0.0))
		_im.surface_add_vertex(p + side * w)
		_im.surface_set_color(Color(1, 1, 1, 1.0 - k))
		_im.surface_set_uv(Vector2(u, 1.0))
		_im.surface_add_vertex(p - side * w)
	_im.surface_end()
