extends Node3D
## 마녀의 단발 마법 투사체. 대상이 이미 죽었으면 피해 없이 사라진다(중복 피해 방지).
## 연출: 흰 심지의 보랏빛 혜성 머리 + 리본 꼬리 + 흩날리는 반짝이(표시 전용).

const Cfg := preload("res://scripts/config.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const Ribbon := preload("res://scripts/visual/vfx/ribbon_trail.gd")

var target = null
var caster = null          # 붉은 만찬 축복: 맞히면 피해의 일부만큼 시전자를 회복
var lifesteal := 0.0
var damage := Cfg.BOLT_DAMAGE
var speed := Cfg.BOLT_SPEED
var _vel := Vector3.ZERO


func _ready() -> void:
	var core := B.sphere(self, 0.1, Vector3.ZERO, Mats.glow(Color(0.95, 0.8, 1.0), 7.0), Vector3.ONE, 8, 4)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.omni(self, Vector3.ZERO, Color(0.8, 0.55, 1.0), 1.4, 2.8, false, 1.2)
	Ribbon.follow(get_parent(), self, Color(0.62, 0.3, 1.0), Color(1.0, 0.9, 1.0), 0.3, 0.3, 1.7)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		Fx.poof(global_position, Color(0.75, 0.55, 1.0), 0.35)
		Sfx.play(self, "bolt_fizzle")
		queue_free()
		return
	var aim_height: float = target.get("aim_height") if target.get("aim_height") != null else .65
	var aim: Vector3 = target.global_position + Vector3(0, aim_height, 0)
	var to := aim - global_position
	var step := speed * delta
	if to.length() <= step + 0.15:
		target.take_damage(damage)
		if lifesteal > 0.0 and caster != null and is_instance_valid(caster) and not caster.dead:
			caster.heal(damage * lifesteal)
		Fx.hit(aim, Fx.C_MAGIC)
		Sfx.play(self, "bolt_hit")
		queue_free()
		return
	_vel = to.normalized() * speed
	global_position += _vel * delta
	Fx.comet_head(global_position, _vel, Fx.C_MAGIC, 1.5)
