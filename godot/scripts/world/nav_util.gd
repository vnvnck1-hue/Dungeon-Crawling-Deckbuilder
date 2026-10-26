extends RefCounted
## 내비메시 보정 공통 함수(2026-10-18, 산장 뒤 구석 진동 버그 수정).
## map_get_closest_point 는 가장 가까운 내비 폴리곤이면 무엇이든 돌려준다 — 장애물 윗면의 고립 섬이나
## 울타리·바위 띠 뒤의 막힌 포켓도 포함된다. 캐릭터 목적지는 반드시 (1) 지면 높이이고 (2) 출발점에서 경로가 닿는 곳이어야 한다.
const Layout := preload("res://scripts/world/layout.gd")
const GROUND_Y := 0.35   # 이보다 높은 내비 점은 장애물 윗면(섬)


## p 에 가장 가까운 지면 내비 점. 섬이거나 max_dist 보다 멀면 null.
static func ground_point(map: RID, p: Vector3, max_dist := 1.5):
	var c := NavigationServer3D.map_get_closest_point(map, p)
	if c.y > GROUND_Y: return null
	if Vector2(c.x - p.x, c.z - p.z).length() > max_dist: return null
	c.y = 0.0
	return c


## from 에서 to 까지 경로가 닿는가(경로 끝이 to 에서 tolerance 안).
static func reachable(map: RID, from: Vector3, to: Vector3, tolerance := 0.8) -> bool:
	var path := NavigationServer3D.map_get_path(map, from, to, true)
	return path.size() > 1 and Vector2(path[-1].x - to.x, path[-1].z - to.z).length() <= tolerance


## 지면 내비 점이면서 from 에서 닿는 점. 아니면 null.
static func walkable_from(map: RID, from: Vector3, p: Vector3, max_dist := 1.5, tolerance := 0.8):
	var c = ground_point(map, p, max_dist)
	if c == null: return null
	if not reachable(map, from, c, tolerance): return null
	return c


## 마녀 클릭 이동 등: 가까운 지면 점을 돌려준다. 가장 가까운 내비 점이 섬이면 반경 안에서 지면 점을 다시 찾고, 없으면 p 그대로(y=0).
static func ground_or_near(map: RID, p: Vector3, search := 2.5) -> Vector3:
	var c := NavigationServer3D.map_get_closest_point(map, p)
	if c.y <= GROUND_Y:
		c.y = 0.0
		return c
	for ring in [1.0, 2.0, search]:
		for i in 8:
			var a := TAU * i / 8.0
			var q = ground_point(map, p + Vector3(cos(a), 0, sin(a)) * ring, 1.0)
			if q != null: return q
	return Vector3(p.x, 0.0, p.z)
