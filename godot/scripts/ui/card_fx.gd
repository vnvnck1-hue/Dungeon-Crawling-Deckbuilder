extends Control
## 카드 획득·소모 연출 레이어: 입자 폭발, 반짝임, 떠오르는 수량 글자, 날아가거나 타 없어지는 카드 복제본.
## 표시 전용(입력·게임 상태 없음). 카드 위에 그려진다.

const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const CardView := preload("res://scripts/ui/card_view.gd")
const HandTime := preload("res://scripts/ui/hand_focus_time.gd")   # 손패 고민 시간: 세상이 늦춰져도 연출은 실제 시간으로
const REVEAL_GLOW := preload("res://shaders/card_reveal_glow.gdshader")

const GOLD := Color(1.0, 0.82, 0.42)
const TEAL := Color(0.45, 0.95, 0.95)
const CREAM := Color(1.0, 0.95, 0.82)

static var _dot: Texture2D


static func dot_texture() -> Texture2D:
	if _dot == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var t := GradientTexture2D.new()
		t.gradient = g
		t.width = 32
		t.height = 32
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
		_dot = t
	return _dot


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS


## 입자 폭발. s = 화면 배율(디자인 → 화면)
func burst(at: Vector2, s: float, amount := 40, colors: Array = [CREAM, GOLD, TEAL], speed := 240.0, up := false) -> void:
	var p := CPUParticles2D.new()
	p.position = at
	p.texture = dot_texture()
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.95
	p.lifetime = 0.85
	p.direction = Vector2(0, -1)
	p.spread = 70.0 if up else 180.0
	p.initial_velocity_min = speed * 0.45 * s
	p.initial_velocity_max = speed * s
	p.gravity = Vector2(0, 260.0 * s)
	p.damping_min = 40.0 * s
	p.damping_max = 90.0 * s
	p.scale_amount_min = 0.18 * s
	p.scale_amount_max = 0.5 * s
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, colors[0])
	ramp.set_color(1, Color(colors[-1], 0.0))
	if colors.size() > 2:
		ramp.add_point(0.45, colors[1])
	p.color_ramp = ramp
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = add
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.4, true, false, true).timeout.connect(p.queue_free)


## 카드 윤곽을 따라 퍼지는 에디티브 글로우(획득·공개·소모 순간의 강조).
## card_size = 카드의 화면 px 크기(배율 적용 후), rot_deg = 카드 회전. 섬광·충격파·광선은 셰이더가 그린다.
## 두 겹으로 올린다: 첫 겹이 터지고 LAYER_DELAY 뒤 조금 작고 옅은 둘째 겹이 뒤따라 깊이를 준다.
## 등장은 TRANS_BACK(살짝 넘쳤다 돌아옴), 퇴장은 TRANS_CUBIC EASE_IN 으로 여운을 남긴다.
const LAYER_DELAY := 0.09
func card_glow(at: Vector2, card_size: Vector2, rot_deg := 0.0, core := CREAM, mid := GOLD, edge := TEAL, strength := 1.0, dur := 0.8) -> void:
	_glow_layer(at, card_size, rot_deg, core, mid, edge, strength, dur, 1.0, 0.0)
	_glow_layer(at, card_size, rot_deg, core, mid, edge, strength * 0.6, dur * 0.9, 0.8, LAYER_DELAY)


## 글로우 한 겹. spread_mul = 파동 거리 배율, delay = 시작 지연(초)
func _glow_layer(at: Vector2, card_size: Vector2, rot_deg: float, core: Color, mid: Color, edge: Color, strength: float, dur: float, spread_mul: float, delay: float) -> void:
	var g := ColorRect.new()
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pad := Vector2.ONE * card_size.x * 0.6
	g.size = card_size + pad * 2.0
	g.pivot_offset = g.size * 0.5
	g.position = at - g.pivot_offset
	g.rotation_degrees = rot_deg
	g.color = Color.WHITE
	var m := ShaderMaterial.new()
	m.shader = REVEAL_GLOW
	m.set_shader_parameter("card_size", card_size)
	m.set_shader_parameter("pad", pad)
	m.set_shader_parameter("progress", 0.0)
	m.set_shader_parameter("seed", randf() * 10.0)
	m.set_shader_parameter("color_core", core)
	m.set_shader_parameter("color_mid", mid)
	m.set_shader_parameter("color_edge", edge)
	m.set_shader_parameter("spread", 0.42 * spread_mul)
	m.set_shader_parameter("flash_strength", 0.75 * strength)
	m.set_shader_parameter("ring_strength", 0.7 * strength)
	m.set_shader_parameter("ray_strength", 0.6 * strength)
	g.material = m
	g.scale = Vector2.ONE * 0.82
	g.visible = delay <= 0.0
	g.set_meta("glow_progress", 0.0)
	g.set_meta("glow_delay", delay)
	add_child(g)
	var tw := g.create_tween().set_ignore_time_scale(true)
	if delay > 0.0:
		tw.tween_interval(delay)
		tw.tween_callback(func(): g.visible = true)
	tw.set_parallel()
	# 진행도: 처음을 빠르게 밀어 넣는다(셰이더 안에서 다시 expo/quart 로 이징)
	tw.tween_method(func(v: float):
		m.set_shader_parameter("progress", v)
		g.set_meta("glow_progress", v), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# 크기: 0.82 → 1.0 을 넘쳤다 돌아오는 백 이징(텐션)
	tw.tween_property(g, "scale", Vector2.ONE, dur * 0.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	# 마지막엔 큐빅 인으로 거둔다
	tw.tween_property(g, "modulate:a", 0.0, dur * 0.35).set_delay(dur * 0.65).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	tw.chain().tween_callback(g.queue_free)


func float_text(at: Vector2, text: String, color: Color, s: float) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MoonSkin.font(true))
	l.add_theme_font_size_override("font_size", int(30 * s))
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.06, 0.03, 0.12, 0.95))
	l.add_theme_constant_override("outline_size", int(7 * s))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	l.reset_size()
	l.pivot_offset = l.size * 0.5
	l.position = at - l.size * 0.5
	l.scale = Vector2.ONE * 0.4
	var tw := l.create_tween().set_ignore_time_scale(true).set_parallel()
	tw.tween_property(l, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "position:y", l.position.y - 46.0 * s, 0.95).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.35).set_delay(0.65)
	tw.chain().tween_callback(l.queue_free)


## 카드 복제본이 from → to로 휘어 날아간다(스택 자원 획득 등). 도착 시 done 호출.
func fly(tex: Texture2D, from: Vector2, to: Vector2, card_size: Vector2, s0: float, s1: float, dur: float, done: Callable) -> void:
	var g := _ghost(tex, card_size)
	g.snap(from, randf_range(-8, 8), s0)
	g.flourish("toss", dur)   # 날아가는 동안 한 바퀴 핑그르르 돌며 휜다
	var arc := FlyFx.new()
	arc.card = g
	arc.from = from
	arc.to = to
	arc.s0 = s0
	arc.s1 = s1
	arc.dur = dur
	arc.done = done
	add_child(arc)


## 카드 복제본이 타 없어진다(스택 일부 소모). show_center 를 주면 그 자리로 크게 날아가 보여 준 뒤 탄다
func dissolve_copy(tex: Texture2D, at: Vector2, card_size: Vector2, rot: float, s: float, show_center := Vector2.INF, show_scale := 0.0) -> void:
	var g := _ghost(tex, card_size)
	g.snap(at, rot, s)
	g.start_dissolve(Callable(), show_center, show_scale)
	var d := DissolveFx.new()
	d.card = g
	add_child(d)


func _ghost(tex: Texture2D, card_size: Vector2) -> CardView:
	var g := CardView.new()
	g.setup("", tex)
	add_child(g)
	g.resize(card_size)
	return g


class FlyFx extends Node:
	var card
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var s0 := 1.0
	var s1 := 1.0
	var dur := 0.5
	var done: Callable
	var t := 0.0

	func _process(delta: float) -> void:
		delta = HandTime.ui_delta(delta)
		t = minf(t + delta / dur, 1.0)
		var e := t * t * (3.0 - 2.0 * t)
		var mid := from.lerp(to, 0.5) + Vector2(0, -minf(220.0, from.distance_to(to) * 0.35))
		card.snap(from.lerp(mid, e).lerp(mid.lerp(to, e), e), lerpf(card.rot, 0.0, 0.1), lerpf(s0, s1, e))
		card.t_lift = 1.0 - e
		card.lift = card.t_lift
		card.step_warp(delta)
		card._apply()
		if t >= 1.0:
			if done.is_valid():
				done.call()
			card.queue_free()
			queue_free()


class DissolveFx extends Node:
	var card

	func _process(delta: float) -> void:
		delta = HandTime.ui_delta(delta)
		card.step(delta)
		if card.tick_dissolve(delta):
			card.queue_free()
			queue_free()
