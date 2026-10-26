extends RefCounted
## Single source for terrain, clearing exclusions, inhabitants and map markers.
const SITES := [
	{"id":"venom_hollow", "label":"맹독 균열지", "center":Vector2(-23,-13), "radii":Vector2(8.0,6.8), "seed":61015, "count":6},
	{"id":"wing_nest", "label":"독날개 군락", "center":Vector2(26,-10), "radii":Vector2(6.4,7.4), "seed":61016, "count":5},
	{"id":"blighted_roots", "label":"오염된 뿌리숲", "center":Vector2(-4,28), "radii":Vector2(6.2,5.4), "seed":61017, "count":4},
]
## 니벨라의 서리 둥지(보스룸). 맵 북쪽 경계 밖으로 붙은 별관이며 남쪽 끝만 필드와 겹친다.
## 입구는 남쪽(entrance_angle, 타원 매개변수 각)으로 열려 서쪽 탐험길 (0,-27) 에서 PATH_NEST 로 이어진다.
## 처음 블록아웃(14×11m)의 지름 3배인 42×33m — 줌아웃한 화면을 거의 꽉 채운다. 독 서식지와 달리 지형 오염·주민은 없고 world/boss_room.gd 가 모두 맡는다.
## 이동 제한(Layout.clamp_to_map)·숲 경계 울타리(world._build_boundary)는 이 타원 안을 맵으로 친다.
const BOSS_ROOM := {"id":"nivella_lair", "label":"니벨라의 서리 둥지", "center":Vector2(-4.0,-48.0), "radii":Vector2(21.0,16.2),
	"entrance_angle":1.35, "entrance_half":.27}

static func normalized_distance(point: Vector2, site: Dictionary) -> float:
	return ((point-site.center)/site.radii).length()

static func clearing_at(point: Vector2) -> bool:
	for site in SITES:
		if normalized_distance(point,site)<.94: return true
	return normalized_distance(point,BOSS_ROOM)<1.18

static func influence_at(point: Vector2) -> float:
	var value := 0.0
	for site in SITES:
		value = maxf(value,1.0-smoothstep(.55,1.55,normalized_distance(point,site)))
	return value

static func site_at(point: Vector2) -> Dictionary:
	for site in SITES:
		if normalized_distance(point,site)<1.15: return site
	return {}
