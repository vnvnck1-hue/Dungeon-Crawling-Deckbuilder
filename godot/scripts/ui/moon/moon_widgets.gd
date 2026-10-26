extends RefCounted
## 달빛 UI 기본 부품. 그룹 내부는 원본 아틀라스 px 좌표로 작성하고 그룹 전체를 슬롯 배율로 스케일한다.

const Layout := preload("res://scripts/ui/moon/moon_layout.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")


## 슬롯 하나(예: player_status). 크기 = 원본 아틀라스 영역, 배율·위치 = 슬롯 맞춤. 자체 입력은 받지 않는다.
class MoonGroup extends Control:
	var id := ""
	var origin := Vector2.ZERO  # 원본 아틀라스에서 이 그룹의 왼쪽 위

	func setup(group_id: String) -> MoonGroup:
		id = group_id
		name = "Moon_" + group_id
		var r: Rect2 = Layout.SLOTS[group_id]["atlas"]
		origin = r.position
		size = r.size
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		return self

	func _ready() -> void:
		get_parent().resized.connect(relayout)
		relayout()

	func relayout() -> void:
		var f: Array = Layout.fit(id, get_parent().size)
		position = f[0]
		scale = Vector2.ONE * float(f[1])

	## 원본 아틀라스 절대 좌표 rect를 그룹 내부 좌표로
	func local(abs_rect: Rect2) -> Rect2:
		return Rect2(abs_rect.position - origin, abs_rect.size)

	func add_piece(tex_id: String, abs_rect: Rect2) -> TextureRect:
		var t := TextureRect.new()
		t.name = tex_id
		t.texture = MoonSkin.tex(tex_id)
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var r := local(abs_rect)
		t.position = r.position
		t.size = r.size
		add_child(t)
		return t

	func add_label(abs_rect: Rect2, font_size: int, color: Color, bold := true,
			align := HORIZONTAL_ALIGNMENT_CENTER) -> MoonLabel:
		var l := MoonLabel.new()
		l.base_size = font_size
		l.add_theme_font_override("font", MoonSkin.font(bold))
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", color)
		l.horizontal_alignment = align
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		l.clip_text = false
		var r := local(abs_rect)
		l.position = r.position
		l.size = r.size
		add_child(l)
		return l

	## 툴팁을 보여 주는 투명 영역(이 영역 위 클릭은 월드로 가지 않는다)
	func add_hover(abs_rect: Rect2) -> Control:
		var c := Control.new()
		c.mouse_filter = Control.MOUSE_FILTER_STOP
		var r := local(abs_rect)
		c.position = r.position
		c.size = r.size
		add_child(c)
		return c


## 숫자가 길어져도 영역을 넘지 않도록 글자 크기만 줄이는 라벨(초상·게이지를 침범하지 않는다)
class MoonLabel extends Label:
	var base_size := 18
	var min_size := 10

	func set_value(t: String) -> void:
		if t == text:
			return
		text = t
		t = atr(t)   # 영문판: 화면에 나올 번역문 길이로 맞춘다
		var f: Font = get_theme_font("font")
		var fs := base_size
		var lines := 1 if autowrap_mode == TextServer.AUTOWRAP_OFF else 2
		while fs > min_size:
			if lines == 1:
				if f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x <= size.x:
					break
			else:
				var h := f.get_multiline_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, size.x, fs).y
				if h <= size.y:
					break
			fs -= 1
		add_theme_font_size_override("font_size", fs)


## 원본 채움 줄무늬를 3-slice로 줄여 그리는 게이지. 왼쪽/오른쪽 끝(cap)은 그대로, 가운데만 늘이거나 줄인다.
class MoonGauge extends Control:
	var fill_tex: Texture2D
	var cap := 6.0
	var value := 1.0
	var shown := 1.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_value(v: float, instant := false) -> void:
		var nv := clampf(v, 0.0, 1.0)
		# HUD 가 매 프레임 부르므로 값이 그대로면 다시 그리지 않는다(움직이는 중이면 _process 가 그린다)
		if nv == value and (not instant or shown == value):
			return
		value = nv
		if instant:
			shown = value
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_equal_approx(shown, value):
			shown = move_toward(shown, value, maxf(absf(value - shown), 0.05) * delta * 10.0)
			queue_redraw()

	func _draw() -> void:
		if fill_tex == null or shown <= 0.0:
			return
		var ts := fill_tex.get_size()
		var w := size.x * shown
		var c := minf(cap, w * 0.5)
		var tc := c * ts.y / size.y if size.y > 0 else c
		tc = minf(tc, ts.x * 0.5)
		draw_texture_rect_region(fill_tex, Rect2(0, 0, c, size.y), Rect2(0, 0, tc, ts.y))
		if w - 2.0 * c > 0.0:
			draw_texture_rect_region(fill_tex, Rect2(c, 0, w - 2.0 * c, size.y), Rect2(tc, 0, ts.x - 2.0 * tc, ts.y))
		draw_texture_rect_region(fill_tex, Rect2(w - c, 0, c, size.y), Rect2(ts.x - tc, 0, tc, ts.y))


## 그림 버튼. 승인 그림 그대로 두고 상태만 표시(명세 §5): hover=약한 청록 경계, pressed=1px 아래·명도 0.94,
## disabled=저채도(또는 별도 비활성 그림), focus=얇은 청록 링. 마우스와 키보드(Enter/Space)가 같은 신호로 간다.
class MoonButton extends Control:
	signal pressed

	var art: TextureRect
	var mat: ShaderMaterial
	var disabled := false: set = set_disabled
	var active_tint := Color(1, 1, 1, 0)  # 활성 임시 착색(최종 활성 그림이 없을 때만)
	var normal_tex: Texture2D
	var disabled_tex: Texture2D
	var _hover := false
	var _down := false
	var _mask: Image

	func setup(tex: Texture2D, local_rect: Rect2, disabled_texture: Texture2D = null) -> MoonButton:
		normal_tex = tex
		disabled_tex = disabled_texture
		position = local_rect.position
		size = local_rect.size
		focus_mode = Control.FOCUS_ALL
		mouse_filter = Control.MOUSE_FILTER_STOP
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		art = TextureRect.new()
		art.texture = tex
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_SCALE
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.size = size
		mat = MoonSkin.button_material()
		art.material = mat
		add_child(art)
		if tex != null:
			_mask = tex.get_image()
			if _mask != null and _mask.is_compressed():
				_mask = null
		mouse_entered.connect(_on_enter)
		mouse_exited.connect(_on_exit)
		focus_entered.connect(_refresh)
		focus_exited.connect(_refresh)
		_refresh()
		return self

	func _on_enter() -> void:
		_hover = true
		_refresh()

	func _on_exit() -> void:
		_hover = false
		_down = false
		_refresh()

	func set_disabled(v: bool) -> void:
		if disabled == v:
			return
		disabled = v
		if v:
			_down = false
		_refresh()

	## 투명 외곽은 누를 수 없다(그림 모양대로 판정)
	func _has_point(p: Vector2) -> bool:
		if not Rect2(Vector2.ZERO, size).has_point(p):
			return false
		if _mask == null:
			return true
		var ip := Vector2i((p / size * Vector2(_mask.get_size())).floor())
		ip = ip.clamp(Vector2i.ZERO, _mask.get_size() - Vector2i.ONE)
		return _mask.get_pixelv(ip).a > 0.1

	func _gui_input(event: InputEvent) -> void:
		var mb := event as InputEventMouseButton
		if mb != null and mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_down = not disabled
			else:
				var fire := _down and not disabled and _has_point(mb.position)
				_down = false
				if fire:
					pressed.emit()
			_refresh()
			accept_event()
		elif event.is_action_pressed("ui_accept") and has_focus() and not disabled:
			pressed.emit()
			accept_event()

	func _refresh() -> void:
		if art == null:
			return
		var use_disabled_art := disabled and disabled_tex != null
		art.texture = disabled_tex if use_disabled_art else normal_tex
		var px := 1.0 / maxf(get_global_transform().get_scale().y, 0.01)
		art.position = Vector2(0, px if _down else 0.0)
		mat.set_shader_parameter("brightness", 0.94 if _down else 1.0)
		mat.set_shader_parameter("saturation", 0.3 if disabled and not use_disabled_art else 1.0)
		if disabled and not use_disabled_art:
			mat.set_shader_parameter("brightness", 0.78)
		mat.set_shader_parameter("tint", active_tint if not disabled else Color(1, 1, 1, 0))
		var o := 0.0
		if not disabled and (_hover or _down):
			o = 0.55
		if has_focus() and not disabled:
			o = maxf(o, 0.9)
		if active_tint.a > 0.0 and not disabled:
			o = maxf(o, 0.35)
		mat.set_shader_parameter("outline", o)
		mat.set_shader_parameter("outline_px", 2.0 / maxf(_tex_scale(), 0.01))

	## 텍스처 px당 화면 px(외곽선 두께를 화면 기준 약 2px로 유지)
	func _tex_scale() -> float:
		if normal_tex == null:
			return 1.0
		return get_global_transform().get_scale().x * size.x / normal_tex.get_size().x
