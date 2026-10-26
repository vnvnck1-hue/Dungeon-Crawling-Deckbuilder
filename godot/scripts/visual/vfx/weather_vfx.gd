extends Node
## 주변 분위기 연출: 바람 줄기·돌풍 눈보라·흩날리는 나뭇잎·나무에서 떨어지는 눈·창문 불빛 반딧불·굴뚝 불씨·
## 야영지 모닥불·제단 빛 입자. 카메라가 보는 영역 주변에서만 만든다. 게임 상태는 읽기만 한다.
## 밤(전투) 동안은 돌풍이 잦고 강해져 눈보라가 된다.

const Pool := preload("res://scripts/visual/vfx/vfx_pool.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const Layout := preload("res://scripts/world/layout.gd")

const WIND := Vector3(0.9, 0.0, 0.42)
const LEAF_COLORS := [Color(0.22, 0.5, 0.38), Color(0.38, 0.6, 0.3), Color(0.95, 0.6, 0.22),
	Color(0.88, 0.36, 0.28), Color(0.3, 0.56, 0.42)]
const CAMP := Vector3(-20.0, 0.0, 23.0)
const SHRINE := Vector3(8.0, 0.0, -26.0)

var world
var pool
var snowfall: GPUParticles3D
var gust := 0.0            # 0..1 지금 바람 세기
var storm := 0.0           # 0..1 밤 눈보라 정도
var _gust_target := 0.0
var _gust_timer := 3.0
var _gust_len := 0.0
var _acc: Dictionary = {}
var _trees: Array = []     # 보이는 근처 나무 [위치, 높이]
var _tree_scan := 0.0
var _center := Vector3.ZERO
var _radius := 20.0
var _snow_mat: ParticleProcessMaterial
var _last_state := -1
var _wind_n := Vector3.RIGHT


func _ready() -> void:
	name = "WeatherVfx"
	_wind_n = WIND.normalized()
	if snowfall != null:
		snowfall.amount = 330
		snowfall.amount_ratio = 0.4
		_snow_mat = snowfall.process_material



func _rate(key: String, per_sec: float, dt: float) -> int:
	var a: float = _acc.get(key, randf()) + per_sec * dt
	var n := int(a)
	_acc[key] = a - n
	return n


func _process(dt: float) -> void:
	if dt <= 0.0 or pool == null:
		return
	_update_view()
	_update_wind(dt)
	_wind_lines(dt)
	_blizzard(dt)
	_leaves(dt)
	_lodge_life(dt)
	_landmarks(dt)


func _update_view() -> void:
	var cam: Camera3D = world.camera
	var dir := -cam.global_basis.z
	if absf(dir.y) > 0.01:
		var t := -cam.global_position.y / dir.y
		_center = cam.global_position + dir * t
	_center.y = 0.0
	_radius = clampf(cam.size * 1.05, 12.0, 34.0) if cam.projection == Camera3D.PROJECTION_ORTHOGONAL else 24.0


func _update_wind(dt: float) -> void:
	var session = world.game.session if world.game != null else null
	var combat: bool = session != null and session.state == 1
	if session != null and session.state != _last_state:
		if session.state == 1:
			_start_gust(1.0, 4.0)   # 밤이 시작되면 바로 큰 눈보라 한 번
		_last_state = session.state
	storm = move_toward(storm, 1.0 if combat else 0.0, dt * 0.25)
	_gust_timer -= dt
	if _gust_len > 0.0:
		_gust_len -= dt
		if _gust_len <= 0.0:
			_gust_target = 0.0
	elif _gust_timer <= 0.0:
		_start_gust(randf_range(0.55, 1.0), randf_range(2.2, 4.0))
	gust = move_toward(gust, maxf(_gust_target, storm * 0.45), dt * (1.2 if _gust_target > gust else 0.5))
	if _snow_mat != null:
		var w := gust + storm * 0.6
		_snow_mat.gravity = Vector3(WIND.x, -0.15, WIND.z) * (w * 2.2) + Vector3(0, -0.15, 0)
		snowfall.amount_ratio = clampf(0.36 + storm * 0.5 + gust * 0.25, 0.0, 1.0)


func _start_gust(strength: float, length: float) -> void:
	if strength >= 0.8:
		Sfx.play(self, "gust")
	else:
		Sfx.play(self, "gust_soft")  # 약한 돌풍: 멀리서 부는 아주 약한 바람(가끔 깔리는 앰비언트)
	_gust_target = strength
	_gust_len = length
	_gust_timer = length + (randf_range(3.0, 7.0) if storm > 0.5 else randf_range(6.0, 12.0))


func _rand_in_view(margin := 1.0) -> Vector3:
	var a := randf() * TAU
	var r := sqrt(randf()) * _radius * margin
	return _center + Vector3(cos(a), 0, sin(a)) * r


## 만화식 바람 줄기: 가늘고 긴 흰 선이 휘어 지나간다.
func _wind_lines(dt: float) -> void:
	var n := _rate("line", lerpf(1.6, 11.0, gust) + storm * 4.0, dt)
	for i in n:
		var p := _rand_in_view(1.0) - _wind_n * _radius * 0.35 + Vector3(0, randf_range(0.4, 3.2), 0)
		var spd := randf_range(7.0, 10.0) * (0.8 + gust * 0.5)
		var curl := randf_range(-0.9, 0.9) if randf() < 0.65 else randf_range(2.4, 3.4) * (1.0 if randf() < 0.5 else -1.0)
		pool.emit(Pool.STREAK, p, _wind_n * spd + Vector3(0, randf_range(-0.2, 0.3), 0), randf_range(0.7, 1.15),
			randf_range(0.06, 0.09), Color(1, 1, 1, randf_range(0.35, 0.55) * (0.7 + gust * 0.4)),
			{"aspect": randf_range(16.0, 26.0), "align": true, "curl": curl, "fade_in": 0.25})


## 돌풍·밤 눈보라: 낮게 휘몰아치는 눈송이와 지면을 쓸고 가는 눈안개.
func _blizzard(dt: float) -> void:
	var w := gust + storm * 0.7
	var n := _rate("flake", w * 70.0, dt)
	for i in n:
		var p := _rand_in_view(1.0) - _wind_n * _radius * 0.3 + Vector3(0, randf_range(0.1, 2.6), 0)
		pool.emit(Pool.FLAKE, p, _wind_n * randf_range(4.0, 8.0) + Vector3(0, randf_range(-0.3, 0.6), 0), randf_range(1.2, 2.0),
			randf_range(0.08, 0.15), Color(0.98, 0.98, 1.0, 0.9),
			{"curl": randf_range(-1.2, 1.2), "sway": 0.8, "gravity": -0.4, "fade_in": 0.15})
	var m := _rate("drift", w * 14.0, dt)
	for i in m:
		var p2 := _rand_in_view(0.9) - _wind_n * _radius * 0.25 + Vector3(0, randf_range(0.1, 0.5), 0)
		pool.emit(Pool.STREAK, p2, _wind_n * randf_range(5.0, 8.0), randf_range(0.9, 1.4),
			randf_range(0.16, 0.26), Color(0.96, 0.96, 1.0, 0.4), {"aspect": randf_range(9.0, 14.0), "align": true, "fade_in": 0.3,
			"curl": randf_range(-0.4, 0.4)})


func _scan_trees() -> void:
	_trees.clear()
	for o in world.camera_occluders:
		var b: AABB = o["bounds"]
		var c := b.get_center()
		if Vector2(c.x - _center.x, c.z - _center.z).length() < _radius * 1.1:
			_trees.append([Vector3(c.x, 0, c.z), b.end.y, b.size.x * 0.5])


## 흩날리는 나뭇잎과 바람에 털리는 가지 위 눈.
func _leaves(dt: float) -> void:
	_tree_scan -= dt
	if _tree_scan <= 0.0:
		_tree_scan = 0.5
		_scan_trees()
	if _trees.is_empty():
		return
	var n := _rate("leaf", lerpf(2.5, 12.0, gust) + storm * 3.0, dt)
	for i in n:
		var t: Array = _trees[randi() % _trees.size()]
		var p: Vector3 = t[0] + Fx._rh(randf_range(0.2, t[2])) + Vector3(0, randf_range(t[1] * 0.4, t[1] * 0.85), 0)
		var c: Color = LEAF_COLORS[randi() % LEAF_COLORS.size()]
		pool.emit(Pool.LEAF, p, _wind_n * randf_range(0.8, 2.0) * (1.0 + gust * 1.8) + Vector3(0, -randf_range(0.5, 0.9), 0),
			randf_range(5.0, 7.0), randf_range(0.17, 0.25), c,
			{"sway": randf_range(0.8, 1.6), "spin": randf_range(-4.0, 4.0), "land": true, "aspect": 0.55, "fade_in": 0.05})
	var m := _rate("clump", gust * 3.0 + storm * 1.0, dt)
	for i in m:
		var t2: Array = _trees[randi() % _trees.size()]
		var p2: Vector3 = t2[0] + Fx._rh(randf_range(0.3, t2[2])) + Vector3(0, t2[1] * randf_range(0.45, 0.75), 0)
		for k in 3:
			pool.emit(Pool.PUFF, p2 + Fx._rv(0.2), _wind_n * 0.8 + Vector3(0, -0.6, 0), 1.2, randf_range(0.16, 0.28), Fx.C_SNOW,
				{"gravity": -8.0, "land": true, "grow": 0.7})


## 산장 주변: 창문 불빛 반딧불, 굴뚝 불씨.
func _lodge_life(dt: float) -> void:
	if Vector2(_center.x, _center.z).length() > _radius + 8.0:
		return
	var n := _rate("mote", 2.4, dt)
	for i in n:
		var p := Vector3(randf_range(-3.0, 3.5), randf_range(0.4, 2.2), randf_range(2.9, 4.6))
		pool.emit(Pool.GLOW, p, Vector3(0, randf_range(0.15, 0.35), 0), randf_range(2.5, 3.5), randf_range(0.12, 0.2),
			Color(1.0, 0.72, 0.35, 0.9), {"additive": true, "sway": 0.5, "fade_in": 0.3})
	var s := _rate("spark", 1.8 + gust, dt)
	for i in s:
		pool.emit(Pool.SPARKLE, Layout.CHIMNEY_TOP + Fx._rv(0.1), Vector3(0, randf_range(1.2, 2.0), 0) + WIND * gust * 1.5,
			randf_range(0.9, 1.4), randf_range(0.1, 0.16), Color(1.0, 0.62, 0.25),
			{"additive": true, "sway": 0.7, "spin": 6.0, "drag": 0.3})


func _landmarks(dt: float) -> void:
	# 야영지 모닥불: 마녀가 가까이 가면 타닥거림이 들린다
	var p = world.game.player if world.game != null else null
	if p != null and is_instance_valid(p):
		var d := Vector2(p.global_position.x - CAMP.x, p.global_position.z - CAMP.z).length()
		Sfx.loop(self, "campfire", "campfire", clampf(1.0 - (d - 2.5) / 9.0, 0.0, 1.0))
	if Vector2(_center.x - CAMP.x, _center.z - CAMP.z).length() < _radius + 6.0:
		# 카툰 모닥불: 겹친 빛 덩어리 + 위로 튀는 불씨
		for i in _rate("fire", 14.0, dt):
			var c := Color(1.0, 0.45, 0.1) if randf() < 0.5 else Color(1.0, 0.75, 0.2)
			pool.emit(Pool.PUFF, CAMP + Fx._rh(0.15) + Vector3(0, 0.45, 0), Vector3(0, randf_range(1.2, 1.8), 0), randf_range(0.35, 0.5),
				randf_range(0.32, 0.45), c, {"grow": 0.15, "additive": true, "sway": 0.6})
		for i in _rate("ember", 3.0, dt):
			pool.emit(Pool.SPARKLE, CAMP + Vector3(0, 0.6, 0), Fx._rh(0.4) + Vector3(0, randf_range(1.5, 2.6), 0), randf_range(1.0, 1.6),
				0.13, Color(1.0, 0.6, 0.2), {"additive": true, "sway": 1.0, "spin": 6.0})
		for i in _rate("campsmoke", 1.5, dt):
			pool.emit(Pool.PUFF, CAMP + Vector3(0, 1.0, 0), Vector3(0, 0.8, 0) + WIND * 0.4, 2.2, 0.35, Color(0.62, 0.58, 0.78, 0.5),
				{"grow": 3.0, "sway": 0.3, "fade_in": 0.2})
	if Vector2(_center.x - SHRINE.x, _center.z - SHRINE.z).length() < _radius + 6.0:
		for i in _rate("shrine", 5.0, dt):
			pool.emit(Pool.SPARKLE if randf() < 0.5 else Pool.GLOW, SHRINE + Fx._rh(randf_range(0.2, 1.2)) + Vector3(0, 0.2, 0),
				Vector3(0, randf_range(0.6, 1.2), 0), randf_range(1.6, 2.4), randf_range(0.14, 0.24), Color(0.5, 0.75, 1.0),
				{"additive": true, "sway": 0.4, "spin": 3.0, "fade_in": 0.2})


## 지금 바람의 수평 방향과 세기(다른 연출이 입김·연기를 날릴 때 사용).
func wind_vector() -> Vector3:
	return _wind_n * (0.3 + gust * 1.2 + storm * 0.5)
