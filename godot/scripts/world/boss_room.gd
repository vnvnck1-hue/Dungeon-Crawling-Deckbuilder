extends Node3D
## 니벨라 보스룸(맵 북쪽 가장자리 서리 둥지). 기준: art/concepts/monsters/nivella-boss-room-turnarounds-v01.
## - 지형: 청록 얼음 판석 바닥, 곡선 외곽 석재(입구만 열림), 뒤쪽 수정 절벽, 파손·쓰러진 기둥, 무너진 아치, 잔해·목재, 서리실 거미줄.
## - 보스: 정식 모델 전까지 서리 거미(spider_visual)를 BOSS_SCALE 배로 키운 임시 표시. 전투 판정은 아직 없다(표시·연출 전용).
## - 연출: 마녀가 방 안으로 들어서면 카메라가 물러나며 보스 쪽으로 시야를 연다 → 보스가 몸을 돌려 발견 → 포효(흔들림·서리 충격파·이름 배너).
## - 분위기: 다가갈수록 차가운 남청 조명·짙은 비네트·바닥 안개(post_grade boss_amount)가 섞이고, 포효 뒤에는 비네트가 박동한다.
const Sites := preload("res://scripts/world/hazard_sites.gd")
const Kit := preload("res://scripts/visual/boss_room_kit.gd")
const ToxicKit := preload("res://scripts/visual/toxic_kit.gd")
const SpiderVisual := preload("res://scripts/visual/spider_visual.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Cfg := preload("res://scripts/config.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const MIST := preload("res://shaders/toxic_mist.gdshader")
const RoarVfx := preload("res://scripts/visual/vfx/nivella_roar_vfx.gd")
const NivellaBoss := preload("res://scripts/actors/nivella_boss.gd")
const BossBar := preload("res://scripts/ui/boss_health_bar.gd")
const Web := preload("res://scripts/visual/vfx/nivella_web.gd")

const BOSS_SCALE := 8.5              # 서리 거미 기본 크기(1.45배) 위에 다시 곱한다
const BOSS_LOCAL := Vector3(-3.7, 0.0, -5.4)   # 둥지 중심 기준: 화면 위쪽(카메라 반대편) 안쪽
const BOSS_IDLE_YAW := -2.2          # 발견 전: 입구가 아니라 옆 벽을 보고 있다
const BOSS_RADIUS := 4.1             # 마녀가 통과하지 못하는 몸 충돌 반경
## 보스 뒤 반원의 높은 파손 기둥: [정규 x, 정규 z, 높이] — 거미줄 막이 덮어씌우고 보스 쪽으로 실을 건다
const PILLARS := [[-0.70, -0.46, 4.4], [0.38, -0.74, 5.0], [-0.30, -0.80, 4.6], [0.74, -0.42, 4.0], [-0.86, 0.02, 3.4]]
## 서리 알 무더기: [정규 x, 정규 z, [[앞뒤·옆 오프셋(m), 반지름, 높이], ...]]
const EGG_CLUSTERS := [
	[-0.52, -0.18, [[Vector2(0, 0), 1.5, 4.0], [Vector2(1.7, 1.4), 1.15, 3.0], [Vector2(-1.3, 1.7), 0.95, 2.4]]],
	[0.50, -0.45, [[Vector2(0, 0), 1.4, 3.6], [Vector2(1.6, -1.1), 1.0, 2.6]]],
	[0.20, -0.56, [[Vector2(0, 0), 1.7, 4.4]]],
]
const PROP_SCALE := 1.9              # 3면도 프랍 블록아웃 배율(둥지 크기에 맞춤)
const ENTER_AT := 0.92               # 정규 거리: 입구를 지나 이 안으로 들어오면 연출 시작
const LEAVE_AT := 1.12               # 이 밖으로 나가면 시야·분위기 원래대로
const FRAME_HEIGHT := 29.0           # 둥지 안 카메라 직교 높이: 둥지 전체(42×33m)가 화면을 거의 채운다
const FOCUS_PULL := 0.85             # 초점을 마녀 → 둥지 중심으로 당기는 비율
const NOTICE_DELAY := 0.55           # 들어선 뒤 보스가 고개를 돌리기까지
const TURN_TIME := 0.75
const RE_ROAR_COOLDOWN := 8.0
const ROAR_BLIZZARD_RADIUS := 14.0   # 다시 포효할 때 눈보라가 멈추는 반경(m) — 둥지(21×16m) 안쪽
## 첫 포효: 눈보라가 세 번 연달아(확! 확! 확!) 화면 끝까지 퍼진다. [시작 지연(초), 세기, 흔들림]
const FIRST_ROAR_WAVES := [[0.0, 0.8, 0.6], [0.34, 0.85, 0.7], [0.68, 0.95, 0.95]]
const FIRST_ROAR_RADIUS := 42.0      # 줌아웃 화면(높이 29) 모서리까지 닿는 반경
const FIRST_ROAR_SPREAD := 1.15
## 스크린 아래 방향(월드). Layout 주석: 화면 아래 1m = 월드 (0.574, 0.819)
const SCREEN_DOWN := Vector2(0.574, 0.819)

enum Phase { DORMANT, NOTICE, TURN, ROAR, WATCH, DEAD }

var world
var site: Dictionary
var radii: Vector2
var boss: Node3D                     # SpiderVisual
var boss_body: StaticBody3D
var combat                           # actors/nivella_boss.gd: 체력·공격 패턴
var hp_bar                           # ui/boss_health_bar.gd: 화면 위 가운데 체력바
var floor_mat: ShaderMaterial
var mist_mats: Array[ShaderMaterial] = []
var crystal_lights: Array[OmniLight3D] = []
var eye_light: OmniLight3D
var motes: CPUParticles3D
var influence := 0.0                 # 분위기(0 밖 ~ 1 안)
var framing := 0.0                   # 카메라 시야 열기(0~1)
var inside := false
var phase := Phase.DORMANT
var roars := 0                       # 검증용
var last_blizzard: Node3D            # 검증용: 마지막 포효 눈보라
var blizzards := 0                   # 검증용: 포효 눈보라 개수(내리찍기 제외)
var enters := 0                      # 검증용
var _phase_t := 0.0
var _clock := 0.0
var _flash := 0.0
var _beat := 0.0
var _last_roar_end := -100.0
var _yaw_from := 0.0
var _yaw_to := 0.0
var _peaked := false
var _slammed := false
var _sent := Vector3(-1, -1, -1)


func build(owner_world) -> void:
	world = owner_world
	name = "BossRoom"
	process_priority = 24   # 낮 시계(5)·카메라(10)·대기 원근(20) 다음, 독 지역과 같은 단계에서 그 위에 섞는다
	site = Sites.BOSS_ROOM
	radii = site.radii
	position = Vector3(site.center.x, 0.0, site.center.y)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61020
	_build_ground()
	var ice := Kit.ice_floor(radii * 1.02, rng)
	add_child(ice)
	floor_mat = ice.material_override
	var props := B.node(self, Vector3.ZERO, Vector3.ZERO, "Props")
	_build_rim(props, rng)
	_build_interior(props, rng)
	_build_webs(props)
	ToxicKit.fuse(props)
	_build_air(rng)
	_spawn_boss()


# ───────────────────────── 지형·프랍 ─────────────────────────

## 타원 매개변수 각 a 의 테두리 점(방 로컬, k = 정규 거리).
func _rim_point(a: float, k := 1.0) -> Vector3:
	return Vector3(cos(a) * radii.x * k, 0.0, sin(a) * radii.y * k)


## 정규 좌표(-1~1) → 방 로컬. 프랍 배치를 둥지 크기에 맞춰 늘리려고 쓴다.
func _at(nx: float, nz: float) -> Vector3:
	return Vector3(nx * radii.x, 0.0, nz * radii.y)


## 1 = 카메라 반대편(화면 위쪽 벽), -1 = 카메라 쪽.
func _backness(a: float) -> float:
	var d := Vector2(cos(a) * radii.x, sin(a) * radii.y).normalized()
	return -d.dot(SCREEN_DOWN)


func _in_entrance(a: float, pad := 0.0) -> bool:
	return absf(wrapf(a - float(site.entrance_angle), -PI, PI)) < float(site.entrance_half) + pad


func _place(props: Node3D, node: Node3D, at: Vector3, yaw: float, size := PROP_SCALE) -> Node3D:
	node.position = at
	node.rotation.y = yaw
	node.scale = Vector3.ONE * size
	props.add_child(node)
	return node


func _build_rim(props: Node3D, rng: RandomNumberGenerator) -> void:
	var n := 80
	for i in n:
		var a := TAU * (i + 0.5) / n
		if _in_entrance(a):
			continue
		var back := _backness(a)
		var at := _rim_point(a, 1.03)
		var tangent := Vector3(-sin(a) * radii.x, 0.0, cos(a) * radii.y).normalized()
		var yaw := atan2(tangent.x, tangent.z)
		# 카메라 쪽은 낮은 석재 턱(안이 보이게), 뒤쪽은 높은 석재 + 수정 절벽이 둥지를 감싼다
		var h := lerpf(0.7, 1.9, smoothstep(-0.3, 0.6, back)) * rng.randf_range(0.85, 1.2)
		_place(props, Kit.rim_block(Vector3(1.6, h, 2.0), rng), at, yaw, 1.0)
		_obstacle(at, 1.0, h)
		if back > 0.05:
			# 뒤쪽 벽: 큰 수정 절벽을 두 겹으로(바깥 겹이 맵 밖 빈 곳을 가린다)
			_place(props, Kit.crystal_cliff(rng, rng.randf_range(3.2, 5.0)), _rim_point(a, 1.13), yaw, rng.randf_range(1.6, 2.2))
			if i % 2 == 0:
				_place(props, Kit.crystal_cliff(rng, rng.randf_range(4.5, 6.5)), _rim_point(a, 1.3), yaw, rng.randf_range(2.0, 2.6))
		elif back > -0.45:
			if i % 2 == 0:
				_place(props, Kit.crystal_cliff(rng, rng.randf_range(2.2, 3.2)), _rim_point(a, 1.16), yaw, 1.4)
			if i % 3 == 1:
				_place(props, Kit.crystal_cluster(rng, rng.randf_range(0.9, 1.4)), _rim_point(a, 0.94), rng.randf() * TAU)
		elif i % 4 == 0:
			_place(props, Kit.rubble(rng, 5), _rim_point(a, 1.12), yaw, 1.3)
	# 입구 양옆 문기둥(부러진 기둥 한 쌍) — 카메라 쪽이라 낮게
	for s in [-1.0, 1.0]:
		var a: float = float(site.entrance_angle) + s * (float(site.entrance_half) + 0.05)
		var post := _place(props, Kit.pillar(rng, 2.0 if s < 0.0 else 1.4, true), _rim_point(a, 1.04), rng.randf() * TAU)
		_obstacle(post.position, 0.9, 2.0)


func _build_interior(props: Node3D, rng: RandomNumberGenerator) -> void:
	# 보스 뒤로 높은 파손 기둥들(거미줄을 거는 기둥): 둥지 뒤쪽 반원
	for spec in PILLARS:
		var p := _place(props, Kit.pillar(rng, spec[2], true), _at(spec[0], spec[1]), rng.randf_range(-0.3, 0.3))
		_obstacle(p.position, 0.62 * PROP_SCALE, spec[2])
	var arch := _place(props, Kit.ruined_arch(rng), _at(-0.78, 0.30), deg_to_rad(64.0))
	for x in [-1.5, 1.5]:
		_obstacle(arch.position + Basis(Vector3.UP, arch.rotation.y) * Vector3(x * PROP_SCALE, 0, 0), 0.62 * PROP_SCALE, 3.0)
	for spec in [[0.62, -0.08, 28.0], [-0.42, 0.42, -40.0], [0.30, 0.50, 75.0]]:
		var fallen := _place(props, Kit.fallen_pillar(rng), _at(spec[0], spec[1]), deg_to_rad(spec[2]))
		_obstacle(fallen.position, 0.75 * PROP_SCALE, 1.2)
	for spec in [[-0.46, -0.72, 1.5], [0.09, -0.86, 1.3], [0.70, -0.52, 1.2], [-0.86, -0.20, 1.1], [0.84, 0.18, 0.9],
			[-0.58, 0.64, 0.8], [0.40, 0.72, 0.7], [-0.18, -0.92, 1.4], [0.55, -0.80, 1.0], [-0.70, -0.58, 1.2],
			[-0.30, 0.20, 0.6], [0.20, -0.20, 0.7], [0.62, 0.42, 0.8], [-0.92, 0.40, 0.9]]:
		var c := _place(props, Kit.crystal_cluster(rng, spec[2]), _at(spec[0], spec[1]), rng.randf() * TAU)
		if spec[2] >= 0.9:
			_obstacle(c.position, 0.45 * spec[2] * PROP_SCALE, 1.6)
	for spec in [[-0.38, 0.55], [0.52, 0.48], [-0.66, -0.30], [0.20, -0.66], [0.70, -0.20], [-0.10, 0.38], [-0.80, 0.55], [0.05, 0.75]]:
		_place(props, Kit.rubble(rng, rng.randi_range(5, 8)), _at(spec[0], spec[1]), rng.randf() * TAU)
	for spec in [[-0.18, 0.66, 20.0], [0.80, 0.05, -50.0], [-0.55, 0.10, 70.0], [0.45, 0.25, 10.0]]:
		_place(props, Kit.timber(rng), _at(spec[0], spec[1]), deg_to_rad(spec[2]))


## 거미줄(레퍼런스: 알을 감싼 끈적한 막, 2026-10-23): 막이 기둥 꼭대기·알을 덮어씌우고 가닥으로 갈라져 땅에 박힌다.
## 모든 가닥은 보스 쪽으로 더 길게 뻗고, 기둥 끝에서 보스 발치로 팽팽한 실이 걸려 둥지 전체가 보스를 향해 흐른다.
func _build_webs(props: Node3D) -> void:
	var boss_at := Vector3(BOSS_LOCAL.x, 0.0, BOSS_LOCAL.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = 61077
	for spec in PILLARS:
		var base := _at(spec[0], spec[1])
		var top: float = spec[2] * PROP_SCALE
		var to := (boss_at - base).normalized()
		props.add_child(Web.make_shroud(base, 0.85, top * 1.04, 4.5, 8, rng.randf() * TAU, to, 1.3, 0.3))
		# 기둥 끝 → 보스 발치: 굵은 실 하나와 가는 실 둘(강약)
		for k in 3:
			var g := boss_at + (base - boss_at).normalized() * rng.randf_range(3.5, 6.0) 				+ to.cross(Vector3.UP) * rng.randf_range(-3.0, 3.0)
			props.add_child(Web.make_strand(base + Vector3.UP * top * 0.92, g, 0.7 if k == 0 else 0.38, k == 0))
	for cluster in EGG_CLUSTERS:
		var c := _at(cluster[0], cluster[1])
		for egg in cluster[2]:
			var off: Vector2 = egg[0]
			var base := c + Vector3(off.x, 0.0, off.y)
			var rx: float = egg[1]
			var h: float = egg[2]
			props.add_child(Web.make_egg(base, rx, h))
			props.add_child(Web.make_shroud(base, rx, h, rx * 1.9, 7, rng.randf() * TAU, (boss_at - base).normalized(), 0.8, 0.48))
			_obstacle(base, rx * 0.95, h)
	# 바닥에 퍼진 막
	for spec in [[0.30, 0.10, 3.0], [-0.35, 0.15, 2.6], [0.05, 0.55, 2.2], [-0.62, 0.42, 2.0]]:
		props.add_child(Web.make_splat(_at(spec[0], spec[1]), spec[2], 9))


## 둥지 바닥 충돌판: 별관 쪽은 원래 지면 충돌(±52m) 밖이라 따로 깐다.
## 둥지 뒤쪽은 눈 지면 메시(±60m)도 넘어가므로, 절벽 너머 빈 배경이 보이지 않게 어두운 눈 바닥을 넓게 깐다.
func _build_ground() -> void:
	var under := PlaneMesh.new()
	under.size = radii * 3.4
	var snow := B.mi(self, under, Vector3(0, -0.03, 0), Mats.solid(Color("5c5a8c"), {"noise_amount": .1, "noise_scale": .3, "sky_fill": .2}))
	snow.name = "NestBackdropGround"
	snow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	body.name = "NestGround"
	body.position = position + Vector3(0, -1.0, 0)
	body.collision_layer = Cfg.L_GROUND
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(radii.x * 2.3, 1.0, radii.y * 2.3)
	cs.shape = bs
	body.add_child(cs)
	world.nav_region.add_child(body)


func _obstacle(at_local: Vector3, radius: float, height: float) -> void:
	var body := StaticBody3D.new()
	body.name = "BossRoomCollision"
	body.set_meta("boss_room", true)
	body.position = position + Vector3(at_local.x, 0.0, at_local.z)
	body.collision_layer = Cfg.L_OBSTACLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = maxf(Cfg.OBSTACLE_MIN_HEIGHT, height)
	cs.shape = shape
	cs.position.y = shape.height * 0.5
	body.add_child(cs)
	world.nav_region.add_child(body)


# ───────────────────────── 공기(안개·서리 입자·빛) ─────────────────────────

func _build_air(rng: RandomNumberGenerator) -> void:
	for layer in 4:
		var mist := ShaderMaterial.new()
		mist.shader = MIST
		mist.set_shader_parameter("phase", rng.randf() * 20.0)
		mist.set_shader_parameter("mist_color", Color(0.62, 0.72, 1.0, [0.30, 0.20, 0.13, 0.08][layer]))
		mist_mats.append(mist)
		var plane := PlaneMesh.new()
		plane.size = radii * (2.6 - layer * 0.15)
		var m := B.mi(self, plane, Vector3(0, 0.18 + layer * 0.6, 0), mist)
		m.name = "FrostMist"
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 보스 발치에 고인 짙은 냉기
	var pool := ShaderMaterial.new()
	pool.shader = MIST
	pool.set_shader_parameter("phase", 3.3)
	pool.set_shader_parameter("mist_color", Color(0.78, 0.86, 1.0, 0.34))
	mist_mats.append(pool)
	var pool_plane := PlaneMesh.new()
	pool_plane.size = Vector2(17.0, 13.5)
	var pm := B.mi(self, pool_plane, BOSS_LOCAL + Vector3(0, 0.4, 0), pool)
	pm.name = "BossColdPool"
	pm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	motes = CPUParticles3D.new()
	motes.name = "FrostMotes"
	motes.amount = 300
	motes.lifetime = 8.0
	motes.preprocess = 8.0
	motes.local_coords = true
	motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	motes.emission_box_extents = Vector3(radii.x, 0.5, radii.y)
	motes.direction = Vector3(0.2, 1, -0.1)
	motes.spread = 25.0
	motes.gravity = Vector3(0.03, 0.05, 0)
	motes.initial_velocity_min = 0.1
	motes.initial_velocity_max = 0.35
	motes.scale_amount_min = 0.6
	motes.scale_amount_max = 1.5
	motes.color = Color(0.72, 0.84, 1.0, 0.8)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.2, Color.WHITE)
	g.add_point(0.75, Color(1, 1, 1, 0.7))
	g.set_color(1, Color(1, 1, 1, 0))
	motes.color_ramp = g
	var q := QuadMesh.new()
	q.size = Vector2(0.09, 0.09)
	q.material = Mats.particle(Color.WHITE, true)
	motes.mesh = q
	motes.seed = rng.randi()
	add_child(motes)
	for p in [[-0.46, -0.72], [0.09, -0.86], [0.70, -0.52], [-0.86, -0.20], [0.84, 0.18], [-0.58, 0.64], [0.40, 0.72], [-0.18, -0.92]]:
		var l := B.omni(self, _at(p[0], p[1]) + Vector3(0, 1.6, 0), Color("6f8cff"), 0.9, 8.0, false, 1.4)
		l.set_meta("phase", rng.randf() * TAU)
		crystal_lights.append(l)


func _spawn_boss() -> void:
	boss = SpiderVisual.new()
	boss.name = "NivellaStandIn"
	boss.scale *= BOSS_SCALE
	boss.position = BOSS_LOCAL
	boss.rotation.y = BOSS_IDLE_YAW
	add_child(boss)
	eye_light = B.omni(boss, Vector3(0, 0.35, 0.35), Color("8fb4ff"), 0.0, 3.0, false, 1.2)
	# 어두운 몸이 밤 배경에 묻히지 않게: 뒤 위에서 차가운 테두리빛, 앞 위에서 약한 채움빛
	B.omni(self, BOSS_LOCAL + Vector3(-1.2, 8.5, -5.5), Color("9fb8ff"), 2.8, 16.0, false, 1.1).name = "BossRimLight"
	B.omni(self, BOSS_LOCAL + Vector3(3.2, 6.5, 6.5), Color("c4d2ff"), 1.2, 14.0, false, 1.3).name = "BossFillLight"
	boss_body = StaticBody3D.new()
	boss_body.name = "NivellaBodyCollision"
	boss_body.position = position + BOSS_LOCAL
	# 이동만 막고 시야는 막지 않는 층: 마녀의 평타·번개가 보스 자신의 몸에 가려 '시야 없음'이 되지 않게
	boss_body.collision_layer = Cfg.L_BOUNDARY
	boss_body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = BOSS_RADIUS
	shape.height = 4.2
	cs.shape = shape
	cs.position.y = 2.1
	boss_body.add_child(cs)
	world.nav_region.add_child(boss_body)
	combat = NivellaBoss.new()
	combat.position = BOSS_LOCAL
	add_child(combat)
	combat.setup(self, world.game, boss, BOSS_RADIUS)
	combat.died.connect(_on_boss_died)
	combat.stock_broken.connect(func(_left): pulse_flash(1.0))
	hp_bar = BossBar.new()
	add_child(hp_bar)
	hp_bar.bind(world.game, combat)


# ───────────────────────── 매 프레임 ─────────────────────────

func normalized_distance_of(p: Vector3) -> float:
	return Sites.normalized_distance(Vector2(p.x, p.z), site)


func _process(delta: float) -> void:
	if world == null or world.game.player == null or not is_instance_valid(world.game.player):
		return
	_clock += delta
	var player: Vector3 = world.game.player.global_position
	var nd := normalized_distance_of(player)
	if not inside and nd < ENTER_AT:
		_enter()
	elif inside and nd > LEAVE_AT:
		_leave()
	_tick_phase(delta, player)
	# 분위기: 다가오면서부터 서서히, 안에서는 끝까지
	var wanted := 1.0 if inside else 1.0 - smoothstep(0.85, 1.7, nd)
	influence = move_toward(influence, wanted, delta * (0.7 if wanted > influence else 0.45))
	framing = move_toward(framing, 1.0 if inside else 0.0, delta / (1.5 if inside else 1.1))
	_apply_camera(player)
	_apply_grade(delta)
	_animate_air()


func _enter() -> void:
	inside = true
	enters += 1
	Sfx.play(self, "night_warn")
	world.game.toast(str(site.label), Color("bcd0ff"))
	if combat.dead:
		return
	if roars > 0:
		hp_bar.show_bar()
	if phase in [Phase.DORMANT, Phase.WATCH] and _clock - _last_roar_end > RE_ROAR_COOLDOWN:
		_set_phase(Phase.NOTICE)
	elif phase == Phase.DORMANT:
		_set_phase(Phase.WATCH)   # 막 포효한 뒤 다시 들어오면 소리 없이 노려보기만


func _leave() -> void:
	inside = false
	combat.pause_fight()
	hp_bar.leave()
	if phase == Phase.WATCH:
		_set_phase(Phase.DORMANT)


## 보스 BGM(sound_bank bgm_boss): 둥지 안에서 등장 연출(알아챔)이 시작된 뒤부터 보스가 살아 있는 동안.
func wants_music() -> bool:
	return inside and combat != null and not combat.dead and phase != Phase.DORMANT


func _set_phase(p: Phase) -> void:
	phase = p
	_phase_t = 0.0


func _tick_phase(delta: float, player: Vector3) -> void:
	_phase_t += delta
	var to_player := player - boss.global_position
	var face := atan2(to_player.x, to_player.z)   # 모델은 +Z 를 본다
	match phase:
		Phase.DORMANT:
			boss.rotation.y = lerp_angle(boss.rotation.y, BOSS_IDLE_YAW, clampf(delta * 1.2, 0.0, 1.0))
			eye_light.light_energy = move_toward(eye_light.light_energy, 0.0, delta)
		Phase.NOTICE:
			# 멈칫: 다리를 고쳐 딛고 눈빛이 켜진다
			eye_light.light_energy = move_toward(eye_light.light_energy, 1.6, delta * 3.0)
			if _phase_t >= NOTICE_DELAY:
				_yaw_from = boss.rotation.y
				_yaw_to = face
				_set_phase(Phase.TURN)
		Phase.TURN:
			var u := clampf(_phase_t / TURN_TIME, 0.0, 1.0)
			boss.rotation.y = lerp_angle(_yaw_from, _yaw_to, u * u * (3.0 - 2.0 * u))
			if u >= 1.0:
				boss.roar()
				roars += 1
				_peaked = false
				_slammed = false
				_set_phase(Phase.ROAR)
		Phase.ROAR:
			boss.rotation.y = lerp_angle(boss.rotation.y, face, clampf(delta * 1.5, 0.0, 1.0))
			if not _peaked and _phase_t >= SpiderVisual.ROAR_PEAK:
				_peaked = true
				_roar_peak()
			if not _slammed and _phase_t >= SpiderVisual.ROAR_SLAM:
				_slammed = true
				_roar_slam()
			if not boss.is_roaring():
				_last_roar_end = _clock
				_set_phase(Phase.WATCH)
		Phase.WATCH:
			# 마녀를 계속 노려보며 싸운다(패턴·판정은 combat)
			boss.rotation.y = lerp_angle(boss.rotation.y, face, clampf(delta * (3.0 if combat.active else 2.0), 0.0, 1.0))
			eye_light.light_energy = 1.1 + sin(_clock * 3.0) * 0.25
			if inside and not combat.dead and not combat.active:
				combat.start_fight()
		Phase.DEAD:
			eye_light.light_energy = move_toward(eye_light.light_energy, 0.0, delta * 2.0)


func _roar_peak() -> void:
	Sfx.play(self, "boss_roar")
	Sfx.play(self, "frost_burst")
	world.shake(0.8, 1.4)
	_flash = 1.0
	_beat = 1.0
	var head: Vector3 = boss.global_position + Vector3(0, 2.6, 0) + boss.global_basis.z.normalized() * 2.0
	Fx.burst(world, head, Color(0.78, 0.88, 1.0), 60, 9.0)
	# 포효 눈보라: 보스 둘레로 눈 띠·눈보라 벽·파편이 확 퍼진다(VisualShader).
	if roars == 1:
		for wave in FIRST_ROAR_WAVES:
			if wave[0] <= 0.0:
				_blizzard_wave(wave[1], wave[2])
			else:
				get_tree().create_timer(wave[0], false).timeout.connect(_blizzard_wave.bind(wave[1], wave[2]))
	else:
		blizzards += 1
		last_blizzard = RoarVfx.burst(world, boss.global_position, ROAR_BLIZZARD_RADIUS, 0.8)
	if world.game.get("banner") != null:
		world.game.banner.show_card("boss", "니벨라", "서리 둥지의 여왕", "", 1.6, Color("bcd0ff"))
	# 등장 배너와 함께 화면 위 체력바가 펼쳐지며 차오른다(처음 한 번), 다시 포효할 때는 그냥 보인다
	if roars == 1:
		hp_bar.intro()
	else:
		hp_bar.show_bar()


## 첫 포효의 눈보라 한 번: 화면 끝까지 퍼지고, 칠 때마다 흔들림·섬광·서리 폭발음이 겹친다.
func _blizzard_wave(strength: float, shake: float) -> void:
	if not is_inside_tree():
		return
	blizzards += 1
	last_blizzard = RoarVfx.burst(world, boss.global_position, FIRST_ROAR_RADIUS, strength, FIRST_ROAR_SPREAD)
	world.shake(shake, 0.5)
	_flash = maxf(_flash, 0.5 + shake * 0.5)
	_beat = 1.0
	Sfx.play(self, "frost_burst")


func _roar_slam() -> void:
	Sfx.play(self, "mon_big")
	world.shake(0.3, 0.35)
	_flash = maxf(_flash, 0.45)
	for id in ["L1", "R1"]:
		var tip: Vector3 = boss.leg_tip_world(SpiderVisual.LEG_ORDER.find(id))
		Fx.snow_kick(Vector3(tip.x, 0.05, tip.z), boss.global_basis.z.normalized(), 8, 4.0)
	# 앞다리를 내리찍을 때 작은 눈보라가 한 번 더
	RoarVfx.burst(world, boss.global_position + boss.global_basis.z.normalized() * 3.0, 6.5, 0.5)


## 보스 전투 쪽에서 화면 섬광을 한 번 더 줄 때(단 파괴·눈보라 폭발).
func pulse_flash(amount: float) -> void:
	_flash = maxf(_flash, amount)
	_beat = 1.0


func _on_boss_died() -> void:
	_set_phase(Phase.DEAD)
	pulse_flash(1.0)


func _apply_camera(_player: Vector3) -> void:
	var cam = world.player_camera
	if cam == null:
		return
	var k := framing * framing * (3.0 - 2.0 * framing)
	cam.framing_extra = maxf(FRAME_HEIGHT - cam.desired_height, 0.0) * k
	cam.framing_point = global_position + Vector3(BOSS_LOCAL.x, 0.0, BOSS_LOCAL.z) * 0.6
	cam.framing_weight = FOCUS_PULL * k


func _apply_grade(delta: float) -> void:
	_flash = move_toward(_flash, 0.0, delta * 1.6)
	# 포효 뒤에는 방 안에 있는 동안 심장 박동처럼 비네트가 조인다(두 번 뛰고 쉼)
	var beat := 0.0
	if inside and phase in [Phase.ROAR, Phase.WATCH] and not combat.dead:
		var t := fmod(_clock, 1.25)
		beat = exp(-t * 9.0) + exp(-maxf(t - 0.22, 0.0) * 9.0) * (0.7 if t > 0.22 else 0.0)
	_beat = lerpf(_beat, beat, clampf(delta * 12.0, 0.0, 1.0))
	var send := Vector3(influence * 0.9, _flash, _beat * influence)
	if not send.is_equal_approx(_sent):
		_sent = send
		world.post_mat.set_shader_parameter("boss_amount", send.x)
		world.post_mat.set_shader_parameter("boss_flash", send.y)
		world.post_mat.set_shader_parameter("boss_beat", send.z)
	floor_mat.set_shader_parameter("pulse", _flash)
	if influence > 0.0:
		var env: Environment = world.env
		env.ambient_light_color = env.ambient_light_color.lerp(Color("3d4c94"), influence * 0.75)
		env.ambient_light_energy = lerpf(env.ambient_light_energy, 0.34, influence * 0.8)
		world.sun.light_color = world.sun.light_color.lerp(Color("90a6ff"), influence * 0.85)
		world.sun.light_energy = lerpf(world.sun.light_energy, 0.46, influence * 0.85)
		env.glow_intensity = lerpf(env.glow_intensity, 0.8, influence)
		env.fog_light_color = env.fog_light_color.lerp(Color("2a3266"), influence * 0.8)


func _animate_air() -> void:
	Web.tick(get_process_delta_time())
	for l in crystal_lights:
		var ph: float = l.get_meta("phase")
		l.light_energy = (0.55 + sin(_clock * 0.9 + ph) * 0.2) * (0.4 + influence * 0.6) + _flash * 1.4
	motes.speed_scale = 1.0 + _flash * 3.0
