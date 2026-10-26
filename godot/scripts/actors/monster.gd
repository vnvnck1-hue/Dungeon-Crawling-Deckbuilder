extends CharacterBody3D
## 숲의 괴물: 출현 시 산장 또는 양을 목표로 배정. 플레이어가 근접하면 플레이어를 공격.
## 기본 개체는 가장 연약한 적이다. big=true는 카드로 변환되는 큰 숲의 괴물(덩치·체력이 크고 등에 가지, 걸을 때 잎이 떨어짐).
## configure(kind)로 적 종류를 바꾼다(볼륨 확장 E1, Cfg.ENEMY_KINDS): 침식된 자(원거리·주머니 저주), 맹독 곤충(빠름·독 포자),
## 공성 괴물(산장만 노림·산장 피해 3배), 보스 빈 굴의 주인(피해 상한·부름·전리품 카드).
## 기본 적은 서리 거미(kind "spider"): 시각 모델 spider_visual.gd가 IK 보행·깜빡임을 스스로 그리고, 이동은 달리다 멈칫한다.

const Cfg := preload("res://scripts/config.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const SoftSep := preload("res://scripts/actors/soft_separation.gd")
const Models := preload("res://scripts/visual/models.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
## 적 종류별 전용 소리(없으면 공용 괴물 소리). 2026-10-19 빈 소리 v02
const KIND_SFX := {
	"boss": {"spawn": "boss_roar", "roar": "boss_roar", "attack": "boss_attack", "die": "boss_die"},
	"cultist": {"spawn": "cultist_spawn", "hurt": "cultist_hurt", "die": "cultist_die"},
	"brute": {"spawn": "brute_spawn", "hurt": "brute_hurt", "die": "brute_die"},
}
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const SpiderVisual := preload("res://scripts/visual/spider_visual.gd")
const FrostVfx := preload("res://scripts/visual/vfx/frost_rune_vfx.gd")
## 괴물이 마녀 다음으로 노리는 대상 그룹(_pick_foe 가 이 순서로 훑는다)
const FOE_GROUPS := ["allies", "thorn_plants", "watchtowers"]

enum Goal { LODGE, SHEEP }

var game
var hp := 36.0
var max_hp := 36.0
var dead := false
var hp_offset := 1.5
var goal := Goal.LODGE
var attack_point := Vector3.ZERO
var target_sheep = null
var agent: NavigationAgent3D
var visual: Node3D
var body: Node3D
var attack_cd := 0.0
var engaged = null
var chase = null          # 쫓고 있는 적(마녀·용병·하수인·가시덩굴). _pick_foe() 가 고른다
var path_failed := false
var _repath_t := 0.0
var _stuck_t := 0.0
var _stuck_ref := Vector3.ZERO
var _anim_t := 0.0
var _lunge_t := 0.0
## 피격 반동(시각 모델에 hurt() 가 없는 종류: 숲의 괴물·침식된 자·맹독 곤충·공성 괴물·보스). 맞은 뒤 경과 초, 음수면 없음.
var _hurt_t := -1.0
const HURT_TIME := 0.42
## 카드 획득 대상(표식 개체). 처치자와 무관하게 사망 시 한 번만 카드를 준다(v0.3 §8).
var card_drop := ""
var _card_given := false
var big := false
var speed := Cfg.MONSTER_SPEED
var damage := Cfg.MONSTER_DAMAGE
var _leaf_t := 0.0
var _slows: Dictionary = {}  # 출처 -> [이동 배율, 남은 시간]. 서리 룬·수호 등불이 건다
var _frost_mark: MeshInstance3D
var kind := "forest"
var reach := Cfg.MONSTER_MELEE
var interval := Cfg.MONSTER_INTERVAL
var lodge_mult := 1.0
var ignore_units := false
var is_boss := false
var kind_scale := 1.0
var tint := Color(0, 0, 0, 0)
var _roar_t := Cfg.BOSS_ROAR_INTERVAL
var _cursed := false        # 이 개체가 이미 침식 카드를 넣었는지(개체당 한 번)
var _scuttle_t := 0.0       # 서리 거미: 현재 달리기/멈춤 구간의 남은 시간
var _scuttle_go := true
var _scuttle_k := 1.0
var _scuttle_pause := 0.25


func setup(g, hp_value: float, sheep_goal: bool) -> void:
	game = g
	hp = hp_value
	max_hp = hp_value
	goal = Goal.SHEEP if sheep_goal else Goal.LODGE


## 큰 숲의 괴물로 지정(_ready 전에 호출).
func make_big() -> void:
	big = true
	hp *= Cfg.BIG_MONSTER_HP_MULT
	max_hp = hp
	speed = Cfg.BIG_MONSTER_SPEED
	damage = Cfg.BIG_MONSTER_DAMAGE
	hp_offset = 1.95


## 적 종류 지정(setup 뒤, _ready 전에 호출). 기본 체력은 setup의 그 밤 체력에 hp_mult를 곱한다.
func configure(k: String) -> void:
	var d: Dictionary = Cfg.ENEMY_KINDS.get(k, Cfg.ENEMY_KINDS["forest"])
	kind = k if Cfg.ENEMY_KINDS.has(k) else "forest"
	hp = float(d["hp"]) if d.has("hp") else hp * float(d.get("hp_mult", 1.0))
	max_hp = hp
	speed = float(d["speed"])
	damage = float(d["damage"])
	interval = float(d["interval"])
	reach = float(d["reach"])
	lodge_mult = float(d.get("lodge_mult", 1.0))
	ignore_units = bool(d.get("ignore_units", false))
	kind_scale = float(d.get("scale", 1.0))
	tint = d.get("tint", Color(0, 0, 0, 0))
	if bool(d.get("big", false)):
		big = true
		hp_offset = 1.95 * kind_scale / Cfg.BIG_MONSTER_SCALE
	else:
		hp_offset = 1.5 * kind_scale
	if kind == "boss":
		is_boss = true
		card_drop = Cfg.BOSS_TROPHY


func display_name() -> String:
	return String(Cfg.ENEMY_KINDS.get(kind, {}).get("name", "숲의 괴물"))


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
	agent.path_desired_distance = 0.4
	agent.target_desired_distance = 0.2
	add_child(agent)
	if kind == "spider" and not big:
		visual = SpiderVisual.new()
	else:
		visual = Models.make_big_monster() if big else Models.make_monster()
	body = visual.get_node("Body")
	if kind != "forest" and kind != "spider":
		visual.scale *= kind_scale / (Cfg.BIG_MONSTER_SCALE if big else 1.0)
	add_child(visual)
	add_to_group("enemies")
	add_to_group("wave_enemies")
	SoftSep.register(self, 0.32 * kind_scale, 3.0 if big else 1.0)
	add_to_group("show_hp")
	if card_drop != "" and not is_boss:
		_add_card_mark()
	if tint.a > 0.0:
		_add_kind_mark()
	if is_boss:
		add_to_group("bosses")
	if goal == Goal.LODGE:
		attack_point = game.world.lodge.claim_attack_point(global_position)
	_anim_t = randf() * 10.0
	_stuck_ref = global_position
	Fx.spawn_portal(global_position)
	_sfx("spawn", "mon_big" if card_drop != "" else "mon_spawn")


func _add_card_mark() -> void:
	# 머리 위의 초록 빛 표식과 발밑 고리: 처치하면 카드를 얻는 개체
	var mark := B.node(self, Vector3(0, 2.45 if big else 1.75, 0), Vector3.ZERO, "CardMark")
	var orb := B.sphere(mark, 0.12, Vector3.ZERO, Mats.glow(Color(0.55, 1.0, 0.45), 5.0), Vector3.ONE, 8, 4)
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.omni(mark, Vector3.ZERO, Color(0.55, 1.0, 0.45), 0.8, 2.4, false, 1.2)
	var ring := B.torus(self, 0.45, 0.58, Vector3(0, 0.04, 0), Mats.unshaded_shared(Color(0.55, 1.0, 0.45, 0.7), true, true))
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.15, 1.0)
	var tw := mark.create_tween().set_loops()
	var y0 := mark.position.y
	tw.tween_property(mark, "position:y", y0 + 0.2, 0.6).set_trans(Tween.TRANS_SINE)
	tw.tween_property(mark, "position:y", y0, 0.6).set_trans(Tween.TRANS_SINE)


## 종류 표식: 머리 위의 작은 빛(침식된 자의 촛불, 곤충의 독빛, 공성 괴물의 불씨, 보스의 서리 눈). 표시 전용.
func _add_kind_mark() -> void:
	var y := 1.75 * kind_scale if not big else 2.0 * kind_scale
	var mark := B.node(self, Vector3(0, y, 0), Vector3.ZERO, "KindMark")
	var orb := B.sphere(mark, 0.1 * maxf(kind_scale, 0.8), Vector3.ZERO, Mats.glow(tint, 4.0), Vector3.ONE, 8, 4)
	orb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.omni(mark, Vector3.ZERO, tint, 0.7, 2.0 * kind_scale, false, 1.0)


## 먼저 공격할 적(마녀·용병·하수인·가시덩굴): 가는 길 Cfg.MONSTER_AGGRO 안의 가장 가까운 대상.
## 한번 쫓기 시작하면 Cfg.MONSTER_LEASH 보다 멀어지거나 쓰러지거나 산장에 숨을 때까지 쫓는다.
## 산장만 노리는 공성 괴물(ignore_units)은 적을 상대하지 않는다.
func _pick_foe():
	if ignore_units:
		return null
	if game.get("merc_kit") != null:
		var taunted = game.merc_kit.taunt_of(self)  # 도발(철테 방패·결투·냄비 투구 함성)
		if taunted != null and _foe_valid(taunted):
			chase = taunted
			return chase
	if _foe_valid(chase) and _foe_dist(chase) <= Cfg.MONSTER_LEASH:
		return chase
	chase = null
	var best_d := maxf(Cfg.MONSTER_AGGRO, reach)
	best_d = _closer_foe(game.player, best_d)
	# 매 틱 도는 경로라 그룹을 이어 붙인 새 배열을 만들지 않고 그룹마다 같은 순서로 훑는다
	for group in FOE_GROUPS:
		for a in get_tree().get_nodes_in_group(group):
			best_d = _closer_foe(a, best_d)
	return chase


## _pick_foe 의 한 후보: best_d 이하로 가까우면 chase 로 삼고 새 최단 거리를 돌려준다.
func _closer_foe(a, best_d: float) -> float:
	if not _foe_valid(a):
		return best_d
	var d := _foe_dist(a)
	if d <= best_d:
		chase = a
		return d
	return best_d


## 주변의 아군 대상(용병·하수인·가시덩굴, 마녀 제외) 중 가장 가까운 것. 검증 도구가 쓴다.
func _nearest_ally():
	if ignore_units:
		return null
	var best = null
	var best_d := maxf(Cfg.MONSTER_AGGRO, reach)
	for a in get_tree().get_nodes_in_group("allies") + get_tree().get_nodes_in_group("thorn_plants"):
		if _foe_valid(a) and _flat(a.global_position) <= best_d:
			best_d = _flat(a.global_position)
			best = a
	return best


func _foe_valid(a) -> bool:
	# 감시탑 위 사냥꾼은 직접 칠 수 없다(탑을 친다)
	if a != null and is_instance_valid(a) and game.get("merc_kit") != null and game.merc_kit.stealthed(a):
		return false  # 매복 중인 사야
	return a != null and is_instance_valid(a) and not a.dead and a.get(&"hidden") != true and a.get(&"on_tower") != true


## 대상까지 평면 거리. 감시탑처럼 덩치 있는 대상은 발치(foe_radius)까지로 잰다.
func _foe_dist(a) -> float:
	var r = a.get(&"foe_radius")
	return _flat(a.global_position) - (float(r) if r != null else 0.0)


func _flat(p: Vector3) -> float:
	return ActorUtil.flat_dist(p, global_position)


func _physics_process(delta: float) -> void:
	if dead:
		return
	var lodge = game.world.lodge
	var pasture = game.world.pasture
	var player = game.player
	var attack_target = null
	var face_point := global_position
	var move_target := global_position

	var foe = _pick_foe()
	if is_boss:
		_tick_roar(delta)
	if foe != null and _foe_dist(foe) <= reach:
		# 주변의 적(마녀·용병·하수인·가시덩굴)을 산장·양보다 먼저 공격한다
		attack_target = foe
		face_point = foe.global_position
	elif foe != null:
		move_target = foe.global_position
	else:
		if goal == Goal.SHEEP:
			if target_sheep == null or not is_instance_valid(target_sheep) or target_sheep.dead:
				target_sheep = pasture.nearest_alive_sheep(global_position)
				if target_sheep == null:
					goal = Goal.LODGE
					attack_point = lodge.claim_attack_point(global_position)
		if goal == Goal.SHEEP:
			move_target = target_sheep.global_position
			# 울타리 너머로 공격하지 않도록 목장 안에 들어왔을 때만 공격
			if _flat(move_target) <= Cfg.MONSTER_MELEE and pasture.inside(global_position, 0.05):
				attack_target = target_sheep
				face_point = move_target
		else:
			move_target = attack_point
			if lodge.distance_to(global_position) <= reach:
				attack_target = lodge
				face_point = lodge.closest_point(global_position)

	if attack_target != null:
		velocity = SoftSep.push(self)   # 공격 중에도 겹친 동료와는 천천히 벌어진다
		_face(face_point - global_position, delta)
		if attack_target != engaged:
			engaged = attack_target
			attack_cd = 0.5
		attack_cd -= delta
		if attack_cd <= 0.0:
			attack_cd = interval
			_lunge_t = 0.35
			if reach > 2.0:
				# 원거리(침식된 자): 대상 자리에 보랏빛 저주가 터진다
				Fx.hit(face_point + Vector3(0, 0.9, 0), tint if tint.a > 0.0 else Color(0.75, 0.35, 1.0))
			else:
				Fx.claw(global_position + Vector3(0, 0.7, 0), face_point - global_position)
			if visual.has_method("strike"):
				visual.strike(face_point)
			_sfx("attack", "mon_attack")
			var out := 1.0
			if game.get("merc_kit") != null:
				out = game.merc_kit.enemy_out_mult(self, attack_target)  # 재 구름 · 타크 미끄러짐
			if attack_target == lodge:
				lodge.take_damage(damage * lodge_mult * out, self)
				if kind == "cultist":
					_curse("corrupt_prayer", "침식된 자의 기도가 산장에 스몄습니다")
			else:
				if attack_target.is_in_group("watchtowers"):
					attack_target.take_damage(damage * lodge_mult * out, self)
				else:
					attack_target.take_damage(damage * out)
				if kind == "insect" and attack_target == player:
					_curse("poison_spore", "맹독 곤충의 포자가 주머니에 들어왔습니다")
		_stuck_t = 0.0
		_stuck_ref = global_position
	else:
		engaged = null
		_repath_t -= delta
		if _repath_t <= 0.0:
			agent.target_position = move_target
			_repath_t = 0.35
		var next := agent.get_next_path_position()
		var dir := next - global_position
		dir.y = 0.0
		var v := Vector3.ZERO
		if dir.length() > 0.05:
			v = dir.normalized() * speed * slow_factor() * _scuttle(delta)
		velocity = v + SoftSep.push(self)
		if v.length() > 0.05:
			_face(v, delta)
			if big:
				_shed_leaves(delta, v)
		_check_stuck(delta)
	_tick_slows(delta)
	if not dead:
		move_and_slide()
		global_position.y = 0.0
		if not visual.has_method("strike"):   # 서리 거미는 시각 모델이 스스로 움직인다
			_animate(delta, attack_target == null)


## 감속: 같은 출처는 갱신하고, 여러 출처가 겹치면 가장 강한 배율만 적용한다.
func apply_slow(source: String, factor: float, duration: float) -> void:
	if dead:
		return
	var cur = _slows.get(source)
	if cur == null or cur[1] < duration:
		_slows[source] = [factor, duration]
	_sync_frost_mark()


func slow_factor() -> float:
	var f := 1.0
	for k in _slows:
		f = minf(f, _slows[k][0])
	if game != null and game.get("relics") != null and game.relics != null:
		f *= game.relics.enemy_speed_mult()
	return f


func _tick_slows(delta: float) -> void:
	if _slows.is_empty():
		return
	for k in _slows.keys():
		_slows[k][1] -= delta
		if _slows[k][1] <= 0.0:
			_slows.erase(k)
	_sync_frost_mark()


## 느려진 동안 발밑에 서리 자국이 번져 있다가, 풀리면 녹아 사라진다(표시 전용).
func _sync_frost_mark() -> void:
	var on := not _slows.is_empty() and not dead
	if on and _frost_mark == null:
		_frost_mark = FrostVfx.slow_mark(self)
	if _frost_mark != null:
		if on and not _frost_mark.get_meta("frost_on", false):
			Sfx.play(self, "slow_apply")
		FrostVfx.set_slow_mark(_frost_mark, on)


## 걸을 때 등의 가지에서 나뭇잎이 조금씩 떨어진다(표시 전용).
func _shed_leaves(delta: float, vel: Vector3) -> void:
	_leaf_t = ActorUtil.shed_leaves(_leaf_t, delta, global_position, vel)


## 서리 거미의 '달리다 멈칫': 0.9~1.6초 내달리고 0.18~0.32초 얼어붙는다. 평균 속도가 원래와 같도록 달리는 구간을 빠르게 한다.
func _scuttle(delta: float) -> float:
	if kind != "spider" or big:
		return 1.0
	_scuttle_t -= delta
	if _scuttle_t <= 0.0:
		_scuttle_go = not _scuttle_go
		if _scuttle_go:
			var run := randf_range(0.9, 1.6)
			var pause := randf_range(0.18, 0.32)
			_scuttle_t = run
			# 멈춤 구간 속도 0.08 → 달리는 구간 배율 = (run + pause - 0.08·pause) / run
			_scuttle_k = (run + pause - 0.08 * pause) / run
			_scuttle_pause = pause
		else:
			_scuttle_t = _scuttle_pause
	return _scuttle_k if _scuttle_go else 0.08


func _check_stuck(delta: float) -> void:
	_stuck_t += delta
	if _stuck_t >= 3.0:
		var moved := _flat(_stuck_ref)
		if moved < 0.3:
			if not path_failed:
				push_warning("몬스터 경로 실패: %s" % str(global_position))
			path_failed = true
			if goal == Goal.LODGE:
				attack_point = game.world.lodge.claim_attack_point(global_position)
		else:
			path_failed = false
		_stuck_t = 0.0
		_stuck_ref = global_position


func _face(dir: Vector3, delta: float) -> void:
	ActorUtil.face(visual, dir, delta, 8.0)


func _animate(delta: float, walking: bool) -> void:
	_anim_t += delta * (7.0 if walking else 2.0)
	body.position.y = absf(sin(_anim_t)) * (0.07 if walking else 0.02)
	body.rotation.z = sin(_anim_t * 0.5) * 0.08
	if _lunge_t > 0.0:
		_lunge_t -= delta
		var k := sin(clampf(_lunge_t / 0.35, 0.0, 1.0) * PI)
		body.position.z = k * 0.3
		body.rotation.x = k * 0.35
	else:
		body.position.z = 0.0
		body.rotation.x = 0.0
	_animate_hurt(delta)


## 피격 반동: 맞는 순간 뒤로 확 젖혀지며 납작하게 눌렸다가(0.04초에 정점), 출렁이며 돌아온다. 보스·공성 괴물은 덜 밀린다.
func _animate_hurt(delta: float) -> void:
	if _hurt_t < 0.0:
		return
	_hurt_t += delta
	if _hurt_t >= HURT_TIME:
		_hurt_t = -1.0
		body.scale = Vector3.ONE
		return
	var t := _hurt_t
	var snap := minf(t / 0.04, 1.0)
	var recoil := snap * exp(-maxf(t - 0.04, 0.0) * 9.0) * cos(maxf(t - 0.04, 0.0) * 22.0)
	var heavy := 0.45 if is_boss else (0.7 if big else 1.0)
	body.rotation.x += -0.5 * recoil * heavy
	body.position.z += -0.18 * recoil * heavy
	body.rotation.z += sin(t * 55.0) * 0.1 * exp(-t * 10.0) * heavy
	var squash := snap * exp(-maxf(t - 0.04, 0.0) * 14.0) * heavy
	body.scale = Vector3(1.0 + 0.14 * squash, 1.0 - 0.18 * squash, 1.0 + 0.14 * squash)


## 침식 카드: 개체당 한 번, 한 밤 상한까지 주머니에 넣는다(ChapterDirector가 상한을 센다).
func _curse(card_id: String, why: String) -> void:
	if _cursed or game == null or game.get("chapter") == null or game.chapter == null:
		return
	_cursed = true
	game.chapter.add_corruption(card_id, why)


## 보스의 부름: 일정 간격으로 숲의 괴물을 곁에 불러내고 저주의 속삭임을 남긴다.
func _tick_roar(delta: float) -> void:
	_roar_t -= delta
	if _roar_t > 0.0:
		return
	_roar_t = Cfg.BOSS_ROAR_INTERVAL
	for i in Cfg.BOSS_ROAR_SPAWN:
		var a := randf() * TAU
		game.waves.spawn_extra(global_position + Vector3(cos(a), 0, sin(a)) * 1.8, "spider")
	if game.get("world") != null:
		game.world.shake(0.2, 0.4)
	_sfx("roar", "mon_big")
	game.toast("%s의 울부짖음 — 서리 거미가 깨어납니다" % display_name(), Color(0.7, 0.85, 1.0))
	if game.get("chapter") != null and game.chapter != null:
		game.chapter.add_corruption("cursed_whisper", "보스의 울부짖음이 저주를 남겼습니다")


func take_damage(amount: float) -> void:
	if dead:
		return
	if game != null and game.get("merc_kit") != null:
		amount *= game.merc_kit.enemy_taken_mult(self)  # 사냥 표식
	if is_boss:
		amount = minf(amount, Cfg.BOSS_HIT_CAP)
	hp -= amount
	Fx.flash(visual)
	if visual.has_method("hurt") and hp > 0.0:
		visual.hurt()
	elif hp > 0.0:
		_hurt_t = 0.0
	Fx.damage_number(get_parent(), global_position + Vector3(0, 1.9, 0), amount)
	if hp <= 0.0:
		die()
	else:
		_sfx("hurt", "mon_hit")


func _sfx(what: String, fallback: String) -> void:
	Sfx.play_or(self, KIND_SFX.get(kind, {}).get(what, fallback), fallback)


func die() -> void:
	dead = true
	if game != null and game.get("merc_kit") != null:
		game.merc_kit.on_enemy_died(self)  # 회복 꽃·전리품·수인 둘
	hp = 0.0
	velocity = Vector3.ZERO
	remove_from_group("enemies")
	remove_from_group("wave_enemies")
	remove_from_group("show_hp")
	collision_mask = 0
	_sfx("die", "mon_die")
	# 처치 골드: 동전이 흩뿌려지며 소량의 골드(scripts/game/kill_gold.gd)
	if game.get("kill_gold") != null:
		game.kill_gold.on_enemy_killed(self)
	if card_drop != "" and not _card_given:
		_card_given = true
		game.cards.add(card_drop)
		if is_boss:
			game.toast("%s을(를) 쓰러뜨렸습니다 — 전리품 '%s' 카드!" % [display_name(), game.cards.def(card_drop).get("name", card_drop)], Color(0.7, 0.9, 1.0))
		else:
			game.toast("큰 숲의 괴물을 쓰러뜨려 숲의 괴물 카드를 얻었습니다!", Color(0.6, 1.0, 0.55))
		Fx.celebrate(global_position + Vector3(0, 1.0, 0), Color(0.55, 1.0, 0.45))
		Sfx.play(self, "mon_drop")
	if visual.has_method("die_curl"):
		# 서리 거미: 뒤집히며 다리를 오므린 뒤 사라진다
		visual.die_curl()
		get_tree().create_timer(visual.DEATH_TIME, false).timeout.connect(func(): if is_instance_valid(self): Fx.vanish(self))
		return
	Fx.vanish(self)
