extends RefCounted
## 월드·액터가 모델을 받는 창구. 실제 모델은 칠한 GLB(painted_models)·자연 키트(nature_models)·Tripo 캐릭터에서 온다.
## 모델을 바꿀 때는 이 함수들의 반환 노드만 바꾸면 된다(게임 로직은 래퍼에 있음). 예전 기본 도형 블록아웃은 2026-10-21 정리했다.

const B := preload("res://scripts/visual/build.gd")
const Cfg := preload("res://scripts/config.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Painted := preload("res://scripts/visual/painted_models.gd")
const Nature := preload("res://scripts/visual/nature_models.gd")

# 팔레트 — 퍼플 설경, 짙은 초록 나무, 앰버 빛
const C_SNOW := Color("e0dcff")
const C_STONE := Color("8e7f72")
const C_HAT := Color("5b3aa8")
const C_GOLD := Color("e2b24e")


static func snow_mat() -> ShaderMaterial:
	return Mats.solid(C_SNOW, {"noise_amount": 0.04, "rim_strength": 0.3})


# ───────────────────────── 환경 프랍 ─────────────────────────

static func make_pine(h: float, rng: RandomNumberGenerator) -> Node3D:
	return Nature.pine(h, rng)


static func make_rock(size: float, rng: RandomNumberGenerator) -> Node3D:
	return Nature.rock(size, rng)


static func make_shrub(rng: RandomNumberGenerator) -> Node3D:
	return Nature.asset("berry_shrub")


static func make_log() -> Node3D:
	return Nature.asset("fallen_log")


static func make_barrel() -> Node3D:
	return Painted.asset("barrel")


static func make_firewood() -> Node3D:
	return Painted.asset("firewood")


static func make_hay() -> Node3D:
	return Painted.asset("hay_bale")


static func make_stepping_stone(rng: RandomNumberGenerator) -> Node3D:
	var v := Painted.asset("step_stone")
	v.rotation_degrees.y=rng.randf_range(-12,12)
	return v


## 울타리 한 줄. 기둥 사이 1.3m 이하로 나눈다.
static func build_fence(parent: Node3D, a: Vector3, b: Vector3, skip_first_post := false) -> void:
	Painted.fence(parent,a,b,skip_first_post)


# ───────────────────────── 산장 ─────────────────────────

## 본채. 반환: 앵커·발광 노드.
static func build_lodge(root: Node3D) -> Dictionary:
	return Painted.lodge(root)


## 객실 증축 모듈(목장 반대쪽 -X). 본채는 유지한 채 덧붙인다.
static func build_extension(root: Node3D) -> Node3D:
	return Painted.extension(root)

# ───────────────────────── 캐릭터 ─────────────────────────

## SD 마녀(모자 포함 약 1.3m). 정면 +Z.
## 플레이어 마녀. Tripo 파츠 캐릭터(북쪽의 마녀, docs/character-3d-pipeline.md)가 있으면 그것, 없으면 기존 칠한 모델.
static func make_witch() -> Dictionary:
	var rigged: Dictionary = load("res://scripts/visual/character_models.gd").make_player_witch()
	return rigged if not rigged.is_empty() else Painted.witch()


## 사용자 제공 양 GLB + 부품 피벗·자동 스키닝 모션(visual/sheep_visual.gd). 이전 채색 양은 Painted.sheep().
static func make_sheep() -> Node3D:
	return preload("res://scripts/visual/sheep_visual.gd").new()


## 숲에서 오는 그림자 괴물(기능 검증용 1종).
static func make_monster() -> Node3D:
	return Painted.monster()

## 큰 숲의 괴물: 카드로 변환되는 개체. 기본 괴물보다 덩치가 크고 등에서 이끼 낀 가지가 튀어나와 있다.
## 뒤쪽은 -Z(괴물은 +Z를 바라본다). 가지는 Body 아래에 붙어 걸음 흔들림을 함께 탄다.
static func make_big_monster() -> Node3D:
	var root := Painted.monster()
	var body: Node3D = root.get_node("Body")
	var bark := Mats.solid(Color("4a3226"), {"noise_amount": 0.08, "rim_strength": 0.3, "rim_color": Color(0.6, 0.5, 1.0)})
	var bark_light := Mats.solid(Color("6b4a33"), {"noise_amount": 0.06, "rim_strength": 0.2})
	var moss := Mats.solid(Color("3f6a3a"), {"noise_amount": 0.1, "rim_strength": 0.3})
	var leaf := Mats.solid(Color("5f8f3e"), {"noise_amount": 0.08, "rim_strength": 0.35})
	var leaf_warm := Mats.solid(Color("a8822f"), {"noise_amount": 0.08})
	var back := B.node(body, Vector3(0, 0.88, -0.3), Vector3.ZERO, "BackBranches")
	# 가지 밑동을 감싼 작은 이끼 뭉치
	for m in [Vector3(-0.1, 0.0, 0.03), Vector3(0.12, -0.04, 0.02), Vector3(0.0, -0.12, 0.06)]:
		B.sphere(back, 0.09, m, moss, Vector3(1.3, 0.7, 1.0), 8, 4)
	# [밑동 위치, 회전(도), 길이, 굵기]: 등에서 위·뒤로 솟은 굵은 가지 셋 + 옆으로 삐친 짧은 가지 둘
	var limbs := [
		[Vector3(-0.12, 0.02, 0.0), Vector3(-34, 0, 26), 0.62, 0.055],
		[Vector3(0.03, 0.06, -0.02), Vector3(-26, 0, -6), 0.78, 0.065],
		[Vector3(0.15, 0.0, 0.0), Vector3(-40, 0, -30), 0.55, 0.05],
		[Vector3(-0.2, -0.1, 0.04), Vector3(-72, 0, 55), 0.32, 0.035],
		[Vector3(0.22, -0.12, 0.04), Vector3(-75, 0, -52), 0.3, 0.032],
	]
	for i in limbs.size():
		var l: Array = limbs[i]
		var limb := B.node(back, l[0], l[1], "Limb%d" % i)
		var length: float = l[2]
		var thick: float = l[3]
		var mat := bark if i % 2 == 0 else bark_light
		# 중간에서 꺾이는 두 마디 가지
		var half := length * 0.55
		B.cyl(limb, thick * 0.7, thick, half, Vector3(0, half * 0.5, 0), mat, 6)
		var upper := B.node(limb, Vector3(0, half, 0), Vector3(-14, 0, (12.0 if i % 2 == 0 else -12.0)), "Upper")
		B.cyl(upper, thick * 0.3, thick * 0.7, length - half, Vector3(0, (length - half) * 0.5, 0), mat, 6)
		if i < 3:
			# 갈래 잔가지와 끝의 작은 잎
			var twig := B.node(limb, Vector3(0, half * 0.8, 0), Vector3(-10, 0, (-50.0 if i % 2 == 0 else 50.0)), "Twig")
			B.cyl(twig, thick * 0.18, thick * 0.4, length * 0.32, Vector3(0, length * 0.16, 0), bark_light, 5)
			B.sphere(twig, 0.05, Vector3(0, length * 0.33, 0), leaf_warm if i == 1 else leaf, Vector3(1.3, 0.6, 0.9), 6, 3)
			B.sphere(upper, 0.06, Vector3(0, length - half, 0), leaf, Vector3(1.4, 0.65, 1.0), 6, 3)
			B.sphere(upper, 0.045, Vector3(0.04, (length - half) * 0.6, 0.02), leaf_warm if i == 0 else leaf, Vector3(1.3, 0.6, 0.9), 6, 3)
	root.scale = Vector3.ONE * Cfg.BIG_MONSTER_SCALE
	root.set_meta("big", true)
	return root


static func make_traveler(rng: RandomNumberGenerator) -> Node3D:
	return Painted.traveler()

## 거대한 용. 원점 = 지붕 용마루 위 발 접점. 정면 +Z.
static func make_dragon() -> Dictionary:
	return Painted.dragon()
