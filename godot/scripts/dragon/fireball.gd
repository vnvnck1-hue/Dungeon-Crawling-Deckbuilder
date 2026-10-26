extends Node3D
## 용의 독립 불덩이. 발사 시 정한 지점으로 날아가 폭발한다(타깃이 죽어도 그 지점에서 폭발).
## 폭발 피해는 "enemies" 그룹에만 적용 → 산장·플레이어·양은 피해 없음.

const Cfg := preload("res://scripts/config.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const Ribbon := preload("res://scripts/visual/vfx/ribbon_trail.gd")

var game
var target_point := Vector3.ZERO
var _trail: GPUParticles3D
var _core: Node3D


func _ready() -> void:
	_core = B.node(self)
	var c := B.sphere(_core, 0.45, Vector3.ZERO, Mats.glow(Color(1.0, 0.55, 0.15), 7.0), Vector3.ONE, 12, 6)
	c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var halo := B.sphere(_core, 0.8, Vector3.ZERO, Mats.unshaded(Color(1.0, 0.5, 0.15, 0.35), true, true), Vector3.ONE, 12, 6)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	B.omni(self, Vector3.ZERO, Color(1.0, 0.45, 0.12), 3.0, 8.0, false, 1.0)
	_trail = GPUParticles3D.new()
	_trail.amount = 60
	_trail.lifetime = 0.6
	_trail.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.2
	pm.initial_velocity_max = 0.8
	pm.gravity = Vector3(0, 0.6, 0)
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.8, 0.4, 1.0))
	grad.set_color(1, Color(0.6, 0.3, 0.5, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	_trail.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.7, 0.7)
	q.material = Mats.particle(Color(1, 1, 1, 1), true)
	_trail.draw_pass_1 = q
	add_child(_trail)
	Ribbon.follow(get_parent(), self, Color(1.0, 0.42, 0.08), Color(1.0, 0.92, 0.55), 0.55, 0.32, 1.4)


func _process(delta: float) -> void:
	var to := target_point - global_position
	var step := Cfg.FIREBALL_SPEED * delta
	_core.rotation.y += delta * 8.0
	if to.length() <= step:
		global_position = target_point
		_explode()
		return
	global_position += to.normalized() * step
	Fx.comet_head(global_position, to.normalized() * Cfg.FIREBALL_SPEED, Fx.C_FIRE, 2.2)


func _explode() -> void:
	Sfx.play(self, "fireball_boom")
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d := Vector2(e.global_position.x - target_point.x, e.global_position.z - target_point.z).length()
		if d <= Cfg.FIREBALL_RADIUS:
			e.take_damage(Cfg.FIREBALL_DAMAGE)
	Fx.explosion(get_parent(), target_point, Cfg.FIREBALL_RADIUS)
	game.world.shake(0.28, 0.35)
	# 꼬리 입자는 남겨서 자연스럽게 사라지게 한다
	var trail := _trail
	var keep := trail.global_transform
	remove_child(trail)
	get_parent().add_child(trail)
	trail.global_transform = keep
	trail.emitting = false
	trail.get_tree().create_timer(1.0, false).timeout.connect(trail.queue_free)
	queue_free()
