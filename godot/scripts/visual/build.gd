extends RefCounted
## 기본 도형 메시 조립 도우미. 모든 블록아웃 모델은 이 함수들로 만든다.


static func mi(parent: Node, mesh: Mesh, pos: Vector3, mat: Material, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	m.material_override = mat
	m.position = pos
	m.rotation_degrees = rot
	m.scale = scl
	parent.add_child(m)
	return m


static func box(parent: Node, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var b := BoxMesh.new()
	b.size = size
	return mi(parent, b, pos, mat, rot)


static func bevel_box(parent: Node, size: Vector3, pos: Vector3, mat: Material, radius := 0.04, rot := Vector3.ZERO) -> MeshInstance3D:
	var h := size * 0.5
	var r := minf(radius, minf(h.x, minf(h.y,h.z)) * .8)
	var points: Array[Vector3] = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for x: float in [-1.0,1.0]:
		for y: float in [-1.0,1.0]:
			for z: float in [-1.0,1.0]:
				var signv := Vector3(x,y,z)
				var corner: Array[Vector3] = []
				for axis in 3:
					var p := h * signv
					p[axis] -= r * signv[axis]
					points.append(p)
					corner.append(p)
				_poly(st,corner,signv.normalized())
	for axis in 3:
		for s: float in [-1.0,1.0]:
			var face: Array[Vector3] = []
			var normal := Vector3.ZERO
			normal[axis] = s
			for p in points:
				if absf(p[axis]-h[axis]*s)<.0001: face.append(p)
			_poly(st,face,normal)
	for axis in 3:
		var a := (axis+1)%3
		var b := (axis+2)%3
		for sa: float in [-1.0,1.0]:
			for sb: float in [-1.0,1.0]:
				var face: Array[Vector3] = []
				var normal := Vector3.ZERO
				normal[a] = sa
				normal[b] = sb
				for p in points:
					if absf(p[a]*sa+p[b]*sb-(h[a]+h[b]-r))<.0001: face.append(p)
				_poly(st,face,normal.normalized())
	st.index()
	return mi(parent,st.commit(),pos,mat,rot)


static func _poly(st: SurfaceTool, points: Array[Vector3], normal: Vector3) -> void:
	if points.size()<3: return
	var c := Vector3.ZERO
	for p in points: c+=p
	c/=points.size()
	var u := normal.cross(Vector3.UP).normalized()
	if u.length_squared()<.01: u=Vector3.RIGHT
	var v := normal.cross(u)
	points.sort_custom(func(a: Vector3,b: Vector3): return atan2((a-c).dot(v),(a-c).dot(u)) < atan2((b-c).dot(v),(b-c).dot(u)))
	for i in range(1,points.size()-1):
		for p: Vector3 in [points[0],points[i],points[i+1]]:
			st.set_normal(normal)
			st.set_uv(Vector2(p.dot(u),p.dot(v)))
			st.add_vertex(p)


static func cyl(parent: Node, r_top: float, r_bot: float, h: float, pos: Vector3, mat: Material,
		segs := 8, rot := Vector3.ZERO) -> MeshInstance3D:
	var c := CylinderMesh.new()
	c.top_radius = r_top
	c.bottom_radius = r_bot
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return mi(parent, c, pos, mat, rot)


static func sphere(parent: Node, r: float, pos: Vector3, mat: Material, scl := Vector3.ONE,
		segs := 14, rings := 7) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	return mi(parent, s, pos, mat, Vector3.ZERO, scl)


static func prism(parent: Node, size: Vector3, pos: Vector3, mat: Material, rot := Vector3.ZERO,
		left_to_right := 0.5) -> MeshInstance3D:
	var p := PrismMesh.new()
	p.size = size
	p.left_to_right = left_to_right
	return mi(parent, p, pos, mat, rot)


static var _torus_cache := {}

## 같은 반지름의 고리는 메시 하나를 같이 쓴다(액터마다 생기는 발밑 고리 등). 호출한 쪽은 메시를 고치지 않는다.
static func torus(parent: Node, inner: float, outer: float, pos: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var key := Vector2(inner, outer)
	var t: TorusMesh = _torus_cache.get(key)
	if t == null:
		t = TorusMesh.new()
		t.inner_radius = inner
		t.outer_radius = outer
		t.rings = 16
		t.ring_segments = 8
		_torus_cache[key] = t
	return mi(parent, t, pos, mat, rot)


static func node(parent: Node, pos := Vector3.ZERO, rot := Vector3.ZERO, node_name := "") -> Node3D:
	var n := Node3D.new()
	if node_name != "":
		n.name = node_name
	n.position = pos
	n.rotation_degrees = rot
	parent.add_child(n)
	return n


static func omni(parent: Node, pos: Vector3, color: Color, energy: float, light_range: float,
		shadow := false, attenuation := 1.0) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.omni_attenuation = attenuation
	l.shadow_enabled = shadow
	l.light_specular = 0.0
	parent.add_child(l)
	return l
