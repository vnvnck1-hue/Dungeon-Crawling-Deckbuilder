extends Node3D
## 양: 목장 안에서 짧게 배회. 근처에 적이 오면 반대쪽으로 도망친다.
## 하루 한 번 털을 생산한다(v0.3 §7). 미수확분은 한 번분만 유지하며, 마녀가 다가가 수확해야 양털 카드가 된다.
## 새끼양(카드 lamb)은 작고 약하며 털을 생산하지 않는다. grow_day 낮이 되면 목장이 grow_up()을 불러 어른 양이 된다.
## 남은 일수는 마녀가 가까이 갔을 때만 말풍선(ui/lamb_bubble.gd)으로 알려 준다.

const Cfg := preload("res://scripts/config.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const SoftSep := preload("res://scripts/actors/soft_separation.gd")
const Models := preload("res://scripts/visual/models.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
var _fleeing := false
## 울음 간격(ms): 맞을 때마다·위협이 범위를 들락날락할 때마다 울면 계속 반복되므로 양마다, 무리 전체로 간격을 둔다.
const HURT_CRY_GAP := 1500
const FLEE_CRY_GAP := 4000
const HERD_CRY_GAP := 500
const BLEAT_CRY_GAP := 6000
static var _herd_cry_ms := -100000
var _hurt_cry_ms := -100000
var _flee_cry_ms := -100000
var _bleat_cry_ms := -100000

var pasture
var hp := Cfg.SHEEP_HP
var max_hp := Cfg.SHEEP_HP
var dead := false
var hp_offset := 1.05
var born_day := 1
var is_lamb := false
var is_black := false
var card_uid := -1   # 입식 카드(죽으면 버림패로)
var grow_day := 0          # 새끼양이 어른 양이 되는 날(낮 시작 기준)
var wool_ready := false
var held := false          # 마녀가 털을 깎으러 오는 동안·깎는 동안 제자리에 멈춘다
var shearing := false      # 털 깎는 중(몸을 살짝 떠는 모션)
var shear_progress := 0.0  # 깎다 만 진행(초). 연속 수확 중 다른 양을 먼저 깎으러 가도 돌아오면 이어서 깎는다
var visual: SheepVisual    # 모션은 visual 이 맡는다: 여기선 speed·grazing·alarmed·held·shearing 만 넣는다
var body: Node3D
var _target := Vector3.ZERO
var _wait := 0.0
var _rng := RandomNumberGenerator.new()
const SheepVisual := preload("res://scripts/visual/sheep_visual.gd")


func _ready() -> void:
	_rng.randomize()
	visual = Models.make_sheep()
	body = visual.get_node("Body")
	add_child(visual)
	if is_black:
		visual.set_black()
		var head := visual.get_node("Body/Head")
		var b := preload("res://scripts/visual/build.gd")
		var mats := preload("res://scripts/visual/mats.gd")
		for side: float in [-1.0, 1.0]:
			b.sphere(head, 0.03, visual.eye_local(side), mats.glow(Color(1.0, 0.78, 0.3), 2.5), Vector3.ONE, 8, 4)
	if is_lamb:
		hp = Cfg.LAMB_HP
		max_hp = Cfg.LAMB_HP
		hp_offset = 1.05 * Cfg.LAMB_SCALE + 0.15
		visual.scale = Vector3.ONE * Cfg.LAMB_SCALE
	visual.rotation.y = _rng.randf_range(0, TAU)
	add_to_group("sheep")
	SoftSep.register(self, 0.2 if is_lamb else 0.3, 0.7)
	add_to_group("show_hp")
	_target = position
	_wait = _rng.randf_range(0.5, 3.0)


func wool_card_id() -> String:
	return "black_wool" if is_black else "wool"


func _pick_target(away_from = null) -> void:
	var r: Rect2 = pasture.wander_rect()
	if away_from != null:
		var dir: Vector3 = global_position - away_from
		dir.y = 0
		_target = global_position + dir.normalized() * 1.5
	else:
		_target = Vector3(_rng.randf_range(r.position.x, r.end.x), 0, _rng.randf_range(r.position.y, r.end.y))
	_target.x = clampf(_target.x, r.position.x, r.end.x)
	_target.z = clampf(_target.z, r.position.y, r.end.y)
	# 울타리에 몰려 달아날 곳이 제자리면, 위협에서 가장 먼 우리 모서리로 울타리를 따라 달아난다
	if away_from != null and _flat_dist(_target, global_position) < 0.4:
		var best := _target
		var best_d := -1.0
		for c in [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]:
			var p := Vector3(c.x, 0, c.y)
			var d := _flat_dist(p, away_from)
			if d > best_d:
				best_d = d
				best = p
		_target = best
	# 건초 더미 모서리는 피한다
	if _target.x < r.position.x + 0.6 and _target.z < r.position.y + 0.7:
		_target.z = r.position.y + 0.9


func _process(delta: float) -> void:
	if dead:
		return
	_soft_nudge(delta)
	var threat = null
	var td := 2.6
	for e in get_tree().get_nodes_in_group("enemies"):
		var d: float = global_position.distance_to(e.global_position)
		if d < td:
			td = d
			threat = e
	var speed := 0.45 if not is_lamb else 0.55
	visual.held = held and threat == null
	visual.shearing = shearing and visual.held
	visual.alarmed = threat != null
	visual.grazing = false
	visual.speed = 0.0
	if held and threat == null:
		_target = global_position
		_wait = 0.5
		return
	if threat == null:
		_fleeing = false
	if threat != null:
		speed = 1.1
		if not _fleeing:
			_fleeing = true
			_cry_flee()
		if _wait > 0.0 or global_position.distance_to(_target) < 0.2:
			_pick_target(threat.global_position)
			_wait = 0.0
	if _wait > 0.0:
		_wait -= delta
		visual.grazing = true
		if _wait <= 0.0:
			_pick_target()
		return
	var to := _target - global_position
	to.y = 0
	if to.length() < 0.08:
		_wait = _rng.randf_range(1.5, 4.0)
		# 풀 뜯으며 가끔 운다: 마녀가 가까울 때만, 네 번에 한 번꼴.
		# 쫓기는 중엔 매 프레임 '도착'할 수 있어(울타리에 몰리면) 풀 뜯는 울음을 내지 않는다.
		if threat == null and _rng.randf() < 0.25 and Sfx.near_player(self, 3.0, 12.0) > 0.2 \
				and _cry_ready(_bleat_cry_ms, BLEAT_CRY_GAP):
			# 무리 간격은 지키되 갱신하지 않는다: 한가한 울음 때문에 바로 뒤 아파서 우는 소리가 막히면 안 된다
			_bleat_cry_ms = Time.get_ticks_msec()
			Sfx.play(self, "sheep_bleat")
			visual.bleat()
		return
	var step := minf(speed * delta, to.length())
	global_position += to.normalized() * step
	visual.speed = step / maxf(delta, 0.0001)
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(to.x, to.z), clampf(delta * 6.0, 0.0, 1.0))


## 다른 양·마녀·괴물과 겹쳤으면 천천히 떨어진다. 울타리 밖으로는 밀려나지 않는다.
func _soft_nudge(delta: float) -> void:
	var step := SoftSep.push(self) * delta
	if step.length_squared() < 0.000001:
		return
	var to := global_position + step
	if pasture == null or pasture.inside(to, 0.15):
		global_position = to


func _flat_dist(a: Vector3, b: Vector3) -> float:
	return ActorUtil.flat_dist(a, b)


## 이 양의 마지막 울음(last_ms)에서 gap 이 지났고, 무리의 다른 양이 방금 울지 않았으면 true.
func _cry_ready(last_ms: int, gap: int) -> bool:
	var now := Time.get_ticks_msec()
	return now - last_ms >= gap and now - _herd_cry_ms >= HERD_CRY_GAP


## 도망치기 시작할 때의 울음. 위협이 범위를 들락날락해도 FLEE_CRY_GAP 에 한 번만.
func _cry_flee() -> void:
	if _cry_ready(_flee_cry_ms, FLEE_CRY_GAP):
		_herd_cry_ms = Time.get_ticks_msec()
		_flee_cry_ms = _herd_cry_ms
		Sfx.play(self, "sheep_flee")


## 어른 양이 되기까지 남은 낮의 수(오늘 기준). 어른 양은 0.
func days_to_grow(today: int) -> int:
	return maxi(grow_day - today, 0) if is_lamb else 0


func grow_up() -> void:
	if not is_lamb or dead:
		return
	is_lamb = false
	max_hp = Cfg.SHEEP_HP
	hp = Cfg.SHEEP_HP
	hp_offset = 1.05
	var tw := visual.create_tween()
	tw.tween_property(visual, "scale", Vector3.ONE * 1.12, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(visual, "scale", Vector3.ONE, 0.2)
	Fx.celebrate(global_position + Vector3(0, 0.4, 0), Color(1.0, 0.96, 0.82), 0.7)


func take_damage(amount: float) -> void:
	if dead:
		return
	hp = maxf(hp - amount, 0.0)
	Fx.flash(visual)
	visual.flinch()
	Fx.damage_number(get_parent(), global_position + Vector3(0, 1.3, 0), amount, Color(1.0, 0.5, 0.45))
	# 쓰러지는 마지막 한 대는 항상 운다
	if hp <= 0.0 or _cry_ready(_hurt_cry_ms, HURT_CRY_GAP):
		_herd_cry_ms = Time.get_ticks_msec()
		_hurt_cry_ms = _herd_cry_ms
		Sfx.play(self, "sheep_hurt")
	if hp <= 0.0:
		dead = true
		remove_from_group("sheep")
		remove_from_group("show_hp")
		pasture.on_sheep_died(self)
		Fx.vanish(self, Color(0.95, 0.92, 0.9, 0.8))
