extends Node3D
## 산장 앞마당(A안): 중앙 모닥불 쉼터, 감시탑 건설 예약 공터 2곳, 제단 건설 예약 공터 1곳.
## 모닥불은 밤에 돌아온 일꾼·대기 용병이 모이는 생활 중심이다(Layout.rest_slots).
## 모닥불 연료(docs/resource-uses-expansion-v01.md v0.3): 목재 1개 = 60초, 최대 3개. 다 타면 꺼지고 불빛도 사라진다.
## 켜져 있을 때만 생고기로 스튜를 만들 수 있고(card_use_resolver), 낮에는 곁의 용병이 아주 천천히 회복한다(ally.gd).
## 공터는 모서리 돌·둘레 돌로 자리만 읽히게 한 빈 예약 공간이다(충돌 없음, 건설 규칙은 별도).

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Models := preload("res://scripts/visual/models.gd")
const Nature := preload("res://scripts/visual/nature_models.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const FireVfx := preload("res://scripts/visual/vfx/fire_vfx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")

const C_FLAME := Color(1.0, 0.62, 0.22)
const C_EMBER := Color(1.0, 0.42, 0.12)
const C_STONE := Color("8e8798")
const C_DIRT := Color("7f6d5c")
## 공터 바닥: 다져진 눈(연한 회보라)과 그 안쪽 드러난 땅(차분한 회갈색). 눈밭 색에 가깝게 두어 "네모 패치"로 읽히지 않게 한다.
const C_TRAMPLED := Color("c3b6c0")
const C_PACKED := Color("a39390")

var campfire: Node3D
var fire_light: OmniLight3D
var site_nodes: Array = []
var fuel := Cfg.CAMPFIRE_START_FUEL   # 남은 연소 시간(초). 0이면 꺼짐
var gauge_shown := 0.0                # 링 게이지가 보여 주는 채움(0~1). 목재를 넣으면 부드럽게 차오른다
var _world
var _ember: MeshInstance3D
var _ember_lit: Material
var _ember_out: Material                # 꺼진 불의 식은 숯
var fire_vfx: FireVfx                   # 불꽃·연기·불티(scripts/visual/vfx/fire_vfx.gd, hearth 프리셋)
var _t := 0.0
var _wind_t := 0.0
var _rng := RandomNumberGenerator.new()


func build(world) -> void:
	name = "LodgeYard"
	_world = world
	gauge_shown = fuel_ratio()
	_rng.seed = 20261018
	_build_campfire(world)
	for c in [Layout.TOWER_SITE_LEFT, Layout.TOWER_SITE_RIGHT]:
		site_nodes.append(_build_tower_site(c))
	site_nodes.append(_build_altar_site())


# ───────────────────────── 모닥불 쉼터 ─────────────────────────

func _build_campfire(world) -> void:
	campfire = B.node(self, Layout.CAMPFIRE, Vector3.ZERO, "Campfire")
	# 불·돌 둘레 충돌: 아무도 불 위를 지나지 않는다.
	var body := StaticBody3D.new()
	body.name = "CampfireBody"
	body.collision_layer = Cfg.L_OBSTACLE
	body.collision_mask = 0
	body.position = Layout.CAMPFIRE
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = Layout.CAMPFIRE_RADIUS
	cyl.height = Cfg.OBSTACLE_MIN_HEIGHT
	cs.shape = cyl
	cs.position.y = cyl.height * 0.5
	body.add_child(cs)
	world.nav_region.add_child(body)
	# 둘레 돌 8개
	for i in 8:
		var a := TAU * i / 8.0 + 0.3
		var stone := Models.make_stepping_stone(_rng)
		stone.scale = Vector3(0.55, 0.9, 0.5)
		stone.position = Vector3(cos(a), 0, sin(a)) * 0.78
		stone.rotation_degrees.y = rad_to_deg(-a) + _rng.randf_range(-15, 15)
		campfire.add_child(stone)
	# 장작과 불꽃
	var wood := Models.make_firewood()
	wood.scale = Vector3(0.8, 0.8, 0.8)
	wood.rotation_degrees.y = 25
	campfire.add_child(wood)
	var ember := Mats.glow(C_EMBER, 2.5)
	_ember = B.cyl(campfire, 0.3, 0.42, 0.12, Vector3(0, 0.26, 0), ember, 8)
	_ember_lit = ember
	_ember_out = Mats.solid(Color("3b302e"), {"noise_amount": 0.2})
	# 불꽃: 셰이더 노이즈로 그린 몽글한 화염. 불빛은 아래 fire_light 가 맡으므로 모듈 불빛은 끈다
	fire_vfx = FireVfx.new()
	fire_vfx.preset = "hearth"
	fire_vfx.size = 0.85             # 높은 탑다운 카메라에서도 불꽃·연기가 읽히는 크기(돌 둘레 0.78m 안)
	fire_vfx.smoke_opacity = 0.85
	fire_vfx.with_light = false
	fire_vfx.position = Vector3(0, 0.22, 0)
	campfire.add_child(fire_vfx)
	fire_light = B.omni(campfire, Vector3(0, 1.1, 0), Color(1.0, 0.64, 0.3), 1.3, 7.5)
	# 통나무 의자 둘, 도끼, 바구니 — 일꾼 쉼터 소품(소량)
	for seat in [[-1.75, 0.55, 78.0], [1.45, 1.15, -28.0]]:
		var log_prop := Models.make_log()
		log_prop.position = Vector3(seat[0], 0, seat[1])
		log_prop.rotation_degrees.y = seat[2]
		log_prop.scale = Vector3.ONE * 0.72
		campfire.add_child(log_prop)
	_axe(campfire, Vector3(-1.35, 0, -0.95), -40.0)
	_basket(campfire, Vector3(1.55, 0, -0.65))


func _axe(parent: Node3D, at: Vector3, yaw: float) -> void:
	var root := B.node(parent, at, Vector3(0, yaw, 0), "Axe")
	var wood := Mats.solid(Color("7a5236"), {"noise_amount": 0.05})
	var steel := Mats.solid(Color("a9adb8"), {"rim_strength": 0.3})
	var stump := Models.make_firewood()
	stump.scale = Vector3(0.55, 0.9, 0.55)
	root.add_child(stump)
	B.box(root, Vector3(0.07, 0.07, 0.78), Vector3(0.0, 0.52, 0.0), wood, Vector3(-55, 0, 0))
	B.box(root, Vector3(0.05, 0.26, 0.2), Vector3(0.0, 0.8, 0.26), steel, Vector3(-55, 0, 0))


func _basket(parent: Node3D, at: Vector3) -> void:
	var root := B.node(parent, at, Vector3.ZERO, "Basket")
	var wicker := Mats.solid(Color("b48a5e"), {"noise_amount": 0.1})
	B.cyl(root, 0.3, 0.24, 0.34, Vector3(0, 0.17, 0), wicker, 9)
	B.cyl(root, 0.33, 0.3, 0.05, Vector3(0, 0.36, 0), Mats.solid(Color("8e6a44")), 9)
	B.sphere(root, 0.1, Vector3(0.05, 0.4, -0.04), Mats.solid(Color("c94f3f")), Vector3.ONE, 8, 4)
	B.sphere(root, 0.09, Vector3(-0.1, 0.4, 0.06), Mats.solid(Color("d8b35a")), Vector3.ONE, 8, 4)


# ───────────────────────── 건설 예약 공터 ─────────────────────────

func _build_tower_site(center: Vector2) -> Node3D:
	var site := B.node(self, Vector3(center.x, 0, center.y), Vector3.ZERO, "TowerSite")
	site.set_meta("reserved_site", "tower")
	var half := Layout.TOWER_SITE_SIZE * 0.5
	# 자연스러운 공터(2026-10-18): 갈색 네모 대신 눈이 다져진 불규칙한 자리 두 겹 + 흩어진 돌·고사리.
	_patch(site, half + 0.55, 0.22, C_TRAMPLED, 0.012, 11)
	_patch(site, half - 0.15, 0.3, C_PACKED, 0.02, 9)
	_scatter(site, half - 0.3, 6, 0.26, 0.42)
	# 모서리 표시 돌: 반듯한 육면체 대신 작은 눈 바위를 모서리 근처에 비스듬히
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var rock := Nature.asset("rock_shards" if _rng.randf() < 0.5 else "rock_boulder_snow")
			var s := _rng.randf_range(0.2, 0.3)
			rock.scale = Vector3(s * _rng.randf_range(0.9, 1.3), s * 0.9, s * _rng.randf_range(0.9, 1.3))
			rock.position = Vector3(sx * (half - 0.15) + _rng.randf_range(-0.25, 0.25), 0, sz * (half - 0.15) + _rng.randf_range(-0.25, 0.25))
			rock.rotation_degrees.y = _rng.randf_range(0, 360)
			site.add_child(rock)
	_edge_plants(site, half + 0.35, 3)
	return site


func _build_altar_site() -> Node3D:
	var c := Layout.ALTAR_SITE
	var site := B.node(self, Vector3(c.x, 0, c.y), Vector3.ZERO, "AltarSite")
	site.set_meta("reserved_site", "altar")
	var r := Layout.ALTAR_SITE_RADIUS
	_patch(site, r + 0.25, 0.16, C_TRAMPLED, 0.012, 14)
	_patch(site, r - 0.75, 0.28, C_PACKED, 0.02, 11)
	_scatter(site, r - 0.9, 7, 0.22, 0.38)
	# 둘레 돌: 간격·크기를 흔들어 손으로 놓은 돌무더기처럼
	for i in 8:
		var a := TAU * i / 8.0 + 0.15 + _rng.randf_range(-0.12, 0.12)
		var stone := Models.make_stepping_stone(_rng)
		var s := _rng.randf_range(0.75, 1.05)
		stone.scale = Vector3(0.95 * s, _rng.randf_range(1.1, 1.7), 0.8 * s)
		stone.position = Vector3(cos(a), 0, sin(a)) * (r + _rng.randf_range(-0.2, 0.2))
		stone.rotation_degrees.y = rad_to_deg(-a) + 90 + _rng.randf_range(-18, 18)
		site.add_child(stone)
	_edge_plants(site, r + 0.6, 4)
	return site


## 불규칙한 다각형 바닥 자리(평평한 부채꼴 메시). jitter = 반지름 흔들림 비율.
func _patch(parent: Node3D, radius: float, jitter: float, color: Color, y: float, sides: int) -> void:
	var mat := Mats.solid(color, {"noise_amount": 0.28, "rim_strength": 0.0, "top_snow": 0.0})
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var ring: Array = []
	var phase := _rng.randf_range(0.0, TAU)
	for i in sides:
		var a := TAU * i / sides + phase
		var rr := radius * (1.0 + _rng.randf_range(-jitter, jitter))
		ring.append(Vector3(cos(a) * rr, y, sin(a) * rr))
	for i in sides:
		st.set_normal(Vector3.UP); st.set_uv(Vector2(0.5, 0.5)); st.add_vertex(Vector3(0, y, 0))
		var p1: Vector3 = ring[(i + 1) % sides]
		var p0: Vector3 = ring[i]
		st.set_normal(Vector3.UP); st.set_uv(Vector2(p1.x, p1.z) * 0.2 + Vector2(0.5, 0.5)); st.add_vertex(p1)
		st.set_normal(Vector3.UP); st.set_uv(Vector2(p0.x, p0.z) * 0.2 + Vector2(0.5, 0.5)); st.add_vertex(p0)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)


## 자리 안에 작은 납작돌을 흩어 놓는다.
func _scatter(parent: Node3D, radius: float, count: int, s_min: float, s_max: float) -> void:
	for i in count:
		var a := _rng.randf_range(0.0, TAU)
		var d := radius * sqrt(_rng.randf_range(0.15, 1.0))
		var stone := Models.make_stepping_stone(_rng)
		var s := _rng.randf_range(s_min, s_max)
		stone.scale = Vector3(s, _rng.randf_range(0.5, 0.8), s * _rng.randf_range(0.8, 1.2))
		stone.position = Vector3(cos(a) * d, 0, sin(a) * d)
		stone.rotation_degrees.y = _rng.randf_range(0, 360)
		parent.add_child(stone)


## 자리 가장자리의 고사리·버섯(충돌 없음).
func _edge_plants(parent: Node3D, radius: float, count: int) -> void:
	for i in count:
		var a := TAU * i / count + _rng.randf_range(-0.5, 0.5)
		var plant := Nature.asset("fern_clump" if i % 2 == 0 else "mushroom_cluster")
		var s := _rng.randf_range(0.6, 0.9)
		plant.scale = Vector3(s, s, s)
		plant.position = Vector3(cos(a), 0, sin(a)) * (radius + _rng.randf_range(-0.2, 0.3))
		plant.rotation_degrees.y = _rng.randf_range(0, 360)
		parent.add_child(plant)


# ───────────────────────── 모닥불 연료 ─────────────────────────

func max_fuel() -> float:
	return Cfg.CAMPFIRE_FUEL_PER_TIMBER * Cfg.CAMPFIRE_MAX_TIMBER


func is_lit() -> bool:
	return fuel > 0.0


func fuel_ratio() -> float:
	return clampf(fuel / max_fuel(), 0.0, 1.0)


## 목재를 더 넣을 수 없는 이유(넣을 수 있으면 빈 문자열). 한 개분 넘게 남은 자리가 있어야 받는다.
func timber_block_reason() -> String:
	if fuel > max_fuel() - Cfg.CAMPFIRE_FUEL_PER_TIMBER * 0.5:
		return "모닥불 연료가 가득합니다 (%d초 남음)" % int(ceil(fuel))
	return ""


## 목재 1개를 넣는다. 꺼진 불은 다시 켜진다. 반환: 늘어난 연소 시간(초).
func add_timber() -> float:
	var before := fuel
	fuel = minf(fuel + Cfg.CAMPFIRE_FUEL_PER_TIMBER, max_fuel())
	if before <= 0.0 and Fx.pool != null:
		Fx.celebrate(Layout.CAMPFIRE + Vector3(0, 0.6, 0), C_FLAME, 0.6)
	return fuel - before


## 지면 점이 모닥불에 놓은 것으로 볼 만큼 가까운가.
func contains_ground(p: Vector3) -> bool:
	return Vector2(p.x - Layout.CAMPFIRE.x, p.z - Layout.CAMPFIRE.z).length() <= Cfg.CAMPFIRE_DROP_RANGE


## 이 위치의 용병이 지금 받는 모닥불 회복(초당). 낮(준비 시간)·불이 켜짐·반경 안일 때만.
func heal_rate_at(p: Vector3) -> float:
	if not is_lit() or _session_state() != SessionScript.State.PREP:
		return 0.0
	if Vector2(p.x - Layout.CAMPFIRE.x, p.z - Layout.CAMPFIRE.z).length() > Cfg.CAMPFIRE_HEAL_RADIUS:
		return 0.0
	return Cfg.CAMPFIRE_HEAL_PER_SEC


func _session_state() -> int:
	var g = _world.game if _world != null else null
	if g == null or g.session == null:
		return -1
	return g.session.state


## 낮·밤·정리 중에는 탄다. 게임이 끝났거나 세션이 없으면 멈춘다.
func _burning() -> bool:
	var st := _session_state()
	return st == SessionScript.State.PREP or st == SessionScript.State.COMBAT or st == SessionScript.State.CLEARING


func _step_fuel(delta: float) -> void:
	if _burning():
		fuel = maxf(fuel - delta, 0.0)
	gauge_shown = move_toward(gauge_shown, fuel_ratio(), delta * 1.5)


# ───────────────────────── 불꽃 애니메이션 ─────────────────────────

func _process(delta: float) -> void:
	_t += delta
	_step_fuel(delta)
	# 남은 연료가 적으면 불꽃이 잦아들고, 꺼지면 불꽃·불빛·불씨가 모두 사라진다(숯만 어둡게 남음).
	var lit := is_lit()
	var strength := clampf(fuel / 12.0, 0.35, 1.0) if lit else 0.0
	if fire_vfx != null:
		if fire_vfx.lit != lit:
			fire_vfx.lit = lit
		if absf(fire_vfx.intensity - strength) > 0.02:
			fire_vfx.intensity = strength
		# 바람: 굴뚝 연기·입김과 같은 WeatherVfx 바람에 연기·불티가 눕는다(0.25초마다 갱신)
		_wind_t -= delta
		if _wind_t <= 0.0:
			_wind_t = 0.25
			var weather = _world.get("weather_vfx") if _world != null else null
			var w: Vector3 = weather.wind_vector() if weather != null and is_instance_valid(weather) else Vector3(0.3, 0, 0)
			fire_vfx.wind = fire_vfx.wind.lerp(w * 1.2, 0.5)
	if _ember != null:
		var ember_mat: Material = _ember_lit if lit else _ember_out
		if _ember.material_override != ember_mat:
			_ember.material_override = ember_mat
	if fire_light != null:
		fire_light.visible = lit
		fire_light.light_energy = (1.3 + sin(_t * 11.0) * 0.12 + sin(_t * 27.0) * 0.06) * strength
	if campfire != null and campfire.is_inside_tree():
		Sfx.loop(self, "yard_campfire", "campfire", Sfx.near_player(campfire, 2.5, 11.0) if lit else 0.0)

