extends Node3D
## 반딧불이 떼(카드 firefly_swarm): 놓은 자리 주변의 안개를 넓게 걷어 낸다(FIREFLY_SIGHT). 감속은 없다.
## 그날 밤 전투가 끝나면 흩어지고 카드는 버림패로 간다(수호 등불과 같은 수명).

const Cfg := preload("res://scripts/config.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")

const C_FLY := Color(0.85, 1.0, 0.45)

var game
var card_uid := -1
var sight_radius := Cfg.FIREFLY_SIGHT
var dead := false
var _flies: Array = []
var _t := 0.0


func _ready() -> void:
	add_to_group("sight_sources")
	add_to_group("firefly_swarms")
	for i in 9:
		var f := B.sphere(self, 0.05, Vector3.ZERO, Mats.glow(C_FLY, 6.0), Vector3.ONE, 6, 3)
		f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_flies.append(f)
	B.omni(self, Vector3(0, 1.2, 0), C_FLY, 1.2, 4.0)
	game.session.state_changed.connect(_on_state)
	Fx.summon(global_position, C_FLY)


func _process(delta: float) -> void:
	_t += delta
	for i in _flies.size():
		var a := _t * (0.6 + i * 0.07) + i * 1.3
		_flies[i].position = Vector3(cos(a) * (0.6 + i * 0.12), 0.9 + sin(_t * 1.7 + i) * 0.35, sin(a * 1.1) * (0.6 + i * 0.1))


func _on_state(state: int) -> void:
	if state in [SessionScript.State.CLEARING, SessionScript.State.VICTORY, SessionScript.State.DEFEAT]:
		disperse()


func disperse() -> void:
	if dead:
		return
	dead = true
	if card_uid >= 0 and game.cards != null:
		game.cards.retire(card_uid)
		card_uid = -1
	remove_from_group("sight_sources")
	remove_from_group("firefly_swarms")
	Fx.poof(global_position + Vector3(0, 1.0, 0), C_FLY, 0.6)
	preload("res://scripts/audio/sfx.gd").play(self, "firefly_disperse")
	queue_free()
