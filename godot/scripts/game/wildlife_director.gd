extends Node
## WildlifeDirector: 낮 동안 숲에 토끼·사슴을 가끔 풀어 둔다(기획 §3). 밤에는 새로 나오지 않고 남은 개체는 사라진다.
## 출현 지점은 산장에서 ANIMAL_SPAWN_RING 거리의 이동 가능 지면이며, 목장·위험 지역·지도 밖은 피한다.

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const Hazards := preload("res://scripts/world/hazard_sites.gd")
const AnimalScript := preload("res://scripts/actors/wild_animal.gd")

var game
var stats := {"spawned": 0}
var _timer := 6.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "WildlifeDirector"
	_rng.randomize()


func alive(kind := "") -> int:
	var n := 0
	for a in get_tree().get_nodes_in_group("animals"):
		if not a.dead and (kind == "" or a.kind == kind):
			n += 1
	return n


func _process(delta: float) -> void:
	if game == null or game.session == null or game.session.is_over() or game.session.state != 0:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = _rng.randf_range(Cfg.ANIMAL_SPAWN_INTERVAL[0], Cfg.ANIMAL_SPAWN_INTERVAL[1])
	var want: Array = []
	if alive("rabbit") < Cfg.RABBIT_MAX:
		want.append("rabbit")
	if alive("deer") < Cfg.DEER_MAX:
		want.append("deer")
	if want.is_empty():
		return
	spawn(want[_rng.randi_range(0, want.size() - 1)])


## 한 마리 출현. 적당한 자리를 못 찾으면 null.
func spawn(kind: String, near := Vector3.INF):
	var p := _find_spot(near)
	if p == Vector3.INF:
		return null
	var a := AnimalScript.new()
	a.setup(game, kind)
	a.position = p
	game.actors.add_child(a)
	stats["spawned"] += 1
	return a


func _find_spot(near: Vector3) -> Vector3:
	var nav_map: RID = game.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		return Vector3.INF
	var c: Vector3 = game.world.lodge.global_position
	for i in 24:
		var p: Vector3
		if near != Vector3.INF:
			p = near + Vector3(_rng.randf_range(-3, 3), 0, _rng.randf_range(-3, 3))
		else:
			var a := _rng.randf_range(0.0, TAU)
			var r := _rng.randf_range(Cfg.ANIMAL_SPAWN_RING[0], Cfg.ANIMAL_SPAWN_RING[1])
			p = c + Vector3(cos(a) * r, 0, sin(a) * r)
		if Vector2(p.x, p.z).distance_to(Layout.MAP_CENTER) > Layout.BOUNDARY_RADIUS - 3.0:
			continue
		if Hazards.clearing_at(Vector2(p.x, p.z)):
			continue
		var nav = NavUtil.walkable_from(nav_map, Layout.DOOR_FRONT, p, 1.5)
		if nav == null:
			continue
		if game.world.pasture.inside(nav, 1.0) or game.world.lodge.distance_to(nav) < 3.0:
			continue
		return nav
	return Vector3.INF


## 웨이브 시작: 남은 동물은 숲으로 사라진다.
func on_wave_start() -> void:
	for a in get_tree().get_nodes_in_group("animals"):
		if not a.dead:
			a.leave()
