extends RefCounted
## 사용자 제공 감시탑 GLB(assets/structures/watchtower/watchtower.glb). 한 메시에 1단계(지붕 없는 망루)와
## 2단계(지붕·깃발 탑)가 나란히 들어 있어, 삼각형 중심 X로 둘을 나눠 각자 발밑 중심(0,0,0)에 맞춘 메시를 만든다.
## 원본은 1×0.78×0.89로 정규화돼 있다. MODEL_SCALE 6.5 → 1단계 약 2.7×3.0m(높이), 2단계 약 3.1×5.1m로
## 산장(4.9×5.9, 굴뚝 5.2m)·공터(3.2m) 크기에 맞춘다. 칠은 산장과 같은 user_cottage 셰이더(원본 텍스처 유지).

const GLB := "res://assets/structures/watchtower/watchtower.glb"
const SHADER := preload("res://shaders/user_cottage.gdshader")
const MODEL_SCALE := 6.5
const SPLIT_X := -0.03          # 두 탑 사이 빈 구간(-0.075~0.025) 가운데
const FLOOR_Y := 0.32           # 두 탑 공통 발판 윗면(모델 단위). 높이별 위쪽 면 면적 측정값
## 단계별 발판 위 사냥꾼 자리(탑 발밑 중심 기준, 미터). 2단계는 세 명.
const PERCHES := [
	[Vector3(0.0, 0.0, 0.0)],
	[Vector3(-0.55, 0.0, 0.35), Vector3(0.55, 0.0, 0.35), Vector3(0.0, 0.0, -0.5)],
]

static var _meshes: Array = []   # [1단계 ArrayMesh, 2단계 ArrayMesh]
static var _sizes: Array = []    # 각 탑의 배율 적용 전 크기
static var _material: ShaderMaterial


static func floor_height() -> float:
	return FLOOR_Y * MODEL_SCALE


## 단계(1·2)별 배율 적용 크기(m).
static func size_of(level: int) -> Vector3:
	_ensure()
	return _sizes[level - 1] * MODEL_SCALE


## 단계(1·2) 탑의 시각 노드. 발밑 중심이 원점이다.
static func build(level: int) -> Node3D:
	_ensure()
	var root := Node3D.new()
	root.name = "WatchtowerL%d" % level
	var mi := MeshInstance3D.new()
	mi.name = "Tower"
	mi.mesh = _meshes[level - 1]
	mi.material_override = _material
	mi.scale = Vector3.ONE * MODEL_SCALE
	root.add_child(mi)
	return root


static func _ensure() -> void:
	if not _meshes.is_empty():
		return
	var scene: PackedScene = load(GLB)
	var inst: Node3D = scene.instantiate()
	var src: MeshInstance3D = inst.find_children("*", "MeshInstance3D", true, false)[0]
	var arrays: Array = src.mesh.surface_get_arrays(0)
	var source_mat: StandardMaterial3D = src.mesh.surface_get_material(0)
	_material = ShaderMaterial.new()
	_material.resource_name = "WatchtowerOriginalPaint"
	_material.shader = SHADER
	_material.set_shader_parameter("cottage_paint", source_mat.albedo_texture)
	for side in [-1.0, 1.0]:
		var pair := _split(arrays, side)
		_meshes.append(pair[0])
		_sizes.append(pair[1])
	inst.free()


## side −1 = 1단계(X < SPLIT_X), +1 = 2단계. 반환 [ArrayMesh, 크기].
static func _split(a: Array, side: float) -> Array:
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var keep := PackedInt32Array()
	var used := {}
	var lo := Vector3(INF, INF, INF)
	var hi := -lo
	for t in range(0, idx.size() - 2, 3):
		var c := (v[idx[t]] + v[idx[t + 1]] + v[idx[t + 2]]) / 3.0
		if signf(c.x - SPLIT_X) != side:
			continue
		for k in 3:
			keep.append(idx[t + k])
			used[idx[t + k]] = true
			lo = lo.min(v[idx[t + k]])
			hi = hi.max(v[idx[t + k]])
	# 쓰는 정점만 남기고 X·Z를 발밑 중심으로 옮긴다.
	var shift := Vector3((lo.x + hi.x) * 0.5, lo.y, (lo.z + hi.z) * 0.5)
	var remap := {}
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	var nv := PackedVector3Array()
	var nn := PackedVector3Array()
	var nuv := PackedVector2Array()
	var nt := PackedFloat32Array()
	var normals: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var tangents = a[Mesh.ARRAY_TANGENT]
	var keys: Array = used.keys()
	keys.sort()
	for old in keys:
		remap[old] = nv.size()
		nv.append(v[old] - shift)
		nn.append(normals[old])
		nuv.append(uvs[old])
		if tangents != null:
			for k in 4:
				nt.append(tangents[old * 4 + k])
	var ni := PackedInt32Array()
	for i in keep:
		ni.append(remap[i])
	out[Mesh.ARRAY_VERTEX] = nv
	out[Mesh.ARRAY_NORMAL] = nn
	out[Mesh.ARRAY_TEX_UV] = nuv
	if tangents != null:
		out[Mesh.ARRAY_TANGENT] = nt
	out[Mesh.ARRAY_INDEX] = ni
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, out)
	return [mesh, hi - lo]
