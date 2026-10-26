extends Node
## 파츠 묶음 캐릭터(Tripo Segment → tools/tripo_character_ingest.gd)의 절차적 애니메이션.
## 묶음 피벗(meta part_group: torso·head·arm_r·arm_l·leg_r·leg_l·backpack·cape·lantern·wing_r·wing_l·tail)을 돌려 움직인다.
## 상태: walk(걷기) · idle(서 있기) · greet(문 앞 인사) · wave(떠나며 손 흔들기)
##       windup(지팡이 공격 준비, amount 0→1) · cast(마법 발사) · work(양털 깎기) · hurt(괴로워 움츠림).
## 직업(용병, docs/mercenary-jobs-design.md): chop(도끼질, amount = 한 번 찍는 주기 0→1) · pick(채집 줍기, amount 0→1) ·
##       lookout(감시탑 위 경계) · flee(산장으로 대피) — 반복 상태.
##       action("slash"|"draw"|"stab") — 한 번 하는 공격(전투용병 베기 / 사냥꾼 활 당겨 쏘기 / 하수인 들이받기). 반복 상태 위에 덮어 그린다.
##       공격 = 느린 예비 동작(ease-in) → 임팩트로 순식간에 꽂힘(지수 감속 + 살짝 넘침) → 그 자세로 멈춤 → 회복.
##       임팩트 순간 freeze(초)로 자세를 얼려(타격 멈춤) 타격감을 준다. 시간표는 ACTIONS, 임팩트 시각은 impact_time().
##       flinch() — 맞았을 때 움찔(어느 상태에든 겹친다).
## 수치는 style 사전(character_models.gd)에서 캐릭터 성격에 맞게 고친다. 게임 판정·이동에는 관여하지 않는다.

var state := "idle"
var amount := 0.0               # windup 진행도 등 상태별 입력(0~1)
var style: Dictionary = {}
var pivots: Dictionary = {}     # 묶음 → Node3D
var _rest: Dictionary = {}      # 묶음 → 기본 위치
var _t := 0.0                   # 상태 안 경과 시간
var _phase := 0.0               # 걸음 위상
var _swing := 0.0               # 등불·망토의 출렁임(걷기 속도를 따라 천천히 오르내림)
## 손에 쥔 직업 도구(ally.gd 가 넣는다): bow·bow_string·arrow 등. 상태별로 자세를 맞춘다.
var props: Dictionary = {}
var _action := ""               # 진행 중인 한 번짜리 공격
var _act_t := 0.0
var _freeze := 0.0              # 타격 멈춤 남은 시간
var _flinch := 0.0

## 한 번짜리 공격 시간표(초): 예비 동작 → 꽂기 → 멈춤 → 회복. 임팩트 = wind + strike.
const ACTIONS := {
	"slash": {"wind": 0.24, "strike": 0.06, "hold": 0.1, "recover": 0.26},
	"draw": {"wind": 0.34, "strike": 0.05, "hold": 0.12, "recover": 0.3},
	"stab": {"wind": 0.18, "strike": 0.05, "hold": 0.08, "recover": 0.22},
}
## 도끼질 한 주기 안의 임팩트 위치(0~1). ally.gd 가 이 순간에 나무 파편·흔들림·소리를 낸다.
const CHOP_IMPACT := 0.64


func setup(root: Node3D, style_: Dictionary) -> void:
	style = style_
	for n in root.find_children("*", "Node3D", true, false):
		if n.has_meta("part_group"):
			pivots[str(n.get_meta("part_group"))] = n
			_rest[str(n.get_meta("part_group"))] = (n as Node3D).position


func play(next: String) -> void:
	if next == state: return
	state = next
	_t = 0.0


## 한 번짜리 공격 시작. 임팩트까지 걸리는 시간을 돌려준다(판정·화살 발사를 그 순간에 맞춘다).
func action(kind: String) -> float:
	_action = kind
	_act_t = 0.0
	return impact_time(kind)


static func impact_time(kind: String) -> float:
	var a: Dictionary = ACTIONS.get(kind, ACTIONS["slash"])
	return float(a.wind) + float(a.strike)


func busy() -> bool:
	return _action != ""


## 타격 멈춤: 자세를 그대로 얼린다(그동안 시간이 흐르지 않는다).
func freeze(t: float) -> void:
	_freeze = maxf(_freeze, t)


func flinch() -> void:
	_flinch = 0.2


# ---------------------------------------------------------------- 이징(공격의 급격한 임팩트)

static func ease_in_cubic(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * x


static func ease_in_out(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## 지수 감속: 첫 몇 프레임에 거의 다 가 버린다(꽂히는 순간).
static func ease_out_expo(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return 1.0 if x >= 1.0 else 1.0 - pow(2.0, -10.0 * x)


## 지수 감속 + 살짝 넘침(임팩트에서 목표를 지나쳤다 되돌아옴). x 0→1 에서 0→(1+넘침)→1.
static func ease_out_snap(x: float, over := 0.12) -> float:
	x = clampf(x, 0.0, 1.0)
	return ease_out_expo(x) + over * sin(clampf(x, 0.0, 1.0) * PI) * (1.0 - x * 0.5)


func _s(key: String, fallback: float) -> float:
	return float(style.get(key, fallback))


func _rot(group: String, deg: Vector3) -> void:
	if pivots.has(group): pivots[group].rotation_degrees = deg


func _add(group: String, deg: Vector3) -> void:
	if pivots.has(group): pivots[group].rotation_degrees += deg


## 반복 상태가 정한 자세 위에 공격 자세를 w 만큼 덮는다(회복 때 w 가 줄며 원래 자세로 돌아간다).
func _over(group: String, deg: Vector3, w: float) -> void:
	if pivots.has(group): pivots[group].rotation_degrees = pivots[group].rotation_degrees.lerp(deg, w)


func _prop(name: String) -> Node3D:
	var p = props.get(name)
	return p if p != null and is_instance_valid(p) else null


func _lift(group: String, y: float) -> void:
	if pivots.has(group): pivots[group].position = _rest[group] + Vector3(0, y, 0)


func _process(delta: float) -> void:
	if _freeze > 0.0:
		# 타격 멈춤: 자세를 얼린 채 몸통만 잘게 떤다
		_freeze -= delta
		if pivots.has("torso"):
			pivots["torso"].position = _rest["torso"] + Vector3(randf_range(-0.01, 0.01), 0, randf_range(-0.01, 0.01))
		return
	_t += delta
	_swing = move_toward(_swing, 1.0 if state in ["walk", "wave", "flee"] else 0.0, delta * 2.5)
	match state:
		"walk": _walk(delta)
		"greet": _greet()
		"wave": _walk(delta); _wave_arm()
		"windup": _windup()
		"cast": _cast()
		"work": _work()
		"hurt": _hurt()
		"chop": _chop()
		"pick": _pick()
		"lookout": _lookout()
		"flee": _flee(delta)
		_: _idle()
	_props_rest()
	if _action != "":
		_act_t += delta
		var a: Dictionary = ACTIONS[_action]
		if _act_t >= float(a.wind) + float(a.strike) + float(a.hold) + float(a.recover):
			_action = ""
		else:
			match _action:
				"slash": _slash(a)
				"draw": _draw(a)
				"stab": _stab(a)
	if _flinch > 0.0:
		_flinch -= delta
		var f := _flinch / 0.2
		_add("torso", Vector3(-10.0 * f, 0, sin(_flinch * 60.0) * 4.0 * f))
		_add("head", Vector3(-14.0 * f, 0, 0))
	_bow_align()
	_secondary(delta)


func _walk(delta: float) -> void:
	_phase += delta * _s("walk_freq", 9.0)
	var s := sin(_phase)
	var hop := absf(s)
	var leg := _s("leg_swing", 30.0)
	var arm := _s("arm_swing", 24.0)
	var staff_arm := _s("staff_arm_swing", arm)   # 지팡이를 쥔 왼팔은 덜 흔든다
	_lift("torso", hop * _s("walk_bounce", 0.045))
	_rot("torso", Vector3(_s("walk_lean", 6.0), 0, s * _s("walk_roll", 4.0)))
	_rot("leg_r", Vector3(s * leg, 0, 0))
	_rot("leg_l", Vector3(-s * leg, 0, 0))
	_rot("arm_r", Vector3(-s * arm, 0, -8))
	_rot("arm_l", Vector3(s * staff_arm + _s("staff_arm_x", 0.0), 0, 8))
	_rot("head", Vector3(-hop * _s("head_bob", 5.0), sin(_phase * 0.5) * _s("head_look", 6.0), -s * 3.0))
	# 무거운 등짐은 반 박자 늦게 출렁인다.
	_rot("backpack", Vector3(sin(_phase - 1.2) * _s("pack_sway", 7.0), 0, sin(_phase * 0.5 - 1.0) * 3.0))


func _idle() -> void:
	var b := sin(_t * 2.2)
	_lift("torso", 0.0)
	_rot("torso", Vector3(b * 1.5, 0, 0))
	_rot("leg_r", Vector3.ZERO)
	_rot("leg_l", Vector3.ZERO)
	_rot("arm_r", Vector3(0, 0, -6 - b * 2.0))
	_rot("arm_l", Vector3(_s("staff_arm_x", 0.0), 0, 6 + b * 2.0))
	# 고개 돌리기: 니브는 두리번(넓고 잦게), 마녀는 가끔 천천히 주변을 살핀다.
	var look := sin(_t * _s("idle_look_freq", 0.7))
	_rot("head", Vector3(-b * 2.0, look * _s("idle_look", 18.0), 0))
	_rot("backpack", Vector3(b * 1.5, 0, 0))


## 흥정꾼 인사: 한 손을 내밀어 손가락을 비비고(값 얘기), 고개를 갸웃하며 깡충 뛴다.
func _greet() -> void:
	var t := _t
	var rub := sin(t * 22.0)
	var hop := maxf(0.0, sin(t * 7.0))
	var up := clampf(t / 0.25, 0.0, 1.0)
	_lift("torso", hop * 0.035)
	_rot("torso", Vector3(-4.0 * up, 0, 0))
	_rot("arm_r", Vector3(-75.0 * up + rub * 6.0, 0, -18.0 + rub * 5.0))
	_rot("arm_l", Vector3(-20.0 * up, 0, 30.0 * up))
	_rot("head", Vector3(-6.0 * up, 12.0 * up, 14.0 * up + sin(t * 5.0) * 4.0))
	_rot("leg_r", Vector3(-hop * 10.0, 0, 0))
	_rot("leg_l", Vector3(hop * 6.0, 0, 0))
	_rot("backpack", Vector3(hop * 6.0, 0, 0))


## 떠나며 뒤돌아 손 흔들기(걷기와 겹친다).
func _wave_arm() -> void:
	# 큰 귀·머리에 가리지 않도록 머리 위가 아니라 바깥 비스듬히 앞으로 들어 흔든다.
	_rot("arm_l", Vector3(-35, 0, 95 + sin(_t * 14.0) * 22.0))
	_rot("head", Vector3(0, -20, 8))


## 공격 준비: 지팡이 팔을 앞으로 들어 올리고 대상을 똑바로 본다(침착하게, 몸은 거의 그대로).
func _windup() -> void:
	var k := clampf(amount, 0.0, 1.0)
	_lift("torso", 0.0)
	_rot("torso", Vector3(-4.0 * k, 0, 0))
	_rot("leg_r", Vector3(-6.0 * k, 0, 0))
	_rot("leg_l", Vector3(6.0 * k, 0, 0))
	_rot("arm_l", Vector3(_s("staff_arm_x", 0.0) - 55.0 * k, 0, 10.0 + 10.0 * k))
	_rot("arm_r", Vector3(-10.0 * k, 0, -14.0 - 10.0 * k))
	_rot("head", Vector3(6.0 * k, 0, 0))


## 발사: 지팡이 팔을 짧게 앞으로 내지르고 돌아온다(0.3초).
func _cast() -> void:
	var p := sin(clampf(_t / 0.3, 0.0, 1.0) * PI)
	_rot("torso", Vector3(5.0 * p, 0, 0))
	_rot("arm_l", Vector3(_s("staff_arm_x", 0.0) - 55.0 - 30.0 * p, 0, 18.0))
	_rot("arm_r", Vector3(0, 0, -20.0 - 10.0 * p))
	_rot("head", Vector3(4.0 * p, 0, 0))
	_rot("cape", Vector3(-18.0 * p, 0, 0))


## 양털 깎기: 오른손(가위)을 앞으로 내밀어 빠르게 여닫고, 고개를 숙여 손끝을 본다.
func _work() -> void:
	var snip := sin(_t * 18.0)
	_rot("arm_r", Vector3(-60.0 + snip * 6.0, 0, -12.0))
	_rot("arm_l", Vector3(-15.0, 0, 18.0))
	_rot("head", Vector3(16.0, -8.0, 0))
	_rot("leg_r", Vector3(-8.0, 0, 0))
	_rot("leg_l", Vector3(8.0, 0, 0))


## 괴로움(늑대의 피 등): 두 팔로 몸을 감싸고 고개를 숙이며 떤다. 몸 전체 흔들림은 플레이어 쪽이 맡는다.
func _hurt() -> void:
	var shake := sin(_t * 40.0) * 4.0
	_rot("arm_r", Vector3(-40.0 + shake, 25.0, -5.0))
	_rot("arm_l", Vector3(-40.0 - shake, -25.0, 5.0))
	_rot("head", Vector3(22.0, shake, 0))


# ---------------------------------------------------------------- 직업 반복 동작

## 도끼질 한 주기: 머리 위 뒤로 천천히 끌어올림(ease-in-out) → 순식간에 내리찍음(지수 감속 + 넘침) → 박힌 채 부르르 → 뽑아 들며 회복.
func _chop() -> void:
	var u := fposmod(amount, 1.0)
	var arm := -35.0       # 오른팔(도끼) 앞뒤 각도: 기본 -35 · 머리 위 -175 · 찍힌 자리 -72
	var lean := 0.0        # 상체 숙임(도)
	var drop := 0.0
	if u < 0.5:
		var k := ease_in_out(u / 0.5)
		arm = lerpf(-35.0, -175.0, k)
		lean = -12.0 * k
	elif u < CHOP_IMPACT:
		var k2 := ease_out_snap((u - 0.5) / (CHOP_IMPACT - 0.5), 0.1)
		arm = lerpf(-175.0, -72.0, k2)
		lean = lerpf(-12.0, 30.0, k2)
		drop = k2
	elif u < 0.78:
		arm = -72.0 + sin((u - CHOP_IMPACT) * 160.0) * 2.5   # 박힌 도끼가 부르르
		lean = 30.0
		drop = 1.0
	else:
		var r := ease_in_out((u - 0.78) / 0.22)
		arm = lerpf(-72.0, -35.0, r)
		lean = lerpf(30.0, 0.0, r)
		drop = 1.0 - r
	_lift("torso", -0.035 * drop)
	_rot("torso", Vector3(lean, -8.0, 0))
	_rot("arm_r", Vector3(arm, 0, -6))
	_rot("arm_l", Vector3(arm + 14.0, 0, 12))
	_rot("head", Vector3(clampf(lean * 0.5, -6.0, 14.0), 0, 0))
	_rot("leg_r", Vector3(-14.0, 0, -4))
	_rot("leg_l", Vector3(12.0, 0, 4))


## 채집 줍기(3초): 쪼그려 앉아 손을 뻗어 집고 → 등 바구니에 넣기를 두 번 되풀이한다.
func _pick() -> void:
	var u := fposmod(amount * 2.0, 1.0)
	var crouch := ease_in_out(u / 0.25) * (1.0 - ease_in_out((u - 0.6) / 0.2))
	var reach := ease_in_out((u - 0.15) / 0.2) * (1.0 - ease_in_out((u - 0.45) / 0.15))
	var toss := ease_in_out((u - 0.6) / 0.15) * (1.0 - ease_in_out((u - 0.85) / 0.15))
	_lift("torso", -0.09 * crouch)
	_rot("torso", Vector3(38.0 * crouch - 6.0 * toss, 0, 0))
	_rot("leg_r", Vector3(-35.0 * crouch, 0, -6.0 * crouch))
	_rot("leg_l", Vector3(-35.0 * crouch, 0, 6.0 * crouch))
	_rot("arm_r", Vector3(-55.0 * reach - 165.0 * toss, 0, -10.0 + 8.0 * toss))
	_rot("arm_l", Vector3(-30.0 * crouch, 0, 14.0))
	_rot("head", Vector3(22.0 * crouch - 10.0 * toss, -10.0 * toss, 0))


## 감시탑 위 경계(겨눌 적이 없을 때): 한 손을 이마에 대고 천천히 먼 곳을 훑는다.
func _lookout() -> void:
	var scan := sin(_t * 0.5)
	_lift("torso", 0.0)
	_rot("torso", Vector3(4.0, scan * 18.0, 0))
	_rot("arm_r", Vector3(-150.0, 25.0, -25.0))
	_rot("arm_l", Vector3(-10.0, 0, 10.0))
	_rot("head", Vector3(-6.0, scan * 22.0, 0))
	_rot("leg_r", Vector3.ZERO)
	_rot("leg_l", Vector3.ZERO)


## 대피: 앞으로 숙여 허둥지둥, 팔을 머리 위로 휘저으며 잰걸음.
func _flee(delta: float) -> void:
	_phase += delta * _s("walk_freq", 9.0) * 1.5
	var s := sin(_phase)
	_lift("torso", absf(s) * 0.05)
	_rot("torso", Vector3(16.0, 0, s * 6.0))
	_rot("leg_r", Vector3(s * 38.0, 0, 0))
	_rot("leg_l", Vector3(-s * 38.0, 0, 0))
	_rot("arm_r", Vector3(-150.0 + s * 25.0, 0, -25.0))
	_rot("arm_l", Vector3(-150.0 - s * 25.0, 0, 25.0))
	_rot("head", Vector3(-8.0, sin(_phase * 0.7) * 25.0, 0))


# ---------------------------------------------------------------- 한 번짜리 공격(급격한 임팩트 이징)

## [예비 0→1(ease-in, 점점 빨라짐), 꽂기 0→1(지수 감속 + 넘침), 덮는 세기(회복 때 1→0)]
func _phases(a: Dictionary) -> Array:
	var w := float(a.wind)
	var s := float(a.strike)
	var h := float(a.hold)
	var wind := ease_in_cubic(_act_t / w) * 0.85 + ease_in_out(_act_t / w) * 0.15
	var hit := ease_out_snap((_act_t - w) / s, 0.14) if _act_t > w else 0.0
	var on := 1.0 - ease_in_out((_act_t - w - s - h) / float(a.recover)) if _act_t > w + s + h else 1.0
	return [wind, hit, on]


## 전투용병 베기: 검을 오른쪽 위 뒤로 크게 감아올리고(방패는 앞으로) → 대각선으로 몸을 던지며 순식간에 내리벤다.
func _slash(a: Dictionary) -> void:
	var ph := _phases(a)
	var wind: float = ph[0]
	var hit: float = ph[1]
	var on: float = ph[2]
	var yaw := lerpf(32.0 * wind, -38.0, hit)
	_over("arm_r", Vector3(lerpf(lerpf(-8.0, -170.0, wind), -40.0, hit), 0, lerpf(-45.0 * wind, 32.0, hit)), on)
	_over("arm_l", Vector3(-75.0 * wind * (1.0 - hit * 0.5), 0, 22.0), on)
	_over("torso", Vector3(lerpf(-10.0 * wind, 26.0, hit), yaw, -6.0 * hit), on)
	_over("leg_r", Vector3(lerpf(8.0 * wind, -32.0, hit), 0, 0), on)
	_over("leg_l", Vector3(lerpf(-6.0 * wind, 22.0, hit), 0, 0), on)
	_over("head", Vector3(lerpf(-8.0 * wind, 12.0, hit), -yaw * 0.5, 0), on)
	_lift("torso", (-0.05 * hit + 0.015 * wind) * on)


## 사냥꾼 활: 몸을 옆으로 틀고 활 팔을 앞으로 뻗은 채 시위를 끝까지 당김 → 놓는 순간 당기던 손이 뒤로 튕기고 시위가 떤다.
func _draw(a: Dictionary) -> void:
	var ph := _phases(a)
	var wind: float = ph[0]
	var rel: float = ph[1]
	var on: float = ph[2]
	var raise := ease_out_expo(_act_t / (float(a.wind) * 0.45))
	_over("torso", Vector3(-4.0 * raise - 5.0 * rel, -30.0 * raise, 0), on)
	_over("arm_l", Vector3(-88.0 * raise + 8.0 * rel, 0, 6.0 + 5.0 * rel), on)
	_over("arm_r", Vector3(lerpf(-82.0 * raise, -55.0, rel), 0, lerpf(-6.0 - 26.0 * wind, -62.0, rel)), on)
	_over("head", Vector3(-2.0 * raise, 28.0 * raise, 0), on)
	_over("leg_r", Vector3(-8.0 * raise, 0, -6.0 * raise), on)
	_over("leg_l", Vector3(8.0 * raise, 0, 6.0 * raise), on)
	var string := _prop("bow_string")
	if string != null:
		# 시위: 당긴 만큼 뒤로, 놓으면 앞으로 튕겼다 떤다
		var pull := float(string.get_meta("pull", 0.17)) * wind * (1.0 - minf(rel, 1.0))
		var twang := sin(_act_t * 95.0) * 0.025 * minf(rel, 1.0) * on
		string.position.z = float(string.get_meta("rest_z", 0.0)) - pull + twang
	var arrow := _prop("arrow")
	if arrow != null:
		arrow.visible = rel <= 0.0 and raise > 0.3


## 하수인 들이받기(직업 없음): 웅크렸다가 앞으로 확 덮친다.
func _stab(a: Dictionary) -> void:
	var ph := _phases(a)
	_over("torso", Vector3(lerpf(-12.0 * ph[0], 30.0, ph[1]), 0, 0), ph[2])
	_over("arm_r", Vector3(lerpf(-30.0 * ph[0], -95.0, ph[1]), 0, -10), ph[2])
	_over("arm_l", Vector3(lerpf(-30.0 * ph[0], -95.0, ph[1]), 0, 10), ph[2])


## 활은 팔이 어떻게 기울어도 세로로 선다(팔 각도가 다 정해진 뒤 부른다).
func _bow_align() -> void:
	var bow := _prop("bow")
	if bow != null and pivots.has("arm_l"):
		bow.rotation_degrees = Vector3(-pivots["arm_l"].rotation_degrees.x, 0, 0)


## 당기지 않을 때 시위·화살은 제자리.
func _props_rest() -> void:
	if _action != "draw":
		var string := _prop("bow_string")
		if string != null:
			string.position.z = float(string.get_meta("rest_z", 0.0))
		var arrow := _prop("arrow")
		if arrow != null:
			arrow.visible = false


## 등불·망토: 걸을 때 반 박자 늦게 흔들리고, 서 있으면 천천히 잦아든다(모든 상태에 겹친다).
func _secondary(_delta: float) -> void:
	if state == "cast": return
	var sway := sin(_phase - 1.4) * _swing
	_rot("lantern", Vector3(sway * _s("lantern_sway", 14.0) + sin(_t * 1.6) * 2.0, 0, sin(_phase * 0.5 - 0.8) * _swing * 6.0))
	_rot("cape", Vector3(-_swing * _s("cape_flutter", 10.0) + sin(_phase * 2.0) * _swing * 3.0 + sin(_t * 1.3) * 1.0, 0, 0))
	# 요정 날개: 등 가운데를 축으로 앞뒤로 빠르게 파닥인다(좌우 대칭). 걸을 때 조금 더 크게.
	var flap := sin(_t * _s("wing_freq", 14.0)) * (_s("wing_flap", 18.0) * (1.0 + _swing * 0.4))
	_rot("wing_r", Vector3(0, -flap - 8.0, 0))
	_rot("wing_l", Vector3(0, flap + 8.0, 0))
	# 수인 꼬리: 좌우로 살랑이고 걸을 때는 걸음에 맞춰 더 크게 흔든다.
	var wag := sin(_t * _s("tail_freq", 4.0)) * _s("tail_wag", 14.0) + sin(_phase) * _swing * _s("tail_wag", 14.0) * 0.6
	_rot("tail", Vector3(-6.0 * _swing, wag, 0))
