extends RefCounted
## 니벨라 둥지의 서리 거미줄 막과 서리 알. 무늬·흔들림은 VisualShader(tools/build_nivella_web_shader.gd 가 만든
## shaders/vfx/nivella/nv_frost_web.tres · nv_frost_egg.tres)가 그리고, 여기서는 모양(메시)과 충격파 전달을 맡는다.
## 기준(사용자 레퍼런스 2026-10-23): 끈적한 막이 붙은 곳에서 한 방향으로 흘러내리며 길고 짧은 가닥으로 갈라져 뾰족하게 박힌다.
##  - curtain: 두 기둥 끝 사이에 걸려 둥지 안쪽(보스 쪽) 바닥으로 흘러내리는 막
##  - splat:   바닥에 납작하게 퍼진 막(가운데가 살짝 부푼 별 모양)
##  - shroud:  알을 위에서 감싸고 아래로 흘러 땅에 가닥을 박는 덮개
##  - egg:     속이 비치는 얼음 젤리 알
## 메시 UV = (가닥 좌표: 정수 하나가 가닥 하나, 흐름 0 붙은 쪽 → 1 끝), 정점색 R = 흔들림 가중치.
## 흔들림: 바람에 늘 살랑이고, shock(위치, 세기) 로 알린 충격파가 거리만큼 늦게 닿아 출렁였다 잦아든다(최근 4개).
const WEB_SHADER := preload("res://shaders/vfx/nivella/nv_frost_web.tres")
const EGG_SHADER := preload("res://shaders/vfx/nivella/nv_frost_egg.tres")
const SLOTS := ["shock_a", "shock_b", "shock_c", "shock_d"]
const SHOCK_LIFE := 4.0

static var _mat: ShaderMaterial
static var _egg_mat: ShaderMaterial
static var _shocks: Array = []      # [위치, 경과 초, 세기]
static var _strand_offset := 0      # 메시마다 가닥 무늬가 겹치지 않게 UV.x 를 정수만큼 민다
static var shocks_sent := 0         # 검증용


static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = WEB_SHADER
	return _mat


static func egg_material() -> ShaderMaterial:
	if _egg_mat == null:
		_egg_mat = ShaderMaterial.new()
		_egg_mat.shader = EGG_SHADER
	return _egg_mat


# ───────────────────────── 메시 ─────────────────────────

## 격자 한 장: pos(u, v) → 로컬 위치, pin(v) → 흔들림 가중치. strands = u 0~1 에 들어갈 가닥 수.
## membrane = 붙은 쪽에서 가닥으로 갈라지기 전까지 막 길이(정점색 G, 셰이더가 읽음). off >= 0 이면 가닥 무늬 시작을 고정.
static func _sheet(nu: int, nv: int, strands: int, pos: Callable, pin: Callable, membrane := 0.0, off_fixed := -1) -> ArrayMesh:
	_strand_offset += strands + 3
	var off := float(_strand_offset if off_fixed < 0 else off_fixed)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j in nv + 1:
		var v := float(j) / nv
		for i in nu + 1:
			var u := float(i) / nu
			st.set_color(Color(float(pin.call(v)), membrane, 0.0, 1.0))
			st.set_uv(Vector2(u * strands + off, v))
			st.add_vertex(pos.call(u, v))
	for j in nv:
		for i in nu:
			var a := j * (nu + 1) + i
			var b := a + 1
			var c := a + nu + 1
			var d := c + 1
			for idx in [a, c, b, b, c, d]:
				st.add_index(idx)
	st.generate_normals()
	return st.commit()


static func _mi(mesh: Mesh, mat: Material, n: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = n
	mi.mesh = mesh
	mi.material_override = mat
	return mi


static func _bezier(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	return a * (1.0 - t) * (1.0 - t) + c * 2.0 * (1.0 - t) * t + b * t * t


## 두 기둥 끝(top_a·top_b) 사이에 걸려 drop(바닥) 쪽으로 흘러내리는 막. spread = 바닥에서 퍼지는 폭.
static func make_curtain(top_a: Vector3, top_b: Vector3, drop: Vector3, spread: float, strands := 10) -> MeshInstance3D:
	var across := top_b - top_a
	across.y = 0.0
	across = across.normalized()
	var sag := top_a.distance_to(top_b) * 0.1
	var mid_top := (top_a + top_b) * 0.5
	var pos := func(u: float, v: float) -> Vector3:
		var top: Vector3 = top_a.lerp(top_b, u) + Vector3.DOWN * sag * sin(PI * u)
		# 바닥 고정점은 위쪽보다 넓게 부채꼴로 벌어져 가닥이 비스듬히 팽팽하게 뻗는다
		var ground: Vector3 = drop + across * (u - 0.5) * spread
		ground.y = 0.03
		var out: Vector3 = (ground - Vector3(mid_top.x, 0.03, mid_top.z)).normalized()
		if v <= 0.84:
			var t := v / 0.84
			var ctrl: Vector3 = top.lerp(ground, 0.5) + Vector3.DOWN * top.y * 0.18
			return _bezier(top, ctrl, ground, t)
		# 끝 16%: 땅에 닿은 뒤 바깥으로 조금 기어가며 뾰족해진다
		return ground + out * (v - 0.84) / 0.16 * spread * 0.12
	var pin := func(v: float) -> float: return sin(PI * v)
	return _mi(_sheet(28, 22, strands, pos, pin), material(), "FrostWebCurtain")


## 바닥에 퍼진 막: center 에서 radius 까지 별 모양 가닥, 가운데가 lift 만큼 부푼다.
static func make_splat(center: Vector3, radius: float, strands := 9, lift := 0.35) -> MeshInstance3D:
	var pos := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var r := v * radius
		return center + Vector3(cos(a) * r, 0.03 + lift * pow(1.0 - v, 2.0), sin(a) * r)
	var pin := func(v: float) -> float: return 0.35 * sin(PI * v)
	return _mi(_sheet(36, 12, strands, pos, pin, 0.2), material(), "FrostWebSplat")


## 알을 감싼 막: 알(바닥 중심 base, 반지름 rx, 높이 h) 꼭대기에서 몸을 타고 내려와 reach 만큼 땅에 가닥을 뻗는다.
## bias_dir 쪽(예: 보스)으로 가닥이 더 길게 뻗어 둥지 전체에 흐름이 생긴다. cover = 덮개 막 길이(0~0.5).
static func make_shroud(base: Vector3, rx: float, h: float, reach: float, strands := 9, phase := 0.0,
		bias_dir := Vector3.ZERO, bias := 0.0, cover := 0.36) -> MeshInstance3D:
	var cy := h * 0.5
	var phi_end := 1.85
	var on_egg := func(dir: Vector3, phi: float) -> Vector3:
		return base + dir * sin(phi) * rx * 1.04 + Vector3.UP * (cy + cos(phi) * h * 0.5 * 1.03)
	var pos := func(u: float, v: float) -> Vector3:
		var a := u * TAU
		var dir := Vector3(cos(a), 0.0, sin(a))
		if v <= 0.5:
			return on_egg.call(dir, v / 0.5 * phi_end)
		var start: Vector3 = on_egg.call(dir, phi_end)
		var far := rx + reach * (0.75 + 0.35 * sin(a * 3.0 + phase)) * (1.0 + bias * maxf(dir.dot(bias_dir), 0.0))
		var end := base + dir * far * 0.72 + Vector3.UP * 0.03
		if v <= 0.85:
			var t := (v - 0.5) / 0.35
			var ctrl := start + dir * rx * 0.45 + Vector3.DOWN * h * 0.2
			return _bezier(start, ctrl, end, t)
		# 땅에 닿은 가닥이 바깥으로 길게 기어간다
		return end + dir * far * 0.28 * (v - 0.85) / 0.15
	var pin := func(v: float) -> float: return 0.15 if v < 0.5 else sin(PI * v) * 0.8
	return _mi(_sheet(40, 26, strands, pos, pin, cover), material(), "FrostEggShroud")


## 팽팽하게 걸린 실 한 가닥: top 에서 ground 로 처지며 내려가 땅에 바늘처럼 박힌다. thick = 굵은 주 가닥.
static func make_strand(top: Vector3, ground: Vector3, width: float, thick := true) -> MeshInstance3D:
	ground.y = 0.03
	var flat := ground - top
	flat.y = 0.0
	var side := flat.normalized().cross(Vector3.UP) * width
	var droop := top.y * 0.22
	var pos := func(u: float, v: float) -> Vector3:
		var ctrl := top.lerp(ground, 0.5) + Vector3.DOWN * droop
		return _bezier(top, ctrl, ground, v) + side * (u - 0.5)
	var pin := func(v: float) -> float: return sin(PI * v)
	# 셰이더는 floor(UV.x) 가 3의 배수인 칸을 굵은 주 가닥으로 그린다
	return _mi(_sheet(4, 24, 1, pos, pin, 0.0, 300 if thick else 301), material(), "FrostWebStrand")


## 얼음 젤리 알 본체(바닥 중심 base, 반지름 rx, 높이 h). 아래가 조금 땅에 묻힌다.
static func make_egg(base: Vector3, rx: float, h: float) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 1.0
	s.height = 2.0
	s.radial_segments = 28
	s.rings = 16
	var mi := _mi(s, egg_material(), "FrostEgg")
	mi.position = base + Vector3.UP * h * 0.44
	mi.scale = Vector3(rx, h * 0.5, rx)
	return mi


## 예전 꼭짓점 거미줄 호출 호환: 꼭짓점들의 중심에 바닥 막을 깐다(공격 '거미줄 투척' 자국 등).
static func make(anchors: Array[Vector3]) -> MeshInstance3D:
	var c := Vector3.ZERO
	var r := 0.0
	for p in anchors:
		c += p
	c /= anchors.size()
	for p in anchors:
		r = maxf(r, Vector2(p.x - c.x, p.z - c.z).length())
	return make_splat(Vector3(c.x, 0.0, c.z), r, 8, 0.15)


# ───────────────────────── 충격파 ─────────────────────────

## 충격파를 알린다: pos 에서 퍼져 나가며 strength(약 0.3~1.5) 만큼 막·알을 흔든다.
static func shock(pos: Vector3, strength := 1.0) -> void:
	_shocks.push_front([pos, 0.0, strength])
	if _shocks.size() > SLOTS.size():
		_shocks.resize(SLOTS.size())
	shocks_sent += 1
	_push()


## 매 프레임(보스룸이 부른다): 충격파 나이를 먹이고 셰이더에 넘긴다.
static func tick(delta: float) -> void:
	if _shocks.is_empty():
		return
	for s in _shocks:
		s[1] += delta
	while not _shocks.is_empty() and _shocks[-1][1] > SHOCK_LIFE:
		_shocks.pop_back()
	_push()


static func _push() -> void:
	var amp := Vector4.ZERO
	var slots: Array[Vector4] = []
	for i in SLOTS.size():
		if i < _shocks.size():
			var p: Vector3 = _shocks[i][0]
			slots.append(Vector4(p.x, p.y, p.z, _shocks[i][1]))
			amp[i] = _shocks[i][2]
		else:
			slots.append(Vector4(0, -100, 0, 99.0))
	for m in [material(), egg_material()]:
		for i in SLOTS.size():
			m.set_shader_parameter(SLOTS[i], slots[i])
		m.set_shader_parameter("shock_amp", amp)


## 검증용: 지금 막을 흔들고 있는 충격파 세기 합.
static func active_shock() -> float:
	var t := 0.0
	for s in _shocks:
		t += float(s[2]) * exp(-float(s[1]) * 2.0)
	return t
