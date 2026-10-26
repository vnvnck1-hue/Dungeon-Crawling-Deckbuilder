extends Node3D
## 숲길 원정대의 3D 무대: 환경·달빛·카메라·지면·숲 프랍·방(공터)·방 사이 좁은 길. 표시 전용(판정은 core/battle.gd).
## 마녀산장 world.gd 의 환경·후처리·화면 스타일(ScreenStyle)·VFX 풀 구성을 그대로 따르고, 산장 고정 구도만 뺐다.
## ScreenStyle.apply(self, id) 가 쓰는 필드(env·sun·ground_mat·post_mat·outline_mesh·outline_mat·reference_lighting)를 가진다.

const D := preload("res://dungeon/data/defs.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Models := preload("res://scripts/visual/models.gd")
const Nature := preload("res://scripts/visual/nature_models.gd")
const ScreenStyle := preload("res://scripts/visual/screen_style.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const VfxPool := preload("res://scripts/visual/vfx/vfx_pool.gd")
const FireVfx := preload("res://scripts/visual/vfx/fire_vfx.gd")
const WeatherVfx := preload("res://scripts/visual/vfx/weather_vfx.gd")
const BreathVapor := preload("res://scripts/visual/vfx/breath_vapor.gd")
const AerialPerspective := preload("res://scripts/visual/aerial_perspective.gd")
const HAZE_SHADER := preload("res://shaders/ground_haze.gdshader")
const GROUND_SHADER := preload("res://dungeon/shaders/dungeon_ground.gdshader")
const TILE_SHADER := preload("res://dungeon/shaders/board_tiles.gdshader")
const POST_SHADER := preload("res://shaders/post_grade.gdshader")
const OUTLINE_SHADER := preload("res://shaders/toon_outline.gdshader")
const GROUND_SNOW := preload("res://assets/ground/painted_snow_v1.png")
const GROUND_TRAIL := preload("res://assets/ground/painted_trail_v1.png")
const GROUND_FOREST := preload("res://assets/ground/painted_forest_v1.png")

const SCREEN_STYLE := "toon_midnight"
const TILE := 2.0
## 전장을 칼바람 나락처럼 사선으로: 진행 방향(열이 늘어나는 쪽)이 화면 오른쪽 위로 기운다
const LANE_DEG := 28.0
const BOARD_HALF := Vector2(D.COLS * TILE * 0.5, D.ROWS * TILE * 0.5)
const CLEAR_HALF := Vector2(10.6, 6.4)    # 공터(나무가 서지 않는 곳) 반 크기
const ROOM_STEP := 30.0                   # 방과 방 사이 진행 거리
const JOGS := [7.0, -8.0, 6.0, -7.0, 5.0]
const PATH_WIDTH := 1.7                   # 좁은 숲길 폭(나무는 그 바깥부터)
const ENTRY_LEN := 18.0                   # 첫 방 앞의 들어오는 길
## 마녀산장 날씨 모듈이 산장 자리(원점 근처)에 반딧불·굴뚝 불씨·야영지 불을 뿌리므로 던전은 멀리 떨어진 곳에 놓는다
const ORIGIN := Vector3(160.0, 0.0, 120.0)
const SPOT_LAYER := 20                    # 딤드 강조 때 어둠 위에 다시 그리는 렌더 레이어
## 카메라(쿼터뷰): 살짝 사선 위에서. 화면 아래쪽은 손패가 덮으므로 초점을 공터보다 카메라 쪽으로 당긴다
const CAM_FOV := 34.0
const CAM_PITCH := 52.0
const CAM_YAW := 0.0
const CAM_HEIGHT := 15.2                  # 초점 거리에서 보이는 세로 폭(m) — 행군·타이틀
const CAM_HEIGHT_BATTLE := 13.2           # 전투: 더 당겨서 캐릭터가 화면에 크게 들어온다(맨 뒷줄 적·보스 체력 막대가 잘리지 않는 선)
const CAM_FOCUS_OFFSET := Vector3(0.6, 0, 2.3)
const CAM_FOCUS_OFFSET_BATTLE := Vector3(0.6, 0, 1.0)   # 전투 초점(손패가 아래를 덮으므로 격자를 조금 위로 올린다)
const AMBIENT_COLOR := Color(0.65, 0.69, 0.93)
const MOON_COLOR := Color(0.94, 0.92, 1.0)
const MOON_ROT := Vector3(-64.0, 145.0, 0.0)

var env: Environment
var sun: DirectionalLight3D
var camera: Camera3D
var ground_mat: ShaderMaterial
var post_mat: ShaderMaterial
var outline_mesh: MeshInstance3D
var outline_mat: ShaderMaterial
var reference_lighting: RoomLights
var vfx_pool
var snow: GPUParticles3D
var weather              # 마녀산장 WeatherVfx: 돌풍·눈보라·바람 줄기·나뭇잎·나무에서 털리는 눈
var breath               # 마녀산장 BreathVapor: 차가운 공기 속 입김
var aerial_perspective   # 마녀산장 AerialPerspective: 깊이 안개 + 주변 불빛 색이 번지는 공기
## 마녀산장 모듈이 읽는 자리(던전에는 없는 것은 null)
var game = null
var day_cycle = null
var player_camera = null        # build() 에서 self. AerialPerspective 가 focus·follow_enabled 를 읽는다
var follow_enabled := true
var camera_occluders: Array = []   # WeatherVfx 가 나무 자리를 읽는다(= occluders)
var _spot_layer: CanvasLayer
var _spot_dim: ColorRect
var _spot_vp: SubViewport
var _spot_cam: Camera3D
var _spot_nodes: Array = []
var _spot_tw: Tween

var lane := Vector3.ZERO      # 열 방향(아군 → 적)
var perp := Vector3.ZERO      # 행 방향
var rooms: Array = []         # {center, exit, entry, tiles(MeshInstance3D), tile_mat, state(Image), state_tex}
var paths: Array = []         # 방 i → i+1 길(점 목록). paths[0] 앞의 entry_path 는 첫 방으로 들어오는 길
var entry_path: Array = []

var focus := Vector3.ZERO
var _focus_target := Vector3.ZERO
var _follow_speed := 3.0
## 카메라 줌: 초점 거리에서 보이는 세로 폭(m). 행군 때는 CAM_HEIGHT, 전투 때는 CAM_HEIGHT_BATTLE 로 당겨 캐릭터가 크게 보인다.
var cam_height := CAM_HEIGHT
var _cam_height_target := CAM_HEIGHT
var _zoom_speed := 2.0
var _shake_t := 0.0
var _shake_amp := 0.0
var _rng := RandomNumberGenerator.new()


class RoomLights extends Node3D:
	## 레퍼런스 색 웅덩이(마녀산장 reference_lighting.gd 의 방 단위 판): 방마다 자홍·청 조명 몇 개. configure(p) 는 ScreenStyle 이 부른다.
	var lights: Array = []    # [OmniLight3D, energy, magenta?]

	func add_pool(at: Vector3, light_range: float, energy: float, magenta: bool) -> void:
		var l := OmniLight3D.new()
		l.position = at
		l.omni_range = light_range
		l.omni_attenuation = 1.25
		l.light_specular = 0.0
		l.shadow_enabled = false
		add_child(l)
		lights.append([l, energy, magenta])

	var hazes: Array = []    # [MeshInstance3D, ShaderMaterial]

	func add_haze(at: Vector3, size: Vector2) -> void:
		var mesh := MeshInstance3D.new()
		mesh.name = "GroundHaze"
		var plane := PlaneMesh.new()
		plane.size = size
		mesh.mesh = plane
		mesh.position = at
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := ShaderMaterial.new()
		m.shader = HAZE_SHADER
		mesh.material_override = m
		add_child(mesh)
		hazes.append([mesh, m])

	func configure(p: Dictionary) -> void:
		for h in hazes:
			h[0].visible = p.rig_energy > 0.0 and p.haze_opacity > 0.0
			h[1].set_shader_parameter("opacity", p.haze_opacity * 1.6)
			h[1].set_shader_parameter("haze_color", p.magenta_color)
		for e in lights:
			var l: OmniLight3D = e[0]
			l.visible = p.rig_energy > 0.0
			l.light_energy = float(e[1]) * p.rig_energy
			l.light_color = p.magenta_color if e[2] else p.cyan_color


func build() -> void:
	_rng.seed = 20261026
	player_camera = self
	var a := deg_to_rad(LANE_DEG)
	lane = Vector3(cos(a), 0, -sin(a))
	perp = Vector3(sin(a), 0, cos(a))
	_layout_rooms()
	_build_environment()
	_build_camera()
	_build_ground()
	_build_post()
	vfx_pool = VfxPool.new()
	add_child(vfx_pool)
	Fx.pool = vfx_pool
	_build_snow()
	reference_lighting = RoomLights.new()
	reference_lighting.name = "RoomLights"
	add_child(reference_lighting)
	for i in rooms.size():
		_build_room(i)
	_build_forest()
	camera_occluders = occluders
	focus_on(room_focus(0), true)
	# 날씨·입김·공기 원근(마녀산장 world._build_fx / aerial_perspective 와 같은 연결)
	weather = WeatherVfx.new()
	weather.world = self
	weather.pool = vfx_pool
	weather.snowfall = snow
	add_child(weather)
	breath = BreathVapor.new()
	breath.camera = camera
	breath.weather = weather
	add_child(breath)
	ScreenStyle.apply(self, SCREEN_STYLE)
	aerial_perspective = AerialPerspective.new()
	aerial_perspective.name = "AerialPerspective"
	add_child(aerial_perspective)
	aerial_perspective.bind(self)
	_build_spotlight()


# ───────────────────────── 방·길 배치 ─────────────────────────

func _layout_rooms() -> void:
	var c := ORIGIN
	for i in D.ROOMS.size():
		if i > 0:
			c += lane * ROOM_STEP + perp * float(JOGS[(i - 1) % JOGS.size()])
		rooms.append({"center": c, "exit": c + lane * (CLEAR_HALF.x + 0.5), "entry": c - lane * (CLEAR_HALF.x + 0.5)})
	for i in rooms.size() - 1:
		paths.append(_wiggle(rooms[i].exit, rooms[i + 1].entry, i))
	var start: Vector3 = rooms[0].entry - lane * ENTRY_LEN - perp * 4.0
	entry_path = _wiggle(start, rooms[0].entry, 99)


## 두 점 사이 구불구불한 좁은 길(점 7개).
func _wiggle(from: Vector3, to: Vector3, seed_i: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = 77 + seed_i * 13
	var pts: Array = [from]
	var side := perp
	for k in range(1, 6):
		var u := k / 6.0
		var bend := sin(u * PI) * r.randf_range(-3.5, 3.5) + r.randf_range(-0.8, 0.8)
		pts.append(from.lerp(to, u) + side * bend)
	pts.append(to)
	return pts


## 칸(열, 행) → 그 방의 세계 좌표(칸 가운데, 지면).
func cell_pos(room_i: int, cell: Vector2i) -> Vector3:
	var c: Vector3 = rooms[room_i].center
	return c + lane * ((cell.x + 0.5) * TILE - BOARD_HALF.x) + perp * ((cell.y + 0.5) * TILE - BOARD_HALF.y)


## 세계 좌표 → 칸. 격자 밖이면 (-1, -1).
func pos_cell(room_i: int, p: Vector3) -> Vector2i:
	var q: Vector3 = p - rooms[room_i].center
	var x := floori((q.dot(lane) + BOARD_HALF.x) / TILE)
	var y := floori((q.dot(perp) + BOARD_HALF.y) / TILE)
	var c := Vector2i(x, y)
	return c if D.in_board(c) else Vector2i(-1, -1)


func room_focus(i: int) -> Vector3:
	return rooms[i].center + CAM_FOCUS_OFFSET_BATTLE


## 화면 좌표 → 지면(y=0) 위의 점. 못 맞히면 INF.
func ground_at(screen: Vector2) -> Vector3:
	var from := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3.INF
	var t := -from.y / dir.y
	return from + dir * t if t > 0.0 else Vector3.INF


# ───────────────────────── 카메라 ─────────────────────────

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.fov = CAM_FOV
	camera.near = 0.5
	camera.far = 160.0
	camera.rotation_degrees = Vector3(-CAM_PITCH, CAM_YAW, 0)
	add_child(camera)
	camera.current = true


func focus_on(p: Vector3, instant := false, speed := 3.0) -> void:
	_focus_target = p
	_follow_speed = speed
	if instant:
		focus = p
		_place_camera()


## 줌: 보이는 세로 폭(m)을 바꾼다. instant 면 바로, 아니면 speed 로 부드럽게.
func set_zoom(height: float, instant := false, speed := 2.0) -> void:
	_cam_height_target = height
	_zoom_speed = speed
	if instant:
		cam_height = height
		_place_camera()


func _place_camera() -> void:
	var dist := cam_height * 0.5 / tan(deg_to_rad(CAM_FOV) * 0.5)
	camera.position = focus + camera.transform.basis.z * dist
	if snow != null:
		snow.position = focus + Vector3(0, 13, -4)


class StormState extends RefCounted:
	var session := {"state": 0}
	var player = null


## 보스 방: 마녀산장 밤 전투처럼 눈보라가 몰아친다. 평소에는 가끔 돌풍.
func set_storm(on: bool) -> void:
	if game == null:
		game = StormState.new()
	game.session["state"] = 1 if on else 0


func shake(amount: float, duration: float) -> void:
	_shake_amp = maxf(_shake_amp, amount)
	_shake_t = maxf(_shake_t, duration)


func _process(delta: float) -> void:
	focus = focus.lerp(_focus_target, 1.0 - exp(-delta * _follow_speed))
	cam_height = lerpf(cam_height, _cam_height_target, 1.0 - exp(-delta * _zoom_speed))
	_place_camera()
	_update_occlusion(delta)
	_sync_spot_camera()
	if _shake_t > 0.0:
		_shake_t -= delta
		var s := _shake_amp * clampf(_shake_t / 0.3, 0.0, 1.0)
		camera.h_offset = randf_range(-s, s)
		camera.v_offset = randf_range(-s, s)
		if _shake_t <= 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
			_shake_amp = 0.0


# ───────────────────────── 환경·지면·후처리 ─────────────────────────

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b2552")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = 0.65
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4] else 0.0)
	env.ssao_enabled = true
	env.ssao_detail = 0.4
	env.ssao_light_affect = 0.15
	env.adjustment_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.8
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Moonlight"
	sun.light_color = MOON_COLOR
	sun.light_energy = 0.6
	sun.light_specular = 0.0
	sun.rotation_degrees = MOON_ROT
	sun.shadow_enabled = true
	sun.shadow_bias = 0.18
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _build_ground() -> void:
	var lo := Vector3(INF, 0, INF)
	var hi := Vector3(-INF, 0, -INF)
	for p in _all_route_points():
		lo = Vector3(minf(lo.x, p.x), 0, minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), 0, maxf(hi.z, p.z))
	var pad := 50.0
	var plane := PlaneMesh.new()
	plane.size = Vector2(hi.x - lo.x + pad * 2.0, hi.z - lo.z + pad * 2.0)
	plane.subdivide_width = 0
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = GROUND_SHADER
	ground_mat.set_shader_parameter("painted_snow", GROUND_SNOW)
	ground_mat.set_shader_parameter("painted_trail", GROUND_TRAIL)
	ground_mat.set_shader_parameter("painted_forest", GROUND_FOREST)
	var segs := PackedVector4Array()
	for path in [entry_path] + paths:
		for i in path.size() - 1:
			segs.append(Vector4(path[i].x, path[i].z, path[i + 1].x, path[i + 1].z))
	ground_mat.set_shader_parameter("trail_count", mini(segs.size(), 64))
	segs.resize(64)
	ground_mat.set_shader_parameter("trail_segments", segs)
	ground_mat.set_shader_parameter("trail_width", PATH_WIDTH)
	var rv := PackedVector4Array()
	for r in rooms:
		rv.append(Vector4(r.center.x, r.center.z, CLEAR_HALF.x - 1.2, CLEAR_HALF.y - 1.0))
	ground_mat.set_shader_parameter("room_count", rooms.size())
	rv.resize(8)
	ground_mat.set_shader_parameter("rooms", rv)
	ground_mat.set_shader_parameter("room_axis", Vector2(lane.x, lane.z))
	var mi := MeshInstance3D.new()
	mi.name = "Ground"
	mi.mesh = plane
	mi.material_override = ground_mat
	mi.position = (lo + hi) * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_post() -> void:
	outline_mesh = MeshInstance3D.new()
	outline_mesh.name = "ToonOutline"
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	outline_mesh.mesh = quad
	outline_mesh.extra_cull_margin = 16384.0
	outline_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	outline_mesh.position.z = -2.0
	outline_mat = ShaderMaterial.new()
	outline_mat.shader = OUTLINE_SHADER
	outline_mat.render_priority = 127
	outline_mesh.material_override = outline_mat
	outline_mesh.visible = false
	camera.add_child(outline_mesh)
	var layer := CanvasLayer.new()
	layer.name = "PostGrade"
	layer.layer = 1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = POST_SHADER
	rect.material = post_mat
	layer.add_child(rect)


## 눈 내림(마녀산장 world._build_fx 와 같은 값). 카메라 초점을 따라다닌다.
func _build_snow() -> void:
	snow = GPUParticles3D.new()
	snow.name = "Snowfall"
	snow.amount = 140
	snow.lifetime = 10.0
	snow.preprocess = 10.0
	snow.local_coords = false
	snow.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(30, 0.5, 24)
	pm.direction = Vector3(0.25, -1, 0.1)
	pm.spread = 12.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 1.6
	pm.gravity = Vector3(0, -0.15, 0)
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.6
	pm.turbulence_noise_scale = 6.0
	pm.turbulence_influence_min = 0.02
	pm.turbulence_influence_max = 0.06
	pm.scale_min = 0.3
	pm.scale_max = 0.65
	snow.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.11, 0.11)
	q.material = Mats.particle(Color(0.95, 0.94, 1.0, 0.85))
	snow.draw_pass_1 = q
	add_child(snow)


# ───────────────────────── 방(격자·모닥불·조명) ─────────────────────────

func _build_room(i: int) -> void:
	var r: Dictionary = rooms[i]
	var c: Vector3 = r.center
	# 격자 오버레이: UV.x = 열 비율, UV.y = 행 비율이 되도록 평면을 방 축에 맞춰 돌린다
	var plane := PlaneMesh.new()
	plane.size = Vector2(BOARD_HALF.x * 2.0, BOARD_HALF.y * 2.0)
	var tiles := MeshInstance3D.new()
	tiles.name = "Board%d" % i
	tiles.mesh = plane
	tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	tiles.transform = Transform3D(Basis(lane, Vector3.UP, perp), c + Vector3(0, 0.04, 0))
	var img := Image.create(D.COLS, D.ROWS, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var tex := ImageTexture.create_from_image(img)
	var m := ShaderMaterial.new()
	m.shader = TILE_SHADER
	m.set_shader_parameter("cell_state", tex)
	m.set_shader_parameter("grid", Vector2(D.COLS, D.ROWS))
	m.set_shader_parameter("ally_cols", float(D.ALLY_COLS))
	m.set_shader_parameter("reveal", 0.0)
	tiles.material_override = m
	add_child(tiles)
	r["tiles"] = tiles
	r["tile_mat"] = m
	r["state"] = img
	r["state_tex"] = tex
	# 아군 진영 뒤쪽 모닥불(마녀산장 lodge_yard 모닥불과 같은 조립) + 적 진영 뒤 화로 둘
	var warm := []
	var fire_at := c - lane * (BOARD_HALF.x + 1.3) + perp * 2.2
	_campfire(fire_at, 0.75)
	warm.append(Vector4(fire_at.x, fire_at.z, 3.2, 0.9))
	for s in [-1.0, 1.0]:
		var at: Vector3 = c + lane * (BOARD_HALF.x + 1.2) + perp * s * (BOARD_HALF.y + 0.4)
		_brazier(at)
		warm.append(Vector4(at.x, at.z, 2.2, 0.6))
	r["warm"] = warm
	# 색 웅덩이: 적 쪽 자홍, 아군 쪽 청
	reference_lighting.add_pool(c + lane * 6.0 + Vector3(0, 3.0, 0) - perp * 4.0, 11.0, 3.2, true)
	reference_lighting.add_pool(c - lane * 5.0 + Vector3(0, 4.5, 0) + perp * 3.0, 12.0, 1.1, false)
	reference_lighting.add_pool(c + perp * 7.0 + Vector3(0, 3.0, 0), 9.0, 1.6, true)
	reference_lighting.add_haze(c + lane * 9.0 - perp * 5.0 + Vector3(0, 0.4, 0), Vector2(14, 10))
	reference_lighting.add_haze(c - lane * 11.0 + perp * 6.0 + Vector3(0, 0.35, 0), Vector2(12, 9))
	var all_warm := PackedVector4Array()
	for rr in rooms:
		if rr.has("warm"):
			for w in rr.warm:
				all_warm.append(w)
	ground_mat.set_shader_parameter("warm_count", mini(all_warm.size(), 16))
	all_warm.resize(16)
	ground_mat.set_shader_parameter("warm_spots", all_warm)


func _campfire(at: Vector3, s: float) -> void:
	var camp := B.node(self, at, Vector3.ZERO, "Campfire")
	var wood := Models.make_firewood()
	wood.scale = Vector3.ONE * 0.8 * s
	wood.rotation_degrees.y = _rng.randf_range(0, 360)
	camp.add_child(wood)
	B.cyl(camp, 0.3 * s, 0.42 * s, 0.12, Vector3(0, 0.2, 0), Mats.glow(Color(1.0, 0.45, 0.15), 2.5), 8)
	var fire := FireVfx.new()
	fire.preset = "hearth"
	fire.size = 0.85 * s
	fire.smoke_opacity = 0.85
	fire.with_light = false
	fire.position = Vector3(0, 0.22, 0)
	camp.add_child(fire)
	B.omni(camp, Vector3(0, 1.1, 0), Color(1.0, 0.64, 0.3), 1.5, 8.0)
	for k in 2:
		var log_prop := Models.make_log()
		var ang := _rng.randf_range(0, TAU)
		log_prop.position = Vector3(cos(ang), 0, sin(ang)) * 1.5
		log_prop.rotation_degrees.y = rad_to_deg(-ang) + 90
		log_prop.scale = Vector3.ONE * 0.65
		camp.add_child(log_prop)


## 적 진영 뒤 돌 화로: 바위 위 마녀빛(보라) 불꽃.
func _brazier(at: Vector3) -> void:
	var node := B.node(self, at, Vector3.ZERO, "Brazier")
	var rock := Nature.asset("user_rock_low")
	rock.scale = Vector3.ONE * 0.55
	rock.rotation.y = _rng.randf_range(-PI, PI)
	node.add_child(rock)
	var fire := FireVfx.new()
	fire.preset = "witch"
	fire.size = 0.5
	fire.smoke_opacity = 0.3
	fire.with_light = false
	fire.position = Vector3(0, 0.55, 0)
	node.add_child(fire)
	B.omni(node, Vector3(0, 1.4, 0), Color(0.8, 0.45, 1.0), 1.4, 6.5)


# ───────────────────────── 딤드 강조 ─────────────────────────

## 카드를 집어 겨눌 때: 화면 전체를 어둡게 덮고, 강조할 유닛(카드 주인·대상 적)과 격자만 그 위에 다시 그린다.
## 같은 World3D 를 보는 SubViewport 카메라가 SPOT_LAYER 만 그려 투명 배경으로 겹친다(표시 전용).
func _build_spotlight() -> void:
	_spot_layer = CanvasLayer.new()
	_spot_layer.name = "Spotlight"
	_spot_layer.layer = 2          # 후처리(1) 위, UI(5) 아래
	add_child(_spot_layer)
	_spot_dim = ColorRect.new()
	_spot_dim.color = Color(0.03, 0.02, 0.07, 0.0)
	_spot_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_spot_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot_layer.add_child(_spot_dim)
	var box := SubViewportContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.stretch = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_spot_layer.add_child(box)
	_spot_vp = SubViewport.new()
	_spot_vp.transparent_bg = true
	_spot_vp.msaa_3d = Viewport.MSAA_2X
	_spot_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	box.add_child(_spot_vp)
	_spot_cam = Camera3D.new()
	_spot_cam.cull_mask = 1 << (SPOT_LAYER - 1)
	var e := Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = env.ambient_light_color
	e.ambient_light_energy = env.ambient_light_energy
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_spot_cam.environment = e
	_spot_vp.add_child(_spot_cam)
	_spot_layer.visible = false


## nodes 를 강조(on) 하거나 풀기. room_i 의 격자도 어둠 위로 올린다.
func spotlight(nodes: Array, on: bool, room_i := -1) -> void:
	for n in _spot_nodes:
		if is_instance_valid(n):
			_set_spot_layer(n, false)
	_spot_nodes = nodes.duplicate() if on else []
	for n in _spot_nodes:
		_set_spot_layer(n, true)
	if on and room_i >= 0:
		_spot_nodes.append(rooms[room_i].tiles)
		_set_spot_layer(rooms[room_i].tiles, true)
	if _spot_tw != null and _spot_tw.is_valid():
		_spot_tw.kill()
	_spot_tw = create_tween()
	if on:
		_spot_layer.visible = true
		_spot_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_spot_tw.tween_property(_spot_dim, "color:a", 0.62, 0.16)
	else:
		_spot_tw.tween_property(_spot_dim, "color:a", 0.0, 0.18)
		_spot_tw.tween_callback(func() -> void:
			_spot_layer.visible = false
			_spot_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED)


func spotlight_on() -> bool:
	return _spot_layer.visible and _spot_dim.color.a > 0.3


func _set_spot_layer(n: Node, on: bool) -> void:
	var list: Array = n.find_children("*", "VisualInstance3D", true, false)
	if n is VisualInstance3D:
		list.append(n)
	for v: VisualInstance3D in list:
		v.set_layer_mask_value(SPOT_LAYER, on)


func _sync_spot_camera() -> void:
	if _spot_layer == null or not _spot_layer.visible:
		return
	_spot_cam.global_transform = camera.global_transform
	_spot_cam.fov = camera.fov
	_spot_cam.keep_aspect = camera.keep_aspect
	_spot_cam.near = camera.near
	_spot_cam.far = camera.far
	_spot_cam.h_offset = camera.h_offset
	_spot_cam.v_offset = camera.v_offset


## 칸 강조: cells 의 칸을 color(a = 세기)로. clear 가 참이면 먼저 모두 지운다.
func paint_cells(room_i: int, cells: Array, color: Color, clear := true) -> void:
	var r: Dictionary = rooms[room_i]
	var img: Image = r.state
	if clear:
		img.fill(Color(0, 0, 0, 0))
	for c in cells:
		if D.in_board(c):
			img.set_pixel(c.x, c.y, color)
	(r.state_tex as ImageTexture).update(img)


## 칸마다 다른 색을 한 번에(나중 항목이 앞 항목을 덮는다).
func paint_many(room_i: int, cells: Array, colors: Array) -> void:
	var r: Dictionary = rooms[room_i]
	var img: Image = r.state
	img.fill(Color(0, 0, 0, 0))
	for k in cells.size():
		if D.in_board(cells[k]):
			img.set_pixel(cells[k].x, cells[k].y, colors[k])
	(r.state_tex as ImageTexture).update(img)


func clear_cells(room_i: int) -> void:
	paint_cells(room_i, [], Color.TRANSPARENT)


func set_board_reveal(room_i: int, v: float) -> void:
	(rooms[room_i].tile_mat as ShaderMaterial).set_shader_parameter("reveal", v)


# ───────────────────────── 숲 ─────────────────────────

func _all_route_points() -> Array:
	var pts: Array = []
	for r in rooms:
		for sx in [-1.0, 1.0]:
			for sy in [-1.0, 1.0]:
				pts.append(r.center + lane * CLEAR_HALF.x * sx + perp * CLEAR_HALF.y * sy)
	for path in [entry_path] + paths:
		pts.append_array(path)
	return pts


## 공터까지의 거리(m). 공터 안이면 음수.
func room_distance(p: Vector3) -> float:
	var d := INF
	for r in rooms:
		var q: Vector3 = p - r.center
		var lx := absf(q.dot(lane)) - CLEAR_HALF.x
		var ly := absf(q.dot(perp)) - CLEAR_HALF.y
		var outside := Vector2(maxf(lx, 0.0), maxf(ly, 0.0)).length()
		d = minf(d, outside + minf(maxf(lx, ly), 0.0))
	return d


## 길 가운데 선까지의 거리(m).
func path_distance(p: Vector3) -> float:
	var d := INF
	var p2 := Vector2(p.x, p.z)
	for path in [entry_path] + paths:
		for i in path.size() - 1:
			var a := Vector2(path[i].x, path[i].z)
			var ab := Vector2(path[i + 1].x, path[i + 1].z) - a
			var t := clampf((p2 - a).dot(ab) / maxf(ab.length_squared(), 0.001), 0.0, 1.0)
			d = minf(d, (p2 - a - ab * t).length())
	return d


## 공터·길까지의 거리(m). 공터 안이면 음수.
func open_distance(p: Vector3) -> float:
	return minf(room_distance(p), path_distance(p) - PATH_WIDTH)


## 키 큰 나무가 서면 카메라 쪽에서 공터(격자)를 가리는가(카메라는 +Z 쪽 위에서 내려다본다).
## 길은 가려도 된다 — 지나가는 원정대를 가리는 나무는 비친다(_update_occlusion).
func _blocks_room(p: Vector3, reach: float) -> bool:
	var k := 1.0
	while k <= reach:
		if room_distance(p - Vector3(0, 0, k)) < 0.5:
			return true
		k += 1.2
	return false


var occluders: Array = []      # {bounds: AABB, meshes, fade, pos} — 카메라와 유닛 사이를 가리면 비친다(마녀산장 player_camera 방식)
var watch_points: Array = []   # main.gd 가 매 프레임 넣는 유닛 가슴 높이 점


func _tree(holder: Node3D, id: String, p: Vector3, height: float, base_h: float) -> void:
	var node := Nature.asset(id)
	node.scale = Vector3.ONE * height / base_h
	node.position = p
	node.rotation.y = _rng.randf_range(-PI, PI)
	holder.add_child(node)
	var r := height * 0.33
	occluders.append({"bounds": AABB(Vector3(p.x - r, 1.2, p.z - r), Vector3(r * 2.0, height - 1.2, r * 2.0)),
		"meshes": node.find_children("*", "MeshInstance3D", true, false), "fade": 0.0, "pos": p})


func _small(holder: Node3D, list: Array, p: Vector3, lo := 0.7, hi := 1.15) -> void:
	var node := Nature.asset(list[_rng.randi_range(0, list.size() - 1)])
	node.position = p
	node.rotation.y = _rng.randf_range(-PI, PI)
	node.scale = Vector3.ONE * _rng.randf_range(lo, hi)
	holder.add_child(node)


func _build_forest() -> void:
	var holder := Node3D.new()
	holder.name = "Forest"
	add_child(holder)
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for p in _all_route_points():
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.z))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.z))
	lo -= Vector2(24, 24)
	hi += Vector2(24, 30)
	var step := 2.6
	var tall := ["pine_swept_snow", "pine_broad_snow", "pine_sparse_snow"]
	var tall_h := [5.45, 4.24, 5.25]
	var small := ["berry_shrub", "fern_clump", "mushroom_cluster", "user_rock_low", "user_rock_pile", "hollow_stump", "pine_sapling_snow", "fallen_log"]
	var edge := ["berry_shrub", "fern_clump", "mushroom_cluster", "user_rock_low", "user_rock_pile", "fern_clump"]
	var y := lo.y
	while y < hi.y:
		var x := lo.x
		while x < hi.x:
			var p := Vector3(x + _rng.randf_range(-1.0, 1.0), 0, y + _rng.randf_range(-1.0, 1.0))
			x += step
			var d := open_distance(p)
			if d < 1.1 or d > 26.0:
				continue
			# 길·공터 가장자리일수록 촘촘하게(벽처럼), 멀수록 듬성하게
			if _rng.randf() > lerpf(0.97, 0.6, clampf(d / 26.0, 0.0, 1.0)):
				continue
			if _blocks_room(p, 7.5):
				if _rng.randf() < 0.4:
					_small(holder, small, p)
				continue
			var roll := _rng.randf()
			if roll < 0.84:
				var k := _rng.randi_range(0, tall.size() - 1)
				_tree(holder, tall[k], p, _rng.randf_range(4.6, 7.4), float(tall_h[k]))
			elif roll < 0.91:
				_tree(holder, "dead_snag", p, _rng.randf_range(3.5, 5.0), 4.2)
			else:
				_small(holder, ["user_rock_spire", "user_rock_ledge", "rock_boulder_snow", "user_rock_slab"], p, 0.8, 1.4)
		y += step
	# 좁은 길 양옆: 덤불·고사리·바위가 줄지어 길 가장자리를 그린다
	for path in [entry_path] + paths:
		for i in path.size() - 1:
			var a: Vector3 = path[i]
			var b: Vector3 = path[i + 1]
			var n := int(a.distance_to(b) / 1.5)
			var side := (b - a).normalized().cross(Vector3.UP)
			for k in n:
				var at := a.lerp(b, (k + _rng.randf()) / maxf(n, 1))
				for sgn in [-1.0, 1.0]:
					if _rng.randf() < 0.55:
						var q: Vector3 = at + side * sgn * _rng.randf_range(PATH_WIDTH + 0.5, PATH_WIDTH + 1.3)
						if room_distance(q) > 1.0 and path_distance(q) > PATH_WIDTH + 0.3:
							_small(holder, edge, q, 0.6, 1.0)
	# 공터 가장자리 장식(덤불·버섯·바위)
	for r in rooms:
		for k in 16:
			var ang := _rng.randf_range(0, TAU)
			var p: Vector3 = r.center + lane * cos(ang) * (CLEAR_HALF.x + 0.4) + perp * sin(ang) * (CLEAR_HALF.y + 0.4)
			if room_distance(p) < -0.2 or path_distance(p) < PATH_WIDTH + 1.0:
				continue
			_small(holder, small.slice(0, 6), p)


## 카메라와 지켜볼 점(유닛) 사이를 가리는 나무는 비친다(마녀산장 player_camera._update_occlusion 과 같은 값).
func _update_occlusion(delta: float) -> void:
	var cam := camera.global_position
	for tree in occluders:
		var obscured := false
		if (tree.pos as Vector3).distance_to(focus) < 26.0:
			for w in watch_points:
				if tree.bounds.intersects_segment(cam, w) != null:
					obscured = true
					break
		var wanted := 0.78 if obscured else 0.0
		var alpha := move_toward(float(tree.fade), wanted, delta * 4.0)
		if not is_equal_approx(alpha, float(tree.fade)):
			tree.fade = alpha
			for mesh in tree.meshes:
				mesh.transparency = alpha
