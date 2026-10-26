extends Node3D
## 보름달 늑대인간 스킬 연출(표시 전용 — 피해·감속 판정은 actors/player.gd 가 한다).
## 면은 모두 shaders/vfx/werewolf/ 의 VisualShader(tools/build_werewolf_shaders.gd 로 재생성)로 그리고,
## 입자는 공용 VfxPool, 화면 흔들림은 World.shake 를 쓴다.
##
##   claw_rake   Q 할퀴기 한 번: 세 줄 발톱 자국이 0.09초에 그어지고 뜯긴 가장자리부터 타 사라짐(0.42) + 불씨·털 뭉치
##   bite_snap   물기: 송곳니 턱이 0.08초에 맞물리며 섬광 + 짧은 충격
##   slam        덮치기 착지: 지면 충격 고리·방사 균열·네 줄 발톱 패임(2.2초 뒤 식어 사라짐) + 눈 파편·흙먼지·보랏빛 순간광
##   moon_burst  변신: 바닥 보름달 문양 + 몸을 감싸는 광기 불꽃 기둥 + 보랏빛 연기
##   rage_trail  덮치기 도약 동안 몸을 따라오는 보랏빛 꼬리 리본 + 광기 불꽃(끝나면 줄어들며 사라짐)

const Fx := preload("res://scripts/visual/fx.gd")
const Pool := preload("res://scripts/visual/vfx/vfx_pool.gd")
const Ribbon := preload("res://scripts/visual/vfx/ribbon_trail.gd")
const SH_RAKE := preload("res://shaders/vfx/werewolf/ww_claw_rake.tres")
const SH_BITE := preload("res://shaders/vfx/werewolf/ww_bite_snap.tres")
const SH_SLAM := preload("res://shaders/vfx/werewolf/ww_ground_slam.tres")
const SH_MOON := preload("res://shaders/vfx/werewolf/ww_moon_sigil.tres")
const SH_WISP := preload("res://shaders/vfx/werewolf/ww_rage_wisp.tres")

const C_RAGE := Color(0.82, 0.38, 1.0)
const C_HOT := Color(1.0, 0.62, 0.92)
const C_FUR := Color(0.55, 0.56, 0.64)

enum Kind { RAKE, BITE, SLAM, MOON, WISP }

var kind := Kind.RAKE
var t := 0.0
var life := 0.5
var _mi: MeshInstance3D
var _mat: ShaderMaterial
var _light: OmniLight3D
var _follow: Node3D           # WISP: 따라갈 몸(없으면 제자리)
var _hold := 0.0              # WISP: 켜 두는 시간(끝나면 사그라든다)

static var _cyl: ArrayMesh


# ---------------------------------------------------------------- 공개 함수

## Q 할퀴기 한 번. origin = 늑대 발밑, dir = 할퀴는 방향(수평), side = +1 오른팔 / -1 왼팔.
static func claw_rake(parent: Node, origin: Vector3, dir: Vector3, side: float) -> Node3D:
	var f := Vector3(dir.x, 0, dir.z).normalized()
	var v := _spawn(parent, Kind.RAKE, 0.42)
	if v == null: return null
	var right := f.cross(Vector3.UP).normalized()
	# 바깥에서 안쪽으로 휘두른다: uv.x 가 휘두르는 방향. 살짝 비스듬히(대각선 베기) 눕혀 위 카메라에서 잘 보이게.
	var sweep := -right * side
	var b := _plane_basis(v, sweep, side)
	v._plane(Vector2(2.3, 1.25), SH_RAKE, 3)
	v.global_transform = Transform3D(b, origin + Vector3(0, 0.85, 0) + f * 1.05)
	v._mat.set_shader_parameter("seed", randf() * 10.0)
	v._mat.set_shader_parameter("progress", 0.0)
	v._light_at(Vector3.ZERO, C_RAGE, 1.6, 3.0)
	var P = Fx._p()
	if P != null:
		var at := origin + Vector3(0, 0.85, 0) + f * 1.1
		for i in 7:
			var vel := sweep * randf_range(2.5, 4.5) + f * randf_range(0.5, 2.0) + Vector3(0, randf_range(0.5, 2.0), 0)
			P.emit(Pool.STREAK, at - sweep * 0.6 + sweep * randf() * 1.2, vel, randf_range(0.18, 0.3), randf_range(0.14, 0.22),
				C_HOT if i % 2 else C_RAGE, {"gravity": -6.0, "align": true, "aspect": 0.3, "additive": true})
	return v


## 물기: 대상 앞에 송곳니 턱이 맞물린다. pos = 맞는 자리(가슴 높이), dir = 늑대 → 대상.
static func bite_snap(parent: Node, pos: Vector3, dir: Vector3, big := false) -> Node3D:
	var v := _spawn(parent, Kind.BITE, 0.32)
	if v == null: return null
	var s := 2.1 if big else 1.45
	v._plane(Vector2(s, s), SH_BITE, 4)
	v.global_position = pos - Vector3(dir.x, 0, dir.z).normalized() * 0.15
	v._mat.set_shader_parameter("close", 0.0)
	v._face_camera()
	Fx.hit(pos, Color(1.0, 0.45, 0.75), big)
	return v


## 덮치기 착지 지면 충격. dir = 덮친 방향(수평).
static func slam(parent: Node, pos: Vector3, dir: Vector3) -> Node3D:
	var v := _spawn(parent, Kind.SLAM, 2.3)
	if v == null: return null
	var f := Vector3(dir.x, 0, dir.z).normalized()
	if f.length() < 0.1: f = Vector3.FORWARD
	v._plane(Vector2(4.4, 4.4), SH_SLAM, 1)
	# 평면 uv.y(+Z) 가 덮친 방향을 향하게
	v.global_transform = Transform3D(Basis(f.cross(Vector3.UP).normalized() * -1.0, Vector3.UP, f), Vector3(pos.x, 0.045, pos.z))
	v._mat.set_shader_parameter("seed", randf() * 10.0)
	v._mat.set_shader_parameter("wave", 0.0)
	v._mat.set_shader_parameter("crack", 0.0)
	v._light_at(Vector3(0, 0.9, 0), C_RAGE, 4.5, 5.0)
	var P = Fx._p()
	if P != null:
		# 사방으로 튀는 눈 파편과 낮게 깔리는 흙먼지
		for i in 16:
			var a := randf() * TAU
			var o := Vector3(cos(a), 0, sin(a))
			P.emit(Pool.STREAK, pos + o * 0.4 + Vector3(0, 0.2, 0), o * randf_range(3.0, 6.0) + Vector3(0, randf_range(2.5, 5.5), 0),
				randf_range(0.35, 0.6), randf_range(0.14, 0.24), Color(0.92, 0.94, 1.0), {"gravity": -14.0, "align": true, "aspect": 0.35, "land": true})
		for i in 10:
			var a := TAU * i / 10.0 + randf_range(-0.2, 0.2)
			var o := Vector3(cos(a), 0, sin(a))
			P.emit(Pool.CLOUD if i % 2 else Pool.PUFF, pos + o * 0.7 + Vector3(0, 0.2, 0), o * randf_range(2.0, 3.2) + Vector3(0, 0.3, 0),
				randf_range(0.6, 0.9), randf_range(0.45, 0.7), Color(0.85, 0.82, 0.95, 0.5), {"drag": 3.0, "grow": 1.8, "fade_in": 0.05})
		P.emit(Pool.SHOCK, pos + Vector3(0, 0.6, 0), Vector3.ZERO, 0.22, 1.8, C_HOT, {"pop": true, "grow": 1.4, "additive": true})
	return v


## 변신: 바닥 보름달 문양 + 몸을 감싸는 광기 불꽃 기둥.
static func moon_burst(parent: Node, pos: Vector3) -> void:
	var v := _spawn(parent, Kind.MOON, 1.9)
	if v == null: return
	v._plane(Vector2(3.4, 3.4), SH_MOON, 1)
	v.global_position = Vector3(pos.x, 0.05, pos.z)
	v._mat.set_shader_parameter("reveal", 0.0)
	v._light_at(Vector3(0, 1.2, 0), Color(0.7, 0.5, 1.0), 5.0, 6.0)
	var w := _spawn(parent, Kind.WISP, 1.4)
	if w != null:
		w._cylinder(0.85, 2.6)
		w.global_position = Vector3(pos.x, 0.0, pos.z)
		w._hold = 0.55
	var P = Fx._p()
	if P != null:
		for i in 14:
			var a := randf() * TAU
			P.emit(Pool.SPARKLE if i % 3 else Pool.STAR, pos + Vector3(cos(a), 0, sin(a)) * randf_range(0.3, 1.4) + Vector3(0, randf_range(0.2, 1.5), 0),
				Vector3(0, randf_range(0.8, 1.8), 0), randf_range(0.6, 1.0), randf_range(0.16, 0.28), Color(0.85, 0.7, 1.0),
				{"additive": true, "spin": randf_range(-6, 6), "pop": true})


## 덮치기 도약 동안 몸을 따라오는 꼬리 리본 + 몸 둘레 광기 불꽃. hold 초 뒤 사그라든다.
static func rage_trail(parent: Node, body: Node3D, hold: float) -> void:
	if parent == null or body == null or not body.is_inside_tree():
		return
	var marker := Node3D.new()
	marker.name = "RageTrailMarker"
	marker.position = Vector3(0, 0.75, 0)
	body.add_child(marker)
	Ribbon.follow(parent, marker, C_RAGE, Color(1.0, 0.9, 1.0), 0.42, 0.22, 2.0)
	var tw := marker.create_tween()
	tw.tween_interval(hold)
	tw.tween_callback(marker.queue_free)
	var w := _spawn(parent, Kind.WISP, hold + 0.45)
	if w != null:
		w._cylinder(0.6, 1.9)
		w._follow = body
		w._hold = hold


## 타격 순간 화면 흔들림(World.shake). game 이 없으면(검증 장면) 무시.
static func shake(game: Node, amount: float, duration: float) -> void:
	if game != null and is_instance_valid(game) and game.get("world") != null and game.world.has_method("shake"):
		game.world.shake(amount, duration)


# ---------------------------------------------------------------- 내부

static func _spawn(parent: Node, k: Kind, lifetime: float) -> Node3D:
	if parent == null or not is_instance_valid(parent) or not parent.is_inside_tree():
		return null
	var v = load("res://scripts/visual/vfx/werewolf_vfx.gd").new()
	v.kind = k
	v.life = lifetime
	v.name = "WerewolfVfx_" + Kind.keys()[k]
	parent.add_child(v)
	return v


## 할퀴기 판: uv.x = 휘두르는 방향. 판 법선을 위와 카메라 사이로 세워 위에서 내려다보는 화면에서도 세 줄이 또렷하고,
## 휘두르는 방향으로 20도 비스듬히(대각선 베기) 돌린다. PlaneMesh 앞면은 +Y.
static func _plane_basis(v: Node3D, sweep: Vector3, side: float) -> Basis:
	var n := Vector3.UP
	var cam := v.get_viewport().get_camera_3d() if v.is_inside_tree() else null
	if cam != null:
		n = (Vector3.UP + (cam.global_position - v.global_position).normalized() * 0.9).normalized()
	var x := (sweep - n * sweep.dot(n)).normalized()
	x = x.rotated(n, deg_to_rad(20.0 * side))
	return Basis(x, n, x.cross(n)).orthonormalized()


func _plane(size: Vector2, sh: Shader, priority: int) -> void:
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


func _cylinder(radius: float, height: float) -> void:
	_mi = MeshInstance3D.new()
	_mi.mesh = _get_cyl()
	_mat = ShaderMaterial.new()
	_mat.shader = SH_WISP
	_mat.render_priority = 2
	_mat.set_shader_parameter("seed", randf() * 10.0)
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.scale = Vector3(radius, height, radius)
	add_child(_mi)


func _light_at(at: Vector3, color: Color, energy: float, rng: float) -> void:
	_light = OmniLight3D.new()
	_light.light_color = color
	_light.omni_range = rng
	_light.light_energy = energy
	_light.position = at
	_light.set_meta("peak", energy)
	add_child(_light)


## 판을 카메라 쪽으로 세운다(물기 턱은 화면에 정면으로 보여야 읽힌다). PlaneMesh 앞면은 +Y.
func _face_camera() -> void:
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	if cam == null: return
	var to_cam := (cam.global_position - global_position).normalized()
	var up_hint := cam.global_basis.y
	var x := up_hint.cross(to_cam).normalized()
	var z := x.cross(to_cam).normalized() * -1.0
	_mi.global_basis = Basis(x, to_cam, -z).orthonormalized()


func _process(delta: float) -> void:
	t += delta
	_step()
	if t >= life:
		queue_free()


func _step() -> void:
	if _light != null:
		_light.light_energy = float(_light.get_meta("peak")) * exp(-t * 9.0)
	match kind:
		Kind.RAKE:
			_mat.set_shader_parameter("progress", _ease_out(clampf(t / 0.09, 0.0, 1.0)))
			_mat.set_shader_parameter("burn", clampf((t - 0.1) / 0.3, 0.0, 1.0))
			_mat.set_shader_parameter("intensity", 1.0 + 1.6 * exp(-t * 20.0))
		Kind.BITE:
			var c := _ease_in(clampf(t / 0.08, 0.0, 1.0))
			_mat.set_shader_parameter("close", c)
			_mat.set_shader_parameter("flash", clampf((t - 0.07) / 0.12, 0.0, 1.0) * exp(-maxf(t - 0.08, 0.0) * 10.0) * 1.0)
			_mat.set_shader_parameter("fade", 1.0 - smoothstep(0.16, 0.32, t))
			_mi.scale = Vector3.ONE * (1.0 + 0.25 * clampf((t - 0.08) / 0.2, 0.0, 1.0))
			_face_camera()
		Kind.SLAM:
			_mat.set_shader_parameter("wave", _ease_out(clampf(t / 0.3, 0.0, 1.0)) * 0.95)
			_mat.set_shader_parameter("crack", _ease_out(clampf(t / 0.12, 0.0, 1.0)))
			_mat.set_shader_parameter("cool", clampf((t - 0.25) / 0.9, 0.0, 1.0))
			_mat.set_shader_parameter("fade", 1.0 - smoothstep(1.6, 2.3, t))
		Kind.MOON:
			_mat.set_shader_parameter("reveal", _ease_out(clampf(t / 0.35, 0.0, 1.0)) * 1.05)
			_mat.set_shader_parameter("intensity", 1.0 + 2.0 * exp(-t * 6.0))
			_mat.set_shader_parameter("fade", 1.0 - smoothstep(1.2, 1.9, t))
			rotation.y = t * 0.3
		Kind.WISP:
			if _follow != null and is_instance_valid(_follow):
				global_position = _follow.global_position
			_mat.set_shader_parameter("rise", clampf(t / 0.2, 0.0, 1.0))
			_mat.set_shader_parameter("fade", 1.0 - smoothstep(_hold, life, t))


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _ease_in(x: float) -> float:
	return x * x * x


## 뚜껑 없는 원통(반지름 1, 높이 1, 바닥 y=0). uv.x = 둘레, uv.y = 높이 비율.
static func _get_cyl() -> ArrayMesh:
	if _cyl != null:
		return _cyl
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 24
	for i in n:
		var a0 := TAU * i / n
		var a1 := TAU * (i + 1) / n
		var p0 := Vector3(cos(a0), 0, sin(a0))
		var p1 := Vector3(cos(a1), 0, sin(a1))
		var u0 := float(i) / n
		var u1 := float(i + 1) / n
		for v in [[p0, Vector2(u0, 0)], [p1, Vector2(u1, 0)], [p1 + Vector3.UP, Vector2(u1, 1)],
				[p0, Vector2(u0, 0)], [p1 + Vector3.UP, Vector2(u1, 1)], [p0 + Vector3.UP, Vector2(u0, 1)]]:
			var pos: Vector3 = v[0]
			st.set_normal(Vector3(pos.x, 0, pos.z).normalized())
			st.set_uv(v[1])
			st.add_vertex(pos)
	_cyl = st.commit()
	return _cyl
