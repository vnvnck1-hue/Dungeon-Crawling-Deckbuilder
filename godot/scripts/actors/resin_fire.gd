extends Node3D
## 송진 횃불(카드 resin_torch): 놓은 자리에 송진 불길이 RESIN_TIME초 동안 타오르며 반경 안의 적에게 초당 피해를 준다.
## 판정은 1초 간격. 불길 모양은 표시 전용.

const Cfg := preload("res://scripts/config.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

const C_FIRE := Color(1.0, 0.55, 0.2)

var game
var time_left := Cfg.RESIN_TIME
var hits := 0
var _tick := 0.0
var _light: OmniLight3D


func _ready() -> void:
	add_to_group("resin_fires")
	B.torus(self, Cfg.RESIN_RADIUS - 0.1, Cfg.RESIN_RADIUS, Vector3(0, 0.04, 0), Mats.unshaded(Color(C_FIRE, 0.55), true, true))
	for i in 6:
		var a := TAU * i / 6.0
		B.sphere(self, 0.16, Vector3(cos(a), 0.2, sin(a)) * Cfg.RESIN_RADIUS * 0.5, Mats.glow(C_FIRE, 5.0), Vector3(1, 1.6, 1), 6, 3)
	_light = B.omni(self, Vector3(0, 0.8, 0), C_FIRE, 2.4, Cfg.RESIN_RADIUS + 1.5)
	Fx.burst(get_parent(), global_position + Vector3(0, 0.3, 0), C_FIRE, 20, 3.5, 0.2, 0.6)
	Sfx.play(self, "dragon_fire")


func _process(delta: float) -> void:
	time_left -= delta
	_tick -= delta
	if _tick <= 0.0 and time_left > 0.0:
		_tick = 1.0
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.dead:
				continue
			if Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length() <= Cfg.RESIN_RADIUS:
				e.take_damage(Cfg.RESIN_DPS)
				hits += 1
	if _light != null:
		_light.light_energy = 2.4 * (0.85 + randf() * 0.3)
	if time_left <= 0.0:
		queue_free()
