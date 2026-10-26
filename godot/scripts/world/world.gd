extends Node3D
## World: 바닥·본채·목장·숲·조명·카메라·내비게이션.
## 라이팅 구성(승인 원화 기준):
##  - 환경광(보라·인디고)이 그림자 쪽 전체를 채워 "그림자 = 짙은 보라"가 되게 한다.
##  - 달빛(연한 라벤더) 방향광 하나로 넓은 명암과 부드러운 그림자.
##  - 창문·벽등의 앰버 옴니 라이트를 작은 범위에 모아 눈밭에 따뜻한 빛 웅덩이를 만든다.
##  - 글로우로 창문 번짐, 후처리로 가장자리 인디고 비네트.

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const Models := preload("res://scripts/visual/models.gd")
const Nature := preload("res://scripts/visual/nature_models.gd")
const LodgeScript := preload("res://scripts/world/lodge.gd")
const PastureScript := preload("res://scripts/world/pasture.gd")
const GraveyardScript := preload("res://scripts/world/graveyard.gd")
const RearBlockerScript := preload("res://scripts/world/rear_blocker.gd")
const LodgeYardScript := preload("res://scripts/world/lodge_yard.gd")
const YardHedgesScript := preload("res://scripts/world/yard_hedges.gd")
const WatchtowerScript := preload("res://scripts/world/watchtower.gd")
const GROUND_SHADER := preload("res://shaders/painted_ground.gdshader")
const GROUND_PAINT := preload("res://assets/painted/ground_cleanplate.png")
const GROUND_SNOW := preload("res://assets/ground/painted_snow_v1.png")
const GROUND_TRAIL := preload("res://assets/ground/painted_trail_v1.png")
const GROUND_FOREST := preload("res://assets/ground/painted_forest_v1.png")
const GROUND_PROP_MASK := preload("res://assets/ground/prop_blend_mask.png")
const POST_SHADER := preload("res://shaders/post_grade.gdshader")
const OUTLINE_SHADER := preload("res://shaders/toon_outline.gdshader")
const ScreenStyle := preload("res://scripts/visual/screen_style.gd")
const CameraStyle := preload("res://scripts/visual/camera_style.gd")
const ReferenceLighting := preload("res://scripts/visual/reference_lighting.gd")
const Exploration := preload("res://scripts/world/exploration.gd")
const GrassMeadow := preload("res://scripts/world/grass_meadow.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const PlayerCamera := preload("res://scripts/visual/player_camera.gd")
const AerialPerspective := preload("res://scripts/visual/aerial_perspective.gd")
const DayCycle := preload("res://scripts/visual/day_cycle.gd")
const FogOfWar := preload("res://scripts/visual/fog_of_war.gd")
const VfxPool := preload("res://scripts/visual/vfx/vfx_pool.gd")
const WeatherVfx := preload("res://scripts/visual/vfx/weather_vfx.gd")
const ChimneySmoke := preload("res://scripts/visual/vfx/chimney_smoke.gd")
const ActorVfx := preload("res://scripts/visual/vfx/actor_vfx.gd")
const BreathVapor := preload("res://scripts/visual/vfx/breath_vapor.gd")
const HazardRegions := preload("res://scripts/world/hazard_regions.gd")
const BossRoom := preload("res://scripts/world/boss_room.gd")
const Fx := preload("res://scripts/visual/fx.gd")
signal screen_style_changed(id: String)
signal camera_style_changed(id: String)
signal air_style_changed(id: String)

# 기존 화면 초기화 값. 실제 런타임 값은 visual/screen_style.gd의 프리셋에서 조정.
# 원화 측정값(sRGB) 기준: 햇빛 든 눈 ≈ (145,142,228), 그림자 눈 ≈ (83,93,198), 문 앞 빛 웅덩이 ≈ (237,175,133)
# → 선형 공간에서 그림자 = 알베도×환경광, 밝은 면 = 알베도×(환경광+달빛)이 되도록 역산한 값.
const AMBIENT_COLOR := Color(0.65, 0.69, 0.93)
const AMBIENT_ENERGY := 0.65
const MOON_COLOR := Color(0.94, 0.92, 1.0)
const MOON_ENERGY := 0.60
const MOON_ROT := Vector3(-64.0, 145.0, 0.0)

var game
var camera: Camera3D
var player_camera
var nav_region: NavigationRegion3D
var lodge
var pasture
var graveyard
var rear_blocker
var yard
var yard_hedges
var towers: Array = []   # 감시탑 공터 2곳(world/watchtower.gd). 처음엔 빈 공터(level 0)
var sun: DirectionalLight3D
var env: Environment
var ground_mat: ShaderMaterial
var post_mat: ShaderMaterial
var outline_mat: ShaderMaterial
var outline_mesh: MeshInstance3D
var reference_lighting: Node3D
var aerial_perspective
var day_cycle
var fog_of_war
var vfx_pool
var weather_vfx
var actor_vfx
var hazard_regions
var boss_room
var debug_draw := false
## 벌목 가능한 자원 나무(장식 숲 전체가 아님). {pos, body, visual, remaining, reserved}
var harvest_trees: Array = []
var camera_occluders: Array = []
var grass: GrassField
var grass_inner: GrassField   # 산장 둘레 촘촘한 풀밭(grass_meadow.gd)
var _shake_t := 0.0
var _shake_amp := 0.0
var _rng := RandomNumberGenerator.new()


func build(g) -> void:
	game = g
	_rng.seed = 20261013
	_build_environment()
	_build_camera()
	nav_region = NavigationRegion3D.new()
	nav_region.name = "NavRegion"
	add_child(nav_region)
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = Cfg.L_GROUND | Cfg.L_OBSTACLE | Cfg.L_BOUNDARY
	nm.agent_radius = 0.5
	nm.agent_height = 1.25
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	# 굽기 높이를 y −1~1 로 제한: 장애물(후면 띠·채움 상자·바위·울타리) 윗면이 고립된 내비 섬으로 구워지지 않게 한다.
	# 섬이 있으면 map_get_closest_point 가 산장 뒤 등 닿을 수 없는 곳을 돌려줘 캐릭터가 벽에 부딪혀 진동했다(2026-10-18).
	# 모든 장애물 충돌 높이는 1.2m 이상이어야 한다(Cfg.OBSTACLE_MIN_HEIGHT).
	# z 는 북쪽 보스 둥지 별관(hazard_sites BOSS_ROOM, z -64 까지)을 포함하도록 -70 부터 굽는다
	nm.filter_baking_aabb = AABB(Vector3(-52, -1, -70), Vector3(104, 2, 122))
	nav_region.navigation_mesh = nm
	_build_ground()
	lodge = LodgeScript.new()
	lodge.name = "Lodge"
	lodge.game = game
	nav_region.add_child(lodge)
	pasture = PastureScript.new()
	pasture.game = game
	nav_region.add_child(pasture)
	graveyard = GraveyardScript.new()
	graveyard.game = game
	add_child(graveyard)
	# A안: 산장 뒤 닫힌 바위 띠(충돌·내비 제외)와 앞마당 모닥불·건설 예약 공터
	rear_blocker = RearBlockerScript.new()
	add_child(rear_blocker)
	rear_blocker.build(self)
	yard = LodgeYardScript.new()
	add_child(yard)
	yard.build(self)
	for site in [["left", Layout.TOWER_SITE_LEFT], ["right", Layout.TOWER_SITE_RIGHT]]:
		var tower := WatchtowerScript.new()
		tower.setup(game, site[0], site[1])
		nav_region.add_child(tower)
		towers.append(tower)
	_build_forest()
	_build_props()
	Exploration.build(self, _rng)
	# 식생 구분선 시안(--yard-hedge=<id>, F7 순환). 풀밭보다 먼저 두어 풀이 충돌 부품을 피한다.
	yard_hedges = YardHedgesScript.new()
	add_child(yard_hedges)
	yard_hedges.build(self)
	hazard_regions = HazardRegions.new()
	add_child(hazard_regions)
	hazard_regions.build(self)
	boss_room = BossRoom.new()
	add_child(boss_room)
	boss_room.build(self)
	grass = GrassMeadow.build(self)
	_build_boundary()
	_build_fx()
	_build_post()
	reference_lighting = ReferenceLighting.new()
	reference_lighting.name = "ReferenceLighting"
	add_child(reference_lighting)
	reference_lighting.build()
	set_screen_style(ScreenStyle.current_id)
	# Ground cleanplate stays anchored to the original world projection, independent of lens.
	set_camera_style(CameraStyle.current_id)
	aerial_perspective = AerialPerspective.new()
	aerial_perspective.name = "AerialPerspective"
	add_child(aerial_perspective)
	aerial_perspective.bind(self)
	bake_nav()


func set_screen_style(id: String) -> bool:
	if not ScreenStyle.apply(self,id): return false
	if day_cycle != null: day_cycle.refresh()
	if aerial_perspective != null: aerial_perspective.sync_colors()
	screen_style_changed.emit(id)
	return true

func bind_day_and_sight() -> void:
	day_cycle = DayCycle.new()
	day_cycle.name = "DayCycle"
	add_child(day_cycle)
	day_cycle.bind(self)
	fog_of_war = FogOfWar.new()
	fog_of_war.name = "FogOfWar"
	add_child(fog_of_war)
	fog_of_war.bind(self)


## F7: 다음 식생 구분선 시안. 표시 이름을 돌려준다.
func cycle_yard_hedges() -> String:
	if yard_hedges == null: return ""
	return yard_hedges.rebuild(yard_hedges.next_variant())


## F6: next grass colour tone. Returns its display name.
func cycle_grass_tone() -> String:
	if grass == null: return ""
	return GrassMeadow.apply_tone(grass, GrassMeadow.tone_index + 1)


## Shift+F6: next grass shape preset (leaf rosettes / the old paddle-blade carpet). Returns its display name.
func cycle_grass_shape() -> String:
	if grass == null: return ""
	return GrassMeadow.apply_shape(self, GrassMeadow.shape_index + 1)


func set_camera_style(id: String) -> bool:
	if not CameraStyle.apply(camera,id): return false
	if player_camera != null: player_camera.on_lens_changed()
	if aerial_perspective != null: aerial_perspective.sync_camera()
	_shake_t = 0.0
	_shake_amp = 0.0
	camera_style_changed.emit(id)
	return true


func set_air_style(id: String) -> bool:
	if not aerial_perspective.configure(id): return false
	air_style_changed.emit(id)
	return true


func bind_player_camera(player: Node3D) -> void:
	player_camera = PlayerCamera.new()
	player_camera.name = "PlayerCamera"
	add_child(player_camera)
	player_camera.bind(camera, player, camera_occluders)
	if grass != null: grass.push_target = player # blades part around the witch
	if grass_inner != null: grass_inner.push_target = player
	if "--overview" in OS.get_cmdline_user_args(): player_camera.toggle_overview()
	if aerial_perspective != null: aerial_perspective.sync_camera()


func bake_nav() -> void:
	nav_region.bake_navigation_mesh(false)


# ───────────────────────── 환경·조명·카메라 ─────────────────────────

func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("2b2552")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = AMBIENT_COLOR
	env.ambient_light_energy = AMBIENT_ENERGY
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_hdr_scale = 2.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	for i in 7:
		env.set_glow_level(i, 1.0 if i in [1, 2, 3, 4] else 0.0)
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 1.8
	env.ssao_power = 1.4
	env.ssao_detail = 0.4
	env.ssao_light_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.0
	env.adjustment_contrast = 1.0
	env.adjustment_brightness = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.name = "Moonlight"
	sun.light_color = MOON_COLOR
	sun.light_energy = MOON_ENERGY
	sun.light_specular = 0.0
	sun.rotation_degrees = MOON_ROT
	sun.shadow_enabled = true
	sun.shadow_opacity = 0.85
	sun.shadow_blur = 1.6
	sun.light_angular_distance = 2.5
	sun.shadow_bias = 0.18
	sun.shadow_normal_bias = 1.2
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = 90.0
	add_child(sun)


func _build_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = Layout.CAMERA_SIZE
	camera.near = 1.0
	camera.far = 140.0
	camera.rotation_degrees = Vector3(-Layout.CAMERA_PITCH, Layout.CAMERA_YAW, 0)
	add_child(camera)
	camera.position = Layout.CAMERA_TARGET + camera.transform.basis.z * Layout.CAMERA_DISTANCE
	camera.current = true


func shake(amount: float, duration: float) -> void:
	_shake_amp = maxf(_shake_amp, amount)
	_shake_t = maxf(_shake_t, duration)


func _process(delta: float) -> void:
	if _shake_t > 0.0:
		_shake_t -= delta
		var a := _shake_amp * clampf(_shake_t / 0.3, 0.0, 1.0)
		camera.h_offset = randf_range(-a, a)
		camera.v_offset = randf_range(-a, a)
		if _shake_t <= 0.0:
			camera.h_offset = 0.0
			camera.v_offset = 0.0
			_shake_amp = 0.0


# ───────────────────────── 바닥·숲·프랍 ─────────────────────────

func _build_ground() -> void:
	var body := StaticBody3D.new()
	body.name = "Ground"
	body.collision_layer = Cfg.L_GROUND
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(Layout.GROUND_EXTENT, 1, Layout.GROUND_EXTENT)
	cs.shape = bs
	# 내비메시는 걷는 면 위로 2칸(0.5m) 올라가 구워지므로, 바닥 충돌을 0.5m 내려 경로 높이를 y=0에 맞춘다
	cs.position.y = -1.0
	body.add_child(cs)
	nav_region.add_child(body)

	var plane := PlaneMesh.new()
	plane.size = Vector2(120, 120)
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = GROUND_SHADER
	ground_mat.set_shader_parameter("cleanplate", GROUND_PAINT)
	ground_mat.set_shader_parameter("painted_snow", GROUND_SNOW)
	ground_mat.set_shader_parameter("painted_trail", GROUND_TRAIL)
	ground_mat.set_shader_parameter("painted_forest", GROUND_FOREST)
	ground_mat.set_shader_parameter("prop_blend_mask", GROUND_PROP_MASK)
	ground_mat.set_shader_parameter("painted_ground_enabled", 1.0)
	ground_mat.set_shader_parameter("reference_center", Layout.CAMERA_TARGET)
	ground_mat.set_shader_parameter("reference_right", camera.transform.basis.x)
	ground_mat.set_shader_parameter("reference_up", camera.transform.basis.y)
	ground_mat.set_shader_parameter("reference_size", Vector2(Layout.CAMERA_SIZE*2.0,Layout.CAMERA_SIZE))
	var segments := PackedVector4Array()
	for path in Layout.EXPLORATION_PATHS:
		for i in range(path.size()-1):
			segments.append(Vector4(path[i].x,path[i].y,path[i+1].x,path[i+1].y))
	ground_mat.set_shader_parameter("trail_count", segments.size())
	segments.resize(64)
	ground_mat.set_shader_parameter("trail_segments", segments)
	ground_mat.set_shader_parameter("clearings", PackedVector2Array([Vector2(-24,5),Vector2(8,-26),Vector2(-20,23),Vector2(23,18)]))
	var mi := MeshInstance3D.new()
	mi.name = "SnowGround"
	mi.mesh = plane
	mi.material_override = ground_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _add_tree(p: Vector2, h: float, asset_id := "", authored_scale := Vector3.ONE, authored_rotation := Vector3.ZERO, authored_radius := 0.0) -> Dictionary:
	var body := StaticBody3D.new()
	body.collision_layer = Cfg.L_OBSTACLE
	body.collision_mask = 0
	body.position = Vector3(p.x, 0, p.y)
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.4
	cyl.height = 2.0
	cs.shape = cyl
	cs.position.y = 1.0
	body.add_child(cs)
	var v := Models.make_pine(h, _rng) if asset_id.is_empty() else Nature.asset(asset_id)
	if asset_id.is_empty():
		v.rotation_degrees.y = _rng.randf_range(0, 360)
	else:
		v.scale = authored_scale
		v.rotation_degrees = authored_rotation
	body.add_child(v)
	nav_region.add_child(body)
	var radius := authored_radius if authored_radius > 0.0 else 2.1*h/6.4
	var occluder := {"bounds":AABB(Vector3(p.x-radius,1.4,p.y-radius),Vector3(radius*2,h-1.4,radius*2)),
		"meshes":v.find_children("*","MeshInstance3D",true,false), "fade":0.0}
	camera_occluders.append(occluder)
	# 직업 분화 v1: 모든 나무가 벌목 대상. 목재량은 높이에 비례한다.
	var yield_amount := tree_yield(h)
	var tree := {"pos": body.position, "body": body, "visual": v, "remaining": yield_amount, "max": yield_amount,
		"height": h, "reserved": null, "occluder": occluder, "removed": false}
	harvest_trees.append(tree)
	return tree


## 높이(m) → 목재량. 6m ≈ 40(기존 20의 두 배), 묘목 1.6m ≈ 11, 8m ≈ 55.
static func tree_yield(h: float) -> int:
	return clampi(int(round(h * Cfg.TREE_YIELD_PER_M)), Cfg.TREE_YIELD_MIN, Cfg.TREE_YIELD_MAX)


## 벌목 지정 불가 사유. 가능하면 빈 문자열. 둘러싸인 나무(접근 지면 없음·주변 나무 과밀)는 지정할 수 없다.
func tree_access(tree: Dictionary) -> String:
	if tree.get("removed", false) or tree["remaining"] <= 0:
		return "이미 베인 나무입니다"
	var p: Vector3 = tree["pos"]
	var crowd := 0
	for t in harvest_trees:
		if t == tree or t.get("removed", false):
			continue
		if Vector2(t["pos"].x - p.x, t["pos"].z - p.z).length() <= Cfg.TREE_CROWD_RADIUS:
			crowd += 1
	if crowd >= Cfg.TREE_CROWD_MAX:
		return "나무에 둘러싸여 접근할 수 없습니다"
	var nav_map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) > 0:
		# 지면 내비 점이어야 하고(장애물 윗면 섬 제외), 현관에서 경로가 닿아야 한다(후면 띠 뒤 포켓 제외).
		var nav = NavUtil.walkable_from(nav_map, Layout.DOOR_FRONT, p, Cfg.TREE_ACCESS_NAV + 0.5, 0.9)
		if nav == null:
			return "다가갈 길이 없는 나무입니다"
	return ""


## 마우스 아래의 벌목 가능 나무 중 가장 가까운 것(화면 거리 px). 없으면 빈 사전.
func tree_near_screen(sp: Vector2, max_px: float) -> Dictionary:
	var best := {}
	var best_d := max_px
	for t in harvest_trees:
		if t.get("removed", false):
			continue
		var top: Vector3 = t["pos"] + Vector3(0, minf(t["height"] * 0.45, 2.4), 0)
		if camera.is_position_behind(top):
			continue
		var d := camera.unproject_position(top).distance_to(sp)
		if d < best_d:
			best_d = d
			best = t
	return best


func _build_forest() -> void:
	for t in Layout.TREES:
		_add_tree(Vector2(t[0], t[1]), t[2])


## 목재가 바닥난 나무: 쓰러지는 연출 뒤 월드에서 사라진다(충돌·경로·카메라 가림 포함).
func deplete_tree(tree: Dictionary) -> void:
	if tree.get("removed", false):
		return
	tree["removed"] = true
	tree["reserved"] = null
	var v: Node3D = tree["visual"]
	var body: StaticBody3D = tree["body"]
	Fx.tree_fall(tree["pos"], tree["height"])
	Sfx.play(self, "tree_fall")
	camera_occluders.erase(tree["occluder"])
	# 충돌은 바로 치우고 경로를 다시 굽는다. 시각은 기울어지며 작아진 뒤 제거한다.
	for c in body.get_children():
		if c is CollisionShape3D:
			c.disabled = true
	body.collision_layer = 0
	var tw := v.create_tween().set_parallel(true)
	tw.tween_property(v, "rotation_degrees:x", 70.0, 0.9).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(v, "scale", v.scale * Vector3(0.6, 0.25, 0.6), 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(func():
		if is_instance_valid(body):
			body.queue_free())
	harvest_trees.erase(tree)
	call_deferred("bake_nav")


func _build_props() -> void:
	for r in Layout.ROCKS:
		var body := StaticBody3D.new()
		body.collision_layer = Cfg.L_OBSTACLE
		body.collision_mask = 0
		body.position = Vector3(r[0], 0, r[1])
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = 1.35 * r[2]
		cyl.height = maxf(Cfg.OBSTACLE_MIN_HEIGHT, 1.6 * r[2])
		cs.shape = cyl
		cs.position.y = cyl.height * 0.5
		body.add_child(cs)
		body.add_child(Models.make_rock(r[2], _rng))
		nav_region.add_child(body)
	var decor := B.node(self, Vector3.ZERO, Vector3.ZERO, "Decor")
	for s in Layout.SHRUBS:
		var shrub := Models.make_shrub(_rng)
		shrub.position = Vector3(s[0], 0, s[1])
		decor.add_child(shrub)
	for l in Layout.LOGS:
		var lg := Models.make_log()
		lg.position = Vector3(l[0], 0, l[1])
		lg.rotation_degrees.y = l[2]
		decor.add_child(lg)
	for st in Layout.STEPPING_STONES:
		var stone := Models.make_stepping_stone(_rng)
		stone.scale = Vector3(1.5,1.0,1.4)
		stone.position = Vector3(st[0], 0, st[1])
		decor.add_child(stone)


## Closed outer forest boundary. All routes, clearings and spawn points are inside.
func _build_boundary() -> void:
	var body := StaticBody3D.new()
	body.name = "ForestBoundary"
	body.collision_layer = Cfg.L_BOUNDARY
	body.collision_mask = 0
	nav_region.add_child(body)
	var n := 128
	var c := Layout.MAP_CENTER
	for i in n:
		var a := TAU * (i + 0.5) / n
		var p := c + Vector2(cos(a), sin(a)) * Layout.BOUNDARY_RADIUS
		if Layout.in_boss_nest(p, 1.02):
			continue   # 북쪽 둥지 별관과 이어지는 구간은 열어 두고 둥지 외곽 석재가 벽이 된다
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.6, 2.0, TAU * Layout.BOUNDARY_RADIUS / n + 0.3)
		cs.shape = bs
		cs.position = Vector3(p.x, 1.0, p.y)
		cs.rotation.y = -a
		body.add_child(cs)


# ───────────────────────── 눈·연기·후처리 ─────────────────────────

func _build_fx() -> void:
	# 눈 내림: 작고 성긴 입자. 플레이 영역 가독성을 해치지 않게 밀도를 낮게 유지.
	var snow := GPUParticles3D.new()
	snow.name = "Snowfall"
	snow.process_mode = Node.PROCESS_MODE_ALWAYS
	snow.amount = 120
	snow.lifetime = 10.0
	snow.preprocess = 10.0
	snow.visibility_aabb = AABB(Vector3(-40, -20, -40), Vector3(80, 40, 80))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(46, 0.5, 46)
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
	snow.position = Layout.CAMERA_TARGET + Vector3(0, 13, 0)
	add_child(snow)

	# 굴뚝 연기: Stam 의 Stable Fluids 로 굴뚝 위 공기 흐름을 풀어 그린다(따뜻한 복숭아색 → 라벤더로 흩어짐).
	var smoke := ChimneySmoke.new()
	smoke.camera = camera
	smoke.position = Layout.CHIMNEY_TOP
	add_child(smoke)

	# 카툰 VFX: 입자 풀 + 날씨(바람·눈보라·나뭇잎) + 캐릭터(발자국·입김)
	vfx_pool = VfxPool.new()
	add_child(vfx_pool)
	Fx.pool = vfx_pool
	weather_vfx = WeatherVfx.new()
	weather_vfx.world = self
	weather_vfx.pool = vfx_pool
	weather_vfx.snowfall = snow
	smoke.weather = weather_vfx
	add_child(weather_vfx)
	# 입김: 굴뚝 연기와 같은 Stable Fluids 로 날숨을 구워 부드러운 기체로 그린다.
	var breath := BreathVapor.new()
	breath.camera = camera
	breath.weather = weather_vfx
	add_child(breath)
	actor_vfx = ActorVfx.new()
	actor_vfx.game = game
	actor_vfx.weather = weather_vfx
	actor_vfx.breath = breath
	add_child(actor_vfx)


func _build_post() -> void:
	outline_mesh = MeshInstance3D.new()
	outline_mesh.name = "ToonOutline"
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
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
	var m := ShaderMaterial.new()
	m.shader = POST_SHADER
	post_mat = m
	rect.material = m
	layer.add_child(rect)


# ───────────────────────── 입력 도우미 ─────────────────────────

func show_click_marker(pos: Vector3) -> void:
	Sfx.play(self, "move_click")
	var m := Mats.unshaded(Color(0.85, 0.8, 1.0, 0.9), true, true)
	var ring := B.torus(self, 0.32, 0.42, pos + Vector3(0, 0.05, 0), m)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.2, 0.2, 1.2)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(0.4, 0.2, 0.4), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.45)
	tw.chain().tween_callback(ring.queue_free)
	if vfx_pool != null:
		for i in 4:
			var a := TAU * i / 4.0 + 0.4
			vfx_pool.emit(VfxPool.SPARKLE, pos + Vector3(cos(a) * 0.35, 0.15, sin(a) * 0.35), Vector3(cos(a), 2.2, sin(a)) * 0.9,
				0.35, 0.16, Color(0.9, 0.82, 1.0), {"additive": true, "drag": 2.0, "spin": 8.0, "gravity": -3.0})
