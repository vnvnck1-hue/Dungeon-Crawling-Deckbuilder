extends Node3D
## DragonDefense: 지붕 앵커에 용 소환 → 1초 등장 → 2초마다 가장 밀집한 적 무리로 불덩이 한 발.
## 웨이브 정리 시 3초 동안 퇴장. 소환은 [용비늘] 카드(card_use_resolver "dragon")가 하고 여기서는 연출·공격과 용비늘 드랍을 맡는다.
## 용비늘 드랍(2026-10-24 사용자 확정): 적 처치마다 Cfg.DRAGON_SCALE_DROP(말라의 외알 안경 배율 적용), 보스는 확정.

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const Models := preload("res://scripts/visual/models.gd")
const B := preload("res://scripts/visual/build.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const FireballScript := preload("res://scripts/dragon/fireball.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")

enum Phase { NONE, SUMMONING, ACTIVE, LEAVING }

var game
var phase := Phase.NONE
var used_this_wave := false
var scales_dropped := 0                # 이번 판 적에게서 떨어진 용비늘 수
var _t := 0.0
var _fire_cd := 0.0
var _parts: Dictionary = {}
var _model: Node3D
var _recoil := 0.0


func _ready() -> void:
	name = "DragonDefense"
	position = Layout.DRAGON_ANCHOR


func is_present() -> bool:
	return phase != Phase.NONE


func on_wave_start() -> void:
	used_this_wave = false


## 용비늘 카드를 산장에 놓을 수 없는 사유(가능하면 빈 문자열).
func block_reason() -> String:
	if game.session.state != SessionScript.State.COMBAT:
		return "용비늘은 밤 전투 중에만 쓸 수 있습니다"
	if is_present() or used_this_wave:
		return "이번 웨이브에 이미 용을 불렀습니다"
	if game.waves.alive() == 0 and game.waves.pending() == 0:
		return "남은 적이 없습니다"
	return ""


## 이 적을 쓰러뜨렸을 때 용비늘이 떨어질 확률. 보스는 확정.
func scale_drop_chance(enemy) -> float:
	if enemy != null and enemy.get("is_boss") == true:
		return 1.0
	var mult := 1.0
	if game.get("kill_gold") != null:
		mult = game.kill_gold.loot_chance_mult(enemy)
	return Cfg.DRAGON_SCALE_DROP * mult


## 적 처치 → 용비늘 드랍 판정. kill_gold.on_enemy_killed·nivella_boss.die 가 부른다. 반환: 떨어졌는가.
## roll 은 검증용(0..1 값을 넘기면 그 값으로 판정).
func on_enemy_killed(enemy, roll := -1.0) -> bool:
	if game.session != null and game.session.is_over():
		return false
	if (randf() if roll < 0.0 else roll) >= scale_drop_chance(enemy):
		return false
	scales_dropped += 1
	game.cards.add(Cfg.DRAGON_SCALE)
	game.toast("붉은 비늘이 떨어졌습니다 — 전리품 '용비늘' 카드! 산장에 놓으면 용이 내려옵니다", Color(1.0, 0.55, 0.3))
	if enemy != null and is_instance_valid(enemy) and enemy is Node3D:
		Fx.celebrate(enemy.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.45, 0.2))
	game.sounds.play_or("relic_get", "mon_drop")
	return true


func summon() -> bool:
	if phase != Phase.NONE:
		return false
	used_this_wave = true
	phase = Phase.SUMMONING
	_t = 0.0
	_parts = Models.make_dragon()
	_model = _parts["root"]
	_model.rotation_degrees.y = 28.0
	_model.scale = Vector3.ONE * 0.05
	add_child(_model)
	var tw := _model.create_tween()
	tw.tween_property(_model, "scale", Vector3.ONE, Cfg.DRAGON_SUMMON_TIME).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 소환 섬광
	var flash := B.omni(self, Vector3(0, 2.5, 1.0), Color(1.0, 0.6, 0.3), 12.0, 16.0, false, 0.9)
	var ftw := flash.create_tween()
	ftw.tween_property(flash, "light_energy", 0.0, 1.1).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	ftw.tween_callback(flash.queue_free)
	Fx.celebrate(global_position + Vector3(0, 1.5, 0), Color(1.0, 0.6, 0.25), 2.0)
	Fx.hit(global_position + Vector3(0, 2.0, 0), Fx.C_FIRE, true)
	game.world.shake(0.3, 0.5)
	game.sounds.play("dragon_arrival")
	return true


func dismiss() -> float:
	if phase == Phase.NONE or phase == Phase.LEAVING:
		return Cfg.DRAGON_LEAVE_TIME if phase == Phase.LEAVING else 0.0
	phase = Phase.LEAVING
	Sfx.play(self, "dragon_leave")
	var m := _model
	var tw := m.create_tween().set_parallel(true)
	tw.tween_property(m, "position", Vector3(0, 9.0, -6.0), Cfg.DRAGON_LEAVE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(m, "scale", Vector3.ONE * 0.05, Cfg.DRAGON_LEAVE_TIME).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(_on_left)
	return Cfg.DRAGON_LEAVE_TIME


func _on_left() -> void:
	if _model != null:
		_model.queue_free()
	_model = null
	_parts = {}
	phase = Phase.NONE


func _process(delta: float) -> void:
	if phase == Phase.NONE:
		return
	_t += delta
	_animate(delta)
	Sfx.loop(self, "dragon_wings", "dragon_wings", 0.0 if phase == Phase.LEAVING else 0.7)
	match phase:
		Phase.SUMMONING:
			if _t >= Cfg.DRAGON_SUMMON_TIME:
				phase = Phase.ACTIVE
				_fire_cd = 0.0
		Phase.ACTIVE:
			_fire_cd -= delta
			if _fire_cd <= 0.0:
				var p = _pick_target()
				if p != null:
					_fire(p)
					_fire_cd = Cfg.DRAGON_FIRE_INTERVAL
				else:
					_fire_cd = 0.2


## 가장 밀집한 적 무리의 중심(사거리 안).
func _pick_target():
	var enemies: Array = []
	var origin := Vector2(global_position.x, global_position.z)
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var p := Vector2(e.global_position.x, e.global_position.z)
		if p.distance_to(origin) <= Cfg.FIREBALL_RANGE:
			enemies.append(p)
	if enemies.is_empty():
		return null
	var best_sum := Vector2.ZERO
	var best_n := 0
	var best_center_d := 1e9
	for p: Vector2 in enemies:
		var n := 0
		var sum := Vector2.ZERO
		for q: Vector2 in enemies:
			if p.distance_to(q) <= Cfg.FIREBALL_RADIUS * 0.8:
				n += 1
				sum += q
		var cd := p.length()
		if n > best_n or (n == best_n and cd < best_center_d):
			best_n = n
			best_sum = sum
			best_center_d = cd
	var c := best_sum / best_n
	return Vector3(c.x, 0.1, c.y)


func _fire(point: Vector3) -> void:
	var fb := FireballScript.new()
	fb.game = game
	fb.target_point = point
	game.actors.add_child(fb)
	var mouth: Node3D = _parts["mouth"]
	fb.global_position = mouth.global_position
	_recoil = 0.4
	var head: Node3D = _parts["head"]
	Fx.cast(mouth.global_position, mouth.global_position, Fx.C_FIRE)
	Sfx.play(self, "dragon_fire")
	# 고개를 목표 쪽으로 살짝 돌림
	var local := _model.to_local(point)
	head.rotation.y = clampf(atan2(local.x, local.z), -0.6, 0.6)


func _animate(delta: float) -> void:
	if _parts.is_empty():
		return
	var wings: Array = _parts["wings"]
	for i in wings.size():
		var w: Node3D = wings[i]
		var s := -1.0 if i == 0 else 1.0
		w.rotation.z = s * (-0.42 + sin(_t * 3.2) * 0.16)
	var neck: Node3D = _parts["neck"]
	if _recoil > 0.0:
		_recoil -= delta
	var k := sin(clampf(_recoil / 0.4, 0.0, 1.0) * PI)
	neck.rotation.x = deg_to_rad(32.0) - k * 0.35 + sin(_t * 1.6) * 0.03
	var ember: OmniLight3D = _parts["ember"]
	ember.light_energy = 2.0 + sin(_t * 7.0) * 0.4 + k * 4.0
