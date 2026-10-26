extends Node3D
## 양 시각 모델. 게임 판정은 actors/sheep.gd 그대로이고 이 노드는 표시와 모션만 맡는다.
## - 사용자 제공 Tripo GLB(assets/animals/sheep/sheep.glb, 뼈대·애니메이션 없음, 부품 9개)를 읽어 +Z를 바라보게 돌린다.
##   머리는 몸통 메시에 붙어 있어 목 기준 2본 뼈대(몸통·머리)로 자동 스키닝하고, 귀·정수리 털·꼬리·다리 4개는 부품마다 피벗을 잡는다.
## - 모션: 걷기(대각 다리 교대 + 끄덕임), 달아나기(앞뒤 다리가 모여 뛰는 바운드 + 몸 흔들기), 풀 뜯기(고개 숙여 뜯다가 들고 씹기),
##   두리번(정지 중 고개 돌리기), 숨쉬기, 귀 털기·꼬리 흔들기, 털 깎는 동안 떨기, 피격 움찔, 울 때 고개 들기, 돌 때 몸 기울기.
## - 소유자(sheep.gd)는 speed·grazing·alarmed·held·shearing 만 매 프레임 넣고, 사건은 flinch()·bleat()로 알린다.
## 노드 구조 Body/Head 는 기존 양과 같다(검은 양 눈 장식이 Head 아래에 붙는다).

const GLB := "res://assets/animals/sheep/sheep.glb"
const SpiderVisual := preload("res://scripts/visual/spider_visual.gd")

## 원본은 -X를 바라본다. Y축 +90°로 돌리면 머리가 +Z로 온다(x' = z, z' = -x).
const ORIENT := Basis(Vector3.UP, PI * 0.5)
const MODEL_SCALE := 1.0
const BODY_PART := "tripo_part_0"
const TAIL_PART := "tripo_part_1"
const TOPKNOT_PART := "tripo_part_6"
## 다리: 양 기준 왼쪽(+X)·오른쪽, 앞(+Z)·뒤
const LEG_PARTS := {"FL": "tripo_part_2", "FR": "tripo_part_3", "BL": "tripo_part_4", "BR": "tripo_part_5"}
const EAR_PARTS := {"EarL": "tripo_part_8", "EarR": "tripo_part_7"}
## 목 피벗과 머리 가중치 구간(돌린 뒤 좌표). 몸통 단면상 z 0.24 앞쪽, 높이 0.30 위가 머리다.
const NECK := Vector3(0.0, 0.48, 0.24)
const HEAD_Z := Vector2(0.24, 0.34)
const HEAD_Y := Vector2(0.30, 0.42)
## 검은 양 눈 장식 위치(Head 기준)
const EYE_OFFSET := Vector3(0.085, 0.12, 0.15)

# 보행: 한 주기에 나아가는 거리(m)
const WALK_STRIDE := 0.30
const RUN_STRIDE := 0.52
const RUN_FROM := 0.6
const RUN_FULL := 1.0
## 다리 위상(주기 비율): 걷기는 대각 교대, 달리기는 앞 한 쌍·뒤 한 쌍이 거의 함께 딛는 바운드
const WALK_PHASE := {"FL": 0.0, "BR": 0.0, "FR": 0.5, "BL": 0.5}
const RUN_PHASE := {"FL": 0.0, "FR": 0.08, "BL": 0.5, "BR": 0.58}

static var _cache: Dictionary = {}

# 소유자가 매 프레임 넣는 상태
var speed := 0.0
var grazing := false
var alarmed := false
var held := false
var shearing := false

var body: Node3D
var head: Node3D
var tail: Node3D
var skeleton: Skeleton3D
var legs: Dictionary = {}
var ears: Dictionary = {}
var gait_phase := 0.0
var head_pitch := 0.0
var head_yaw := 0.0
var is_black := false

var _rig: Dictionary
var _t := 0.0
var _spd := 0.0
var _rng := RandomNumberGenerator.new()
var _prev_yaw := 0.0
var _lean := 0.0
var _flinch := 0.0
var _flinch_side := 1.0
var _bleat := 0.0
var _graze_t := 0.0
var _graze_up := false
var _look_t := 0.0
var _look := Vector2.ZERO
var _ear_flick := {"EarL": 0.0, "EarR": 0.0}
var _ear_next := 2.0
var _wag := 0.0
var _wag_next := 3.0
var _ear_pose := {}
var _tail_raise := 0.0


func _init() -> void:
	name = "SheepVisual"
	_rng.randomize()
	_rig = _build_rig()
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	body.add_child(skeleton)
	skeleton.add_bone("Body")
	skeleton.add_bone("Head")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_rest(1, Transform3D(Basis(), NECK))
	skeleton.reset_bone_poses()
	var wool := MeshInstance3D.new()
	wool.name = "WoolBody"
	wool.mesh = _rig["body_mesh"]
	wool.skin = _rig["skin"]
	skeleton.add_child(wool)
	wool.skeleton = NodePath("..")
	head = Node3D.new()
	head.name = "Head"
	head.position = NECK
	body.add_child(head)
	_part(head, "WoolTopknot", TOPKNOT_PART, NECK)
	for id in EAR_PARTS:
		var pivot: Vector3 = _rig["pivots"][id]
		var ear := Node3D.new()
		ear.name = id
		ear.position = pivot - NECK
		head.add_child(ear)
		_part(ear, "Ear", EAR_PARTS[id], pivot)
		ears[id] = ear
	tail = Node3D.new()
	tail.name = "Tail"
	tail.position = _rig["pivots"]["Tail"]
	body.add_child(tail)
	_part(tail, "WoolTail", TAIL_PART, tail.position)
	for id in LEG_PARTS:
		var leg := Node3D.new()
		leg.name = "Leg" + id
		leg.position = _rig["pivots"][id]
		body.add_child(leg)
		_part(leg, "Leg", LEG_PARTS[id], leg.position)
		legs[id] = leg
	_graze_t = _rng.randf_range(0.0, 2.0)
	_look_t = _rng.randf_range(0.5, 2.0)
	_ear_next = _rng.randf_range(1.0, 4.0)
	_wag_next = _rng.randf_range(1.5, 5.0)


func _ready() -> void:
	_prev_yaw = rotation.y


func _part(parent: Node3D, label: String, key: String, pivot: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = label
	mi.mesh = _rig["parts"][key]
	mi.position = -pivot   # 메시 좌표는 모델 기준이므로 부모 피벗(모델 좌표)만큼 되돌린다
	parent.add_child(mi)
	return mi


## 놀라 움찔: 고개를 젖히고 몸이 한쪽으로 휘청, 귀가 뒤로 접힌다.
func flinch() -> void:
	_flinch = 1.0
	_flinch_side = -1.0 if _rng.randf() < 0.5 else 1.0


## 울 때 고개를 들고 잠깐 멈춘다.
func bleat() -> void:
	_bleat = 1.0


## 검은 양: 텍스처 명암(검은 얼굴·흰 털)은 살리고 바탕색만 어둡게 바꾼다. 공유 재질은 건드리지 않는다.
func set_black() -> void:
	is_black = true
	for mi: MeshInstance3D in find_children("*", "MeshInstance3D", true, false):
		var src := mi.mesh.surface_get_material(0) as ShaderMaterial
		if src == null:
			continue
		var m := src.duplicate() as ShaderMaterial
		var tone := Color("4a3f5e") if mi.name.begins_with("Wool") else Color("2a2436")
		m.set_shader_parameter("base_color", tone)
		m.set_shader_parameter("paint_gain", 1.6)
		mi.material_override = m


## 검은 양 눈 장식의 Head 기준 위치(side = -1 오른쪽, 1 왼쪽)
func eye_local(side: float) -> Vector3:
	return Vector3(EYE_OFFSET.x * side, EYE_OFFSET.y, EYE_OFFSET.z)


func _process(delta: float) -> void:
	_t += delta
	var k := 1.0 - exp(-delta * 8.0)
	_spd = lerpf(_spd, speed, 1.0 - exp(-delta * 10.0))
	var run := smoothstep(RUN_FROM, RUN_FULL, _spd)
	var moving := smoothstep(0.03, 0.15, _spd)
	var stride := lerpf(WALK_STRIDE, RUN_STRIDE, run)
	gait_phase = fposmod(gait_phase + delta * _spd / stride, 1.0)
	var ph := gait_phase * TAU
	_flinch = move_toward(_flinch, 0.0, delta * 2.8)
	_bleat = move_toward(_bleat, 0.0, delta * 1.4)

	# 돌 때 바깥쪽으로 기울기
	var yaw_rate := wrapf(rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.001)
	_prev_yaw = rotation.y
	_lean = lerpf(_lean, clampf(-yaw_rate * 0.03, -0.12, 0.12) * moving, k)

	# 다리
	for id in legs:
		var off := lerpf(WALK_PHASE[id], RUN_PHASE[id], run) * TAU
		var amp := lerpf(0.5, 0.8, run) * moving
		var leg: Node3D = legs[id]
		leg.rotation.x = sin(ph + off) * amp
		leg.position.y = (_rig["pivots"][id] as Vector3).y + maxf(cos(ph + off), 0.0) * 0.015 * moving

	# 몸통: 걷기는 한 주기에 두 번 통통, 달리기는 크게 뛰어오르며 앞뒤로 흔들린다
	var walk_bob := (0.5 - 0.5 * cos(ph * 2.0)) * 0.022
	var run_bob := maxf(sin(ph + 0.6), 0.0) * 0.07
	body.position.y = lerpf(walk_bob, run_bob, run) * moving
	var shiver := sin(_t * 15.0) * 0.045 if shearing else 0.0
	body.rotation.z = sin(ph) * 0.035 * moving * (1.0 - run) + _lean + shiver \
		+ sin(_flinch * PI) * 0.16 * _flinch_side
	body.rotation.x = sin(ph - 0.4) * 0.11 * run
	# 숨쉬기(서 있을 때만 눈에 띄게)
	var breath := sin(_t * 2.3) * 0.012 * (1.0 - moving * 0.7)
	skeleton.set_bone_pose_scale(0, Vector3(1.0 + breath * 0.6, 1.0 + breath, 1.0))

	# 머리
	var pitch := 0.0
	var yaw := 0.0
	if held:
		pitch = 0.12 if shearing else -0.08
		yaw = sin(_t * 0.7) * 0.08
	elif alarmed or run > 0.3:
		pitch = -0.22 + sin(ph * 2.0) * 0.05 * moving
		yaw = 0.0
	elif moving > 0.5:
		pitch = 0.08 + sin(ph * 2.0) * 0.05
		yaw = 0.0
	elif grazing:
		_graze_t -= delta
		if _graze_t <= 0.0:
			_graze_up = not _graze_up
			_graze_t = _rng.randf_range(0.9, 1.6) if _graze_up else _rng.randf_range(1.8, 3.6)
		if _graze_up:   # 고개 들고 씹기
			pitch = 0.05 + sin(_t * 13.0) * 0.025
			yaw = sin(_t * 0.9) * 0.15
		else:            # 고개 숙여 뜯기
			pitch = 0.55 + absf(sin(_t * 7.0)) * 0.07
			yaw = sin(_t * 0.6) * 0.12
	else:
		_look_t -= delta
		if _look_t <= 0.0:
			_look_t = _rng.randf_range(1.2, 3.5)
			_look = Vector2(_rng.randf_range(-0.12, 0.15), _rng.randf_range(-0.4, 0.4))
		pitch = _look.x
		yaw = _look.y
	pitch = lerpf(pitch, -0.35, _bleat * (1.0 - _bleat) * 4.0) - sin(_flinch * PI) * 0.4
	head_pitch = lerpf(head_pitch, pitch, k)
	head_yaw = lerpf(head_yaw, yaw, 1.0 - exp(-delta * 5.0))
	head.rotation = Vector3(head_pitch, head_yaw, 0.0)
	skeleton.set_bone_pose_position(1, head.position)
	skeleton.set_bone_pose_rotation(1, head.quaternion)

	# 귀: 가끔 털고, 놀라면 뒤로 접고, 걸을 때 출렁
	_ear_next -= delta
	if _ear_next <= 0.0:
		_ear_next = _rng.randf_range(1.5, 5.0)
		var which := "EarL" if _rng.randf() < 0.5 else "EarR"
		_ear_flick[which] = 1.0
		if _rng.randf() < 0.3:
			_ear_flick["EarL" if which == "EarR" else "EarR"] = 1.0
	var back := clampf((1.0 if alarmed else 0.0) + _flinch, 0.0, 1.0)
	for id in ears:
		var s := 1.0 if id == "EarL" else -1.0
		_ear_flick[id] = move_toward(_ear_flick[id], 0.0, delta * 4.0)
		var f: float = _ear_flick[id]
		var flick := sin(f * PI * 2.0) * 0.45 * f
		var bounce := sin(ph * 2.0 + 0.8) * 0.12 * moving
		var target := Vector3(0.0, back * 0.7 * s, (flick + bounce - back * 0.25) * s)
		var pose: Vector3 = _ear_pose.get(id, Vector3.ZERO)
		pose = pose.lerp(target, 1.0 - exp(-delta * 14.0))
		_ear_pose[id] = pose
		ears[id].rotation = pose

	# 꼬리: 가끔 흔들고, 달아날 땐 치켜든다
	_wag_next -= delta
	if _wag_next <= 0.0:
		_wag_next = _rng.randf_range(2.0, 6.0)
		_wag = 1.0
	_wag = move_toward(_wag, 0.0, delta * 1.3)
	_tail_raise = lerpf(_tail_raise, 0.45 * maxf(run, 1.0 if alarmed else 0.0), k)
	tail.rotation = Vector3(_tail_raise + sin(ph * 2.0) * 0.1 * moving, sin(_t * 16.0) * 0.4 * _wag, 0.0)


# ── 리그 구성(한 번만) ─────────────────────────────────────────

func _build_rig() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var scene: Node3D = (load(GLB) as PackedScene).instantiate()
	var raw := {}
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := Transform3D(ORIENT.scaled(Vector3.ONE * MODEL_SCALE), Vector3.ZERO) * _local_to(scene, mi)
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in pos.size():
			pos[i] = xf * pos[i]
			nor[i] = (xf.basis * nor[i]).normalized()
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
		# 원본 LOD·탄젠트는 버린다(부품이 작아 필요 없고, 정점을 옮겨 탄젠트가 맞지 않는다)
		arr[Mesh.ARRAY_TANGENT] = null
		raw[str(mi.name)] = {"arrays": arr, "material": mi.mesh.surface_get_material(0)}
	scene.free()

	var out := {"parts": {}, "pivots": {}}
	for key in raw:
		if key == BODY_PART:
			continue
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, raw[key]["arrays"])
		m.surface_set_material(0, SpiderVisual._paint(raw[key]["material"], false, raw[key]["arrays"]))
		out["parts"][key] = m

	# 몸통: 목 앞·위쪽 정점을 머리 뼈에 부드럽게 나눠 싣는다
	var arr: Array = raw[BODY_PART]["arrays"]
	var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bones := PackedInt32Array()
	var weights := PackedFloat32Array()
	for v in pos:
		var w := smoothstep(HEAD_Z.x, HEAD_Z.y, v.z) * smoothstep(HEAD_Y.x, HEAD_Y.y, v.y)
		bones.append_array([0, 1, 0, 0])
		weights.append_array([1.0 - w, w, 0.0, 0.0])
	arr[Mesh.ARRAY_BONES] = bones
	arr[Mesh.ARRAY_WEIGHTS] = weights
	var body_mesh := ArrayMesh.new()
	body_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	body_mesh.surface_set_material(0, SpiderVisual._paint(raw[BODY_PART]["material"], false, arr))
	out["body_mesh"] = body_mesh
	var skin := Skin.new()
	skin.add_bind(0, Transform3D())
	skin.add_bind(1, Transform3D(Basis(), NECK).affine_inverse())
	out["skin"] = skin

	# 피벗: 다리는 윗면 가운데, 귀는 머리 쪽 끝, 꼬리는 몸에 붙는 앞쪽 끝
	for id in LEG_PARTS:
		var p: PackedVector3Array = raw[LEG_PARTS[id]]["arrays"][Mesh.ARRAY_VERTEX]
		var c := _center(p)
		out["pivots"][id] = Vector3(c.x, _max_axis(p, 1), c.z)
	for id in EAR_PARTS:
		var p: PackedVector3Array = raw[EAR_PARTS[id]]["arrays"][Mesh.ARRAY_VERTEX]
		var inner := INF
		for v in p:
			inner = minf(inner, absf(v.x))
		out["pivots"][id] = _center(_filter(p, func(v: Vector3) -> bool: return absf(v.x) < inner + 0.03))
	var tp: PackedVector3Array = raw[TAIL_PART]["arrays"][Mesh.ARRAY_VERTEX]
	var front := _max_axis(tp, 2)
	out["pivots"]["Tail"] = _center(_filter(tp, func(v: Vector3) -> bool: return v.z > front - 0.03))
	_cache = out
	return out


static func _local_to(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D()
	var cur: Node = n
	while cur != root and cur is Node3D:
		xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _center(p: PackedVector3Array) -> Vector3:
	var c := Vector3.ZERO
	for v in p:
		c += v
	return c / maxf(p.size(), 1)


static func _max_axis(p: PackedVector3Array, axis: int) -> float:
	var m := -INF
	for v in p:
		m = maxf(m, v[axis])
	return m


static func _filter(p: PackedVector3Array, keep: Callable) -> PackedVector3Array:
	var out := PackedVector3Array()
	for v in p:
		if keep.call(v):
			out.append(v)
	return out
