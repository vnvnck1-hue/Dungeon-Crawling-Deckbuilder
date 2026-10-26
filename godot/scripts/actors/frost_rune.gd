extends Node3D
## 서리 룬(카드 frost_rune): 놓은 자리에서 즉시 터져 반경 안의 적에게 피해를 주고 느리게 한다.
## 판정은 생성 순간 한 번이다. 연출(문양·결정·서리·빛기둥)은 visual/vfx/frost_rune_vfx.gd 가 맡고,
## 연출이 끝나면 이 노드도 사라진다.

const Cfg := preload("res://scripts/config.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const FrostVfx := preload("res://scripts/visual/vfx/frost_rune_vfx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

const C_FROST := Color(0.62, 0.86, 1.0)

var game
var hits := 0


func _ready() -> void:
	var vfx := FrostVfx.new()
	vfx.radius = Cfg.FROST_RADIUS
	add_child(vfx)
	vfx.tree_exiting.connect(queue_free)
	_burst(vfx)


func _burst(vfx) -> void:
	Sfx.play(self, "frost_burst")
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
		if d > Cfg.FROST_RADIUS:
			continue
		e.take_damage(Cfg.FROST_DAMAGE)
		if not e.dead:
			e.apply_slow("frost", Cfg.FROST_SLOW, Cfg.FROST_SLOW_TIME)
		Fx.hit(e.global_position + Vector3(0, 0.7, 0), C_FROST)
		vfx.encase(e.global_position)
		hits += 1
	if game != null:
		game.world.shake(0.12, 0.25)
