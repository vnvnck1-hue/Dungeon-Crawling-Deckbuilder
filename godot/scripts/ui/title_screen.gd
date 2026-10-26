extends Control
## 타이틀(로비) 화면(main_scene, 첫 실행 플로우 보강 — 사용자 결정 2026-10-17): 이어하기 · 새로운 이야기 · 기록 보관소 · 설정 · 나가기.
## 화면은 로비 컨셉 원화(art/concepts/lobby/races-closeup-distant-v02, 사용자 선택 2026-10-24)를 그대로 재현한다. docs/lobby.md
## 원화를 Codex가 나눈 레이어(assets/ui/lobby/)로 1920×1080 무대에 겹치고, 무대를 화면에 꽉 차게 키운다.
## 배경(정지) → 일곱 인물(shaders/lobby_idle.gdshader 로 천천히 숨·고개·날개 아이들링) → 타이틀 로고 → 메뉴 글자.
## 메뉴 글자도 원화 픽셀 그림이고, 마우스·키보드로 고른 줄로 금색 초승달과 밑줄이 옮겨 가며 그 줄이 원화의 「이어하기」만큼 커진다.
## 영어(F8)이거나 레이어가 없으면 같은 자리에 게임이 글자를 그린다.
## '새로운 이야기' 다음은 네 마녀 선택(지금은 이름 없는 '마녀' 한 칸만 고를 수 있고 셋은 '?'로 잠김, 방위 미정) → 게임(main.tscn, 도입 연출).
## 이어하기(저장)·기록 보관소는 아직 없어 누르면 안내만 띄운다. 설정은 HUD의 소리 설정 부품을 그대로 빌려 쓴다.
## 인자: -- --skip-title(또는 스크린샷 인자 --shot=…) 이면 곧장 게임으로 들어간다(기존 실행 방식 호환).

const Flow := preload("res://scripts/game/flow.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const SoundBankScript := preload("res://scripts/audio/sound_bank.gd")
const WindowMode := preload("res://scripts/visual/window_mode.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const ShotScript := preload("res://scripts/tools/screenshot_runner.gd")
const LobbyRig := preload("res://scripts/ui/lobby_rig.gd")

const ART_DIR := "res://assets/ui/ftue/"
const LOBBY_DIR := "res://assets/ui/lobby/"
const CANVAS := Vector2(1920, 1080)
## 넓은 화면용 왼쪽 확장(Codex 납품 lobby_*_wide.png, 2640×1080): 원화를 x=720 에 두고 왼쪽을 이어 그렸다(docs/handoff/codex-lobby-wide-v01.md)
const WIDE_EXT := 720.0
const INK := Color8(62, 34, 52)              # 원화 메뉴 글자의 자두빛 먹색(게임이 글자를 그릴 때)
## 메뉴 줄: [이름(그림 파일 lobby_menu_<이름>.png), 글자, 레이어가 없을 때 원화 좌표의 글자 상자]
const MENU := [
	["continue", "이어하기", Rect2(1512, 574, 160, 46)],
	["new", "새로운 이야기", Rect2(1512, 670, 200, 38)],
	["archive", "기록 보관소", Rect2(1512, 750, 176, 38)],
	["settings", "설정", Rect2(1512, 830, 66, 38)],
]
const EXIT_RECT := Rect2(1782, 986, 78, 32)
const MOON_RECT := Rect2(1450, 574, 46, 46)        # 「이어하기」 왼쪽 초승달
const UNDERLINE_RECT := Rect2(1510, 624, 252, 14)  # 「이어하기」 아래 밑줄
const HIGHLIGHT_TIME := 0.32
## [id, 이름, 설명, 선택 가능]
const WITCHES := [
	["witch", "마녀", "숲속 산장을 지키는 마녀.\n방위는 아직 모른다.", true],
	["locked_1", "?", "아직 만나지 못한 마녀", false],
	["locked_2", "?", "아직 만나지 못한 마녀", false],
	["locked_3", "?", "아직 만나지 못한 마녀", false],
]

var sounds              # HUD 설정 부품이 game.sounds 로 쓴다
var display             # 디스플레이 설정(WindowMode). HUD 디스플레이 부품이 있으면 game.display 로 쓴다
var settings_parts      # 부품만 빌려 쓰는 HUD 인스턴스(트리에 넣지만 짓지 않는다)
var stage: Control      # 원화 좌표(1920×1080) 무대. 화면에 꽉 차게 키운다
var bg: Control
var characters: TextureRect
var character_mat: ShaderMaterial
var title_box: Control
var menu: Control
var new_btn: Button
var continue_btn: Button
var archive_btn: Button
var settings_btn: Button
var quit_btn: Button
var menu_buttons: Array = []    # 메뉴 4줄(이어하기·새로운 이야기·기록 보관소·설정)
var menu_art: Array = []        # 줄마다 원화 글자 그림(TextureRect) 또는 null
var menu_rects: Array = []      # 줄마다 원화 좌표의 글자 상자
var exit_art: TextureRect
var moon_mark: Control
var underline: Control
var notice: Label
var highlighted := 0
var layered := false            # 원화 레이어가 모두 있으면 true
var art_x := 0.0                # 무대 안에서 원화(타이틀·메뉴 좌표)가 시작하는 x. 넓은 레이어가 있으면 WIDE_EXT
var settings_panel: PanelContainer
var tutorial_toggle: CheckButton
var fullscreen_toggle: CheckButton
var select_panel: Control
var slot_buttons: Array = []
var start_btn: Button
var select_note: Label
var selected := -1
var music: AudioStreamPlayer
var _t := 0.0
var _locale := ""
var _hl_tween: Tween
var _notice_tween: Tween


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = MoonSkin.make_theme()
	preload("res://scripts/ui/moon/moon_skin.gd").install_web_font_fallback()
	get_tree().paused = false
	var user := OS.get_cmdline_user_args()
	if "--skip-title" in user or not ShotScript.parse_args().is_empty():
		get_tree().change_scene_to_file.call_deferred(Flow.GAME_SCENE)
		return
	sounds = SoundBankScript.new()
	add_child(sounds)
	display = WindowMode.new()
	display.name = "WindowMode"
	add_child(display)
	var card_language := preload("res://scripts/ui/card_language.gd").new()   # F8 카드 언어 한국어 ↔ English
	card_language.name = "CardLanguage"
	add_child(card_language)
	var card_feel := preload("res://scripts/ui/card_feel.gd").new()   # F9 카드 질감 기존(일렁임) → 단단하게 → 아주 단단하게
	card_feel.name = "CardFeel"
	add_child(card_feel)
	settings_parts = HudScript.new()
	settings_parts.game = self
	add_child(settings_parts)
	layered = lobby_layers_ready()
	_build_stage()
	_build_background()
	_build_characters()
	_build_title()
	_build_menu()
	_build_settings()
	_build_select()
	resized.connect(_fit_stage)
	_fit_stage()
	_apply_language()
	_start_music.call_deferred()
	continue_btn.grab_focus.call_deferred()


static func lobby_layers_ready() -> bool:
	for f in ["lobby_bg", "lobby_characters", "lobby_title", "lobby_menu_continue", "lobby_menu_new", "lobby_menu_archive",
			"lobby_menu_settings", "lobby_menu_exit", "lobby_menu_moon", "lobby_menu_underline"]:
		if not ResourceLoader.exists(LOBBY_DIR + f + ".png"):
			return false
	return true


# ───────────────────────── 무대·배경·인물 ─────────────────────────

static func wide_layers_ready() -> bool:
	for f in ["lobby_bg_wide", "lobby_characters_wide"]:
		if not ResourceLoader.exists(LOBBY_DIR + f + ".png"):
			return false
	return true


func _build_stage() -> void:
	stage = Control.new()
	stage.name = "LobbyStage"
	art_x = WIDE_EXT if layered and wide_layers_ready() else 0.0
	stage.size = Vector2(art_x + CANVAS.x, CANVAS.y)
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stage)


## 무대를 화면 높이에 꼭 맞춰(위아래를 자르지 않음, 사용자 요청 2026-10-24) 메뉴가 있는 오른쪽 끝에 붙인다.
## 화면이 16:9보다 넓으면 원화 왼쪽의 확장 그림이 드러나고, 좁으면 왼쪽 인물이 조금 잘린다.
## 확장까지 다 보이고도 남을 만큼 넓으면(약 2.44:1 초과) 그때만 가로에 맞추고 위아래를 가운데 기준으로 조금 자른다.
func _fit_stage() -> void:
	var vp := size if size.x > 0.0 else get_viewport_rect().size
	var s := vp.y / CANVAS.y
	if stage.size.x * s < vp.x:
		s = vp.x / stage.size.x
	stage.scale = Vector2(s, s)
	stage.position = Vector2(vp.x - stage.size.x * s, (vp.y - CANVAS.y * s) * 0.5)
	# 나가기(원화 y≈1018)가 잘리지 않게
	var exit_bottom := (EXIT_RECT.end.y + 24.0) * s + stage.position.y
	if exit_bottom > vp.y:
		stage.position.y -= exit_bottom - vp.y


func _layer(path: String, node_name: String) -> TextureRect:
	var tr := TextureRect.new()
	tr.name = node_name
	tr.texture = load(path)
	tr.size = CANVAS if tr.texture == null else tr.texture.get_size()
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return tr


func _build_background() -> void:
	if layered:
		bg = _layer(LOBBY_DIR + ("lobby_bg_wide.png" if art_x > 0.0 else "lobby_bg.png"), "Background")
	elif ResourceLoader.exists(ART_DIR + "title_bg.png"):
		bg = _layer(ART_DIR + "title_bg.png", "Background")
		(bg as TextureRect).stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.size = stage.size
	else:
		bg = NightLodge.new()   # 플레이스홀더: 밤의 산장 실루엣
		bg.name = "Background"
		bg.size = stage.size
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(bg)


func _build_characters() -> void:
	if not layered:
		return
	characters = _layer(LOBBY_DIR + ("lobby_characters_wide.png" if art_x > 0.0 else "lobby_characters.png"), "Characters")
	if LobbyRig.weights_ready():
		character_mat = ShaderMaterial.new()
		character_mat.shader = preload("res://shaders/lobby_idle.gdshader")
		LobbyRig.apply(character_mat, Vector2(art_x, 0.0), characters.size)
		characters.material = character_mat
	stage.add_child(characters)


func _process(delta: float) -> void:
	_t += delta
	if character_mat != null:
		character_mat.set_shader_parameter("motion_time", _t)
	if bg is NightLodge:
		bg.t = _t
		bg.queue_redraw()
	var loc := TranslationServer.get_locale()
	if loc != _locale:
		_apply_language()


func _start_music() -> void:
	var list = sounds.streams.get("bgm_evening", sounds.streams.get("bgm_field", []))
	if list.is_empty():
		return
	music = AudioStreamPlayer.new()
	music.name = "TitleMusic"
	var stream: AudioStream = list[0]
	if "loop" in stream:   # 로비 음악은 계속 되풀이한다(사용자 요청 2026-10-24). 공유 리소스라 사본에만 켠다
		stream = stream.duplicate()
		stream.loop = true
	music.stream = stream
	music.bus = SoundBankScript.MUSIC_BUS
	music.volume_db = float(sounds.gains.get("bgm_evening", -10.0))
	add_child(music)
	if not ("loop" in stream):
		music.finished.connect(music.play)   # loop 속성이 없는 형식이면 끝나면 다시 튼다
	music.play()


# ───────────────────────── 제목·메뉴 ─────────────────────────

func _build_title() -> void:
	if layered:
		title_box = _layer(LOBBY_DIR + "lobby_title.png", "TitleBox")
	else:
		var t := Label.new()
		t.name = "TitleBox"
		t.text = "마녀산장"
		t.position = Vector2(1290, 250)
		t.size = Vector2(600, 220)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_override("font", MoonSkin.font(true))
		t.add_theme_font_size_override("font_size", 140)
		t.add_theme_color_override("font_color", INK)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_box = t
	title_box.position.x += art_x
	stage.add_child(title_box)


## 원화 글자 그림을 불투명 영역만 잘라 그 자리에 둔다. 반환: [TextureRect, 원화 좌표 상자]
func _cut(file: String, fallback: Rect2) -> Array:
	if not layered:
		return [null, fallback]
	var tex: Texture2D = load(LOBBY_DIR + file + ".png")
	var used := Rect2(tex.get_image().get_used_rect())
	if used.size.x < 2.0:
		used = fallback
	var at := AtlasTexture.new()
	at.atlas = tex
	at.region = used
	var tr := TextureRect.new()
	tr.name = file
	tr.texture = at
	tr.position = used.position
	tr.size = used.size
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return [tr, used]


func _build_menu() -> void:
	menu = Control.new()
	menu.name = "Menu"
	menu.size = CANVAS
	menu.position.x = art_x
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(menu)
	var moon := _cut("lobby_menu_moon", MOON_RECT)
	var line := _cut("lobby_menu_underline", UNDERLINE_RECT)
	moon_mark = moon[0] if moon[0] != null else _mark_moon()
	underline = line[0] if line[0] != null else _mark_line()
	moon_mark.set_meta("home", moon[1])
	underline.set_meta("home", line[1])
	menu.add_child(underline)
	menu.add_child(moon_mark)
	var actions := [_on_continue, _open_select, _on_archive, _open_settings]
	for i in MENU.size():
		var cut := _cut("lobby_menu_" + MENU[i][0], MENU[i][2])
		menu_art.append(cut[0])
		menu_rects.append(cut[1])
		var b := _menu_button(MENU[i][1], cut[1], actions[i])
		b.name = "Menu_" + MENU[i][0]
		var idx := i
		b.mouse_entered.connect(func(): highlight(idx))
		b.focus_entered.connect(func(): highlight(idx))
		if cut[0] != null:
			menu.add_child(cut[0])
		menu.add_child(b)
		menu_buttons.append(b)
	continue_btn = menu_buttons[0]
	new_btn = menu_buttons[1]
	archive_btn = menu_buttons[2]
	settings_btn = menu_buttons[3]
	continue_btn.disabled = true   # 저장·이어하기는 아직 없다(누르면 안내)
	continue_btn.tooltip_text = "저장·이어하기는 아직 준비 중입니다"
	continue_btn.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			_on_continue())
	var ex := _cut("lobby_menu_exit", EXIT_RECT)
	exit_art = ex[0]
	if exit_art != null:
		exit_art.pivot_offset = ex[1].size * 0.5
		menu.add_child(exit_art)
	quit_btn = _menu_button("나가기", ex[1], func(): get_tree().quit())
	quit_btn.name = "Menu_exit"
	quit_btn.mouse_entered.connect(func(): _hover_exit(true))
	quit_btn.mouse_exited.connect(func(): _hover_exit(false))
	quit_btn.focus_entered.connect(func(): _hover_exit(true))
	quit_btn.focus_exited.connect(func(): _hover_exit(false))
	menu.add_child(quit_btn)
	notice = Label.new()
	notice.name = "Notice"
	notice.position = Vector2(1512, 900)
	notice.size = Vector2(380, 40)
	notice.add_theme_font_override("font", MoonSkin.font(false))
	notice.add_theme_font_size_override("font_size", 22)
	notice.add_theme_color_override("font_color", Color(INK, 0.85))
	notice.modulate.a = 0.0
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	menu.add_child(notice)
	highlight(0, true)


## 메뉴 한 줄: 원화 글자 상자 위에 투명한 버튼(글자는 그림이 보여 주고, 영어·그림 없음일 때만 버튼 글자를 보인다).
func _menu_button(text: String, rect: Rect2, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	var r := rect.grow_individual(16, 8, 24, 8)
	b.position = r.position
	b.size = r.size
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	var empty := StyleBoxEmpty.new()
	empty.content_margin_left = 16
	for st in ["normal", "hover", "pressed", "focus", "disabled", "hover_pressed"]:
		b.add_theme_stylebox_override(st, empty)
	b.add_theme_font_override("font", MoonSkin.font(true))
	b.add_theme_font_size_override("font_size", int(rect.size.y * 0.78))
	b.pressed.connect(cb)
	return b


## 고른 줄로 초승달·밑줄을 옮기고 그 줄을 원화 「이어하기」 크기로 키운다(나머지는 원화의 보통 줄 크기).
func highlight(i: int, instant := false) -> void:
	highlighted = i
	var base: Rect2 = menu_rects[0]
	var small_h: float = menu_rects[1].size.y
	var big := base.size.y / small_h       # 고른 줄 배율(원화에서 이어하기 ÷ 보통 줄)
	if _hl_tween != null:
		_hl_tween.kill()
		_hl_tween = null
	var dur := 0.0 if instant else HIGHLIGHT_TIME
	if dur > 0.0:
		_hl_tween = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for k in menu_rects.size():
		var r: Rect2 = menu_rects[k]
		var sc := 1.0
		if k == 0 and i != 0:
			sc = 1.0 / big
		elif k != 0 and k == i:
			sc = big
		var art: Control = menu_art[k] if menu_art[k] != null else menu_buttons[k]
		art.pivot_offset = Vector2(0.0, r.size.y * 0.5) if art == menu_art[k] else Vector2(16.0, art.size.y * 0.5)
		_tween_to(art, "scale", Vector2(sc, sc), dur)
	# 원화의 이어하기 기준 상대 위치를 그대로 고른 줄로 옮긴다(세로는 줄 가운데, 가로는 글자 왼쪽 끝 기준)
	var target: Rect2 = menu_rects[i]
	var dy := target.get_center().y - base.get_center().y
	var dx := target.position.x - base.position.x
	for m in [moon_mark, underline]:
		var home: Rect2 = m.get_meta("home")
		_tween_to(m, "position", home.position + Vector2(dx, dy), dur)


func _tween_to(n: Control, prop: String, value, dur: float) -> void:
	if dur <= 0.0:
		n.set(prop, value)
	else:
		_hl_tween.tween_property(n, prop, value, dur)


func _hover_exit(on: bool) -> void:
	var n: Control = exit_art if exit_art != null else quit_btn
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "scale", Vector2.ONE * (1.12 if on else 1.0), 0.2)
	tw.tween_property(n, "modulate", Color(1.15, 1.0, 0.85) if on else Color.WHITE, 0.2)


func _on_continue() -> void:
	show_notice("저장된 이야기가 아직 없습니다")


func _on_archive() -> void:
	show_notice("기록 보관소는 아직 준비 중입니다")


## 메뉴 아래에 잠깐 뜨는 안내(원화 글자와 같은 먹색).
func show_notice(text: String) -> void:
	notice.text = text
	if _notice_tween != null:
		_notice_tween.kill()
	_notice_tween = create_tween()
	_notice_tween.tween_property(notice, "modulate:a", 1.0, 0.18)
	_notice_tween.tween_interval(1.8)
	_notice_tween.tween_property(notice, "modulate:a", 0.0, 0.5)


## 그림이 없을 때 초승달·밑줄 대신 그리는 단순 도형.
func _mark_moon() -> Control:
	var c := ColorRect.new()
	c.color = Color8(196, 132, 52)
	c.size = Vector2(10, 10)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var home := MOON_RECT
	c.set_meta("home", Rect2(home.get_center() - Vector2(5, 5), Vector2(10, 10)))
	return c


func _mark_line() -> Control:
	var c := ColorRect.new()
	c.color = Color8(196, 132, 52)
	c.size = Vector2(UNDERLINE_RECT.size.x, 3)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## 한국어 + 레이어가 있으면 원화 글자 그림, 아니면(영어·레이어 없음) 같은 자리에 버튼 글자를 그린다.
func _apply_language() -> void:
	_locale = TranslationServer.get_locale()
	var use_art := layered and _locale.begins_with("ko")
	for k in menu_buttons.size():
		if menu_art[k] != null:
			menu_art[k].visible = use_art
		_set_button_ink(menu_buttons[k], not use_art)
	if exit_art != null:
		exit_art.visible = use_art
	_set_button_ink(quit_btn, not use_art)


func _set_button_ink(b: Button, show_text: bool) -> void:
	var c := INK if show_text else Color(0, 0, 0, 0)
	for k in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(k, c)
	b.add_theme_color_override("font_disabled_color", c)
	b.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0))


# ───────────────────────── 설정 ─────────────────────────

func _build_settings() -> void:
	settings_panel = PanelContainer.new()
	settings_panel.name = "Settings"
	settings_panel.add_theme_stylebox_override("panel", MoonSkin.modal_box())
	settings_panel.anchor_left = 0.5
	settings_panel.anchor_right = 0.5
	settings_panel.anchor_top = 0.5
	settings_panel.anchor_bottom = 0.5
	settings_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	settings_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	settings_panel.visible = false
	add_child(settings_panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 460
	v.add_theme_constant_override("separation", 10)
	settings_panel.add_child(v)
	var t := Label.new()
	t.text = "설정"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_override("font", MoonSkin.font(true))
	t.add_theme_font_size_override("font_size", 28)
	t.add_theme_color_override("font_color", MoonSkin.CREAM)
	v.add_child(t)
	v.add_child(_section("화면"))
	var screen := VBoxContainer.new()
	screen.name = "DisplaySettings"
	v.add_child(screen)
	if settings_parts.has_method("_build_display_settings"):
		# 디스플레이 설정 부품(화면 모드·창 크기 등)이 있는 HUD면 그대로 빌려 쓴다
		if "pause_display" in settings_parts:
			settings_parts.pause_display = screen
		settings_parts._build_display_settings(screen)
	else:
		fullscreen_toggle = CheckButton.new()
		fullscreen_toggle.name = "FullscreenToggle"
		fullscreen_toggle.text = "전체 화면  (F11)"
		fullscreen_toggle.add_theme_font_size_override("font_size", 15)
		fullscreen_toggle.toggled.connect(func(_on: bool): display.toggle_fullscreen())
		screen.add_child(fullscreen_toggle)
	v.add_child(_section("소리"))
	var sound := VBoxContainer.new()
	sound.name = "SoundSettings"
	sound.add_theme_constant_override("separation", 4)
	v.add_child(sound)
	settings_parts._build_sound_settings(sound)
	v.add_child(_section("안내"))
	tutorial_toggle = CheckButton.new()
	tutorial_toggle.name = "TutorialReplay"
	tutorial_toggle.text = "튜토리얼 다시 보기 (다음 새 이야기에서 첫 고용 안내)"
	tutorial_toggle.add_theme_font_size_override("font_size", 15)
	tutorial_toggle.toggled.connect(func(on: bool): Flow.set_tutorial_done(not on))
	v.add_child(tutorial_toggle)
	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(close_settings)
	v.add_child(close)


func _section(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MoonSkin.font(true))
	l.add_theme_font_size_override("font_size", 17)
	l.add_theme_color_override("font_color", MoonSkin.TEAL)
	return l


func _open_settings() -> void:
	tutorial_toggle.set_pressed_no_signal(not Flow.tutorial_done())
	if fullscreen_toggle != null:
		var w := get_window()
		fullscreen_toggle.set_pressed_no_signal(w.mode in [Window.MODE_FULLSCREEN, Window.MODE_EXCLUSIVE_FULLSCREEN])
	settings_panel.visible = true
	title_box.visible = false
	menu.visible = false
	sounds.play("panel_open")


func close_settings() -> void:
	settings_panel.visible = false
	title_box.visible = true
	menu.visible = true
	sounds.play("panel_close")
	settings_btn.grab_focus.call_deferred()


# ───────────────────────── 마녀 선택 ─────────────────────────

func _build_select() -> void:
	select_panel = Control.new()
	select_panel.name = "WitchSelect"
	select_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	select_panel.visible = false
	add_child(select_panel)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.03, 0.01, 0.08, 0.72)
	select_panel.add_child(dim)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 18)
	select_panel.add_child(v)
	var head := Label.new()
	head.text = "누구의 이야기인가"
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_override("font", MoonSkin.font(true))
	head.add_theme_font_size_override("font_size", 40)
	head.add_theme_color_override("font_color", MoonSkin.CREAM)
	v.add_child(head)
	var lead := Label.new()
	lead.text = "마녀사냥에서 살아남은 네 마녀. 지금은 한 사람의 이야기만 열려 있습니다."
	lead.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lead.add_theme_font_size_override("font_size", 17)
	lead.add_theme_color_override("font_color", MoonSkin.LAVENDER)
	v.add_child(lead)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	v.add_child(row)
	for i in WITCHES.size():
		row.add_child(_slot(i))
	select_note = Label.new()
	select_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	select_note.add_theme_font_size_override("font_size", 16)
	select_note.add_theme_color_override("font_color", MoonSkin.CREAM_DIM)
	v.add_child(select_note)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	v.add_child(buttons)
	var back := Button.new()
	back.text = "뒤로"
	back.custom_minimum_size = Vector2(180, 50)
	back.pressed.connect(close_select)
	buttons.add_child(back)
	start_btn = Button.new()
	start_btn.text = "이 마녀로 시작"
	start_btn.custom_minimum_size = Vector2(260, 50)
	start_btn.add_theme_font_override("font", MoonSkin.font(true))
	start_btn.disabled = true
	start_btn.pressed.connect(start_story)
	buttons.add_child(start_btn)


func _slot(i: int) -> Control:
	var w: Array = WITCHES[i]
	var b := Button.new()
	b.name = "Witch_%s" % w[0]
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(230, 400)
	b.focus_mode = Control.FOCUS_ALL
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_FULL_RECT)
	v.offset_left = 12
	v.offset_right = -12
	v.offset_top = 12
	v.offset_bottom = -12
	v.add_theme_constant_override("separation", 8)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(v)
	var art_path := ART_DIR + ("witch_portrait.png" if w[3] else "witch_locked.png")
	var pic: Control
	if ResourceLoader.exists(art_path):
		var tr := TextureRect.new()
		tr.texture = load(art_path)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic = tr
	else:
		var sil := WitchSilhouette.new()   # 플레이스홀더 실루엣
		sil.locked = not w[3]
		pic = sil
	pic.custom_minimum_size = Vector2(200, 270)
	pic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(pic)
	if not w[3] and pic is TextureRect:
		var q := Label.new()   # 잠긴 칸의 '?'는 그림 위에 게임이 그린다
		q.text = "?"
		q.set_anchors_preset(Control.PRESET_FULL_RECT)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		q.add_theme_font_override("font", MoonSkin.font(true))
		q.add_theme_font_size_override("font_size", 96)
		q.add_theme_color_override("font_color", Color(MoonSkin.LAVENDER, 0.85))
		q.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pic.add_child(q)
	var name_l := Label.new()
	name_l.text = w[1] if w[3] else ""   # 잠긴 칸의 '?'는 그림 위에 크게 하나만
	name_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_l.add_theme_font_override("font", MoonSkin.font(true))
	name_l.add_theme_font_size_override("font_size", 26)
	name_l.add_theme_color_override("font_color", MoonSkin.CREAM if w[3] else MoonSkin.LAVENDER)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(name_l)
	var desc := Label.new()
	desc.text = w[2]
	desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", MoonSkin.CREAM_DIM)
	desc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(desc)
	if not w[3]:
		b.modulate = Color(0.72, 0.68, 0.82)
		b.tooltip_text = "잠김 — 아직 만나지 못한 마녀"
	b.pressed.connect(func(): select_witch(i))
	slot_buttons.append(b)
	return b


func _open_select() -> void:
	select_panel.visible = true
	menu.visible = false
	title_box.visible = false
	sounds.play("panel_open")
	select_witch(0)
	start_btn.grab_focus.call_deferred()


func close_select() -> void:
	select_panel.visible = false
	menu.visible = true
	title_box.visible = true
	new_btn.grab_focus.call_deferred()


## 잠긴 칸은 고를 수 없다. 반환: 실제로 선택됐는지.
func select_witch(i: int) -> bool:
	var ok: bool = WITCHES[i][3]
	if ok:
		selected = i
		select_note.text = "선택: %s" % WITCHES[i][1]
	else:
		select_note.text = "아직 잠겨 있습니다 — 다른 마녀의 이야기는 나중에 열립니다"
		sounds.play("card_deny")
	for k in slot_buttons.size():
		slot_buttons[k].set_pressed_no_signal(k == selected)
	start_btn.disabled = selected < 0
	return ok


## 새 이야기 시작: 프롤로그부터.
func start_story() -> void:
	if selected < 0:
		return
	Flow.witch_id = WITCHES[selected][0]
	if music != null:
		var tw := create_tween()
		tw.tween_property(music, "volume_db", -40.0, 0.4)
	Flow.start_game(get_tree(), true)


func _unhandled_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo or k.keycode != KEY_ESCAPE:
		return
	if settings_panel.visible:
		close_settings()
	elif select_panel.visible:
		close_select()
	get_viewport().set_input_as_handled()


# ───────────────────────── 플레이스홀더 그림 ─────────────────────────

## 밤의 산장(로비 원화 레이어도 옛 타이틀 그림도 없을 때): 하늘 그라데이션·달·숲 실루엣·눈밭·창문 불빛.
class NightLodge extends Control:
	var t := 0.0

	func _draw() -> void:
		var s := size
		var sky_top := Color(0.08, 0.05, 0.20)
		var sky_low := Color(0.26, 0.16, 0.40)
		for i in 24:
			var y0 := s.y * i / 24.0
			draw_rect(Rect2(0, y0, s.x, s.y / 24.0 + 1), sky_top.lerp(sky_low, i / 23.0))
		draw_circle(Vector2(s.x * 0.74, s.y * 0.2), s.y * 0.06, Color(0.98, 0.94, 0.82))
		draw_circle(Vector2(s.x * 0.74, s.y * 0.2), s.y * 0.11, Color(0.9, 0.85, 1.0, 0.08))
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for layer in 3:
			var base := s.y * (0.62 + layer * 0.07)
			var col := Color(0.10, 0.08, 0.22).lerp(Color(0.03, 0.03, 0.09), layer / 2.0)
			var x := -40.0
			while x < s.x + 40.0:
				var h := s.y * rng.randf_range(0.16, 0.3) * (1.0 - layer * 0.15)
				var w := h * 0.42
				draw_colored_polygon(PackedVector2Array([Vector2(x, base), Vector2(x + w * 0.5, base - h), Vector2(x + w, base)]), col)
				x += w * rng.randf_range(0.55, 0.9)
			draw_rect(Rect2(0, base - 1, s.x, s.y - base + 1), col)
		# 눈밭
		draw_rect(Rect2(0, s.y * 0.8, s.x, s.y * 0.2), Color(0.42, 0.40, 0.62))
		# 산장
		var lx := s.x * 0.58
		var ly := s.y * 0.8
		var lw := s.x * 0.16
		var lh := s.y * 0.13
		draw_rect(Rect2(lx, ly - lh, lw, lh), Color(0.16, 0.10, 0.18))
		draw_colored_polygon(PackedVector2Array([Vector2(lx - lw * 0.08, ly - lh), Vector2(lx + lw * 0.5, ly - lh * 2.0), Vector2(lx + lw * 1.08, ly - lh)]), Color(0.78, 0.76, 0.92))
		draw_rect(Rect2(lx + lw * 0.72, ly - lh * 2.0, lw * 0.1, lh * 0.6), Color(0.2, 0.14, 0.2))
		var flicker := 0.85 + 0.15 * sin(t * 7.0) * sin(t * 3.1)
		for wx in [0.18, 0.62]:
			var r := Rect2(lx + lw * wx, ly - lh * 0.68, lw * 0.2, lh * 0.34)
			draw_rect(r.grow(lw * 0.06), Color(1.0, 0.7, 0.3, 0.12 * flicker))
			draw_rect(r, Color(1.0, 0.76, 0.38) * flicker)
		# 굴뚝 연기
		for k in 5:
			var p := fmod(t * 0.12 + k * 0.2, 1.0)
			draw_circle(Vector2(lx + lw * 0.77 + sin(p * 6.0 + k) * 10.0, ly - lh * 2.0 - p * s.y * 0.18), 8.0 + p * 18.0, Color(0.7, 0.66, 0.85, 0.18 * (1.0 - p)))


## 마녀 실루엣(선택 칸 그림이 오기 전): 후드 쓴 상반신. 잠긴 칸은 단색 + '?'.
class WitchSilhouette extends Control:
	var locked := false

	func _draw() -> void:
		var s := size
		var c := Vector2(s.x * 0.5, s.y * 0.5)
		var col := Color(0.16, 0.13, 0.28) if locked else Color(0.36, 0.24, 0.55)
		var cloak := PackedVector2Array([Vector2(c.x - s.x * 0.38, s.y), Vector2(c.x - s.x * 0.2, c.y - s.y * 0.05), Vector2(c.x, c.y - s.y * 0.36), Vector2(c.x + s.x * 0.2, c.y - s.y * 0.05), Vector2(c.x + s.x * 0.38, s.y)])
		draw_colored_polygon(cloak, col)
		draw_circle(Vector2(c.x, c.y - s.y * 0.12), s.x * 0.15, col.darkened(0.25))
		if locked:
			var font := get_theme_default_font()
			var fs := 96
			var w := font.get_string_size("?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string(font, Vector2(c.x - w * 0.5, c.y + fs * 0.35), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.75, 0.68, 0.95, 0.9))
		else:
			draw_circle(Vector2(c.x + s.x * 0.17, c.y + s.y * 0.22), s.x * 0.05, Color(1.0, 0.76, 0.38))
			draw_circle(Vector2(c.x + s.x * 0.17, c.y + s.y * 0.22), s.x * 0.11, Color(1.0, 0.7, 0.3, 0.18))
