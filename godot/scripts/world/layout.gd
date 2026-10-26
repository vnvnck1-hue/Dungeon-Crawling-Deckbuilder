extends RefCounted
## 장면 배치값. 산장 바닥 중심 = 원점, 1단위 = 1m, 건물 정면 = +Z.
## 화면 기준: 카메라가 +X+Z 쪽에서 내려다보므로 화면 아래 = (+X,+Z), 화면 왼쪽 위 = -X, 오른쪽 위 = -Z.
## 화면 오른쪽 1m = 월드 (0.819, -0.574), 화면 아래 1m = 월드 (0.574, 0.819).
##
## 산장 주변은 A안(docs/handoff/lodge-map-layout-a-v01.md, 2026-10-17 승인)을 따른다.
##  - 산장 뒤: REAR_BLOCKER 바위 띠가 닫힌 고리로 감싸 마녀·일꾼·적 모두 산장 뒤를 통과하지 못한다(묘지는 띠 안 포켓).
##  - 산장 왼쪽(-X): EXTENSION_RESERVE 증축 예약 눈밭. 장식·자원 나무·길을 두지 않는다.
##  - 산장 오른쪽(+X): 목장(config.gd PASTURE_LEVELS).
##  - 앞마당: CAMPFIRE 일꾼 쉼터, 양옆 TOWER_SITE_LEFT/RIGHT 감시탑 예약 공터, 왼쪽 아래 ALTAR_SITE 제단 예약 공터.
##  - 좌우 웨이브 길: PATH_A(서쪽 숲 → 마당), PATH_B(동쪽 숲 → 마당). 북쪽 제단은 PATH_SHRINE 탐험길로만 잇는다.

const CAMERA_TARGET := Vector3(1.0, 0.0, 1.3)
const CAMERA_YAW := 35.0
const CAMERA_PITCH := 50.0
const CAMERA_SIZE := 21.0
const CAMERA_DISTANCE := 45.0

const PLINTH_SIZE := Vector3(4.9, 0.4, 5.9)
const LODGE_RECT := Rect2(-2.45, -2.95, 4.9, 5.9)
const EXTENSION_RECT := Rect2(-5.45, -1.7, 3.2, 3.4)
## 증축 예약 영역(본채 왼쪽 벽에 이어진 눈밭). 최종 증축 크기는 미정이라 모듈 2칸 폭만큼 비워 둔다.
const EXTENSION_RESERVE := Rect2(-9.5, -3.0, 7.25, 6.0)
## 목장 영역은 단계별로 config.gd의 PASTURE_LEVELS가 정한다(산장 +X 벽을 한 변으로 공유).

const DOOR_FRONT := Vector3(0.5, 0.0, 3.9)
const PLAYER_START := Vector3(5.3, 0.0, 6.2)
const DRAGON_ANCHOR := Vector3(0.0, 5.0, -0.3)
const CHIMNEY_TOP := Vector3(1.20, 5.23, 1.28)

## ── 앞마당(A안) ──
## 모닥불: 현관에서 화면 아래로 약 7.8m. 대기 용병은 둘레 두 겹(rest_slots)에 선다.
const CAMPFIRE := Vector3(4.3, 0.0, 11.0)
const CAMPFIRE_RADIUS := 0.9        # 불·돌 둘레 충돌 반경
const REST_RING_INNER := 1.7
const REST_RING_OUTER := 2.5
## 마당 길 분기점(모닥불 왼쪽). 현관 길·왼쪽 길·오른쪽 길·제단 가지 길이 여기서 만난다.
const YARD_HUB := Vector2(1.0, 10.5)
## 감시탑 건설 예약 공터 2곳(모닥불 화면 좌우 약 7m). 초기에는 모서리 돌만 있는 빈 사각 공터.
const TOWER_SITE_LEFT := Vector2(-3.6, 12.4)
const TOWER_SITE_RIGHT := Vector2(9.2, 6.2)
const TOWER_SITE_SIZE := 3.2
## 제단 건설 예약 공터(화면 왼쪽 아래 원형). 기존 제단 시스템은 LANDMARKS.shrine에 그대로 둔다.
const ALTAR_SITE := Vector2(-3.0, 16.8)
const ALTAR_SITE_RADIUS := 2.2

## ── 길 ──
## 웨이브 길 두 개. 각 배열의 앞쪽이 마당(카메라 쪽) 끝, 뒤쪽이 숲 안쪽 끝.
## PATH_A: 서쪽 벌목터에서 현관 앞 길로. PATH_B: 동쪽 숲에서 목장 앞을 지나 모닥불 남쪽으로 돌아 분기점으로.
const PATH_DOOR := [Vector2(0.5,3.9), Vector2(0.8,7.0), Vector2(1.0,10.5)]
const PATH_A := [Vector2(0.8,7.0), Vector2(-3.5,9.5), Vector2(-8,8), Vector2(-13.5,5.5),
	Vector2(-18,4), Vector2(-24,5)]
const PATH_B := [Vector2(1.0,10.5), Vector2(2.3,14.2), Vector2(6.8,13.6), Vector2(10,10.5),
	Vector2(14,6.5), Vector2(18.5,4.5), Vector2(23,4.2), Vector2(27,5)]
const PATH_ALTAR := [Vector2(1.0,10.5), Vector2(-0.4,13.0), Vector2(-1.8,14.9)]
## 북쪽 달빛 돌 제단으로 가는 탐험길(웨이브 진입로 아님). 오른쪽 길에서 갈라져 목장 동쪽 바깥을 지난다.
const PATH_SHRINE := [Vector2(14,6.5), Vector2(14.2,1.5), Vector2(13.5,-4), Vector2(12.5,-9),
	Vector2(10.5,-13.5), Vector2(8,-17), Vector2(7,-20), Vector2(8,-26), Vector2(6,-27)]
const SPAWN_A := Vector3(-21.5, 0.0, 2.7)
const SPAWN_B := Vector3(25.5, 0.0, 4.4)
const TRAVELER_ROUTE := [Vector3(-14.5, 0, 5.2), Vector3(-8, 0, 8), Vector3(-3.5, 0, 9.5), Vector3(0.8, 0, 7.0), Vector3(0.5, 0, 3.9)]

const BOUNDARY_RADIUS := 38.0
const GROUND_EXTENT := 104.0
const MAP_CENTER := Vector2(1.0, 1.3)
## Walkable clearings, connected by wide snow trails. Existing enemy spawns stay near the lodge.
const LANDMARKS := [
	{"id":"logging", "name":"서쪽 벌목터", "pos":Vector2(-24, 5)},
	{"id":"shrine", "name":"달빛 돌 제단", "pos":Vector2(8, -26)},
	{"id":"camp", "name":"숲속 야영지", "pos":Vector2(-20, 23)},
	{"id":"lookout", "name":"설원 전망터", "pos":Vector2(23, 18)},
]
const PATH_WEST := [Vector2(-13.5,5.5), Vector2(-24,5), Vector2(-29,1), Vector2(-30,-6),
	Vector2(-25,-13), Vector2(-19,-18), Vector2(-9,-23), Vector2(0,-27), Vector2(8,-26)]
const PATH_NORTH := [Vector2(8,-26), Vector2(15,-28), Vector2(23,-24), Vector2(29,-18),
	Vector2(30,-8), Vector2(27,1), Vector2(27,9), Vector2(23,18)]
const PATH_SOUTH := [Vector2(-24,5), Vector2(-29,12), Vector2(-26,19), Vector2(-20,23),
	Vector2(-12,27), Vector2(-2,30), Vector2(10,27), Vector2(18,24), Vector2(23,18)]
## 야영지에서 제단 공터 남쪽을 지나 모닥불 남쪽 오른쪽 길에 합류한다.
const PATH_HOME := [Vector2(-20,23), Vector2(-14,21.5), Vector2(-8.5,20.2), Vector2(-3.5,20.3),
	Vector2(0.5,19.6), Vector2(3.8,17.4), Vector2(6.8,13.6)]
## 서쪽 탐험길에서 북쪽 니벨라 둥지 입구로(hazard_sites.gd BOSS_ROOM).
const PATH_NEST := [Vector2(0,-27), Vector2(0.2,-30.0), Vector2(0.5,-32.8)]
const EXPLORATION_PATHS := [PATH_DOOR, PATH_A, PATH_B, PATH_ALTAR, PATH_SHRINE, PATH_HOME,
	PATH_WEST, PATH_NORTH, PATH_SOUTH, PATH_NEST]

## ── 후면 차단 띠 ──
## 닫힌 고리 중심선. 각 변에 상자 충돌(REAR_BLOCKER_THICKNESS 두께)을 두고 그 위에 바위를 얹는다.
## 고리 안쪽은 산장 뒤 바위 정원 + 묘지 포켓이며 REAR_FILL 상자로 내비메시에서 제외한다.
const REAR_BLOCKER := [Vector2(-13.2,-4.3), Vector2(-2.6,-4.0), Vector2(8.6,-4.0), Vector2(9.0,-11.0),
	Vector2(3.0,-11.6), Vector2(-3.0,-12.2), Vector2(-4.5,-12.0), Vector2(-6.5,-11.5), Vector2(-9.0,-8.5),
	Vector2(-11.5,-5.0), Vector2(-13.2,-4.3)]
const REAR_BLOCKER_THICKNESS := 1.4
const REAR_BLOCKER_HEIGHT := 1.9
## [x0, z0, x1, z1] 고리 안쪽을 덮는 평면 차단 상자
const REAR_FILL := [[-10.5,-9.3,0.5,-4.6], [0.5,-10.6,8.4,-4.6], [-5.5,-11.4,0.5,-9.3], [-8.5,-10.5,-5.5,-9.3]]
## 띠 안쪽에서 바위를 낮게 두어 묘지가 보이게 하는 구간(x 범위, 앞 변에만 적용)
const REAR_LOW_ROCKS_X := Vector2(0.5, 8.6)

## [x, z, 높이]
## Resource wrappers keep their original coordinates. Decorative forest lives in forest_layout.json.
## 예약 영역(증축·후면 띠·마당 공터) 밖에만 둔다. 후면 차단은 자원 나무에 의존하지 않는다.
const TREES := [[-11.6,1.2,6.0],[-3.6,-16.2,6.6],[-9.2,18.0,5.6]]
## [x, z, 크기]
const ROCKS := []
const SHRUBS := []
const LOGS := []
const STEPPING_STONES := [[0.6, 5.1], [0.85, 6.4], [1.0, 7.7], [1.05, 9.0]]


## 모닥불 둘레 대기 자리(안쪽 8 + 바깥 8). ContractDirector가 대기 용병을 여기 세운다.
static func rest_slots() -> Array:
	var out: Array = []
	for i in 8:
		var a := TAU * i / 8.0 + 0.2
		out.append(CAMPFIRE + Vector3(cos(a), 0, sin(a)) * REST_RING_INNER)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0 + 0.2
		out.append(CAMPFIRE + Vector3(cos(a), 0, sin(a)) * REST_RING_OUTER)
	return out


static func tower_site_rect(center: Vector2) -> Rect2:
	return Rect2(center - Vector2.ONE * TOWER_SITE_SIZE * 0.5, Vector2.ONE * TOWER_SITE_SIZE)


## 마당 시설·예약 공간 안인가(길·식생·자원 배치를 피할 때 쓴다).
static func in_yard_reserve(p: Vector2, margin := 0.0) -> bool:
	if p.distance_to(Vector2(CAMPFIRE.x, CAMPFIRE.z)) < REST_RING_OUTER + 0.6 + margin: return true
	if p.distance_to(ALTAR_SITE) < ALTAR_SITE_RADIUS + margin: return true
	for c in [TOWER_SITE_LEFT, TOWER_SITE_RIGHT]:
		if tower_site_rect(c).grow(margin).has_point(p): return true
	return EXTENSION_RESERVE.grow(margin).has_point(p)


## 후면 차단 고리 안쪽인가(짝수-홀수 규칙).
static func in_rear_enclosure(p: Vector2) -> bool:
	var inside := false
	var n := REAR_BLOCKER.size() - 1
	for i in n:
		var a: Vector2 = REAR_BLOCKER[i]
		var b: Vector2 = REAR_BLOCKER[i + 1]
		if (a.y > p.y) != (b.y > p.y):
			var x := a.x + (p.y - a.y) / (b.y - a.y) * (b.x - a.x)
			if p.x < x: inside = not inside
	return inside


static func seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func dist_to_path(p: Vector2, path: Array, from_index := 0) -> float:
	var best := 1e9
	for i in range(from_index, path.size() - 1):
		best = minf(best, seg_dist(p, path[i], path[i + 1]))
	return best


static func dist_to_trails(p: Vector2) -> float:
	var best := 1e9
	for path in EXPLORATION_PATHS:
		best = minf(best, dist_to_path(p, path))
	return best


## 북쪽 경계 밖 보스 둥지 안인가(정규 거리 limit 미만).
static func in_boss_nest(p: Vector2, limit := 0.97) -> bool:
	var nest: Dictionary = preload("res://scripts/world/hazard_sites.gd").BOSS_ROOM
	return ((p - nest.center) / nest.radii).length() < limit


static func clamp_to_map(p: Vector3, margin := 1.0) -> Vector3:
	var at := Vector2(p.x, p.z)
	var flat := at - MAP_CENTER
	if flat.length() <= BOUNDARY_RADIUS - margin or in_boss_nest(at):
		return Vector3(p.x, 0.0, p.z)
	# 둥지 별관 쪽으로 벗어났으면 원형 맵이 아니라 둥지 타원 안쪽으로 당긴다(둥지 안에서 원 쪽으로 튀지 않게)
	var nest: Dictionary = preload("res://scripts/world/hazard_sites.gd").BOSS_ROOM
	var n: Vector2 = (at - nest.center) / nest.radii
	if n.length() < 1.3 and flat.length() < BOUNDARY_RADIUS + 40.0:
		var e: Vector2 = nest.center + n.normalized() * 0.96 * nest.radii
		return Vector3(e.x, 0.0, e.y)
	flat = flat.limit_length(BOUNDARY_RADIUS - margin) + MAP_CENTER
	return Vector3(flat.x, 0.0, flat.y)
