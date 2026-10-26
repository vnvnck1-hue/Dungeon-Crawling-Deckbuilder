extends Node3D
## 피클의 덫(고블린 카드 v1): 작은 덫. 적이 밟으면 덫이 닫히며 피해를 주고 잠깐 멈춰 세운다.
## 터진 덫은 그 자리에 닫힌 채 남고, 고블린 용병이 있으면 새벽에 다시 깐다(goblin_cards.gd on_dawn). 없으면 새벽에 치운다.

const GoblinData := preload("res://scripts/game/goblin_data.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")

var game
var armed := true
var sprung_count := 0
var _jaw_l: Node3D
var _jaw_r: Node3D


func _ready() -> void:
	add_to_group("goblin_traps")
	var iron := Mats.solid(Color(0.42, 0.38, 0.34))
	B.cyl(self, 0.24, 0.26, 0.03, Vector3(0, 0.015, 0), iron)
	_jaw_l = Node3D.new()
	_jaw_r = Node3D.new()
	_jaw_l.position = Vector3(-0.2, 0.03, 0)
	_jaw_r.position = Vector3(0.2, 0.03, 0)
	add_child(_jaw_l)
	add_child(_jaw_r)
	var teeth := Mats.solid(Color(0.62, 0.58, 0.5))
	for j in [_jaw_l, _jaw_r]:
		var s := 1.0 if j == _jaw_l else -1.0
		B.box(j, Vector3(0.04, 0.03, 0.42), Vector3(s * 0.0, 0.0, 0.0), teeth)
		for k in 4:
			B.box(j, Vector3(0.06, 0.05, 0.03), Vector3(s * 0.04, 0.03, -0.15 + k * 0.1), teeth)
	_set_open(true)


func _set_open(open: bool) -> void:
	_jaw_l.rotation.z = -1.2 if open else 0.0
	_jaw_r.rotation.z = 1.2 if open else 0.0
	_jaw_l.position.x = -0.2 if open else -0.04
	_jaw_r.position.x = 0.2 if open else 0.04


func _physics_process(_delta: float) -> void:
	if not armed:
		return
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if ActorUtil.flat_dist(e.global_position, global_position) <= GoblinData.TRAP_TRIGGER:
			spring(e)
			return


func spring(e) -> void:
	armed = false
	sprung_count += 1
	_set_open(false)
	e.take_damage(GoblinData.TRAP_DAMAGE)
	if game != null and game.get("goblin") != null and not e.dead:
		game.goblin.stun(e, GoblinData.TRAP_STUN)
	Fx.hit(global_position + Vector3(0, 0.2, 0), Color(0.9, 0.85, 0.7))
	Sfx.play_or(self, "goblin_trap_snap", "vine_bind")


func rearm() -> void:
	armed = true
	_set_open(true)
	Fx.celebrate(global_position + Vector3(0, 0.2, 0), Color(0.7, 0.95, 0.5), 0.3)
