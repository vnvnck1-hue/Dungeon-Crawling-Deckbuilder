extends Node3D
## 후면 차단 띠(A안): 산장·증축 예약·목장 뒤를 닫힌 고리로 감싸는 바위 정원.
## 충돌은 Layout.REAR_BLOCKER 각 변의 상자(L_OBSTACLE)와 고리 안쪽을 덮는 REAR_FILL 상자가 맡아
## 내비메시에서 산장 뒤가 통째로 빠진다. 바위·침엽수·관목은 그 위의 시각 마감이며 자원 나무가 아니다.
## 묘지(graveyard.gd)는 고리 안 포켓에 그대로 있고, 포켓 앞 변의 바위만 낮게 두어 비석이 보이게 한다.

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const Nature := preload("res://scripts/visual/nature_models.gd")

## 자산별 (기준 높이, 기준 반경) — forest_layout.json의 scale 대비 높이에서 역산.
const ROCK_BASE := {
	"rock_boulder_snow": Vector2(1.71, 1.38),
	"rock_shards": Vector2(2.11, 1.32),
	"rock_ledge_snow": Vector2(1.96, 1.81),
	"rock_spire_snow": Vector2(3.41, 1.38),
}
## 정원 안쪽 침엽수 [x, z, 높이] — 산장 뒤 수관. 벌목 대상이 아니다.
const PINES := [[-7.6,-7.2,6.2], [-3.4,-8.0,5.4], [-10.6,-6.4,4.6], [-0.6,-7.4,4.2], [6.6,-10.2,4.0]]
## 관목·고사리 [x, z, 자산]
const UNDERGROWTH := [[-5.8,-5.4,"berry_shrub"], [-1.0,-5.6,"fern_clump"], [-9.6,-9.2,"berry_shrub"],
	[4.0,-4.9,"fern_clump"], [8.1,-6.0,"berry_shrub"], [-12.0,-6.3,"fern_clump"], [1.2,-10.9,"berry_shrub"]]

var body: StaticBody3D
var rock_count := 0
var _rng := RandomNumberGenerator.new()


func build(world) -> void:
	name = "RearBlocker"
	_rng.seed = 20261017
	body = StaticBody3D.new()
	body.name = "RearBlockerBody"
	body.collision_layer = Cfg.L_OBSTACLE
	body.collision_mask = 0
	world.nav_region.add_child(body)
	var ring: Array = Layout.REAR_BLOCKER
	for i in ring.size() - 1:
		_wall_segment(ring[i], ring[i + 1])
	for f in Layout.REAR_FILL:
		_fill_box(Vector2(f[0], f[1]), Vector2(f[2], f[3]))
	for p in PINES:
		var pine := Nature.pine(p[2], _rng)
		pine.position = Vector3(p[0], 0, p[1])
		pine.rotation_degrees.y = _rng.randf_range(0, 360)
		add_child(pine)
	for u in UNDERGROWTH:
		var shrub := Nature.asset(u[2])
		shrub.position = Vector3(u[0], 0, u[1])
		shrub.rotation_degrees.y = _rng.randf_range(0, 360)
		add_child(shrub)


func _wall_segment(a: Vector2, b: Vector2) -> void:
	var length := a.distance_to(b)
	var mid := (a + b) * 0.5
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(Layout.REAR_BLOCKER_THICKNESS, Layout.REAR_BLOCKER_HEIGHT, length + Layout.REAR_BLOCKER_THICKNESS * 0.5)
	cs.shape = bs
	cs.position = Vector3(mid.x, Layout.REAR_BLOCKER_HEIGHT * 0.5, mid.y)
	cs.rotation.y = atan2((b - a).x, (b - a).y)
	body.add_child(cs)
	# 변 위의 바위: 약 1.9m 간격, 변 방향으로 약간 흔들어 자연스러운 띠를 만든다.
	var n := maxi(1, int(round(length / 1.9)))
	var dir := (b - a) / length
	var side := Vector2(-dir.y, dir.x)
	var front_edge := is_equal_approx(a.y, -4.0) or is_equal_approx(b.y, -4.0) or (a.y > -4.5 and b.y > -4.5)
	for k in n:
		var t := (k + 0.5) / n
		var at := a.lerp(b, t) + side * _rng.randf_range(-0.25, 0.25) + dir * _rng.randf_range(-0.3, 0.3)
		var low := front_edge and at.x > Layout.REAR_LOW_ROCKS_X.x and at.x < Layout.REAR_LOW_ROCKS_X.y
		_rock(at, low)


func _rock(at: Vector2, low: bool) -> void:
	var ids := ["rock_boulder_snow", "rock_shards", "rock_ledge_snow", "rock_boulder_snow", "rock_spire_snow"]
	var id: String = ids[_rng.randi_range(0, ids.size() - 1)]
	if low and id == "rock_spire_snow": id = "rock_boulder_snow"
	var base: Vector2 = ROCK_BASE[id]
	var height := _rng.randf_range(0.8, 1.15) if low else _rng.randf_range(1.5, 2.4)
	if id == "rock_spire_snow": height = _rng.randf_range(2.4, 3.2)
	var s := height / base.x
	var model := Nature.asset(id)
	model.position = Vector3(at.x, 0, at.y)
	model.scale = Vector3(s * _rng.randf_range(0.9, 1.25), s, s * _rng.randf_range(0.9, 1.2))
	model.rotation_degrees.y = _rng.randf_range(0, 360)
	model.set_meta("placement_role", "rear_blocker")
	add_child(model)
	rock_count += 1


func _fill_box(p0: Vector2, p1: Vector2) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	var size := p1 - p0
	bs.size = Vector3(absf(size.x), 1.2, absf(size.y))
	cs.shape = bs
	cs.position = Vector3((p0.x + p1.x) * 0.5, 0.6, (p0.y + p1.y) * 0.5)
	body.add_child(cs)
