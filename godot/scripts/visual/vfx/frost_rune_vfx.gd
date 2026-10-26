extends Node3D
## 서리 룬 폭발 연출(표시 전용 — 피해·감속 판정은 actors/frost_rune.gd 가 한다).
## 모든 면은 shaders/vfx/frost_rune/ 의 VisualShader(tools/build_frost_rune_shaders.gd 로 재생성)로 그린다.
##
## 시간표(초)
##   0.00  룬 문양이 위에서부터 그려지며 섬광 · 냉기 빛기둥이 솟음 · 차가운 빛
##   0.00  톱니 결정 충격 고리가 반경 끝까지 퍼짐(0.4) · 서리가 바닥에 번짐(0.35)
##   0.02  얼음 결정 무리가 안쪽부터 바깥으로 솟음(겹겹이 0.14) · 얼음 파편·눈송이·냉기 연무
##   1.25  결정이 끝부터 녹아내림(0.55) · 문양이 옅어짐(1.35~2.0)
##   1.60  바닥 서리가 바깥부터 녹음(1.0) → 2.7 에 스스로 사라짐

const Fx := preload("res://scripts/visual/fx.gd")
const Pool := preload("res://scripts/visual/vfx/vfx_pool.gd")
const SH_SIGIL := preload("res://shaders/vfx/frost_rune/frost_sigil.tres")
const SH_RIME := preload("res://shaders/vfx/frost_rune/frost_rime.tres")
const SH_SHOCK := preload("res://shaders/vfx/frost_rune/frost_shock.tres")
const SH_PILLAR := preload("res://shaders/vfx/frost_rune/frost_pillar.tres")
const SH_CRYSTAL := preload("res://shaders/vfx/frost_rune/frost_crystal.tres")

const C_ICE := Color(0.62, 0.86, 1.0)
const C_MIST := Color(0.8, 0.86, 1.0, 0.22)
const C_RUNE := Color(0.74, 0.62, 1.0)
const LIFE := 2.7
const SIGIL_EXTENT := 1.12
const MAX_ENCASE := 8

var radius := 2.6
var t := 0.0
var _sigil: MeshInstance3D
var _rime: MeshInstance3D
var _shock: MeshInstance3D
var _pillar: MeshInstance3D
var _light: OmniLight3D
var _clusters: Array = []     # {pivot, mat, delay, melt_at, flash}
var _encased := 0
var _spin0 := 0.0

static var _shards: Array = []
static var _pillar_mesh: ArrayMesh


func _ready() -> void:
	name = "FrostRuneVfx"
	var d := radius * 2.0
	_rime = _ground(d * 1.05, 0.03, SH_RIME, 0)
	_rime.material_override.set_shader_parameter("spread", 0.0)
	_rime.material_override.set_shader_parameter("cell_scale", 7.0)
	_rime.material_override.set_shader_parameter("opacity", 0.62)
	_sigil = _ground(d * SIGIL_EXTENT, 0.05, SH_SIGIL, 1)
	_sigil.material_override.set_shader_parameter("extent", SIGIL_EXTENT)
	_sigil.material_override.set_shader_parameter("reveal", 0.0)
	_spin0 = randf() * TAU
	_shock = _ground(d * 1.2, 0.07, SH_SHOCK, 2)
	_shock.material_override.set_shader_parameter("wave", 0.0)
	_pillar = MeshInstance3D.new()
	_pillar.name = "FrostPillar"
	_pillar.mesh = _get_pillar_mesh()
	_pillar.material_override = _mat(SH_PILLAR, 3)
	_pillar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_pillar.scale = Vector3(radius * 0.38, 3.4, radius * 0.38)
	add_child(_pillar)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.55, 0.8, 1.0)
	_light.omni_range = radius * 2.2
	_light.light_energy = 0.0
	_light.position = Vector3(0, 1.2, 0)
	add_child(_light)
	_spawn_crystals()
	_emit_particles()
	_step(0.0)


func _process(delta: float) -> void:
	t += delta
	_step(t)
	if t >= LIFE:
		queue_free()


## 적이 맞은 자리에 작은 결정이 순간 얼어붙었다가 부서진다.
func encase(world_pos: Vector3) -> void:
	if _encased >= MAX_ENCASE:
		return
	_encased += 1
	var local := to_local(Vector3(world_pos.x, global_position.y, world_pos.z))
	_cluster(local, 0.6, 3, 0.05, 0.8)
	var P = Fx._p()
	if P != null:
		for i in 5:
			var v := Vector3(randf_range(-1, 1), randf_range(0.6, 1.6), randf_range(-1, 1)) * 2.2
			P.emit(Pool.STREAK, world_pos + Vector3(0, 0.5, 0), v, randf_range(0.3, 0.45), randf_range(0.14, 0.22),
				Color(0.85, 0.95, 1.0), {"gravity": -9.0, "align": true, "aspect": 0.35, "additive": true})


func _step(time: float) -> void:
	# 룬 문양: 0.22초에 그려지고, 섬광 뒤 은은하게 빛나다 옅어진다.
	var sm: ShaderMaterial = _sigil.material_override
	sm.set_shader_parameter("reveal", _ease_out(clampf(time / 0.22, 0.0, 1.0)))
	sm.set_shader_parameter("intensity", 1.0 + 2.4 * exp(-time * 8.0) + 0.12 * sin(time * 9.0))
	sm.set_shader_parameter("fade", 1.0 - smoothstep(1.35, 2.0, time))
	var pop := 0.86 + 0.14 * _back_out(clampf(time / 0.28, 0.0, 1.0))
	_sigil.scale = Vector3(pop, 1.0, pop) * (1.0 + 0.05 * smoothstep(1.35, 2.0, time))
	_sigil.rotation.y = _spin0 + time * 0.22
	# 충격 고리
	var sw := clampf(time / 0.4, 0.0, 1.0)
	var shm: ShaderMaterial = _shock.material_override
	shm.set_shader_parameter("wave", (1.0 - pow(1.0 - sw, 3.0)) * 0.92)
	shm.set_shader_parameter("energy", 1.0 - smoothstep(0.22, 0.5, time))
	_shock.visible = time < 0.55
	# 냉기 빛기둥
	var pm: ShaderMaterial = _pillar.material_override
	pm.set_shader_parameter("rise", clampf(time / 0.12, 0.0, 1.0))
	pm.set_shader_parameter("fade", 1.0 - smoothstep(0.1, 0.55, time))
	var pw := radius * (0.34 + 0.12 * clampf(time / 0.55, 0.0, 1.0))
	_pillar.scale = Vector3(pw, 3.4, pw)
	_pillar.visible = time < 0.6
	# 서리 번짐 → 녹음
	var rm: ShaderMaterial = _rime.material_override
	rm.set_shader_parameter("spread", _ease_out(clampf(time / 0.35, 0.0, 1.0)))
	rm.set_shader_parameter("melt", clampf((time - 1.6) / 1.0, 0.0, 1.0))
	# 차가운 빛
	_light.light_energy = 3.2 * exp(-time * 5.0) + 0.6 * (1.0 - smoothstep(0.4, 1.8, time))
	# 얼음 결정
	for c in _clusters:
		var lt: float = time - c["delay"]
		var pivot: Node3D = c["pivot"]
		var mat: ShaderMaterial = c["mat"]
		if lt < 0.0:
			pivot.visible = false
			continue
		pivot.visible = true
		var g := _back_out(clampf(lt / 0.14, 0.0, 1.0))
		var sink := smoothstep(c["melt_at"], c["melt_at"] + 0.55, lt) * 0.25
		pivot.scale = Vector3(0.55 + 0.45 * g, maxf(g - sink, 0.02), 0.55 + 0.45 * g) * c["size"]
		mat.set_shader_parameter("flash", exp(-lt * 9.0) * 0.85)
		mat.set_shader_parameter("melt", clampf((lt - c["melt_at"]) / 0.55, 0.0, 1.0))


# ---------------------------------------------------------------- 구성

func _spawn_crystals() -> void:
	# 바깥 고리: 9무리, 안쪽: 3무리. 안쪽부터 바깥으로 차례로 솟는다.
	var outer := 9
	var off := randf() * TAU
	for i in outer:
		var a := off + TAU * i / outer + randf_range(-0.18, 0.18)
		var rr := radius * randf_range(0.62, 0.9)
		_cluster(Vector3(cos(a), 0, sin(a)) * rr, randf_range(1.2, 1.65), randi_range(3, 4), 0.06 + rr / radius * 0.1, randf_range(1.15, 1.4))
	for i in 3:
		var a := off + TAU * (i + 0.5) / 3.0
		var rr := radius * randf_range(0.24, 0.36)
		_cluster(Vector3(cos(a), 0, sin(a)) * rr, randf_range(0.8, 1.05), 2, 0.02, randf_range(1.05, 1.25))


## 결정 한 무리: 바닥 중심(pivot)에서 바깥으로 기운 뾰족 결정 여러 개.
func _cluster(at: Vector3, size: float, count: int, delay: float, melt_at: float) -> void:
	var pivot := Node3D.new()
	pivot.name = "IceCluster"
	pivot.position = at
	pivot.rotation.y = randf() * TAU
	add_child(pivot)
	var mat := _mat(SH_CRYSTAL, 0)
	mat.set_shader_parameter("seed", randf() * 10.0)
	var out_dir := Vector3(at.x, 0, at.z)
	var out_yaw := atan2(out_dir.x, out_dir.z) - pivot.rotation.y if out_dir.length() > 0.05 else randf() * TAU
	for k in count:
		var shard := MeshInstance3D.new()
		shard.mesh = _get_shard(randi() % 4)
		shard.material_override = mat
		shard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var h := 1.0 if k == 0 else randf_range(0.45, 0.75)
		var w := 1.0 if k == 0 else randf_range(0.6, 0.85)
		var side := Vector3(randf_range(-0.16, 0.16), 0, randf_range(-0.16, 0.16)) if k > 0 else Vector3.ZERO
		shard.position = side
		shard.scale = Vector3(w, h, w)
		# 바깥쪽으로 기울어진 채 솟는다(가운데 결정은 덜 기운다).
		var lean := randf_range(0.12, 0.3) if k == 0 else randf_range(0.35, 0.65)
		var yaw := out_yaw + randf_range(-0.9, 0.9) * (0.3 if k == 0 else 1.0)
		shard.basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, lean) * Basis.from_scale(Vector3(w, h, w))
		pivot.add_child(shard)
	_clusters.append({"pivot": pivot, "mat": mat, "delay": delay, "melt_at": melt_at, "size": size})


func _emit_particles() -> void:
	var P = Fx._p()
	if P == null:
		return
	var c := global_position
	# 얼음 파편: 바깥 위로 튀어 떨어진다.
	for i in 18:
		var a := randf() * TAU
		var v := Vector3(cos(a), 0, sin(a)) * randf_range(2.5, 5.0) + Vector3(0, randf_range(2.5, 5.0), 0)
		P.emit(Pool.STREAK, c + Vector3(cos(a), 0, sin(a)) * radius * 0.3 + Vector3(0, 0.3, 0), v, randf_range(0.45, 0.7),
			randf_range(0.16, 0.28), Color(0.82, 0.94, 1.0), {"gravity": -12.0, "align": true, "aspect": 0.32, "additive": true, "land": true})
	# 눈송이: 천천히 떠올랐다 내려앉는다.
	for i in 16:
		var a := randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * radius * randf_range(0.1, 0.95) + Vector3(0, randf_range(0.2, 1.2), 0)
		P.emit(Pool.FLAKE, p, Vector3(randf_range(-0.3, 0.3), randf_range(0.6, 1.4), randf_range(-0.3, 0.3)), randf_range(1.2, 1.9),
			randf_range(0.14, 0.24), Color(0.92, 0.97, 1.0), {"gravity": -0.8, "drag": 1.2, "spin": randf_range(-3, 3), "sway": 0.6, "fade_in": 0.1})
	# 가장자리 냉기 연무
	for i in 8:
		var a := TAU * i / 8.0 + randf_range(-0.2, 0.2)
		var dir := Vector3(cos(a), 0, sin(a))
		P.emit(Pool.CLOUD if i % 2 else Pool.PUFF, c + dir * radius * 0.85 + Vector3(0, 0.25, 0), dir * 1.6 + Vector3(0, 0.3, 0),
			randf_range(0.7, 1.0), randf_range(0.4, 0.6), C_MIST, {"drag": 2.5, "grow": 1.7, "fade_in": 0.1})
	# 반짝이: 결정 위로 오르는 서리 빛
	for i in 14:
		var a := randf() * TAU
		var p := c + Vector3(cos(a), 0, sin(a)) * radius * randf_range(0.2, 0.9) + Vector3(0, randf_range(0.3, 1.2), 0)
		P.emit(Pool.SPARKLE if i % 3 else Pool.STAR, p, Vector3(0, randf_range(0.5, 1.4), 0), randf_range(0.6, 1.1),
			randf_range(0.14, 0.26), C_ICE.lightened(0.35), {"additive": true, "spin": randf_range(-6, 6), "pop": true, "fade_in": 0.05})


func _ground(size: float, y: float, sh: Shader, priority: int) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(size, size)
	m.mesh = pm
	m.material_override = _mat(sh, priority)
	m.material_override.set_shader_parameter("seed", randf() * 10.0)
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = Vector3(0, y, 0)
	add_child(m)
	return m


static func _mat(sh: Shader, priority: int) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = priority
	return m


static func _ease_out(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)


static func _back_out(x: float) -> float:
	var c1 := 1.9
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


# ---------------------------------------------------------------- 메시(한 번 만들어 재사용)

## 뾰족한 얼음 결정(높이 1, 바닥 반지름 약 0.13). 면마다 평평한 법선, uv.y = 높이 비율.
static func _get_shard(variant: int) -> ArrayMesh:
	if _shards.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 7151
		for v in 4:
			_shards.append(_build_shard(rng, 5 + v % 2))
	return _shards[variant % _shards.size()]


static func _build_shard(rng: RandomNumberGenerator, sides: int) -> ArrayMesh:
	var base: Array[Vector3] = []
	var shoulder: Array[Vector3] = []
	var rb := 0.19
	var sh_y := rng.randf_range(0.55, 0.7)
	for i in sides:
		var a := TAU * i / sides + rng.randf_range(-0.2, 0.2)
		var r1 := rb * rng.randf_range(0.8, 1.15)
		base.append(Vector3(cos(a) * r1, -0.06, sin(a) * r1))
		var r2 := r1 * rng.randf_range(0.82, 0.98)
		shoulder.append(Vector3(cos(a) * r2, sh_y + rng.randf_range(-0.06, 0.06), sin(a) * r2))
	var tip := Vector3(rng.randf_range(-0.02, 0.02), 1.0, rng.randf_range(-0.02, 0.02))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in sides:
		var j := (i + 1) % sides
		var u0 := float(i) / sides
		var u1 := float(i + 1) / sides
		_tri(st, base[i], base[j], shoulder[j], Vector2(u0, 0), Vector2(u1, 0), Vector2(u1, shoulder[j].y))
		_tri(st, base[i], shoulder[j], shoulder[i], Vector2(u0, 0), Vector2(u1, shoulder[j].y), Vector2(u0, shoulder[i].y))
		_tri(st, shoulder[i], shoulder[j], tip, Vector2(u0, shoulder[i].y), Vector2(u1, shoulder[j].y), Vector2((u0 + u1) * 0.5, 1.0))
	return st.commit()


## 바깥을 향한 평면 법선의 삼각형(감기 방향도 바깥 기준으로 맞춘다).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ua: Vector2, ub: Vector2, uc: Vector2) -> void:
	var n := (c - a).cross(b - a).normalized()
	var mid := (a + b + c) / 3.0
	if n.dot(Vector3(mid.x, 0, mid.z)) < 0.0:
		var tmp := b
		b = c
		c = tmp
		var tu := ub
		ub = uc
		uc = tu
		n = -n
	for pair in [[a, ua], [b, ub], [c, uc]]:
		st.set_normal(n)
		st.set_uv(pair[1])
		st.add_vertex(pair[0])


## 뚜껑 없는 원통(반지름 1, 높이 1, 바닥 y=0). uv.x = 둘레, uv.y = 높이 비율.
static func _get_pillar_mesh() -> ArrayMesh:
	if _pillar_mesh != null:
		return _pillar_mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 28
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
	_pillar_mesh = st.commit()
	return _pillar_mesh


# ---------------------------------------------------------------- 감속 표식(적 발밑)

## 느려진 적 발밑의 서리 자국. 같은 서리 셰이더를 작게, 세포를 크게 쓴다.
static func slow_mark(parent: Node3D) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.name = "FrostSlowMark"
	var pm := PlaneMesh.new()
	pm.size = Vector2(1.5, 1.5)
	m.mesh = pm
	var mat := _mat(SH_RIME, 0)
	mat.set_shader_parameter("seed", randf() * 10.0)
	mat.set_shader_parameter("cell_scale", 3.2)
	mat.set_shader_parameter("opacity", 0.72)
	mat.set_shader_parameter("spread", 0.0)
	m.material_override = mat
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	m.position = Vector3(0, 0.04, 0)
	m.visible = false
	parent.add_child(m)
	return m


## 켜면 서리가 번지고, 끄면 녹아 사라진다.
static func set_slow_mark(m: MeshInstance3D, on: bool) -> void:
	if m == null or not is_instance_valid(m):
		return
	var showing: bool = m.get_meta("frost_on", false)
	if showing == on:
		return
	m.set_meta("frost_on", on)
	var mat: ShaderMaterial = m.material_override
	if m.has_meta("frost_tw"):
		var old: Tween = m.get_meta("frost_tw")
		if old != null and old.is_valid():
			old.kill()
	var tw := m.create_tween()
	m.set_meta("frost_tw", tw)
	if on:
		m.visible = true
		mat.set_shader_parameter("melt", 0.0)
		tw.tween_method(func(v: float): mat.set_shader_parameter("spread", v), 0.0, 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		tw.tween_method(func(v: float): mat.set_shader_parameter("melt", v), 0.0, 1.0, 0.45)
		tw.tween_callback(func(): m.visible = false)
