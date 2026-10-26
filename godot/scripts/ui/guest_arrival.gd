extends CanvasLayer
## 비차단 도착 소개는 손패 위에 표시한 뒤 초상을 관리 버튼으로 보낸다.
## 한 번에 온 손님들은 대화창 하나에서 차례로 인사하고(앞 손님 초상이 같은 자리에서 다음 손님 초상으로 교차 전환된다, 2026-10-23),
## 마지막 손님까지 끝나면 관리 버튼으로 날아가 모두 함께 들어간다(사용자 요청 2026-10-22: 손님마다 창이 따로 뜨지 않게).
## presentation_only 모드에서는 중앙 대화창의 인물·대사 표현만 담당한다.
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const Extension := preload("res://scripts/ui/moon/moon_extension.gd")
const InkShader := preload("res://shaders/guest_ink_panel.tres")
const PortraitShader := preload("res://shaders/guest_portrait_motion.gdshader")  # 초상 아이들링·등장 가슴 모핑(docs/erin-portrait-motion.md)
const PortraitMotion := preload("res://scripts/ui/portrait_motion.gd")  # 손님별 아이들링 값(docs/portrait-motion-all.md)
const Session := preload("res://scripts/game/game_session.gd")
const MoonLayout := preload("res://scripts/ui/moon/moon_layout.gd")
const DESIGN_SIZE := Vector2(1200, 600)
const NOTICE_DURATION := 0.6
const PORTRAIT_RECT := Rect2(0, 0, 480, 600)
const PANEL_RECT := Rect2(70, 78, 1130, 500)
const TEXT_X := 524.0
const TEXT_WIDTH := 580.0
const TEXT_IN_TIME := 0.46     # 줄마다 올라오는 모션 시간(_animate_guest와 같은 값)
const PORTRAIT_IN_TIME := 0.69
const PORTRAIT_POP_FROM := 0.92   # 등장 스케일 트윈 시작 배율(하단 중앙 피벗, 사용자 요청 2026-10-22)
const PORTRAIT_POP_OVERSHOOT := 1.6  # ease-out-back 세기: 최종 배율을 약 1.5% 살짝 넘었다 돌아온다
## 대사는 펜으로 종이에 적듯 한 글자씩 드러나며 펜 긁는 소리가 난다(docs/dialogue-handwriting.md).
const Handwriting := preload("res://scripts/ui/handwriting.gd")
const HandwritingShader := preload("res://shaders/handwriting_reveal.gdshader")
const WRITE_DELAY := 0.94           # 대화창: 패널·이름이 자리 잡은 뒤 첫 글자를 쓰기 시작하는 시각
const WRITE_DELAY_COMPACT := 0.32   # 도착 소개
const WRITE_DELAY_UPDATE := 0.12    # 같은 인물의 다음 대사
const QUILL_EVENT := "quill_scratch"
const QUILL_ATTACK := 22.0          # 펜 압력 → 소리 크기 따라가는 속도(1/초)
const QUILL_RELEASE := 12.0
const READ_PAUSE := 1.5             # 다 적은 뒤 읽을 틈(다음 손님으로 넘어가거나 다 함께 날아가기 전)
const SWAP_TIME := 0.34             # 같은 창에서 다음 손님으로 넘어가기 전 앞 손님의 이름·대사를 걷어 내는 시간
const FLIGHT_TIME := 0.65
const FLIGHT_STAGGER := 0.11        # 다 함께 날아갈 때 손님 사이 출발 간격

signal introduction_finished
signal guest_admitted(profile: Dictionary)
var game
var presentation_only := false
var panel_extend := 0.0  # presentation_only: 패널(과 stage)을 오른쪽으로 넓힐 폭. 대화 선택지 열이 그 안에 들어간다(_ready 전에 설정)
var dialogue_font_size := 28
var text_width := TEXT_WIDTH
var portrait_home := PORTRAIT_RECT.position
var rule_home := Vector2(TEXT_X, 337)
var flight_time := 0.0
var flight_start := Vector2.ZERO
var flight_size := Vector2.ZERO
var last_landing := Vector2.ZERO
var flying_portrait: TextureRect
var flyers: Array[TextureRect] = []   # 함께 날아가는 초상들(flyers[0] == flying_portrait)
var flights: Array = []               # 초상별 비행 {center, size, delay, landed}
var outgoing: TextureRect             # 다음 손님 초상이 떠오르는 동안 같은 자리에서 옅어지는 앞 손님 초상
var panel_time := 0.0                 # 패널이 열린 뒤 시간. 같은 창에서 손님이 바뀌어도 패널은 다시 열리지 않는다
var active := false
var phase := "idle"
var profiles: Array = []
var guest_index := -1
var pending: Array = []
var clock := 0.0
var phase_time := 0.0
var guest_duration := 7.0
var ready_time := 0.0          # 이 시각(phase_time) 전에는 클릭으로 넘기지 않는다: 글이 다 나올 때까지 최소 표시
var hint: Label
var root: Control
var stage: Control
var notice: Control
var panel: ColorRect
var panel_material: ShaderMaterial
var shadow: ColorRect
var shadow_material: ShaderMaterial
var portrait: TextureRect
var portrait_base_scale := 1.0        # 대화창 배율(dialogue_portrait_scale). 등장 트윈이 끝나면 이 배율
var portrait_pivot_shift := Vector2.ZERO  # 하단 피벗으로 바꿔도 위쪽 기준 배율의 최종 모습과 같도록 옮기는 양
var portrait_material: ShaderMaterial  # 초상 모션 셰이더. 프로필에 portrait_motion 이 있을 때만 움직인다
var name_label: Label
var role_label: Label
var detail_label: Label
var count_label: Label
var dialogue_lines: Array[Label] = []
var rule: ColorRect
var progress: ColorRect
var chime: AudioStreamPlayer
var text_motion: Array = []
var _texture_cache: Dictionary = {}
var writing                        # Handwriting 타임라인(지금 대사)
var write_start := 0.0             # phase_time 기준 첫 획 시각
var quill: AudioStreamPlayer       # 펜 긁는 반복음. 압력에 따라 크기가 오르내린다
var quill_level := 0.0
var _quill_source: AudioStream

func _ready() -> void:
	name = "GuestArrival"
	layer = 20 if presentation_only else 8
	process_mode = Node.PROCESS_MODE_ALWAYS if presentation_only else Node.PROCESS_MODE_PAUSABLE
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.theme = MoonSkin.make_theme()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.visible = false
	add_child(root)
	stage = Control.new()
	stage.name = "FloatingGuest"
	stage.size = DESIGN_SIZE + Vector2(panel_extend, 0)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stage)
	_build_story()
	_build_hint()
	_build_notice()
	_build_chime()
	flying_portrait = _portrait_sprite(root)
	flyers.append(flying_portrait)
	get_viewport().size_changed.connect(_layout)
	if not presentation_only:
		game.economy.batch_arrived.connect(enqueue)
		game.session.state_changed.connect(_on_session_changed)
	_layout()

## 비행·줄서기에 쓰는 장식 없는 초상 조각.
func _portrait_sprite(parent: Control) -> TextureRect:
	var sprite := TextureRect.new()
	sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sprite.visible = false
	parent.add_child(sprite)
	return sprite

func _ink(at: Rect2, opacity: float) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = at.position
	rect.size = at.size
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = InkShader
	mat.set_shader_parameter("reveal", 0.0)
	mat.set_shader_parameter("opacity", opacity)
	rect.material = mat
	stage.add_child(rect)
	return rect

## 대사 줄: 올라오는 모션 대신 필기 셰이더가 펜 끝까지만 보여 준다.
func _dialogue_line(at: Rect2, pixels: int, color: Color) -> Label:
	var label := _text("", at, pixels, color, 0.0)
	text_motion.pop_back()
	label.position = Vector2.ZERO
	var mat := ShaderMaterial.new()
	mat.shader = HandwritingShader
	mat.set_shader_parameter("center_y", at.size.y * 0.5)
	mat.set_shader_parameter("reveal_x", -20.0)
	label.material = mat
	return label

func _text(text: String, at: Rect2, pixels: int, color: Color, delay: float, bold := false) -> Label:
	# 줄별 클리핑 + 위치/알파: 타자기 대신 정돈된 모션 그래픽으로 올라온다.
	var clip := Control.new()
	clip.position = at.position
	clip.size = at.size
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(clip)
	var label := Label.new()
	label.text = text
	label.size = at.size
	label.add_theme_font_override("font", MoonSkin.font(bold))
	label.add_theme_font_size_override("font_size", pixels)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip.add_child(label)
	text_motion.append({"label": label, "delay": delay, "travel": 18.0 if bold else 12.0})
	return label

func _build_story() -> void:
	if not presentation_only:
		_build_compact_story()
		return
	var panel_rect := Rect2(PANEL_RECT.position, PANEL_RECT.size + Vector2(panel_extend, 0))
	shadow = _ink(Rect2(panel_rect.position + Vector2(-9, 16), panel_rect.size + Vector2(14, 15)), 0.22)
	shadow_material = shadow.material
	panel = _ink(panel_rect, 0.985)
	panel.name = "LivingInkPanel"
	panel_material = panel.material
	portrait = TextureRect.new()
	portrait.name = "CutoutPortrait"
	portrait.position = PORTRAIT_RECT.position
	portrait.size = PORTRAIT_RECT.size
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 기본은 원본 알파 유지. 에린만 프로필에서 직선 밑단의 표시 마감을 지정한다.
	portrait_material = _portrait_motion_material()
	portrait.material = portrait_material
	stage.add_child(portrait)
	count_label = _text("", Rect2(TEXT_X, 119, TEXT_WIDTH, 32), 17, Color8(172, 156, 184), 0.26)
	name_label = _text("", Rect2(TEXT_X - 3, 164, TEXT_WIDTH, 76), 54, Color8(250, 230, 188), 0.4, true)
	role_label = _text("", Rect2(TEXT_X, 245, TEXT_WIDTH, 34), 23, Color8(167, 199, 194), 0.55)
	detail_label = _text("", Rect2(TEXT_X, 284, TEXT_WIDTH, 32), 19, Color8(177, 167, 186), 0.67)
	rule = ColorRect.new()
	rule.position = Vector2(TEXT_X, 337)
	rule.color = Color8(197, 165, 116, 160)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(rule)
	for i in 3:
		var label := _dialogue_line(Rect2(TEXT_X, 359 + i * 45, TEXT_WIDTH, 45), 28, Color8(236, 227, 216))
		label.name = "DialogueLine%d" % i
		dialogue_lines.append(label)
	progress = ColorRect.new()
	progress.position = Vector2(TEXT_X, 526)
	progress.color = Color8(179, 151, 120, 95)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(progress)

func _build_compact_story() -> void:
	stage.size = Vector2(1100, 380)
	text_width = 715.0
	dialogue_font_size = 33
	portrait_home = Vector2.ZERO
	rule_home = Vector2(328, 139)
	shadow = _ink(Rect2(89, 66, 1014, 320), 0.2)
	shadow_material = shadow.material
	panel = _ink(Rect2(100, 48, 1000, 325), 0.985)
	panel_material = panel.material
	portrait = TextureRect.new()
	portrait.name = "CutoutPortrait"
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.size = Vector2(304, 380)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 도착 초상도 대화창과 동일한 원본 알파를 그대로 표시한다.
	portrait_material = _portrait_motion_material()
	portrait.material = portrait_material
	stage.add_child(portrait)
	count_label = _text("", Rect2(866, 88, 180, 27), 17, MoonSkin.LAVENDER, 0.12)
	name_label = _text("", Rect2(326, 70, 210, 62), 41, MoonSkin.CREAM, 0.12, true)
	role_label = _text("", Rect2(540, 87, 320, 35), 25, Color8(170, 202, 196), 0.2)
	detail_label = _text("", Rect2(0, 0, 0, 0), 18, MoonSkin.LAVENDER, 0.2)
	detail_label.get_parent().visible = false
	rule = ColorRect.new()
	rule.position = rule_home
	rule.color = Color8(197, 165, 116, 130)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(rule)
	for i in 3:
		var label := _dialogue_line(Rect2(328, 156 + i * 47, text_width, 47), dialogue_font_size, Color8(244, 235, 221))
		dialogue_lines.append(label)
	progress = ColorRect.new()
	progress.position = Vector2(328, 324)
	progress.color = Color8(179, 151, 120, 90)
	progress.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(progress)

## 글이 다 나온 뒤 패널 오른쪽 아래에 뜨는 안내.
func _build_hint() -> void:
	hint = Label.new()
	hint.text = "클릭하여 계속 ▸"
	hint.size = Vector2(220, 32)
	hint.position = panel.position + panel.size - Vector2(hint.size.x + 30, hint.size.y + 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint.add_theme_font_override("font", MoonSkin.font(true))
	hint.add_theme_font_size_override("font_size", 21)
	hint.add_theme_color_override("font_color", MoonSkin.LAVENDER)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint.modulate.a = 0.0
	hint.visible = not presentation_only
	stage.add_child(hint)


func _build_notice() -> void:
	notice = Control.new()
	notice.size = Vector2(680, 58)
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(notice)
	var back := Panel.new()
	back.size = notice.size
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_theme_stylebox_override("panel", Extension.toast())
	notice.add_child(back)
	var footsteps := Extension.icon("footsteps", 32)
	footsteps.position = Vector2(15, 12)
	footsteps.size = Vector2(32, 32)
	notice.add_child(footsteps)
	var label := Label.new()
	label.name = "Count"
	label.position = Vector2(16, 0)
	label.size = Vector2(648, 58)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", MoonSkin.CREAM)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.add_child(label)

func _layout() -> void:
	var view := get_viewport().get_visible_rect().size
	var s := minf(view.x / 2540.0, view.y / 1150.0) if presentation_only else minf(view.x / 3400.0, view.y / 1600.0)
	stage.scale = Vector2.ONE * s
	if presentation_only:
		stage.position = Vector2(view.x * 0.5, view.y * 0.48) - stage.size * s * 0.5
	else:
		var hud_scale := MoonLayout.ui_scale(view)
		var hand_bottom := MoonLayout.to_view(Vector2(800, game.hud.card_hand.CARD_BOTTOM), Vector2(0.5, 1), view).y
		var hand_top: float = hand_bottom - game.hud.card_hand.CARD_DESIGN.y * hud_scale
		stage.position = Vector2((view.x - stage.size.x * s) * 0.5, hand_top - 14.0 * hud_scale - stage.size.y * s)
	notice.scale = Vector2.ONE * s
	notice.position = Vector2((view.x - notice.size.x * s) * 0.5, stage.position.y + 80.0 * s)

func enqueue(arriving: Array) -> void:
	if OS.get_cmdline_user_args().has("--guest-intros=off"): return
	if arriving.is_empty() or game.session.is_over(): return
	if active and phase in ["notice", "guest", "swap"]:
		# 소개 중에 또 온 손님은 새 창을 띄우지 않고 지금 창의 차례 뒤에 잇는다
		profiles.append_array(arriving.duplicate(true))
		if phase == "notice": notice.get_node("Count").text = "✧  손님 %d명이 산장을 찾아옵니다" % profiles.size()
		else: count_label.text = "손님 %d / %d" % [guest_index + 1, profiles.size()]
		return
	pending.append(arriving.duplicate(true))
	if not active: _begin_next()

func _begin_next() -> void:
	profiles = pending.pop_front()
	guest_index = -1
	_clear_outgoing()
	active = true
	phase = "notice"
	phase_time = 0.0
	root.visible = true
	stage.visible = false
	notice.visible = true
	notice.modulate.a = 0.0
	notice.get_node("Count").text = "✧  손님 %d명이 산장을 찾아옵니다" % profiles.size()
	if profiles.size() == 1 and profiles[0].get("merchant", false):
		notice.get_node("Count").text = "✧  떠돌이 행상이 좌판을 지고 찾아옵니다"
	# 선택된 도착음이 있으면 그것을, 없으면 예전 합성 차임을 쓴다
	if game != null and game.sounds != null and game.sounds.streams.has("guest_arrive"):
		game.sounds.play("guest_arrive")
	else:
		chime.play()

func _show_guest() -> void:
	guest_index += 1
	_clear_outgoing()
	if guest_index > 0 and portrait.visible:
		# 앞 손님 초상을 그 자리 그대로 복제해 두고, 새 초상이 떠오르는 만큼 옅게 만든다(교차 전환)
		outgoing = portrait.duplicate() as TextureRect
		outgoing.name = "OutgoingPortrait"
		outgoing.material = portrait_material.duplicate()
		stage.add_child(outgoing)
		stage.move_child(outgoing, portrait.get_index())
	if game != null and game.sounds != null:
		game.sounds.play("guest_card")
	phase = "guest"
	phase_time = 0.0
	notice.visible = false
	stage.visible = true
	stage.modulate.a = 1.0
	portrait.visible = true
	flying_portrait.visible = false
	# 패널은 첫 손님에서만 열린다. 다음 손님은 같은 창에서 초상·글만 새로 들어온다.
	if guest_index == 0: panel_time = 0.0
	for line in dialogue_lines: line.modulate.a = 1.0
	var profile: Dictionary = profiles[guest_index]
	# 도착 카드에 첫인사가 뜰 때 그 인물의 목소리
	if game != null and game.sounds != null:
		game.sounds.voice(profile)
	var path: String = profile["portrait"]
	if not _texture_cache.has(path): _texture_cache[path] = load(path)
	portrait.texture = _texture_cache[path]
	_apply_portrait_motion(profile)
	# 원본 PNG를 리샘플링하지 않고 대화창에서만 균등 확대한다. 인물 교체 시 기본 배율로 복구.
	var portrait_scale := float(profile.get("dialogue_portrait_scale", 1.0)) if presentation_only else 1.0
	# 등장 스케일 트윈은 발끝(하단 중앙)을 축으로 한다. 최종 모습은 위쪽 기준 배율과 같게: 위치를 H·(배율−1) 만큼 내려 보정.
	portrait_base_scale = portrait_scale
	portrait.pivot_offset = Vector2(portrait.size.x * 0.5, portrait.size.y)
	portrait_pivot_shift = Vector2(0.0, portrait.size.y * (portrait_scale - 1.0))
	portrait.scale = Vector2.ONE * portrait_scale * PORTRAIT_POP_FROM
	portrait_material.set_shader_parameter("rounded_hem", presentation_only and bool(profile.get("dialogue_portrait_rounded_hem", false)))
	name_label.text = profile["person"]
	# 종족은 직업과 별개의 축(docs/races-guests-v01.md): "종족 · 역할"로 적고 종족 보조색을 입힌다.
	var race_name: String = str(profile.get("race_name", ""))
	role_label.text = ("%s · %s" % [race_name, profile["role"]]) if race_name != "" else str(profile["role"])
	role_label.modulate = profile.get("race_accent", Color.WHITE)
	# 포트레이트 미납품 인물은 익명 실루엣을 종족색으로 옅게 물들여 구분한다.
	portrait.modulate = (Color(profile.get("race_accent", Color.WHITE), 1.0).lerp(Color.WHITE, 0.35)) if profile.get("portrait_missing", false) else Color.WHITE
	detail_label.text = profile["detail"]
	count_label.text = ("산장의 이야기" if presentation_only else "손님 %d / %d" % [guest_index + 1, profiles.size()])
	update_dialogue(profile["line"])
	write_start = WRITE_DELAY if presentation_only else WRITE_DELAY_COMPACT
	ready_time = PORTRAIT_IN_TIME
	for entry in text_motion:
		ready_time = maxf(ready_time, float(entry["delay"]) + TEXT_IN_TIME)
	# 도착 소개는 다 적고 나서 읽을 틈(1.6초 이상)을 두고 산장으로 날아간다
	guest_duration = 99999.0 if presentation_only else maxf(0.6 + clampf(str(profile["line"]).replace("\n", "").length() / 12.0 + 1.0, 2.8, 4.4), write_start + writing.total + READ_PAUSE)
	_animate_guest()
	_layout()

func show_profile(profile: Dictionary, text: String, title: String = "산장의 이야기") -> void:
	profiles = [profile.duplicate(true)]
	profiles[0]["line"] = text
	guest_index = -1
	active = true
	root.visible = true
	_show_guest()
	count_label.text = title

## 대화 중 말하는 사람을 바꾼다(연작의 끼어들기, guest_story_arcs.gd). 패널은 그대로 두고 초상·이름·글만 교차 전환한다.
func swap_speaker(profile: Dictionary, text: String, title: String) -> void:
	var next := profile.duplicate(true)
	next["line"] = text
	profiles.append(next)
	_show_guest()
	count_label.text = title

## 대사 글색(마녀의 생각·장면 묘사는 괄호 글에 옅은 색을 입힌다). 알파는 등장 연출 것을 그대로 둔다.
func set_dialogue_tint(color: Color) -> void:
	for line in dialogue_lines:
		line.modulate = Color(color.r, color.g, color.b, line.modulate.a)

func update_dialogue(text: String) -> void:
	# 같은 인물과 대화하는 동안 초상·정보·패널의 등장 타임라인은 유지한다.
	# 대사 글은 새로 펜으로 적는다(_show_guest 는 첫 대사의 시작 시각을 패널 등장 뒤로 다시 잡는다).
	var lines := _wrap_dialogue(text)
	var shown: Array = []
	for i in dialogue_lines.size():
		dialogue_lines[i].text = lines[i] if i < lines.size() else ""
		shown.append(dialogue_lines[i].text)
	writing = Handwriting.build(shown, MoonSkin.font(), dialogue_font_size)
	write_start = phase_time + WRITE_DELAY_UPDATE
	_apply_writing()

## 지금 글을 적는 중인지(대화 '다음'·도착 클릭은 먼저 남은 글을 마저 적는다).
func is_writing() -> bool:
	return active and writing != null and writing.is_writing(phase_time - write_start)

## 남은 글을 한 번에 다 적는다(젖은 잉크도 바로 마름).
func finish_writing() -> void:
	if writing == null: return
	write_start = phase_time - writing.total - 1.0
	_apply_writing()

func _apply_writing() -> void:
	if writing == null: return
	var t := phase_time - write_start
	for i in dialogue_lines.size():
		var mat := dialogue_lines[i].material as ShaderMaterial
		mat.set_shader_parameter("reveal_x", writing.reveal_at(i, t))
		mat.set_shader_parameter("wet_amount", 0.85 * writing.wetness(i, t))

## 펜 긁는 소리: selected.json 의 quill_scratch 를 반복 재생하고, 획 압력을 빠르게 따라 크기를 올리고 내린다.
## 띄어쓰기·문장부호 쉼에서는 펜을 들어 조용해진다. 소리 파일이 없으면 글만 적힌다.
func _step_quill(delta: float) -> void:
	var t := phase_time - write_start
	var target: float = writing.pen_at(t) if active and phase == "guest" and writing != null else 0.0
	quill_level = move_toward(quill_level, target, delta * (QUILL_ATTACK if target > quill_level else QUILL_RELEASE))
	if quill_level <= 0.001:
		if quill != null and quill.playing: quill.stop()
		return
	if quill == null:
		if game == null or game.sounds == null or not game.sounds.streams.has(QUILL_EVENT): return
		quill = AudioStreamPlayer.new()
		quill.name = "QuillScratch"
		quill.bus = "Sfx"
		add_child(quill)
	var source: AudioStream = game.sounds.streams[QUILL_EVENT][0]
	if source != _quill_source:
		_quill_source = source
		var stream: AudioStream = source.duplicate()
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_begin = 0
			stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		elif stream is AudioStreamMP3:
			stream.loop = true
		quill.stream = stream
	if not quill.playing:
		# 반복 지점이 매번 같은 데서 시작하지 않게
		quill.play(randf() * quill.stream.get_length())
		quill.pitch_scale = randf_range(0.94, 1.08)
	quill.volume_db = float(game.sounds.gains.get(QUILL_EVENT, -14.0)) + linear_to_db(quill_level)

func _wrap_dialogue(text: String) -> Array[String]:
	var lines: Array[String] = []
	var font: Font = MoonSkin.font()
	for paragraph in text.split("\n"):
		var line := ""
		for word in paragraph.split(" ", false):
			var candidate: String = word if line.is_empty() else line + " " + word
			if not line.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, dialogue_font_size).x > text_width - 4.0:
				lines.append(line.strip_edges())
				line = ""
			# 보통은 단어 사이에서 줄바꿈. 패널보다 긴 단어만 글자 단위로 나눈다.
			if not line.is_empty(): line += " "
			for character in word:
				if font.get_string_size(line + character, HORIZONTAL_ALIGNMENT_LEFT, -1, dialogue_font_size).x > text_width - 4.0:
					lines.append(line.strip_edges())
					line = ""
				line += character
		if not line.is_empty(): lines.append(line.strip_edges())
	return lines

## 끝에서 목표를 살짝 넘었다 돌아오는 이징(초상 등장 스케일).
func ease_out_back(value: float) -> float:
	var t := clampf(value, 0.0, 1.0) - 1.0
	return 1.0 + (PORTRAIT_POP_OVERSHOOT + 1.0) * t * t * t + PORTRAIT_POP_OVERSHOOT * t * t


func ease_out(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return 1.0 - pow(1.0 - t, 3.0)

func _animate_guest() -> void:
	var enter := ease_out(panel_time / (0.55 if presentation_only else 0.3))
	var leave := 1.0
	panel_material.set_shader_parameter("motion_time", clock)
	shadow_material.set_shader_parameter("motion_time", clock)
	panel_material.set_shader_parameter("reveal", enter)
	shadow_material.set_shader_parameter("reveal", enter)
	panel_material.set_shader_parameter("opacity", 0.985 * leave)
	shadow_material.set_shader_parameter("opacity", 0.22 * leave)
	var portrait_k := ease_out((phase_time - 0.06) / 0.63)
	portrait.modulate.a = portrait_k * leave
	# 초상은 셰이더로 몸이 직접 숨쉬므로 통째로 위아래로 떠다니는 움직임은 없다(사용자 요청 2026-10-22 에린, 2026-10-23 전원).
	# 발끝을 축으로 살짝 작게 시작해 커지며 자리 잡는다(세로 미끄럼 대신 스케일, 가슴 모핑 진동과 같은 순간에 시작)
	if outgoing != null:
		# 다음 손님: 같은 자리에서 앞 손님 초상과 교차 전환만 한다(커지기·옆 미끄럼 없음)
		portrait.scale = Vector2.ONE * portrait_base_scale
		portrait.position = portrait_home + portrait_pivot_shift
		outgoing.modulate.a = 1.0 - portrait_k
		(outgoing.material as ShaderMaterial).set_shader_parameter("motion_time", clock)
		if portrait_k >= 1.0: _clear_outgoing()
	else:
		portrait.scale = Vector2.ONE * portrait_base_scale * lerpf(PORTRAIT_POP_FROM, 1.0, ease_out_back((phase_time - 0.06) / 0.63))
		portrait.position = portrait_home + portrait_pivot_shift + Vector2(-22.0 * (1.0 - portrait_k), 0.0)
	# 초상 셰이더: 아이들링 시계와, 초상이 나타나기 시작한 순간(0.06초)부터 센 등장 시간(가슴 모핑 진동)
	portrait_material.set_shader_parameter("motion_time", clock)
	portrait_material.set_shader_parameter("appear", phase_time - 0.06)
	for entry in text_motion:
		var k := ease_out((phase_time - float(entry["delay"])) / TEXT_IN_TIME)
		var label: Label = entry["label"]
		label.modulate.a = k * leave
		label.position = Vector2(0, float(entry["travel"]) * (1.0 - k) - 4.0 * (1.0 - leave))
	_apply_writing()
	rule.size = Vector2(76.0 * ease_out((phase_time - 0.22) / 0.35), 1.0)
	rule.modulate.a = leave
	progress.size = Vector2(54.0 * clampf(1.0 - phase_time / guest_duration, 0.0, 1.0), 1.0)
	progress.modulate.a = ease_out((phase_time - 1.4) / 0.5) * leave
	if hint != null and hint.visible:
		var hint_at := ready_time if writing == null else maxf(ready_time, write_start + writing.total)
		hint.modulate.a = ease_out((phase_time - hint_at) / 0.25) * (0.75 + 0.25 * sin(clock * 4.0)) * leave

## 초상 아이들링·등장 가슴 모핑 셰이더 재질. 기본은 정지(idle 0·chest 0)라 모션 정보가 없는 손님은 이전과 똑같이 보인다.
func _portrait_motion_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = PortraitShader
	mat.set_shader_parameter("idle_amount", 0.0)
	mat.set_shader_parameter("chest_amount", 0.0)
	mat.set_shader_parameter("appear", -1.0)
	return mat


## 손님의 모션 값(PortraitMotion.for_profile: 에린은 프로필 portrait_motion, 나머지는 종족·개인 성격표)을 셰이더에 싣는다.
## 재질을 손님끼리 같이 쓰므로 먼저 기본값으로 되돌려 앞 손님 값이 남지 않게 한다.
func _apply_portrait_motion(profile: Dictionary) -> void:
	if portrait_material == null: return
	var m: Dictionary = PortraitMotion.DEFAULTS.duplicate()
	m.merge(PortraitMotion.for_profile(profile), true)
	for k in m:
		var uniform: String = {"idle": "idle_amount", "chest": "chest_amount"}.get(k, k)
		portrait_material.set_shader_parameter(uniform, m[k])
	portrait_material.set_shader_parameter("appear", -1.0)


func _process(delta: float) -> void:
	if not active:
		if quill_level > 0.0: _step_quill(delta)
		return
	clock += delta
	phase_time += delta
	panel_time += delta
	_step_quill(delta)
	if phase == "notice":
		notice.modulate.a = ease_out(phase_time / 0.12) * (1.0 - smoothstep(0.42, NOTICE_DURATION, phase_time))
		if phase_time >= NOTICE_DURATION: _show_guest()
	elif phase == "guest":
		_animate_guest()
		if not presentation_only and phase_time >= guest_duration: _advance()
	elif phase == "swap":
		_animate_swap()
	elif phase == "flight":
		_animate_flight(delta)

## 손님 소개 패널을 클릭하면 다음 동작(산장으로 날아감)으로 바로 넘어간다.
## 글이 다 나오기 전(ready_time 전)의 클릭은 넘기지 않지만, 패널 위 클릭이 월드로 새지 않도록 소비한다.
func _input(event: InputEvent) -> void:
	if presentation_only or not active or not phase in ["guest", "swap"]:
		return
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if not _panel_hit(mb.position):
		return
	get_viewport().set_input_as_handled()
	if phase == "swap":
		return
	if is_writing():
		# 적는 중의 클릭은 남은 글을 마저 적고, 읽을 틈을 둔 뒤 날아간다
		finish_writing()
		guest_duration = minf(guest_duration, phase_time + READ_PAUSE)
	elif phase_time >= ready_time:
		_advance()


func _panel_hit(p: Vector2) -> bool:
	for c: Control in [panel, portrait]:
		if (c.get_global_transform() * Rect2(Vector2.ZERO, c.size)).has_point(p):
			return true
	return false


## 다 읽은 손님 다음: 남은 손님이 있으면 같은 창에서 교체, 마지막이면 다 함께 날아간다.
func _advance() -> void:
	if guest_index + 1 < profiles.size(): _start_swap()
	else: _start_flight()


## 앞 손님 초상은 자리에 그대로 둔 채 이름·대사만 걷어 낸다. 초상은 다음 손님이 나올 때 교차 전환된다.
func _start_swap() -> void:
	phase = "swap"
	phase_time = 0.0


func _animate_swap() -> void:
	var k := ease_out(phase_time / SWAP_TIME)
	# 패널은 그대로 두고 앞 손님의 이름·대사만 걷어 낸다
	panel_material.set_shader_parameter("motion_time", clock)
	shadow_material.set_shader_parameter("motion_time", clock)
	portrait_material.set_shader_parameter("motion_time", clock)
	var fade := 1.0 - smoothstep(0.0, 0.7, k)
	for entry in text_motion: entry["label"].modulate.a = fade
	for line in dialogue_lines: line.modulate.a = fade
	rule.modulate.a = fade
	progress.modulate.a = 0.0
	if hint != null: hint.modulate.a = 0.0
	if phase_time >= SWAP_TIME: _show_guest()


func _clear_outgoing() -> void:
	if outgoing != null: outgoing.queue_free()
	outgoing = null


## 마지막 손님 초상 하나가 관리 버튼으로 날아가고, 내려앉을 때 이번에 온 손님 모두가 함께 들어간다.
func _start_flight() -> void:
	phase = "flight"
	flight_time = 0.0
	_clear_outgoing()
	var starts: Array = [{"rect": portrait.get_global_rect(), "texture": portrait.texture, "tint": portrait.modulate}]
	portrait.visible = false
	while flyers.size() < starts.size(): flyers.append(_portrait_sprite(root))
	flights.clear()
	for i in starts.size():
		var rect: Rect2 = starts[i]["rect"]
		var fly := flyers[i]
		fly.texture = starts[i]["texture"]
		fly.size = rect.size
		fly.position = rect.position
		fly.modulate = Color(starts[i]["tint"], 1.0)
		fly.visible = true
		flights.append({"center": rect.get_center(), "size": rect.size, "delay": FLIGHT_STAGGER * i, "landed": false})
	flight_start = flights[0]["center"]
	flight_size = flights[0]["size"]

func _animate_flight(delta: float) -> void:
	flight_time += delta
	var target: Vector2 = game.hud.moon.lodge_btn.get_global_rect().get_center()
	var landed_all := true
	for i in flights.size():
		var f: Dictionary = flights[i]
		if f["landed"]: continue
		var fly := flyers[i]
		var t := clampf((flight_time - float(f["delay"])) / FLIGHT_TIME, 0.0, 1.0)
		var start: Vector2 = f["center"]
		var middle := start.lerp(target, 0.55) + Vector2(0, -70.0)
		var k := t * t
		var center := start.lerp(middle, k).lerp(middle.lerp(target, k), k)
		fly.size = (f["size"] as Vector2).lerp(Vector2(14, 18), k)
		fly.position = center - fly.size * 0.5
		fly.modulate.a = 1.0 - smoothstep(0.85, 1.0, t)
		if t >= 1.0:
			f["landed"] = true
			fly.visible = false
			last_landing = target
			if game != null and game.sounds != null:
				game.sounds.play("guest_enter")
			for profile in profiles: guest_admitted.emit(profile)
		else:
			landed_all = false
	var fade := 1.0 - smoothstep(0.0, 0.2, flight_time)
	stage.modulate.a = fade
	panel_material.set_shader_parameter("opacity", 0.985 * fade)
	shadow_material.set_shader_parameter("opacity", 0.22 * fade)
	if landed_all: finish()

func finish() -> void:
	if not active: return
	active = false
	phase = "idle"
	root.visible = false
	for fly in flyers: fly.visible = false
	_clear_outgoing()
	introduction_finished.emit()
	if not pending.is_empty(): _begin_next()

func _on_session_changed(state: int) -> void:
	if state != Session.State.PREP:
		pending.clear()
		finish()

func _build_chime() -> void:
	var data := PackedByteArray()
	var rate := 22050
	var samples := int(rate * 1.3)
	data.resize(samples * 2)
	for i in samples:
		var t := float(i) / rate
		var value := (sin(TAU * 659.25 * t) + 0.42 * sin(TAU * 1320.0 * t) + 0.18 * sin(TAU * 1840.0 * t))
		value *= exp(-t * 4.7) * minf(t * 150.0, 1.0) * 0.23
		data.encode_s16(i * 2, int(clampf(value, -1.0, 1.0) * 32767.0))
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = rate
	sound.data = data
	chime = AudioStreamPlayer.new()
	chime.stream = sound
	chime.volume_db = -16.0
	chime.bus = "Sfx"
	add_child(chime)

