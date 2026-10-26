extends Node3D
## 마녀 Q 번개 일격(Lightning Lance) 연출(표시 전용 — 피해·감전 판정은 actors/player.gd 가 한다).
## 면은 모두 shaders/vfx/lightning/ 의 VisualShader(tools/build_lightning_shaders.gd 로 재생성)로 그리고,
## 입자는 공용 VfxPool, 화면 흔들림은 World.shake 를 쓴다. 판정 시점은 hit_delay() 로 연출과 맞춘다.
##
## 프리셋(Shift+Q 로 바꿈, 기본값 Cfg.LIGHTNING_PRESET)
##   0 기본 번개  가로 번개 줄기 두 겹이 0.05초에 뻗고 지직거리다 꼬리부터 끊김 + 하얀 구체 + 지면 방전 자국 (청록)
##   1 뇌창       셀 음영 창머리가 0.14초에 날아가며 꺾인 나선 두 가닥을 남기고, 지나간 적마다 네 갈래 별 + 파편,
##                끝점에서 큰 별 파열 → 나선이 꼬리부터 각지게 타서 사라짐 (금빛·흰빛 + 보라 외곽, 경계가 딱 끊김)
##   2 흑뢰       땅이 시전자에서 끝으로 찢기며(0.12초) 검은 틈이 열리고, 앞머리를 따라 하늘에서 검은 심의 번개 기둥이
##                연달아 내리꽂힘(맞은 적마다 한 줄기 더) → 틈이 닫히며 사라짐 (검보라 심 + 자홍 테두리, 뒤집힌 색)

const Fx := preload("res://scripts/visual/fx.gd")
const Pool := preload("res://scripts/visual/vfx/vfx_pool.gd")
const SH_BOLT := preload("res://shaders/vfx/lightning/lt_bolt.tres")
const SH_ORB := preload("res://shaders/vfx/lightning/lt_orb.tres")
const SH_SCORCH := preload("res://shaders/vfx/lightning/lt_scorch.tres")
const SH_SPEAR := preload("res://shaders/vfx/lightning/lt_spear.tres")
const SH_HELIX := preload("res://shaders/vfx/lightning/lt_helix.tres")
const SH_STAR := preload("res://shaders/vfx/lightning/lt_star.tres")
const SH_RIFT := preload("res://shaders/vfx/lightning/lt_rift.tres")
const SH_PILLAR := preload("res://shaders/vfx/lightning/lt_pillar.tres")

enum Preset { CLASSIC, SPEAR, RIFT }
const PRESET_NAMES := ["기본 번개", "뇌창", "흑뢰"]

const C_CORE := Color(0.9, 1.0, 1.0)
const C_ELEC := Color(0.3, 0.85, 1.0)
const C_GOLD := Color(1.0, 0.78, 0.25)
const C_GOLD_HOT := Color(1.0, 0.96, 0.8)
const C_VIOLET := Color(0.62, 0.3, 1.0)
const C_MAGENTA := Color(1.0, 0.35, 0.95)
const C_VOID := Color(0.16, 0.05, 0.26)

# 기본 번개
const REACH_T := 0.05        # 줄기가 끝까지 뻗는 시간
const HOLD_T := 0.17         # 이때까지 지직거리며 밝게 버팀
const FLICKER_T := 0.035     # 모양이 새로 튀는 간격
const BOLT_LIFE := 0.42
# 뇌창
const SPEAR_T := 0.14        # 창머리가 끝점까지 날아가는 시간
const HELIX_LIFE := 0.5
# 흑뢰
const RIFT_T := 0.12         # 땅이 끝까지 찢기는 시간
const PILLAR_DROP := 0.05    # 기둥이 하늘에서 땅까지 내리꽂히는 시간
const RIFT_PILLARS := [0.12, 0.34, 0.56, 0.78, 0.98]

enum Kind { BOLT, ORB, SCORCH, SPEAR, HELIX, STAR, RIFT, PILLAR }

var kind := Kind.BOLT
var t := 0.0
var life := 0.5
var _delay := 0.0             # 이 시간 뒤에 나타난다(그 전엔 숨김). life 는 나타난 뒤부터 센다
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _flick := 0.0
var _fx_t := 0.0
var _shake := 0.0             # 나타나는 순간 화면 흔들림 세기(0 이면 없음)
var _landed := false


# ---------------------------------------------------------------- 공개 함수

## 번개 일격 한 번. from = 지팡이 끝, to = 줄기 끝(사거리 끝), hits = 맞은 적의 가슴 높이 점들.
static func lance(parent: Node, from: Vector3, to: Vector3, hits: Array = [], preset := Preset.CLASSIC) -> void:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return
	if from.distance_to(to) < 0.2:
		return
	match preset:
		Preset.SPEAR: _spear_cast(parent, from, to, hits)
		Preset.RIFT: _rift_cast(parent, from, to, hits)
		_: _classic_cast(parent, from, to, hits)


## 판정 시점: 줄기를 따라 frac(0 시전점 → 1 끝점) 위치의 적이 연출상 맞는 때(초).
static func hit_delay(preset: int, frac: float) -> float:
	frac = clampf(frac, 0.0, 1.0)
	match preset:
		Preset.SPEAR: return SPEAR_T * frac
		Preset.RIFT: return RIFT_T * frac + PILLAR_DROP
		_: return REACH_T * frac


static func preset_name(preset: int) -> String:
	return PRESET_NAMES[clampi(preset, 0, PRESET_NAMES.size() - 1)]


## 타격 순간 화면 흔들림(World.shake). game 이 없으면(검증 장면) 무시.
static func shake(game: Node, amount: float, duration: float) -> void:
	if game != null and is_instance_valid(game) and game.get("world") != null and game.world.has_method("shake"):
		game.world.shake(amount, duration)


# ---------------------------------------------------------------- 프리셋 0 · 기본 번개

static func _classic_cast(parent: Node, from: Vector3, to: Vector3, hits: Array) -> void:
	var length := from.distance_to(to)
	# 줄기 두 겹: 굵은 칼날 + 가늘고 크게 꺾이는 곁줄기
	var main := _spawn(parent, Kind.BOLT, BOLT_LIFE)
	main._bolt(from, to, 2.6, 1.0, 1.0)
	var side := _spawn(parent, Kind.BOLT, BOLT_LIFE * 0.85)
	side._bolt(from, to, 3.4, 0.35, 0.7)
	main._light_at((to - from) * 0.5, C_ELEC, 5.0, maxf(length * 0.75, 4.0))
	# 지팡이 끝 섬광 구체
	_spawn(parent, Kind.ORB, 0.2)._orb(from, 1.1)
	# 끝점 구체 + 지면 방전 자국(줄기 머리가 닿는 순간)
	var end := _spawn(parent, Kind.ORB, 0.38, REACH_T * 0.8)
	end._orb(to, 2.4)
	end._light_at(Vector3.ZERO, C_ELEC, 8.0, 5.5)
	_spawn(parent, Kind.SCORCH, 1.6)._ground(Vector3(to.x, 0.045, to.z), 3.0)
	# 맞은 적마다 작은 구체와 불꽃
	for h in hits:
		_spawn(parent, Kind.ORB, 0.3, REACH_T * _frac(from, to, h))._orb(h, 1.5)
		Fx.hit(h, C_ELEC, true)
	var P = Fx._p()
	if P == null:
		return
	var dir := (to - from) / length
	for i in int(clampf(length * 2.2, 8.0, 26.0)):
		var at := from.lerp(to, randf())
		var vel := dir * randf_range(4.0, 9.0) + Fx._rv(randf_range(1.5, 4.0)) + Vector3(0, 1.2, 0)
		P.emit(Pool.STREAK, at, vel, randf_range(0.14, 0.3), randf_range(0.12, 0.22), C_CORE if i % 3 == 0 else C_ELEC,
			{"gravity": -7.0, "align": true, "aspect": 0.25, "additive": true, "drag": 2.0})
	P.emit(Pool.SHOCK, to, Vector3.ZERO, 0.22, 2.2, C_ELEC, {"pop": true, "grow": 1.5, "additive": true})
	P.emit(Pool.RING, to, Vector3.ZERO, 0.3, 0.5, Color(0.85, 1.0, 1.0, 0.95), {"additive": true, "grow": 5.0})
	P.emit(Pool.RING, Vector3(to.x, 0.06, to.z), Vector3.ZERO, 0.4, 1.0, Color(0.5, 0.9, 1.0, 0.85), {"ground": true, "additive": true, "grow": 3.2})
	for i in 14:
		var v := Fx._rv(randf_range(3.0, 7.5))
		v.y = absf(v.y) + 1.5
		P.emit(Pool.STREAK, to, v, randf_range(0.2, 0.42), randf_range(0.14, 0.26), C_CORE if i % 2 else C_ELEC,
			{"gravity": -12.0, "align": true, "aspect": 0.25, "additive": true, "land": true})
	P.emit(Pool.RING, Vector3(from.x, 0.05, from.z), Vector3.ZERO, 0.3, 0.6, Color(0.5, 0.9, 1.0, 0.7), {"ground": true, "additive": true, "grow": 2.4})


# ---------------------------------------------------------------- 프리셋 1 · 뇌창

static func _spear_cast(parent: Node, from: Vector3, to: Vector3, hits: Array) -> void:
	var length := from.distance_to(to)
	var helix := _spawn(parent, Kind.HELIX, HELIX_LIFE)
	helix._helix(from, to)
	var head := _spawn(parent, Kind.SPEAR, SPEAR_T)
	head._spear(from, to)
	head._light_at(Vector3.ZERO, C_GOLD, 4.0, 4.0)
	# 쏘는 순간 지팡이 끝 작은 별
	_spawn(parent, Kind.STAR, 0.16)._star(from, 1.3)
	for h in hits:
		var s := _spawn(parent, Kind.STAR, 0.26, SPEAR_T * _frac(from, to, h))
		s._star(h, 2.2)
		s._shake = 0.1
	var end := _spawn(parent, Kind.STAR, 0.34, SPEAR_T)
	end._star(to, 2.9)
	end._light_at(Vector3.ZERO, C_GOLD, 3.5, 5.0)
	end._shake = 0.16
	var sc := _spawn(parent, Kind.SCORCH, 1.2, SPEAR_T)
	sc._ground(Vector3(to.x, 0.045, to.z), 2.6)
	sc._mat.set_shader_parameter("color_hot", Color(1.0, 0.8, 0.35))
	sc._mat.set_shader_parameter("color_scorch", Color(0.2, 0.12, 0.28))
	var P = Fx._p()
	if P != null:
		# 시전자 발밑 금빛 고리(반동)
		P.emit(Pool.RING, Vector3(from.x, 0.05, from.z), Vector3.ZERO, 0.25, 0.5, Color(1.0, 0.85, 0.4, 0.8), {"ground": true, "additive": true, "grow": 2.6})
		P.emit(Pool.STREAK, from, (to - from) / length * 14.0, 0.12, 0.5, C_GOLD_HOT, {"align": true, "aspect": 0.18, "additive": true})


# ---------------------------------------------------------------- 프리셋 2 · 흑뢰

static func _rift_cast(parent: Node, from: Vector3, to: Vector3, hits: Array) -> void:
	var b := Vector3(to.x, 0.0, to.z)
	var a := Vector3(from.x, 0.0, from.z)
	a += (b - a).normalized() * 0.6   # 마녀 발밑은 비워 둔다(균열은 깊이 검사 없이 수풀 위에 그린다)
	var rift := _spawn(parent, Kind.RIFT, 0.8)
	rift._rift(a, b)
	rift._light_at(Vector3(0, 0.6, 0), C_MAGENTA, 3.5, maxf(a.distance_to(b) * 0.7, 4.0))
	var fracs: Array = RIFT_PILLARS.duplicate()
	for h in hits:
		fracs.append(_frac(from, to, h))
	for i in fracs.size():
		var f: float = fracs[i]
		var at := a.lerp(b, f)
		var p := _spawn(parent, Kind.PILLAR, 0.34, RIFT_T * f)
		p._pillar(at, 7.0 if i < RIFT_PILLARS.size() else 8.0, 2.0 if i < RIFT_PILLARS.size() else 2.6)
		p._shake = 0.07 if i < RIFT_PILLARS.size() else 0.13
	var sc := _spawn(parent, Kind.SCORCH, 1.4, RIFT_T)
	sc._ground(Vector3(b.x, 0.045, b.z), 3.2)
	sc._mat.set_shader_parameter("color_hot", Color(1.0, 0.4, 0.95))
	sc._mat.set_shader_parameter("color_scorch", Color(0.08, 0.02, 0.12))
	var P = Fx._p()
	if P != null:
		P.emit(Pool.RING, Vector3(from.x, 0.05, from.z), Vector3.ZERO, 0.3, 0.6, Color(1.0, 0.4, 0.95, 0.75), {"ground": true, "additive": true, "grow": 2.4})


# ---------------------------------------------------------------- 내부 · 생성

static func _spawn(parent: Node, k: Kind, lifetime: float, delay := 0.0) -> Node3D:
	var v = load("res://scripts/visual/vfx/lightning_vfx.gd").new()
	v.kind = k
	v.life = lifetime
	v._delay = delay
	v.name = "LightningVfx_" + Kind.keys()[k]
	parent.add_child(v, true)
	v.visible = delay <= 0.0
	return v


static func _frac(from: Vector3, to: Vector3, p: Vector3) -> float:
	var d := to - from
	d.y = 0.0
	var r := p - from
	r.y = 0.0
	return clampf(r.dot(d) / maxf(d.length_squared(), 0.001), 0.0, 1.0)


func _quad(size: Vector2, sh: Shader, priority: int) -> void:
	_mi = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	_mi.mesh = pm
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.render_priority = priority
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_mi)


## 줄기 판: uv.x = from → to. 판은 줄기 축을 중심으로 돌려 카메라 쪽을 향하게 세운다(위에서 내려다봐도 납작해지지 않음).
func _bolt(from: Vector3, to: Vector3, width: float, thickness: float, intensity: float) -> void:
	_from = from
	_to = to
	_quad(Vector2(from.distance_to(to), width), SH_BOLT, 5)
	_mat.set_shader_parameter("thickness", thickness)
	_mat.set_shader_parameter("intensity", intensity)
	_mat.set_shader_parameter("seed", randf() * 50.0)
	_mat.set_shader_parameter("reach", 0.0)
	set_meta("base_intensity", intensity)
	global_position = (from + to) * 0.5
	_face_along()


func _orb(at: Vector3, diameter: float) -> void:
	_quad(Vector2(diameter, diameter), SH_ORB, 6)
	_mat.set_shader_parameter("seed", randf() * 50.0)
	_mat.set_shader_parameter("pulse", 0.0)
	_mat.set_shader_parameter("arcs", 0.0)
	_mat.set_shader_parameter("fade", 0.0)
	global_position = at
	_face_camera()


func _ground(at: Vector3, diameter: float) -> void:
	_quad(Vector2(diameter, diameter), SH_SCORCH, 1)
	_mat.set_shader_parameter("seed", randf() * 50.0)
	_mat.set_shader_parameter("wave", 0.0)
	_mat.set_shader_parameter("spread", 0.0)
	_mat.set_shader_parameter("fade", 0.0)
	global_position = at
	rotation.y = randf() * TAU


func _helix(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	_quad(Vector2(from.distance_to(to), 1.7), SH_HELIX, 5)
	_mat.set_shader_parameter("len", from.distance_to(to))
	_mat.set_shader_parameter("seed", randf() * 10.0)
	_mat.set_shader_parameter("head", 0.0)
	_mat.set_shader_parameter("burn", 0.0)
	global_position = (from + to) * 0.5
	_face_along()


## 창머리 판: 로컬 +X 끝이 창끝. 매 프레임 날아가는 자리로 옮긴다.
func _spear(from: Vector3, to: Vector3) -> void:
	_from = from
	_to = to
	_quad(Vector2(3.0, 1.25), SH_SPEAR, 7)
	_mat.set_shader_parameter("seed", randf() * 10.0)
	global_position = from
	_face_along()


func _star(at: Vector3, diameter: float) -> void:
	_quad(Vector2(diameter, diameter), SH_STAR, 6)
	_mat.set_shader_parameter("seed", randf() * 10.0)
	_mat.set_shader_parameter("burst", 0.0)
	global_position = at
	_face_camera()


## 땅의 균열 판: 땅에 눕히고 uv.x = a → b.
func _rift(a: Vector3, b: Vector3) -> void:
	_from = a
	_to = b
	var x := (b - a).normalized()
	_quad(Vector2(a.distance_to(b), 3.0), SH_RIFT, 2)
	_mat.set_shader_parameter("len", a.distance_to(b))
	_mat.set_shader_parameter("seed", randf() * 10.0)
	_mat.set_shader_parameter("reach", 0.0)
	_mat.set_shader_parameter("open", 0.0)
	global_position = (a + b) * 0.5 + Vector3(0, 0.05, 0)
	_mi.global_basis = Basis(x, Vector3.UP, x.cross(Vector3.UP))


## 하늘 기둥 판: 아래 끝이 ground 에 닿고 카메라를 정면으로 본다(uv.y 0 = 위).
func _pillar(ground: Vector3, height: float, width: float) -> void:
	_from = ground
	_quad(Vector2(width, height), SH_PILLAR, 4)
	_mat.set_shader_parameter("seed", randf() * 10.0)
	_mat.set_shader_parameter("drop", 0.0)
	_mat.set_shader_parameter("flash", 0.0)
	set_meta("height", height)
	global_position = ground
	_face_pillar()


func _light_at(local: Vector3, color: Color, energy: float, rng: float) -> void:
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = rng
	_light.light_energy = energy
	_light.position = local
	_light.set_meta("peak", energy)
	add_child(_light)


# ---------------------------------------------------------------- 내부 · 방향

func _cam() -> Camera3D:
	return get_viewport().get_camera_3d() if is_inside_tree() else null


## PlaneMesh 앞면은 +Y, 크기 x 는 로컬 X 축. X = 줄기 방향, Y = 줄기에 수직인 카메라 쪽.
func _face_along() -> void:
	var x := (_to - _from).normalized()
	var to_cam := Vector3.UP
	var cam := _cam()
	if cam != null:
		to_cam = (cam.global_position - global_position).normalized()
	var n := to_cam - x * to_cam.dot(x)
	if n.length() < 0.01:
		n = Vector3.UP - x * x.y
	n = n.normalized()
	_mi.global_basis = Basis(x, n, x.cross(n)).orthonormalized()


func _face_camera() -> void:
	var cam := _cam()
	if cam == null:
		_mi.global_basis = Basis(Vector3.RIGHT, Vector3.BACK, Vector3.DOWN)
		return
	var to_cam := (cam.global_position - global_position).normalized()
	var x := cam.global_basis.y.cross(to_cam).normalized()
	_mi.global_basis = Basis(x, to_cam, x.cross(to_cam)).orthonormalized()


## 기둥: 판 법선 = 카메라 쪽, 로컬 +Z = 화면에서 아래(땅) 방향. 아래 끝이 땅점에 오도록 판 가운데를 위로 올린다.
func _face_pillar() -> void:
	var n := Vector3.BACK
	var cam := _cam()
	if cam != null:
		n = (cam.global_position - _from).normalized()
	var z := Vector3.DOWN - n * Vector3.DOWN.dot(n)
	if z.length() < 0.01:
		z = Vector3.FORWARD
	z = z.normalized()
	var x := n.cross(z).normalized()
	_mi.global_basis = Basis(x, n, z)
	_mi.global_position = _from - z * float(get_meta("height", 7.0)) * 0.5


# ---------------------------------------------------------------- 내부 · 시간표

func _process(delta: float) -> void:
	t += delta
	if t < _delay:
		visible = false
		return
	var k := t - _delay
	if not visible:
		visible = true
		_appear()
	_step(k, delta)
	if k >= life:
		queue_free()


## 나타나는 순간 한 번: 흔들림·입자.
func _appear() -> void:
	if _shake > 0.0 and is_inside_tree():
		shake(get_tree().current_scene, _shake, 0.2)
	var P = Fx._p()
	if P == null:
		return
	match kind:
		Kind.STAR:
			var pos := global_position
			for i in 10:
				var v := Fx._rv(randf_range(3.5, 8.0))
				v.y = absf(v.y) + 1.0
				P.emit(Pool.STREAK, pos, v, randf_range(0.14, 0.28), randf_range(0.16, 0.28), C_GOLD_HOT if i % 2 else C_GOLD,
					{"gravity": -10.0, "align": true, "aspect": 0.2, "additive": true})
			P.emit(Pool.SHOCK, pos, Vector3.ZERO, 0.16, 1.4 * _mi.mesh.size.x / 2.2, C_GOLD, {"pop": true, "grow": 1.4, "additive": true})
		Kind.PILLAR:
			var g := _from
			P.emit(Pool.SHOCK, g + Vector3(0, 0.3, 0), Vector3.ZERO, 0.18, 1.6, C_MAGENTA, {"pop": true, "grow": 1.6, "additive": true})
			P.emit(Pool.RING, g + Vector3(0, 0.05, 0), Vector3.ZERO, 0.32, 0.6, Color(1.0, 0.45, 0.95, 0.85), {"ground": true, "additive": true, "grow": 3.0})
			for i in 7:
				var a := randf() * TAU
				var o := Vector3(cos(a), 0, sin(a))
				P.emit(Pool.STREAK, g + o * 0.2 + Vector3(0, 0.1, 0), o * randf_range(2.0, 4.5) + Vector3(0, randf_range(3.0, 6.0), 0),
					randf_range(0.3, 0.5), randf_range(0.12, 0.2), C_VOID if i % 2 else C_MAGENTA,
					{"gravity": -16.0, "align": true, "aspect": 0.4, "land": true, "additive": i % 2 == 0})
			for i in 4:
				var a := TAU * i / 4.0 + randf_range(-0.4, 0.4)
				P.emit(Pool.CLOUD, g + Vector3(cos(a), 0.15, sin(a)) * 0.4, Vector3(cos(a), 0.2, sin(a)) * 1.6,
					randf_range(0.5, 0.7), randf_range(0.5, 0.8), Color(0.25, 0.1, 0.35, 0.55), {"drag": 3.0, "grow": 1.8, "fade_in": 0.03})


func _step(k: float, delta: float) -> void:
	if _light != null:
		_light.light_energy = float(_light.get_meta("peak")) * exp(-k * 11.0) * (0.75 + 0.5 * randf())
	match kind:
		Kind.BOLT:
			_mat.set_shader_parameter("reach", _ease_out(clampf(k / REACH_T, 0.0, 1.0)))
			_mat.set_shader_parameter("dissolve", clampf((k - HOLD_T) / (life - HOLD_T), 0.0, 1.0))
			# 지직거림: 버티는 동안 일정 간격으로 모양을 새로 뽑고 밝기를 튀긴다
			_flick -= delta
			if _flick <= 0.0 and k < HOLD_T + 0.08:
				_flick = FLICKER_T
				_mat.set_shader_parameter("seed", randf() * 50.0)
			var base: float = get_meta("base_intensity", 1.0)
			var pop := 1.1 * exp(-k * 16.0) + (0.3 * randf() if k < HOLD_T else 0.0)
			_mat.set_shader_parameter("intensity", base * (1.0 + pop))
			_face_along()
			_mi.scale = Vector3(1.0, 1.0, 1.0 + 0.35 * exp(-k * 20.0))
		Kind.ORB:
			_mat.set_shader_parameter("pulse", exp(-k * 9.0))
			_mat.set_shader_parameter("arcs", _ease_out(clampf(k / (life * 0.6), 0.0, 1.0)))
			_mat.set_shader_parameter("fade", (1.0 - smoothstep(life * 0.45, life, k)) * minf(1.0, k / 0.02 + 0.3))
			_flick -= delta
			if _flick <= 0.0:
				_flick = 0.05
				_mat.set_shader_parameter("seed", randf() * 50.0)
			_face_camera()
			_mi.scale = Vector3.ONE * (0.6 + 0.6 * _ease_out(clampf(k / 0.08, 0.0, 1.0)))
		Kind.SCORCH:
			_mat.set_shader_parameter("wave", _ease_out(clampf(k / 0.22, 0.0, 1.0)) * 0.95)
			_mat.set_shader_parameter("spread", _ease_out(clampf(k / 0.08, 0.0, 1.0)))
			_mat.set_shader_parameter("cool", clampf((k - 0.12) / 0.6, 0.0, 1.0))
			_mat.set_shader_parameter("fade", 1.0 - smoothstep(life * 0.6, life, k))
		Kind.SPEAR:
			# 처음엔 빠르게 튀어나가 끝에서 살짝 감속(ease-out 약하게)
			var f := 1.0 - pow(1.0 - clampf(k / SPEAR_T, 0.0, 1.0), 1.6)
			var dir := (_to - _from).normalized()
			global_position = _from.lerp(_to, f) - dir * 1.5
			_mat.set_shader_parameter("flare", exp(-k * 25.0))
			_mat.set_shader_parameter("fade", 1.0)
			_face_along()
			var P = Fx._p()
			if P != null:
				# 창머리 뒤로 흩어지는 금빛 속도선
				var head := global_position + dir * 1.5
				for i in 2:
					P.emit(Pool.STREAK, head - dir * randf_range(0.2, 1.4) + Fx._rv(0.35), -dir * randf_range(1.0, 3.0), randf_range(0.08, 0.16),
						randf_range(0.2, 0.36), C_GOLD_HOT if i == 0 else C_GOLD, {"align": true, "aspect": 0.12, "additive": true})
		Kind.HELIX:
			var f := 1.0 - pow(1.0 - clampf(k / SPEAR_T, 0.0, 1.0), 1.6)
			_mat.set_shader_parameter("head", f)
			_mat.set_shader_parameter("burn", clampf((k - SPEAR_T - 0.04) / (life - SPEAR_T - 0.08), 0.0, 1.0))
			_face_along()
		Kind.STAR:
			_mat.set_shader_parameter("burst", _ease_out(clampf(k / life, 0.0, 1.0)))
			_mat.set_shader_parameter("fade", 1.0 - smoothstep(life * 0.7, life, k))
			_face_camera()
		Kind.RIFT:
			_mat.set_shader_parameter("reach", _ease_out(clampf(k / RIFT_T, 0.0, 1.0)))
			_mat.set_shader_parameter("open", _ease_out(clampf(k / (RIFT_T + 0.08), 0.0, 1.0)) * (1.0 - smoothstep(0.35, 0.65, k)))
			_mat.set_shader_parameter("fade", 1.0 - smoothstep(0.5, life, k))
		Kind.PILLAR:
			_mat.set_shader_parameter("drop", _ease_in(clampf(k / PILLAR_DROP, 0.0, 1.0)) * 1.02)
			var landed := k >= PILLAR_DROP
			_mat.set_shader_parameter("flash", exp(-(k - PILLAR_DROP) * 18.0) if landed else 0.0)
			_mat.set_shader_parameter("fade", 1.0 - smoothstep(life * 0.5, life, k))
			# 내리꽂힌 뒤 한 번 모양이 튄다
			if landed and not _landed:
				_landed = true
				_mat.set_shader_parameter("seed", randf() * 10.0)
			_face_pillar()
			_mi.scale = Vector3(1.0 + 0.5 * exp(-maxf(k - PILLAR_DROP, 0.0) * 14.0) * float(landed), 1.0, 1.0)


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _ease_in(x: float) -> float:
	return x * x
