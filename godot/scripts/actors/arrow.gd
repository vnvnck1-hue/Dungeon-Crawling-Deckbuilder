extends Node3D
## 사냥꾼의 화살: 대상(적 또는 야생 동물)을 향해 살짝 포물선을 그리며 날아가 맞힌다. 대상이 이미 죽었으면 땅에 떨어진다.
## 동물을 맞히기 전에 last_hunter를 남겨, 쓰러진 동물의 전리품이 쏜 사냥꾼에게 간다.
## 비행(2026-10-21): 쏜 자리 → 대상의 지금 자리 사이를 정해진 시간(거리 / ARROW_FLIGHT_SPEED)에 걸쳐 보간하고
## 위로 볼록한 호(높이 = 거리 × ARROW_ARC)를 더한다 — 대상이 움직여도 끝점이 따라가 빗나가지 않는다(판정은 예전과 같음).
## 화살 끝을 따라 짧은 빛 꼬리(RibbonTrail)가 남아 쏘는 것이 잘 보인다.

const Cfg := preload("res://scripts/config.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const Ribbon := preload("res://scripts/visual/vfx/ribbon_trail.gd")

var target = null
var shooter = null
var damage := Cfg.HUNTER_DAMAGE
var flight := 0.5            # 비행 시간(초) — 첫 프레임에 거리로 정한다
var arc := 0.5               # 호 꼭대기 높이(m)
var t := 0.0
var _from := Vector3.ZERO
var _started := false
var _shaft: Node3D
var _tip: Node3D             # 꼬리 리본이 따라가는 점(깃 쪽)


func _ready() -> void:
	# 화살촉이 +Z 로 만들어져 있어 look_at(-Z 가 앞)과 반대였다 — 뒤집어 촉이 날아가는 쪽을 보게 한다
	_shaft = B.node(self, Vector3.ZERO, Vector3(0, 180, 0), "Shaft")
	B.cyl(_shaft, 0.012, 0.012, 0.55, Vector3(0, 0, 0), Mats.solid(Color("d8d2c0")), 5, Vector3(90, 0, 0))
	B.cyl(_shaft, 0.0, 0.03, 0.08, Vector3(0, 0, 0.3), Mats.solid(Color("aeb4c4")), 5, Vector3(90, 0, 0))
	B.box(_shaft, Vector3(0.06, 0.012, 0.08), Vector3(0, 0, -0.25), Mats.solid(Color("c9565a")))
	for c in _shaft.get_children():
		if c is GeometryInstance3D:
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_tip = B.node(self, Vector3(0, 0, 0.2), Vector3.ZERO, "TrailPoint")   # 깃 쪽(뒤)에서 꼬리가 나온다


func _aim() -> Vector3:
	return target.global_position + Vector3(0, float(target.get("hp_offset")) * 0.45 if target.get("hp_offset") != null else 0.6, 0)


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target) or target.dead:
		Fx.poof(global_position, Color(0.8, 0.75, 0.6), 0.25)
		queue_free()
		return
	if not _started:
		# 첫 프레임: 쏜 자리·비행 시간·호 높이를 정하고 꼬리를 단다
		_started = true
		_from = global_position
		var d := Vector2(_aim().x - _from.x, _aim().z - _from.z).length()
		flight = clampf(d / Cfg.ARROW_FLIGHT_SPEED, Cfg.ARROW_FLIGHT_MIN, Cfg.ARROW_FLIGHT_MAX)
		arc = minf(d * Cfg.ARROW_ARC + 0.2, Cfg.ARROW_ARC_MAX)
		if get_parent() != null:
			Ribbon.follow(get_parent(), _tip, Color(1.0, 0.82, 0.45), Color(1.0, 0.98, 0.9), 0.09, 0.26, 1.4)
	t += delta
	var u := clampf(t / flight, 0.0, 1.0)
	var aim := _aim()
	var prev := global_position
	global_position = _point(aim, u)
	var vel := (global_position - prev) if u > 0.02 else (_point(aim, u + 0.02) - global_position)
	if vel.length() > 0.0005:
		look_at(global_position + vel, Vector3.UP)
	if u >= 1.0:
		if target.is_in_group("animals") and shooter != null:
			target.last_hunter = shooter
		target.take_damage(damage)
		if shooter != null and is_instance_valid(shooter) and shooter.has_method("on_hit") and target.is_in_group("enemies"):
			shooter.on_hit(target)
		Fx.hit(aim, Color(1.0, 0.9, 0.7))
		Sfx.play_or(self, "arrow_hit", "bolt_hit")
		queue_free()


## 비행 진행 u(0~1)의 자리: 직선 보간 + 위로 볼록한 호(4u(1-u)).
func _point(aim: Vector3, u: float) -> Vector3:
	return _from.lerp(aim, u) + Vector3(0, arc * 4.0 * u * (1.0 - u), 0)
