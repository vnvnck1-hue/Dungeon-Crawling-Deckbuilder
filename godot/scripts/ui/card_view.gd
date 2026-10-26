extends Control
## 손패 카드 한 장의 화면 표현(하스스톤식). 게임 상태는 갖지 않고 CardHand가 목표(위치·회전·배율)를 준다.
## 스프링으로 따라가 약간 출렁이며, 드래그 중에는 속도에 따라 관성으로 기운다.
## 기준점 pos = 카드 아래 가운데(화면 좌표). 그림자·발광은 카드 뒤(show_behind_parent)에 그린다.

const BURN := preload("res://shaders/card_burn.gdshader")
const BURN_GLOW_SHADER := preload("res://shaders/card_burn_glow.gdshader")
const CatalogScript := preload("res://scripts/ui/card_catalog.gd")
const SurfaceScript := preload("res://scripts/ui/card_surface.gd")
const CardFeel := preload("res://scripts/ui/card_feel.gd")
const CARD_BACK := preload("res://assets/cards/hand/card_back.png")
## 전설 카드(카탈로그 "frame": "legendary"): 금테 숨쉬기·별빛·회전에 반응하는 광택(card_burn.gdshader Legendary)
const LEGEND_MASK := "res://assets/cards/fx/legendary_frame_mask.png"
const LEGEND_GLOW := Color(1.0, 0.78, 0.4)

## 소모 연출: 섬광 뒤 BURN_TIME 동안 불꽃 띠가 아래에서 위로 타 올라간다
const BURN_DELAY := 0.12
const BURN_TIME := 0.9
## 소모 중 불꽃이 카드 밖으로 삐져나갈 여백(카드 폭 대비, 한쪽)
const BURN_PAD := 0.12
## 소모 중 카드 뒤 발광 색(셰이더 flame_color 와 맞춘 보라)
const BURN_GLOW := Color(0.6, 0.45, 0.95)
## 소모 중 카드 위 에디티브 글로우 층이 카드 밖으로 번질 여백(카드 폭 대비, 한쪽)
const GLOW_PAD := 0.3
## 연소선 여유(셰이더 burn_margin 과 같은 값: fire_thickness + wobble*0.15 + jaggedness*0.3 + 0.02)
const BURN_MARGIN := 0.14 + 0.865 * 0.15 + 0.164 * 0.3 + 0.02
## 재 입자: 연소선에서 떨어져 나와 위로 날리는 검은 조각. 카드가 사라진 뒤에도 남도록 카드의 형제 노드로 둔다
const ASH_AMOUNT := 36
const ASH_LIFETIME := 1.15
## 사용 카드 보여 주기(사용자 확정 2026-10-20): 타기 전에 핑그르 돌며 화면 오른쪽으로 크게 날아가 SHOW_HOLD 동안 앞면을 보여 준다
const SHOW_MOVE := 0.5     # 회전하며 날아가는 시간(초)
const SHOW_HOLD := 0.45    # 도착 뒤 멈춰 보여 주는 시간(초)
const SHOW_GLOW := Color(1.0, 0.86, 0.55)

enum Mode { HAND, DRAG, REVEAL, LEAVING, DYING }

## 마법 카드 연출(card_warp.gdshaderinc): 움직임이 카드를 휘고·비틀고·돌린다. 모드별 반응 배율
const WARP_MOTION := {Mode.HAND: 0.45, Mode.DRAG: 1.0, Mode.REVEAL: 0.9, Mode.LEAVING: 1.0, Mode.DYING: 0.6}
## 휨·회전 스프링(감쇠비가 낮아 젤리처럼 출렁이며 자리 잡는다). 실제 감쇠비는 카드 질감 프리셋(card_feel.gd warp_z, 기존 = WARP_Z)
const WARP_K := 150.0
const WARP_Z := 0.3
## 짧은 연출 동작(flourish)의 기본 길이(초)
const FLOURISH_TIME := {"draw": 0.95, "pickup": 0.5, "return": 0.62, "use": 0.62, "burn": 0.9, "stash": 0.8, "toss": 0.6, "hover": 0.45, "land": 0.5}

var uid := -1
var card_id := ""
var mode := Mode.HAND
var art: Control              # card_surface.gd: 격자 메시로 그린 카드 그림(texture 속성)
var shadow: TextureRect
var shadow_mul := 1.0         # 그림자 진하기 배율(대화창에 띄운 카드는 0: 옆 툴팁·아래 버튼에 그림자가 지지 않게)
var glow: TextureRect
var burn_glow: Control       # 소모 중 카드 위에 겹치는 보랏빛 에디티브 글로우
var glow_mat: ShaderMaterial
var ash: CPUParticles2D      # 소모 중 날리는 검은 재(부모의 자식 = 카드의 형제)
var ash_y := 0.0             # 재가 나오는 연소선의 카드 기준 y(검증용)
var badge: Label
var person: Label

# 스프링 상태(화면 좌표, 도, 배율)
var pos := Vector2.ZERO
var vel := Vector2.ZERO
var rot := 0.0
var rvel := 0.0
var scl := 1.0
var svel := 0.0
var t_pos := Vector2.ZERO
var t_rot := 0.0
var t_scl := 1.0
var lift := 0.0           # 0=손패에 놓임 · 1=들어 올림(그림자가 멀고 흐려짐)
var t_lift := 0.0
var glow_color := Color(0.22, 0.74, 0.76)
var glow_amt := 0.0
var t_glow := 0.0
var fade := 1.0
var tilt := Vector2.ZERO  # 원근 기울기(셰이더). x: 좌우, y: 앞뒤
var _sent_tilt := Vector2(INF, INF)  # 마지막으로 셰이더에 보낸 tilt·shine(같으면 다시 보내지 않는다)
var _sent_shine := -1.0
var t_tilt := Vector2.ZERO
var mat: ShaderMaterial
var t_fade := 1.0
var legendary := false
var legend_motion := 0.0      # 회전·이동 속도에서 나온 0..1(부드럽게 감쇠) — 셰이더 legend_motion
var _legend_t := 0.0
var timer := 0.0          # REVEAL 유지 시간 / LEAVING·DYING 진행 시간
# 마법 연출 상태. t_yaw·t_pitch(라디안)·t_float(0..1 둥실 떠다니는 정도)는 CardHand 가 준다. 나머지는 움직임에서 저절로 나온다
var t_yaw := 0.0
var t_pitch := 0.0
var t_float := 0.0
var float_amt := 0.0
var yaw := 0.0
var pitch := 0.0
var bend := Vector2.ZERO
var twist := 0.0
var flutter := 0.0
var magic := 0.0
var _wvel := PackedFloat32Array([0, 0, 0, 0, 0])   # yaw·pitch·bend.x·bend.y·twist 스프링 속도
var _prev_vel := Vector2.ZERO
var _float_time := 0.0
var _seed := 0.0
var fl_kind := ""          # 진행 중인 연출 동작(없으면 "")
var _fl_t := 0.0
var _fl_dur := 1.0
var warp := {}             # 마지막으로 계산한 최종 변형 값(검증·캡처용)
var _sent_warp := PackedFloat32Array()
var _face_w := 1.0         # 화면에서 보이는 카드 폭 비율(옆으로 돌면 그림자도 좁아진다)
var _roll_now := 0.0
var on_done: Callable
var show_time := 0.0       # 소모 전 보여 주기 길이(0이면 제자리에서 바로 탄다)
var _burning := false
var path_lock := false     # true면 위치·회전·크기를 스프링 대신 바깥(CardHand 주머니 흡입 곡선)이 직접 정한다. vel은 휨 계산용으로 바깥이 넣는다

# 모드별 스프링 강도와 감쇠비(1 미만이면 살짝 출렁임)
const SPRING := {
	Mode.HAND: [240.0, 0.68],
	Mode.DRAG: [620.0, 0.78],
	Mode.REVEAL: [230.0, 0.58],   # 공개 위치에 살짝 넘쳤다 돌아오는 텐션
	Mode.LEAVING: [120.0, 0.95],
	Mode.DYING: [300.0, 0.9],
}

static var _soft_tex: Texture2D
static var _ash_tex: Texture2D


static func soft_texture() -> Texture2D:
	if _soft_tex == null:
		# 둥근 사각형 + 부드러운 가장자리(그림자·발광 공용). 안쪽 영역 = 카드 크기, 바깥 24px 감쇠
		var w := 96
		var h := 112
		var m := 22.0
		var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
		for y in h:
			for x in w:
				var dx := maxf(maxf(m - x, x - (w - 1 - m)), 0.0)
				var dy := maxf(maxf(m - y, y - (h - 1 - m)), 0.0)
				var d := sqrt(dx * dx + dy * dy) / m
				var a := clampf(1.0 - d, 0.0, 1.0)
				a = a * a * (3.0 - 2.0 * a)
				img.set_pixel(x, y, Color(1, 1, 1, a))
		_soft_tex = ImageTexture.create_from_image(img)
	return _soft_tex


## 재 조각 텍스처: 울퉁불퉁한 작은 덩어리(회전·크기 무작위로 써서 모양이 반복돼 보이지 않게)
static func ash_texture() -> Texture2D:
	if _ash_tex == null:
		var n := 10
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var c := Vector2(n - 1, n - 1) * 0.5
		for y in n:
			for x in n:
				var d := (Vector2(x, y) - c).length() / (n * 0.5)
				var bump := rng.randf_range(-0.28, 0.28)
				var a := clampf(1.0 - (d + bump) * 1.25, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, 1.0 if a > 0.35 else 0.0))
		_ash_tex = ImageTexture.create_from_image(img)
	return _ash_tex


func setup(id: String, tex: Texture2D) -> void:
	card_id = id
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 발광을 먼저, 그림자를 그 위에 그린다(그림자가 발광에 씻겨 사라지지 않게)
	glow = _soft_rect()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	glow.material = add
	glow.modulate = Color(glow_color, 0.0)
	shadow = _soft_rect()
	shadow.modulate = Color(0.02, 0.0, 0.06, 0.7)
	# 격자 메시로 그려 셰이더가 카드를 휘고 돌릴 수 있게 한다(card_surface.gd)
	art = SurfaceScript.new()
	art.texture = tex
	add_child(art)
	mat = ShaderMaterial.new()
	mat.shader = BURN
	mat.set_shader_parameter("card_back", CARD_BACK)
	art.material = mat
	_seed = randf() * TAU
	set_legendary_for(id)
	# 소모 중에만 보이는 에디티브 글로우 층(카드 위, 더 넓은 사각형)
	burn_glow = SurfaceScript.new()
	burn_glow.texture = tex
	burn_glow.visible = false
	glow_mat = ShaderMaterial.new()
	glow_mat.shader = BURN_GLOW_SHADER
	burn_glow.material = glow_mat
	add_child(burn_glow)


func _soft_rect() -> TextureRect:
	var t := TextureRect.new()
	t.texture = soft_texture()
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_SCALE
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.show_behind_parent = true
	add_child(t)
	return t


func resize(card_size: Vector2) -> void:
	size = card_size
	pivot_offset = Vector2(card_size.x * 0.5, card_size.y)
	# 전설 카드(사용자 확정 2026-10-20): 셰이더 원근 기울기 대신 카드 중앙을 축으로 실제로 회전한다
	if legendary:
		pivot_offset = card_size * 0.5
	art.size = card_size
	mat.set_shader_parameter("card_size", card_size)
	glow_mat.set_shader_parameter("card_size", card_size)


## 상태를 즉시 맞춘다(첫 배치·순간 이동)
func snap(p: Vector2, r := 0.0, s := 1.0) -> void:
	pos = p
	t_pos = p
	rot = r
	t_rot = r
	scl = s
	t_scl = s
	vel = Vector2.ZERO
	rvel = 0.0
	svel = 0.0
	_apply()


func step(delta: float) -> void:
	var k: float = SPRING[mode][0]
	var z: float = SPRING[mode][1]
	z = lerpf(z, maxf(z, 1.0), float(CardFeel.p()["spring"]))   # 단단한 질감일수록 넘쳤다 돌아오는 출렁임을 줄인다
	var c := 2.0 * sqrt(k) * z
	var n := maxi(1, ceili(delta / (1.0 / 120.0)))
	var h := delta / n
	for i in n:
		if path_lock:
			break
		vel += ((t_pos - pos) * k - vel * c) * h
		pos += vel * h
		rvel += ((t_rot - rot) * k * 0.8 - rvel * c * 0.9) * h
		rot += rvel * h
		svel += ((t_scl - scl) * k - svel * c) * h
		scl += svel * h
	var e := 1.0 - exp(-delta * 14.0)
	lift = lerpf(lift, t_lift, e)
	glow_amt = lerpf(glow_amt, t_glow, 1.0 - exp(-delta * 10.0))
	fade = lerpf(fade, t_fade, e)
	tilt = tilt.lerp(t_tilt, 1.0 - exp(-delta * 16.0))
	# 전설 카드는 셰이더 원근 기울기를 쓰지 않는다(실제 회전만)
	if legendary:
		tilt = Vector2.ZERO
	# 손패의 모든 카드가 매 프레임 지나가므로, 쉬고 있는 카드는 셰이더 값이 그대로면 다시 보내지 않는다
	var shine := clampf(lift, 0.0, 1.0)
	if tilt != _sent_tilt:
		_sent_tilt = tilt
		mat.set_shader_parameter("tilt", tilt)
	if shine != _sent_shine:
		_sent_shine = shine
		mat.set_shader_parameter("shine", shine)
	if burn_glow.visible:
		glow_mat.set_shader_parameter("tilt", tilt)
	if legendary:
		_legend_step(delta)
	step_warp(delta)
	_apply()


## 연출 동작 시작. kind: draw(뽑힘 — 뒷면에서 1바퀴 반 핑그르르 돌며 앞면으로) · pickup(집어 듦 — 휘청 튕김) ·
## return(손패로 되돌아감 — 한 바퀴 비틀며 회전) · use(사용 — 한 바퀴 돌며 비틀려 타오름) · stash(주머니로 — 두루마리처럼 말림) ·
## toss(복제본이 날아감 — 한 바퀴) · hover(마우스 올림 — 오목하게 휘었다 폄) · land(공개 후 손패로 — 살랑 흔들림)
func flourish(kind: String, dur := -1.0) -> void:
	fl_kind = kind
	_fl_t = 0.0
	_fl_dur = dur if dur > 0.0 else float(FLOURISH_TIME.get(kind, 0.5))


## 휨·회전 갱신: 움직임(속도·가속) + 둥실 떠다님 + 연출 동작을 합쳐 셰이더에 보낸다.
func step_warp(delta: float) -> void:
	if delta <= 0.0:
		return
	var acc := (vel - _prev_vel) / delta
	_prev_vel = vel
	# 카드 질감 프리셋(card_feel.gd, F9): 기존은 모두 1배, 단단할수록 휨·둥실거림·물결이 줄고 스프링이 덜 출렁인다
	var feel := CardFeel.p()
	var mm: float = WARP_MOTION[mode] * float(feel["motion"])
	var bm: float = float(feel["bend"])
	# 움직이는 쪽으로 몸을 돌리고(yaw·pitch), 빠를수록 공기를 받아 휘며(bend) 펄럭이고(flutter), 급히 꺾이면 위아래가 비틀린다(twist)
	var tg := PackedFloat32Array([
		t_yaw + clampf(vel.x * 0.00075, -0.75, 0.75) * mm,
		t_pitch + clampf(-vel.y * 0.0006, -0.6, 0.6) * mm,
		clampf(absf(vel.x) * 0.00032, 0.0, 0.5) * mm * bm,
		clampf(absf(vel.y) * 0.00028, 0.0, 0.45) * mm * bm,
		clampf(-acc.x * 0.00005, -0.9, 0.9) * mm * bm])
	var t_flut := clampf(vel.length() / 2200.0, 0.0, 0.8) * mm
	# 마법에 떠받쳐진 듯 둥실 떠다님
	float_amt = lerpf(float_amt, t_float, 1.0 - exp(-delta * 5.0))
	_float_time += delta
	var f := float_amt * float(feel["float"])
	var ft := _float_time
	tg[0] += f * 0.2 * sin(ft * 1.7 + _seed)
	tg[1] += f * 0.13 * sin(ft * 1.3 + _seed * 2.0)
	tg[2] += f * 0.12 * sin(ft * 2.1 + _seed * 0.5)
	tg[4] += f * 0.16 * sin(ft * 1.1 + _seed * 3.0)
	t_flut += f * 0.18
	t_flut *= float(feel["flutter"])
	var cur := PackedFloat32Array([yaw, pitch, bend.x, bend.y, twist])
	var n := maxi(1, ceili(delta / (1.0 / 120.0)))
	var h := delta / n
	var c := 2.0 * sqrt(WARP_K) * float(feel["warp_z"])
	for _i in n:
		for j in 5:
			_wvel[j] += ((tg[j] - cur[j]) * WARP_K - _wvel[j] * c) * h
			cur[j] += _wvel[j] * h
	yaw = cur[0]
	pitch = cur[1]
	bend = Vector2(cur[2], cur[3])
	twist = cur[4]
	flutter = lerpf(flutter, t_flut, 1.0 - exp(-delta * 8.0))
	magic = lerpf(magic, 0.35 * f, 1.0 - exp(-delta * 6.0))
	# 연출 동작은 스프링 위에 그대로 더한다(정해진 궤적)
	var o := _flourish_offsets(delta)
	# 단단한 질감: 연출의 회전(yaw)·말림(roll)은 그대로, 종이처럼 휘고 비틀리고 물결치는 몫만 줄인다
	for j in range(1, 5):
		o[j] *= bm
	o[6] *= float(feel["flutter"])
	o[7] *= float(feel["magic"])
	var w_yaw: float = yaw + o[0]
	var w_pitch: float = pitch + o[1]
	var w_bend := bend + Vector2(o[2], o[3])
	var w_twist: float = twist + o[4]
	var w_roll: float = o[5]
	var w_flut: float = clampf(flutter + o[6], 0.0, 1.2)
	var w_magic: float = clampf(magic + o[7], 0.0, 1.0)
	_face_w = maxf(absf(cos(w_yaw)) * (1.0 - absf(w_bend.x) * 0.25), 0.12)
	_roll_now = w_roll
	# 수량 배지는 평평한 겹이라 카드가 옆·뒤로 돌거나 말리는 동안은 감춘다(앞면이 정면일 때만 보인다)
	if badge != null and mode != Mode.DYING:
		var face_a := clampf((cos(w_yaw) - 0.55) / 0.35, 0.0, 1.0) * clampf(1.0 - w_roll * 5.0, 0.0, 1.0)
		badge.get_parent().modulate.a = face_a
	warp["yaw"] = w_yaw
	warp["pitch"] = w_pitch
	warp["bend"] = w_bend
	warp["twist"] = w_twist
	warp["roll"] = w_roll
	warp["flutter"] = w_flut
	warp["magic"] = w_magic
	var pack := PackedFloat32Array([w_yaw, w_pitch, w_bend.x, w_bend.y, w_twist, w_roll, w_flut, w_magic])
	if _sent_warp.size() == pack.size():
		var same := true
		for j in pack.size():
			if absf(pack[j] - _sent_warp[j]) > 0.0004:
				same = false
				break
		if same:
			return
	_sent_warp = pack
	_send_warp(mat)
	if burn_glow.visible:
		_send_warp(glow_mat)


func _send_warp(m: ShaderMaterial) -> void:
	m.set_shader_parameter("warp_yaw", warp["yaw"])
	m.set_shader_parameter("warp_pitch", warp["pitch"])
	m.set_shader_parameter("warp_bend", warp["bend"])
	m.set_shader_parameter("warp_twist", warp["twist"])
	m.set_shader_parameter("warp_roll", warp["roll"])
	m.set_shader_parameter("warp_flutter", warp["flutter"])
	m.set_shader_parameter("warp_magic", warp["magic"])


## 진행 중인 연출 동작이 더할 값 [yaw, pitch, bend.x, bend.y, twist, roll, flutter, magic]
func _flourish_offsets(delta: float) -> PackedFloat32Array:
	var o := PackedFloat32Array([0, 0, 0, 0, 0, 0, 0, 0])
	if fl_kind == "":
		return o
	_fl_t += delta
	var u := clampf(_fl_t / _fl_dur, 0.0, 1.0)
	var arc := sin(PI * u)
	var out3 := 1.0 - pow(1.0 - u, 3.0)
	match fl_kind:
		"draw":
			# 뒷면(−3π ≡ π)에서 시작해 1바퀴 반을 핑그르르 돌아 앞면으로 멈춘다. 도는 동안 위아래가 비틀리고 휜다
			o[0] = -3.0 * PI * (1.0 - out3)
			o[4] = 1.5 * arc * (1.0 - u)
			o[2] = 0.55 * arc
			o[1] = 0.35 * sin(TAU * u) * (1.0 - u)
			o[6] = 0.6 * (1.0 - u)
			o[7] = 1.0 - u * u
		"pickup":
			# 손패에서 떼어 낼 때 종이가 튕기듯 오목하게 휘었다가 펴진다
			o[1] = -0.5 * arc * (1.0 - u * 0.5)
			o[3] = -0.45 * arc
			o[2] = 0.32 * sin(TAU * u) * (1.0 - u)
			o[7] = 0.8 * (1.0 - u)
		"return":
			# 손패로 되돌아가며 한 바퀴 비틀어 돈다
			o[0] = TAU * (1.0 - out3)
			o[4] = -1.0 * arc
			o[2] = 0.4 * arc
			o[7] = 0.6 * (1.0 - u)
		"use":
			# 마법에 사로잡혀 한 바퀴 돌며 비틀리고 오목하게 감긴다(동시에 아래에서 타오른다)
			o[0] = TAU * (1.0 - pow(1.0 - u, 2.0))
			o[4] = 1.7 * arc
			o[2] = -0.6 * arc
			o[6] = 0.7 * arc
			o[7] = 1.0 - u * 0.4
		"burn":
			# 보여 준 뒤 제자리에서 타오를 때: 돌지 않고 열기에 비틀리며 오목하게 감긴다
			o[4] = 0.7 * arc
			o[2] = -0.45 * arc
			o[6] = 0.6 * arc
			o[7] = 1.0 - u * 0.4
		"stash":
			# 주머니의 소용돌이에 붙잡혀(사용자 요청 2026-10-23): 처음엔 오목하게 휘청 끌려가다가, 빨려 들수록 위아래가 비틀려 꼬이고
			# 펄럭이며, 마지막에 두루마리처럼 말려 주머니 입구로 쏙 들어간다. 곡선 궤적은 CardHand._step_suck 이 그린다
			var pull := u * u
			var tail := clampf((u - 0.45) / 0.55, 0.0, 1.0)
			o[0] = -0.8 * PI * out3
			o[2] = -0.8 * arc + 0.3 * pull
			o[3] = -0.5 * sin(PI * minf(u * 1.6, 1.0)) + 0.3 * pull
			o[4] = 0.9 * arc + 1.4 * pull + 0.35 * sin(TAU * u * 1.5) * (1.0 - u)
			o[5] = tail * tail * (3.0 - 2.0 * tail)
			o[6] = 0.9 * arc
			o[7] = 0.5 + 0.5 * u
		"toss":
			o[0] = TAU * out3
			o[2] = 0.45 * arc
			o[4] = 0.8 * arc
			o[7] = 0.8 * (1.0 - u)
		"hover":
			o[3] = -0.28 * arc * (1.0 - u * 0.5)
			o[1] = -0.22 * arc * (1.0 - u)
			o[7] = 0.75 * (1.0 - u)
		"land":
			o[2] = 0.3 * arc * (1.0 - u)
			o[4] = -0.6 * arc * (1.0 - u)
			o[1] = 0.25 * sin(TAU * u) * (1.0 - u)
	# 주머니로 말려 들어간 카드는 사라질 때까지 말린 채로 둔다
	if u >= 1.0 and fl_kind != "stash":
		fl_kind = ""
	return o


## 카드 id 가 전설 프레임이면 전설 셰이더·중앙 회전 축을 켜고, 아니면 끈다(확대 카드처럼 한 뷰를 여러 카드에 재사용할 때도 부른다).
func set_legendary_for(id: String) -> void:
	legendary = id != "" and String(CatalogScript.find(id).get("frame", "")) == "legendary" and ResourceLoader.exists(LEGEND_MASK)
	mat.set_shader_parameter("legendary", legendary)
	if legendary:
		mat.set_shader_parameter("legend_mask", load(LEGEND_MASK))
	else:
		legend_motion = 0.0
		mat.set_shader_parameter("legend_motion", 0.0)
	if size != Vector2.ZERO:
		pivot_offset = size * 0.5 if legendary else Vector2(size.x * 0.5, size.y)


## 전설 카드: 회전 속도·이동 속도·기울기 변화를 빛 반응(0..1)으로 바꿔 셰이더에 보낸다.
func _legend_step(delta: float) -> void:
	_legend_t += delta
	# 손패 드래그의 실제 회전은 ±4° 안팎이라 그 폭에서도 빛이 살도록 감도를 맞춘다
	var m := clampf(absf(rvel) / 14.0 + vel.length() / 1400.0, 0.0, 1.0)
	# 빨리 차오르고 천천히 가라앉는다(움직임이 멈춰도 빛이 잠깐 남는다)
	legend_motion = lerpf(legend_motion, m, 1.0 - exp(-delta * (14.0 if m > legend_motion else 2.5)))
	mat.set_shader_parameter("legend_motion", legend_motion)
	mat.set_shader_parameter("legend_angle", deg_to_rad(rot))


func _apply() -> void:
	# pos = 카드 아래 가운데(회전 축과 무관). 회전 축이 가운데인 전설 카드도 배치 각도(t_rot)·크기에서는
	# 아래 가운데가 pos 에 오도록 보정해 손패 부채꼴·확대 자리가 다른 카드와 같다(축은 출렁임·연출 회전에만 남는다)
	var s := maxf(scl, 0.01)
	var foot := Vector2(size.x * 0.5, size.y)
	position = pos - pivot_offset - ((foot - pivot_offset) * s).rotated(deg_to_rad(t_rot))
	rotation_degrees = rot
	scale = Vector2.ONE * s
	modulate.a = fade
	# 그림자: 화면 아래쪽으로 떨어지고, 들어 올릴수록 멀고 넓고 옅어진다(카드 회전과 무관하게 화면 기준)
	# 부드러운 텍스처의 꽉 찬 안쪽은 전체의 54%: 테두리를 카드 폭의 30~42%만큼 넓혀 안쪽이 카드와 비슷해지게 한다.
	var u := size.x / 96.0
	var off := (Vector2(4.0 + 14.0 * lift, 7.0 + 34.0 * lift) * u).rotated(-rotation)
	var g := size.x * (0.26 + 0.12 * lift)
	# 카드가 옆으로 돌거나(폭) 말리면(높이) 그림자도 그만큼 줄어든다
	var body := Vector2(size.x * _face_w, size.y * (1.0 - _roll_now * 0.75))
	shadow.position = off + Vector2((size.x - body.x) * 0.5, 0.0) - Vector2(g, g)
	shadow.size = body + Vector2(g, g) * 2.0
	shadow.modulate.a = (0.78 - 0.18 * lift) * fade * shadow_mul
	var gs := size.x * 0.24
	glow.position = -Vector2(gs, gs)
	glow.size = size + Vector2(gs, gs) * 2.0
	glow.modulate = Color(glow_color, glow_amt * fade)
	# 전설 카드: 다른 발광(선택·소모)이 없을 때 카드 뒤에 금빛 후광이 은은히 숨 쉰다
	if legendary and glow_amt < 0.2:
		var halo := 0.16 + 0.07 * sin(_legend_t * 1.6) + 0.22 * legend_motion
		glow.modulate = Color(LEGEND_GLOW, maxf(glow_amt, halo) * fade)


## 소모: 섬광 → 살짝 커지며 아래에서 위로 불꽃 띠가 타 올라가 없어짐.
## show_center(화면 좌표, 카드 중심)를 주면 먼저 핑그르 돌며 그 자리로 show_scale 만큼 커져 날아가 앞면을 보여 준 뒤 탄다.
func start_dissolve(done: Callable, show_center := Vector2.INF, show_scale := 0.0) -> void:
	mode = Mode.DYING
	timer = 0.0
	on_done = done
	t_tilt = Vector2.ZERO
	t_lift = 1.0
	_burning = false
	if badge != null:
		badge.get_parent().visible = false
	if person != null:
		person.get_parent().visible = false
	if show_center.is_finite() and show_scale > 0.0:
		show_time = SHOW_MOVE + SHOW_HOLD
		# pos 는 카드 아래 가운데(_apply 가 전설 카드의 가운데 축도 보정한다)
		t_pos = show_center + Vector2(0, size.y * 0.5 * show_scale)
		t_scl = show_scale
		t_rot = 0.0
		t_glow = 0.75
		glow_color = SHOW_GLOW
		flourish("use", SHOW_MOVE)   # 날아가는 동안 한 바퀴 돌아 앞면으로 멈춘다
		return
	show_time = 0.0
	t_scl = maxf(scl * 1.3, 1.05)
	t_rot = rot * 0.5
	flourish("use")
	_begin_burn()


## 타기 시작: 불꽃 자리·글로우 층·재 입자를 켠다
func _begin_burn() -> void:
	_burning = true
	t_glow = 0.8
	glow_color = BURN_GLOW
	if show_time > 0.0:
		t_scl = scl * 1.08
		flourish("burn")
	# 그림 사각형을 넓혀 불꽃이 카드 밖으로 번질 자리를 만든다(셰이더가 카드 UV를 다시 맞춘다)
	var p := Vector2.ONE * size.x * BURN_PAD
	art.position = -p
	art.size = size + p * 2.0
	mat.set_shader_parameter("pad", p)
	# 보랏빛 에디티브 글로우 층: 불꽃보다 넓게 번지도록 더 큰 여백
	var gp := Vector2.ONE * size.x * GLOW_PAD
	burn_glow.position = -gp
	burn_glow.size = size + gp * 2.0
	glow_mat.set_shader_parameter("pad", gp)
	glow_mat.set_shader_parameter("tilt", tilt)
	glow_mat.set_shader_parameter("progress", 0.0)
	burn_glow.visible = true
	_sent_warp = PackedFloat32Array()   # 글로우 층도 같은 휨을 받도록 다음 프레임에 다시 보낸다
	_spawn_ash()


## 재 입자 생성. 카드가 먼저 사라져도 재는 끝까지 날리도록 같은 부모 아래 형제로 붙인다(없으면 카드 자신).
func _spawn_ash() -> void:
	ash = CPUParticles2D.new()
	ash.texture = ash_texture()
	ash.amount = ASH_AMOUNT
	ash.lifetime = ASH_LIFETIME
	ash.lifetime_randomness = 0.4
	ash.explosiveness = 0.0
	ash.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	ash.emission_rect_extents = Vector2(size.x * 0.42, size.y * 0.02)
	ash.direction = Vector2(0, -1)
	ash.spread = 58.0                           # 좌우로 흩어지며 위로 날린다
	ash.initial_velocity_min = size.y * 0.55
	ash.initial_velocity_max = size.y * 1.25
	ash.gravity = Vector2(0, -size.y * 0.45)    # 뜨거운 공기 따라 연소선보다 빨리 위로 날아오른다
	ash.damping_min = size.y * 0.1
	ash.damping_max = size.y * 0.3
	# 접선 가속은 가로로 긴 발생 사각형에서 세로 방향이 되어 절반이 아래로 떨어진다 → 쓰지 않는다
	ash.linear_accel_min = -size.y * 0.25
	ash.linear_accel_max = size.y * 0.25
	ash.angle_min = 0.0
	ash.angle_max = 360.0
	ash.angular_velocity_min = -240.0
	ash.angular_velocity_max = 240.0
	ash.scale_amount_min = 0.3
	ash.scale_amount_max = 0.7
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(0.75, 0.8))
	sc.add_point(Vector2(1.0, 0.0))
	ash.scale_amount_curve = sc
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.38, 0.22, 0.55, 0.75))   # 연소선에서 막 떨어진 조각은 잠깐 보랏빛 잉걸
	ramp.set_color(1, Color(0.02, 0.01, 0.04, 0.0))
	ramp.add_point(0.12, Color(0.05, 0.03, 0.08, 0.92))
	ramp.add_point(0.7, Color(0.04, 0.02, 0.07, 0.8))
	ash.color_ramp = ramp
	var host: Node = get_parent() if get_parent() != null else self
	host.add_child(ash)
	ash.z_index = z_index + 1
	_place_ash(0.0)
	ash.emitting = true


## 연소선(아래→위)의 현재 카드 기준 y 에 재 발생 사각형을 맞춘다. p = 소모 진행 0..1
func _place_ash(p: float) -> void:
	var line := lerpf(-BURN_MARGIN, 1.0 + BURN_MARGIN, p)
	ash_y = size.y * (1.0 - line) + size.y * 0.03   # 연소선 바로 아래(탄 쪽)에서 떨어져 나온다
	ash.emitting = line >= -0.04 and line <= 1.02
	var local := Vector2(size.x * 0.5, clampf(ash_y, -size.y * 0.06, size.y * 1.06))
	ash.transform = get_transform() * Transform2D(0.0, local) if ash.get_parent() != self else Transform2D(0.0, local)


func _exit_tree() -> void:
	# 소모 도중 카드가 먼저 지워져도(장면 전환 등) 재가 계속 나오지 않게 한다
	_release_ash()


## 재 입자는 카드보다 오래 남는다: 발생을 멈추고 수명이 끝나면 지운다
func _release_ash() -> void:
	if ash == null:
		return
	var a := ash
	ash = null
	a.emitting = false
	var tree := a.get_tree()
	if tree == null:
		a.queue_free()
		return
	tree.create_timer(ASH_LIFETIME * 1.4 + 0.2, true, false, true).timeout.connect(func() -> void:
		if is_instance_valid(a):
			a.queue_free())


## 보여 주기 단계인가(검증용)
func showing() -> bool:
	return mode == Mode.DYING and not _burning


func tick_dissolve(delta: float) -> bool:
	timer += delta
	if not _burning:
		if timer < show_time:
			return false
		_begin_burn()
	var bt := timer - show_time
	var m := art.material as ShaderMaterial
	var flash := clampf(1.0 - bt / 0.16, 0.0, 1.0) if bt < 0.16 else 0.0
	m.set_shader_parameter("flash", clampf(bt / 0.08, 0.0, 1.0) if bt < 0.08 else flash)
	var p := clampf((bt - BURN_DELAY) / BURN_TIME, 0.0, 1.0)
	m.set_shader_parameter("progress", p)
	glow_mat.set_shader_parameter("progress", p)
	shadow.visible = p < 0.35
	t_glow = maxf(0.0, 1.0 - p * 1.4)
	if ash != null:
		_place_ash(p)
	var done := bt >= BURN_DELAY + BURN_TIME
	if done:
		_release_ash()
	return done
