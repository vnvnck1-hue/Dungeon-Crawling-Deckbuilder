extends RefCounted
## Wind-waved grass clumps poking through the snow around the lodge (GrassField).
## Built after the forest so tree/rock colliders can be kept clear. Visual only: no collision, no nav effect.
const Layout := preload("res://scripts/world/layout.gd")
const Cfg := preload("res://scripts/config.gd")
const GraveyardScript := preload("res://scripts/world/graveyard.gd")
const WeatherVfx := preload("res://scripts/visual/vfx/weather_vfx.gd")

const FIELD_SIZE := 60.0 # round field, radius 30 m around the map centre
const TRAIL_CLEAR := 1.8 # m kept clear on each side of trail centre lines
const WALK_CLEAR := 1.5 # door -> stepping stones -> yard hub, the path the witch walks most
const YARD_CLEAR_CENTER := Vector2(3.0, 8.5) # A안 열린 앞마당 타원(현관 앞 ~ 모닥불 ~ 목장 문 앞)
const YARD_CLEAR_RADII := Vector2(3.4, 3.0) # 2026-10-18: 산장 바로 주변 잔디 보강으로 열린 마당 타원을 현관~모닥불 사이로 줄임
## 산장 둘레 촘촘한 안쪽 풀밭(2026-10-18 사용자 요청): 반경 13m, 군락 간격·밀도를 높인다.
const INNER_FIELD_SIZE := 26.0
const INNER_CENTER := Vector2(1.0, 4.0)
## Colour tones, cycled in game with F6 (HUD) or chosen with the `grass_tone=<id>` user arg.
## Waves read through small value/hue shifts and darker troughs; only `frost` keeps the old white glint.
const TONES := [
	{"id": "moss", "name": "이끼 숲", "color_root": Color(.035, .09, .09), "color_tip": Color(.20, .38, .30),
		"color_dry": Color(.33, .38, .30), "color_sheen": Color(.28, .47, .34), "flower_a": Color(.66, .62, .82),
		"flower_b": Color(.62, .72, .86), "sheen_amount": .5, "trough_shade": .22, "toon_mix": .45, "translucency": .25, "variation": .4},
	{"id": "winter_straw", "name": "겨울 마른풀", "color_root": Color(.05, .10, .10), "color_tip": Color(.33, .42, .29),
		"color_dry": Color(.62, .51, .32), "color_sheen": Color(.55, .55, .38), "flower_a": Color(.86, .82, .70),
		"flower_b": Color(.76, .70, .82), "sheen_amount": .45, "trough_shade": .25, "toon_mix": .4, "translucency": .35, "variation": .6},
	{"id": "dusk_sage", "name": "황혼 세이지", "color_root": Color(.06, .07, .14), "color_tip": Color(.30, .44, .38),
		"color_dry": Color(.50, .42, .58), "color_sheen": Color(.40, .52, .48), "flower_a": Color(.72, .62, .86),
		"flower_b": Color(.60, .70, .88), "sheen_amount": .45, "trough_shade": .2, "toon_mix": .5, "translucency": .2, "variation": .5},
	{"id": "evergreen", "name": "깊은 상록", "color_root": Color(.02, .07, .07), "color_tip": Color(.12, .30, .26),
		"color_dry": Color(.19, .28, .28), "color_sheen": Color(.18, .39, .33), "flower_a": Color(.64, .72, .92),
		"flower_b": Color(.78, .66, .90), "sheen_amount": .55, "trough_shade": .3, "toon_mix": .6, "translucency": .3, "variation": .35},
	{"id": "frost", "name": "서리 청록 (이전)", "color_root": Color(.04, .11, .12), "color_tip": Color(.22, .48, .41),
		"color_dry": Color(.46, .48, .62), "color_sheen": Color(.80, .87, 1.0), "flower_a": Color(.70, .82, 1.0),
		"flower_b": Color(.86, .64, 1.0), "sheen_amount": .7, "trough_shade": 0.0, "toon_mix": 1.0, "translucency": 0.0, "variation": .45},
]
static var tone_index := 0
## Shape presets, cycled in game with Shift+F6 or chosen with the `grass_shape=<id>` user arg.
## `outer`/`inner` are GrassField properties per field, `paint` the shader's leaf painting (0 = flat, as before 2026-10-22).
const SHAPES := [
	{"id": "leaf", "name": "잎 포기 (손그림 잎)",
		"outer": {"classic": false, "height_range": Vector2(.45, 1.3), "clump_density": 3.0, "meadow_density": .06, "weed_ratio": .3, "spear_ratio": .3},
		"inner": {"classic": false, "height_range": Vector2(.42, 1.2), "clump_density": 2.2, "meadow_density": .1, "weed_ratio": .3, "spear_ratio": .3},
		"paint": {"normal_flatten": .35, "midrib_light": .5, "vein_shade": .38, "edge_shade": .3, "half_tone": .25, "brush_amount": .45, "tip_glow": 1.0, "root_shade": .6}},
	{"id": "classic", "name": "이전 풀 (주걱 잎 카펫)",
		"outer": {"classic": true, "height_range": Vector2(.13, .58), "clump_density": 16.0, "meadow_density": .15, "weed_ratio": .14, "spear_ratio": 0.0},
		"inner": {"classic": true, "height_range": Vector2(.12, .5), "clump_density": 18.0, "meadow_density": .45, "weed_ratio": .14, "spear_ratio": 0.0},
		"paint": {"normal_flatten": .75, "midrib_light": 0.0, "vein_shade": 0.0, "edge_shade": 0.0, "half_tone": 0.0, "brush_amount": 0.0, "tip_glow": 0.0, "root_shade": 0.0}},
]
static var shape_index := 0

## Switch both fields to another shape preset and rebuild them. Returns its display name.
static func apply_shape(world, index: int) -> String:
	shape_index = posmod(index, SHAPES.size())
	var shape: Dictionary = SHAPES[shape_index]
	var grass: GrassField = world.grass
	grass.material = grass.shader_material # keep the live material (tone, wind) across the rebuild
	for field: GrassField in [grass, world.grass_inner]:
		if field == null: continue
		_set_props(field, shape.outer if field == grass else shape.inner)
		field.rebuild()
	_set_paint(grass.shader_material, shape.paint)
	return shape.name

static func _set_props(field: GrassField, props: Dictionary) -> void:
	for k in props: field.set(k, props[k])

static func _set_paint(m: ShaderMaterial, paint: Dictionary) -> void:
	for k in paint: m.set_shader_parameter(k, paint[k])

static func apply_tone(grass: GrassField, index: int) -> String:
	tone_index = posmod(index, TONES.size())
	var tone: Dictionary = TONES[tone_index]
	for k in tone:
		if k != "id" and k != "name": grass.shader_material.set_shader_parameter(k, tone[k])
	return tone.name

static func build(world) -> GrassField:
	var blocked := _obstacles(world)
	var pasture_rect: Rect2 = Cfg.PASTURE_LEVELS[-1].rect
	var keep := [Layout.LODGE_RECT.grow(.35), Layout.EXTENSION_RECT.grow(.7), pasture_rect.grow(.6),
		Rect2(1.7, -6.3, 5.3, 2.7), # graveyard plots
		# 증축 예약 눈밭은 2026-10-18 부터 풀이 자란다(산장 바로 주변 잔디 보강). 증축 사각형만 비운다.
		Layout.tower_site_rect(Layout.TOWER_SITE_LEFT).grow(.6), Layout.tower_site_rect(Layout.TOWER_SITE_RIGHT).grow(.6),
		Rect2(-13.9, -12.9, 23.6, 9.6)] # 후면 차단 바위 정원
	for p: Vector3 in GraveyardScript.plots():
		keep[3] = keep[3].expand(Vector2(p.x, p.z))
	var walk := [Vector2(Layout.DOOR_FRONT.x, Layout.DOOR_FRONT.z)]
	for s in Layout.STEPPING_STONES: walk.append(Vector2(s[0], s[1]))
	walk.append(Layout.YARD_HUB)
	var campfire := Vector2(Layout.CAMPFIRE.x, Layout.CAMPFIRE.z)
	var keep_out := func(p: Vector2) -> bool:
		if preload("res://scripts/world/hazard_sites.gd").clearing_at(p): return true
		for r: Rect2 in keep:
			if r.has_point(p): return true
		if p.distance_to(Vector2(Layout.DOOR_FRONT.x, Layout.DOOR_FRONT.z)) < 1.8: return true
		if p.distance_to(campfire) < Layout.REST_RING_OUTER + 1.0: return true
		# A안 열린 앞마당(현관·모닥불·목장 문 사이)은 눈밭으로 비워 둔다
		if ((p - YARD_CLEAR_CENTER) / YARD_CLEAR_RADII).length() < 1.0: return true
		if p.distance_to(Layout.ALTAR_SITE) < Layout.ALTAR_SITE_RADIUS + .8: return true
		if Layout.dist_to_path(p, walk) < WALK_CLEAR: return true
		for landmark in Layout.LANDMARKS:
			if p.distance_to(landmark.pos) < 4.0: return true
		for o: Vector3 in blocked:
			if p.distance_to(Vector2(o.x, o.y)) < o.z: return true
		return Layout.dist_to_trails(p) < TRAIL_CLEAR
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("grass_shape="):
			var id := arg.get_slice("=", 1)
			for i in SHAPES.size():
				if SHAPES[i].id == id: shape_index = i
	var shape: Dictionary = SHAPES[shape_index]
	var grass := GrassField.new()
	grass.name = "GrassMeadow"
	grass.size = Vector2(FIELD_SIZE, FIELD_SIZE)
	grass.position = Vector3(Layout.MAP_CENTER.x, 0, Layout.MAP_CENTER.y)
	grass.round_edge = true
	grass.chunk_size = 15.0 # sparse field: fewer, larger chunks keep draw calls low
	grass.clump_spacing = 3.4
	grass.open_ground = .38 # leave plenty of snow showing
	_set_props(grass, shape.outer) # 2026-10-22 기본 `leaf`: 큰 잎 포기 — 수를 줄이고 크게(손그림 잎 질감이 읽히게)
	grass.visibility_end = 0.0 # the game camera sits ~45 m away; the field is bounded anyway
	grass.keep_out = keep_out
	world.add_child(grass)
	# 산장 둘레 안쪽 풀밭: 같은 제외 규칙, 군락이 촘촘하고 눈이 덜 보인다. 바깥 풀밭과 겹쳐 산장 쪽으로 갈수록 짙어진다.
	var inner := GrassField.new()
	inner.name = "GrassLodge"
	inner.size = Vector2(INNER_FIELD_SIZE, INNER_FIELD_SIZE)
	inner.position = Vector3(INNER_CENTER.x, 0, INNER_CENTER.y)
	inner.round_edge = true
	inner.chunk_size = 13.0
	inner.grass_seed = 11
	inner.clump_spacing = 2.1
	inner.clump_radius = Vector2(.9, 2.2)
	inner.open_ground = .22
	_set_props(inner, shape.inner)
	inner.visibility_end = 0.0
	inner.keep_out = keep_out
	inner.material = grass.shader_material # 같은 재질·톤 공유
	world.add_child(inner)
	world.grass_inner = inner
	var m := grass.shader_material
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("grass_tone="):
			var id := arg.get_slice("=", 1)
			for i in TONES.size():
				if TONES[i].id == id: tone_index = i
	apply_tone(grass, tone_index)
	_set_paint(m, shape.paint)
	m.set_shader_parameter("wind_direction", Vector2(WeatherVfx.WIND.x, WeatherVfx.WIND.z)) # same drift as the snowfall
	m.set_shader_parameter("fade_distance", Vector2(90, 110))
	return grass

## Trees and rocks as (x, z, clear radius).
static func _obstacles(world) -> Array[Vector3]:
	var out: Array[Vector3] = []
	for body in world.nav_region.get_children():
		if not (body is StaticBody3D) or not (body.collision_layer & Cfg.L_OBSTACLE): continue
		var radius := .5
		for cs in body.get_children():
			if cs is CollisionShape3D and cs.shape is CylinderShape3D: radius = maxf(radius, cs.shape.radius)
		out.append(Vector3(body.position.x, body.position.z, radius + .45))
	return out
