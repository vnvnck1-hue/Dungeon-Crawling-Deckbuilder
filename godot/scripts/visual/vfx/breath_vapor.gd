extends Node3D
## 차가운 공기 속 입김. 굴뚝 연기처럼 Stable Fluids(stable_fluid.gd)로 '날숨 한 번'의 공기 흐름을 풀어 만든 기체다.
## - 캐릭터가 많아 입김마다 유체를 풀 수는 없으므로, 시작할 때 작업 스레드에서 날숨을 몇 가지(VARIANTS) 풀어
##   그 밀도장을 시간 순서대로 한 장의 아틀라스(플립북)에 굽는다.
## - 입김 하나 = 카메라를 향한 세로 판 하나. 셰이더가 나이에 맞는 두 장을 보간하고 흐르는 노이즈로 결을 비튼다.
##   윤곽선 없는 반투명 기체가 입 앞에서 뿜어져 말려 오르며 옅게 흩어진다.
## - 판은 입 위치에서 날숨 방향(화면 가로로 투영)으로 뻗고, 바람을 따라 조금씩 밀려간다.
## 게임 판정과 무관한 표시 전용 노드. ActorVfx 가 exhale() 를 부른다.

const Fluid := preload("res://scripts/visual/vfx/stable_fluid.gd")
const SHADER := preload("res://shaders/breath_vapor.gdshader")

const NX := 28
const NY := 28
const CELL := 0.036               # 칸 한 변(m) → 판 1.0m × 1.0m (breath_k 1 기준)
const SRC := Vector2i(3, 13)      # 입(날숨이 나오는 칸). 판 왼쪽 아래쪽에 두어 앞으로 뻗고 위로 오를 자리를 남긴다
const JET := 7                    # 날숨 분출 줄기 길이(칸)
const STEP := 1.0 / 30.0          # 풀이 간격(초)
const RECORD_EVERY := 2           # 두 단계마다 한 장 → 15장/초
const FRAMES := 27                # 날숨 한 번 = 1.8초
const VARIANTS := 3               # 서로 다른 날숨 모양 수
const LIFE := 1.8                 # 입김 하나의 수명(초) = 구운 길이
const MAX_PUFFS := 40
const PULL := 0.30                # 판을 카메라 쪽으로 당기는 거리(m)
const PULL_FACING := 0.25         # 카메라를 향해 내쉴 때 더 당기는 거리(m)

var weather                       # WeatherVfx(바람). 없으면 바람 없음
var camera: Camera3D
var threaded := true              # false 면 _ready 에서 바로 굽는다(검증용)
var bake_usec := 0
var atlas_image: Image            # 구운 밀도 아틀라스(검증용으로 남겨 둔다)
var spawned := 0

var material: ShaderMaterial
var _quad: QuadMesh
var _atlas_tex: ImageTexture
var _task := -1
var _baked := false
var _live: Array = []             # {node, age, life, vel, variant}
var _free: Array[MeshInstance3D] = []


func _init() -> void:
	name = "BreathVapor"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	_build_material()
	if threaded:
		_task = WorkerThreadPool.add_task(_bake, false, "breath vapor bake")
	else:
		_bake()
		_upload()


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func is_ready() -> bool:
	return _baked


func active_count() -> int:
	return _live.size()


## 입김 한 번. pos = 입, forward = 내쉬는 방향(바람을 섞어 넘겨도 된다), color.a = 진하기, scale = 크기.
func exhale(pos: Vector3, forward: Vector3, color := Color(1, 1, 1, 0.6), scale := 1.0) -> void:
	if not _baked:
		return
	var f := Vector3(forward.x, 0.0, forward.z)
	f = f.normalized() if f.length() > 1e-4 else Vector3.FORWARD
	var mi: MeshInstance3D
	if _free.is_empty():
		if _live.size() >= MAX_PUFFS:
			mi = _live.pop_front()["node"]
		else:
			mi = _new_puff()
	else:
		mi = _free.pop_back()
	var variant := randi() % VARIANTS
	mi.visible = true
	mi.set_instance_shader_parameter("tint", color)
	mi.set_instance_shader_parameter("variant", float(variant))
	mi.set_instance_shader_parameter("seed", randf() * 10.0)
	mi.set_instance_shader_parameter("age", 0.0)
	var life := LIFE * randf_range(0.9, 1.1)
	_live.append({"node": mi, "age": 0.0, "life": life, "dir": f, "pos": pos, "scale": scale * randf_range(0.9, 1.1)})
	_orient(_live[-1])
	spawned += 1


func _new_puff() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = material
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 0.5
	add_child(mi)
	return mi


func _build_material() -> void:
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("cells", Vector2(NX, NY))
	material.set_shader_parameter("grid", Vector2(FRAMES, VARIANTS))
	material.set_shader_parameter("detail", _noise_tex())
	_quad = QuadMesh.new()
	var size := Vector2(NX, NY) * CELL
	_quad.size = size
	# 판 원점 = 입 칸 가운데. 판은 원점에서 +x(날숨 방향)·+y(위)로 펼쳐진다.
	var src := (Vector2(SRC) - Vector2(0.5, 0.5)) * CELL
	_quad.center_offset = Vector3(0.5 * size.x - src.x, 0.5 * size.y - src.y, 0.0)


## 이음매 없는 두 겹 노이즈(결 비틀기·옅은 구멍).
func _noise_tex() -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.seed = 53
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.frequency = 0.03
	fn.fractal_octaves = 3
	var t := NoiseTexture2D.new()
	t.width = 96
	t.height = 96
	t.seamless = true
	t.generate_mipmaps = true
	t.noise = fn
	return t


# ───────────────────────── 굽기(작업 스레드) ─────────────────────────

## 날숨 VARIANTS 가지를 풀어 (NX+2)×(NY+2) 밀도장 FRAMES 장씩 아틀라스로 굽는다.
## 가로 = 시간, 세로 = 변형. 전체 최댓값으로 정규화해 0..1 로 담는다.
func _bake() -> void:
	var t0 := Time.get_ticks_usec()
	var tw := NX + 2
	var th := NY + 2
	var data := PackedFloat32Array()
	data.resize(tw * FRAMES * th * VARIANTS)
	data.fill(0.0)
	var peak := 0.0
	for vi in VARIANTS:
		var frames := simulate_exhale(vi)
		for fi in FRAMES:
			var d: PackedFloat32Array = frames[fi]
			for y in th:
				var row := (vi * th + y) * tw * FRAMES + fi * tw
				for x in tw:
					var val := d[x + tw * y]
					data[row + x] = val
					peak = maxf(peak, val)
	if peak > 0.0:
		var inv := 1.0 / peak
		for k in data.size():
			data[k] = minf(data[k] * inv, 1.0)
	atlas_image = Image.create_from_data(tw * FRAMES, th * VARIANTS, false, Image.FORMAT_RF, data.to_byte_array())
	bake_usec = Time.get_ticks_usec() - t0


## 날숨 한 번을 풀어 FRAMES 장의 밀도장(경계 칸 포함)을 돌려준다. 변형마다 숨의 세기·길이·흔들림이 다르다.
## 정적 함수가 아닌 이유: 검증 스크립트가 같은 설정으로 다시 풀어 본다.
func simulate_exhale(variant: int) -> Array:
	var f = Fluid.new(NX, NY)
	f.buoyancy = 13.0             # 따뜻한 숨이라 천천히 떠오른다
	f.cooling = 0.7               # 식으면서 부력이 줄고 그 자리에 머물며 흩어진다
	f.weight = 0.0
	f.vorticity = 2.4             # 앞으로 뻗다 말려 오르는 소용돌이
	f.dissipation = 0.3
	f.diffusion = 1.6             # 가장자리를 무르게(선명한 윤곽 없이)
	f.iterations = 10
	f.wind = 0.0
	f.wind_rate = 0.45            # 정지 공기의 저항: 날숨 기세가 차츰 죽는다
	var n := FastNoiseLite.new()
	n.seed = 101 + variant * 37
	n.frequency = 2.2
	var strength: float = [1.0, 1.15, 0.88][variant % 3]
	var exhale := 0.42 + 0.08 * float(variant % 3)      # 내쉬는 시간(초)
	var out: Array = []
	var t := 0.0
	var step_i := 0
	while out.size() < FRAMES:
		if t < exhale:
			# 처음엔 세게, 끝으로 갈수록 약하게(부드러운 날숨 곡선)
			var env := sin(PI * minf(t / exhale, 1.0)) * (1.0 - 0.35 * t / exhale)
			var wob := n.get_noise_1d(t * 6.0)
			var speed := 30.0 * strength * env
			# 입 앞으로 뻗는 분출 줄기 전체에 속도를 건다(입 칸에만 걸면 압력 투영이 거의 상쇄한다).
			for j in range(SRC.y - 1, SRC.y + 2):
				var prof := 1.0 if j == SRC.y else 0.55
				for i in range(SRC.x - 1, SRC.x + JET):
					var k: int = f.idx(i, j)
					var along := 1.0 - 0.75 * float(i - SRC.x + 1) / float(JET + 1)
					f.u[k] = maxf(f.u[k], speed * prof * along)
					f.v[k] = speed * (0.1 + 0.18 * wob) * prof * along
				for i in range(SRC.x - 1, SRC.x + 2):
					var k: int = f.idx(i, j)
					f.dens[k] += 9.0 * env * prof * STEP
					f.temp[k] = maxf(f.temp[k], 0.8 * env)
		f.step(STEP)
		t += STEP
		step_i += 1
		if step_i % RECORD_EVERY == 0:
			out.append(f.dens.duplicate())
	return out


func _upload() -> void:
	_atlas_tex = ImageTexture.create_from_image(atlas_image)
	material.set_shader_parameter("atlas", _atlas_tex)
	_baked = true


# ───────────────────────── 매 프레임 ─────────────────────────

func _process(dt: float) -> void:
	if _task != -1:
		if WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			_upload()
		return
	if _live.is_empty():
		return
	var wind := Vector3.ZERO
	if weather != null and is_instance_valid(weather) and weather.has_method("wind_vector"):
		wind = weather.wind_vector()
	var i := 0
	while i < _live.size():
		var p: Dictionary = _live[i]
		p["age"] = float(p["age"]) + dt
		var mi: MeshInstance3D = p["node"]
		if float(p["age"]) >= float(p["life"]):
			mi.visible = false
			_free.append(mi)
			_live.remove_at(i)
			continue
		var a := float(p["age"]) / float(p["life"])
		# 흩어진 김은 바람을 타고 밀려간다(처음엔 날숨 기세에 가려 약하게).
		p["pos"] = (p["pos"] as Vector3) + (wind * (0.25 + 0.55 * a) + Vector3(0, 0.05, 0)) * dt
		mi.set_instance_shader_parameter("age", a)
		_orient(p)
		i += 1


func _view_camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null


## 판을 세운 채 카메라 쪽으로 돌리고, 날숨 방향이 화면 왼쪽이면 좌우를 뒤집는다.
## 카메라 쪽/반대쪽으로 내쉬면 화면에선 짧아 보이므로 가로를 줄이고 대신 조금 부풀린다.
## 내려다보는 카메라에선 입이 모자 챙·머리 아래에 묻히므로 판을 카메라 쪽으로 조금 당긴다.
## 카메라를 향해 내쉴수록 더 당기고, 등지고 내쉬면 거의 당기지 않아 머리 뒤로 가려지게 둔다.
func _orient(p: Dictionary) -> void:
	var cam := _view_camera()
	var right := cam.global_basis.x if cam != null else Vector3.RIGHT
	right.y = 0.0
	right = right.normalized() if right.length() > 1e-4 else Vector3.RIGHT
	var fwd := right.cross(Vector3.UP)
	var dir: Vector3 = p["dir"]
	var side := dir.dot(right)
	var k: float = p["scale"]
	var sx := k * lerpf(0.55, 1.0, absf(side)) * (1.0 if side >= 0.0 else -1.0)
	var sy := k * lerpf(1.15, 1.0, absf(side))
	var toward := maxf(dir.dot(fwd), 0.0)
	var pull := (PULL + PULL_FACING * toward) * k
	var mi: MeshInstance3D = p["node"]
	mi.global_basis = Basis(right * sx, Vector3.UP * sy, fwd)
	mi.global_position = (p["pos"] as Vector3) + fwd * pull
