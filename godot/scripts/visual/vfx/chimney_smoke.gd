extends Node3D
## 산장 굴뚝 연기. Jos Stam 의 Stable Fluids(stable_fluid.gd)로 굴뚝 위 세로 단면의 공기 흐름을 풀고,
## 그 밀도장을 카메라 쪽(수평)으로 돌린 세로 판에 셰이더로 그린다.
## - 굴뚝 입구 = 바닥 경계의 유입구. 불 세기(퍼프)와 좌우 흔들림을 느린 노이즈로 바꿔 숨 쉬듯 뿜는다.
## - 바람(WeatherVfx.wind_vector)을 판의 가로축에 투영해 위로 갈수록 세게 연기를 끈다. 돌풍 때 눕는다.
## - 풀이는 작업 스레드에서 30Hz 로 돌리고, 화면은 직전/현재 밀도장을 보간해 매 프레임 부드럽게 그린다.
## 노드 위치는 굴뚝 꼭대기(Layout.CHIMNEY_TOP)다. 판은 자식 "Plume" 이 가진다.

const Fluid := preload("res://scripts/visual/vfx/stable_fluid.gd")
const SHADER := preload("res://shaders/chimney_smoke.gdshader")

const NX := 40
const NY := 56
const CELL := 0.11                # 칸 한 변(m) → 판 4.4m × 6.2m
const STEP := 1.0 / 30.0          # 시뮬레이션 간격(초)
const MOUTH := Vector2i(10, 11)   # 굴뚝 입구 칸 범위 = 연도 구멍 안쪽 폭(≈0.22m). 바람 반대편(왼쪽)에 여유를 둔다
const WARMUP := 2.5               # 처음 보일 때 이미 피어오른 상태가 되도록 미리 돌리는 시간(초)
const MOUTH_SINK := 0.25          # 판 바닥 = 연도 구멍 안(테두리 0.25m 아래). 연기가 구멍 속에서 솟아나 흘러나온다

var fluid
var weather                       # WeatherVfx(바람). 없으면 잔잔한 기본 바람
var camera: Camera3D              # 판을 돌릴 기준. 없으면 현재 뷰포트 카메라
var threaded := true              # false 면 메인 스레드에서 바로 푼다(검증용)
var sim_time := 0.0               # 지금까지 푼 시뮬레이션 시간(초)
var steps := 0
var last_step_usec := 0
var wind_cells := 0.0             # 지금 판 가로축 바람(칸/초)

var plume: MeshInstance3D
var material: ShaderMaterial
var _img_prev: Image
var _tex_prev: ImageTexture
var _tex_cur: ImageTexture
var _noise := FastNoiseLite.new()
var _acc := 0.0
var _since_publish := 0.0
var _task := -1
var _ready_to_show := false


func _init() -> void:
	name = "ChimneySmoke"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	fluid = Fluid.new(NX, NY)
	fluid.buoyancy = 7.0
	fluid.cooling = 0.15
	fluid.weight = 0.0
	fluid.vorticity = 1.6
	fluid.dissipation = 0.11
	fluid.iterations = 10
	# 판 바닥은 연도 구멍 안이다: 테두리 높이까지 구멍 양옆 칸을 벽(고체)으로 막아 연기가 위로만 나오게 한다.
	var rim_rows := maxi(int(round(MOUTH_SINK / CELL)), 1)
	fluid.add_solid(MOUTH.x - 1, MOUTH.x - 1, 1, rim_rows)
	fluid.add_solid(MOUTH.y + 1, MOUTH.y + 1, 1, rim_rows)
	_noise.seed = 7
	_noise.frequency = 0.8
	_build_plume()
	_feed_inputs()
	_launch(int(WARMUP / STEP))


func _exit_tree() -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1


func _build_plume() -> void:
	var empty := Image.create(NX + 2, NY + 2, false, Image.FORMAT_RF)
	_tex_prev = ImageTexture.create_from_image(empty)
	_tex_cur = ImageTexture.create_from_image(empty)
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("dens_prev", _tex_prev)
	material.set_shader_parameter("dens_cur", _tex_cur)
	material.set_shader_parameter("detail", _rgb_noise())
	material.set_shader_parameter("cells", Vector2(NX, NY))
	material.set_shader_parameter("fade", 0.0)
	var quad := QuadMesh.new()
	var size := Vector2(NX, NY) * CELL
	quad.size = size
	var mouth_x := (0.5 * float(MOUTH.x + MOUTH.y) - 0.5) * CELL   # 입구 가운데의 판 왼쪽 끝 기준 위치
	quad.center_offset = Vector3(0.5 * size.x - mouth_x, 0.5 * size.y - MOUTH_SINK, 0.0)
	plume = MeshInstance3D.new()
	plume.name = "Plume"
	plume.mesh = quad
	plume.material_override = material
	plume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	plume.extra_cull_margin = 1.0
	add_child(plume)


## 세 채널이 서로 다른 무늬인 이음매 없는 노이즈(셰이더의 결 비틀기·밀도 결).
func _rgb_noise() -> ImageTexture:
	var n := 96
	var img := Image.create(n, n, true, Image.FORMAT_RGB8)
	var chans: Array[FastNoiseLite] = []
	for c in 3:
		var fn := FastNoiseLite.new()
		fn.seed = 31 + c * 17
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.045 if c < 2 else 0.07
		fn.fractal_octaves = 3
		chans.append(fn)
	# 원환면(4D 대신 두 원)으로 감아 가장자리가 이어지게 한다.
	for y in n:
		for x in n:
			var ax := TAU * float(x) / n
			var ay := TAU * float(y) / n
			var col := Color()
			for c in 3:
				var r := 18.0
				var val := chans[c].get_noise_3d(cos(ax) * r, sin(ax) * r, cos(ay) * r + sin(ay) * 7.0)
				col[c] = clampf(0.5 + 0.6 * val, 0.0, 1.0)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _process(dt: float) -> void:
	_face_camera()
	_since_publish += dt
	if _task != -1:
		if not WorkerThreadPool.is_task_completed(_task):
			_update_blend()
			return
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_publish()
	_acc = minf(_acc + dt, STEP * 4.0)
	if _acc >= STEP and _should_simulate():
		_acc -= STEP
		_feed_inputs()
		_launch(1)
	_update_blend()


## 시뮬레이션 시간을 seconds 만큼 바로(동기) 진행한다. 검증·캡처용.
func simulate(seconds: float) -> void:
	if _task != -1:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_publish()
	var n := int(round(seconds / STEP))
	for i in n:
		_feed_inputs()
		_run_steps(1)
	_publish()
	_since_publish = STEP


func _should_simulate() -> bool:
	if not is_visible_in_tree():
		return false
	return true


## 굴뚝 불의 숨결: 시뮬레이션 시간에 따라 뿜는 세기(퍼프)와 좌우 흔들림을 바꾼다.
## 노이즈만 읽으므로 풀이 스레드 안에서 매 단계 불러도 된다.
func _breathe() -> void:
	var t := sim_time
	var puff := clampf(0.78 + 0.32 * _noise.get_noise_1d(t) + 0.12 * _noise.get_noise_1d(t * 3.1 + 40.0), 0.35, 1.2)
	var sway := 2.6 * _noise.get_noise_1d(t * 1.7 + 90.0)
	fluid.set_inflow(MOUTH.x, MOUTH.y, 11.0 * puff, 3.0 * puff, 1.0, sway * 0.6)


## 바람을 유체 입력으로 넣는다(카메라·날씨를 읽으므로 메인 스레드에서, 풀이 시작 전에).
func _feed_inputs() -> void:
	var w := Vector3(0.42, 0.0, 0.2)
	if weather != null and is_instance_valid(weather) and weather.has_method("wind_vector"):
		w = weather.wind_vector()
	var right := _plane_right()
	wind_cells = w.dot(right) / CELL
	fluid.wind = wind_cells


func _launch(n: int) -> void:
	if threaded:
		_task = WorkerThreadPool.add_task(_run_steps.bind(n), false, "chimney smoke")
	else:
		_run_steps(n)
		_publish()


func _run_steps(n: int) -> void:
	var t0 := Time.get_ticks_usec()
	for i in n:
		_breathe()
		fluid.step(STEP)
		sim_time += STEP
		steps += 1
	last_step_usec = (Time.get_ticks_usec() - t0) / maxi(n, 1)


## 풀이 결과를 텍스처로 올린다: 지금 것은 '직전'으로 밀고 새 밀도장을 '현재'로.
func _publish() -> void:
	var img := Image.create_from_data(NX + 2, NY + 2, false, Image.FORMAT_RF, fluid.dens.to_byte_array())
	if _img_prev != null:
		_tex_prev.update(_img_prev)
	else:
		_tex_prev.update(img)
	_tex_cur.update(img)
	_img_prev = img
	_since_publish = 0.0
	_ready_to_show = true


func _update_blend() -> void:
	material.set_shader_parameter("blend", clampf(_since_publish / STEP, 0.0, 1.0))
	var f: float = material.get_shader_parameter("fade")
	if _ready_to_show and f < 1.0:
		material.set_shader_parameter("fade", minf(f + get_process_delta_time() * 1.5, 1.0))


func _view_camera() -> Camera3D:
	if camera != null and is_instance_valid(camera):
		return camera
	return get_viewport().get_camera_3d() if is_inside_tree() else null


## 판의 가로축(월드, 수평). 카메라 오른쪽을 수평으로 눕힌 방향.
func _plane_right() -> Vector3:
	var cam := _view_camera()
	var r := cam.global_basis.x if cam != null else Vector3(cos(deg_to_rad(35.0)), 0.0, -sin(deg_to_rad(35.0)))
	r.y = 0.0
	return r.normalized() if r.length() > 1e-4 else Vector3.RIGHT


## 판을 세운 채(세로축 고정) 카메라 쪽으로 돌린다.
func _face_camera() -> void:
	var right := _plane_right()
	var fwd := right.cross(Vector3.UP)   # 판 앞면(+Z) = 카메라 쪽
	plume.global_basis = Basis(right, Vector3.UP, fwd)
