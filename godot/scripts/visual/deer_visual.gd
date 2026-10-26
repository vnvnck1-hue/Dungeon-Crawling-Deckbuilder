extends Node3D
## 사슴 시각 모델. 게임 판정은 actors/wild_animal.gd 그대로이고 이 노드는 표시와 모션만 맡는다.
## - 사용자 제공 Tripo GLB(assets/animals/deer/deer.glb, 뼈대·애니메이션 없음, 부품 11개)는 몸이 비스듬히(약 62°) 놓이고
##   고개가 왼쪽으로 돌아가 있어, 몸통 주축으로 +Z 정면을 맞추고 머리 부품은 목 위에서 따로 펴 준다.
## - 뼈대 하나(몸통·목·머리·귀 2·꼬리·다리 4×2마디)에 모든 부품을 스키닝한다: 몸통 메시는 목·꼬리 구간을 부드럽게 나눠 싣고,
##   다리 메시는 무릎에서 나눈다. 머리·뿔·귀는 머리/귀 뼈에 그대로 붙는다.
## - 모션: 걷기(뒤왼→앞왼→뒤오→앞오 4박자, 들 때 무릎 접기, 목 끄덕임), 달아나기(앞뒤 한 쌍씩 뛰는 바운드 + 몸 앞뒤 흔들림 +
##   흰 꼬리 치켜들기), 풀 뜯기(목을 땅까지 내렸다 들어 씹으며 두리번), 경계(목 꼿꼿, 귀 세우기), 숨쉬기, 귀 털기, 꼬리 까딱, 피격 움찔.
## - 소유자는 speed·grazing·alarmed 만 매 프레임 넣고, 사건은 flinch()로 알린다. 노드 구조 Body/Head 는 기존 사슴과 같다.

const GLB := "res://assets/animals/deer/deer.glb"
const SpiderVisual := preload("res://scripts/visual/spider_visual.gd")

## 원본 → 게임 좌표: Y축 62° 회전으로 몸통 주축을 +Z에 맞추고, 몸 가운데를 원점으로 옮긴 뒤 키울 비율
const ORIENT_DEG := 62.0
const CENTER_SHIFT := Vector3(0.078, 0.0, 0.0)
const MODEL_SCALE := 1.55
## 머리 부품(머리·뿔·귀·눈 반사)은 왼쪽으로 돌아가 있다: 머리 피벗 기준으로 이만큼 돌려 정면을 보게 한다
const HEAD_YAW_FIX_DEG := -24.0
const BODY_PART := "tripo_part_0"
const HEAD_PARTS := ["tripo_part_2", "tripo_part_3", "tripo_part_5", "tripo_part_10"]
const EAR_PARTS := {"EarL": "tripo_part_8", "EarR": "tripo_part_7"}
const LEG_PARTS := {"FL": "tripo_part_9", "FR": "tripo_part_4", "BL": "tripo_part_6", "BR": "tripo_part_1"}
## 목: 어깨(NECK_BASE) → 목 꼭대기(머리 피벗) 축을 따라 0~1로 재서, 뿌리부터 목 아래 뼈·위 뼈로 서서히 넘긴다(스케일 전 좌표).
## 가슴 아래쪽(NECK_Y 아래)은 몸통에 남긴다.
const NECK_BASE := Vector3(0.0, 0.58, 0.0)
const NECK_T := Vector2(-0.05, 0.35)     # 몸통 → 목 아래 뼈
const NECK2_T := Vector2(0.45, 0.75)     # 목 아래 → 목 위 뼈
const NECK_Y := Vector2(0.45, 0.58)
## 꼬리: 엉덩이 끝에서 뒤로 늘어진 부분(뒤쪽 z만으로 가른다)
const TAIL_Z := Vector2(-0.435, -0.47)
const TAIL_TOP_Y := 0.40
const KNEE_FRAC := 0.5      # 다리 높이에서 무릎 위치 비율
const KNEE_BLEND := 0.03

# 보행
const WALK_STRIDE := 0.9
const RUN_STRIDE := 1.7
const RUN_FROM := 1.2
const RUN_FULL := 2.0
## 걷기: 뒤왼 0 → 앞왼 0.25 → 뒤오 0.5 → 앞오 0.75 (사족 보행 순서), 달리기: 뒤 한 쌍 → 앞 한 쌍 바운드
const WALK_PHASE := {"BL": 0.0, "FL": 0.25, "BR": 0.5, "FR": 0.75}
const RUN_PHASE := {"BL": 0.0, "BR": 0.06, "FL": 0.5, "FR": 0.56}
const WALK_DUTY := 0.66
const RUN_DUTY := 0.42

static var _cache: Dictionary = {}

# 소유자가 매 프레임 넣는 상태
var speed := 0.0
var grazing := false
var alarmed := false

var body: Node3D
var head: Node3D
var skeleton: Skeleton3D
var gait_phase := 0.0
var neck_pitch := 0.0
var head_pitch := 0.0
var head_yaw := 0.0
var leg_angle := {}        # 다리 id -> 윗마디 각(검증용)
var knee_angle := {}

var _rig: Dictionary
var _bone := {}
var _leg_bones: Array = []
var _t := 0.0
var _spd := 0.0
var _rng := RandomNumberGenerator.new()
var _prev_yaw := 0.0
var _lean := 0.0
var _flinch := 0.0
var _flinch_side := 1.0
var _graze_t := 0.0
var _graze_up := false
var _look_t := 0.0
var _look := Vector2.ZERO
var _ear_flick := {"EarL": 0.0, "EarR": 0.0}
var _ear_pose := {}
var _ear_next := 2.0
var _tail_flick := 0.0
var _tail_next := 3.0
var _tail_raise := 0.0


func _init() -> void:
	name = "DeerVisual"
	_rng.randomize()
	_rig = _build_rig()
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	body.add_child(skeleton)
	for b: Array in _rig["bones"]:
		var i := skeleton.get_bone_count()
		skeleton.add_bone(b[0])
		if b[1] != "":
			skeleton.set_bone_parent(i, _bone[b[1]])
		_bone[b[0]] = i
		skeleton.set_bone_rest(i, Transform3D(Basis(), b[2]))
	skeleton.reset_bone_poses()
	for key in _rig["meshes"]:
		var mi := MeshInstance3D.new()
		mi.name = _rig["labels"][key]
		mi.mesh = _rig["meshes"][key]
		mi.skin = _rig["skin"]
		skeleton.add_child(mi)
		mi.skeleton = NodePath("..")
	# Head 노드: 머리 뼈 위치를 따라가는 표시용 기준점(사냥 화살 표적·HP 막대 등 외부 참조와 기존 구조 호환)
	head = Node3D.new()
	head.name = "Head"
	body.add_child(head)
	_graze_t = _rng.randf_range(0.0, 2.0)
	_look_t = _rng.randf_range(0.5, 2.0)
	_ear_next = _rng.randf_range(1.0, 4.0)
	_tail_next = _rng.randf_range(1.5, 5.0)
	_apply_pose()


func _ready() -> void:
	_prev_yaw = rotation.y


## 놀라 움찔: 목을 젖히고 몸이 한쪽으로 휘청, 귀가 뒤로 접힌다.
func flinch() -> void:
	_flinch = 1.0
	_flinch_side = -1.0 if _rng.randf() < 0.5 else 1.0


func _process(delta: float) -> void:
	_t += delta
	var k := 1.0 - exp(-delta * 7.0)
	_spd = lerpf(_spd, speed, 1.0 - exp(-delta * 8.0))
	var run := smoothstep(RUN_FROM, RUN_FULL, _spd)
	var moving := smoothstep(0.05, 0.3, _spd)
	var stride := lerpf(WALK_STRIDE, RUN_STRIDE, run)
	gait_phase = fposmod(gait_phase + delta * _spd / stride, 1.0)
	var ph := gait_phase * TAU
	_flinch = move_toward(_flinch, 0.0, delta * 2.5)
	var yaw_rate := wrapf(rotation.y - _prev_yaw, -PI, PI) / maxf(delta, 0.001)
	_prev_yaw = rotation.y
	_lean = lerpf(_lean, clampf(-yaw_rate * 0.025, -0.12, 0.12) * moving, k)

	# 다리: 디딤(발이 뒤로 밀림) → 들기(무릎 접고 앞으로)
	var duty := lerpf(WALK_DUTY, RUN_DUTY, run)
	var amp := lerpf(0.32, 0.6, run) * moving
	for id in LEG_PARTS:
		var p := fposmod(gait_phase - lerpf(WALK_PHASE[id], RUN_PHASE[id], run), 1.0)   # 위상값이 클수록 늦게 든다
		var a := 0.0
		var flex := 0.0
		if p < duty:
			a = lerpf(-amp, amp, p / duty)
		else:
			var u := (p - duty) / (1.0 - duty)
			a = lerpf(amp, -amp, smoothstep(0.0, 1.0, u))
			flex = sin(u * PI) * lerpf(0.9, 1.4, run) * moving
		leg_angle[id] = a
		knee_angle[id] = flex if id.begins_with("F") else -flex * 0.8   # 앞무릎은 뒤로, 뒷다리 관절은 앞으로 접힌다

	# 몸통: 걷기는 살짝 오르내림, 달리기는 크게 뛰며 앞뒤로 흔들린다
	var walk_bob := (0.5 - 0.5 * cos(ph * 2.0)) * 0.025
	var run_bob := maxf(sin(ph - 0.3), 0.0) * 0.16
	body.position.y = lerpf(walk_bob, run_bob, run) * moving
	body.rotation.x = sin(ph + 0.6) * 0.12 * run
	body.rotation.z = sin(ph) * 0.02 * moving * (1.0 - run) + _lean + sin(_flinch * PI) * 0.12 * _flinch_side

	# 목·머리
	var neck := 0.0
	var hp := 0.0
	var yaw := 0.0
	if alarmed or run > 0.3:
		neck = -0.25 + sin(ph) * 0.08 * run
		hp = 0.05
		yaw = 0.0
	elif moving > 0.5:
		neck = 0.08 + sin(ph * 2.0) * 0.05
		hp = 0.0
	elif grazing:
		_graze_t -= delta
		if _graze_t <= 0.0:
			_graze_up = not _graze_up
			_graze_t = _rng.randf_range(1.2, 2.4) if _graze_up else _rng.randf_range(2.0, 4.0)
		if _graze_up:   # 고개 들고 씹으며 두리번
			neck = -0.1
			hp = sin(_t * 11.0) * 0.03
			yaw = sin(_t * 0.8) * 0.4
		else:            # 목을 땅까지 내려 뜯기
			neck = 1.45
			hp = -0.35 + absf(sin(_t * 6.0)) * 0.08   # 목을 깊이 숙이고 머리는 살짝 세워 주둥이가 땅을 향한다
			yaw = sin(_t * 0.5) * 0.15
	else:
		_look_t -= delta
		if _look_t <= 0.0:
			_look_t = _rng.randf_range(1.5, 4.0)
			_look = Vector2(_rng.randf_range(-0.15, 0.2), _rng.randf_range(-0.5, 0.5))
		neck = _look.x
		yaw = _look.y
	neck -= sin(_flinch * PI) * 0.5
	neck_pitch = lerpf(neck_pitch, neck, 1.0 - exp(-delta * 4.0))
	head_pitch = lerpf(head_pitch, hp, k)
	head_yaw = lerpf(head_yaw, yaw, 1.0 - exp(-delta * 3.5))

	# 귀
	_ear_next -= delta
	if _ear_next <= 0.0:
		_ear_next = _rng.randf_range(1.2, 4.5)
		_ear_flick["EarL" if _rng.randf() < 0.5 else "EarR"] = 1.0
	var back := clampf(_flinch + run * 0.6, 0.0, 1.0)
	var perk := 1.0 if alarmed else 0.0
	for id in _ear_flick:
		var s := 1.0 if id == "EarL" else -1.0
		_ear_flick[id] = move_toward(_ear_flick[id], 0.0, delta * 4.5)
		var f: float = _ear_flick[id]
		var target := Vector3(-perk * 0.2, (back * 0.8 - perk * 0.3) * s, (sin(f * PI * 2.0) * 0.5 * f + perk * 0.25 - back * 0.2) * s)
		var pose: Vector3 = _ear_pose.get(id, Vector3.ZERO)
		_ear_pose[id] = pose.lerp(target, 1.0 - exp(-delta * 14.0))

	# 꼬리: 가끔 까딱, 달아날 땐 흰 꼬리를 치켜든다
	_tail_next -= delta
	if _tail_next <= 0.0:
		_tail_next = _rng.randf_range(2.0, 6.0)
		_tail_flick = 1.0
	_tail_flick = move_toward(_tail_flick, 0.0, delta * 1.8)
	_tail_raise = lerpf(_tail_raise, 1.0 if (alarmed or run > 0.3) else 0.0, k)
	var breath := sin(_t * 1.9) * 0.01 * (1.0 - moving * 0.7)
	skeleton.set_bone_pose_scale(0, Vector3(1.0 + breath, 1.0 + breath * 0.6, 1.0))
	_apply_pose()


func _apply_pose() -> void:
	if _leg_bones.is_empty():   # 다리 뼈 번호: 매 프레임 이름을 이어 붙여 찾지 않는다
		for id in LEG_PARTS:
			_leg_bones.append([id, _bone[id + "_upper"], _bone[id + "_lower"]])
	for lb in _leg_bones:
		skeleton.set_bone_pose_rotation(lb[1], Quaternion(Vector3.RIGHT, leg_angle.get(lb[0], 0.0)))
		skeleton.set_bone_pose_rotation(lb[2], Quaternion(Vector3.RIGHT, knee_angle.get(lb[0], 0.0)))
	# 목은 두 마디로 나눠 굽힌다(뿌리 쪽을 조금 더)
	skeleton.set_bone_pose_rotation(_bone["Neck"], Quaternion.from_euler(Vector3(neck_pitch * 0.55, head_yaw * 0.25, 0.0)))
	skeleton.set_bone_pose_rotation(_bone["Neck2"], Quaternion.from_euler(Vector3(neck_pitch * 0.45, head_yaw * 0.25, 0.0)))
	skeleton.set_bone_pose_rotation(_bone["Head"], Quaternion.from_euler(Vector3(head_pitch, head_yaw * 0.5, 0.0)))
	for id in _ear_flick:
		skeleton.set_bone_pose_rotation(_bone[id], Quaternion.from_euler(_ear_pose.get(id, Vector3.ZERO)))
	skeleton.set_bone_pose_rotation(_bone["Tail"], Quaternion(Vector3.RIGHT, _tail_raise * 0.4 + sin(_tail_flick * PI * 3.0) * 0.4 * _tail_flick))
	head.transform = skeleton.get_bone_global_pose(_bone["Head"])


# ── 리그 구성(한 번만) ─────────────────────────────────────────

func _build_rig() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var orient := Transform3D(Basis(Vector3.UP, deg_to_rad(ORIENT_DEG)), Vector3.ZERO)
	orient = Transform3D(Basis(), CENTER_SHIFT) * orient
	var scene: Node3D = (load(GLB) as PackedScene).instantiate()
	var raw := {}
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var xf := orient * _local_to(scene, mi)
		var arr: Array = mi.mesh.surface_get_arrays(0)
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in pos.size():
			pos[i] = xf * pos[i]
			nor[i] = (xf.basis * nor[i]).normalized()
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
		arr[Mesh.ARRAY_TANGENT] = null
		raw[str(mi.name)] = {"arrays": arr, "material": mi.mesh.surface_get_material(0)}
	scene.free()

	# 머리 피벗 = 목 꼭대기(몸통 메시에서 가장 높은 앞쪽 정점들 가운데). 머리 부품을 여기서 펴 준다.
	var body_pos: PackedVector3Array = raw[BODY_PART]["arrays"][Mesh.ARRAY_VERTEX]
	var top := _max_axis(body_pos, 1)
	var head_pivot := _center(_filter(body_pos, func(v: Vector3) -> bool: return v.y > top - 0.06 and v.z > 0.1))
	var fix := Transform3D(Basis(Vector3.UP, deg_to_rad(HEAD_YAW_FIX_DEG)), Vector3.ZERO)
	fix = Transform3D(Basis(), head_pivot) * fix * Transform3D(Basis(), -head_pivot)
	for key in HEAD_PARTS + EAR_PARTS.values():
		var arr: Array = raw[key]["arrays"]
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in pos.size():
			pos[i] = fix * pos[i]
			nor[i] = (fix.basis * nor[i]).normalized()
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
	# 머리를 편 뒤 좌우 가운데를 목 위에 맞춘다
	var head_c := _center(raw["tripo_part_2"]["arrays"][Mesh.ARRAY_VERTEX])
	var head_dx := head_pivot.x - head_c.x
	for key in HEAD_PARTS + EAR_PARTS.values():
		var pos: PackedVector3Array = raw[key]["arrays"][Mesh.ARRAY_VERTEX]
		for i in pos.size():
			pos[i].x += head_dx
		raw[key]["arrays"][Mesh.ARRAY_VERTEX] = pos
	# 크기
	for key in raw:
		var pos: PackedVector3Array = raw[key]["arrays"][Mesh.ARRAY_VERTEX]
		for i in pos.size():
			pos[i] *= MODEL_SCALE
		raw[key]["arrays"][Mesh.ARRAY_VERTEX] = pos
	head_pivot *= MODEL_SCALE
	var s := MODEL_SCALE

	# 뼈: [이름, 부모, 모델 좌표 위치]
	var neck_base := NECK_BASE * s
	var neck_axis := head_pivot - neck_base
	var bones: Array = [["Body", "", Vector3.ZERO], ["Neck", "Body", neck_base],
		["Neck2", "Neck", neck_base + neck_axis * 0.6], ["Head", "Neck2", head_pivot]]
	for id in EAR_PARTS:
		var p: PackedVector3Array = raw[EAR_PARTS[id]]["arrays"][Mesh.ARRAY_VERTEX]
		var inner := INF
		for v in p:
			inner = minf(inner, absf(v.x - head_pivot.x))
		bones.append([id, "Head", _center(_filter(p, func(v: Vector3) -> bool: return absf(v.x - head_pivot.x) < inner + 0.03 * s))])
	# 꼬리 뿌리: 엉덩이 끝 윗부분(정점은 이미 크기를 키운 좌표다)
	var tail_pts := _filter(raw[BODY_PART]["arrays"][Mesh.ARRAY_VERTEX], func(v: Vector3) -> bool: return v.z < TAIL_Z.x * s and v.y > TAIL_TOP_Y * s)
	var tail_c := _center(tail_pts)
	bones.append(["Tail", "Body", Vector3(tail_c.x, _max_axis(tail_pts, 1) - 0.02 * s, TAIL_Z.x * s)])
	var knees := {}
	for id in LEG_PARTS:
		var p: PackedVector3Array = raw[LEG_PARTS[id]]["arrays"][Mesh.ARRAY_VERTEX]
		var c := _center(p)
		var h := _max_axis(p, 1)
		var knee := h * KNEE_FRAC
		knees[id] = knee
		var hip := Vector3(c.x, h - 0.04 * s, c.z)
		var foot := _center(_filter(p, func(v: Vector3) -> bool: return v.y < 0.05 * s))
		bones.append([id + "_upper", "Body", hip])
		bones.append([id + "_lower", id + "_upper", Vector3(lerpf(foot.x, hip.x, KNEE_FRAC), knee, lerpf(foot.z, hip.z, KNEE_FRAC))])
	var index := {}
	var global_rest := {}
	for i in bones.size():
		index[bones[i][0]] = i
		global_rest[bones[i][0]] = bones[i][2]
	# Skeleton 은 부모 기준 rest 를 받으므로 위치를 부모 기준으로 바꿔 둔다
	var local_bones: Array = []
	for b: Array in bones:
		var parent_pos: Vector3 = global_rest[b[1]] if b[1] != "" else Vector3.ZERO
		local_bones.append([b[0], b[1], b[2] - parent_pos])
	var skin := Skin.new()
	for b: Array in bones:
		skin.add_bind(index[b[0]], Transform3D(Basis(), b[2]).affine_inverse())

	var meshes := {}
	var labels := {}
	for key in raw:
		var arr: Array = raw[key]["arrays"]
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var bi := PackedInt32Array()
		var bw := PackedFloat32Array()
		for v in pos:
			var b0 := 0
			var b1 := 0
			var w1 := 0.0
			if key == BODY_PART:
				var wt := smoothstep(TAIL_Z.x * s, TAIL_Z.y * s, v.z)
				if wt > 0.0:
					bi.append_array([0, index["Tail"], 0, 0])
					bw.append_array([1.0 - wt, wt, 0.0, 0.0])
					continue
				# 목 축 위치 t(0 = 어깨, 1 = 목 꼭대기)로 몸통 → 목 아래 → 목 위 → 머리 순으로 넘긴다
				var t := (v - neck_base).dot(neck_axis) / neck_axis.length_squared()
				var on_neck := smoothstep(NECK_T.x, NECK_T.y, t) * smoothstep(NECK_Y.x * s, NECK_Y.y * s, v.y)
				var upper := smoothstep(NECK2_T.x, NECK2_T.y, t) * on_neck
				var near_head := smoothstep(0.95, 1.15, t) * on_neck
				bi.append_array([0, index["Neck"], index["Neck2"], index["Head"]])
				bw.append_array([1.0 - on_neck, on_neck - upper, upper - near_head, near_head])
				continue
			elif key in HEAD_PARTS:
				b0 = index["Head"]
			elif key in EAR_PARTS.values():
				b0 = index[EAR_PARTS.find_key(key)]
			else:
				var id: String = LEG_PARTS.find_key(key)
				b0 = index[id + "_upper"]
				b1 = index[id + "_lower"]
				w1 = smoothstep(knees[id] + KNEE_BLEND * s, knees[id] - KNEE_BLEND * s, v.y)
			bi.append_array([b0, b1, 0, 0])
			bw.append_array([1.0 - w1, w1, 0.0, 0.0])
		arr[Mesh.ARRAY_BONES] = bi
		arr[Mesh.ARRAY_WEIGHTS] = bw
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(0, _paint(raw[key]["material"], arr))
		meshes[key] = m
		if key == BODY_PART: labels[key] = "DeerBody"
		elif key == "tripo_part_2": labels[key] = "DeerHead"
		elif key in HEAD_PARTS: labels[key] = "Antler" if key != "tripo_part_10" else "EyeGlint"
		elif key in EAR_PARTS.values(): labels[key] = EAR_PARTS.find_key(key)
		else: labels[key] = "Leg" + LEG_PARTS.find_key(key)
	_cache = {"bones": local_bones, "skin": skin, "meshes": meshes, "labels": labels}
	return _cache


## 페인터리 재질: 바탕색을 부품 텍스처 평균색으로 두고 텍스처는 평균 밝기로 나눈다(거미와 같은 방식).
## 거미·양과 달리 밝은 쪽으로 끌어올리지 않는다: 사슴의 갈색 털이 분홍빛으로 바래지 않게.
static func _paint(src: Material, arrays: Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SpiderVisual.PAINT
	var avg := Color(1, 1, 1)
	if src is StandardMaterial3D and src.albedo_texture != null:
		m.set_shader_parameter("paint_texture", src.albedo_texture)
		m.set_shader_parameter("use_texture", true)
		avg = SpiderVisual._uv_average(src.albedo_texture, arrays[Mesh.ARRAY_TEX_UV])
		var grey := avg.r * 0.3 + avg.g * 0.59 + avg.b * 0.11
		avg = avg.lerp(Color(grey, grey, grey), 0.22)   # 툰 화면에서 주황빛으로 뜨지 않게 채도를 조금 낮춘다
	var luma := maxf(avg.r * 0.3 + avg.g * 0.59 + avg.b * 0.11, 0.12)
	m.set_shader_parameter("base_color", avg)
	m.set_shader_parameter("paint_gain", minf(1.0 / luma, 4.0))
	m.set_shader_parameter("painted_fill", 0.13)
	return m


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
