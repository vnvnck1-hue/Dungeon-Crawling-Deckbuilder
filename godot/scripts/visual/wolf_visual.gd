extends Node3D
## 보름달 늑대(마녀가 변신한 모습)의 **임시** 블록아웃 모델과 모션. 사용자가 나중에 정식 모델을 따로 준다(docs/wolf-blood-event-design.md §5).
## 원시 도형(build.gd)만으로 만든다: 회색 몸통·목·머리·주둥이·귀 2·다리 4·꼬리. 마녀 visual(scale 1.3) 아래에 붙으므로 로컬 크기는 1.3배 전 기준이다.
## 소유자(actors/player.gd)는 매 프레임 speed 만 넣고, 사건은 strike()(물기)·claw_swipe(side)(할퀴기)·set_pounce(t)(덮치기)·hurt()로 알린다.
## 노드 구조 {"Body","Head"}는 마녀와 같은 피벗 규약이다.

const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")

const C_FUR := Color("7d8190")
const C_FUR_DARK := Color("4f5262")
const C_FUR_LIGHT := Color("b9bcc8")
const C_NOSE := Color("1d1824")
const C_EYE := Color(0.85, 0.45, 1.0)
const C_HAT := Color("3a2268")   # 마녀의 흔적: 목에 걸린 보랏빛 리본

var speed := 0.0

var body: Node3D
var head: Node3D
var neck: Node3D
var tail: Node3D
var legs: Dictionary = {}      # "FL" "FR" "BL" "BR" → 다리 피벗(어깨·엉덩이)
var _t := 0.0
var _gait := 0.0
var _strike := 0.0
var _claw := 0.0
var _claw_side := 1.0
var _pounce := -1.0
var _hurt := 0.0
var _breath := 0.0


func _ready() -> void:
	name = "WolfVisual"
	var fur := Mats.solid(C_FUR, {"rim_strength": 0.35})
	var dark := Mats.solid(C_FUR_DARK, {"rim_strength": 0.3})
	var light := Mats.solid(C_FUR_LIGHT, {"rim_strength": 0.25})
	body = B.node(self, Vector3(0, 0.42, 0), Vector3.ZERO, "Body")
	# 몸통: 앞쪽(+Z)이 머리. 가슴은 조금 크고 허리는 가늘게
	B.sphere(body, 0.2, Vector3(0, 0.0, 0.08), fur, Vector3(1.0, 0.85, 2.0), 12, 8)
	B.sphere(body, 0.19, Vector3(0, -0.02, -0.2), fur, Vector3(0.92, 0.8, 1.2), 12, 8)
	B.sphere(body, 0.16, Vector3(0, -0.07, 0.05), light, Vector3(0.95, 0.6, 1.9), 10, 6)   # 밝은 배
	B.sphere(body, 0.17, Vector3(0, 0.11, -0.02), dark, Vector3(0.9, 0.55, 2.1), 10, 6)    # 등줄기 어두운 털
	# 목·머리
	neck = B.node(body, Vector3(0, 0.08, 0.42), Vector3(-20, 0, 0), "Neck")
	B.sphere(neck, 0.13, Vector3(0, 0.05, 0.05), fur, Vector3(1.0, 0.9, 1.3), 10, 6)
	B.torus(neck, 0.1, 0.145, Vector3(0, 0.02, 0.02), Mats.solid(C_HAT), Vector3(70, 0, 0))   # 마녀의 흔적(리본)
	head = B.node(neck, Vector3(0, 0.14, 0.17), Vector3(18, 0, 0), "Head")
	B.sphere(head, 0.13, Vector3.ZERO, fur, Vector3(1.0, 0.92, 1.1), 12, 8)
	B.cyl(head, 0.055, 0.085, 0.17, Vector3(0, -0.035, 0.17), fur, 8, Vector3(90, 0, 0))     # 주둥이
	B.sphere(head, 0.035, Vector3(0, -0.01, 0.26), Mats.solid(C_NOSE), Vector3.ONE, 6, 4)
	B.sphere(head, 0.05, Vector3(0, -0.085, 0.14), light, Vector3(1.0, 0.6, 1.2), 8, 4)       # 턱(밝은 털)
	for side: float in [-1.0, 1.0]:
		B.cyl(head, 0.0, 0.045, 0.13, Vector3(side * 0.075, 0.12, -0.02), fur, 6, Vector3(-18, 0, side * -14.0))   # 귀
		B.sphere(head, 0.024, Vector3(side * 0.06, 0.035, 0.1), Mats.glow(C_EYE, 2.5), Vector3.ONE, 6, 4)         # 눈
	# 꼬리
	tail = B.node(body, Vector3(0, 0.06, -0.4), Vector3(-130, 0, 0), "Tail")
	B.cyl(tail, 0.035, 0.06, 0.3, Vector3(0, 0.15, 0), fur, 8)
	B.sphere(tail, 0.06, Vector3(0, 0.3, 0), light, Vector3.ONE, 8, 4)
	# 다리 4개: 어깨·엉덩이 피벗에서 아래로. 발은 밝은 털
	var pivots := {"FL": Vector3(-0.12, -0.08, 0.26), "FR": Vector3(0.12, -0.08, 0.26), "BL": Vector3(-0.11, -0.06, -0.26), "BR": Vector3(0.11, -0.06, -0.26)}
	for key in pivots:
		var pivot := B.node(body, pivots[key], Vector3.ZERO, "Leg" + key)
		B.cyl(pivot, 0.045, 0.06, 0.3, Vector3(0, -0.15, 0), fur, 7)
		B.sphere(pivot, 0.055, Vector3(0, -0.31, 0.02), light, Vector3(1.0, 0.7, 1.2), 7, 4)
		legs[key] = pivot


func strike() -> void:
	_strike = 0.22


func claw_swipe(side: float) -> void:
	_claw = 0.16
	_claw_side = side


## 덮치기 진행 0~1(음수면 끝). 몸이 앞으로 늘어나고 포물선으로 뜬다.
func set_pounce(t: float) -> void:
	_pounce = t


func hurt() -> void:
	_hurt = 0.2


func _process(delta: float) -> void:
	_t += delta
	var running := speed > 0.2
	var stride: float = clampf(speed / 5.6, 0.0, 1.4)
	_gait += delta * (6.0 + 9.0 * stride)
	_strike = maxf(_strike - delta, 0.0)
	_claw = maxf(_claw - delta, 0.0)
	_hurt = maxf(_hurt - delta, 0.0)
	_breath = sin(_t * 2.4)
	if _pounce >= 0.0:
		# 덮치기: 몸을 앞으로 늘이고 다리를 뒤로 모은다
		var arc := sin(_pounce * PI)
		body.position.y = 0.42 + arc * 0.45
		body.rotation.x = deg_to_rad(-25.0 * arc)
		body.scale = Vector3(0.9, 0.9, 1.25)
		for key in legs:
			legs[key].rotation.x = deg_to_rad(55.0 if key.begins_with("B") else -70.0)
		neck.rotation.x = deg_to_rad(-5.0)
		tail.rotation.x = deg_to_rad(-170.0)
		return
	body.scale = Vector3.ONE
	if running:
		# 달리기: 앞 한 쌍 → 뒤 한 쌍 바운드, 몸이 위아래로 튀고 앞뒤로 흔들린다
		body.position.y = 0.42 + absf(sin(_gait)) * 0.07 * stride
		body.rotation.x = sin(_gait) * 0.14 * stride
		body.rotation.z = 0.0
		for key in legs:
			var phase: float = {"FL": 0.0, "FR": 0.35, "BL": 3.1, "BR": 3.45}[key]
			legs[key].rotation.x = sin(_gait + phase) * (0.55 + 0.3 * stride)
		tail.rotation.x = deg_to_rad(-150.0) + sin(_gait * 0.5) * 0.2
		neck.rotation.x = deg_to_rad(-26.0) + sin(_gait) * 0.08
	else:
		# 정지: 숨쉬기, 꼬리 느리게 흔들기, 귀·머리 둘러보기
		body.position.y = 0.42 + _breath * 0.008
		body.rotation.x = 0.0
		body.rotation.z = 0.0
		for key in legs:
			legs[key].rotation.x = lerp_angle(legs[key].rotation.x, 0.0, clampf(delta * 10.0, 0.0, 1.0))
		tail.rotation.x = deg_to_rad(-130.0) + sin(_t * 1.6) * 0.25
		tail.rotation.z = sin(_t * 2.3) * 0.3
		neck.rotation.x = deg_to_rad(-20.0) + _breath * 0.03
		head.rotation.y = sin(_t * 0.7) * 0.25
	if _strike > 0.0:
		# 물기: 목을 앞으로 내밀고 머리를 숙인다
		var k := sin(_strike / 0.22 * PI)
		neck.position.z = 0.42 + k * 0.16
		neck.rotation.x = deg_to_rad(-20.0 + 30.0 * k)
		head.rotation.x = deg_to_rad(18.0 + 25.0 * k)
	else:
		neck.position.z = 0.42
		head.rotation.x = deg_to_rad(18.0)
	if _claw > 0.0:
		# 할퀴기: 앞발 하나를 크게 휘두르고 몸을 그쪽으로 기울인다
		var k2 := sin(_claw / 0.16 * PI)
		var leg: Node3D = legs["FR"] if _claw_side > 0.0 else legs["FL"]
		leg.rotation.x = deg_to_rad(-110.0 * k2)
		leg.rotation.z = deg_to_rad(-35.0 * k2 * _claw_side)
		body.rotation.z = deg_to_rad(10.0 * k2 * _claw_side)
		body.position.y = 0.42 + k2 * 0.05
	if _hurt > 0.0:
		body.rotation.z += sin(_hurt * 60.0) * 0.08
