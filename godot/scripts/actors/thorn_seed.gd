extends Node3D
## Persistent living barricade. Grows in daylight, fights at night, accepts black wool.

const Cfg := preload("res://scripts/config.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")

var game
var hp := Cfg.THORN_HP
var max_hp := Cfg.THORN_HP
var hp_offset := 1.25
var dead := false
var growth := 0.0
var empowered := false
var sight_radius := 3.0
var visual: Node3D
var _vines: Node3D
var _eyes: Node3D
var _label: Label3D
var _tick := 0.0
var _time := 0.0


var card_uid := -1   # 심은 카드(파괴되면 버림패로)


func _ready() -> void:
	add_to_group("thorn_plants")
	add_to_group("show_hp")
	add_to_group("sight_sources")
	_build()
	_refresh()
	Fx.summon(global_position, Color(0.5, 0.8, 0.35))
	Sfx.play(self, "thorn_plant")


func is_grown() -> bool:
	return growth >= Cfg.THORN_GROW_TIME


func _build() -> void:
	visual = B.node(self, Vector3.ZERO, Vector3.ZERO, "ThornVisual")
	var shell := Mats.solid(Color("513723"), {"rim_strength": 0.2})
	var husk := Mats.solid(Color("40563a"), {"rim_strength": 0.2})
	var thorn := Mats.solid(Color("80546f"))
	B.sphere(visual, 0.47, Vector3(0, 0.48, 0), husk, Vector3(1.1, 1, 1), 12, 8)
	B.sphere(visual, 0.35, Vector3(0, 0.5, 0.28), shell, Vector3(1, 1, 0.45), 12, 8)
	for side: float in [-1.0, 1.0]:
		B.box(visual, Vector3(0.14, 0.025, 0.025), Vector3(side * 0.13, 0.53, 0.45), Mats.solid(Color("17151c")), Vector3(0, 0, side * 12))
		B.sphere(visual, 0.15, Vector3(side * 0.12, 1.0, 0), Mats.solid(Color("76a34b")), Vector3(0.6, 1.2, 0.35), 8, 4)
	_eyes = B.node(visual, Vector3.ZERO, Vector3.ZERO, "AwakeEyes")
	for side: float in [-1.0, 1.0]:
		B.sphere(_eyes, 0.055, Vector3(side * 0.13, 0.55, 0.46), Mats.glow(Color(0.8, 1, 0.35), 2), Vector3.ONE, 8, 4)
	_vines = B.node(visual, Vector3.ZERO, Vector3.ZERO, "Vines")
	for i in 8:
		var angle := TAU * i / 8.0
		var pivot := B.node(_vines, Vector3.ZERO, Vector3(0, rad_to_deg(angle), 0))
		for j in 3:
			var z := 0.42 + j * 0.31
			B.sphere(pivot, 0.15, Vector3(sin(j * 1.1) * 0.12, 0.15 + j * 0.08, z), husk, Vector3(0.7, 0.8, 1.55), 8, 4)
			B.cyl(pivot, 0.0, 0.12, 0.4, Vector3(0, 0.36 + j * 0.08, z), thorn, 5, Vector3(25, 0, 15))
	_label = Label3D.new()
	_label.position.y = 1.65
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 28
	_label.pixel_size = 0.007
	_label.outline_size = 8
	_label.no_depth_test = true
	add_child(_label)


func _refresh() -> void:
	var ratio := clampf(growth / Cfg.THORN_GROW_TIME, 0, 1)
	visual.scale = Vector3.ONE * lerpf(0.6, 1.0, ratio)
	_vines.scale = Vector3.ONE * lerpf(0.35, 1.0, ratio)
	var awake: bool = game.session.state == SessionScript.State.COMBAT
	_eyes.visible = awake
	if awake:
		_label.text = "가시 방책" + (" · 의식 강화" if empowered else (" · 어린 가시" if not is_grown() else ""))
	else:
		_label.text = "가시 방책 · 의식 강화" if empowered else ("가시 방책 · 성장 완료" if is_grown() else "잠자는 가시 · %d초 뒤 성장" % ceili(Cfg.THORN_GROW_TIME - growth))
	_label.modulate = Color(0.85, 0.65, 1.0) if empowered else Color(0.8, 1.0, 0.6)


func _process(delta: float) -> void:
	if dead:
		return
	_time += delta
	if game.session.state == SessionScript.State.PREP:
		growth = minf(growth + delta, Cfg.THORN_GROW_TIME)
	_refresh()
	visual.position.y = sin(_time * 2.0) * 0.025
	if game.session.state != SessionScript.State.COMBAT:
		return
	_tick -= delta
	if _tick > 0:
		return
	_tick = Cfg.THORN_INTERVAL
	var damage := Cfg.THORN_RITUAL_DAMAGE if empowered else Cfg.THORN_DAMAGE
	if not is_grown():
		damage *= 0.5
	if game.get("chapter") != null and game.chapter != null:
		damage *= game.chapter.thorn_mult()  # 가시의 봉헌 축복
	var lashed := false
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy.dead or Vector2(enemy.global_position.x - global_position.x, enemy.global_position.z - global_position.z).length() > Cfg.THORN_RADIUS:
			continue
		if enemy.has_method("apply_slow"):
			enemy.apply_slow("thorns", Cfg.THORN_SLOW if is_grown() else 0.65, Cfg.THORN_INTERVAL + 0.15)
		enemy.take_damage(damage)
		lashed = true
		Fx.claw(global_position + Vector3(0, 0.45, 0), enemy.global_position - global_position)
	if lashed:
		Sfx.play(self, "thorn_lash")


func can_receive_offering() -> bool:
	return not dead and (not empowered or hp < max_hp)


func offer_black_wool() -> void:
	empowered = true
	growth = Cfg.THORN_GROW_TIME
	max_hp = Cfg.THORN_RITUAL_HP
	hp = max_hp
	_refresh()
	Fx.celebrate(global_position + Vector3(0, 0.5, 0), Color(0.75, 0.5, 1.0), 0.9)
	Sfx.play(self, "thorn_empower")


func take_damage(amount: float) -> void:
	if dead:
		return
	if game != null and game.get("race_cards") != null and game.race_cards.facility_shielded():
		return  # 돌 속의 노래(종족 카드 v1): 시설이 피해를 받지 않는다
	hp = maxf(hp - amount, 0)
	Fx.flash(visual)
	if hp > 0:
		Sfx.play(self, "thorn_hit")
	if hp <= 0:
		dead = true
		Sfx.play(self, "thorn_die")
		if card_uid >= 0 and game.cards != null:
			game.cards.retire(card_uid)
			card_uid = -1
		remove_from_group("thorn_plants")
		remove_from_group("show_hp")
		remove_from_group("sight_sources")
		Fx.vanish(self, Color(0.45, 0.6, 0.3))
