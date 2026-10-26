extends RefCounted
## 짧은 연출 효과 모음(피격 번쩍임, 타격·마법·발자국·입김·폭발 등). 게임 판정과 분리된 표시 전용 코드.
## 카툰 효과는 World가 만든 VfxPool(scripts/visual/vfx/vfx_pool.gd)에 입자를 보낸다.
## 풀이 없으면(도구 스크립트·검증 장면) 조용히 아무것도 하지 않는다.

const Mats := preload("res://scripts/visual/mats.gd")
const B := preload("res://scripts/visual/build.gd")
const Pool := preload("res://scripts/visual/vfx/vfx_pool.gd")

## World가 설정한다.
static var pool: Node3D = null

# 공용 팔레트(레퍼런스: 또렷한 흰 심지 + 채도 높은 테두리, 라벤더 그림자)
const C_MAGIC := Color(0.78, 0.45, 1.0)
const C_MAGIC_HOT := Color(1.0, 0.72, 1.0)
const C_SNOW := Color(0.97, 0.97, 1.0)
const C_SNOW_SHADE := Color(0.78, 0.8, 1.0)
const C_PRINT := Color(0.26, 0.25, 0.6, 0.72)
const C_GOLD := Color(1.0, 0.82, 0.3)
const C_FIRE := Color(1.0, 0.55, 0.15)
const C_DARK := Color(0.32, 0.22, 0.48)


static func _p():
	if pool != null and is_instance_valid(pool) and pool.is_inside_tree():
		return pool
	return null


static func _rv(spread: float) -> Vector3:
	return Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized() * spread


static func _rh(spread: float) -> Vector3:
	var a := randf() * TAU
	return Vector3(cos(a), 0, sin(a)) * spread


# ───────────────────────── 기존 효과 ─────────────────────────

static func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var painted := n.material_override is ShaderMaterial
		for i in n.mesh.get_surface_count():
			painted = painted or n.get_surface_override_material(i) is ShaderMaterial
		if painted: out.append(n)
	for c in n.get_children():
		_collect(c, out)


static func flash(root: Node3D, strength := 1.0) -> void:
	if root == null or not root.is_inside_tree():
		return
	var meshes: Array = []
	_collect(root, meshes)
	if meshes.is_empty():
		return
	var tw := root.create_tween().set_parallel(true)
	for m: MeshInstance3D in meshes:
		m.set_instance_shader_parameter("hit_flash", strength)
		tw.tween_property(m, "instance_shader_parameters/hit_flash", 0.0, 0.22)
	# 맞은 순간 몸이 납작해졌다 튕겨 돌아오는 카툰 스쿼시(건물처럼 약한 번쩍임에는 쓰지 않는다)
	if strength < 0.9 or root.has_meta("fx_squash"):
		return
	root.set_meta("fx_squash", true)
	var base := root.scale
	var sq := root.create_tween()
	sq.tween_property(root, "scale", Vector3(base.x * 1.18, base.y * 0.8, base.z * 1.18), 0.05)
	sq.tween_property(root, "scale", base, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	sq.tween_callback(func(): root.remove_meta("fx_squash"))


## 한 번 터지는 입자 묶음. 풀이 있으면 카툰 입자(반짝이·몽글)로 그린다.
static func burst(parent: Node, pos: Vector3, color: Color, amount := 16, speed := 3.0,
		size := 0.18, lifetime := 0.6, additive := true, gravity := -4.0) -> void:
	var P = _p()
	if P != null:
		for i in amount:
			var v := _rv(1.0)
			v.y = absf(v.y) * 0.8 + 0.3
			v = v.normalized() * randf_range(speed * 0.5, speed)
			var shape := Pool.SPARKLE if additive and i % 3 != 0 else (Pool.GLOW if additive else Pool.PUFF)
			P.emit(shape, pos, v, lifetime * randf_range(0.7, 1.2), size * randf_range(1.2, 2.0), color,
				{"gravity": gravity, "drag": 1.8, "additive": additive, "pop": true, "grow": 0.4,
				"spin": randf_range(-6, 6)})
		return
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 0.95
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 80.0
	pm.initial_velocity_min = speed * 0.5
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, gravity, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	p.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	q.material = Mats.particle(color, additive)
	p.draw_pass_1 = q
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	p.get_tree().create_timer(lifetime + 0.5, false).timeout.connect(p.queue_free)


## 죽음·퇴장: 작게 줄어들며 사라짐 + 카툰 연기 뭉치(펑!).
static func vanish(node: Node3D, color := Color(0.35, 0.28, 0.6, 0.8), duration := 0.35) -> void:
	var at := node.global_position + Vector3(0, 0.5, 0)
	if _p() != null:
		poof(at, Color(color.r, color.g, color.b, 1.0), 1.0)
	else:
		burst(node.get_parent(), at, color, 14, 1.6, 0.45, 0.8, false, 0.8)
	var tw := node.create_tween()
	tw.tween_property(node, "scale", Vector3(0.05, 0.05, 0.05), duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(node.queue_free)


## 불덩이 폭발: 섬광(광원) + 카툰 화염 별 + 연기 구름 고리 + 불씨 + 그을음.
static func explosion(parent: Node, pos: Vector3, radius: float) -> void:
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos
	var light := B.omni(root, Vector3(0, 1.5, 0), Color(1.0, 0.45, 0.14), 2.6, radius * 1.8, false, 1.2)
	var tw := root.create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	root.get_tree().create_timer(2.0, false).timeout.connect(root.queue_free)
	var P = _p()
	if P == null:
		burst(root, pos + Vector3(0, 0.4, 0), Color(1.0, 0.6, 0.25), 24, 5.0, 0.24, 0.7, true, -6.0)
		return
	var g := Vector3(pos.x, 0.0, pos.z)
	# 화염 별(겹쳐서 주황 → 노랑 심지)
	P.emit(Pool.SHOCK, g + Vector3(0, 0.9, 0), Vector3.ZERO, 0.42, radius * 1.5, Color(1.0, 0.5, 0.12), {"pop": true, "grow": 1.25, "additive": false})
	P.emit(Pool.SHOCK, g + Vector3(0, 1.0, 0), Vector3.ZERO, 0.3, radius * 1.0, Color(1.0, 0.85, 0.3), {"pop": true, "grow": 1.2, "additive": true})
	P.emit(Pool.GLOW, g + Vector3(0, 1.0, 0), Vector3.ZERO, 0.35, radius * 2.6, Color(1.0, 0.5, 0.15, 0.8), {"additive": true, "grow": 1.4})
	# 지면 충격 고리 + 그을음
	P.emit(Pool.RING, g + Vector3(0, 0.05, 0), Vector3.ZERO, 0.45, radius * 0.6, Color(1.0, 0.75, 0.4, 0.9), {"ground": true, "grow": 4.2, "additive": true})
	P.emit(Pool.SCORCH, g + Vector3(0, 0.025, 0), Vector3.ZERO, 6.0, radius * 1.3, Color(0.13, 0.08, 0.2, 0.55), {"ground": true, "fade_in": 0.02})
	# 불꽃 뭉치(주황·노랑) → 위로 피어오르는 따뜻한 연기 구름
	for i in 9:
		var d := _rh(1.0)
		P.emit(Pool.PUFF, g + d * radius * 0.25 + Vector3(0, 0.6 + randf() * 0.5, 0), d * randf_range(3.0, 4.5) + Vector3(0, 1.5, 0),
			randf_range(0.3, 0.45), randf_range(0.7, 1.0), Color(1.0, 0.62, 0.18) if i % 2 else Color(1.0, 0.85, 0.35),
			{"drag": 4.0, "grow": 0.5, "pop": true, "additive": true})
	for i in 7:
		var d2 := _rh(1.0)
		var at := g + d2 * radius * 0.3 + Vector3(0, 0.9 + randf() * 0.6, 0)
		P.emit(Pool.CLOUD if i % 2 == 0 else Pool.PUFF, at, d2 * randf_range(1.5, 2.5) + Vector3(0, 1.8, 0), randf_range(0.9, 1.3),
			randf_range(0.6, 0.95), Color(0.66, 0.56, 0.72), {"drag": 2.5, "grow": 1.7, "pop": true, "fade_in": 0.15})
	# 불씨·파편
	for i in 18:
		var v := _rh(randf_range(3.0, 7.0)) + Vector3(0, randf_range(4.0, 8.0), 0)
		P.emit(Pool.SPARKLE if i % 2 == 0 else Pool.GLOW, g + Vector3(0, 0.6, 0), v, randf_range(0.6, 1.0), randf_range(0.25, 0.45),
			Color(1.0, 0.7, 0.25), {"gravity": -14.0, "drag": 0.8, "additive": true, "spin": 8.0})
	for i in 8:
		var v2 := _rh(randf_range(2.0, 5.0)) + Vector3(0, randf_range(5.0, 8.0), 0)
		P.emit(Pool.LEAF, g + Vector3(0, 0.4, 0), v2, 1.4, randf_range(0.18, 0.28), Color(0.3, 0.22, 0.3),
			{"gravity": -16.0, "spin": randf_range(-14, 14), "land": true})


# ───────────────────────── 마법·투사체 ─────────────────────────

## 지팡이 끝 발사 섬광 + 발밑 마법진.
static func cast(tip: Vector3, feet: Vector3, color := C_MAGIC) -> void:
	var P = _p()
	if P == null: return
	P.emit(Pool.GLOW, tip, Vector3.ZERO, 0.18, 1.1, color, {"additive": true, "pop": true, "grow": 0.4})
	P.emit(Pool.SPARKLE, tip, Vector3.ZERO, 0.22, 0.9, C_MAGIC_HOT, {"additive": true, "pop": true, "grow": 0.3, "rot": 0.0})
	P.emit(Pool.RING, tip, Vector3.ZERO, 0.22, 0.25, color, {"additive": true, "grow": 3.2})
	for i in 5:
		P.emit(Pool.SPARKLE, tip, _rv(randf_range(1.0, 2.2)) + Vector3(0, 0.6, 0), randf_range(0.3, 0.5), randf_range(0.14, 0.24), C_MAGIC_HOT,
			{"additive": true, "drag": 3.0, "spin": 8.0, "gravity": 1.0})
	P.emit(Pool.RING, feet + Vector3(0, 0.04, 0), Vector3.ZERO, 0.4, 0.9, Color(color.r, color.g, color.b, 0.8), {"ground": true, "additive": true, "grow": 1.8})
	P.emit(Pool.GLOW, feet + Vector3(0, 0.03, 0), Vector3.ZERO, 0.35, 1.7, Color(color.r, color.g, color.b, 0.45), {"ground": true, "additive": true, "grow": 0.7})


## 투사체 머리: 매 프레임 호출(짧게 사는 입자로 혜성 머리를 그린다).
static func comet_head(pos: Vector3, vel: Vector3, color := C_MAGIC, scale := 1.0) -> void:
	var P = _p()
	if P == null: return
	var ang: float = P.screen_angle(vel)
	# 밝은 눈밭에서도 색이 남도록 채도 높은 반투명 후광을 먼저 깔고, 그 위에 가산 심지
	P.emit(Pool.GLOW, pos, Vector3.ZERO, 0.05, 1.0 * scale, Color(color.r * 0.7, color.g * 0.55, color.b, 0.75))
	P.emit(Pool.GLOW, pos, Vector3.ZERO, 0.05, 0.6 * scale, Color(color.r, color.g, color.b, 0.9), {"additive": true})
	P.emit(Pool.STREAK, pos - vel.normalized() * 0.12 * scale, Vector3.ZERO, 0.04, 0.26 * scale, color.lightened(0.35), {"additive": true, "aspect": 3.0, "rot": ang + PI})
	if randf() < 0.6:
		P.emit(Pool.SPARKLE, pos + _rv(0.12 * scale), -vel * 0.08 + _rv(0.5), randf_range(0.25, 0.45), randf_range(0.12, 0.22) * scale,
			C_MAGIC_HOT if randf() < 0.5 else color, {"additive": true, "spin": 7.0, "grow": 0.2, "drag": 2.0})


## 타격: 별 모양 충격 + 반짝이 + 작은 고리. big=true면 더 크게.
static func hit(pos: Vector3, color := C_MAGIC, big := false) -> void:
	var P = _p()
	if P == null: return
	var k := 1.5 if big else 1.0
	P.emit(Pool.SHOCK, pos, Vector3.ZERO, 0.2, 0.85 * k, color, {"pop": true, "grow": 1.25, "additive": false})
	P.emit(Pool.GLOW, pos, Vector3.ZERO, 0.16, 1.2 * k, color, {"additive": true, "grow": 0.6})
	P.emit(Pool.RING, pos, Vector3.ZERO, 0.22, 0.3 * k, Color(1, 1, 1, 0.9), {"additive": true, "grow": 3.6})
	for i in int(6 * k):
		var v := _rv(randf_range(2.5, 4.5) * k)
		v.y = absf(v.y) + 1.0
		P.emit(Pool.STAR if i % 3 == 0 else Pool.SPARKLE, pos, v, randf_range(0.3, 0.5), randf_range(0.14, 0.24) * k,
			color.lightened(0.3), {"gravity": -9.0, "drag": 1.5, "spin": randf_range(-10, 10), "additive": i % 3 != 0})


## 근접 공격 베기(용병): 초승달 섬광.
static func slash(pos: Vector3, dir: Vector3, color := Color(1.0, 0.92, 0.65)) -> void:
	var P = _p()
	if P == null: return
	var ang: float = P.screen_angle(dir)
	P.emit(Pool.SLASH, pos + dir.normalized() * 0.35, dir * 0.6, 0.2, 1.2, color, {"rot": ang - PI * 0.5, "pop": true, "grow": 1.3, "additive": true})
	P.emit(Pool.SLASH, pos + dir.normalized() * 0.35, dir * 0.6, 0.16, 1.0, Color(1, 1, 1, 0.8), {"rot": ang - PI * 0.5 + 0.25, "pop": true, "grow": 1.25})


## 몬스터 할퀴기: 보랏빛 세 줄 발톱 자국.
static func claw(pos: Vector3, dir: Vector3, color := Color(0.85, 0.35, 1.0)) -> void:
	var P = _p()
	if P == null: return
	var ang: float = P.screen_angle(dir)
	P.emit(Pool.CLAW, pos + dir.normalized() * 0.3, Vector3.ZERO, 0.26, 0.9, color, {"rot": ang + 0.5, "pop": true, "grow": 1.15})


## 떠오르는 피해 숫자(레퍼런스의 굵은 숫자 + 어두운 외곽선).
static func damage_number(parent: Node, pos: Vector3, amount: float, color := Color(1.0, 0.95, 0.55)) -> void:
	if parent == null or not parent.is_inside_tree() or _p() == null:
		return
	var l := Label3D.new()
	l.text = str(int(round(amount)))
	l.font_size = 76
	l.outline_size = 22
	l.pixel_size = 0.0065
	l.modulate = color
	l.outline_modulate = Color(0.16, 0.08, 0.22)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 20
	l.outline_render_priority = 19
	l.double_sided = true
	parent.add_child(l)
	l.global_position = pos + Vector3(randf_range(-0.25, 0.25), 0, randf_range(-0.25, 0.25))
	l.scale = Vector3.ONE * 0.3
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE * 1.25, 0.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y + 1.0, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_property(l, "scale", Vector3.ONE * 0.95, 0.12)
	tw.tween_property(l, "modulate:a", 0.0, 0.3).set_delay(0.3)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.3).set_delay(0.3)
	tw.chain().tween_callback(l.queue_free)


## 떠오르는 짧은 글(+골드 등).
static func float_text(parent: Node, pos: Vector3, text: String, color: Color) -> void:
	if parent == null or not parent.is_inside_tree() or _p() == null:
		return
	var l := Label3D.new()
	l.text = text
	l.font_size = 60
	l.outline_size = 18
	l.pixel_size = 0.0065
	l.modulate = color
	l.outline_modulate = Color(0.22, 0.12, 0.08)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.render_priority = 20
	l.outline_render_priority = 19
	parent.add_child(l)
	l.global_position = pos
	l.scale = Vector3.ONE * 0.4
	var tw := l.create_tween().set_parallel(true)
	tw.tween_property(l, "scale", Vector3.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y + 1.3, 1.2).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.4).set_delay(0.8)
	tw.tween_property(l, "outline_modulate:a", 0.0, 0.4).set_delay(0.8)
	tw.chain().tween_callback(l.queue_free)


# ───────────────────────── 캐릭터 주변 ─────────────────────────

## 눈 위 발자국(지면에 눕는 자국, 서서히 사라짐).
static func footprint(pos: Vector3, yaw: float, size := 0.32, color := C_PRINT, life := 7.0) -> void:
	var P = _p()
	if P == null: return
	P.emit(Pool.FOOT, Vector3(pos.x, 0.05, pos.z), Vector3.ZERO, life, size, color, {"ground": true, "rot": yaw, "aspect": 0.62})


## 걸음마다 발끝에서 튀는 작은 눈 뭉치.
static func snow_kick(pos: Vector3, back: Vector3, amount := 2, scale := 1.0) -> void:
	var P = _p()
	if P == null: return
	for i in amount:
		var v := back * randf_range(0.6, 1.2) + _rh(0.4) + Vector3(0, randf_range(1.0, 1.8), 0)
		P.emit(Pool.PUFF, pos + Vector3(0, 0.08, 0), v * scale, randf_range(0.35, 0.5), randf_range(0.12, 0.2) * scale, C_SNOW,
			{"gravity": -7.0, "drag": 1.0, "grow": 0.3})


## 입김: 얼굴 앞에서 퍼지며 떠오르는 몽글한 김.
static func breath(pos: Vector3, forward: Vector3, color := Color(1, 1, 1, 0.6), scale := 1.0) -> void:
	var P = _p()
	if P == null: return
	var f := Vector3(forward.x, 0, forward.z).normalized()
	for i in 4:
		var v := f * randf_range(0.5, 0.9) * scale + Vector3(0, randf_range(0.15, 0.35), 0) + _rh(0.12)
		P.emit(Pool.PUFF, pos + f * 0.06 * i, v, randf_range(1.3, 1.8), randf_range(0.16, 0.22) * scale,
			Color(color.r, color.g, color.b, minf(color.a + 0.15, 0.9)), {"grow": randf_range(3.2, 4.0), "drag": 1.4, "fade_in": 0.06})


## 몬스터 출현: 바닥의 어두운 소환진 + 보랏빛 연기 뭉치.
static func spawn_portal(pos: Vector3) -> void:
	var P = _p()
	if P == null: return
	var g := Vector3(pos.x, 0.04, pos.z)
	P.emit(Pool.RING, g, Vector3.ZERO, 0.9, 0.4, Color(0.75, 0.3, 1.0, 0.9), {"ground": true, "additive": true, "grow": 4.5})
	P.emit(Pool.SCORCH, g, Vector3.ZERO, 1.6, 1.8, Color(0.12, 0.05, 0.2, 0.6), {"ground": true, "fade_in": 0.1})
	for i in 7:
		var d := _rh(1.0)
		P.emit(Pool.PUFF if i % 2 else Pool.CLOUD, g + d * 0.3 + Vector3(0, 0.3, 0), d * randf_range(1.2, 2.2) + Vector3(0, 0.8, 0),
			randf_range(0.6, 0.9), randf_range(0.5, 0.8), Color(0.42, 0.28, 0.6), {"drag": 3.0, "grow": 1.5, "pop": true})
	for i in 6:
		P.emit(Pool.SPARKLE, g + _rh(0.5), Vector3(0, randf_range(1.5, 3.0), 0), randf_range(0.5, 0.8), 0.2, Color(0.85, 0.5, 1.0),
			{"additive": true, "spin": 6.0, "drag": 1.0})


## 아군 소환: 카드가 땅에 떨어진 자리에 빛 기둥 + 마법진 + 별.
static func summon(pos: Vector3, color := Color(1.0, 0.82, 0.45)) -> void:
	var P = _p()
	if P == null: return
	var g := Vector3(pos.x, 0.04, pos.z)
	P.emit(Pool.RING, g, Vector3.ZERO, 0.7, 0.6, color, {"ground": true, "additive": true, "grow": 3.2})
	P.emit(Pool.RING, g, Vector3.ZERO, 0.9, 1.9, Color(color.r, color.g, color.b, 0.7), {"ground": true, "additive": true, "grow": 0.6})
	P.emit(Pool.GLOW, g, Vector3.ZERO, 0.8, 2.6, Color(color.r, color.g, color.b, 0.55), {"ground": true, "additive": true, "grow": 0.5})
	P.emit(Pool.GLOW, g + Vector3(0, 1.5, 0), Vector3.ZERO, 0.45, 3.4, Color(color.r, color.g, color.b, 0.7), {"additive": true, "aspect": 0.28, "grow": 0.3, "rot": 0.0})
	for i in 8:
		var d := _rh(1.0)
		P.emit(Pool.STAR if i % 2 == 0 else Pool.SPARKLE, g + Vector3(0, 0.6, 0), d * randf_range(2.0, 3.5) + Vector3(0, randf_range(2.5, 4.0), 0),
			randf_range(0.5, 0.8), randf_range(0.22, 0.34), color.lightened(0.2), {"gravity": -9.0, "drag": 1.2, "spin": 9.0, "additive": i % 2 == 1, "pop": true})
	for i in 6:
		var d2 := _rh(1.0)
		P.emit(Pool.PUFF, g + d2 * 0.4 + Vector3(0, 0.15, 0), d2 * 2.4, 0.6, 0.45, C_SNOW, {"drag": 4.0, "grow": 1.4, "pop": true})


## 펑! 카툰 연기 뭉치(죽음·퇴장).
static func poof(pos: Vector3, color: Color, scale := 1.0) -> void:
	var P = _p()
	if P == null: return
	P.emit(Pool.CLOUD, pos, Vector3(0, 0.6, 0), 0.6, 1.1 * scale, color.lightened(0.15), {"pop": true, "grow": 1.4, "drag": 2.0})
	for i in 8:
		var d := _rh(1.0)
		P.emit(Pool.PUFF, pos + d * 0.2, d * randf_range(1.6, 2.6) * scale + Vector3(0, randf_range(0.3, 1.2), 0),
			randf_range(0.45, 0.7), randf_range(0.35, 0.55) * scale, color, {"drag": 3.5, "grow": 1.3, "pop": true})
	for i in 3:
		var d2 := _rh(1.0)
		P.emit(Pool.STAR, pos + Vector3(0, 0.3, 0), d2 * 1.8 + Vector3(0, 2.6, 0), 0.7, 0.26 * scale, Color(1.0, 0.92, 0.5),
			{"gravity": -7.0, "spin": 10.0, "pop": true})


## 도끼질 나무 조각 + 나무 꼭대기에서 떨어지는 눈.
static func wood_chips(pos: Vector3, crown := Vector3.INF) -> void:
	var P = _p()
	if P == null: return
	for i in 4:
		var v := _rh(randf_range(1.0, 2.2)) + Vector3(0, randf_range(2.2, 3.6), 0)
		P.emit(Pool.LEAF, pos, v, 1.6, randf_range(0.12, 0.2), Color(0.86, 0.62, 0.36) if i % 2 else Color(0.62, 0.42, 0.26),
			{"gravity": -12.0, "spin": randf_range(-16, 16), "land": true, "aspect": 0.6})
	P.emit(Pool.SHOCK, pos, Vector3.ZERO, 0.12, 0.45, Color(1.0, 0.9, 0.7), {"pop": true, "additive": true})
	if crown != Vector3.INF:
		for i in 3:
			P.emit(Pool.PUFF, crown + _rh(randf_range(0.3, 1.0)), Vector3(0, -0.5, 0), randf_range(0.8, 1.1), randf_range(0.2, 0.32), C_SNOW,
				{"gravity": -7.0, "land": true, "grow": 0.6})


## 나무가 다 베였을 때: 큰 눈 뭉치가 쏟아진다.
static func tree_fall(pos: Vector3, height := 6.0) -> void:
	var P = _p()
	if P == null: return
	for i in 14:
		var at := pos + _rh(randf_range(0.2, 1.4)) + Vector3(0, randf_range(1.0, height * 0.7), 0)
		P.emit(Pool.PUFF if i % 3 else Pool.CLOUD, at, _rh(0.6) + Vector3(0, -1.0, 0), randf_range(1.0, 1.4), randf_range(0.4, 0.75), C_SNOW,
			{"gravity": -6.0, "land": true, "grow": 1.2, "pop": true})
	for i in 8:
		var d := _rh(1.0)
		P.emit(Pool.PUFF, pos + d * 0.5 + Vector3(0, 0.2, 0), d * 3.0, 0.7, 0.55, C_SNOW, {"drag": 4.0, "grow": 1.6, "pop": true})


## 양털 수확: 몽실몽실 털 뭉치 + 반짝이.
static func wool(pos: Vector3) -> void:
	var P = _p()
	if P == null: return
	for i in 10:
		var v := _rh(randf_range(0.8, 2.0)) + Vector3(0, randf_range(2.0, 3.4), 0)
		P.emit(Pool.CLOUD if i % 3 == 0 else Pool.PUFF, pos, v, randf_range(0.8, 1.1), randf_range(0.22, 0.38), Color(1.0, 0.97, 0.88),
			{"gravity": -6.0, "drag": 1.4, "pop": true, "spin": randf_range(-3, 3), "land": true})
	for i in 6:
		P.emit(Pool.SPARKLE, pos + _rv(0.4), Vector3(0, 1.2, 0), randf_range(0.5, 0.8), 0.22, Color(1.0, 0.95, 0.7), {"additive": true, "spin": 6.0, "pop": true})


## 회복: 초록 십자와 반짝이가 피어오른다.
static func heal(pos: Vector3) -> void:
	var P = _p()
	if P == null: return
	for i in 5:
		P.emit(Pool.PLUS, pos + _rh(randf_range(0.2, 0.5)) + Vector3(0, randf() * 0.4, 0), Vector3(0, randf_range(1.0, 1.6), 0),
			randf_range(0.7, 1.0), randf_range(0.22, 0.32), Color(0.5, 1.0, 0.55), {"pop": true, "drag": 0.6})
	for i in 6:
		P.emit(Pool.SPARKLE, pos + _rh(0.5), Vector3(0, 1.5, 0), 0.7, 0.18, Color(0.75, 1.0, 0.7), {"additive": true, "spin": 5.0})


## 산장 피격: 나무 조각과 지붕 눈가루.
static func splinters(pos: Vector3) -> void:
	var P = _p()
	if P == null: return
	for i in 4:
		var v := _rh(randf_range(1.0, 2.5)) + Vector3(0, randf_range(2.0, 3.5), 0)
		P.emit(Pool.LEAF, pos, v, 1.2, randf_range(0.14, 0.22), Color(0.7, 0.45, 0.28), {"gravity": -12.0, "spin": 14.0, "land": true, "aspect": 0.5})
	P.emit(Pool.PUFF, pos + Vector3(0, 0.2, 0), Vector3(0, 0.8, 0), 0.5, 0.4, C_SNOW, {"grow": 1.6, "drag": 2.0, "pop": true})


## 반짝이는 고리(건설·수리·용 공물 등 긍정적 사건).
static func celebrate(pos: Vector3, color := C_GOLD, scale := 1.0) -> void:
	var P = _p()
	if P == null: return
	var g := Vector3(pos.x, 0.04, pos.z)
	P.emit(Pool.RING, g, Vector3.ZERO, 0.6, 0.8 * scale, color, {"ground": true, "additive": true, "grow": 3.5})
	for i in 10:
		var d := _rh(1.0)
		P.emit(Pool.CLOUD if i % 2 else Pool.PUFF, g + d * 0.8 * scale + Vector3(0, 0.3, 0), d * 2.6 * scale, 0.75, randf_range(0.55, 0.85) * scale, C_SNOW,
			{"drag": 3.5, "grow": 1.4, "pop": true})
	for i in 12:
		var v := _rh(randf_range(1.5, 3.5)) + Vector3(0, randf_range(3.0, 5.0), 0)
		P.emit(Pool.STAR if i % 3 == 0 else Pool.SPARKLE, pos, v * scale, randf_range(0.6, 0.9), randf_range(0.2, 0.32) * scale, color,
			{"gravity": -9.0, "drag": 1.0, "spin": 9.0, "additive": i % 3 != 0, "pop": true})


## 골드 획득: 금빛 반짝이와 동전 별이 튀어오른다.
static func gold(pos: Vector3, amount: int) -> void:
	var P = _p()
	if P == null: return
	for i in clampi(amount / 4 + 3, 3, 10):
		var v := _rh(randf_range(0.6, 1.6)) + Vector3(0, randf_range(3.0, 4.5), 0)
		P.emit(Pool.STAR, pos, v, randf_range(0.7, 0.9), randf_range(0.2, 0.28), C_GOLD, {"gravity": -10.0, "spin": 8.0, "pop": true})
	P.emit(Pool.GLOW, pos, Vector3.ZERO, 0.3, 1.2, C_GOLD, {"additive": true, "grow": 0.5})


## 무덤이 생김: 희미한 넋 빛이 위로 올라가며 흩어진다.
static func soul(pos: Vector3) -> void:
	var P = _p()
	if P == null: return
	P.emit(Pool.GLOW, pos, Vector3(0, 0.8, 0), 1.4, 0.9, Color(0.75, 0.8, 1.0, 0.55), {"additive": true, "grow": 0.4, "sway": 0.4})
	for i in 7:
		P.emit(Pool.SPARKLE, pos + _rh(0.35), Vector3(0, randf_range(0.7, 1.4), 0) + _rh(0.2), randf_range(1.0, 1.6), randf_range(0.12, 0.2),
			Color(0.82, 0.86, 1.0), {"additive": true, "spin": 4.0, "sway": 0.6, "fade_in": 0.1})


const LEAF_SHED := [Color(0.35, 0.62, 0.3), Color(0.5, 0.72, 0.32), Color(0.78, 0.6, 0.25), Color(0.3, 0.5, 0.28)]

## 큰 숲의 괴물의 걸음: 등의 가지에서 나뭇잎이 한두 장 팔랑이며 떨어진다.
static func leaf_shed(pos: Vector3, back: Vector3, amount := 1) -> void:
	var P = _p()
	if P == null: return
	for i in amount:
		P.emit(Pool.LEAF, pos + _rv(0.25), back * randf_range(0.2, 0.5) + _rh(0.35) + Vector3(0, randf_range(-0.2, 0.25), 0),
			randf_range(2.6, 3.6), randf_range(0.17, 0.24), LEAF_SHED[randi() % LEAF_SHED.size()],
			{"gravity": -0.9, "drag": 0.8, "sway": randf_range(0.8, 1.5), "spin": randf_range(-5.0, 5.0), "land": true, "aspect": 0.55})


## 숲의 괴물 하수인이 시들어 목재가 됨: 나뭇잎·나무 조각이 흩어지고 별이 튄다.
static func wither(pos: Vector3) -> void:
	var P = _p()
	if P == null: return
	for i in 10:
		var v := _rh(randf_range(0.8, 2.0)) + Vector3(0, randf_range(1.6, 3.0), 0)
		var c: Color = LEAF_SHED[randi() % LEAF_SHED.size()] if i % 2 else Color(0.7, 0.5, 0.3)
		P.emit(Pool.LEAF, pos, v, randf_range(1.4, 2.0), randf_range(0.14, 0.22), c,
			{"gravity": -6.0, "drag": 0.8, "spin": randf_range(-10, 10), "sway": 0.8, "land": true, "aspect": 0.6})
	celebrate(pos + Vector3(0, 0.4, 0), Color(0.95, 0.78, 0.5), 0.8)


## 털 깎기 중: 가위질마다 작은 털 뭉치가 튄다.
static func shear(pos: Vector3) -> void:
	var P = _p()
	if P == null: return
	for i in 2:
		var v := _rh(randf_range(0.4, 1.0)) + Vector3(0, randf_range(0.8, 1.6), 0)
		P.emit(Pool.PUFF, pos + _rv(0.12), v, randf_range(0.6, 0.9), randf_range(0.1, 0.17), Color(1.0, 0.97, 0.9),
			{"gravity": -4.0, "drag": 1.6, "pop": true, "land": true})
	P.emit(Pool.SPARKLE, pos, Vector3(0, 0.6, 0), 0.3, 0.16, Color(1.0, 1.0, 0.9), {"additive": true, "pop": true})
