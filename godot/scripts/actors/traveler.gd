extends Node3D
## 여행자: 숲길에서 걸어와 문 앞에서 입실(숨김), 지불 후 다시 나와 숲길로 떠난다.

const Cfg := preload("res://scripts/config.gd")
const SoftSep := preload("res://scripts/actors/soft_separation.gd")
const Models := preload("res://scripts/visual/models.gd")
const Layout := preload("res://scripts/world/layout.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const CharacterModels := preload("res://scripts/visual/character_models.gd")

signal arrived

var route: Array = []
var profile: Dictionary = {}
var leaving := false
var waiting := false
var visual: Node3D
var body: Node3D
var _anim_t := 0.0
var _delay := 0.0
var _rng := RandomNumberGenerator.new()
## 전용 파츠 캐릭터(니브 등)일 때만: 절차 애니메이션과 문 앞 인사·떠날 때 손 흔들기 시간.
var rig: Node
var _rig_style: Dictionary = {}
var _greet_left := 0.0
var _wave_left := 0.0
var _greet_yaw := 0.0


func setup(points: Array, delay: float) -> void:
	route = points.duplicate()
	_delay = delay


func _ready() -> void:
	_rng.randomize()
	# 모든 손님은 3D 파츠 모델(전용 → 종족 공용 → 인간 공용). 예전 겨울 여행자 모델은 쓰지 않는다(사용자 지시 2026-10-21).
	var custom := CharacterModels.make(CharacterModels.model_for(profile))
	visual = custom.root
	body = custom.body
	rig = custom.anim
	_rig_style = custom.style
	add_child(visual)
	add_to_group("readable_characters")   # F10 캐릭터 분리 시험(visual/character_readability.gd)
	SoftSep.register(self, 0.3, 1000.0)   # 정해진 길을 걷는 손님은 밀리지 않고, 다른 캐릭터가 비켜 간다
	visible = _delay <= 0.0


func leave(points: Array, delay: float) -> void:
	leaving = true
	waiting = false
	_greet_left = 0.0
	_wave_left = float(_rig_style.get("wave_time", 0.0))
	route = points.duplicate()
	_delay = delay
	visible = delay <= 0.0


## 정산 후 고용 기회: 문가에 나와 기다린다.
func wait_at(p: Vector3) -> void:
	leaving = false
	waiting = true
	position = Layout.DOOR_FRONT
	route = [p]
	_delay = 0.0
	visible = true


## 고용됨: 계약 카드로 들어가므로 월드에서 퇴장(카드 사용 시 다시 나타난다).
func vanish() -> void:
	waiting = false
	route.clear()
	Fx.vanish(self, Color(1.0, 0.85, 0.55, 0.8), 0.5)


func _process(delta: float) -> void:
	if _delay > 0.0:
		_delay -= delta
		if _delay > 0.0:
			return
		visible = true
	if _greet_left > 0.0:
		_greet_left -= delta
		visual.rotation.y = lerp_angle(visual.rotation.y, _greet_yaw, clampf(delta * 8.0, 0.0, 1.0))
		if _greet_left <= 0.0:
			rig.play("idle")
			visible = false
			arrived.emit()
		return
	if route.is_empty():
		if rig: rig.play("idle")
		return
	var tgt: Vector3 = route[0]
	var to := tgt - position
	to.y = 0
	var step := Cfg.GUEST_WALK_SPEED * delta
	if to.length() <= step:
		position = tgt
		route.pop_front()
		if route.is_empty():
			if leaving:
				queue_free()
			elif waiting:
				visual.rotation.y = deg_to_rad(35.0)
			elif rig and _rig_style.has("greet_time"):
				# 문 앞 인사가 있는 캐릭터(니브: 흥정꾼 인사)는 인사를 한 뒤 들어간다(입실 처리는 인사가 끝나면).
				_greet_left = float(_rig_style.get("greet_time", 1.0))
				_greet_yaw = visual.rotation.y + PI   # 문을 등지고 마당 쪽을 보며 인사
				rig.play("greet")
			else:
				visible = false
				arrived.emit()
		return
	position += to.normalized() * step
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(to.x, to.z), clampf(delta * 10.0, 0.0, 1.0))
	if rig:
		_wave_left = maxf(0.0, _wave_left - delta)
		rig.play("wave" if leaving and _wave_left > 0.0 else "walk")
		return
	_anim_t += delta * 9.0
	body.position.y = absf(sin(_anim_t)) * 0.05
