extends Node3D
## 얼음창(서리 여왕의 왕관, docs/legend-cards-v01.md): 마녀의 마법탄 대신 쏜다.
## 처음 노린 적 쪽으로 곧게 날아가며 길 위의 적 pierce 마리까지 꿰뚫고(같은 적은 한 번), 맞은 적을 느리게 한다.
## 사거리 끝에 닿거나 다 꿰뚫으면 부서진다.

const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Ribbon := preload("res://scripts/visual/vfx/ribbon_trail.gd")

const C_ICE := Color(0.62, 0.88, 1.0)
const HIT_RADIUS := 0.65

var target = null
var caster = null
var lifesteal := 0.0
var damage := 10.0
var speed := 16.0
var reach := 9.0
var pierce := 3
var slow := 0.6
var slow_time := 2.0
var hit_list: Array = []
var _dir := Vector3.FORWARD
var _flown := 0.0


var _aimed := false


func _ready() -> void:
	B.omni(self, Vector3.ZERO, C_ICE, 1.3, 2.6, false, 1.2)
	Ribbon.follow(get_parent(), self, C_ICE, Color(0.95, 1.0, 1.0), 0.22, 0.25, 1.5)


## 쏘는 쪽이 add_child 뒤에 위치를 정하므로 첫 프레임에 방향을 잡는다.
func _aim() -> void:
	_aimed = true
	if target != null and is_instance_valid(target):
		var to: Vector3 = target.global_position + Vector3(0, 0.65, 0) - global_position
		if to.length() > 0.01:
			_dir = to.normalized()
	var spear := Node3D.new()
	add_child(spear)
	spear.basis = Basis.looking_at(_dir, Vector3.UP if absf(_dir.y) < 0.95 else Vector3.RIGHT)
	var m := B.prism(spear, Vector3(0.12, 0.12, 0.9), Vector3(0, 0, -0.1), Mats.glow(Color(0.8, 0.95, 1.0), 4.5))
	m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _process(delta: float) -> void:
	if not _aimed:
		_aim()
	var step := speed * delta
	global_position += _dir * step
	_flown += step
	Fx.comet_head(global_position, _dir * speed, C_ICE, 1.2)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead or e in hit_list:
			continue
		var c: Vector3 = e.global_position + Vector3(0, 0.65, 0)
		if Vector2(c.x - global_position.x, c.z - global_position.z).length() > HIT_RADIUS + 0.25:
			continue
		hit_list.append(e)
		e.take_damage(damage)
		if not e.dead:
			e.apply_slow("ice_lance", slow, slow_time)
		if lifesteal > 0.0 and caster != null and is_instance_valid(caster) and not caster.dead:
			caster.heal(damage * lifesteal)
		Fx.hit(c, C_ICE)
		Sfx.play(self, "bolt_hit")
		if hit_list.size() >= pierce:
			_shatter()
			return
	if _flown >= reach or global_position.y < -0.2:
		_shatter()


func _shatter() -> void:
	Fx.poof(global_position, C_ICE, 0.45)
	queue_free()
