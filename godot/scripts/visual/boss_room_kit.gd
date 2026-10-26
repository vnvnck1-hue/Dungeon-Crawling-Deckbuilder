extends RefCounted
## 니벨라 보스룸 블록아웃 프랍. 3면도(art/concepts/monsters/nivella-boss-room-turnarounds-v01)의 형태·색을 기본 도형으로 옮겼다.
## 정식 모델이 오면 같은 함수 자리를 GLB 로 바꾼다. 모든 함수는 바닥(y=0)에 놓이는 Node3D 를 돌려준다.
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const FLOOR := preload("res://shaders/boss_ice_floor.gdshader")
const Web := preload("res://scripts/visual/vfx/nivella_web.gd")

const STONE := Color("3a3a6c")
const STONE_DARK := Color("27264d")
const PILLAR := Color("4a3c70")
const INSET := Color("2a1f45")
const CRYSTAL := Color("8b9cff")
const CRYSTAL_PALE := Color("c6d4ff")
const TIMBER := Color("4b3a3c")


static func stone(c := STONE) -> ShaderMaterial:
	return Mats.solid(c, {"noise_amount": .16, "noise_scale": 1.4, "rim_color": Color("7f9cff"), "rim_strength": .32,
		"top_snow": .62, "snow_color": Color("dcdcff"), "sky_fill": .28})


static func crystal(pale := false) -> ShaderMaterial:
	var c := CRYSTAL_PALE if pale else CRYSTAL
	return Mats.solid(c, {"emission_color": Color("5e7dff") if not pale else Color("9fc0ff"), "emission_energy": .75 if not pale else .55,
		"rim_color": Color("eef4ff"), "rim_strength": .9, "wrap": .8, "noise_amount": .04, "sky_fill": .5})


static func web_mat() -> ShaderMaterial:
	return Web.material()


## 바닥판: 가장자리가 들쭉날쭉한 타원. UV 는 타원 정규 좌표(셰이더가 바깥 눈 덮임에 쓴다).
static func ice_floor(radii: Vector2, rng: RandomNumberGenerator) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 72
	var rim: Array[Vector2] = []
	for i in n:
		var a := TAU * i / n
		var k := 1.0 + rng.randf_range(-.035, .05)
		rim.append(Vector2(cos(a), sin(a)) * k)
	for i in n:
		var a: Vector2 = rim[i]
		var b: Vector2 = rim[(i + 1) % n]
		for q: Vector2 in [Vector2.ZERO, b, a]:
			st.set_normal(Vector3.UP)
			st.set_uv(q)
			st.add_vertex(Vector3(q.x * radii.x, 0.0, q.y * radii.y))
	var mat := ShaderMaterial.new()
	mat.shader = FLOOR
	var mi := MeshInstance3D.new()
	mi.name = "IceFloor"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.position.y = .025
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## 곡선 외곽 석재 한 덩이(눈 덮인 윗면).
static func rim_block(size: Vector3, rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "RimStone"
	B.bevel_box(root, size, Vector3(0, size.y * .5, 0), stone(STONE if rng.randf() < .6 else STONE_DARK), .09,
		Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-4, 4)))
	return root


## 육각 수정 한 자루: 기둥 + 뾰족한 끝.
static func crystal_shaft(parent: Node3D, base: Vector3, length: float, radius: float, tilt: Vector3, pale := false) -> void:
	var piv := B.node(parent, base, tilt)
	B.cyl(piv, radius * .86, radius, length * .78, Vector3(0, length * .39, 0), crystal(pale), 6)
	B.cyl(piv, 0.0, radius * .86, length * .3, Vector3(0, length * .78 + length * .15, 0), crystal(pale), 6)


## 수정 군집: 큰 수정 하나에 작은 수정이 부채꼴로 기댄다.
static func crystal_cluster(rng: RandomNumberGenerator, size := 1.0) -> Node3D:
	var root := Node3D.new()
	root.name = "CrystalCluster"
	var lean := rng.randf_range(-12, 12)
	crystal_shaft(root, Vector3.ZERO, 1.6 * size, .2 * size, Vector3(lean, 0, rng.randf_range(-10, 10)))
	for i in rng.randi_range(3, 5):
		var a := rng.randf() * TAU
		var off := Vector3(cos(a), 0, sin(a)) * .22 * size
		var ang := rng.randf_range(20, 40)
		crystal_shaft(root, off, rng.randf_range(.55, 1.05) * size, rng.randf_range(.08, .13) * size,
			Vector3(ang * sin(a), 0, -ang * cos(a)), rng.randf() < .35)
	# 밑동 바위
	B.sphere(root, .34 * size, Vector3(0, .05, 0), stone(STONE_DARK), Vector3(1.3, .55, 1.1), 7, 4)
	return root


## 수정이 박힌 절벽 모듈: 각진 바위 더미 + 사이사이 수정.
static func crystal_cliff(rng: RandomNumberGenerator, height := 3.2) -> Node3D:
	var root := Node3D.new()
	root.name = "CrystalCliff"
	for i in 5:
		var h := height * rng.randf_range(.45, 1.0)
		var at := Vector3(rng.randf_range(-1.1, 1.1), h * .42, rng.randf_range(-.5, .5))
		B.sphere(root, 1.0, at, stone(STONE if i % 2 == 0 else STONE_DARK), Vector3(rng.randf_range(.8, 1.2), h * .5, rng.randf_range(.7, 1.0)), 6, 4)
	for i in rng.randi_range(3, 5):
		var at := Vector3(rng.randf_range(-1.2, 1.2), rng.randf_range(.3, height * .7), rng.randf_range(.25, .7))
		crystal_shaft(root, at, rng.randf_range(.7, 1.5), rng.randf_range(.1, .2), Vector3(rng.randf_range(25, 55), 0, rng.randf_range(-30, 30)), rng.randf() < .3)
	return root


## 직립 기둥. broken 이면 윗부분이 비스듬히 부러졌다. 정면에 마름모 장식 홈.
static func pillar(rng: RandomNumberGenerator, height := 3.6, broken := true) -> Node3D:
	var root := Node3D.new()
	root.name = "BrokenPillar" if broken else "Pillar"
	var w := .78
	B.bevel_box(root, Vector3(w * 1.25, .35, w * 1.25), Vector3(0, .175, 0), stone(STONE_DARK), .06)
	var shaft_h := height - (.5 if broken else .3)
	B.bevel_box(root, Vector3(w, shaft_h, w), Vector3(0, .35 + shaft_h * .5, 0), stone(PILLAR), .07)
	B.box(root, Vector3(.26, .5, .05), Vector3(0, .35 + shaft_h * .62, w * .5 + .005), stone(INSET), Vector3(0, 0, 45))
	if broken:
		# 부러진 윗면: 비스듬한 쐐기
		B.prism(root, Vector3(w, .6, w), Vector3(0, .35 + shaft_h + .22, 0), stone(PILLAR), Vector3(0, rng.randf_range(0, 90), rng.randf_range(-14, 14)), rng.randf_range(.1, .9))
	else:
		B.bevel_box(root, Vector3(w * 1.2, .28, w * 1.2), Vector3(0, .35 + shaft_h + .14, 0), stone(STONE_DARK), .05)
	return root


## 쓰러진 기둥: 두 토막으로 갈라져 비스듬히 누워 있다.
static func fallen_pillar(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "FallenPillar"
	B.bevel_box(root, Vector3(.72, .7, 2.3), Vector3(0, .34, -.9), stone(PILLAR), .07, Vector3(0, rng.randf_range(-6, 6), 4))
	B.bevel_box(root, Vector3(.72, .7, 1.4), Vector3(.25, .32, 1.1), stone(PILLAR), .07, Vector3(-6, 14, -5))
	B.box(root, Vector3(.24, .05, .4), Vector3(0, .7, -.9), stone(INSET), Vector3(0, 45, 0))
	for i in 4:
		B.bevel_box(root, Vector3.ONE * rng.randf_range(.18, .32), Vector3(rng.randf_range(-.6, .8), .1, rng.randf_range(-.1, .4)), stone(STONE_DARK), .04,
			Vector3(rng.randf() * 40, rng.randf() * 90, 0))
	return root


## 무너진 석조 아치: 왼쪽 기둥은 떨어져 나가고 오른쪽 기둥 위로 반쯤 남은 아치 돌이 걸려 있다.
static func ruined_arch(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "RuinedArch"
	var right := pillar(rng, 4.4, false)
	right.position = Vector3(1.5, 0, 0)
	root.add_child(right)
	var left := pillar(rng, 1.9, true)
	left.position = Vector3(-1.5, 0, 0)
	root.add_child(left)
	# 아치 돌: 오른쪽 기둥 위에서 왼쪽으로 3/5 만 남았다
	for i in 4:
		var t := float(i) / 6.0
		var a := t * PI
		var at := Vector3(cos(a) * 1.5, 4.25 + sin(a) * .9, 0)
		B.bevel_box(root, Vector3(.82, .5, .74), at, stone(PILLAR if i % 2 == 0 else STONE), .06, Vector3(0, 0, rad_to_deg(a)))
	# 떨어진 아치 돌
	B.bevel_box(root, Vector3(.8, .48, .72), Vector3(-.7, .24, .9), stone(PILLAR), .06, Vector3(8, 30, 70))
	B.bevel_box(root, Vector3(.6, .4, .6), Vector3(-1.9, .2, 1.0), stone(STONE), .06, Vector3(0, 12, 20))
	return root


static func rubble(rng: RandomNumberGenerator, count := 6) -> Node3D:
	var root := Node3D.new()
	root.name = "Rubble"
	for i in count:
		var s := rng.randf_range(.18, .45)
		B.bevel_box(root, Vector3(s * 1.3, s * .8, s), Vector3(rng.randf_range(-.9, .9), s * .35, rng.randf_range(-.6, .6)),
			stone(STONE if i % 2 == 0 else STONE_DARK), .05, Vector3(rng.randf_range(-15, 15), rng.randf() * 180, rng.randf_range(-15, 15)))
	return root


static func timber(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	root.name = "BrokenTimber"
	var wood := Mats.solid(TIMBER, {"noise_amount": .2, "noise_scale": 3.0, "top_snow": .7})
	for i in 3:
		var l := rng.randf_range(1.2, 2.2)
		B.bevel_box(root, Vector3(.32, .12, l), Vector3(rng.randf_range(-.4, .4), .08 + i * .07, rng.randf_range(-.3, .3)), wood, .03,
			Vector3(rng.randf_range(-6, 6), rng.randf_range(-35, 35), rng.randf_range(-8, 8)))
	return root


## 서리실 거미줄: anchors 를 꼭짓점으로 하는 거미줄 한 장. 무늬·흔들림은 VisualShader(nivella_web.gd).
## rings·width 는 예전 띠 거미줄 호출과 맞추려 남긴 인자이며 쓰지 않는다(실 밀도는 크기로 정해진다).
static func frozen_web(anchors: Array[Vector3], _rings := 4, _width := .035) -> MeshInstance3D:
	return Web.make(anchors)
