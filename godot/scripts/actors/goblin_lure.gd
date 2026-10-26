extends Node3D
## 반짝이 미끼(고블린 카드 v1, 2판): 밤에 던지면 LURE_TIME 동안 근처 적이 산장 대신 미끼로 몰려든다.
## 시간이 끝나면 터지며 반짝이 파편이 주변 적을 LURE_BLIND 초 동안 눈부시게 한다(이동·공격 멈춤).
## 적이 노리는 "allies" 그룹에 들어 가장 가까운 표적이 되고, 반경 안 적의 공격 지점을 미끼로 돌린다. 미끼는 맞아도 부서지지 않는다.

const GoblinData := preload("res://scripts/game/goblin_data.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")

var game
var kind := "goblin_lure"
var job := "goblin_lure"
var person := ""
var dead := false
var hidden := false
var on_tower := false
var hp := 9999.0
var max_hp := 9999.0
var hp_offset := 0.6
var carry: Dictionary = {}
var gear: Dictionary = {}
var time_left := GoblinData.LURE_TIME
var blinded := 0
var _pulled: Dictionary = {}   # 적 instance_id → [적, 원래 attack_point]
var _spin: Node3D


func _ready() -> void:
	_spin = Node3D.new()
	add_child(_spin)
	var glass := Mats.glow(Color(1.0, 0.85, 0.4), 2.5)
	for i in 6:
		var a := TAU * i / 6.0
		B.sphere(_spin, 0.07, Vector3(cos(a) * 0.18, 0.12 + 0.05 * (i % 2), sin(a) * 0.18), glass)
	B.cyl(self, 0.22, 0.26, 0.08, Vector3(0, 0.04, 0), Mats.glow(Color(0.9, 0.6, 0.25), 0.6))
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.45)
	light.light_energy = 1.4
	light.omni_range = 3.5
	light.position = Vector3(0, 0.5, 0)
	add_child(light)
	add_to_group("allies")
	Fx.celebrate(global_position + Vector3(0, 0.4, 0), Color(1.0, 0.86, 0.4), 0.5)
	Sfx.play_or(self, "goblin_lure", "card_play")


func display_name() -> String:
	return "반짝이 미끼"


func short_status() -> String:
	return "%d초" % int(ceil(time_left))


func take_damage(_amount: float) -> void:
	if not dead:
		Fx.flash(_spin)


func _process(delta: float) -> void:
	if dead:
		return
	_spin.rotation.y += delta * 3.0
	time_left -= delta
	# 반경 안의 적은 산장 대신 미끼 자리를 공격 지점으로 삼는다(주변에 다른 적수가 있으면 그쪽이 먼저일 수 있다)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead or e.get("attack_point") == null:
			continue
		var key: int = e.get_instance_id()
		if ActorUtil.flat_dist(e.global_position, global_position) <= GoblinData.LURE_PULL:
			if not _pulled.has(key):
				_pulled[key] = [e, e.attack_point]
			e.attack_point = global_position
	if time_left <= 0.0:
		burst()


## 미끼가 터진다: 반경 안 적을 눈부시게 하고, 끌어들인 적의 공격 지점을 되돌린 뒤 사라진다.
func burst() -> void:
	if dead:
		return
	dead = true
	remove_from_group("allies")
	for key in _pulled:
		var pair: Array = _pulled[key]
		if is_instance_valid(pair[0]) and not pair[0].dead:
			pair[0].attack_point = pair[1]
	_pulled.clear()
	if game != null and game.get("goblin") != null:
		blinded = game.goblin.stun_area(global_position, GoblinData.LURE_BLIND_RADIUS, GoblinData.LURE_BLIND, 0.0)
	Fx.celebrate(global_position + Vector3(0, 0.5, 0), Color(1.0, 0.95, 0.6), 1.1)
	Sfx.play_or(self, "goblin_lure_pop", "card_burn")
	Fx.vanish(self, Color(1.0, 0.9, 0.5, 0.8), 0.3)


## 졸개 피해 보너스 판정용: 이 적이 미끼 반경 안인가.
func covers(pos: Vector3) -> bool:
	return not dead and ActorUtil.flat_dist(pos, global_position) <= GoblinData.LURE_BLIND_RADIUS
