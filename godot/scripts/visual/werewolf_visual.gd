extends Node3D
## 보름달 늑대인간(마녀가 변신한 모습) — Tripo 파츠 묶음 모델(scenes/characters/werewolf_witch.tscn)과 절차 애니메이션.
## 원화 v03(회색 늑대인간, 사용자 승인 2026-10-21) → docs/character-3d-pipeline.md.
## 소유자(actors/player.gd)는 매 프레임 speed 만 넣고, 사건은 strike()(물기)·claw_swipe(side)(할퀴기)·set_pounce(t)(덮치기)·
## set_windup(k)(물기 선딜)·hurt()·roar()(변신)·impact(s)(타격 멈춤)로 알린다. 예전 블록아웃 wolf_visual.gd 와 같은 사건 이름이다.
##
## 성격: 흥분해 숨을 헐떡이는 사나운 늑대인간. 늘 등을 굽히고 어깨를 앞으로 내민 채, 팔은 무겁게 늘어뜨린다.
##   정지  : 빠르게 헐떡임(가슴·어깨 들썩, 머리 까딱, 2~3초마다 입김), 무게를 좌우로 옮기며 노려봄, 꼬리 낮게 흔들
##   달리기: 더 깊이 숙여 땅을 박차는 큰 보폭, 팔을 크게 앞뒤로 휘두르고, 착지마다 묵직하게 가라앉으며 눈이 튄다
##   물기  : 선딜에 머리를 젖혀 모았다가 상체째 내리꽂듯 물어뜯는다
##   할퀴기: 팔을 바깥 위로 크게 들었다가 대각선으로 베어 내림 — 좌우 번갈아, 상체가 같이 비튼다
##   덮치기: 웅크려 모았다가 몸을 수평으로 펴고 두 팔을 앞으로 뻗어 날아든 뒤 두 손으로 내리찍는다
##   변신  : 웅크렸다가 등을 젖히고 하늘을 향해 울부짖는다(1.1초)

const CharacterModels := preload("res://scripts/visual/character_models.gd")
const Fx := preload("res://scripts/visual/fx.gd")

const BITE_TIME := 0.26
const CLAW_TIME := 0.15
const ROAR_TIME := 1.1
const HURT_TIME := 0.22
const LAND_TIME := 0.32

var speed := 0.0

var body: Node3D               # 피벗 규약: player.gd·Fx 가 쓰는 몸 루트
var head: Node3D
var model: Node3D
var torso: Node3D
var arm_r: Node3D
var arm_l: Node3D
var fore_r: Node3D
var fore_l: Node3D
var leg_r: Node3D
var leg_l: Node3D
var tail: Node3D
var mouth: Node3D

var _t := 0.0
var _gait := 0.0
var _prev_step := 0.0
var _strike := 0.0
var _windup := 0.0
var _claw := 0.0
var _claw_side := 1.0
var _claw_combo := 0.0
var _pounce := -1.0
var _land := 0.0
var _hurt := 0.0
var _roar := 0.0
var _freeze := 0.0
var _freeze_amp := 0.0
var _breath_cd := 1.0
var _cur := {}                 # 노드 → 현재 회전(도)


func _ready() -> void:
	name = "WolfVisual"
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	model = CharacterModels.make_model_only("werewolf_witch")
	body.add_child(model)
	for n in model.find_children("*", "Node3D", true, false):
		match str(n.get_meta("part_group", "")):
			"torso": torso = n
			"head": head = n
			"arm_r": arm_r = n
			"arm_l": arm_l = n
			"fore_r": fore_r = n
			"fore_l": fore_l = n
			"leg_r": leg_r = n
			"leg_l": leg_l = n
			"tail": tail = n
	for n in _joints():
		_cur[n] = Vector3.ZERO
	# 입김·울음이 나오는 주둥이 끝(머리 묶음 기준, 장면 단위)
	mouth = Node3D.new()
	mouth.name = "Mouth"
	mouth.position = Vector3(-0.03, -0.03, 0.4)
	head.add_child(mouth)


func _joints() -> Array:
	return [torso, head, arm_r, arm_l, fore_r, fore_l, leg_r, leg_l, tail]


# ---------------------------------------------------------------- 사건

func strike() -> void:
	_strike = BITE_TIME
	_windup = 0.0


func set_windup(k: float) -> void:
	_windup = clampf(k, 0.0, 1.0)


func claw_swipe(side: float) -> void:
	_claw = CLAW_TIME
	_claw_side = signf(side) if side != 0.0 else 1.0
	_claw_combo = 0.55


## 덮치기 진행 0~1(음수면 끝 → 착지 반동).
func set_pounce(t: float) -> void:
	if t < 0.0 and _pounce >= 0.0:
		_land = LAND_TIME
	_pounce = t


func hurt() -> void:
	_hurt = HURT_TIME


func roar() -> void:
	_roar = ROAR_TIME
	_breath_cd = 0.45


## 타격 멈춤: 맞는 순간 자세를 잠깐 얼리고 떨게 한다(타격감). 세기 0~1.
func impact(strength := 0.5) -> void:
	_freeze = maxf(_freeze, lerpf(0.035, 0.09, clampf(strength, 0.0, 1.0)))
	_freeze_amp = maxf(_freeze_amp, 0.012 + 0.02 * strength)


# ---------------------------------------------------------------- 매 프레임

func _process(delta: float) -> void:
	if _freeze > 0.0:
		# 멈춘 동안 시간은 흐르지 않고 몸만 잘게 떤다
		_freeze -= delta
		body.position.x = randf_range(-_freeze_amp, _freeze_amp)
		body.position.z = randf_range(-_freeze_amp, _freeze_amp)
		if _freeze <= 0.0:
			_freeze_amp = 0.0
		return
	_t += delta
	_strike = maxf(_strike - delta, 0.0)
	_claw = maxf(_claw - delta, 0.0)
	_claw_combo = maxf(_claw_combo - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	_roar = maxf(_roar - delta, 0.0)
	_land = maxf(_land - delta, 0.0)

	var running := speed > 0.25 and _pounce < 0.0
	var stride := clampf(speed / 7.0, 0.0, 1.3)
	var pose := {}               # 노드 → 목표 회전(도)
	var off := Vector3.ZERO      # 몸 루트 위치
	var sq := Vector3.ONE        # 몸 늘이고 누르기
	var rate := 14.0             # 자세 따라가는 빠르기(동작 중엔 더 빠르게)

	# 헐떡임: 빠른 숨(초당 2.8회) — 가슴·어깨가 들썩이고 머리가 까딱인다
	var pant := sin(_t * TAU * 2.8)
	var pant2 := sin(_t * TAU * 2.8 + 0.9)
	var sway := sin(_t * 1.3)

	if running:
		_gait += delta * (7.5 + 5.5 * stride)
		var g := _gait
		var s := sin(g)
		var lift := absf(s)
		off.y = -0.04 + lift * 0.075 * stride
		pose[torso] = Vector3(30.0 + 6.0 * stride + lift * 4.0, s * 11.0, s * 4.0)
		pose[head] = Vector3(-26.0 + sin(2.0 * g) * 4.0, -s * 8.0, 0.0)
		pose[leg_r] = Vector3(-s * 48.0 * stride - 6.0, 0.0, -3.0)
		pose[leg_l] = Vector3(s * 48.0 * stride - 6.0, 0.0, 3.0)
		pose[arm_r] = Vector3(s * 58.0 * stride - 22.0, 0.0, -14.0)
		pose[arm_l] = Vector3(-s * 58.0 * stride - 22.0, 0.0, 14.0)
		pose[fore_r] = Vector3(-35.0 - maxf(s, 0.0) * 35.0, 0.0, 0.0)
		pose[fore_l] = Vector3(-35.0 - maxf(-s, 0.0) * 35.0, 0.0, 0.0)
		pose[tail] = Vector3(10.0 + sin(2.0 * g) * 7.0, s * 14.0, 0.0)
		sq = Vector3(1.0, 1.0 + (lift - 0.5) * 0.05 * stride, 1.0)
		# 발이 땅을 박차는 순간 눈 튀김(좌우 번갈아)
		if signf(s) != signf(_prev_step) and stride > 0.3:
			var foot: Node3D = leg_r if s > 0.0 else leg_l
			var back := -global_basis.z.normalized()
			Fx.snow_kick(foot.global_position * Vector3(1, 0, 1), back, 2, 1.25)
		_prev_step = s
		rate = 18.0
	else:
		_gait = 0.0
		_prev_step = 0.0
		# 웅크린 채 헐떡이며 노려보기: 무게를 좌우로 옮기고 고개를 천천히 돌린다
		off.y = -0.035 + pant * 0.006
		pose[torso] = Vector3(18.0 + pant * 2.5, sway * 6.0, sway * 3.0)
		pose[head] = Vector3(-14.0 - pant2 * 5.0, sin(_t * 0.55) * 16.0, 0.0)
		pose[leg_r] = Vector3(-8.0, 0.0, -5.0 - sway * 2.0)
		pose[leg_l] = Vector3(-8.0, 0.0, 5.0 - sway * 2.0)
		pose[arm_r] = Vector3(-14.0 + pant * 4.0, 0.0, -12.0 - pant * 3.0)
		pose[arm_l] = Vector3(-14.0 + pant * 4.0, 0.0, 12.0 + pant * 3.0)
		pose[fore_r] = Vector3(-24.0 + pant2 * 4.0, 0.0, 0.0)
		pose[fore_l] = Vector3(-24.0 + pant2 * 4.0, 0.0, 0.0)
		pose[tail] = Vector3(-12.0 + sin(_t * 1.1) * 5.0, sin(_t * 1.9) * 20.0, 0.0)
		sq = Vector3(1.0 + pant * 0.018, 1.0 - pant * 0.008, 1.0 + pant * 0.018)
		# 2~3초마다 거친 입김
		_breath_cd -= delta
		if _breath_cd <= 0.0 and is_visible_in_tree():
			_breath_cd = randf_range(1.8, 2.8)
			Fx.breath(mouth.global_position, global_basis.z, Color(1, 1, 1, 0.55), 1.15)

	# 물기 선딜: 머리를 젖혀 모으고 몸을 낮춘다
	if _windup > 0.0 and _strike <= 0.0:
		var w := _windup
		pose[torso] = pose[torso] + Vector3(-8.0, 0.0, 0.0) * w
		pose[head] = pose[head] + Vector3(-22.0, 0.0, 0.0) * w
		pose[arm_r] = pose[arm_r] + Vector3(18.0, 0.0, -10.0) * w
		pose[arm_l] = pose[arm_l] + Vector3(18.0, 0.0, 10.0) * w
		off.y -= 0.04 * w
		rate = 30.0

	# 물기: 젖혔다가 상체째 내리꽂으며 물어뜯기
	if _strike > 0.0:
		var p := 1.0 - _strike / BITE_TIME
		var lunge := _bell(p, 0.18, 0.42, 1.0)
		var back := _bell(p, 0.0, 0.12, 0.2) * 0.6
		pose[torso] = pose[torso] + Vector3(34.0 * lunge - 10.0 * back, 0.0, 0.0)
		pose[head] = pose[head] + Vector3(26.0 * lunge - 24.0 * back, 0.0, 0.0)
		pose[arm_r] = pose[arm_r] + Vector3(-55.0 * lunge, 0.0, -18.0 * lunge)
		pose[arm_l] = pose[arm_l] + Vector3(-55.0 * lunge, 0.0, 18.0 * lunge)
		off.z += 0.14 * lunge
		off.y -= 0.05 * lunge
		rate = 40.0

	# 할퀴기: 바깥 위로 크게 들었다가 대각선으로 베어 내림(좌우 번갈아)
	if _claw_combo > 0.0:
		var stance := clampf(_claw_combo / 0.2, 0.0, 1.0)
		pose[torso] = pose[torso] + Vector3(12.0, 0.0, 0.0) * stance
		off.y -= 0.05 * stance
		rate = 42.0
	if _claw > 0.0:
		var p2 := 1.0 - _claw / CLAW_TIME
		var raise := _bell(p2, 0.0, 0.25, 0.5)
		var cut := _bell(p2, 0.22, 0.55, 1.0)
		var sd := _claw_side
		var arm: Node3D = arm_r if sd > 0.0 else arm_l
		var fore: Node3D = fore_r if sd > 0.0 else fore_l
		var other: Node3D = arm_l if sd > 0.0 else arm_r
		var out := -1.0 if sd > 0.0 else 1.0     # 오른팔은 -z 가 바깥
		pose[arm] = Vector3(-130.0 * raise - 70.0 * cut, 22.0 * sd * cut, out * (55.0 * raise - 30.0 * cut))
		pose[fore] = Vector3(-50.0 * raise - 5.0 * cut, 0.0, 0.0)
		pose[other] = pose[other] + Vector3(20.0, 0.0, 0.0)
		pose[torso] = pose[torso] + Vector3(10.0 * cut, (-20.0 * raise + 26.0 * cut) * sd, 6.0 * sd * cut)
		pose[head] = pose[head] + Vector3(10.0 * cut, (10.0 * raise - 12.0 * cut) * sd, 0.0)

	# 덮치기: 웅크림 → 수평으로 펴고 두 팔 앞으로 뻗어 날아듦 → 두 손 내리찍기
	if _pounce >= 0.0:
		var k := _pounce
		var crouch := _bell(k, 0.0, 0.12, 0.22)
		var fly := _bell(k, 0.15, 0.45, 0.85)
		var smash := _bell(k, 0.75, 0.95, 1.0)
		var arc := sin(clampf((k - 0.12) / 0.8, 0.0, 1.0) * PI)
		off.y = -0.14 * crouch + 0.5 * arc - 0.06 * smash
		pose[torso] = Vector3(40.0 * crouch + 68.0 * fly + 50.0 * smash, 0.0, 0.0)
		pose[head] = Vector3(-10.0 * crouch - 55.0 * fly - 20.0 * smash, 0.0, 0.0)
		pose[arm_r] = Vector3(35.0 * crouch - 155.0 * fly - 80.0 * smash, 0.0, -10.0 - 15.0 * fly)
		pose[arm_l] = Vector3(35.0 * crouch - 155.0 * fly - 80.0 * smash, 0.0, 10.0 + 15.0 * fly)
		pose[fore_r] = Vector3(-30.0 * crouch - 10.0 * fly - 25.0 * smash, 0.0, 0.0)
		pose[fore_l] = Vector3(-30.0 * crouch - 10.0 * fly - 25.0 * smash, 0.0, 0.0)
		pose[leg_r] = Vector3(25.0 * crouch + 60.0 * fly - 20.0 * smash, 0.0, -4.0)
		pose[leg_l] = Vector3(25.0 * crouch + 50.0 * fly - 20.0 * smash, 0.0, 4.0)
		pose[tail] = Vector3(30.0 * fly, 0.0, 0.0)
		sq = Vector3(1.0 + 0.08 * crouch, 1.0 - 0.1 * crouch, 1.0 + 0.12 * fly)
		rate = 50.0

	# 착지 반동: 납작하게 눌렸다가 돌아온다
	if _land > 0.0:
		var l := _land / LAND_TIME
		off.y -= 0.07 * l
		sq = sq * Vector3(1.0 + 0.08 * l, 1.0 - 0.1 * l, 1.0 + 0.08 * l)
		pose[torso] = pose[torso] + Vector3(14.0 * l, 0.0, 0.0)

	# 변신 울부짖음: 웅크렸다가 등을 젖히고 하늘로
	if _roar > 0.0:
		var p3 := 1.0 - _roar / ROAR_TIME
		var curl := _bell(p3, 0.0, 0.15, 0.3)
		var howl := _bell(p3, 0.22, 0.4, 0.92)
		pose[torso] = Vector3(38.0 * curl - 16.0 * howl, 0.0, sin(_t * 40.0) * 2.0 * howl)
		pose[head] = Vector3(15.0 * curl - 50.0 * howl, 0.0, 0.0)
		pose[arm_r] = Vector3(10.0 * curl - 35.0 * howl, 0.0, -10.0 * curl - 62.0 * howl)
		pose[arm_l] = Vector3(10.0 * curl - 35.0 * howl, 0.0, 10.0 * curl + 62.0 * howl)
		pose[fore_r] = Vector3(-40.0 * curl - 50.0 * howl, 0.0, 0.0)
		pose[fore_l] = Vector3(-40.0 * curl - 50.0 * howl, 0.0, 0.0)
		pose[tail] = Vector3(-10.0 * curl + 35.0 * howl, 0.0, 0.0)
		off.y = -0.12 * curl + 0.04 * howl
		sq = Vector3(1.0 + 0.06 * curl, 1.0 - 0.08 * curl + 0.04 * howl, 1.0)
		rate = 22.0
		if howl > 0.5 and _breath_cd <= 0.0:
			_breath_cd = 0.12
			Fx.breath(mouth.global_position, global_basis.z + Vector3.UP, Color(0.85, 0.7, 1.0, 0.6), 1.3)
		_breath_cd -= delta

	# 피격: 움찔 젖히며 흔들림
	if _hurt > 0.0:
		var h := _hurt / HURT_TIME
		pose[torso] = pose[torso] + Vector3(-14.0 * h, 0.0, sin(_hurt * 70.0) * 6.0 * h)
		pose[head] = pose[head] + Vector3(-16.0 * h, 0.0, 0.0)
		off.z -= 0.05 * h

	# 적용: 목표 자세를 지수 감쇠로 따라간다(동작이 짧아도 끊기지 않게, 정지 자세로는 부드럽게)
	var a := 1.0 - exp(-rate * delta)
	for n: Node3D in _joints():
		var want: Vector3 = pose.get(n, Vector3.ZERO)
		var cur: Vector3 = _cur[n]
		cur = cur.lerp(want, a)
		_cur[n] = cur
		n.rotation_degrees = cur
	body.position = body.position.lerp(off, a)
	body.scale = body.scale.lerp(sq, a)


## 0 → 위로 → 0 인 종 모양(a 에서 시작, b 에서 정점, c 에서 끝).
static func _bell(x: float, a: float, b: float, c: float) -> float:
	if x <= a or x >= c:
		return 0.0
	if x < b:
		var u := (x - a) / maxf(b - a, 0.0001)
		return u * u * (3.0 - 2.0 * u)
	var v := (c - x) / maxf(c - b, 0.0001)
	return v * v * (3.0 - 2.0 * v)
