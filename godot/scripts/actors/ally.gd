extends CharacterBody3D
## 카드로 소환한 아군. 직업 분화 v1(docs/mercenary-jobs-design.md):
##  - 나무꾼(lumberjack): 지정 나무를 끝까지 벌목하고 목재를 들고 있다가 마녀가 오면 건넨다. 밤에는 산장 안으로 대피.
##  - 사냥꾼(hunter): 낮에는 토끼·사슴을 활로 사냥해 고기·가죽을 모은다. 적이 오면 원거리 사격, 없으면 산장 주변 정찰.
##  - 전투용병(warrior): 산장 주변을 정찰하다 적이 보이면 근접 전투. 산장이 공격받으면 공격자를 먼저 찾아간다.
##  - 채집가(gatherer): 낮에 랜드마크를 돌며 자원을 줍고 저녁 전에 돌아온다. 밤에는 산장 안으로 대피.
##  - 하수인(minion, 큰 숲의 괴물): 소환 자리 주변의 적과 싸우고, 쓰러지거나 낮이 되면 시들어 목재 1개가 된다.
## 용병은 체력이 0이 되어 쓰러지기 전까지 산장에 남는다. 쓰러지면 산장 뒤편에 무덤이 생기고 들고 있던 자원은 사라진다.

const Cfg := preload("res://scripts/config.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const SoftSep := preload("res://scripts/actors/soft_separation.gd")
const Layout := preload("res://scripts/world/layout.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const Models := preload("res://scripts/visual/models.gd")
const CharacterModels := preload("res://scripts/visual/character_models.gd")
const RigAnim := preload("res://scripts/visual/rig_anim.gd")
## 도끼질 한 번(들어 올림 → 내리찍음 → 뽑기) 주기(초).
const CHOP_PERIOD := 1.05
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const ArrowScript := preload("res://scripts/actors/arrow.gd")

const SessionScript := preload("res://scripts/game/game_session.gd")

## TOWER_GO·TOWER_POST: 밤에 사냥꾼이 빈자리가 있는 감시탑으로 가서 올라간다(world/watchtower.gd). 새벽에 내려온다.
## ESCORT: 낮에 마녀가 산장을 벗어나면 전투직이 따라나와 곁에 붙어 다닌다(docs/merc-escort-v01.md).
enum State { GO_WORK, WORKING, PATROL, PATROL_WAIT, ENGAGE, HUNT, GATHER_OUT, GATHER_PICK, GATHER_RETURN, IDLE, GO_HIDE, HIDDEN, GUARD, DEAD, TOWER_GO, TOWER_POST, ESCORT }

## 동행 중(ESCORT 와 그 사이의 교전·사냥 포함): 적·사냥감을 산장이 아니라 마녀 기준으로 찾는다.
var escort := false
var _escort_far_t := 0.0      # 마녀와 ESCORT_WARP_DIST 밖으로 떨어진 채 지난 시간
var _witch_still_t := 0.0     # 마녀가 제자리에 서 있는 시간
var _witch_prev := Vector3.INF
var _sprint := 1.0            # 동행 따라잡기 속도 배율(마녀와의 거리에 비례, 1 = 걷기)
var tower = null              # 맡은 감시탑(올라가는 중 포함)
var on_tower := false         # 발판 위에 있음: 괴물의 표적이 아니고 움직이지 않는다
var game
var kind := "merc"            # merc | minion
var job := "warrior"          # lumberjack | hunter | warrior | gatherer | minion
var person := ""
var task := "guard"           # 호환용 요약: chop | guard | gather | idle
var state := State.PATROL
var hp := Cfg.MERC_HP
var max_hp := Cfg.MERC_HP
var dead := false
var hidden := false
var hp_offset := 1.75
var tree = null               # 벌목 대상(world.harvest_trees의 항목)
var work_pos := Vector3.ZERO
var progress := 0.0
var guard_point := Vector3.ZERO
var priority = null           # 우선 공격 대상(카드로 지정한 적·산장 공격자)
var target = null             # 현재 교전 대상
var prey = null               # 사냥 대상(야생 동물)
var attack_cd := 0.0
var carry: Dictionary = {}    # 들고 있는 자원 {card_id: 수량}
var gear: Dictionary = {}     # 장착 장비 {slot: {uid, id}} — 수치는 game.equipment가 합산한다
var patrol_point := Vector3.ZERO
var patrol_wait := 0.0
var gather_stops: Array = []
var gather_index := 0
var gather_timer := 0.0
var hide_on_arrive := false
var agent: NavigationAgent3D
var visual: Node3D
var body: Node3D
var _anim_t := 0.0
## 용병: 그 인물의 3D 모델(전용 → 종족 공용) 팔다리 애니메이터. 하수인은 null.
var rig: Node
var _lunge_t := 0.0
var _leaf_t := 0.0
var _repath_t := 0.0
var _stuck_t := 0.0          # 움직이려는데 제자리면 누적(구석·막힌 목적지 감시)
var _stuck_ref := Vector3.ZERO
var failed_tree = null       # 가다가 막힌 나무(다음 배정에서 제외)
var _handover_cd := 0.0
var _bow: Node3D
## 동작의 임팩트 순간을 기다리는 공격 {kind: slash|shot, target, dmg, t(남은 초)}.
var _pending: Dictionary = {}
var _chop_u := 0.0
var _rng := RandomNumberGenerator.new()


var card_uid := -1   # 이 활동을 시작한 카드(활동이 끝나면 버림패로)


func setup(g, ally_kind: String, ally_person: String, ally_job: String, pos: Vector3) -> void:
	game = g
	kind = ally_kind
	person = ally_person
	job = ally_job if ally_kind == "merc" else "minion"
	guard_point = pos
	_rng.randomize()
	if kind == "minion":
		hp = Cfg.MINION_HP
		max_hp = Cfg.MINION_HP
		hp_offset = 1.95
		state = State.GUARD
		task = "guard"
	else:
		max_hp = float(Cfg.JOB_HP.get(job, Cfg.MERC_HP))
		hp = max_hp
		match job:
			"lumberjack":
				task = "chop"
				state = State.GO_WORK
			"gatherer":
				task = "gather"
				state = State.IDLE
			_:
				task = "guard"
				state = State.PATROL


func _ready() -> void:
	collision_layer = 0
	collision_mask = Cfg.L_OBSTACLE | Cfg.L_BOUNDARY
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.1
	cs.shape = cap
	cs.position.y = 0.55
	add_child(cs)
	agent = NavigationAgent3D.new()
	agent.radius = 0.4
	agent.path_desired_distance = 0.35
	agent.target_desired_distance = 0.2
	add_child(agent)
	if kind == "minion":
		visual = Models.make_big_monster()
	else:
		# 고용된 인물은 손님 때와 같은 모델(전용 → 종족 공용)로 나온다. 예전 겨울 여행자 모델은 쓰지 않는다.
		var made := CharacterModels.make(CharacterModels.model_for_person(person))
		visual = made.root
		rig = made.anim
		visual.set_meta("model_id", CharacterModels.model_for_person(person))
	body = visual.get_node("Body")
	add_child(visual)
	add_to_group("readable_characters")   # F10 캐릭터 분리 시험(visual/character_readability.gd)
	if kind == "merc":
		_add_job_props()
	# 아군 표식: 발밑의 따뜻한 고리(적과 구분). 직업별 색.
	var ring_col := Color(0.55, 1.0, 0.65, 0.75)
	if kind == "merc":
		ring_col = {"lumberjack": Color(1.0, 0.82, 0.45, 0.75), "hunter": Color(0.6, 0.95, 0.75, 0.75),
			"warrior": Color(1.0, 0.6, 0.5, 0.75), "gatherer": Color(0.8, 0.75, 1.0, 0.75)}.get(job, Color(1.0, 0.82, 0.45, 0.75))
	var ring := B.torus(self, 0.36, 0.46, Vector3(0, 0.04, 0), Mats.unshaded_shared(ring_col, true, true))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.15, 1.0)
	add_to_group("allies")
	SoftSep.register(self, 0.32 if kind != "minion" else 0.38)
	add_to_group("show_hp")
	_anim_t = randf() * 10.0
	if kind == "merc" and game.get("race_cards") != null:
		game.race_cards.on_ally_spawned(self)  # 영구 강화·그 밤의 흑맥주
	Fx.summon(global_position, Color(0.55, 1.0, 0.6) if kind == "minion" else Color(1.0, 0.82, 0.45))
	Sfx.play(self, "minion_spawn" if kind == "minion" else "merc_spawn")
	if job == "gatherer":
		game.contracts.plan_gathering(self)


## 직업 소품: 나무꾼 도끼 / 사냥꾼 활·화살통 / 전투용병 검·방패 / 채집가 바구니.
## 파츠 모델(rig 있음)은 도구를 손에 쥐이고 등짐은 몸통 등에 붙여 팔·몸과 함께 움직인다(_add_held_props).
func _add_job_props() -> void:
	if rig != null and body.get_child_count() > 0 and _add_held_props(body.get_child(0)):
		return
	match job:
		"lumberjack":
			var grip := B.node(body, Vector3(0.26, 0.42, 0.06), Vector3(0, 0, -20), "Axe")
			B.cyl(grip, 0.025, 0.03, 0.62, Vector3(0, 0.2, 0), Mats.solid(Color("6b4a2c")), 6)
			B.box(grip, Vector3(0.05, 0.16, 0.2), Vector3(0, 0.46, 0.08), Mats.solid(Color("aeb4c4")))
		"hunter":
			_bow = B.node(body, Vector3(-0.24, 0.5, 0.14), Vector3(0, 0, 0), "Bow")
			var wood := Mats.solid(Color("7a4f2a"))
			for seg in [[Vector3(0, 0.22, 0.05), Vector3(28, 0, 0)], [Vector3(0, 0, 0.11), Vector3(0, 0, 0)], [Vector3(0, -0.22, 0.05), Vector3(-28, 0, 0)]]:
				B.cyl(_bow, 0.016, 0.02, 0.24, seg[0], wood, 6, seg[1])
			B.box(_bow, Vector3(0.006, 0.6, 0.006), Vector3(0, 0, -0.02), Mats.solid(Color("e8e2d0")))
			var quiver := B.node(body, Vector3(-0.12, 0.46, -0.24), Vector3(15, 0, 20), "Quiver")
			B.cyl(quiver, 0.05, 0.06, 0.34, Vector3.ZERO, Mats.solid(Color("5c3a22")), 8)
			for i in 3:
				B.cyl(quiver, 0.006, 0.006, 0.22, Vector3(-0.02 + 0.02 * i, 0.26, 0.015 * (i - 1)), Mats.solid(Color("d8d2c0")), 4)
		"warrior":
			var hilt := B.node(body, Vector3(0.26, 0.4, 0.1), Vector3(-10, 0, -15), "Sword")
			B.cyl(hilt, 0.018, 0.02, 0.14, Vector3(0, 0.0, 0), Mats.solid(Color("5c3a22")), 6)
			B.box(hilt, Vector3(0.14, 0.03, 0.03), Vector3(0, 0.08, 0), Mats.solid(Color("8e8a80")))
			B.box(hilt, Vector3(0.05, 0.5, 0.012), Vector3(0, 0.34, 0), Mats.solid(Color("c8ccd8")))
			var shield := B.node(body, Vector3(-0.27, 0.42, 0.05), Vector3(0, 90, 0), "Shield")
			B.cyl(shield, 0.2, 0.2, 0.03, Vector3.ZERO, Mats.solid(Color("7b4a2e")), 12, Vector3(90, 0, 0))
			B.sphere(shield, 0.05, Vector3(0, 0, 0.03), Mats.solid(Color("aeb4c4")), Vector3(1, 1, 0.5), 8, 4)
		"gatherer":
			var basket := B.node(body, Vector3(0, 0.44, -0.3), Vector3(0, 0, 0), "Basket")
			B.cyl(basket, 0.17, 0.13, 0.26, Vector3.ZERO, Mats.solid(Color("b48a4e")), 10)
			B.torus(basket, 0.15, 0.18, Vector3(0, 0.13, 0), Mats.solid(Color("8a6230")))
			B.sphere(basket, 0.06, Vector3(0.04, 0.16, 0.02), Mats.solid(Color("b8443a")), Vector3.ONE, 6, 3)
			B.sphere(basket, 0.05, Vector3(-0.05, 0.15, -0.03), Mats.solid(Color("8fb36a")), Vector3.ONE, 6, 3)


## 손에 쥔 도구. 손 자리(CharacterModels._hand: 팔 묶음 아래 바깥 끝) 아래에 붙고, 모델 배율을 되돌려 세계 크기를 유지한다.
## 팔이 내려가 있을 때 도끼·검은 손에서 앞-아래로 뻗어(팔을 앞으로 휘두르면 그대로 대상에 꽂힘), 도끼날은 휘두르는 쪽을 향한다.
## 활은 rig 이 팔 각도와 상관없이 세로로 세우고, 시위(bow_string)·화살(arrow)은 rig 이 당김에 맞춰 움직인다.
func _add_held_props(model: Node3D) -> bool:
	var hand_r := CharacterModels._hand(model, "arm_r")
	var hand_l := CharacterModels._hand(model, "arm_l")
	var torso: Node3D = null
	for n in model.find_children("*", "Node3D", true, false):
		if str(n.get_meta("part_group", "")) == "torso": torso = n
	if hand_r == null or hand_l == null or torso == null:
		return false
	var inv := Vector3.ONE / model.scale.x
	var back_box: AABB = (torso.get_node("Mesh") as MeshInstance3D).mesh.get_aabb()
	var back := Vector3(0, back_box.get_center().y + back_box.size.y * 0.1, back_box.position.z)
	match job:
		"lumberjack":
			var axe := B.node(hand_r, Vector3.ZERO, Vector3(155, 0, 0), "Axe")
			axe.scale = inv
			B.cyl(axe, 0.025, 0.03, 0.66, Vector3(0, 0.24, 0), Mats.solid(Color("6b4a2c")), 6)
			B.box(axe, Vector3(0.05, 0.17, 0.22), Vector3(0, 0.5, 0.09), Mats.solid(Color("aeb4c4")))
			B.box(axe, Vector3(0.055, 0.04, 0.05), Vector3(0, 0.5, -0.03), Mats.solid(Color("4a4e58")))
			rig.props["axe"] = axe
		"hunter":
			var bow := B.node(hand_l, Vector3(0, 0, 0.02), Vector3.ZERO, "Bow")
			bow.scale = inv
			var wood := Mats.solid(Color("7a4f2a"))
			for seg in [[Vector3(0, 0.24, 0.05), Vector3(28, 0, 0)], [Vector3(0, 0, 0.1), Vector3(0, 0, 0)], [Vector3(0, -0.24, 0.05), Vector3(-28, 0, 0)]]:
				B.cyl(bow, 0.016, 0.02, 0.26, seg[0], wood, 6, seg[1])
			var string := B.node(bow, Vector3(0, 0, -0.01), Vector3.ZERO, "BowString")
			string.set_meta("rest_z", -0.01)
			string.set_meta("pull", 0.2)
			B.box(string, Vector3(0.006, 0.62, 0.006), Vector3.ZERO, Mats.solid(Color("e8e2d0")))
			var arrow := B.node(bow, Vector3(0, 0, -0.12), Vector3(90, 0, 0), "Arrow")
			B.cyl(arrow, 0.007, 0.007, 0.6, Vector3(0, 0.12, 0), Mats.solid(Color("d8d2c0")), 4)
			B.cyl(arrow, 0.0, 0.02, 0.06, Vector3(0, 0.44, 0), Mats.solid(Color("8e939e")), 4)
			arrow.visible = false
			var quiver := B.node(torso, back + Vector3(0.06, 0.02, -0.03), Vector3(15, 0, 20), "Quiver")
			quiver.scale = inv
			B.cyl(quiver, 0.05, 0.06, 0.34, Vector3.ZERO, Mats.solid(Color("5c3a22")), 8)
			for i in 3:
				B.cyl(quiver, 0.006, 0.006, 0.22, Vector3(-0.02 + 0.02 * i, 0.26, 0.015 * (i - 1)), Mats.solid(Color("d8d2c0")), 4)
			_bow = bow
			rig.props["bow"] = bow
			rig.props["bow_string"] = string
			rig.props["arrow"] = arrow
		"warrior":
			var sword := B.node(hand_r, Vector3.ZERO, Vector3(105, 0, 0), "Sword")
			sword.scale = inv
			B.cyl(sword, 0.018, 0.02, 0.14, Vector3(0, 0.0, 0), Mats.solid(Color("5c3a22")), 6)
			B.box(sword, Vector3(0.16, 0.03, 0.035), Vector3(0, 0.08, 0), Mats.solid(Color("8e8a80")))
			B.box(sword, Vector3(0.06, 0.44, 0.016), Vector3(0, 0.31, 0), Mats.solid(Color("c8ccd8")))
			var shield := B.node(hand_l, Vector3(0.05, 0.12, 0.0) / model.scale.x, Vector3(0, 0, 0), "Shield")
			shield.scale = inv
			B.cyl(shield, 0.2, 0.2, 0.035, Vector3.ZERO, Mats.solid(Color("7b4a2e")), 12, Vector3(0, 0, 90))
			B.sphere(shield, 0.05, Vector3(0.03, 0, 0), Mats.solid(Color("aeb4c4")), Vector3(0.5, 1, 1), 8, 4)
			rig.props["sword"] = sword
			rig.props["shield"] = shield
		"gatherer":
			var basket := B.node(torso, back + Vector3(0, 0, -0.08), Vector3(-8, 0, 0), "Basket")
			basket.scale = inv
			B.cyl(basket, 0.17, 0.13, 0.26, Vector3.ZERO, Mats.solid(Color("b48a4e")), 10)
			B.torus(basket, 0.15, 0.18, Vector3(0, 0.13, 0), Mats.solid(Color("8a6230")))
			B.sphere(basket, 0.06, Vector3(0.04, 0.16, 0.02), Mats.solid(Color("b8443a")), Vector3.ONE, 6, 3)
			B.sphere(basket, 0.05, Vector3(-0.05, 0.15, -0.03), Mats.solid(Color("8fb36a")), Vector3.ONE, 6, 3)
			rig.props["basket"] = basket
	return true


# ───────────────────────── 명령(ContractDirector가 호출) ─────────────────────────

func set_chop(t, pos: Vector3) -> void:
	tree = t
	work_pos = pos
	task = "chop"
	progress = 0.0
	state = State.GO_WORK


## 임무 없음: 산장 마당의 대기 자리로 걸어가 기다린다.
func become_idle(spot: Vector3) -> void:
	if dead:
		return
	tree = null
	priority = null
	target = null
	prey = null
	guard_point = spot
	state = State.IDLE


## 채집 경로 지정(출발).
func set_gathering(stops: Array) -> void:
	if dead or stops.is_empty():
		return
	gather_stops = stops
	gather_index = 0
	gather_timer = 0.0
	task = "gather"
	state = State.GATHER_OUT


## 채집 중단·귀환(저녁이 가깝거나 웨이브 시작).
func return_home(hide_after: bool) -> void:
	if dead or state == State.HIDDEN or state == State.GO_HIDE:
		return
	hide_on_arrive = hide_after
	guard_point = game.contracts.yard_spot(self)
	state = State.GATHER_RETURN


func is_combat_job() -> bool:
	return job == "hunter" or job == "warrior" or kind == "minion"


func is_noncombat_job() -> bool:
	return job == "lumberjack" or job == "gatherer"


## 일몰(웨이브 시작): 비전투직은 산장 안으로 대피, 전투직은 계속 정찰·교전, 하수인은 그대로.
func interrupt() -> void:
	if dead:
		return
	if is_noncombat_job():
		if state == State.GATHER_OUT or state == State.GATHER_PICK:
			return_home(true)
		else:
			_go_hide()
	elif kind == "merc":
		prey = null
		escort = false   # 낮에만 동행: 일몰이면 산장으로 돌아가 정찰한다
		if state == State.IDLE or state == State.HUNT or state == State.ESCORT:
			state = State.PATROL
			_pick_patrol_point()


## 새벽(준비 시작): 대피했던 용병이 나오고, 각 직업이 낮 일을 다시 시작한다.
func resume() -> void:
	if dead:
		return
	if tower != null:
		leave_tower()
	if state == State.HIDDEN or state == State.GO_HIDE:
		_unhide()
	hide_on_arrive = false
	match job:
		"lumberjack":
			if tree != null and not tree.get("removed", false) and tree["remaining"] > 0:
				state = State.GO_WORK
			else:
				become_idle(game.contracts.yard_spot(self))
		"gatherer":
			become_idle(game.contracts.yard_spot(self))
			game.contracts.plan_gathering(self)
		"hunter", "warrior":
			if state != State.ENGAGE:
				state = State.PATROL
				_pick_patrol_point()


## 밤의 적이 모두 정리됨: 하수인은 시들어 목재가 되고, 전투직은 정찰을 계속한다.
func end_combat(_spot: Vector3) -> void:
	if dead:
		return
	if kind == "minion":
		game.contracts.wither_minion(self, "낮이 밝아")
		return
	if is_combat_job() and state == State.ENGAGE:
		target = null
		priority = null
		state = State.PATROL
		_pick_patrol_point()


func status_text() -> String:
	var load := carry_total()
	var suffix := " · 보관 %d" % load if load > 0 else ""
	if kind == "merc" and game.get("tavern") != null and game.tavern.hungover(self):
		return "숙취 %d초" % int(ceil(game.tavern.hangover_left(self))) + suffix
	match state:
		State.GO_WORK: return "벌목하러 가는 중" + suffix
		State.WORKING: return "벌목 %d초" % int(ceil(_chop_time() - progress)) + suffix
		State.PATROL, State.PATROL_WAIT: return "정찰 중" + suffix
		State.ENGAGE: return "전투 중" + suffix
		State.HUNT: return "사냥 중" + suffix
		State.ESCORT: return "마녀와 동행 중" + suffix
		State.GATHER_OUT: return "숲 탐색 중 (%d/%d)" % [gather_index + 1, gather_stops.size()] + suffix
		State.GATHER_PICK: return "줍는 중" + suffix
		State.GATHER_RETURN: return "돌아오는 중" + suffix
		State.TOWER_GO: return "감시탑으로 가는 중"
		State.TOWER_POST: return "감시탑 위 경계"
		State.GO_HIDE: return "산장으로 대피"
		State.HIDDEN: return "산장 안"
		State.GUARD:
			if target != null:
				return "전투 중"
			return "대기 — 밤 전투" if game.session.state == 0 else "방어 중"
		State.IDLE:
			if job == "lumberjack" and int(carry.get("timber", 0)) >= Cfg.LUMBERJACK_CARRY:
				return "목재 가득 — 쉬며 마녀를 기다림" + suffix
			if load > 0:
				return "마녀를 기다림" + suffix
			if hp >= max_hp:
				return "산장 마당에서 휴식"
			return "모닥불 곁에서 회복 중" if campfire_heal_rate() > 0.0 else "휴식 중 — 모닥불이 꺼져 회복하지 못함"
	return ""


## 머리 위에 띄우는 짧은 상태(한두 단어). 긴 설명은 status_text()로 용병 명부에 보여 준다.
func short_status() -> String:
	var load := carry_total()
	var suffix := " · 짐%d" % load if load > 0 else ""
	match state:
		State.GO_WORK: return "벌목" + suffix
		State.WORKING: return "벌목 %d초" % int(ceil(_chop_time() - progress)) + suffix
		State.PATROL, State.PATROL_WAIT: return "정찰" + suffix
		State.ENGAGE: return "전투" + suffix
		State.HUNT: return "사냥" + suffix
		State.ESCORT: return "동행" + suffix
		State.GATHER_OUT: return "채집 %d/%d" % [gather_index + 1, gather_stops.size()] + suffix
		State.GATHER_PICK: return "채집" + suffix
		State.GATHER_RETURN: return "귀환" + suffix
		State.TOWER_GO: return "감시탑"
		State.TOWER_POST: return "경계"
		State.GO_HIDE: return "대피"
		State.HIDDEN: return "산장 안"
		State.GUARD:
			if target != null:
				return "전투"
			return "대기" if game.session.state == 0 else "방어"
		State.IDLE:
			if job == "lumberjack" and int(carry.get("timber", 0)) >= Cfg.LUMBERJACK_CARRY:
				return "목재 가득"
			if load > 0:
				return "전달 대기" + suffix
			if hp >= max_hp:
				return "휴식"
			return "회복" if campfire_heal_rate() > 0.0 else "불 꺼짐"
	return ""


## 지금 이 자리에서 받는 모닥불 낮 회복(초당). 앞마당이 없으면 0.
func campfire_heal_rate() -> float:
	var yard = game.world.yard if game != null and game.world != null else null
	return yard.heal_rate_at(global_position) if yard != null else 0.0


## 다친 전투직이 낮에 켜진 모닥불 곁으로 가 쉬어야 하는가.
func wants_campfire_rest() -> bool:
	if dead or kind != "merc" or not is_combat_job() or hp >= max_hp or escort:
		return false
	if game.session.state != 0:   # 낮(준비 시간)만
		return false
	var yard = game.world.yard if game.world != null else null
	return yard != null and yard.is_lit()


func display_name() -> String:
	if kind == "minion":
		return "숲의 괴물"
	return "%s(%s)" % [person, Cfg.JOB_NAMES.get(job, "")]


func carry_total() -> int:
	var n := 0
	for k in carry:
		n += int(carry[k])
	return n


## 자원을 들고 있게 한다(나무꾼 벌목·사냥꾼 사냥·채집가 줍기).
func add_carry(id: String, amount: int) -> void:
	if amount <= 0:
		return
	if kind == "merc" and game.get("race_cards") != null:
		amount *= game.race_cards.carry_mult(self, id)  # 짐꾼의 등짐
	carry[id] = int(carry.get(id, 0)) + amount


## 마녀에게 들고 있던 자원을 모두 넘긴다.
func hand_over() -> void:
	if carry.is_empty() or dead:
		return
	var parts: Array = []
	for id in carry.keys():
		var n: int = carry[id]
		game.cards.add(id, n)
		parts.append("%s +%d" % [game.cards.def(id).get("name", id), n])
	carry.clear()
	game.toast("%s — %s을(를) 건네받았습니다" % [person, " · ".join(parts)], Color(1.0, 0.92, 0.7))
	Fx.celebrate(global_position + Vector3(0, 1.4, 0), Color(1.0, 0.9, 0.6), 0.8)
	Sfx.play(self, "wool_get")
	_handover_cd = 1.0


# ───────────────────────── 행동 ─────────────────────────

func _flat(p: Vector3) -> float:
	return ActorUtil.flat_dist(p, global_position)


func _flat_from(a: Vector3, b: Vector3) -> float:
	return ActorUtil.flat_dist(a, b)


func _lodge_center() -> Vector3:
	return game.world.lodge.global_position


func _chop_time() -> float:
	return Cfg.RELIC_CHOP_TIME if game.relics != null and game.relics.has("old_tree_heart") else Cfg.CHOP_TIME


func _physics_process(delta: float) -> void:
	if dead:
		return
	if hidden:
		# 산장 안에서 쉬는 동안에도 회복한다
		hp = minf(hp + Cfg.MERC_REGEN * delta, max_hp)
		return
	# 불꽃 에일 숙취(주점 카드 v1): 다음 날 낮 처음 얼마 동안은 그 자리에서 쉰다
	if kind == "merc" and game.get("tavern") != null and game.tavern.hungover(self):
		velocity = Vector3.ZERO
		_animate(delta, false)
		return
	var vel := Vector3.ZERO
	attack_cd = maxf(attack_cd - delta, 0.0)
	_tick_pending(delta)
	_handover_cd = maxf(_handover_cd - delta, 0.0)
	if on_tower:
		_tower_post(delta)
		_animate(delta, false)
		return
	# 밤의 사냥꾼은 빈자리가 있는 감시탑부터 맡는다(교전보다 먼저).
	if job == "hunter" and kind == "merc" and tower == null and game.session.state == SessionScript.State.COMBAT:
		_claim_tower()
	# 낮에 마녀가 산장을 벗어나면 따라나서고, 돌아오면 정찰로 복귀한다(docs/merc-escort-v01.md).
	if is_combat_job() and kind == "merc":
		_update_escort(delta)
	if state != State.ESCORT:
		_sprint = 1.0
	# 전투직은 어느 상태에서든 적을 발견하면 교전으로 전환한다(산장 공격자 우선).
	if is_combat_job() and kind == "merc" and state != State.ENGAGE and state != State.TOWER_GO:
		var e = _find_enemy()
		if e != null:
			target = e
			prey = null
			state = State.ENGAGE
	match state:
		State.GO_WORK:
			if tree == null or tree.get("removed", false) or tree["remaining"] <= 0:
				game.contracts.assign_next_tree(self)
			elif _flat(work_pos) <= 0.25:
				state = State.WORKING
			else:
				vel = _steer(work_pos)
		State.WORKING:
			if tree == null or tree.get("removed", false):
				game.contracts.assign_next_tree(self)
			else:
				_face(tree["pos"] - global_position, delta)
				progress += delta
				if progress >= _chop_time():
					game.contracts.finish_chop(self)
		State.PATROL:
			if wants_campfire_rest():
				become_idle(game.contracts.yard_spot(self))
			elif _flat(patrol_point) <= 0.4:
				state = State.PATROL_WAIT
				patrol_wait = _rng.randf_range(Cfg.PATROL_PAUSE[0], Cfg.PATROL_PAUSE[1])
			else:
				vel = _steer(patrol_point)
			if job == "hunter" and game.session.state == 0:
				_look_for_prey()
		State.PATROL_WAIT:
			patrol_wait -= delta
			if wants_campfire_rest():
				become_idle(game.contracts.yard_spot(self))
			elif patrol_wait <= 0.0:
				_pick_patrol_point()
				state = State.PATROL
			if job == "hunter" and game.session.state == 0:
				_look_for_prey()
		State.ENGAGE:
			vel = _engage(delta)
		State.HUNT:
			vel = _hunt(delta)
		State.ESCORT:
			vel = _escort(delta)
		State.GATHER_OUT:
			vel = _gather_out(delta)
		State.GATHER_PICK:
			gather_timer += delta
			if rig == null:
				body.rotation.x = 0.35 + sin(gather_timer * 5.0) * 0.08
			if gather_timer >= Cfg.GATHER_PICK_TIME:
				body.rotation.x = 0.0
				game.contracts.gather_pick(self)
				gather_index += 1
				if gather_index >= gather_stops.size() or game.contracts.gather_must_return(self):
					return_home(false)
				else:
					state = State.GATHER_OUT
		State.GATHER_RETURN:
			if _flat(guard_point) <= 0.35:
				if hide_on_arrive:
					_go_hide()
				else:
					become_idle(guard_point)
			else:
				vel = _steer(guard_point)
		State.IDLE:
			# 모닥불에서 쉬던 전투직: 다 나았거나 불이 꺼지면 정찰로 돌아간다
			if is_combat_job() and kind == "merc" and not wants_campfire_rest():
				state = State.PATROL
				_pick_patrol_point()
			else:
				vel = _steer(guard_point) if _flat(guard_point) > 0.35 else Vector3.ZERO
		State.GO_HIDE:
			var door := Layout.DOOR_FRONT
			if _flat(door) <= 0.5:
				_enter_lodge()
			else:
				vel = _steer(door)
		State.GUARD:
			vel = _guard(delta)
		State.TOWER_GO:
			vel = _go_tower()
	if on_tower:
		return   # 방금 탑에 올랐다: 지면 이동·높이 고정을 건너뛴다
	# 낮에는 켜진 모닥불 곁에서만 아주 천천히 회복한다(docs/resource-uses-expansion-v01.md v0.3).
	# 화로의 온기석이 있으면 밤에도 산장 곁에서 회복한다.
	if kind == "merc" and hp < max_hp:
		var day: bool = game.session.state == 0
		var ember: bool = game.relics != null and game.relics.has("hearth_ember") and _flat(_lodge_center()) <= Cfg.RELIC_EMBER_RADIUS
		if day:
			hp = minf(hp + campfire_heal_rate() * delta, max_hp)
		elif ember:
			hp = minf(hp + Cfg.RELIC_EMBER_REGEN * delta, max_hp)
	_check_handover()
	_watch_stuck(vel, delta)
	velocity = vel + SoftSep.push(self)
	var walking := vel.length() > 0.05
	if walking:
		_face(vel, delta)
		if kind == "minion":
			_shed_leaves(delta, vel)
	move_and_slide()
	global_position.y = 0.0
	_animate(delta, walking)


## 마녀가 가까이 오면 들고 있던 자원을 넘긴다.
func _check_handover() -> void:
	if carry.is_empty() or _handover_cd > 0.0 or game.player == null or game.player.dead:
		return
	if _flat(game.player.global_position) <= Cfg.HANDOVER_RANGE:
		_face(game.player.global_position - global_position, 0.2)
		hand_over()


func _steer(p: Vector3) -> Vector3:
	_repath_t -= get_physics_process_delta_time()
	if _repath_t <= 0.0 or agent.target_position.distance_to(p) > 0.3:
		agent.target_position = p
		_repath_t = 0.4
	var next := agent.get_next_path_position()
	var d := next - global_position
	d.y = 0.0
	var speed := Cfg.BIG_MONSTER_SPEED + 0.3
	if kind != "minion":   # 매 이동 틱이라 _gear 람다 대신 직접 부른다
		var eq = game.get(&"equipment") if game != null else null
		speed = Cfg.MERC_SPEED * (eq.speed_mult(self) if eq != null else 1.0)
		speed *= _sprint   # 동행 따라잡기: 마녀와 멀수록 빠르게 달린다(_escort_speed_mult)
		if game.get("merc_kit") != null:
			speed *= game.merc_kit.speed_mult(self)  # 도망쳐!·요정 둘
	var v := d.normalized() * speed if d.length() > 0.05 else Vector3.ZERO
	return v


# ── 정찰 ──

func _pick_patrol_point() -> void:
	var c := _lodge_center()
	var map: RID = get_world_3d().navigation_map
	for i in 12:
		var a := _rng.randf_range(0.0, TAU)
		var r := _rng.randf_range(Cfg.PATROL_RADIUS[0], Cfg.PATROL_RADIUS[1])
		var p := c + Vector3(cos(a) * r, 0, sin(a) * r)
		# 앞마당·양옆만 정찰한다. 산장 뒤(후면 띠·목장 뒤 구석)는 막다른 포켓이라 제외.
		if p.z < -0.5 or Layout.in_rear_enclosure(Vector2(p.x, p.z)):
			continue
		# 지면 내비 점이고 지금 자리에서 경로가 닿아야 한다(장애물 윗면 섬·막힌 포켓 제외).
		var nav = NavUtil.walkable_from(map, global_position, p, 1.5, 0.6)
		if nav == null:
			continue
		if game.world.pasture.inside(nav, 0.3) or game.world.lodge.distance_to(nav) < 0.8:
			continue
		patrol_point = nav
		return
	patrol_point = Layout.DOOR_FRONT + Vector3(_rng.randf_range(-1.5, 1.5), 0, 1.0 + _rng.randf_range(0.0, 1.5))


# ── 교전 ──

func _valid_enemy(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead


## 교전 대상 찾기: 산장 공격자 → 카드로 지정한 적 → 산장 근처(ENGAGE_RADIUS)의 웨이브 적.
## 동행 중에는 마녀 근처(ESCORT_ENGAGE_RADIUS)의 모든 적(맹독 곤충 포함)을 찾는다.
func _find_enemy():
	var threat = game.contracts.lodge_threat
	if _valid_enemy(threat):
		return threat
	if _valid_enemy(priority):
		return priority
	if escort:
		return _find_enemy_near_witch()
	var c := _lodge_center()
	var best = null
	var best_d := Cfg.ENGAGE_RADIUS
	for e in get_tree().get_nodes_in_group("wave_enemies"):
		if not _valid_enemy(e):
			continue
		var d := _flat_from(c, e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best


func _damage_mult() -> float:
	var m := _gear(func(eq): return eq.damage_mult(self))
	if kind == "merc" and game.get("tavern") != null:
		m *= game.tavern.damage_mult(self)  # 불꽃 에일
	if kind == "merc" and game.get("merc_kit") != null:
		m *= game.merc_kit.damage_mult(self)  # 용병 키트 패시브·버프·시너지
	if kind == "merc" and game.relics != null and game.relics.has("wolf_fang_pendant"):
		return Cfg.RELIC_FANG_MULT * m
	return m


## 공격 간격 배율(종족 카드 v1 — 승리의 함성·무리의 냄새). 작을수록 빠르다.
func _interval_mult() -> float:
	var m: float = game.race_cards.interval_mult(self) if kind == "merc" and game.get("race_cards") != null else 1.0
	if kind == "merc" and game.get("merc_kit") != null:
		m *= game.merc_kit.interval_mult(self)  # 호통·피냄새
	return m


## 공격이 적에게 맞음(근접·화살): 엉겅퀴 맹세 둔화·전쟁 북 넉백.
func on_hit(e) -> void:
	if kind == "merc" and game.get("race_cards") != null:
		game.race_cards.on_hit_from(self, e)
	if kind == "merc" and game.get("tavern") != null:
		game.tavern.on_hit_from(self, e)  # 불꽃 에일: 처음 몇 번은 불을 붙인다
	if kind == "merc" and game.get("merc_kit") != null:
		game.merc_kit.on_ally_hit(self, e)  # 기세 +10


## 장비 배율 하나(장비 모듈이 없으면 1).
func _gear(f: Callable) -> float:
	var eq = game.get("equipment") if game != null else null
	return f.call(eq) if eq != null else 1.0


func _engage(delta: float) -> Vector3:
	var lost := not _valid_enemy(target)
	if not lost:
		# 동행 중에는 마녀에게서, 아니면 산장에서 너무 멀어진 대상을 놓아준다
		if escort and _witch_valid():
			lost = _flat_from(game.player.global_position, target.global_position) > Cfg.ESCORT_DISENGAGE_RADIUS
		else:
			lost = _flat_from(_lodge_center(), target.global_position) > Cfg.DISENGAGE_RADIUS
	if lost:
		target = _find_enemy()
		if target == null:
			priority = null
			if escort:
				state = State.ESCORT
			else:
				state = State.PATROL
				_pick_patrol_point()
			return Vector3.ZERO
	var threat = game.contracts.lodge_threat
	if _valid_enemy(threat) and target != threat:
		target = threat
	var d := _flat(target.global_position)
	if job == "hunter":
		if d <= Cfg.HUNTER_RANGE:
			_face(target.global_position - global_position, delta)
			if attack_cd <= 0.0:
				attack_cd = Cfg.HUNTER_INTERVAL * _interval_mult()
				_shoot(target, Cfg.HUNTER_DAMAGE * _damage_mult())
			if d < Cfg.HUNTER_KITE:
				var away: Vector3 = (global_position - target.global_position)
				away.y = 0.0
				return away.normalized() * Cfg.MERC_SPEED * 0.8
			return Vector3.ZERO
		return _steer(target.global_position)
	# 전투용병: 근접
	if d <= Cfg.ALLY_MELEE:
		_face(target.global_position - global_position, delta)
		if attack_cd <= 0.0 and _pending.is_empty():
			attack_cd = Cfg.WARRIOR_INTERVAL * _interval_mult()
			if rig != null:
				# 크게 감아올렸다가 임팩트 순간에 피해(_slash_impact)
				_pending = {"kind": "slash", "target": target, "dmg": Cfg.WARRIOR_DAMAGE * _damage_mult(), "t": rig.action("slash")}
			else:
				_lunge_t = 0.3
				Fx.slash(global_position + Vector3(0, 0.8, 0), target.global_position - global_position)
				target.take_damage(Cfg.WARRIOR_DAMAGE * _damage_mult())
				on_hit(target)
				Sfx.play(self, "ally_attack")
		return Vector3.ZERO
	return _steer(target.global_position)


func _shoot(at, dmg: float) -> void:
	if rig != null:
		# 시위를 끝까지 당긴 뒤 놓는 순간 화살이 나간다(_release_arrow)
		if _pending.is_empty():
			_pending = {"kind": "shot", "target": at, "dmg": dmg, "t": rig.action("draw")}
		return
	var arrow := ArrowScript.new()
	arrow.target = at
	arrow.damage = dmg
	arrow.shooter = self
	game.actors.add_child(arrow)
	arrow.global_position = global_position + Vector3(0, 1.0, 0)
	_lunge_t = 0.25
	Sfx.play_or(self, "bow_shot", "ally_attack")


# ── 감시탑 ──

## 빈자리가 있는 서 있는 감시탑 중 가장 가까운 곳을 맡는다.
func _claim_tower() -> void:
	var best = null
	var best_d := INF
	for t in game.world.towers:
		if t.has_free_slot():
			var d := _flat(t.global_position)
			if d < best_d:
				best_d = d
				best = t
	if best == null or not best.claim(self):
		return
	tower = best
	target = null
	prey = null
	state = State.TOWER_GO


func _go_tower() -> Vector3:
	if tower == null or not tower.is_standing():
		leave_tower()
		return Vector3.ZERO
	var spot: Vector3 = tower.climb_spot()
	if _flat(spot) <= Cfg.TOWER_CLIMB_RADIUS:
		_climb()
		return Vector3.ZERO
	return _steer(spot)


func _climb() -> void:
	if tower == null or not tower.is_standing():
		leave_tower()
		return
	on_tower = true
	state = State.TOWER_POST
	velocity = Vector3.ZERO
	collision_mask = 0
	global_position = tower.perch_position(self)
	Fx.summon(global_position, Color(0.6, 0.95, 0.75))


## 발판 위: 움직이지 않고 긴 사거리로 쏜다. 탑 공격자 → 산장 공격자 → 가장 가까운 적.
func _tower_post(delta: float) -> void:
	if tower == null or not is_instance_valid(tower) or not tower.is_standing():
		leave_tower()
		return
	global_position = tower.perch_position(self)
	var pick = null
	for cand in [tower.last_attacker, game.contracts.lodge_threat]:
		if _valid_enemy(cand) and _flat(cand.global_position) <= Cfg.TOWER_RANGE:
			pick = cand
			break
	if pick == null:
		var best_d := Cfg.TOWER_RANGE
		for e in get_tree().get_nodes_in_group("enemies"):
			if not _valid_enemy(e):
				continue
			var d := _flat(e.global_position)
			if d <= best_d:
				best_d = d
				pick = e
	target = pick
	if pick == null:
		return
	_face(pick.global_position - global_position, delta)
	if attack_cd <= 0.0:
		attack_cd = Cfg.TOWER_INTERVAL * _interval_mult()
		_shoot(pick, Cfg.HUNTER_DAMAGE * Cfg.TOWER_DAMAGE_MULT * _damage_mult())


## 탑에서 내려와(또는 가는 길을 그만두고) 지상 정찰로 돌아간다. 새벽·탑 붕괴·막힘에서 부른다.
func leave_tower() -> void:
	var t = tower
	tower = null
	if t != null and is_instance_valid(t):
		t.release(self)
	if on_tower:
		on_tower = false
		collision_mask = Cfg.L_OBSTACLE | Cfg.L_BOUNDARY
		global_position = t.climb_spot() if t != null and is_instance_valid(t) else Vector3(global_position.x, 0, global_position.z)
		global_position.y = 0.0
	if dead:
		return
	target = null
	if state == State.TOWER_GO or state == State.TOWER_POST:
		state = State.PATROL
		_pick_patrol_point()


# ── 사냥 ──

## 사냥감 찾기. 기본은 내 위치 기준 HUNT_SEARCH_RADIUS, 동행 중에는 마녀 위치 기준 ESCORT_HUNT_RADIUS 로 부른다.
func _look_for_prey(from := Vector3.INF, radius := Cfg.HUNT_SEARCH_RADIUS) -> void:
	var origin: Vector3 = global_position if from == Vector3.INF else from
	var best = null
	var best_d := radius
	for a in get_tree().get_nodes_in_group("animals"):
		if a.dead:
			continue
		var d := _flat_from(origin, a.global_position)
		if d < best_d:
			best_d = d
			best = a
	if best != null:
		prey = best
		state = State.HUNT


func _hunt(delta: float) -> Vector3:
	if prey == null or not is_instance_valid(prey) or prey.dead or game.session.state != 0:
		prey = null
		if escort:
			state = State.ESCORT
		else:
			state = State.PATROL
			_pick_patrol_point()
		return Vector3.ZERO
	# 동행 중 길가 사냥: 마녀가 움직이기 시작하거나 사냥감이 마녀에게서 멀리 달아나면 바로 따라간다
	if escort and (_witch_still_t < Cfg.ESCORT_STILL_TIME or not _witch_valid()
			or _flat_from(game.player.global_position, prey.global_position) > Cfg.ESCORT_HUNT_RADIUS + 2.0):
		prey = null
		state = State.ESCORT
		return Vector3.ZERO
	var d := _flat(prey.global_position)
	if d <= Cfg.HUNTER_RANGE - 0.4:
		_face(prey.global_position - global_position, delta)
		if attack_cd <= 0.0:
			attack_cd = Cfg.HUNTER_INTERVAL
			_shoot(prey, Cfg.HUNTER_DAMAGE)
		return Vector3.ZERO
	return _steer(prey.global_position)


## 화살에 맞은 사냥감이 쓰러짐: 전리품을 들고 있는다(늑대 송곳니 목걸이면 +1).
func receive_loot(loot: Dictionary) -> void:
	if dead:
		return
	var bonus: int = Cfg.RELIC_FANG_DROP if game.relics != null and game.relics.has("wolf_fang_pendant") else 0
	var parts: Array = []
	for id in loot:
		var n: int = int(loot[id]) + (bonus if loot.keys()[0] == id else 0)
		add_carry(id, n)
		parts.append("%s +%d" % [game.cards.def(id).get("name", id), n])
	game.toast("%s — 사냥 성공: %s (들고 있음)" % [person, " · ".join(parts)], Color(0.9, 1.0, 0.85))


# ── 동행(docs/merc-escort-v01.md) ──

func _witch_valid() -> bool:
	return game != null and game.player != null and is_instance_valid(game.player) and not game.player.dead


## 매 틱: 낮에 마녀가 산장 중심 ESCORT_LEAVE_RADIUS 밖이면 따라나서고, ESCORT_RETURN_RADIUS 안으로 돌아오거나
## 밤이 되거나 마녀가 쓰러지면 동행을 끝낸다. 마녀가 제자리에 선 시간(_witch_still_t)도 여기서 잰다.
func _update_escort(delta: float) -> void:
	if not _witch_valid():
		_witch_still_t = 0.0
		if escort:
			_end_escort()
		return
	var wp: Vector3 = game.player.global_position
	if _witch_prev != Vector3.INF and _flat_from(wp, _witch_prev) < 0.02:
		_witch_still_t += delta
	else:
		_witch_still_t = 0.0
	_witch_prev = wp
	var day: bool = game.session.state == 0 and not game.session.is_over()
	var d := _flat_from(_lodge_center(), wp)
	if escort:
		if not day or d < Cfg.ESCORT_RETURN_RADIUS:
			_end_escort()
		return
	if not day or d < Cfg.ESCORT_LEAVE_RADIUS or on_tower or tower != null:
		return
	if state in [State.PATROL, State.PATROL_WAIT, State.IDLE, State.HUNT, State.ENGAGE]:
		escort = true
		prey = null
		_escort_far_t = 0.0
		if state != State.ENGAGE:
			state = State.ESCORT
		game.contracts.note_escort_start(self)


## 동행 끝: 교전 중이면 마치고(산장 규칙으로 놓아줌), 아니면 정찰로 돌아간다.
func _end_escort() -> void:
	escort = false
	_sprint = 1.0
	_escort_far_t = 0.0
	if state == State.ESCORT or state == State.HUNT:
		prey = null
		state = State.PATROL
		_pick_patrol_point()


func _escort_follow_dist() -> float:
	if not carry.is_empty():
		return Cfg.ESCORT_FOLLOW_CARRY
	return float(Cfg.ESCORT_FOLLOW_DIST.get(job, 2.5))


## 마녀 곁에 붙어 다닌다: 가까우면 서고, 멀면 걷고, 더 멀면 달린다. 아주 멀어진 채 오래면 곁으로 순간이동.
## 사냥꾼은 마녀가 서 있을 때만 주변 사냥감을 찾는다.
func _escort(delta: float) -> Vector3:
	_sprint = 1.0
	if not _witch_valid():
		return Vector3.ZERO
	var wp: Vector3 = game.player.global_position
	var d := _flat(wp)
	if d > Cfg.ESCORT_WARP_DIST:
		_escort_far_t += delta
		if _escort_far_t >= Cfg.ESCORT_WARP_TIME:
			_warp_to_witch()
			return Vector3.ZERO
	else:
		_escort_far_t = 0.0
	if job == "hunter" and _witch_still_t >= Cfg.ESCORT_STILL_TIME:
		_look_for_prey(wp, Cfg.ESCORT_HUNT_RADIUS)
		if state == State.HUNT:
			return Vector3.ZERO
	if d <= _escort_follow_dist():
		_face(wp - global_position, delta)
		return Vector3.ZERO
	_sprint = _escort_speed_mult(d)
	return _steer(wp)


## 마녀와의 거리에 비례한 속도 배율: ESCORT_SPEED_NEAR 에서 1배, ESCORT_SPEED_FAR 이상에서 ESCORT_SPEED_MAX_MULT 배(선형).
func _escort_speed_mult(d: float) -> float:
	var u := clampf((d - Cfg.ESCORT_SPEED_NEAR) / (Cfg.ESCORT_SPEED_FAR - Cfg.ESCORT_SPEED_NEAR), 0.0, 1.0)
	return lerpf(1.0, Cfg.ESCORT_SPEED_MAX_MULT, u)


## 끼임·막힘 안전장치: 마녀 근처의 이동 가능 지면으로 옮긴다.
func _warp_to_witch() -> void:
	_escort_far_t = 0.0
	var wp: Vector3 = game.player.global_position
	var map: RID = get_world_3d().navigation_map
	var dest := wp
	for i in 8:
		var a := _rng.randf_range(0.0, TAU)
		var p := wp + Vector3(cos(a), 0, sin(a)) * _rng.randf_range(1.5, 2.5)
		var nav = NavUtil.walkable_from(map, wp, p, 1.0, 0.6)
		if nav != null:
			dest = nav
			break
	Fx.poof(global_position + Vector3(0, 0.6, 0), Color(0.75, 0.9, 1.0), 0.5)
	global_position = Vector3(dest.x, 0.0, dest.z)
	agent.target_position = global_position
	Fx.poof(global_position + Vector3(0, 0.6, 0), Color(0.75, 0.9, 1.0), 0.5)


## 동행 중 마녀 근처(ESCORT_ENGAGE_RADIUS)의 가장 가까운 적. 밤 웨이브 적뿐 아니라 맹독 곤충도 포함(enemies 그룹).
func _find_enemy_near_witch():
	if not _witch_valid():
		return null
	var wp: Vector3 = game.player.global_position
	var best = null
	var best_d := Cfg.ESCORT_ENGAGE_RADIUS
	for e in get_tree().get_nodes_in_group("enemies"):
		if not _valid_enemy(e):
			continue
		var d := _flat_from(wp, e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best


# ── 채집 ──

func _gather_out(_delta: float) -> Vector3:
	if gather_index >= gather_stops.size():
		return_home(false)
		return Vector3.ZERO
	if game.contracts.gather_must_return(self):
		return_home(false)
		return Vector3.ZERO
	var stop: Vector3 = gather_stops[gather_index]
	if _flat(stop) <= 0.5:
		gather_timer = 0.0
		state = State.GATHER_PICK
		return Vector3.ZERO
	return _steer(stop)


# ── 대피 ──

func _go_hide() -> void:
	target = null
	prey = null
	state = State.GO_HIDE


func _enter_lodge() -> void:
	_pending = {}
	hidden = true
	state = State.HIDDEN
	visible = false
	collision_mask = 0
	remove_from_group("show_hp")
	Fx.poof(Layout.DOOR_FRONT + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.6), 0.6)
	Sfx.play(self, "panel_close")


func _unhide() -> void:
	hidden = false
	visible = true
	collision_mask = Cfg.L_OBSTACLE | Cfg.L_BOUNDARY
	global_position = Layout.DOOR_FRONT + Vector3(_rng.randf_range(-0.4, 0.4), 0, 0.6)
	if not is_in_group("show_hp"):
		add_to_group("show_hp")
	Fx.poof(global_position + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.6), 0.6)


# ── 하수인(기존 방식) ──

func _guard(delta: float) -> Vector3:
	if target != null and (not is_instance_valid(target) or target.dead):
		target = null
	if priority != null and (not is_instance_valid(priority) or priority.dead):
		priority = null
	if priority != null:
		target = priority
	elif target == null or _flat_from(guard_point, target.global_position) > Cfg.ALLY_LEASH:
		target = _nearest_enemy()
	if target == null:
		return _steer(guard_point) if _flat(guard_point) > 0.35 else Vector3.ZERO
	if _flat(target.global_position) <= Cfg.ALLY_MELEE:
		_face(target.global_position - global_position, delta)
		if attack_cd <= 0.0:
			attack_cd = Cfg.MINION_INTERVAL
			_lunge_t = 0.3
			Fx.claw(global_position + Vector3(0, 0.7, 0), target.global_position - global_position, Color(0.5, 1.0, 0.55))
			target.take_damage(Cfg.MINION_DAMAGE)
			Sfx.play(self, "ally_attack")
		return Vector3.ZERO
	return _steer(target.global_position)


func _nearest_enemy():
	var best = null
	var best_d := Cfg.ALLY_AGGRO
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d := _flat_from(guard_point, e.global_position)
		if d <= best_d:
			best_d = d
			best = e
	return best


func _face(dir: Vector3, delta: float) -> void:
	ActorUtil.face(visual, dir, delta, 9.0)


func _animate(delta: float, walking: bool) -> void:
	if rig != null:
		_animate_rig(delta, walking)
		return
	_anim_t += delta * (8.0 if walking else 2.0)
	body.position.y = absf(sin(_anim_t)) * (0.06 if walking else 0.0)
	if state == State.WORKING:
		# 도끼질: 앞으로 크게 숙였다 펴기
		var k := maxf(sin(progress * 6.0), 0.0)
		body.rotation.x = k * 0.45
		if fmod(progress, TAU / 6.0) < delta and tree != null:
			var tp: Vector3 = tree["pos"]
			Fx.wood_chips(tp + (global_position - tp).normalized() * 0.35 + Vector3(0, 0.7, 0), tp + Vector3(0, 3.5, 0))
			_shake_tree(tree["visual"])
			Sfx.play(self, "chop")
	elif state == State.GATHER_PICK:
		pass  # 줍기 숙임은 상태 처리에서
	elif _lunge_t > 0.0:
		_lunge_t -= delta
		var k2 := sin(clampf(_lunge_t / 0.3, 0.0, 1.0) * PI)
		if job == "hunter":
			body.rotation.x = -k2 * 0.12
			if _bow != null:
				_bow.position.z = 0.14 + k2 * 0.1
		else:
			body.position.z = k2 * 0.25
			body.rotation.x = k2 * 0.4
	else:
		body.position.z = 0.0
		body.rotation.x = 0.0


## 파츠 모델 용병: 직업 상태에 맞는 반복 동작(도끼질·줍기·경계·대피·걷기·서기). 공격(베기·활)은 rig.action 이 위에 덮는다.
func _animate_rig(_delta: float, walking: bool) -> void:
	body.position = Vector3.ZERO
	body.rotation = Vector3.ZERO
	if state == State.WORKING and tree != null:
		rig.play("chop")
		var u := fposmod(progress / CHOP_PERIOD, 1.0)
		rig.amount = u
		# 도끼가 박히는 순간: 나무 파편·나무 흔들림·소리 + 짧은 타격 멈춤
		var hit_now := (_chop_u < RigAnim.CHOP_IMPACT and u >= RigAnim.CHOP_IMPACT) or (_chop_u > u and u >= RigAnim.CHOP_IMPACT)
		if hit_now:
			var tp: Vector3 = tree["pos"]
			Fx.wood_chips(tp + (global_position - tp).normalized() * 0.35 + Vector3(0, 0.7, 0), tp + Vector3(0, 3.5, 0))
			_shake_tree(tree["visual"])
			Sfx.play(self, "chop")
			rig.freeze(0.07)
		_chop_u = u
	elif state == State.GATHER_PICK:
		rig.play("pick")
		rig.amount = clampf(gather_timer / Cfg.GATHER_PICK_TIME, 0.0, 1.0)
	elif on_tower:
		rig.play("idle" if target != null else "lookout")
	elif state == State.GO_HIDE and walking:
		rig.play("flee")
	else:
		rig.play("walk" if walking else "idle")


## 공격 판정을 동작의 임팩트 순간에 맞춘다(베기 칼날이 닿는 순간 피해, 시위를 놓는 순간 화살).
func _tick_pending(delta: float) -> void:
	if _pending.is_empty():
		return
	_pending["t"] = float(_pending["t"]) - delta
	if float(_pending["t"]) > 0.0:
		return
	var p := _pending
	_pending = {}
	match str(p["kind"]):
		"slash": _slash_impact(p["target"], float(p["dmg"]))
		"shot": _release_arrow(p["target"], float(p["dmg"]))


## 전투용병 베기 임팩트: 아직 닿는 거리면 피해 + 큰 섬광 + 타격 멈춤 + 짧은 화면 흔들림. 빗나가면 헛베기 섬광만.
func _slash_impact(e, dmg: float) -> void:
	var dir: Vector3 = (e.global_position - global_position) if _valid_enemy(e) else -visual.global_basis.z
	dir.y = 0.0
	var at := global_position + Vector3(0, 0.85, 0) + dir.normalized() * 0.55
	Fx.slash(at, dir, Color(1.0, 0.95, 0.75))
	if _valid_enemy(e) and _flat(e.global_position) <= Cfg.ALLY_MELEE + 0.8:
		e.take_damage(dmg)
		on_hit(e)
		Fx.hit(e.global_position + Vector3(0, 0.8, 0), Color(1.0, 0.85, 0.5))
		Sfx.play(self, "ally_attack")
		if rig != null:
			rig.freeze(0.085)
		if game != null and game.get("world") != null:
			game.world.shake(0.045, 0.1)


## 사냥꾼 시위를 놓는 순간: 화살 발사 + 활 끝의 작은 바람 + 짧은 멈춤.
func _release_arrow(at, dmg: float) -> void:
	if at == null or not is_instance_valid(at) or at.dead:
		return
	var arrow := ArrowScript.new()
	arrow.target = at
	arrow.damage = dmg
	arrow.shooter = self
	game.actors.add_child(arrow)
	arrow.global_position = (_bow.global_position if _bow != null else global_position + Vector3(0, 1.0, 0))
	Fx.snow_kick(_bow.global_position if _bow != null else global_position + Vector3(0, 1.0, 0), -visual.global_basis.z, 1, 0.5)
	Sfx.play_or(self, "bow_shot", "ally_attack")
	if rig != null:
		rig.freeze(0.04)


func take_damage(amount: float) -> void:
	if dead or hidden:
		return
	if game.get("merc_kit") != null:
		var guard = game.merc_kit.guard_of(self)
		if guard != null:
			guard.take_damage(amount)  # 맹세의 방패: 가로크가 대신 맞는다
			return
	if rig != null:
		rig.flinch()
	amount *= _gear(func(eq): return eq.taken_mult(self))
	if game.get("merc_kit") != null:
		amount *= game.merc_kit.taken_mult(self)  # 방패벽
		game.merc_kit.on_ally_hurt(self, amount)  # 받은 만큼 기세(1회 최대 15)
	hp = maxf(hp - amount, 0.0)
	if hp <= 0.0 and game.get("merc_kit") != null and game.merc_kit.try_save(self):
		hp = 1.0  # 재의 축복: 한 번 버틴다
	if hp <= 0.0 and game.get("chapter") != null and game.chapter != null and game.chapter.try_ward(self):
		hp = 1.0  # 수의: 치명타를 한 번 버틴다
	if hp > 0.0:
		Sfx.play(self, "ally_hurt")
	Fx.flash(visual)
	Fx.damage_number(get_parent(), global_position + Vector3(0, 2.0, 0), amount, Color(1.0, 0.5, 0.45))
	if hp <= 0.0:
		if kind != "minion":
			Sfx.play(self, "merc_die")
		if kind == "minion":
			game.contracts.wither_minion(self, "쓰러져")
			return
		dead = true
		game.contracts.on_ally_died(self)
		if game.get("equipment") != null:
			game.equipment.release_all(self)
		_leave_world()
		Fx.vanish(self, Color(0.6, 0.3, 0.3, 0.8))


## 계약 해지(산장 관리): 들고 있던 자원은 마녀에게 넘기고 산장을 떠난다. 계약 카드는 버림패로 가지 않고 없어진다.
func dismiss() -> void:
	if dead or kind != "merc":
		return
	hand_over()
	if tree != null and tree.get("reserved") == self:
		tree["reserved"] = null
	if card_uid >= 0:
		game.cards.release(card_uid)
		card_uid = -1
	dead = true
	if game.get("equipment") != null:
		game.equipment.release_all(self)
	_leave_world()
	if hidden:
		queue_free()
	else:
		Fx.vanish(self, Color(1.0, 0.9, 0.65, 0.8), 0.5)


## 하수인 퇴장(시듦): 감독이 목재를 지급한 뒤 호출한다.
func wither_out() -> void:
	if dead:
		return
	dead = true
	_leave_world()
	Fx.wither(global_position + Vector3(0, 0.6, 0))
	Sfx.play(self, "minion_wither")
	Fx.vanish(self, Color(0.55, 0.75, 0.4, 0.8), 0.6)


## 큰 숲의 괴물의 걸음: 등의 가지에서 나뭇잎이 조금씩 떨어진다(표시 전용).
func _shed_leaves(delta: float, vel: Vector3) -> void:
	_leaf_t = ActorUtil.shed_leaves(_leaf_t, delta, global_position, vel)


func _leave_world() -> void:
	if tower != null and is_instance_valid(tower):
		tower.release(self)
	tower = null
	velocity = Vector3.ZERO
	remove_from_group("allies")
	remove_from_group("show_hp")
	collision_mask = 0
	if game.contracts != null:
		game.contracts.on_ally_removed(self)


## 도끼질에 맞은 나무가 움찔 흔들린다(외형만).
func _shake_tree(v: Node3D) -> void:
	if v == null or not is_instance_valid(v) or v.has_meta("fx_shake"):
		return
	v.set_meta("fx_shake", true)
	var base := v.rotation
	var tw := v.create_tween()
	tw.tween_property(v, "rotation", base + Vector3(0.05, 0, -0.05), 0.06)
	tw.tween_property(v, "rotation", base + Vector3(-0.03, 0, 0.03), 0.1)
	tw.tween_property(v, "rotation", base, 0.18).set_trans(Tween.TRANS_SINE)
	tw.tween_callback(func():
		if is_instance_valid(v):
			v.remove_meta("fx_shake"))


# ── 멈춤 감시 ──

## 움직이려는데 2.5초 동안 0.3m 도 못 갔으면 목적지가 막힌 것이다(구석·막힌 포켓·닿을 수 없는 나무).
## 상태별로 목적지를 버리고 다시 고른다. 벽에 부딪혀 제자리에서 진동하는 현상을 끊는다.
func _watch_stuck(vel: Vector3, delta: float) -> void:
	if vel.length() <= 0.05:
		_stuck_t = 0.0
		_stuck_ref = global_position
		return
	_stuck_t += delta
	if _stuck_t < 2.5:
		return
	var moved := _flat(_stuck_ref)
	_stuck_t = 0.0
	_stuck_ref = global_position
	if moved >= 0.3:
		return
	match state:
		State.PATROL:
			_pick_patrol_point()
		State.GO_WORK:
			failed_tree = tree
			if tree != null and tree.get("reserved") == self:
				tree["reserved"] = null
			tree = null
			game.contracts.assign_next_tree(self)
		State.IDLE, State.GATHER_RETURN:
			guard_point = game.contracts.yard_spot(self)
		State.GATHER_OUT:
			gather_index += 1
		State.TOWER_GO:
			# 사다리 앞이 막혔으면 가까울 때는 그냥 오르고, 멀면 탑을 포기한다
			if tower != null and _flat(tower.climb_spot()) <= 2.5:
				_climb()
			else:
				leave_tower()
		State.ENGAGE, State.HUNT, State.GUARD:
			# 대상이 닿을 수 없는 곳이면 놓아준다
			target = null
			prey = null
			if state != State.GUARD:
				if escort:
					state = State.ESCORT
				else:
					state = State.PATROL
					_pick_patrol_point()
		_:
			pass
