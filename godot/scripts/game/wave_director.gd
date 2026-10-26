extends Node
## WaveDirector: 웨이브별 출현 예약과 두 숲길 출현 지점.
## 웨이브 종료 = 출현 예약이 모두 끝나고 살아 있는 적이 0명.
## 밤 구성은 챕터 데이터(chapter_data.gd)에서 읽는다. 그룹마다 적 종류를 지정할 수 있다(볼륨 확장 E0·E1).

const Cfg := preload("res://scripts/config.gd")
const ChapterData := preload("res://scripts/game/chapter_data.gd")
const Layout := preload("res://scripts/world/layout.gd")
const MonsterScript := preload("res://scripts/actors/monster.gd")

var game
var active := false
var time := 0.0
var groups: Array = []
var next_group := 0
var targets: Array = []
var spawn_index := 0
var total := 0
var wave_hp := 0.0
var card_index := -1
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "WaveDirector"
	_rng.randomize()


func start_wave(n: int) -> void:
	var cfg: Dictionary = ChapterData.day_cfg(n)
	groups = cfg["groups"]
	wave_hp = cfg["hp"]
	total = ChapterData.night_count(n)
	card_index = int(cfg.get("marked", -1))
	var s: int = mini(int(cfg["sheep"]), total)
	# 양 목표를 출현 순서 전체에 고르게 흩어 두 길에 나눈다
	targets.clear()
	for i in total:
		targets.append(int(floor(float(i + 1) * s / total)) > int(floor(float(i) * s / total)))
	time = 0.0
	next_group = 0
	spawn_index = 0
	active = true
	_spawn_due()


func stop() -> void:
	active = false


func _process(delta: float) -> void:
	if not active:
		return
	time += delta
	_spawn_due()


func _spawn_due() -> void:
	while next_group < groups.size() and time >= float(groups[next_group][0]):
		var c: int = groups[next_group][1]
		var kind := ChapterData.group_kind(groups[next_group])
		for k in c:
			_spawn(k, kind)
		next_group += 1


func _spawn(k: int, kind := "forest") -> void:
	var on_b := spawn_index % 2 == 1
	var base: Vector3 = Layout.SPAWN_B if on_b else Layout.SPAWN_A
	var path: Array = Layout.PATH_B if on_b else Layout.PATH_A
	var prev: Vector2 = path[path.size() - 2]
	var back := (Vector2(base.x, base.z) - prev).normalized()
	var side := Vector2(-back.y, back.x)
	var off := back * (k * 0.9) + side * _rng.randf_range(-0.9, 0.9)
	var m := MonsterScript.new()
	# 양 목표는 기본 괴물·곤충만 따른다(침식된 자·공성 괴물·보스는 산장만 노린다)
	var sheep_goal: bool = targets[spawn_index] and kind in ["spider", "forest", "insect"]
	m.setup(game, wave_hp, sheep_goal)
	if spawn_index == card_index and kind in ["spider", "forest"]:
		# 카드로 변환되는 개체는 큰 숲의 괴물(기본 적 자리에 대신 나온다)
		m.configure("forest")
		m.make_big()
		m.card_drop = "forest_monster"
	else:
		m.configure(kind)
	m.position = base + Vector3(off.x, 0, off.y)
	game.actors.add_child(m)
	spawn_index += 1


## 보스의 부름 등으로 웨이브 도중 추가 출현한 적(예약 수에는 넣지 않고 살아 있는 적으로만 센다).
func spawn_extra(pos: Vector3, kind := "spider") -> void:
	var m := MonsterScript.new()
	m.setup(game, wave_hp, false)
	m.configure(kind)
	m.position = pos
	game.actors.add_child(m)


func pending() -> int:
	return total - spawn_index if active else 0


func alive() -> int:
	return get_tree().get_node_count_in_group("wave_enemies")


func is_wave_done() -> bool:
	return active and pending() == 0 and alive() == 0
