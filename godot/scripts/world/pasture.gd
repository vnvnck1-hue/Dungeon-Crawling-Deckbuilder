extends Node3D
## 목장: 울타리(이동 차단), 열린 문, 단계별 크기와 최대 양 수(Cfg.PASTURE_LEVELS).
## 양은 빈자리가 있는 한 계속 들일 수 있고, 최대 수를 늘리려면 목장을 증축한다(울타리를 다시 세우고 경로를 다시 굽는다).

const Cfg := preload("res://scripts/config.gd")
const Models := preload("res://scripts/visual/models.gd")
const Painted := preload("res://scripts/visual/painted_models.gd")
const B := preload("res://scripts/visual/build.gd")
const SheepScript := preload("res://scripts/actors/sheep.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

const GATE_WIDTH := 1.8

var game
var level := 0
var slots: Array = []        # 살아 있는 양(죽으면 목록에서 빠진다)
var rect: Rect2 = Cfg.PASTURE_LEVELS[0]["rect"]
var _fence_visual: Node3D
var _fence_body: StaticBody3D
var _hay: Node3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "Pasture"
	_rng.randomize()
	_build_fences()
	for i in Cfg.SHEEP_START:
		spawn_sheep()


func capacity() -> int:
	return int(Cfg.PASTURE_LEVELS[level]["cap"])


## 문 가운데(울타리 바로 바깥 +X 쪽).
func gate_center() -> Vector3:
	var g := _gate_z()
	return Vector3(rect.end.x, 0, (g.x + g.y) * 0.5)


func _gate_z() -> Vector2:
	var c := rect.get_center().y + 0.35
	return Vector2(c - GATE_WIDTH * 0.5, c + GATE_WIDTH * 0.5)


func _build_fences() -> void:
	var x0 := rect.position.x
	var x1 := rect.end.x
	var z0 := rect.position.y
	var z1 := rect.end.y
	var g := _gate_z()
	_fence_visual = B.node(self, Vector3.ZERO, Vector3.ZERO, "FenceVisual")
	var lines := [
		[Vector3(x0 + 0.05, 0, z0), Vector3(x1, 0, z0)],
		[Vector3(x1, 0, z0), Vector3(x1, 0, g.x)],
		[Vector3(x1, 0, g.y), Vector3(x1, 0, z1)],
		[Vector3(x1, 0, z1), Vector3(x0 + 0.05, 0, z1)],
	]
	_fence_body = StaticBody3D.new()
	_fence_body.name = "FenceBody"
	_fence_body.collision_layer = Cfg.L_BOUNDARY
	_fence_body.collision_mask = 0
	add_child(_fence_body)
	for i in lines.size():
		var a: Vector3 = lines[i][0]
		var b: Vector3 = lines[i][1]
		Models.build_fence(_fence_visual, a, b, i == 1 or i == 3)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.3, Cfg.OBSTACLE_MIN_HEIGHT, a.distance_to(b) + 0.3)
		cs.shape = bs
		cs.position = (a + b) * 0.5 + Vector3(0, 0.5, 0)
		cs.rotation.y = atan2((b - a).x, (b - a).z)
		_fence_body.add_child(cs)
	# 항상 열린 목장 문(바깥 +X 쪽으로 열림)
	Painted.gate(_fence_visual, Vector3(x1, 0, g.x), Vector3(x1, 0, g.y))
	if _hay == null:
		_hay = Models.make_hay()
		_hay.rotation_degrees.y = 90
		add_child(_hay)
	_hay.position = Vector3(x0 + 0.55, 0, z0 + 0.5)


## 목장 증축: 다음 단계 크기로 울타리를 다시 세우고 경로를 다시 굽는다.
func upgrade() -> void:
	if level >= Cfg.PASTURE_LEVELS.size() - 1:
		return
	level += 1
	rect = Cfg.PASTURE_LEVELS[level]["rect"]
	_fence_visual.queue_free()
	_fence_body.free()
	_build_fences()
	game.world.bake_nav()
	_fence_visual.scale = Vector3(1, 0.05, 1)
	var tw := _fence_visual.create_tween()
	tw.tween_property(_fence_visual, "scale", Vector3.ONE, 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Fx.celebrate(Vector3(rect.get_center().x, 1.0, rect.get_center().y), Fx.C_GOLD, 1.3)
	Sfx.play(self, "pasture_up")


func spawn_sheep(day := 1, lamb := false, black := false) -> void:
	var s := SheepScript.new()
	s.pasture = self
	s.born_day = day
	s.is_lamb = lamb
	s.is_black = black
	s.grow_day = day + Cfg.LAMB_GROW_DAYS if lamb else 0
	var r := wander_rect()
	s.position = Vector3(_rng.randf_range(r.position.x + 0.6, r.end.x), 0, _rng.randf_range(r.position.y + 0.3, r.end.y))
	add_child(s)
	slots.append(s)


func alive_count() -> int:
	return slots.filter(func(s): return is_instance_valid(s) and not s.dead).size()


func has_empty_slot() -> bool:
	return alive_count() < capacity()


func add_sheep() -> bool:
	if not has_empty_slot():
		return false
	# 오늘 들인 양은 다음 낮부터 털을 생산한다
	spawn_sheep(game.session.wave_index + 1)
	Fx.poof(slots[-1].global_position + Vector3(0, 0.3, 0), Color(1.0, 0.98, 0.92), 0.7)
	Sfx.play(self, "sheep_add")
	return true


## 새끼양 입식(카드 lamb). 들인 날로부터 Cfg.LAMB_GROW_DAYS일 뒤 낮에 어른 양이 된다.
func add_lamb() -> bool:
	if not has_empty_slot():
		return false
	spawn_sheep(game.session.day(), true)
	Fx.poof(slots[-1].global_position + Vector3(0, 0.25, 0), Color(1.0, 0.98, 0.92), 0.5)
	Sfx.play(self, "sheep_add")
	return true


## Adult black sheep uses a normal pasture slot and first produces on the next morning.
func add_black_sheep() -> bool:
	if not has_empty_slot():
		return false
	spawn_sheep(game.session.day(), false, true)
	Fx.poof(slots[-1].global_position + Vector3(0, 0.3, 0), Color(0.65, 0.45, 0.9), 0.7)
	Sfx.play(self, "sheep_add")
	return true


## 낮 시작: 자랄 날이 된 새끼양을 어른 양으로 바꾼다. produce_wool()보다 먼저 부른다.
func grow_lambs(day: int) -> int:
	var n := 0
	for s in slots:
		if not is_instance_valid(s) or s.dead or not s.is_lamb:
			continue
		if day >= s.grow_day:
			s.grow_up()
			n += 1
	return n


func lamb_count() -> int:
	var n := 0
	for s in slots:
		if is_instance_valid(s) and not s.dead and s.is_lamb:
			n += 1
	return n


## 낮 시작: 2일차부터 생존 양마다 수확 가능 상태(미수확분은 1회분까지만).
func produce_wool(day: int) -> int:
	var n := 0
	for s in slots:
		if is_instance_valid(s) and not s.dead and not s.is_lamb and s.born_day < day and not s.wool_ready:
			s.wool_ready = true
			n += 1
	if n > 0:
		Sfx.play(self, "wool_ready")
	return n


func ready_count() -> int:
	var n := 0
	for s in slots:
		if is_instance_valid(s) and not s.dead and s.wool_ready:
			n += 1
	return n


func nearest_alive_sheep(pos: Vector3):
	var best = null
	var best_d := 1e9
	for s in slots:
		if not is_instance_valid(s) or s.dead:
			continue
		var d := pos.distance_to(s.global_position)
		if d < best_d:
			best_d = d
			best = s
	return best


func inside(pos: Vector3, margin := 0.0) -> bool:
	return rect.grow(margin).has_point(Vector2(pos.x, pos.z))


func wander_rect() -> Rect2:
	return Rect2(rect.position.x + 0.5, rect.position.y + 0.45, rect.size.x - 0.95, rect.size.y - 0.9)


## 제단 공물(붉은 만찬): 어른 양 한 마리를 목장에서 데려간다. 죽음이 아니므로 잃은 양으로 세지 않는다.
func adult_count() -> int:
	return slots.filter(func(s): return is_instance_valid(s) and not s.dead and not s.is_lamb).size()


func sacrifice_sheep() -> bool:
	for s in slots:
		if not is_instance_valid(s) or s.dead or s.is_lamb:
			continue
		slots.erase(s)
		if s.card_uid >= 0 and game.cards != null:
			game.cards.retire(s.card_uid)
			s.card_uid = -1
		s.dead = true
		Fx.poof(s.global_position + Vector3(0, 0.3, 0), Color(0.85, 0.2, 0.3), 0.8)
		s.queue_free()
		return true
	return false


## 목장의 어른 검은 양 수(늑대의 피 이벤트 조건).
func black_sheep_count() -> int:
	return slots.filter(func(s): return is_instance_valid(s) and not s.dead and s.is_black and not s.is_lamb).size()


## 늑대의 피(docs/wolf-blood-event-design.md §2): 파르그에게 어른 검은 양 한 마리를 내준다. 털이 안 자란 양을 먼저 고른다.
func take_black_sheep() -> bool:
	var pick = null
	for s in slots:
		if not is_instance_valid(s) or s.dead or not s.is_black or s.is_lamb:
			continue
		if pick == null or (pick.wool_ready and not s.wool_ready):
			pick = s
	if pick == null:
		return false
	slots.erase(pick)
	if pick.card_uid >= 0 and game.cards != null:
		game.cards.retire(pick.card_uid)
		pick.card_uid = -1
	pick.dead = true
	pick.remove_from_group("sheep")
	pick.remove_from_group("show_hp")
	Fx.poof(pick.global_position + Vector3(0, 0.3, 0), Color(0.55, 0.35, 0.8), 0.9)
	Sfx.play(self, "sheep_flee")
	pick.queue_free()
	return true


func on_sheep_died(s) -> void:
	slots.erase(s)
	if s.card_uid >= 0 and game.cards != null:
		game.cards.retire(s.card_uid)
		s.card_uid = -1
	game.on_sheep_died()
