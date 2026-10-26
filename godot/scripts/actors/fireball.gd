extends Node3D
## 큰 불덩이(전설 카드 v1, docs/legend-cards-v01.md): 불의 정령 화로·폭주하는 마법서가 던진다.
## start 에서 target(지면)까지 포물선으로 날아가 떨어진 자리 반경 radius 의 적에게만 피해. 산장·아군은 다치지 않는다.

const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Ribbon := preload("res://scripts/visual/vfx/ribbon_trail.gd")

var game
var start := Vector3.ZERO
var target := Vector3.ZERO
var damage := 40.0
var radius := 1.6
var size := 1.0
var flight := 0.75
var arc := 3.0
var hits := 0
var _t := 0.0


func _ready() -> void:
	global_position = start
	var core := B.sphere(self, 0.22 * size, Vector3.ZERO, Mats.glow(Color(1.0, 0.75, 0.3), 6.0), Vector3.ONE, 10, 6)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.sphere(self, 0.34 * size, Vector3.ZERO, Mats.unshaded(Color(1.0, 0.4, 0.1, 0.45), true, true), Vector3.ONE, 10, 6)
	B.omni(self, Vector3.ZERO, Color(1.0, 0.5, 0.15), 2.0, 4.0 * size, false, 1.2)
	Ribbon.follow(get_parent(), self, Fx.C_FIRE, Color(1.0, 0.95, 0.7), 0.42 * size, 0.35, 1.8)
	Sfx.play_or(self, "fireball_throw", "magic_bolt")


func _process(delta: float) -> void:
	_t += delta
	var k := clampf(_t / flight, 0.0, 1.0)
	var p := start.lerp(target, k)
	p.y = lerpf(start.y, target.y, k) + sin(k * PI) * arc
	global_position = p
	if k >= 1.0:
		_land()


func _land() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		if Vector2(e.global_position.x - target.x, e.global_position.z - target.z).length() > radius:
			continue
		e.take_damage(damage)
		Fx.hit(e.global_position + Vector3(0, 0.7, 0), Fx.C_FIRE, true)
		hits += 1
	if get_parent() != null:
		Fx.explosion(get_parent(), target, radius)
	Sfx.play_or(self, "fireball_land", "bolt_hit")
	if game != null and game.get("world") != null and game.world.has_method("shake"):
		game.world.shake(0.08, 0.2)
	queue_free()
