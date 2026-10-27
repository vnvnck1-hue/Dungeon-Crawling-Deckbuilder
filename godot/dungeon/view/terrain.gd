extends RefCounted
## 숲길 원정대 지형(표시 전용). 방(공터)·숲길은 y=0 평지 그대로 두고, 그 바깥을 계단식 단과 절벽으로 올리고 내린다.
## 화면 위쪽(카메라 반대편)은 겹겹이 솟은 언덕 단, 아래쪽(카메라 쪽)은 꺼진 낭떠러지와 밤 물웅덩이 —
## 높은 벽이 카메라와 격자 사이에 서지 않으면서 공터가 사방으로 둘러싸인 아늑한 분지처럼 읽히게 한다.

const CELL := 0.6                 # 지형 정점 간격(m)
const FIELD := 2.0                # 공터·길 거리장 표본 간격(m)
const CHUNK := 48                 # 메시 조각 한 변의 칸 수
const WATER_Y := -3.4
## [공터·길에서 떨어진 거리, 그 단의 높이]
const UP_STEPS := [[1.3, 3.0], [7.0, 3.0], [13.0, 3.4], [20.0, 3.8]]
const DOWN_STEPS := [[1.6, 2.6], [6.5, 2.7], [12.0, 2.4]]
const CLIFF_HALF := 0.45          # 절벽 면 반 폭(m) — 좁을수록 가파르다

var world
var origin := Vector2.ZERO        # 정점 격자 (0,0) 의 xz
var gw := 0
var gh := 0
var heights := PackedFloat32Array()
var dists := PackedFloat32Array()  # 정점마다 공터·길까지 거리
var _centre: Array = []            # Vector2(lane 좌표, perp 좌표) 진행 순
var _n_side := FastNoiseLite.new()
var _n_edge := FastNoiseLite.new()
var _n_bump := FastNoiseLite.new()


func build(w, lo: Vector2, hi: Vector2) -> void:
	world = w
	_n_side.seed = 11
	_n_side.frequency = 0.03
	_n_edge.seed = 23
	_n_edge.frequency = 0.08
	_n_edge.fractal_octaves = 3
	_n_bump.seed = 37
	_n_bump.frequency = 0.16
	_build_centre()
	origin = lo
	gw = int(ceil((hi.x - lo.x) / CELL)) + 1
	gh = int(ceil((hi.y - lo.y) / CELL)) + 1
	# 공터·길 거리장은 성기게 재고 정점에서는 보간한다(정점마다 재면 너무 느리다)
	var fw := int(ceil((hi.x - lo.x) / FIELD)) + 2
	var fh := int(ceil((hi.y - lo.y) / FIELD)) + 2
	var field := PackedFloat32Array()
	field.resize(fw * fh)
	for j in fh:
		for i in fw:
			field[j * fw + i] = world.open_distance(Vector3(lo.x + i * FIELD, 0, lo.y + j * FIELD))
	heights.resize(gw * gh)
	dists.resize(gw * gh)
	for j in gh:
		var fz := j * CELL / FIELD
		var j0 := mini(int(fz), fh - 2)
		var tz := fz - j0
		for i in gw:
			var fx := i * CELL / FIELD
			var i0 := mini(int(fx), fw - 2)
			var tx := fx - i0
			var k := j0 * fw + i0
			var d := lerpf(lerpf(field[k], field[k + 1], tx), lerpf(field[k + fw], field[k + fw + 1], tx), tz)
			dists[j * gw + i] = d
			heights[j * gw + i] = _height(lo.x + i * CELL, lo.y + j * CELL, d)


func _build_centre() -> void:
	var pts: Array = []
	for r in world.rooms:
		pts.append(r.center)
	for path in [world.entry_path] + world.paths:
		pts.append_array(path)
	for p in pts:
		_centre.append(Vector2((p as Vector3).dot(world.lane), (p as Vector3).dot(world.perp)))
	_centre.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.x < b.x)


## 진행 좌표 t 에서 길 가운데 선의 옆(perp) 좌표.
func _centre_offset(t: float) -> float:
	if t <= _centre[0].x:
		return _centre[0].y
	for k in range(1, _centre.size()):
		if t <= _centre[k].x:
			var a: Vector2 = _centre[k - 1]
			var b: Vector2 = _centre[k]
			return lerpf(a.y, b.y, (t - a.x) / maxf(b.x - a.x, 0.001))
	return _centre[-1].y


func _height(x: float, z: float, d: float) -> float:
	if d < 0.25:
		return 0.0
	var p := Vector3(x, 0, z)
	# side > 0 = 길보다 카메라 쪽(화면 아래)
	var side: float = p.dot(world.perp) - _centre_offset(p.dot(world.lane))
	var s := clampf(-side / 5.0 + _n_side.get_noise_2d(x, z) * 0.9, -1.0, 1.0)
	# 카메라 쪽 가까운 곳은 반드시 내려간다 — 솟은 벽이 격자·길을 가리지 않게
	var cap := lerpf(-0.75, 1.0, smoothstep(15.0, 24.0, d))
	s = lerpf(s, minf(s, cap), smoothstep(0.0, 4.0, side))
	var e := d + _n_edge.get_noise_2d(x, z) * 1.2
	var steps: Array = UP_STEPS if s > 0.0 else DOWN_STEPS
	var f := 0.0
	for st in steps:
		f += float(st[1]) * smoothstep(float(st[0]) - CLIFF_HALF, float(st[0]) + CLIFF_HALF, e)
	f += _n_bump.get_noise_2d(x, z) * 0.35 * smoothstep(3.0, 6.0, e)
	return f * s * smoothstep(0.25, 1.1, d)


func _h(i: int, j: int) -> float:
	return heights[clampi(j, 0, gh - 1) * gw + clampi(i, 0, gw - 1)]


## 세계 좌표의 지면 높이(정점 격자 보간).
func height_at(p: Vector3) -> float:
	var fx := clampf((p.x - origin.x) / CELL, 0.0, gw - 1.001)
	var fz := clampf((p.z - origin.y) / CELL, 0.0, gh - 1.001)
	var i := int(fx)
	var j := int(fz)
	var tx := fx - i
	var tz := fz - j
	return lerpf(lerpf(_h(i, j), _h(i + 1, j), tx), lerpf(_h(i, j + 1), _h(i + 1, j + 1), tx), tz)


## 내리막 기울기(높이 차 / 거리, xz). 길이가 가파름.
func gradient_at(p: Vector3) -> Vector2:
	var e := 0.5
	return Vector2(height_at(p + Vector3(e, 0, 0)) - height_at(p - Vector3(e, 0, 0)),
		height_at(p + Vector3(0, 0, e)) - height_at(p - Vector3(0, 0, e))) / (2.0 * e)


## 반경 r 안의 가장 높은 지면과 가장 낮은 지면의 차(절벽 언저리 판정).
func relief_at(p: Vector3, r: float) -> float:
	var a := INF
	var b := -INF
	for k in 8:
		var q := p + Vector3(cos(k * TAU / 8.0), 0, sin(k * TAU / 8.0)) * r
		var h := height_at(q)
		a = minf(a, h)
		b = maxf(b, h)
	return b - a


## 지형 메시 조각들을 parent 아래에 만든다.
func make_meshes(parent: Node3D, mat: Material) -> void:
	for cj in range(0, gh - 1, CHUNK):
		for ci in range(0, gw - 1, CHUNK):
			var i1 := mini(ci + CHUNK, gw - 1)
			var j1 := mini(cj + CHUNK, gh - 1)
			var stride := i1 - ci + 1
			var verts := PackedVector3Array()
			var normals := PackedVector3Array()
			var idx := PackedInt32Array()
			for j in range(cj, j1 + 1):
				for i in range(ci, i1 + 1):
					verts.append(Vector3(origin.x + i * CELL, heights[j * gw + i], origin.y + j * CELL))
					normals.append(Vector3(_h(i - 1, j) - _h(i + 1, j), 2.0 * CELL, _h(i, j - 1) - _h(i, j + 1)).normalized())
			for j in j1 - cj:
				for i in i1 - ci:
					var a := j * stride + i
					idx.append_array([a, a + 1, a + stride, a + 1, a + stride + 1, a + stride])
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts
			arrays[Mesh.ARRAY_NORMAL] = normals
			arrays[Mesh.ARRAY_INDEX] = idx
			var mesh := ArrayMesh.new()
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mi := MeshInstance3D.new()
			mi.name = "Terrain_%d_%d" % [ci / CHUNK, cj / CHUNK]
			mi.mesh = mesh
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			parent.add_child(mi)
