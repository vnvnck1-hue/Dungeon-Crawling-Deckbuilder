extends Node3D
## 산장 주변 식생 구분선(시안, 2026-10-18). 길목과 각 구역(증축 예약 눈밭·목장·앞마당 공터·좌우 웨이브 길·
## 제단 탐험길) 사이를 밀도 높은 식생 띠로 갈라 구분선 역할을 하게 한다.
##
## 데이터 구조
##  - BANDS: 모든 시안이 공유하는 구분선 중심선(월드 x,z). face = 띠가 바라보는 길·마당 쪽 점(앞면 판정).
##           gates = 중심선을 따라 [시작 m, 끝 m] 구간을 비워 통행구를 남긴다.
##  - PROFILES: 띠의 단면. rows = 중심선에서의 오프셋(+ 앞면/길 쪽, − 뒷면)과 자산·높이·간격.
##  - VARIANTS: 시안 id → 기본 단면 + 띠별 단면 덮어쓰기. "none" 은 현재 배치 그대로.
##
## 규칙(parts_for 가 거른다)
##  - 충돌 부품(나무·바위)은 길 중심선에서 LANE_COLLIDER + 충돌 반경 이상, 장식은 LANE_DECOR 이상 떨어진다.
##  - 증축 예약·감시탑·제단·모닥불 쉼터(Layout.in_yard_reserve)·후면 띠 안·산장 주변·목장(최대 단계)·목장 문 앞·
##    스폰·랜드마크·오염 지역·자원 나무 접근 반경에는 두지 않는다.
##  - 기존 숲 군집(forest_layout.json)·후면 띠 침엽수·같은 레이어의 충돌 부품과 겹치지 않는다.
##  - 나무는 벌목 대상이 아니다(harvest_trees 에 넣지 않는다). 구분선은 고정 지형이다.
##
## 실행 인자 `--yard-hedge=<id>` 로 시작 시안을 고르고, 게임 중 F7 로 순환한다.

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const Nature := preload("res://scripts/visual/nature_models.gd")
const Forest := preload("res://scripts/world/forest_composition.gd")
const Hazards := preload("res://scripts/world/hazard_sites.gd")
const RearBlocker := preload("res://scripts/world/rear_blocker.gd")
const CATALOG := "res://assets/nature/catalog.json"

const LANE_COLLIDER := 2.6   # 길 중심선 → 충돌면 최소 거리(+ 충돌 반경). 교행 여유 ≈ 2×(2.6−1.8 트레일 반폭)
const LANE_DECOR := 1.9      # 장식(충돌 없음)은 트레일 가장자리까지 내려온다
const TREE_RADIUS := 0.4
const LODGE_MARGIN := 2.4    # 본채 주변: 공격 지점(0.85) + 에이전트 통행
const PASTURE_MARGIN := 1.0
const ORDER := ["none", "a", "b", "c"]
static var current_id := "c"   # 사용자 선택(2026-10-18): C안 바위 능선

## 구분선 중심선. 좌표는 docs/yard-hedge-proposals-v01.md 의 평면도와 같다.
const BANDS := [
	# ── 왼쪽 웨이브 길(PATH_A) ↔ 증축 예약 눈밭: 눈밭의 남쪽 울타리. 산장 모퉁이(x>−8.2) 쪽은 열어 둔다.
	{"id": "reserve_south", "label": "증축 예약 남쪽 울타리", "points": [Vector2(-14.6, 2.0), Vector2(-12.6, 2.8), Vector2(-10.4, 3.9), Vector2(-9.0, 4.3), Vector2(-8.2, 4.4)],
		"face": Vector2(-9, 8), "gates": []},
	# ── 증축 예약 눈밭 서쪽 마감: 울타리 끝에서 후면 띠 시작점까지 올라가 눈밭을 포켓으로 닫는다.
	{"id": "reserve_west", "label": "증축 예약 서쪽 마감", "points": [Vector2(-14.8, 1.4), Vector2(-14.6, -1.4), Vector2(-13.9, -3.7)],
		"face": Vector2(-18, -1), "gates": []},
	# ── 왼쪽 웨이브 길 북쪽 가장자리(벌목터 방향): 길목을 좁혀 진입로가 읽히게 한다.
	{"id": "lane_a_north", "label": "왼쪽 길 북쪽 길목", "points": [Vector2(-20.2, 0.1), Vector2(-18.3, 0.3), Vector2(-16.4, 0.7), Vector2(-15.0, 1.3)],
		"face": Vector2(-17, 4.5), "gates": []},
	# ── 왼쪽 웨이브 길 남쪽 가장자리: 길과 남서 숲(home_neck·lodge_south) 사이를 메운다.
	{"id": "lane_a_south", "label": "왼쪽 길 남쪽 길목", "points": [Vector2(-21.0, 8.2), Vector2(-18.0, 7.5), Vector2(-14.8, 8.9), Vector2(-11.2, 10.6), Vector2(-8.6, 11.6)],
		"face": Vector2(-14, 5.5), "gates": []},
	# ── 제단·감시탑 포켓 서쪽 벽: 왼쪽 길에서 제단 공터·탑 공터 뒤로 돌아가는 눈밭을 막고 포켓을 만든다.
	{"id": "altar_west", "label": "제단 포켓 서쪽 벽", "points": [Vector2(-6.6, 12.0), Vector2(-7.4, 14.2), Vector2(-7.2, 16.9)],
		"face": Vector2(-3.5, 15), "gates": []},
	# ── 목장 동쪽 ↔ 북쪽 제단 탐험길: 목장 울타리 바깥에 좁은 통로(목장 문 접근)만 남기고 탐험길과 가른다.
	{"id": "pasture_east", "label": "목장 동쪽 울타리", "points": [Vector2(10.4, 3.4), Vector2(10.6, 0.4), Vector2(10.6, -3.0)],
		"face": Vector2(14, 0), "gates": []},
	# ── 오른쪽 웨이브 길(PATH_B) 남쪽 가장자리: 남동 숲(south_gate·lookout_inner)을 길까지 끌어와 길목을 만든다.
	{"id": "lane_b_south", "label": "오른쪽 길 남쪽 길목", "points": [Vector2(11.5, 13.6), Vector2(14.6, 10.7), Vector2(17.7, 8.5), Vector2(21.2, 7.7), Vector2(23.8, 7.9)],
		"face": Vector2(16, 6), "gates": []},
	# ── 오른쪽 웨이브 길 북쪽 가장자리(동쪽 바위 병풍 앞): 스폰 B 쪽 진입로를 양쪽에서 조인다.
	{"id": "lane_b_north", "label": "오른쪽 길 북쪽 길목", "points": [Vector2(17.4, 1.3), Vector2(19.6, 0.9), Vector2(22.4, 0.9), Vector2(23.6, 1.2)],
		"face": Vector2(20, 4.5), "gates": []},
	# ── 앞마당 길 가장자리 장식 줄(충돌 없음): 마당 안에서는 길 가장자리를 낮은 식생으로만 긋는다.
	{"id": "yard_edge_b", "label": "오른쪽 길 마당 쪽 가장자리", "points": [Vector2(7.6, 15.9), Vector2(10.4, 13.6), Vector2(13.2, 9.9)],
		"face": Vector2(9, 11), "gates": [], "profile": "edge"},
	{"id": "yard_edge_home", "label": "야영지 길 남쪽 가장자리", "points": [Vector2(-7.0, 22.4), Vector2(-3.2, 22.5), Vector2(1.0, 21.8), Vector2(4.6, 19.8)],
		"face": Vector2(-2, 19), "gates": [], "profile": "edge"},
	# ── 공터 테두리(충돌 없음): 감시탑 공터 2곳·제단 공터를 낮은 관목 고리로 둘러 포켓으로 읽히게 한다. 길에 닿는 변은 자동으로 비워진다.
	{"id": "ring_tower_l", "label": "왼쪽 감시탑 공터 테두리", "points": [Vector2(-5.75, 10.3), Vector2(-5.75, 14.6), Vector2(-1.45, 14.6), Vector2(-1.45, 10.3), Vector2(-5.75, 10.3)],
		"face": Vector2(-3.6, 12.4), "gates": [], "profile": "edge"},
	{"id": "ring_tower_r", "label": "오른쪽 감시탑 공터 테두리", "points": [Vector2(7.05, 4.1), Vector2(7.05, 8.4), Vector2(11.35, 8.4), Vector2(11.35, 4.1), Vector2(7.05, 4.1)],
		"face": Vector2(9.2, 6.2), "gates": [], "profile": "edge"},
	{"id": "ring_altar", "label": "제단 공터 테두리", "points": [Vector2(-3.0, 14.0), Vector2(-5.0, 14.8), Vector2(-5.8, 16.8), Vector2(-5.0, 18.8), Vector2(-3.0, 19.6), Vector2(-1.0, 18.8), Vector2(-0.2, 16.8), Vector2(-1.0, 14.8), Vector2(-3.0, 14.0)],
		"face": Vector2(-3.0, 16.8), "gates": [], "profile": "edge"},
]

## 단면. rows: offset(+ 앞면), kind, assets, h(높이 m 범위; decor 는 스케일 배수), spacing(m), jitter(m, 중심선 방향)
const PROFILES := {
	# 낮은 생울타리: 묘목 두 줄·관목·고사리·작은 바위. 시야를 거의 가리지 않는 선.
	"hedge": {"rows": [
		{"offset": 0.0, "kind": "tree", "assets": ["pine_sapling_snow", "pine_sapling_snow", "pine_sapling"], "h": [1.7, 2.8], "spacing": 1.4, "jitter": 0.3},
		{"offset": -1.05, "kind": "tree", "assets": ["pine_sapling_snow", "pine_sapling"], "h": [1.6, 2.5], "spacing": 1.6, "jitter": 0.5},
		{"offset": -0.5, "kind": "rock", "assets": ["rock_boulder_snow", "rock_shards"], "h": [0.7, 1.05], "spacing": 6.0, "jitter": 1.2},
		{"offset": 0.7, "kind": "decor", "assets": ["berry_shrub", "fern_clump", "berry_shrub"], "h": [0.85, 1.2], "spacing": 0.9, "jitter": 0.25},
		{"offset": -0.5, "kind": "decor", "assets": ["fern_clump", "berry_shrub", "mushroom_cluster"], "h": [0.75, 1.1], "spacing": 1.1, "jitter": 0.3},
		{"offset": -1.7, "kind": "decor", "assets": ["fern_clump", "berry_shrub"], "h": [0.7, 1.0], "spacing": 1.5, "jitter": 0.4},
	]},
	# 숲 쐐기: 큰 침엽수 세 줄(앞줄에 묘목 섞음) + 앞쪽 관목. 원화처럼 길이 숲 사이 골짜기로 읽힌다.
	"wedge": {"rows": [
		{"offset": 0.0, "kind": "tree", "assets": ["pine_swept_snow", "pine_broad_snow", "pine_sparse_snow"], "h": [4.6, 7.0], "spacing": 1.9, "jitter": 0.4},
		{"offset": -0.15, "kind": "tree", "assets": ["pine_sapling_snow", "pine_sapling"], "h": [1.6, 2.5], "spacing": 2.1, "jitter": 0.6},
		{"offset": -1.8, "kind": "tree", "assets": ["pine_broad_snow", "pine_swept_snow", "pine_sparse_snow"], "h": [3.8, 5.8], "spacing": 2.0, "jitter": 0.55},
		{"offset": -3.5, "kind": "tree", "assets": ["pine_broad_snow", "pine_swept_snow"], "h": [3.4, 5.2], "spacing": 2.2, "jitter": 0.6},
		{"offset": -0.8, "kind": "rock", "assets": ["rock_boulder_snow", "rock_shards"], "h": [0.9, 1.4], "spacing": 7.0, "jitter": 1.5},
		{"offset": 0.75, "kind": "decor", "assets": ["berry_shrub", "fern_clump", "fern_clump"], "h": [0.8, 1.2], "spacing": 1.0, "jitter": 0.3},
		{"offset": -0.9, "kind": "decor", "assets": ["fern_clump", "mushroom_cluster"], "h": [0.7, 1.0], "spacing": 1.5, "jitter": 0.4},
		{"offset": -2.6, "kind": "decor", "assets": ["fern_clump", "berry_shrub"], "h": [0.7, 1.0], "spacing": 1.8, "jitter": 0.5},
	]},
	# 바위 능선: 앞줄은 층진 바위·둥근 바위, 뒤에 중간 침엽수 두 줄. 후면 띠와 같은 재질로 경계가 '선'으로 읽힌다.
	"ridge": {"rows": [
		{"offset": -0.35, "kind": "rock", "assets": ["rock_boulder_snow", "rock_shards", "rock_ledge_snow", "rock_boulder_snow"], "h": [0.8, 1.15], "spacing": 1.5, "jitter": 0.3},
		{"offset": -2.0, "kind": "tree", "assets": ["pine_broad_snow", "pine_swept_snow", "pine_sparse_snow"], "h": [3.6, 5.6], "spacing": 2.0, "jitter": 0.55},
		{"offset": -3.6, "kind": "tree", "assets": ["pine_swept_snow", "pine_broad_snow"], "h": [3.2, 4.8], "spacing": 2.3, "jitter": 0.6},
		{"offset": -1.2, "kind": "tree", "assets": ["pine_sapling_snow"], "h": [1.6, 2.2], "spacing": 2.6, "jitter": 0.7},
		{"offset": 0.75, "kind": "decor", "assets": ["fern_clump", "berry_shrub", "fern_clump"], "h": [0.8, 1.15], "spacing": 0.95, "jitter": 0.3},
		{"offset": -1.3, "kind": "decor", "assets": ["berry_shrub", "mushroom_cluster", "fern_clump"], "h": [0.7, 1.0], "spacing": 1.6, "jitter": 0.4},
	]},
	# 마당 안 길 가장자리: 충돌 없는 관목·고사리 줄 + 아주 작은 바위. 동선은 그대로.
	"edge": {"rows": [
		{"offset": 0.0, "kind": "decor", "assets": ["berry_shrub", "fern_clump", "berry_shrub", "fern_clump"], "h": [0.85, 1.2], "spacing": 0.85, "jitter": 0.25},
		{"offset": -0.6, "kind": "decor", "assets": ["fern_clump", "mushroom_cluster", "berry_shrub"], "h": [0.7, 1.0], "spacing": 1.2, "jitter": 0.35},
		{"offset": -0.3, "kind": "decor", "assets": ["rock_shards"], "h": [0.45, 0.6], "spacing": 4.5, "jitter": 1.0},
	]},
}

const VARIANTS := {
	"none": {"name": "현재 배치(구분선 없음)", "profile": "", "overrides": {}},
	"a": {"name": "A안 생울타리 — 낮은 관목·묘목 띠", "profile": "hedge",
		"overrides": {}},
	"b": {"name": "B안 숲 쐐기 — 큰 침엽수 벽", "profile": "wedge",
		"overrides": {"reserve_south": "hedge", "pasture_east": "hedge"}},
	"c": {"name": "C안 바위 능선 — 바위 앞줄·수관 뒷줄", "profile": "ridge",
		"overrides": {"reserve_south": "hedge"}},
}

static var _catalog: Dictionary = {}
static var _generated: Dictionary = {}
var variant_id := "none"
var parts: Array = []
var bodies: Array = []
var _occluders: Array = []
var _world


static func catalog() -> Dictionary:
	if _catalog.is_empty():
		for a in JSON.parse_string(FileAccess.get_file_as_string(CATALOG)).assets:
			_catalog[a.id] = a
	return _catalog


static func variant_from_args() -> String:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--yard-hedge="):
			var id := arg.get_slice("=", 1)
			if VARIANTS.has(id): return id
	return current_id


static func band_profile(variant: String, band: Dictionary) -> String:
	var v: Dictionary = VARIANTS[variant]
	if band.has("profile"): return band.profile
	if v.overrides.has(band.id): return v.overrides[band.id]
	return v.profile


## 시안의 모든 부품(순수 데이터). [{band, kind, asset, at:Vector2, scale:Vector3, rot:Vector3, height, radius}]
static func parts_for(variant: String) -> Array:
	if _generated.has(variant): return _generated[variant]
	var out: Array = []
	if variant == "none" or not VARIANTS.has(variant) or VARIANTS[variant].profile == "":
		_generated[variant] = out
		return out
	var blockers: Array = _static_blockers()
	for band in BANDS:
		var profile: Dictionary = PROFILES[band_profile(variant, band)]
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(variant + ":" + band.id)
		var pts: Array = band.points
		var total := 0.0
		for i in pts.size() - 1: total += pts[i].distance_to(pts[i + 1])
		for row in profile.rows:
			var t := rng.randf_range(0.2, row.spacing * 0.6)
			while t < total - 0.15:
				var sample := _sample(pts, t, band.face)
				var slot_t := t
				t += row.spacing * rng.randf_range(0.82, 1.18)
				if _in_gate(band, slot_t): continue
				# 자리마다 몇 번 흔들어 기존 나무·바위 사이 틈을 채운다(밀도 확보).
				for attempt in 5:
					var spread := 1.0 + attempt * 0.55
					var at: Vector2 = sample.p + sample.n * (row.offset + rng.randf_range(-0.35, 0.35) * spread) \
						+ sample.d * rng.randf_range(-row.jitter, row.jitter) * spread
					var asset: String = row.assets[rng.randi_range(0, row.assets.size() - 1)]
					var part := _make_part(band.id, row.kind, asset, at, rng.randf_range(row.h[0], row.h[1]), rng, sample.n)
					if _blocked(part, blockers, out): continue
					out.append(part)
					break
	_generated[variant] = out
	return out


static func _sample(pts: Array, t: float, face: Vector2) -> Dictionary:
	var left := t
	for i in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var seg := a.distance_to(b)
		if left <= seg or i == pts.size() - 2:
			var d := (b - a) / maxf(seg, 0.001)
			var p := a + d * clampf(left, 0.0, seg)
			var n := Vector2(-d.y, d.x)
			if (face - p).dot(n) < 0.0: n = -n
			return {"p": p, "d": d, "n": n}
		left -= seg
	return {"p": pts[-1], "d": Vector2.RIGHT, "n": Vector2.DOWN}


static func _in_gate(band: Dictionary, t: float) -> bool:
	for g in band.gates:
		if t >= g[0] and t <= g[1]: return true
	return false


static func _make_part(band_id: String, kind: String, asset: String, at: Vector2, h: float, rng: RandomNumberGenerator, n: Vector2) -> Dictionary:
	var size: Array = catalog()[asset].size
	var s: float
	var radius: float
	var height: float
	match kind:
		"tree":
			s = h / size[1]
			radius = TREE_RADIUS
			height = h
		"rock":
			s = h / size[1]
			radius = maxf(size[0], size[2]) * s * 0.48
			height = h
		_:
			s = h
			radius = 0.13
			height = size[1] * s
	var scale := Vector3(s * rng.randf_range(0.9, 1.12), s, s * rng.randf_range(0.9, 1.12))
	var yaw := rad_to_deg(atan2(n.x, n.y)) + rng.randf_range(-40, 40)
	var tilt := rng.randf_range(-1.5, 1.5) if kind == "tree" else 0.0
	return {"band": band_id, "kind": kind, "asset": asset, "at": at, "scale": scale,
		"rot": Vector3(tilt, yaw, tilt * 0.5), "height": height, "radius": radius,
		"canopy": maxf(size[0], size[2]) * s * 0.52}


## 기존 충돌 지형: 숲 군집의 나무·바위, 후면 띠 침엽수, 자원 나무. [{x, z, r, kind}]
static func _static_blockers() -> Array:
	var out: Array = []
	for group in Forest.layout().groups:
		for part in group.parts:
			if part.kind == "tree" or part.kind == "rock":
				out.append({"x": part.position[0], "z": part.position[1], "r": part.collider_radius, "kind": part.kind})
	for p in RearBlocker.PINES: out.append({"x": p[0], "z": p[1], "r": 0.5, "kind": "tree"})
	for t in Layout.TREES: out.append({"x": t[0], "z": t[1], "r": 0.4, "kind": "tree"})
	return out


## 충돌 부품끼리의 최소 거리. 바위끼리는 겹쳐 쌓여도 되고(바위 무더기), 나무 줄기는 바위 안에 들어가지 않는다.
static func _min_gap(kind_a: String, r_a: float, kind_b: String, r_b: float) -> float:
	if kind_a == "rock" and kind_b == "rock": return maxf(r_a, r_b) * 0.75
	if kind_a == "rock" or kind_b == "rock": return r_a + r_b + 0.05
	return r_a + r_b + 0.18


static var reject_log: Dictionary = {}


static func _blocked(part: Dictionary, blockers: Array, placed: Array) -> bool:
	var why := _reject_reason(part, blockers, placed)
	if why != "":
		var key: String = part.band + "/" + part.kind + ":" + why
		reject_log[key] = reject_log.get(key, 0) + 1
	return why != ""


static func _reject_reason(part: Dictionary, blockers: Array, placed: Array) -> String:
	var p: Vector2 = part.at
	var r: float = part.radius
	var collides: bool = part.kind != "decor"
	if Hazards.clearing_at(p): return "hazard"
	if Layout.in_rear_enclosure(p): return "rear"
	if Layout.in_yard_reserve(p, 0.4 + (r if collides else 0.0)): return "reserve"
	if Layout.LODGE_RECT.grow(LODGE_MARGIN).has_point(p): return "lodge"
	var pasture: Rect2 = Cfg.PASTURE_LEVELS[-1].rect
	var body_r: float = r if collides else 0.0
	if pasture.grow(PASTURE_MARGIN + body_r).has_point(p): return "pasture"
	# 목장 문 앞 통로(문 동쪽 x 7.75~9.9, 목장 전체 길이). 충돌 반경만큼 더 비워 최대 목장 문까지 통행을 지킨다.
	if Rect2(pasture.end.x, pasture.position.y - 1.0, 2.15, pasture.size.y + 2.0).grow(body_r).has_point(p): return "gate"
	if p.distance_to(Vector2(Layout.DOOR_FRONT.x, Layout.DOOR_FRONT.z)) < 2.6: return "door"
	for s in [Layout.SPAWN_A, Layout.SPAWN_B]:
		if p.distance_to(Vector2(s.x, s.z)) < 2.4 + r: return "spawn"
	for l in Layout.LANDMARKS:
		if p.distance_to(l.pos) < 4.75 + r: return "landmark"
	var lane := (LANE_COLLIDER + r) if collides else LANE_DECOR
	if Layout.dist_to_trails(p) < lane: return "lane"
	for t in Layout.TREES:
		if collides and p.distance_to(Vector2(t[0], t[1])) < 1.9 + r: return "harvest"
	if collides:
		for b: Dictionary in blockers:
			if p.distance_to(Vector2(b.x, b.z)) < _min_gap(part.kind, r, b.kind, b.r): return "forest"
		for o in placed:
			if o.kind != "decor" and p.distance_to(o.at) < _min_gap(part.kind, r, o.kind, o.radius): return "self"
	else:
		for o in placed:
			if o.kind == "decor" and p.distance_to(o.at) < 0.45: return "self"
	return ""


# ───────────────────────── 월드 조립 ─────────────────────────

func build(world, variant := "") -> void:
	name = "YardHedges"
	_world = world
	variant_id = variant if variant != "" else variant_from_args()
	if not VARIANTS.has(variant_id): variant_id = "none"
	current_id = variant_id
	parts = parts_for(variant_id)
	for part in parts:
		var model := Nature.asset(part.asset)
		model.scale = part.scale
		model.rotation_degrees = part.rot
		model.set_meta("placement_role", "yard_hedge")
		model.set_meta("hedge_band", part.band)
		if part.kind == "decor":
			model.position = Vector3(part.at.x, 0, part.at.y)
			add_child(model)
			continue
		var body := StaticBody3D.new()
		body.name = "Hedge" + str(part.band).to_pascal_case() + ("Tree" if part.kind == "tree" else "Rock")
		body.position = Vector3(part.at.x, 0, part.at.y)
		body.collision_layer = Cfg.L_OBSTACLE
		body.collision_mask = 0
		body.set_meta("hedge_band", part.band)
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = part.radius
		cyl.height = 2.0 if part.kind == "tree" else clampf(part.height, Cfg.OBSTACLE_MIN_HEIGHT, 3.0)
		cs.shape = cyl
		cs.position.y = cyl.height * 0.5
		body.add_child(cs)
		body.add_child(model)
		world.nav_region.add_child(body)
		bodies.append(body)
		if part.kind == "tree" and part.height >= 3.0:
			var radius: float = part.canopy
			var occluder := {"bounds": AABB(Vector3(part.at.x - radius, 1.4, part.at.y - radius), Vector3(radius * 2, part.height - 1.4, radius * 2)),
				"meshes": model.find_children("*", "MeshInstance3D", true, false), "fade": 0.0}
			world.camera_occluders.append(occluder)
			_occluders.append(occluder)


## 다른 시안으로 다시 조립하고 내비메시를 다시 굽는다(F7). 표시 이름을 돌려준다.
func rebuild(variant: String) -> String:
	for b in bodies:
		if is_instance_valid(b): b.queue_free()
	bodies.clear()
	for o in _occluders: _world.camera_occluders.erase(o)
	_occluders.clear()
	for c in get_children(): c.queue_free()
	build(_world, variant)
	_world.bake_nav()
	return VARIANTS[variant_id].name


func next_variant() -> String:
	return ORDER[(ORDER.find(variant_id) + 1) % ORDER.size()]


func count(kind := "") -> int:
	var n := 0
	for p in parts:
		if kind == "" or p.kind == kind: n += 1
	return n
