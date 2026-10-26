extends Node3D
## 묘지: 산장 뒤편(-Z)의 작은 비석 무덤. 쓰러진 용병마다 이름을 새긴 비석이 하나 선다.
## 최대 무덤 수는 단계(Cfg.GRAVE_LEVELS)로 정하며 산장 관리에서 목재·골드로 확장한다.
## 이동·시야를 막지 않는 장식이다(충돌 없음).

const Cfg := preload("res://scripts/config.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

## 산장 뒷벽(z=-2.95) 뒤, 목장 쪽 모서리의 무덤 자리. 기본 카메라(+X+Z에서 내려다봄)에서 지붕에 가리지 않는다.
## 앞줄부터 채운다(단계마다 4기씩 늘어남: 8 → 12 → 16). 셋째 줄 뒤(z=-8) 왼쪽은 바위가 있어 오른쪽만 쓴다.
const PLOTS := [
	Vector3(2.4, 0, -4.4), Vector3(3.5, 0, -4.4), Vector3(4.6, 0, -4.4), Vector3(5.7, 0, -4.4),
	Vector3(2.9, 0, -5.6), Vector3(4.0, 0, -5.6), Vector3(5.1, 0, -5.6), Vector3(6.2, 0, -5.6),
	Vector3(2.4, 0, -6.8), Vector3(3.5, 0, -6.8), Vector3(4.6, 0, -6.8), Vector3(5.7, 0, -6.8),
	Vector3(6.8, 0, -6.8), Vector3(4.6, 0, -8.0), Vector3(5.7, 0, -8.0), Vector3(6.8, 0, -8.0),
]

var game
var level := 0
var graves: Array = []      # {person, day, node}
var _plot_nodes: Array = []
var _stone := Mats.solid(Color("9c9ab4"), {"noise_amount": 0.06, "rim_strength": 0.2, "top_snow": 0.8, "snow_color": Color("f2f0ff")})
var _stone_dark := Mats.solid(Color("6f6c88"), {"noise_amount": 0.05})
var _dirt := Mats.solid(Color("5a4a52"), {"noise_amount": 0.08})
var _snow := Mats.solid(Color("eceaff"), {"rim_strength": 0.15})


func _ready() -> void:
	name = "Graveyard"
	_rebuild_plots()


## A안(2026-10-17): 묘지는 후면 차단 바위 띠(layout.gd REAR_BLOCKER) 안 포켓에 있다. 포켓 앞 변 바위를 낮게 두어
## 비석이 보이고, 아무도 걸어 들어갈 수 없는 장식이다. PLOTS 원좌표에 이 오프셋을 더해 띠 안쪽으로 1.5m 물린다.
const PLOT_OFFSET := Vector3(0, 0, -1.5)


static func plot(i: int) -> Vector3:
	return PLOTS[i] + PLOT_OFFSET


static func plots() -> Array:
	var out: Array = []
	for i in PLOTS.size():
		out.append(plot(i))
	return out


func capacity() -> int:
	return Cfg.GRAVE_LEVELS[mini(level, Cfg.GRAVE_LEVELS.size() - 1)]


func count() -> int:
	return graves.size()


func upgrade() -> void:
	if level >= Cfg.GRAVE_LEVELS.size() - 1:
		return
	level += 1
	_rebuild_plots()
	Sfx.play(self, "grave_up")
	for i in range(Cfg.GRAVE_LEVELS[level - 1], capacity()):
		Fx.poof(plot(i) + Vector3(0, 0.2, 0), Color(0.9, 0.88, 1.0), 0.8)


## 용병이 쓰러짐: 다음 빈자리에 비석을 세운다. 가득 차 있으면 가장 오래된 무덤 자리를 쓴다.
func bury(person: String, day: int) -> void:
	if graves.size() >= capacity():
		var old: Dictionary = graves.pop_front()
		if is_instance_valid(old["node"]):
			old["node"].queue_free()
		for i in graves.size():
			graves[i]["node"].position = plot(i)
	var i := graves.size()
	var node := _make_grave(person, day)
	node.position = plot(i)
	add_child(node)
	graves.append({"person": person, "day": day, "node": node})
	_plot_nodes[i].visible = false
	# 비석이 땅에서 솟아오른다
	var stone: Node3D = node.get_node("Stone")
	stone.position.y = -0.7
	var tw := stone.create_tween()
	tw.tween_property(stone, "position:y", 0.0, 0.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.poof(node.global_position + Vector3(0, 0.25, 0), Color(0.75, 0.7, 0.9), 0.9)
	Fx.soul(node.global_position + Vector3(0, 0.6, 0))
	Sfx.play(self, "grave_rise")


func _rebuild_plots() -> void:
	for n in _plot_nodes:
		n.queue_free()
	_plot_nodes.clear()
	for i in capacity():
		var plot_node := B.node(self, plot(i), Vector3.ZERO, "Plot%d" % i)
		# 빈 무덤 자리: 눈 위에 놓인 낮은 돌 테두리
		for side: float in [-1.0, 1.0]:
			B.box(plot_node, Vector3(0.08, 0.06, 0.78), Vector3(side * 0.27, 0.03, 0.08), _stone_dark)
		B.box(plot_node, Vector3(0.62, 0.06, 0.08), Vector3(0, 0.03, -0.31), _stone_dark)
		plot_node.visible = i >= graves.size()
		_plot_nodes.append(plot_node)


func _make_grave(person: String, day: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Grave"
	root.rotation_degrees.y = randf_range(-6.0, 6.0)
	# 무덤 흙더미와 그 위의 눈
	B.sphere(root, 0.3, Vector3(0, 0.0, 0.12), _dirt, Vector3(1.0, 0.32, 1.45), 10, 5)
	B.sphere(root, 0.27, Vector3(0, 0.04, 0.12), _snow, Vector3(0.95, 0.24, 1.35), 10, 5)
	var stone := B.node(root, Vector3.ZERO, Vector3(randf_range(-5.0, 2.0), 0, randf_range(-5.0, 5.0)), "Stone")
	# 둥근 머리의 작은 비석
	B.box(stone, Vector3(0.42, 0.46, 0.12), Vector3(0, 0.23, -0.28), _stone)
	B.cyl(stone, 0.21, 0.21, 0.12, Vector3(0, 0.46, -0.28), _stone, 12, Vector3(90, 0, 0))
	B.box(stone, Vector3(0.5, 0.06, 0.18), Vector3(0, 0.03, -0.28), _stone_dark)
	B.box(stone, Vector3(0.05, 0.2, 0.02), Vector3(0, 0.42, -0.215), _stone_dark)
	B.box(stone, Vector3(0.14, 0.05, 0.02), Vector3(0, 0.46, -0.215), _stone_dark)
	B.sphere(stone, 0.13, Vector3(0, 0.66, -0.28), _snow, Vector3(1.4, 0.35, 0.8), 8, 4)
	var label := Label3D.new()
	label.text = "%s\n%d일차" % [person, day]
	label.font_size = 40
	label.pixel_size = 0.0045
	label.outline_size = 10
	label.modulate = Color(0.95, 0.93, 1.0)
	label.outline_modulate = Color(0.1, 0.07, 0.2, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = false
	label.position = Vector3(0, 1.05, -0.28)
	stone.add_child(label)
	return root
