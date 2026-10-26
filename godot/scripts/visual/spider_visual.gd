extends Node3D
## 서리 거미(기본 적) 시각 모델. 게임 판정은 monster.gd 그대로이고 이 노드는 표시 전용이다.
## - Tripo GLB(부품 19개, 다리 6개)를 읽어 다리마다 표면 측지 거리로 중심선을 뽑고 관절 4개(밑마디·넓적마디·종아리·발끝마디)에
##   자동 스키닝한다. 원화 기준(4쌍 8다리)에 맞춰 3번 다리를 엉덩이 기준으로 돌려 뒷다리 한 쌍을 만든다.
## - 발은 월드에 디딘 채 남고, 몸이 움직이면 교대 4족 보행(L1·R2·L3·R4 ↔ R1·L2·R3·L4)으로 빠르게 한 발씩 옮긴다.
##   다리는 엉덩이 요 회전 + 무릎이 위로 꺾이는 2관절 IK로 푼다.
## - 몸통 흔들림·배의 스프링 지연·숨쉬기, 머리의 짧고 끊기는 시선 이동, 송곳니 씹기, 앞다리 더듬기, 눈 깜빡임,
##   공격(앞다리 들어 올렸다 내리찍기 + 송곳니), 피격 움찔, 죽음(뒤집히며 다리를 오므림).
## 모델은 +Z를 바라본다(monster._face와 같은 규약).

const GLB := "res://assets/monsters/spider/frozen_spider.glb"
const PAINT := preload("res://shaders/painted_prop.gdshader")
const EYES := preload("res://shaders/spider_eyes.gdshader")
const Fx := preload("res://scripts/visual/fx.gd")

const MODEL_SCALE := 1.45
const UP := Vector3.UP

const LEG_PARTS := {"L1": "tripo_part_8", "L2": "tripo_part_2", "L3": "tripo_part_4",
	"R1": "tripo_part_7", "R2": "tripo_part_6", "R3": "tripo_part_5"}
## 뒷다리 = [원본 다리, 엉덩이 기준 Y 회전(도), 엉덩이 이동]
const REAR_CLONES := {"L4": ["L3", -52.0, Vector3(0.035, 0.0, -0.10)], "R4": ["R3", 52.0, Vector3(-0.035, 0.0, -0.10)]}
const LEG_ORDER := ["L1", "L2", "L3", "L4", "R1", "R2", "R3", "R4"]
const GROUP_A := ["L4", "R3", "L2", "R1"]
## 서 있는 자세에서 발끝 위치 보정(요 회전 도, 바깥으로 미는 거리): 다리가 부채꼴로 고르게 퍼지도록
const STANCE := {"L1": [-6.0, -0.035], "R1": [6.0, -0.035], "L2": [0.0, -0.045], "R2": [0.0, -0.045],
	"L3": [8.0, -0.045], "R3": [-8.0, -0.045], "L4": [0.0, -0.06], "R4": [0.0, -0.06]}
const HEAD_PARTS := ["tripo_part_0", "tripo_part_9", "tripo_part_10", "tripo_part_14", "tripo_part_15", "tripo_part_16", "tripo_part_17"]
const FANG_PARTS := {"FangL": "tripo_part_13", "FangR": "tripo_part_12"}
const ABDOMEN_PARTS := ["tripo_part_1", "tripo_part_3", "tripo_part_19"]
const BODY_PARTS := ["tripo_part_11"]
const BODY_PIVOT := Vector3(0.0, 0.22, 0.10)
const HEAD_PIVOT := Vector3(0.0, 0.25, 0.18)
const ABDOMEN_PIVOT := Vector3(0.0, 0.27, 0.02)
const BODY_CENTER := Vector3(0.0, 0.21, 0.12)
const JOINT_BLEND := 0.05
## 바깥 다리 발끝이 모델 원점보다 7cm 떠 있어 몸 전체를 이만큼 내려 8발이 모두 땅을 딛게 한다
const GROUND_DROP := 0.055

# 보행 수치(모델 좌표 단위, 실제 거리는 × 스케일)
## 위상 보행: 한 주기 동안 몸이 나아가는 거리(STRIDE), 공중에 있는 비율(SWING). 두 무리는 반 주기 어긋나고
## 같은 무리 안에서는 뒤→앞으로 살짝 늦게 뜬다(물결). SWING + 무리 안 최대 지연 < 0.5 이므로 두 무리가 동시에 뜨지 않는다.
const STRIDE := 0.26
const SWING := 0.36
const PERIOD_MIN := 0.17
const PERIOD_MAX := 0.5
const GAIT_MIN_SPEED := 0.2
const PHASE := {"L4": 0.0, "R3": 0.04, "L2": 0.08, "R1": 0.12, "R4": 0.5, "L3": 0.54, "R2": 0.58, "L1": 0.62}
const STEP_LIFT := 0.075
const IDLE_SETTLE := 0.035

static var _cache: Dictionary = {}

var body: Node3D
var head: Node3D
var abdomen: Node3D
var skeleton: Skeleton3D
var legs_mesh: MeshInstance3D
var head_mesh: MeshInstance3D
var fangs: Dictionary = {}
var feet: Dictionary = {}      # 다리 id -> 상태
var speed_now := 0.0
var steps_taken := 0
var blinks := 0
var dying := false
var _rig: Dictionary
var _t := 0.0
var _init_feet := false
var _cycle := 0.0
var _prev_yaw := 0.0
var _turn_rate := 0.0
var _prev_vel := Vector3.ZERO
var _pitch := 0.0
var _roll := 0.0
var _abd := Vector2.ZERO        # 배 스프링 각(피치, 요)
var _abd_v := Vector2.ZERO
var _bob := 0.0
var _blink_t := 0.0
var _blink_next := 2.0
var _blink_plan: Array = []     # [[시작, 위쪽 눈?, 아래쪽 눈?], ...]
var _gaze := Vector2.ZERO
var _gaze_target := Vector2.ZERO
var _gaze_t := 1.0
var _chew_t := 0.0
var _chew_next := 2.0
var _tap_t := -1.0
var _tap_leg := "L1"
var _idle_next := 2.5
var _strike_t := -1.0
var _hurt_t := -1.0
var _roar_t := -1.0
var _die_t := 0.0
var _print_toggle := false


func _init() -> void:
	name = "SpiderVisual"
	scale = Vector3.ONE * MODEL_SCALE
	_rig = _get_cache()
	body = _node(self, BODY_PIVOT - Vector3(0, GROUND_DROP, 0), "Body")
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton"
	skeleton.position = -BODY_PIVOT
	body.add_child(skeleton)
	for id in LEG_ORDER:
		var leg: Dictionary = _rig["legs"][id]
		for k in 4:
			var b := skeleton.add_bone("%s_%d" % [id, k])
			if k > 0:
				skeleton.set_bone_parent(b, b - 1)
			skeleton.set_bone_rest(b, leg["rest_local"][k])
	skeleton.reset_bone_poses()
	legs_mesh = MeshInstance3D.new()
	legs_mesh.name = "Legs"
	legs_mesh.mesh = _rig["legs_mesh"]
	legs_mesh.skin = _rig["skin"]
	skeleton.add_child(legs_mesh)
	legs_mesh.skeleton = NodePath("..")
	_parts(body, BODY_PIVOT, BODY_PARTS)
	head = _node(body, HEAD_PIVOT - BODY_PIVOT, "Head")
	_parts(head, HEAD_PIVOT, HEAD_PARTS)
	for n in head.get_children():
		if n is MeshInstance3D and str(n.name) == "tripo_part_0":
			head_mesh = n
	for f in FANG_PARTS:
		var pivot: Vector3 = _rig["fang_pivot"][f]
		var fp := _node(head, pivot - HEAD_PIVOT, f)
		_parts(fp, pivot, [FANG_PARTS[f]])
		fangs[f] = fp
	abdomen = _node(body, ABDOMEN_PIVOT - BODY_PIVOT, "Abdomen")
	_parts(abdomen, ABDOMEN_PIVOT, ABDOMEN_PARTS)
	for id in LEG_ORDER:
		feet[id] = {"foot": Vector3.ZERO, "step": false, "u": 0.0, "dur": 0.1, "from": Vector3.ZERO, "to": Vector3.ZERO,
			"lift": 0.0, "cycle": -1, "raise": 0.0, "raise_pos": Vector3.ZERO, "air": 0.0}
	_t = randf() * 10.0
	_cycle = randf()
	_blink_next = randf_range(0.8, 3.5)
	_solve_rest()


func _node(parent: Node3D, pos: Vector3, n: String) -> Node3D:
	var x := Node3D.new()
	x.name = n
	x.position = pos
	parent.add_child(x)
	return x


## 모델 좌표로 구운 부품 메시를 pivot(모델 좌표) 아래에 붙인다.
func _parts(parent: Node3D, pivot: Vector3, names: Array) -> void:
	for n in names:
		var mi := MeshInstance3D.new()
		mi.name = n
		mi.mesh = _rig["parts"][n]
		mi.position = -pivot
		parent.add_child(mi)


# ───────────────────────── 리그 구성(정적 캐시) ─────────────────────────

static func _get_cache() -> Dictionary:
	if _cache.is_empty():
		_cache = _build_cache()
	return _cache


static func _build_cache() -> Dictionary:
	var scene: Node3D = load(GLB).instantiate()
	var raw := {}   # 부품 이름 -> {"arrays", "material"}
	for mi: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		var key := str(mi.name)
		if not key.begins_with("tripo_part"):
			key = str(mi.get_parent().name)
		var xf := mi.transform
		var p := mi.get_parent()
		while p != null and p != scene:
			xf = (p as Node3D).transform * xf
			p = p.get_parent()
		var arr := mi.mesh.surface_get_arrays(0)
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		for i in pos.size():
			pos[i] = xf * pos[i]
			nor[i] = (xf.basis * nor[i]).normalized()
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
		raw[key] = {"arrays": arr, "material": mi.mesh.surface_get_material(0)}
	scene.free()

	var out := {"parts": {}, "legs": {}, "fang_pivot": {}}
	for key in raw:
		if key in LEG_PARTS.values():
			continue
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, raw[key]["arrays"])
		m.surface_set_material(0, _paint(raw[key]["material"], key == "tripo_part_0", raw[key]["arrays"]))
		out["parts"][key] = m
	for f in FANG_PARTS:
		var pos: PackedVector3Array = raw[FANG_PARTS[f]]["arrays"][Mesh.ARRAY_VERTEX]
		var top := -INF
		var c := Vector3.ZERO
		for v in pos:
			top = maxf(top, v.y)
			c += v
		c /= pos.size()
		out["fang_pivot"][f] = Vector3(c.x, top - 0.01, c.z)

	# 다리: 원본 6개 + 뒷다리 복제 2개
	var leg_arrays := {}
	var leg_mats := {}
	for id in LEG_PARTS:
		leg_arrays[id] = raw[LEG_PARTS[id]]["arrays"]
		leg_mats[id] = raw[LEG_PARTS[id]]["material"]
	for id in REAR_CLONES:
		var src: String = REAR_CLONES[id][0]
		var arr: Array = leg_arrays[src].duplicate(true)
		var pos: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var nor: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var hip := _hip_point(pos)
		var rot := Basis(UP, deg_to_rad(REAR_CLONES[id][1]))
		var move: Vector3 = REAR_CLONES[id][2]
		for i in pos.size():
			pos[i] = hip + rot * (pos[i] - hip) + move
			nor[i] = rot * nor[i]
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nor
		leg_arrays[id] = arr
		leg_mats[id] = leg_mats[src]

	var legs_mesh := ArrayMesh.new()
	var skin := Skin.new()
	var surf := 0
	for li in LEG_ORDER.size():
		var id: String = LEG_ORDER[li]
		var arr: Array = leg_arrays[id]
		var leg := _rig_leg(arr[Mesh.ARRAY_VERTEX], arr[Mesh.ARRAY_INDEX])
		var bones := PackedInt32Array()
		var weights := PackedFloat32Array()
		var tv: PackedFloat32Array = leg["t"]
		var bounds: Array = leg["bounds"]
		for i in tv.size():
			var t := tv[i]
			var seg := 0
			for j in 3:
				if t >= bounds[j]:
					seg = j + 1
			var b0 := seg
			var b1 := seg
			var w1 := 0.0
			for j in 3:
				if absf(t - bounds[j]) < JOINT_BLEND:
					b0 = j
					b1 = j + 1
					w1 = smoothstep(bounds[j] - JOINT_BLEND, bounds[j] + JOINT_BLEND, t)
			bones.append_array([li * 4 + b0, li * 4 + b1, 0, 0])
			weights.append_array([1.0 - w1, w1, 0.0, 0.0])
		arr[Mesh.ARRAY_BONES] = bones
		arr[Mesh.ARRAY_WEIGHTS] = weights
		legs_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		legs_mesh.surface_set_material(surf, _paint(leg_mats[id], false, arr))
		surf += 1
		for k in 4:
			skin.add_bind(li * 4 + k, (leg["rest"][k] as Transform3D).affine_inverse())
		out["legs"][id] = leg
	out["legs_mesh"] = legs_mesh
	out["skin"] = skin
	return out


## 페인터리 재질. 화면 스타일이 텍스처를 일부만 남기므로(기본 45%) 바탕색을 부품 텍스처의 평균색(정점 UV에서 표본)으로 두고,
## 텍스처 쪽은 평균 밝기로 나눠 원래 밝기를 유지한다. 그래야 짙은 남색 다리·흰 배 무늬가 툰 화면에서도 살아남는다.
static func _paint(src: Material, eyes: bool, arrays: Array) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = EYES if eyes else PAINT
	var avg := Color(1, 1, 1)
	if src is StandardMaterial3D and src.albedo_texture != null:
		m.set_shader_parameter("paint_texture", src.albedo_texture)
		if not eyes:
			m.set_shader_parameter("use_texture", true)
		avg = _uv_average(src.albedo_texture, arrays[Mesh.ARRAY_TEX_UV])
	# 밝은 부품(흰 배·눈 덩이·털)은 무늬의 짙은 색에 끌려 어두워지지 않게 자기 밝기만큼 흰색 쪽으로 올린다
	var l0 := avg.r * 0.3 + avg.g * 0.59 + avg.b * 0.11
	if not eyes:   # 머리 갑각은 짙은 남색 그대로(눈꺼풀 색과 맞춘다)
		avg = avg.lerp(Color(1, 1, 1), clampf(l0 * 1.1, 0.0, 0.85))
	var luma := maxf(avg.r * 0.3 + avg.g * 0.59 + avg.b * 0.11, 0.12)
	m.set_shader_parameter("base_color", avg)
	m.set_shader_parameter("paint_gain", minf(1.0 / luma, 4.0))
	m.set_shader_parameter("painted_fill", 0.13)
	return m


static func _uv_average(tex: Texture2D, uvs: PackedVector2Array) -> Color:
	var img := tex.get_image()
	if img == null or uvs.is_empty():
		return Color(1, 1, 1)
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var sum := Color(0, 0, 0, 0)
	var step := maxi(1, uvs.size() / 400)
	var n := 0
	for i in range(0, uvs.size(), step):
		sum += img.get_pixel(clampi(int(uvs[i].x * w), 0, w - 1), clampi(int(uvs[i].y * h), 0, h - 1))
		n += 1
	return Color(sum.r / n, sum.g / n, sum.b / n)


## 몸 중심에 가장 가까운 정점들의 평균 = 다리 밑동.
static func _hip_point(pos: PackedVector3Array) -> Vector3:
	var order := range(pos.size())
	order.sort_custom(func(a, b): return pos[a].distance_squared_to(BODY_CENTER) < pos[b].distance_squared_to(BODY_CENTER))
	var n := maxi(3, int(pos.size() * 0.04))
	var c := Vector3.ZERO
	for i in n:
		c += pos[order[i]]
	return c / n


## 다리 메시 → 관절 5점(엉덩이·밑마디 끝·무릎·발목·발끝), 정점별 중심선 매개변수 t, 휴식 뼈 변환.
static func _rig_leg(pos: PackedVector3Array, idx: PackedInt32Array) -> Dictionary:
	# 1) UV 이음매로 갈라진 정점을 위치로 합쳐 표면 그래프를 만든다
	var key_of := {}
	var wid := PackedInt32Array()
	var wpos: Array[Vector3] = []
	for v in pos:
		var k := Vector3i(roundi(v.x * 20000.0), roundi(v.y * 20000.0), roundi(v.z * 20000.0))
		if not key_of.has(k):
			key_of[k] = wpos.size()
			wpos.append(v)
		wid.append(key_of[k])
	var n := wpos.size()
	var adj: Array = []
	adj.resize(n)
	for i in n:
		adj[i] = {}
	for t in range(0, idx.size(), 3):
		for e in 3:
			var a := wid[idx[t + e]]
			var b := wid[idx[t + (e + 1) % 3]]
			if a != b:
				adj[a][b] = wpos[a].distance_to(wpos[b])
				adj[b][a] = adj[a][b]
	# 2) 엉덩이(몸 중심에 가까운 정점)에서 측지 거리(다익스트라, 정점 수가 적어 O(n²))
	var dist := PackedFloat32Array()
	dist.resize(n)
	dist.fill(INF)
	var order := range(n)
	order.sort_custom(func(a, b): return wpos[a].distance_squared_to(BODY_CENTER) < wpos[b].distance_squared_to(BODY_CENTER))
	var seeds := maxi(3, int(n * 0.04))
	for i in seeds:
		dist[order[i]] = 0.0
	var done := PackedByteArray()
	done.resize(n)
	for _iter in n:
		var best := -1
		var bd := INF
		for i in n:
			if done[i] == 0 and dist[i] < bd:
				bd = dist[i]
				best = i
		if best < 0:
			break
		done[best] = 1
		for j in adj[best]:
			var nd: float = bd + adj[best][j]
			if nd < dist[j]:
				dist[j] = nd
	# 끊긴 섬(눈 덩이 등)은 가장 가까운 연결 정점의 값을 쓴다
	for i in n:
		if dist[i] == INF:
			var bj := -1
			var bdd := INF
			for j in n:
				if dist[j] != INF and done[j] == 1:
					var dd := wpos[i].distance_squared_to(wpos[j])
					if dd < bdd:
						bdd = dd
						bj = j
			dist[i] = dist[bj] if bj >= 0 else 0.0
	var maxd := 0.0
	var tip_i := 0
	for i in n:
		if dist[i] > maxd:
			maxd = dist[i]
			tip_i = i
	# 3) t를 구간으로 나눠 중심선
	const BINS := 20
	var sums: Array[Vector3] = []
	var cnt: Array[int] = []
	sums.resize(BINS)
	cnt.resize(BINS)
	for b in BINS:
		sums[b] = Vector3.ZERO
		cnt[b] = 0
	var tw := PackedFloat32Array()
	tw.resize(n)
	for i in n:
		tw[i] = dist[i] / maxd
		var b := mini(int(tw[i] * BINS), BINS - 1)
		sums[b] += wpos[i]
		cnt[b] += 1
	var line: Array[Vector3] = []
	var line_t: Array[float] = []
	for b in BINS:
		if cnt[b] > 0:
			line.append(sums[b] / cnt[b])
			line_t.append((b + 0.5) / BINS)
	var hip: Vector3 = line[0]
	var tip: Vector3 = wpos[tip_i]
	# 무릎 = 엉덩이~발끝 현에서 가장 멀리(특히 위로) 솟은 중심선 점. 거의 곧은 다리(앞다리)는 중간에 둔다
	var tk := 0.45
	var best := 0.0
	var chord := (tip - hip).normalized()
	for i in line.size():
		if line_t[i] < 0.22 or line_t[i] > 0.72:
			continue
		var rel := line[i] - hip
		var perp := rel - chord * rel.dot(chord)
		var score := perp.length() + maxf(perp.y, 0.0) * 0.5
		if score > best:
			best = score
			tk = line_t[i]
	# 무릎이 엉덩이보다 낮게 잡히면(앞다리) 거미답지 않으므로 곧은 다리로 보고 중간에 무릎을 둔다
	var straight := best < tip.distance_to(hip) * 0.12 or _line_at(line, line_t, tk).y < hip.y - 0.02
	if straight:
		tk = 0.45
	var t1 := tk * (0.22 if straight else 0.4)   # 곧은 앞다리는 밑마디를 짧게, 넓적마디를 길게
	var t3 := tk + (1.0 - tk) * 0.5
	var joints: Array[Vector3] = [hip, _line_at(line, line_t, t1), _line_at(line, line_t, tk), _line_at(line, line_t, t3), tip]
	# 4) 휴식 뼈: 원점 = 관절, Y = 다음 관절 방향, X = 다리 수직면의 법선(무릎 경첩)
	var out0 := Vector3(tip.x - hip.x, 0.0, tip.z - hip.z).normalized()
	var hinge0 := UP.cross(out0).normalized()
	var rest: Array[Transform3D] = []
	for k in 4:
		rest.append(_frame(joints[k], joints[k + 1], hinge0))
	var rest_local: Array[Transform3D] = [rest[0]]
	for k in range(1, 4):
		rest_local.append(rest[k - 1].affine_inverse() * rest[k])
	var l1 := joints[1].distance_to(joints[2])
	var l2 := joints[2].distance_to(joints[4])
	var v0 := _frame(joints[2], joints[4], hinge0)
	# 휴식 자세의 무릎 방향(엉덩이 요 프레임 기준)을 저장해 IK가 휴식 자세를 그대로 재현하도록 한다
	var d0 := (joints[4] - joints[1])
	var dir0 := d0.normalized()
	var a0 := (l1 * l1 - l2 * l2 + d0.length_squared()) / (2.0 * d0.length())
	var perp0 := joints[2] - (joints[1] + dir0 * a0)
	var pole_frame := Basis(hinge0, UP, out0).inverse()
	# 정점별 t(원래 정점 순서)
	var tv := PackedFloat32Array()
	tv.resize(pos.size())
	for i in pos.size():
		tv[i] = tw[wid[i]]
	return {"joints": joints, "t": tv, "bounds": [t1, tk, t3], "rest": rest, "rest_local": rest_local,
		"out0": out0, "hinge0": hinge0, "l1": l1, "l2": l2, "length": l1 + l2,
		"rel_tib": v0.affine_inverse() * rest[2], "rel_tar": v0.affine_inverse() * rest[3],
		"pole_local": Vector3(0.0, 1.0, 0.6).normalized() if straight or perp0.length() < 1e-4 else pole_frame * perp0.normalized()}


static func _line_at(line: Array[Vector3], lt: Array[float], t: float) -> Vector3:
	if t <= lt[0]:
		return line[0]
	for i in range(1, line.size()):
		if t <= lt[i]:
			return line[i - 1].lerp(line[i], (t - lt[i - 1]) / (lt[i] - lt[i - 1]))
	return line[line.size() - 1]


static func _frame(o: Vector3, target: Vector3, hinge: Vector3) -> Transform3D:
	var y := (target - o).normalized()
	var x := (hinge - y * hinge.dot(y))
	if x.length() < 1e-5:
		x = y.cross(Vector3.FORWARD)
	x = x.normalized()
	return Transform3D(Basis(x, y, x.cross(y)), o)


# ───────────────────────── IK ─────────────────────────

## 골격 공간(모델 좌표) 발 목표 f로 다리를 푼다. curl은 발끝마디를 추가로 오므리는 각(라디안).
func _solve_leg(li: int, f: Vector3, curl := 0.0) -> void:
	var leg: Dictionary = _rig["legs"][LEG_ORDER[li]]
	var j: Array = leg["joints"]
	var j0: Vector3 = j[0]
	var out := Vector3(f.x - j0.x, 0.0, f.z - j0.z)
	out = leg["out0"] if out.length() < 1e-4 else out.normalized()
	var ry := Basis(UP, (leg["out0"] as Vector3).signed_angle_to(out, UP))
	var hinge: Vector3 = ry * leg["hinge0"]
	var j1: Vector3 = j0 + ry * ((j[1] as Vector3) - j0)
	var l1: float = leg["l1"]
	var l2: float = leg["l2"]
	var dv := f - j1
	var d := clampf(dv.length(), absf(l1 - l2) + 0.004, l1 + l2 - 0.002)
	var dir := dv.normalized() if dv.length() > 1e-5 else -UP
	var a := (l1 * l1 - l2 * l2 + d * d) / (2.0 * d)
	var h := sqrt(maxf(l1 * l1 - a * a, 0.0))
	var pole: Vector3 = Basis(hinge, UP, out) * leg["pole_local"]
	var perp := pole - dir * pole.dot(dir)
	perp = (UP - dir * UP.dot(dir)) if perp.length() < 1e-4 else perp
	perp = perp.normalized()
	var knee := j1 + dir * a + perp * h
	var fe := j1 + dir * d
	var g0 := _frame(j0, j1, hinge)
	var g1 := _frame(j1, knee, hinge)
	var v := _frame(knee, fe, hinge)
	var g2: Transform3D = v * leg["rel_tib"]
	var g3: Transform3D = v * leg["rel_tar"]
	if curl != 0.0:
		var hx := g3.basis.x.normalized()
		g3.basis = Basis(hx, curl) * g3.basis
	var b := li * 4
	_set_pose(b, g0)
	_set_pose(b + 1, g0.affine_inverse() * g1)
	_set_pose(b + 2, g1.affine_inverse() * g2)
	_set_pose(b + 3, g2.affine_inverse() * g3)


func _set_pose(b: int, t: Transform3D) -> void:
	skeleton.set_bone_pose_position(b, t.origin)
	skeleton.set_bone_pose_rotation(b, t.basis.get_rotation_quaternion())


func _solve_rest() -> void:
	for li in LEG_ORDER.size():
		_solve_leg(li, _home_local(LEG_ORDER[li]))


## 엉덩이(월드, 몸 흔들림 무시)와 수평 최대 도달 거리(월드).
func _hip_world(id: String) -> Vector3:
	return global_transform * _leg_const(id)["hip"]


func _reach(id: String) -> float:
	return float(_leg_const(id)["reach"]) * _gscale()


## 다리마다 변하지 않는 값(모델 좌표 엉덩이·서 있는 발끝, 축척 전 도달 거리). 매 프레임 다리당 여러 번 쓰여 한 번만 계산한다.
var _leg_consts := {}

func _leg_const(id: String) -> Dictionary:
	var c: Dictionary = _leg_consts.get(id, {})
	if c.is_empty():
		var leg: Dictionary = _rig["legs"][id]
		var j0: Vector3 = leg["joints"][0]
		var hy: float = j0.y - GROUND_DROP
		c = {"hip": j0 - Vector3(0, GROUND_DROP, 0), "reach": sqrt(maxf(pow(float(leg["length"]) * 0.95, 2.0) - hy * hy, 0.01)),
			"home": _compute_home_local(id)}
		_leg_consts[id] = c
	return c


## 착지점을 다리가 닿는 원 안으로 당긴다.
func _clamp_reach(id: String, p: Vector3) -> Vector3:
	var hip := _hip_world(id)
	var h := Vector2(p.x - hip.x, p.z - hip.z)
	var r := _reach(id) * 0.9
	if h.length() > r:
		h = h.normalized() * r
	return Vector3(hip.x + h.x, p.y, hip.z + h.y)


## 서 있는 자세의 발끝(모델 좌표, 지면 y=0).
func _home_local(id: String) -> Vector3:
	return _leg_const(id)["home"]


func _compute_home_local(id: String) -> Vector3:
	var leg: Dictionary = _rig["legs"][id]
	var j0: Vector3 = leg["joints"][0]
	var tip: Vector3 = leg["joints"][4]
	var st: Array = STANCE[id]
	var off := Basis(UP, deg_to_rad(st[0])) * Vector3(tip.x - j0.x, 0.0, tip.z - j0.z)
	off += off.normalized() * float(st[1])
	return Vector3(j0.x + off.x, 0.0, j0.z + off.z)


# ───────────────────────── 매 프레임 ─────────────────────────

func _process(delta: float) -> void:
	if delta <= 0.0 or not is_inside_tree():
		return
	_t += delta
	if dying:
		_tick_death(delta)
		return
	if delta <= 0.0:
		return   # 손패 고민 시간으로 세상이 완전히 멈추면(delta 0) 회전 속도·가속 나눗셈을 건너뛴다
	var mon := get_parent()
	var vel := Vector3.ZERO
	if mon is CharacterBody3D:
		vel = (mon as CharacterBody3D).velocity
	vel.y = 0.0
	speed_now = vel.length()
	var yaw := global_rotation.y
	_turn_rate = lerpf(_turn_rate, wrapf(yaw - _prev_yaw, -PI, PI) / delta, clampf(delta * 10.0, 0.0, 1.0))
	_prev_yaw = yaw
	var acc := (vel - _prev_vel) / delta
	_prev_vel = vel
	_update_feet(delta, vel)
	_update_body(delta, vel, acc)
	_update_actions(delta)
	_apply_legs()
	_update_blink(delta)


func _gscale() -> float:
	return global_transform.basis.get_scale().x


func _home_world(id: String) -> Vector3:
	var p := global_transform * _home_local(id)
	p.y = global_position.y
	return p


func _update_feet(delta: float, vel: Vector3) -> void:
	var s := _gscale()
	if not _init_feet:
		_init_feet = true
		for id in LEG_ORDER:
			feet[id]["foot"] = _home_world(id)
	# 보행 위상: 이동 속도 + 제자리 회전 속도로 돈다. 아주 느리면(멈칫 포함) 멈추고 발만 정리한다
	var gait_speed := speed_now + absf(_turn_rate) * 0.3 * s
	var walking := gait_speed > GAIT_MIN_SPEED
	var period := clampf(STRIDE * s / maxf(gait_speed, 0.01), PERIOD_MIN, PERIOD_MAX)
	if walking:
		_cycle += delta / period
	var stance_t := period * (1.0 - SWING)
	for id in LEG_ORDER:
		var st: Dictionary = feet[id]
		if st["step"]:
			var remain := (1.0 - float(st["u"])) * float(st["dur"])
			# 착지점 = 착지 시점에 서 있을 자세의 발끝 + 디딤 시간의 절반만큼 앞(디딘 동안 발이 집 자리를 지나도록)
			st["to"] = _clamp_reach(id, _home_world(id) + vel * (remain + stance_t * 0.5))
			st["u"] = minf(float(st["u"]) + delta / float(st["dur"]), 1.0)
			var u: float = st["u"]
			var e := 1.0 - (1.0 - u) * (1.0 - u)
			var p: Vector3 = (st["from"] as Vector3).lerp(st["to"], e)
			p.y = global_position.y + float(st["lift"]) * sin(PI * pow(u, 0.7))
			st["foot"] = p
			st["air"] = sin(PI * u)
			if u >= 1.0:
				st["step"] = false
				st["air"] = 0.0
				var land: Vector3 = st["to"]
				land.y = global_position.y
				st["foot"] = land
				steps_taken += 1
				_on_land(land, vel.normalized() if speed_now > 0.01 else Vector3.ZERO)
			continue
		var fp: Vector3 = st["foot"]
		var home := _home_world(id)
		if Vector2(fp.x - home.x, fp.z - home.z).length() > STRIDE * s * 4.0:
			st["foot"] = Vector3(home.x, global_position.y, home.z)   # 순간이동·스폰 직후
			continue
		var hip := _hip_world(id)
		var overreach := Vector2(fp.x - hip.x, fp.z - hip.z).length() > _reach(id) * 0.98
		if walking:
			var lp := _cycle + float(PHASE[id])
			var cyc := int(floor(lp))
			if (fmod(lp, 1.0) < SWING and cyc != int(st["cycle"])) or overreach:
				st["cycle"] = cyc
				var left := (SWING - fmod(lp, 1.0)) * period if not overreach else SWING * period * 0.6
				_start_step(id, maxf(left, 0.05), STEP_LIFT * s)
		elif overreach or (Vector2(fp.x - home.x, fp.z - home.z).length() > IDLE_SETTLE * s and not _neighbor_stepping(id) \
				and randf() < delta * 9.0):
			# 멈춰 있을 때는 어긋난 발만 이웃과 겹치지 않게 하나씩 고쳐 딛는다
			_start_step(id, randf_range(0.1, 0.15), STEP_LIFT * s * 0.6)


func _neighbor_stepping(id: String) -> bool:
	var side := id.substr(0, 1)
	var n := int(id.substr(1))
	for d in [-1, 1]:
		var k := "%s%d" % [side, n + d]
		if feet.has(k) and feet[k]["step"]:
			return true
	return false


func _start_step(id: String, dur: float, lift: float) -> void:
	var st: Dictionary = feet[id]
	st["step"] = true
	st["u"] = 0.0
	st["from"] = st["foot"]
	st["to"] = _clamp_reach(id, _home_world(id))
	st["dur"] = dur
	st["lift"] = lift * randf_range(0.85, 1.15)


func _on_land(at: Vector3, vdir: Vector3) -> void:
	_bob -= 0.004
	_print_toggle = not _print_toggle
	if _print_toggle and speed_now > 0.08 and is_visible_in_tree():
		Fx.footprint(at, atan2(vdir.x, vdir.z), 0.11 * _gscale() / MODEL_SCALE, Color(0.28, 0.2, 0.5, 0.42), 3.5)


func _update_body(delta: float, vel: Vector3, acc: Vector3) -> void:
	var inv := global_transform.basis.orthonormalized().inverse()
	var lv := inv * vel
	var la := inv * acc
	var air := 0.0
	for id in LEG_ORDER:
		air += float(feet[id]["air"])
	# 몸이 다리 사이에서 낮게 출렁인다: 공중 다리가 많을수록 살짝 내려앉고, 착지마다 작게 튄다
	_bob = lerpf(_bob, 0.0, clampf(delta * 14.0, 0.0, 1.0))
	var walk := clampf(speed_now / 1.8, 0.0, 1.0)
	var breathe := sin(_t * 2.1) * 0.004 * (1.0 - walk)
	var y := -air * 0.006 - walk * 0.012 + _bob + breathe
	var lean := clampf(-la.z * 0.012, -0.12, 0.12) + walk * 0.05
	var roll := clampf(-_turn_rate * 0.04, -0.14, 0.14) + clampf(la.x * 0.008, -0.08, 0.08)
	_pitch = lerpf(_pitch, lean, clampf(delta * 9.0, 0.0, 1.0))
	_roll = lerpf(_roll, roll, clampf(delta * 9.0, 0.0, 1.0))
	var pos := BODY_PIVOT + Vector3(0.0, y - GROUND_DROP, 0.0)
	var rot := Vector3(_pitch, sin(_t * 23.0) * 0.006 * walk, _roll)
	# 공격·피격 덧붙임
	var sk := _strike_pose()
	pos += sk[0]
	rot += sk[1]
	var rp := _roar_pose()
	pos += rp[0]
	rot += rp[1]
	if _hurt_t >= 0.0:
		_hurt_t += delta
		var k := sin(clampf(_hurt_t / 0.22, 0.0, 1.0) * PI)
		pos.z -= 0.03 * k
		rot.x -= 0.12 * k
		if _hurt_t > 0.22:
			_hurt_t = -1.0
	body.position = pos
	body.rotation = rot
	# 배: 가속·회전에 늦게 따라오는 스프링 + 숨쉬기
	var target := Vector2(clampf(la.z * 0.025, -0.25, 0.25) - walk * 0.06, clampf(_turn_rate * 0.08, -0.3, 0.3))
	_abd_v += ((target - _abd) * 90.0 - _abd_v * 11.0) * delta
	_abd += _abd_v * delta
	abdomen.rotation = Vector3(_abd.x + air * 0.01, _abd.y, -_abd.y * 0.3)
	var pulse := 1.0 + sin(_t * 2.1 + 0.6) * 0.022 * (1.0 - walk * 0.6)
	if _roar_t >= 0.0:
		# 포효: 배를 치켜들고 크게 부풀린다
		var w := _roar_weight()
		abdomen.rotation.x += 0.42 * w
		pulse += 0.07 * w + sin(_t * 31.0) * 0.012 * w
	abdomen.scale = Vector3(pulse, 2.0 - pulse, pulse)


## 공격 자세: [몸 위치 덧셈, 몸 회전 덧셈]. 들어 올림(0~0.36) → 내리찍기(0.36~0.56) → 복귀.
func _strike_pose() -> Array:
	if _strike_t < 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	var u := _strike_t / 0.5
	var rear := 0.0
	var lunge := 0.0
	if u < 0.36:
		rear = _ease(u / 0.36)
	elif u < 0.56:
		var k := (u - 0.36) / 0.2
		rear = 1.0 - _ease(k) * 1.5
		lunge = _ease(k)
	else:
		var k := (u - 0.56) / 0.44
		rear = -0.5 * (1.0 - _ease(k))
		lunge = 1.0 - _ease(k)
	return [Vector3(0.0, rear * 0.05, -rear * 0.02 + lunge * 0.07), Vector3(-rear * 0.32, 0.0, 0.0)]


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func _update_actions(delta: float) -> void:
	var walk := speed_now > 0.08
	if _roar_t >= 0.0:
		_update_roar(delta)
		return
	# 공격 진행
	if _strike_t >= 0.0:
		_strike_t += delta
		var u := _strike_t / 0.5
		var w := 0.0
		var lift := 0.0
		var reach := 0.0
		if u < 0.36:
			w = _ease(u / 0.36)
			lift = 1.0
			reach = 0.3
		elif u < 0.56:
			w = 1.0
			var k := _ease((u - 0.36) / 0.2)
			lift = 1.0 - k
			reach = 0.3 + 0.7 * k
		else:
			w = 1.0 - _ease((u - 0.56) / 0.44)
			reach = 1.0
		for id in ["L1", "R1"]:
			var home := _home_local(id)
			var fwd := Vector3(home.x * 0.6, 0.0, home.z + 0.08 + reach * 0.1)
			feet[id]["raise"] = w
			feet[id]["raise_pos"] = fwd + UP * (0.02 + lift * 0.24)
		_set_fangs(1.0 if u < 0.4 else (-0.35 if u < 0.62 else 0.0), delta, 30.0)
		if _strike_t >= 0.5:
			_strike_t = -1.0
			feet["L1"]["raise"] = 0.0
			feet["R1"]["raise"] = 0.0
		_head_gaze(delta, true)
		return
	# 가만히 있을 때: 앞다리 더듬기, 송곳니 씹기, 한 발 고쳐 딛기
	_idle_next -= delta
	if not walk and _tap_t < 0.0 and _idle_next <= 0.0:
		_idle_next = randf_range(2.2, 5.0)
		var r := randf()
		if r < 0.55:
			_tap_t = 0.0
			_tap_leg = "L1" if randf() < 0.5 else "R1"
		else:
			var id: String = LEG_ORDER[randi() % LEG_ORDER.size()]
			if not feet[id]["step"]:
				var jitter := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.03 * _gscale()
				feet[id]["foot"] = feet[id]["foot"] + jitter
	if _tap_t >= 0.0:
		_tap_t += delta
		var u := _tap_t / 0.9
		var w := sin(clampf(u, 0.0, 1.0) * PI)
		w = clampf(w * 1.6, 0.0, 1.0)
		# 두 번 톡톡 두드린다
		var tap := absf(sin(u * PI * 4.0)) * 0.07
		var home := _home_local(_tap_leg)
		feet[_tap_leg]["raise"] = w
		feet[_tap_leg]["raise_pos"] = Vector3(home.x * 0.85, 0.03 + tap, home.z + 0.06)
		if u >= 1.0 or walk:
			_tap_t = -1.0
			feet[_tap_leg]["raise"] = 0.0
	_chew_next -= delta
	if _chew_next <= 0.0:
		_chew_next = randf_range(1.5, 4.0) if not walk else randf_range(3.0, 6.0)
		_chew_t = 0.0
	var spread := 0.0
	if _chew_t >= 0.0:
		_chew_t += delta
		spread = absf(sin(_chew_t * 14.0)) * 0.55
		if _chew_t > 0.45:
			_chew_t = -1.0
	_set_fangs(spread, delta, 18.0)
	_head_gaze(delta, false)


func _set_fangs(spread: float, delta: float, rate: float) -> void:
	for f in fangs:
		var s := -1.0 if f == "FangL" else 1.0
		var fp: Node3D = fangs[f]
		var k := clampf(delta * rate, 0.0, 1.0)
		fp.rotation.z = lerpf(fp.rotation.z, s * spread * 0.45, k)
		fp.rotation.x = lerpf(fp.rotation.x, -spread * 0.25, k)


## 머리: 일정 간격으로 짧게 '딱' 끊어 시선을 옮긴다(곤충다운 단속적 움직임).
func _head_gaze(delta: float, focus: bool) -> void:
	_gaze_t -= delta
	if _gaze_t <= 0.0:
		_gaze_t = randf_range(0.35, 1.6)
		var amp := 0.04 if (focus or speed_now > 0.08) else 0.14
		_gaze_target = Vector2(randf_range(-amp, amp) * 0.6, randf_range(-amp, amp))
	_gaze = _gaze.lerp(_gaze_target, clampf(delta * 28.0, 0.0, 1.0))
	head.rotation = Vector3(_gaze.x, _gaze.y, -_gaze.y * 0.3)


func _apply_legs() -> void:
	var to_skel := skeleton.global_transform.affine_inverse()
	for li in LEG_ORDER.size():
		var id: String = LEG_ORDER[li]
		var st: Dictionary = feet[id]
		var f: Vector3 = to_skel * (st["foot"] as Vector3)
		var curl := float(st["air"]) * 0.35
		var w: float = st["raise"]
		if w > 0.0:
			f = f.lerp(st["raise_pos"], w)
			curl += w * 0.25
		_solve_leg(li, f, curl)


# ───────────────────────── 눈 깜빡임 ─────────────────────────

func _update_blink(delta: float) -> void:
	_blink_next -= delta
	if _blink_next <= 0.0 and _blink_plan.is_empty():
		_blink_t = 0.0
		var r := randf()
		if r < 0.22:
			_blink_plan = [[0.0, true, true], [0.26, true, true]]      # 두 번 연달아
		elif r < 0.36:
			_blink_plan = [[0.0, true, false], [0.12, false, true]]    # 위 눈 → 아래 눈 물결
		else:
			_blink_plan = [[0.0, true, true]]
		_blink_next = randf_range(2.0, 5.5)
		blinks += 1
	var top := 0.0
	var big := 0.0
	if not _blink_plan.is_empty():
		_blink_t += delta
		var last := 0.0
		for b in _blink_plan:
			var v := _blink_curve(_blink_t - float(b[0]))
			if b[1]: top = maxf(top, v)
			if b[2]: big = maxf(big, v)
			last = maxf(last, float(b[0]))
		if _blink_t > last + 0.24:
			_blink_plan.clear()
	set_blink(top, big)


## 0.06초에 감고 0.03초 머문 뒤 0.12초에 뜬다.
static func _blink_curve(t: float) -> float:
	if t < 0.0 or t > 0.21:
		return 0.0
	if t < 0.06:
		return t / 0.06
	if t < 0.09:
		return 1.0
	return 1.0 - (t - 0.09) / 0.12


var _blink_sent := Vector2(-1, -1)   # 마지막으로 보낸 값: 같으면 RenderingServer 호출을 건너뛴다(대부분 0,0)
var _blink_mesh: Node

func set_blink(top: float, big: float) -> void:
	if head_mesh != null:
		if _blink_mesh == head_mesh and _blink_sent == Vector2(top, big):
			return
		_blink_mesh = head_mesh
		_blink_sent = Vector2(top, big)
		head_mesh.set_instance_shader_parameter("blink_top", top)
		head_mesh.set_instance_shader_parameter("blink_big", big)


func blink_values() -> Vector2:
	if head_mesh == null:
		return Vector2.ZERO
	return Vector2(float(head_mesh.get_instance_shader_parameter("blink_top")), float(head_mesh.get_instance_shader_parameter("blink_big")))


# ───────────────────────── monster.gd에서 부르는 동작 ─────────────────────────

func strike(_target: Vector3) -> void:
	if not dying:
		_strike_t = 0.0
		_tap_t = -1.0


func hurt() -> void:
	if dying:
		return
	_hurt_t = 0.0
	_abd_v += Vector2(-3.5, randf_range(-2.0, 2.0))
	# 움찔하며 두 발을 고쳐 딛는다
	for id in [LEG_ORDER[randi() % 8], LEG_ORDER[randi() % 8]]:
		if not feet[id]["step"]:
			feet[id]["foot"] += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 0.05 * _gscale()


# ───────────────────────── 포효(보스 연출) ─────────────────────────
## 웅크림(0~ROAR_PEAK*0.5) → 앞몸을 치켜들며 앞다리 두 쌍을 벌림(~ROAR_PEAK) → 떨며 버팀 → 내리찍고 복귀(ROAR_TIME).
## 진행·판정과 무관한 표시 동작이라 보스룸 연출(boss_room.gd)이 시점에 맞춰 흔들림·소리·입자를 붙인다.
const ROAR_TIME := 2.7
const ROAR_PEAK := 0.78      # 가장 높이 치켜든 순간(소리·충격파 기준)
const ROAR_SLAM := 2.15      # 앞다리가 다시 땅을 찍는 순간


func roar() -> void:
	if dying:
		return
	_roar_t = 0.0
	_strike_t = -1.0
	_tap_t = -1.0
	for id in LEG_ORDER:
		feet[id]["raise"] = 0.0


func is_roaring() -> bool:
	return _roar_t >= 0.0


## 치켜든 정도(0~1): 웅크림 구간은 음수 쪽으로 살짝 들어간다.
func _roar_weight() -> float:
	var t := _roar_t
	if t < ROAR_PEAK * 0.5:
		return -0.35 * _ease(t / (ROAR_PEAK * 0.5))
	if t < ROAR_PEAK:
		return lerpf(-0.35, 1.0, _ease((t - ROAR_PEAK * 0.5) / (ROAR_PEAK * 0.5)))
	if t < ROAR_SLAM:
		return 1.0
	if t < ROAR_SLAM + 0.18:
		return lerpf(1.0, -0.25, _ease((t - ROAR_SLAM) / 0.18))
	return lerpf(-0.25, 0.0, _ease((t - ROAR_SLAM - 0.18) / (ROAR_TIME - ROAR_SLAM - 0.18)))


## 포효 자세: [몸 위치 덧셈, 몸 회전 덧셈]
func _roar_pose() -> Array:
	if _roar_t < 0.0:
		return [Vector3.ZERO, Vector3.ZERO]
	var w := _roar_weight()
	var up := maxf(w, 0.0)
	var hold := 1.0 if _roar_t > ROAR_PEAK and _roar_t < ROAR_SLAM else 0.0
	var shiver := sin(_t * 41.0) * 0.012 * hold
	return [Vector3(0.0, up * 0.09 + minf(w, 0.0) * 0.08 + shiver, -up * 0.05),
		Vector3(-up * 0.62 - minf(w, 0.0) * 0.25 + shiver * 1.5, 0.0, sin(_t * 37.0) * 0.02 * hold)]


func _update_roar(delta: float) -> void:
	_roar_t += delta
	var w := _roar_weight()
	var up := maxf(w, 0.0)
	var hold := _roar_t > ROAR_PEAK and _roar_t < ROAR_SLAM
	# 앞다리 한 쌍은 높이 벌려 들고, 둘째 쌍은 반쯤 들어 몸을 키운다. 버티는 동안 허공을 긁듯 떤다.
	for id in ["L1", "R1", "L2", "R2"]:
		var front: bool = id.ends_with("1")
		var home := _home_local(id)
		var claw := sin(_t * (13.0 if front else 9.0) + (0.0 if id.begins_with("L") else 1.7)) * 0.03 * (1.0 if hold else 0.0)
		var lift := (0.36 if front else 0.15) * up
		var out := 1.25 if front else 1.1
		feet[id]["raise"] = clampf(up * (1.0 if front else 0.75), 0.0, 1.0)
		feet[id]["raise_pos"] = Vector3(home.x * out, 0.03 + lift + claw, home.z + (0.14 if front else 0.05) * up)
	# 송곳니를 활짝 벌려 떨고, 머리는 들어 올린 채 짧게 좌우로 턴다
	var spread := 0.0
	if _roar_t > ROAR_PEAK * 0.5 and _roar_t < ROAR_SLAM + 0.1:
		spread = 1.25 + sin(_t * 46.0) * 0.18
	_set_fangs(spread, delta, 26.0)
	var shake := sin(_t * 23.0) * 0.07 * (1.0 if hold else 0.0)
	head.rotation = head.rotation.lerp(Vector3(-0.32 * up, shake, -shake * 0.4), clampf(delta * 18.0, 0.0, 1.0))
	if _roar_t >= ROAR_TIME:
		_roar_t = -1.0
		for id in ["L1", "R1", "L2", "R2"]:
			feet[id]["raise"] = 0.0


## 죽음: 살짝 튀어 올라 옆으로 뒤집히고 다리를 배 쪽으로 오므린다. 끝나는 데 DEATH_TIME초.
const DEATH_TIME := 0.62

func die_curl() -> void:
	if dying:
		return
	dying = true
	_die_t = 0.0
	_strike_t = -1.0
	_tap_t = -1.0
	set_blink(1.0, 1.0)
	# 지금 발 위치를 골격 공간으로 고정해 둔다(이후 루트가 줄어들어도 함께 움직이도록)
	var to_skel := skeleton.global_transform.affine_inverse()
	for id in LEG_ORDER:
		feet[id]["dead_from"] = to_skel * (feet[id]["foot"] as Vector3)


func _tick_death(delta: float) -> void:
	_die_t += delta
	var u := clampf(_die_t / DEATH_TIME, 0.0, 1.0)
	var hop := sin(clampf(u / 0.55, 0.0, 1.0) * PI) * 0.12
	var flip := _ease(clampf((u - 0.08) / 0.5, 0.0, 1.0))
	body.position = BODY_PIVOT + Vector3(0.0, hop + flip * 0.06 - GROUND_DROP, 0.0)
	body.rotation = Vector3(0.0, 0.0, flip * PI * 0.94)
	var curl := _ease(clampf(u / 0.7, 0.0, 1.0))
	for li in LEG_ORDER.size():
		var id: String = LEG_ORDER[li]
		var leg: Dictionary = _rig["legs"][id]
		var j0: Vector3 = leg["joints"][0]
		var out: Vector3 = leg["out0"]
		var tuck: Vector3 = j0 + out * 0.07 + Vector3(0.0, -0.05, 0.0) - Vector3(j0.x, 0, 0) * 0.3
		var twitch := sin(_t * 31.0 + li * 1.7) * 0.012 * (1.0 - u)
		var f: Vector3 = (feet[id]["dead_from"] as Vector3).lerp(tuck, curl) + Vector3(0, twitch, 0)
		_solve_leg(li, f, curl * 0.9)
	_set_fangs(0.0, delta, 10.0)
	abdomen.rotation = abdomen.rotation.lerp(Vector3.ZERO, clampf(delta * 8.0, 0.0, 1.0))


## 검증용: 다리 li의 발끝 뼈 끝(월드)이 목표에 얼마나 가까운지.
func leg_tip_world(li: int) -> Vector3:
	var leg: Dictionary = _rig["legs"][LEG_ORDER[li]]
	var g3 := skeleton.global_transform * skeleton.get_bone_global_pose(li * 4 + 3)
	var rest3: Transform3D = leg["rest"][3]
	return g3 * (rest3.affine_inverse() * (leg["joints"][4] as Vector3))
