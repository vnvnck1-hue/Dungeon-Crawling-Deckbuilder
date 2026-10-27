extends Node3D
## 유닛 하나의 상태이상 3D 표시(표시 전용, unit_view 의 자식). 판정은 core/battle.gd, 숫자 칩은 hud.gd.
## 한눈에 "걸려 있다"를 알 수 있게 상태마다 몸·발밑·주변 세 군데에 동시에 보여 준다.
##   표식: 발밑 붉은 조준 고리 — 쌓인 수만큼 안쪽을 가리키는 화살촉(최대 6), 쌓일수록 크고 빨리 돈다(+ 머리 위 칩의 숫자)
##   화상: 몸에 타오르는 불꽃 띠(껍질 셰이더) + 계속 피어오르는 불씨·연기 + 주황 불빛 깜빡임 + 발밑 그을음
##   냉기: 몸에 서리 테두리 + 가슴 높이를 도는 얼음 조각(쌓인 수 / 빙결까지 3칸) + 발밑 서리 + 눈송이
##   빙결: 전신 얼음 막 + 몸을 가두는 얼음 덩어리와 발밑 얼음 가시 + 자세가 멈춘다. 풀리면 산산이 부서진다
##   투지(전사): 붉게 맥동하는 테두리 + 발밑 붉은 기운 고리 + 피어오르는 붉은 불씨(쌓일수록 많이)
## 사용: status_fx.setup(unit_view) 후 set_value(status, value, delta).

const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Pool := preload("res://scripts/visual/vfx/vfx_pool.gd")
const FrostVfx := preload("res://scripts/visual/vfx/frost_rune_vfx.gd")
const SHELL := preload("res://dungeon/shaders/status_shell.gdshader")
const D := preload("res://dungeon/data/defs.gd")

const C_MARK := Color(1.0, 0.24, 0.2)
const C_FIRE := Color(1.0, 0.5, 0.12)
const C_ICE := Color(0.62, 0.88, 1.0)
const C_FURY := Color(1.0, 0.22, 0.12)

var unit                         # unit_view
var values := {"mark": 0, "chill": 0, "burn": 0, "fury": 0, "freeze": 0}
var _shell_mat: ShaderMaterial
var _shells: Array = []
var _shown := {"burn": 0.0, "chill": 0.0, "freeze": 0.0, "fury": 0.0, "pulse": 0.0}   # 껍질 세기(부드럽게 따라간다)
var _mark_ring: Node3D
var _mark_ticks: Array = []
var _mark_mat: StandardMaterial3D
var _mark_pop := 0.0
var _shards: Array = []          # 냉기 얼음 조각(CHILL_FREEZE 개)
var _shard_pop: Array = []
var _frost: MeshInstance3D       # 발밑 서리(마녀산장 서리 자국)
var _ice: Node3D                 # 빙결 얼음 덩어리
var _ice_mat: StandardMaterial3D
var _fire_light: OmniLight3D
var _fury_ring: MeshInstance3D
var _fury_mat: StandardMaterial3D
var _emit_t := 0.0
var _flake_t := 0.0
var _fury_t := 0.0
var _height := 1.8


func setup(u) -> void:
	unit = u
	_height = float(u.hp_offset)
	_shell_mat = ShaderMaterial.new()
	_shell_mat.shader = SHELL
	_shell_mat.render_priority = 3
	_shell_mat.set_shader_parameter("height", _height)
	_make_shells(u.visual)


## 몸 파츠마다 같은 메시를 자식으로 하나 더 붙여 껍질 재질을 입힌다(파츠 애니메이션을 그대로 따라간다).
func _make_shells(root: Node) -> void:
	for n in root.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null or mi.skin != null or mi.has_meta("status_shell"):
			continue
		var s := MeshInstance3D.new()
		s.mesh = mi.mesh
		s.material_override = _shell_mat
		s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		s.set_meta("status_shell", true)
		s.visible = false
		mi.add_child(s)
		_shells.append(s)


## 상태 값 바꾸기. delta > 0 이면 막 걸린 순간의 연출(번쩍·팝)을 같이 낸다.
func set_value(status: String, value: int, delta := 0) -> void:
	if not values.has(status):
		return
	var before: int = values[status]
	values[status] = value
	match status:
		"mark":
			_set_mark(value, value > before)
		"chill":
			_set_chill(value, value > before)
		"burn":
			if value > before:
				_shown.pulse = 0.6
				_ignite(value)
			_update_light()
		"fury":
			_set_fury(value, value > before)
		"freeze":
			if value > 0 and before == 0:
				_freeze_on()
			elif value == 0 and before > 0:
				_freeze_off()


## 쓰러질 때: 모든 표시를 끈다.
func clear() -> void:
	for k in values.keys():
		if values[k] > 0:
			set_value(k, 0)
	for s in _shells:
		if is_instance_valid(s):
			s.visible = false


# ───────────────────────── 표식 ─────────────────────────

func _set_mark(n: int, grew: bool) -> void:
	if _mark_ring == null:
		if n <= 0:
			return
		_build_mark()
	_mark_ring.visible = n > 0
	for i in _mark_ticks.size():
		_mark_ticks[i].visible = i < n
	_mark_mat.albedo_color = Color(C_MARK.r, C_MARK.g, C_MARK.b, clampf(0.7 + 0.05 * n, 0.0, 1.0))
	if grew:
		_mark_pop = 1.0
		Fx.hit(unit.chest(), C_MARK)


func _build_mark() -> void:
	_mark_mat = Mats.unshaded(C_MARK, true, false)   # 가산이면 보라 바닥 위에서 분홍으로 바래 보여서 섞기로
	_mark_ring = B.node(self, Vector3(0, 0.07, 0), Vector3.ZERO, "MarkRing")
	var ring := B.torus(_mark_ring, 0.7, 0.78, Vector3.ZERO, _mark_mat)
	ring.scale = Vector3(1, 0.1, 1)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 쌓인 수만큼 켜지는 화살촉(안쪽을 가리킨다)
	for k in D.MARK_MAX:
		var a := k * TAU / D.MARK_MAX
		# 프리즘 꼭짓점(+Y)을 X 90° 로 눕혀 +Z 로, 다시 돌려 고리 가운데를 향하게
		var yaw := rad_to_deg(atan2(-cos(a), -sin(a)))
		var tick := B.prism(_mark_ring, Vector3(0.24, 0.3, 0.05), Vector3(cos(a), 0, sin(a)) * 1.0, _mark_mat, Vector3(90, yaw, 0))
		tick.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		tick.visible = false
		_mark_ticks.append(tick)


# ───────────────────────── 냉기·빙결 ─────────────────────────

func _set_chill(n: int, grew: bool) -> void:
	if _shards.is_empty() and n > 0:
		var mat := Mats.glow(C_ICE, 2.2)
		for k in D.CHILL_FREEZE:
			var s := MeshInstance3D.new()
			s.mesh = FrostVfx._get_shard(k % 3)
			s.material_override = mat
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			s.scale = Vector3.ONE * 0.22
			s.visible = false
			add_child(s)
			_shards.append(s)
			_shard_pop.append(0.0)
	for k in _shards.size():
		var on := k < n
		if on and not _shards[k].visible:
			_shard_pop[k] = 1.0
		_shards[k].visible = on
	_frost_mark(n > 0 or values.freeze > 0)
	if grew:
		_shown.pulse = 0.5
		Fx.burst(self, unit.chest(), C_ICE, 10, 2.2, 0.12, 0.6, true, -2.0)


func _frost_mark(on: bool) -> void:
	if _frost == null:
		if not on:
			return
		_frost = FrostVfx.slow_mark(self)
	FrostVfx.set_slow_mark(_frost, on)


func _freeze_on() -> void:
	if _ice == null:
		_ice = B.node(self, Vector3.ZERO, Vector3.ZERO, "IceBlock")
		_ice_mat = StandardMaterial3D.new()
		_ice_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_ice_mat.albedo_color = Color(0.72, 0.9, 1.0, 0.38)
		_ice_mat.emission_enabled = true
		_ice_mat.emission = Color(0.35, 0.6, 0.9)
		_ice_mat.emission_energy_multiplier = 0.6
		_ice_mat.roughness = 0.08
		_ice_mat.metallic_specular = 1.0
		_ice_mat.rim_enabled = true
		_ice_mat.rim = 1.0
		_ice_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var w: float = 0.55 * float(unit.visual.scale.x) + 0.25
		# 몸을 가두는 얼음 기둥(여섯 모 기둥 두 개를 엇갈려 각진 덩어리처럼)
		B.cyl(_ice, w * 0.9, w, _height * 0.95, Vector3(0, _height * 0.475, 0), _ice_mat, 6)
		B.cyl(_ice, w * 0.75, w * 0.85, _height * 0.7, Vector3(0.05, _height * 0.42, 0.04), _ice_mat, 6, Vector3(0, 30, 6))
		# 발밑 얼음 가시
		var spike_mat := Mats.glow(C_ICE, 1.6)
		for k in 7:
			var a := k * TAU / 7.0 + randf() * 0.4
			var s := MeshInstance3D.new()
			s.mesh = FrostVfx._get_shard(k % 3)
			s.material_override = spike_mat
			s.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			s.position = Vector3(cos(a), 0, sin(a)) * w * 1.05
			s.rotation = Vector3(randf_range(-0.5, 0.5), a, randf_range(0.3, 0.7) * signf(cos(a)))
			s.scale = Vector3.ONE * randf_range(0.35, 0.6)
			_ice.add_child(s)
		for c in _ice.find_children("*", "GeometryInstance3D", true, false):
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_ice.visible = true
	_ice.scale = Vector3(1.0, 0.05, 1.0)
	var tw := create_tween()
	tw.tween_property(_ice, "scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_shown.pulse = 1.0
	_frost_mark(true)
	Fx.burst(self, unit.chest(), Color(0.85, 0.97, 1.0), 22, 3.5, 0.16, 0.7, true, -3.0)
	Fx.hit(unit.chest(), C_ICE, true)


func _freeze_off() -> void:
	if _ice != null and _ice.visible:
		# 얼음이 산산이 부서진다
		Fx.burst(self, unit.chest(), C_ICE, 26, 5.0, 0.2, 0.8, true, -9.0)
		Fx.burst(self, unit.global_position + Vector3(0, 0.4, 0), Color(0.9, 0.98, 1.0), 14, 3.0, 0.14, 0.6, false, -9.0)
		var tw := create_tween()
		tw.tween_property(_ice, "scale", Vector3(1.25, 0.3, 1.25), 0.14)
		tw.tween_callback(func() -> void: _ice.visible = false)
	_frost_mark(values.chill > 0)


# ───────────────────────── 화상 ─────────────────────────

func _ignite(n: int) -> void:
	Fx.burst(self, unit.chest(), C_FIRE, 10 + n * 2, 2.6, 0.16, 0.6, true, 1.5)
	var P = Fx._p()
	if P != null:
		P.emit(Pool.SCORCH, unit.global_position + Vector3(0, 0.05, 0), Vector3.ZERO, 6.0, 1.3, Color(0.12, 0.06, 0.04, 0.6), {"ground": true})


func _update_light() -> void:
	var on: bool = values.burn > 0
	if _fire_light == null:
		if not on:
			return
		_fire_light = B.omni(self, Vector3(0, _height * 0.5, 0), Color(1.0, 0.5, 0.15), 1.2, 3.2)
	_fire_light.visible = on


# ───────────────────────── 투지 ─────────────────────────

func _set_fury(n: int, grew: bool) -> void:
	if _fury_ring == null:
		if n <= 0:
			return
		_fury_mat = Mats.unshaded(C_FURY, true, true)
		_fury_ring = B.torus(self, 0.5, 0.66, Vector3(0, 0.06, 0), _fury_mat)
		_fury_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fury_ring.visible = n > 0
	if grew:
		_shown.pulse = 0.4
		Fx.burst(self, unit.chest(), C_FURY, 8 + n, 2.4, 0.14, 0.5, true, 2.0)


# ───────────────────────── 매 프레임 ─────────────────────────

func _process(delta: float) -> void:
	if unit == null or not is_instance_valid(unit):
		return
	var t := Time.get_ticks_msec() * 0.001
	# 껍질 세기: 값으로 정한 목표를 부드럽게 따라간다
	var target := {
		"burn": clampf(0.45 + 0.12 * values.burn, 0.0, 1.0) if values.burn > 0 else 0.0,
		"chill": clampf(0.4 + 0.3 * values.chill, 0.0, 1.0) if values.chill > 0 else 0.0,
		"freeze": 1.0 if values.freeze > 0 else 0.0,
		"fury": clampf(0.3 + 0.09 * values.fury, 0.0, 1.0) if values.fury > 0 else 0.0,
	}
	var any := false
	for k in target:
		_shown[k] = move_toward(_shown[k], target[k], delta * 3.0)
		_shell_mat.set_shader_parameter(k, _shown[k])
		any = any or _shown[k] > 0.001
	_shown.pulse = move_toward(_shown.pulse, 0.0, delta * 2.5)
	_shell_mat.set_shader_parameter("pulse", _shown.pulse)
	_shell_mat.set_shader_parameter("base_y", global_position.y)
	var vis: bool = any or _shown.pulse > 0.01
	for s in _shells:
		if is_instance_valid(s):
			s.visible = vis
	# 표식: 고리가 돌고, 쌓일수록 커진다. 막 쌓이면 튕기듯 커졌다 돌아온다
	if _mark_ring != null and _mark_ring.visible:
		_mark_pop = move_toward(_mark_pop, 0.0, delta * 3.0)
		var k: float = 0.85 + 0.06 * values.mark + 0.45 * _mark_pop
		_mark_ring.scale = Vector3(k, 1.0, k)
		_mark_ring.rotation.y += delta * (1.2 + 0.25 * values.mark)
	# 냉기 조각: 가슴 높이를 돈다(빙결까지 남은 칸이 보이게 빈자리도 일정한 간격)
	for k in _shards.size():
		var s: MeshInstance3D = _shards[k]
		if not s.visible:
			continue
		_shard_pop[k] = move_toward(_shard_pop[k], 0.0, delta * 3.0)
		var a := t * 1.6 + k * TAU / _shards.size()
		var r: float = 0.55 + 0.25 * float(unit.visual.scale.x)
		s.position = Vector3(cos(a) * r, _height * 0.6 + 0.08 * sin(t * 2.0 + k), sin(a) * r)
		s.rotation = Vector3(0.4, -a, 0.3)
		s.scale = Vector3.ONE * (0.24 + 0.3 * _shard_pop[k])
	# 빙결 중에는 자세를 멈춘다
	if values.freeze > 0 and unit.rig != null:
		unit.rig.freeze(0.1)
	var P = Fx._p()
	if P == null:
		return
	# 화상: 불씨·불꽃·연기가 몸에서 계속 피어오른다(쌓일수록 자주)
	if values.burn > 0:
		_emit_t -= delta
		if _fire_light != null:
			_fire_light.light_energy = 0.9 + 0.25 * values.burn + 0.5 * sin(t * 23.0) * sin(t * 7.0)
		while _emit_t <= 0.0:
			_emit_t += 0.11 / (1.0 + 0.35 * values.burn)
			var p: Vector3 = global_position + Vector3(randf_range(-0.32, 0.32), randf_range(0.1, _height * 0.8), randf_range(-0.32, 0.32))
			P.emit(Pool.GLOW, p, Vector3(randf_range(-0.2, 0.2), randf_range(1.2, 2.2), randf_range(-0.2, 0.2)), randf_range(0.35, 0.6),
				randf_range(0.28, 0.5), Color(1.0, randf_range(0.35, 0.65), 0.1, 0.95), {"additive": true, "grow": 0.2, "drag": 1.2})
			if randf() < 0.45:
				P.emit(Pool.SPARKLE, p, Vector3(randf_range(-0.6, 0.6), randf_range(1.5, 3.0), randf_range(-0.6, 0.6)), randf_range(0.5, 0.9),
					0.12, Color(1.0, 0.8, 0.35), {"additive": true, "drag": 0.8, "curl": 2.0})
			if randf() < 0.18:
				P.emit(Pool.PUFF, p + Vector3(0, 0.3, 0), Vector3(0, 0.9, 0), 1.0, 0.45, Color(0.2, 0.16, 0.18, 0.45), {"grow": 2.2, "drag": 0.6})
	# 냉기·빙결: 주변에 눈송이가 내려앉는다
	if values.chill > 0 or values.freeze > 0:
		_flake_t -= delta
		if _flake_t <= 0.0:
			_flake_t = 0.22 if values.freeze > 0 else 0.4 / float(values.chill)
			var p: Vector3 = global_position + Vector3(randf_range(-0.6, 0.6), _height + 0.3, randf_range(-0.6, 0.6))
			P.emit(Pool.FLAKE, p, Vector3(randf_range(-0.2, 0.2), -0.8, randf_range(-0.2, 0.2)), 1.4, 0.16, Color(0.85, 0.95, 1.0, 0.9),
				{"additive": true, "sway": 1.2, "spin": randf_range(-3, 3)})
	# 투지: 발밑 고리가 맥동하고 붉은 불씨가 오른다
	if values.fury > 0 and _fury_ring != null:
		var beat := 1.0 + 0.1 * sin(t * 6.0)
		var k: float = (0.9 + 0.05 * values.fury) * beat
		_fury_ring.scale = Vector3(k, 0.15, k)
		_fury_mat.albedo_color.a = 0.35 + 0.06 * values.fury
		_fury_t -= delta
		if _fury_t <= 0.0:
			_fury_t = 0.5 / (1.0 + 0.4 * values.fury)
			var a := randf() * TAU
			var p: Vector3 = global_position + Vector3(cos(a) * 0.5, 0.1, sin(a) * 0.5)
			P.emit(Pool.GLOW, p, Vector3(0, randf_range(1.0, 1.8), 0), 0.6, 0.22, Color(1.0, 0.25, 0.1, 0.9), {"additive": true, "grow": 0.3})
