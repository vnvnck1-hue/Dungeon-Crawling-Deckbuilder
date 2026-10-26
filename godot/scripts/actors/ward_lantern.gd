extends Node3D
## 수호 등불(카드 ward_lantern): 지면에 세우는 마녀의 등불.
## 빛 반경 안의 적을 느리게 하고(감속은 몬스터가 처리), 주변 안개를 걷어 낸다(fog_of_war가 sight_sources를 읽음).
## 밤 전투가 끝나면(정리 단계) 스스로 꺼진다. 낮에 세우면 그날 밤까지 유지된다.

const Cfg := preload("res://scripts/config.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")

const C_FLAME := Color(1.0, 0.78, 0.45)
const C_WARD := Color(0.82, 0.68, 1.0)

var game
var sight_radius := Cfg.LANTERN_SIGHT
var dead := false
var _light: OmniLight3D
var card_uid := -1   # 설치한 카드(꺼지면 버림패로)
var _flame: MeshInstance3D
var _ring: MeshInstance3D
var _t := 0.0
var _tick := 0.0
var _loop_id := ""  # 반복음 id(매 프레임 문자열을 만들지 않게 _ready 에서 한 번 만든다)


func _ready() -> void:
	_loop_id = "lantern_%d" % get_instance_id()
	add_to_group("ward_lanterns")
	add_to_group("sight_sources")
	_build()
	game.session.state_changed.connect(_on_state)
	scale = Vector3(1, 0.05, 1)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.summon(global_position, C_FLAME)
	Sfx.play(self, "lantern_place")


func _build() -> void:
	var wood := Mats.solid(Color("5a4031"), {"noise_amount": 0.08, "rim_strength": 0.25})
	var iron := Mats.solid(Color("2c2733"), {"rim_strength": 0.35, "rim_color": C_WARD})
	# 눈에 박힌 굽은 장대와 매단 팔
	B.cyl(self, 0.05, 0.07, 1.5, Vector3(0, 0.75, 0), wood, 6)
	B.box(self, Vector3(0.42, 0.06, 0.06), Vector3(0.18, 1.45, 0), wood)
	B.cyl(self, 0.015, 0.015, 0.16, Vector3(0.34, 1.36, 0), iron, 4)
	# 등불 몸체: 지붕·바닥·네 기둥 사이의 빛
	var cage := B.node(self, Vector3(0.34, 1.12, 0), Vector3.ZERO, "Cage")
	B.prism(cage, Vector3(0.26, 0.12, 0.26), Vector3(0, 0.2, 0), iron)
	B.box(cage, Vector3(0.24, 0.04, 0.24), Vector3(0, -0.13, 0), iron)
	for x: float in [-0.1, 0.1]:
		for z: float in [-0.1, 0.1]:
			B.box(cage, Vector3(0.025, 0.28, 0.025), Vector3(x, 0.0, z), iron)
	_flame = B.sphere(cage, 0.075, Vector3(0, 0.0, 0), Mats.glow(C_FLAME, 6.0), Vector3(1, 1.4, 1), 8, 4)
	B.sphere(cage, 0.13, Vector3.ZERO, Mats.unshaded(Color(C_FLAME, 0.22), true, true), Vector3.ONE, 10, 5)
	_light = B.omni(self, Vector3(0.34, 1.15, 0), C_FLAME.lerp(C_WARD, 0.3), 2.2, Cfg.LANTERN_RADIUS + 1.0)
	# 바닥의 보호 고리(감속 반경)
	_ring = B.torus(self, Cfg.LANTERN_RADIUS - 0.08, Cfg.LANTERN_RADIUS, Vector3(0, 0.04, 0), Mats.unshaded(Color(C_WARD, 0.35), true, true))


func _process(delta: float) -> void:
	if dead:
		return
	_t += delta
	var flicker := 1.0 + sin(_t * 9.0) * 0.06 + sin(_t * 23.0) * 0.04
	_light.light_energy = 2.2 * flicker
	_flame.scale = Vector3(1, 1.4, 1) * flicker
	_ring.rotation.y += delta * 0.15
	# 등불 불꽃: 마녀가 가까이 있을 때만 들린다
	Sfx.loop(self, _loop_id, "lantern_loop", Sfx.near_player(self, 2.5, 10.0))
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = 0.2
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d := Vector2(e.global_position.x - global_position.x, e.global_position.z - global_position.z).length()
		if d <= Cfg.LANTERN_RADIUS:
			e.apply_slow("lantern", Cfg.LANTERN_SLOW, 0.35)


func _on_state(state: int) -> void:
	if state in [SessionScript.State.CLEARING, SessionScript.State.VICTORY, SessionScript.State.DEFEAT]:
		extinguish()


func extinguish() -> void:
	if dead:
		return
	dead = true
	if card_uid >= 0 and game.cards != null:
		game.cards.retire(card_uid)
		card_uid = -1
	remove_from_group("ward_lanterns")
	remove_from_group("sight_sources")
	Fx.poof(global_position + Vector3(0.34, 1.1, 0), Color(0.85, 0.8, 0.95), 0.6)
	Sfx.play(self, "lantern_out")
	var tw := create_tween()
	tw.tween_property(_light, "light_energy", 0.0, 0.6)
	tw.parallel().tween_property(self, "scale", Vector3(1, 0.05, 1), 0.6).set_delay(0.3)
	tw.tween_callback(queue_free)
