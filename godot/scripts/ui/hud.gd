extends CanvasLayer
## HUD 컨트롤러: 달빛 마법 상시 HUD(scripts/ui/moon), 손패, 산장 관리창, 일시 정지(설정·지도·조작법),
## 종료 화면, 디버그 메뉴, 알림. 상시 패널의 그림·배치는 MoonHud가, 열기/닫기·시간 정지는 여기서 맡는다.

const Cfg := preload("res://scripts/config.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const ScreenStyle := preload("res://scripts/visual/screen_style.gd")
const CameraStyle := preload("res://scripts/visual/camera_style.gd")
const CardFeel := preload("res://scripts/ui/card_feel.gd")
const HandTime := preload("res://scripts/ui/hand_focus_time.gd")
const AirStyle := preload("res://scripts/visual/aerial_perspective.gd")
const CardHandScript := preload("res://scripts/ui/card_hand.gd")
const ExplorationMap := preload("res://scripts/ui/exploration_map.gd")
const MoonHudScript := preload("res://scripts/ui/moon/moon_hud.gd")
const MoonLayout := preload("res://scripts/ui/moon/moon_layout.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const OutsideClick := preload("res://scripts/ui/outside_click.gd")
const CarryBubbleScript := preload("res://scripts/ui/carry_bubble.gd")
const Extension := preload("res://scripts/ui/moon/moon_extension.gd")
const Flow := preload("res://scripts/game/flow.gd")
const WindowModeScript := preload("res://scripts/visual/window_mode.gd")
const PartyFrameScript := preload("res://scripts/ui/party_frame.gd")
const MercPanelScript := preload("res://scripts/ui/merc_panel.gd")

const C_TEXT := Color(0.96, 0.93, 0.98)
const C_DIM := MoonSkin.LAVENDER

## 지도 창(접이식): 디자인 px, 왼쪽 위 기준(목표판·유물칸 아래). 오른쪽 가장자리는 용병 초상 메달 줄이 쓴다(2026-10-19).
const MAP_SLOT := Rect2(22, 262, 252, 270)

var game
var theme_res: Theme
var root: Control
var moon
var moon_ref: Control
var toast_box: VBoxContainer
var lodge_panel: PanelContainer
var lodge_tabs: TabContainer
var lodge_guests: VBoxContainer
var lodge_history: VBoxContainer
var lodge_contracts: VBoxContainer     # 계약 탭: 활동 중 용병 + 미사용 계약 카드
var contract_rows: Array = []          # [{c, status, button}]
var _contract_key := ""                # 목록이 바뀌었을 때만 줄을 다시 만든다
var lodge_timber: Label
var lodge_gold: Label
var shop_rows: Dictionary = {}
var pause_panel: PanelContainer
var pause_settings: VBoxContainer
var pause_help: Control
var settings_btn: Button
var help_btn: Button
var pause_sound: VBoxContainer
var pause_display: VBoxContainer
var display_btn: Button
var display_mode_select: OptionButton
var display_size_select: OptionButton
var display_vsync: CheckButton
var display_fps_select: OptionButton
var display_scale_select: OptionButton
var display_info: Label
var sound_btn: Button
var volume_sliders: Dictionary = {}  # master·music·sfx → HSlider
var volume_values: Dictionary = {}   # master·music·sfx → 퍼센트 Label
var mute_toggle: CheckButton
var end_panel: PanelContainer
var end_title: Label
var end_body: Label
var end_hint: Label        # 패배 원인별 다음 행동 한 줄
var retry_btn: Button
var title_btn: Button
var debug_panel: PanelContainer
var overlay: Control       # 화면 고정 표시(늑대 스킬 바·디버그), HUD 층 10
var world_marks: Control   # 월드 표시(체력 바·이름표·모닥불 링), WorldMarks 층 4 — 말풍선 아래
var style_select: OptionButton
var camera_select: OptionButton
var air_select: OptionButton
var time_select: OptionButton
var fog_toggle: CheckButton
var fog_select: OptionButton
var card_hand
var map_window: PanelContainer
var relic_tray: HBoxContainer
var party_frame    # 용병 초상 메달(오른쪽 세로 줄, scripts/ui/party_frame.gd)
var merc_panel: PanelContainer   # 용병 관리 창(메달 줄의 "+N"을 누르면, scripts/ui/merc_panel.gd)
var merc_list      # 그 창의 내용(MercPanel)
var exploration_map


func _ready() -> void:
	# 타이틀 화면은 설정 부품(_build_sound_settings 등)만 빌려 쓴다 — 게임 세션이 없으면 HUD를 짓지 않는다
	if game == null or game.get("session") == null:
		set_process(false)
		set_process_unhandled_input(false)
		return
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme_res = MoonSkin.make_theme()
	root = Control.new()
	root.name = "HUDRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = theme_res
	add_child(root)
	overlay = HpOverlay.new()
	overlay.game = game
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	# 월드 표시는 말풍선(층 6)보다 아래 층에 따로 그려 손님·자원 말풍선을 가리지 않게 한다.
	var marks_layer := CanvasLayer.new()
	marks_layer.name = "WorldMarks"
	marks_layer.layer = 4
	add_child(marks_layer)
	world_marks = HpOverlay.new()
	world_marks.name = "WorldMarksOverlay"
	world_marks.game = game
	world_marks.world_marks = true
	world_marks.theme = theme_res
	world_marks.set_anchors_preset(Control.PRESET_FULL_RECT)
	world_marks.mouse_filter = Control.MOUSE_FILTER_IGNORE
	marks_layer.add_child(world_marks)
	moon =MoonHudScript.new()
	moon.game = game
	moon.hud = self
	root.add_child(moon)
	party_frame = PartyFrameScript.new()
	party_frame.game = game
	root.add_child(party_frame)
	_build_toasts()
	card_hand = CardHandScript.new()
	card_hand.name = "CardHand"
	card_hand.game = game
	card_hand.hud = self
	root.add_child(card_hand)
	_build_exploration_map()
	_build_relic_tray()
	_build_lodge_panel()
	_build_merc_panel()
	_build_pause()
	_build_end()
	_build_debug()
	if _ui_arg() == "moon_ref":
		show_reference(true)
	game.session.state_changed.connect(_on_state_changed)
	game.world.screen_style_changed.connect(_sync_screen_style)
	game.world.camera_style_changed.connect(_sync_camera_style)
	game.world.air_style_changed.connect(_sync_air_style)


## 유물칸: 왼쪽 위 상태판 아래. 보물상자에서 고른 유물(영구 패시브)을 아이콘으로 보여 주고, 올리면 설명.
func _build_relic_tray() -> void:
	relic_tray = HBoxContainer.new()
	relic_tray.name = "RelicTray"
	relic_tray.add_theme_constant_override("separation", 6)
	relic_tray.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(relic_tray, 0, 0, 0, 0, 30, 212, 30 + 5 * 50, 212 + 44)
	root.add_child(relic_tray)
	if game.relics != null:
		game.relics.changed.connect(_refresh_relic_tray)
	_refresh_relic_tray()


func _refresh_relic_tray() -> void:
	for c in relic_tray.get_children():
		c.queue_free()
	if game.relics == null:
		return
	for id in game.relics.owned:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Extension.box("relic", 52, Vector4(12, 12, 12, 12), Vector4(6, 6, 6, 6)))
		p.custom_minimum_size = Vector2(44, 44)
		p.tooltip_text = "%s
%s" % [Cfg.RELIC_NAMES[id], Cfg.RELIC_DESC[id]]
		p.mouse_filter = Control.MOUSE_FILTER_STOP
		var icon := TextureRect.new()
		icon.texture = CarryBubbleScript.icon_for(id)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(38, 38)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(icon)
		relic_tray.add_child(p)
		p.modulate = Color(1, 1, 1, 0)
		var tw := p.create_tween().set_ignore_time_scale(true)
		tw.tween_property(p, "modulate:a", 1.0, 0.4)


func _ui_arg() -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ui="):
			return a.trim_prefix("--ui=")
	return ""


## 원본 재현 모드(개발용 비교): 승인 원본 8개 그룹만 보이고 동적 HUD·손패는 숨긴다.
func show_reference(on: bool) -> void:
	if on and moon_ref == null:
		moon_ref = MoonHudScript.Reference.new()
		root.add_child(moon_ref)
		root.move_child(moon_ref, moon.get_index() + 1)
	if moon_ref != null:
		moon_ref.visible = on
	moon.visible = not on
	card_hand.visible = not on


# ───────────────────────── 공용 부품(손패 UI도 사용) ─────────────────────────

func _label(text: String, size := 17, color := C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _title(text: String, size := 26) -> Label:
	var l := _label(text, size, MoonSkin.CREAM)
	l.add_theme_font_override("font", MoonSkin.font(true))
	if size >= 24:
		Extension.title(l)
	return l


func _place(c: Control, al: float, at: float, ar: float, ab: float, ol: float, ot: float, orr: float, ob: float) -> void:
	c.anchor_left = al
	c.anchor_top = at
	c.anchor_right = ar
	c.anchor_bottom = ab
	c.offset_left = ol
	c.offset_top = ot
	c.offset_right = orr
	c.offset_bottom = ob


## 공통 확장 모달(시안에 없는 팝업): 승인 패널의 인디고 바탕·크림 경계만 따른다.
func _modal(w: float, h: float) -> PanelContainer:
	var p := PanelContainer.new()
	_place(p, 0.5, 0.5, 0.5, 0.5, -w * 0.5, -h * 0.5, w * 0.5, h * 0.5)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.grow_vertical = Control.GROW_DIRECTION_BOTH
	p.add_theme_stylebox_override("panel", MoonSkin.modal_box())
	p.set_meta("extension_design", Vector2(w, h))
	p.visible = false
	root.add_child(p)
	p.minimum_size_changed.connect(func(): Extension.fit_modal.call_deferred(p))
	root.resized.connect(func(): Extension.fit_modal(p))
	Extension.fit_modal.call_deferred(p)
	return p


func _button(text: String, h := 44.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, h)
	return b


# ───────────────────────── 구성 ─────────────────────────

func _build_toasts() -> void:
	toast_box = VBoxContainer.new()
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	toast_box.add_theme_constant_override("separation", 4)
	_place(toast_box, 0.5, 0, 0.5, 0, -260, 140, 260, 360)
	root.add_child(toast_box)


func _build_lodge_panel() -> void:
	lodge_panel = _modal(820, 820)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	lodge_panel.add_child(v)
	# 제목은 창 전체 폭 가운데(헤더 그림은 비율 유지). 보유 골드·목재는 제목 아래 한 줄로 두어 가운데 정렬을 깨지 않는다.
	var title := _title("산장 관리")
	v.add_child(title)
	var status := HBoxContainer.new()
	status.add_theme_constant_override("separation", 16)
	v.add_child(status)
	lodge_gold = _label("", 20, MoonSkin.CREAM)
	lodge_gold.add_theme_font_override("font", MoonSkin.font(true))
	lodge_gold.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(lodge_gold)
	lodge_timber = _label("", 17, MoonSkin.CREAM)
	lodge_timber.add_theme_font_override("font", MoonSkin.font(true))
	lodge_timber.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(lodge_timber)
	var note := _label("건물의 생성·증축·확장에는 손패의 목재가 듭니다 (주머니 목재는 뽑아야 사용). 관리창을 여는 동안 준비 시간이 멈춥니다.", 13, C_DIM)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(note)
	var shell := v
	lodge_tabs = TabContainer.new()
	lodge_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(lodge_tabs)
	var facility_scroll := ScrollContainer.new()
	facility_scroll.name = "시설"
	facility_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lodge_tabs.add_child(facility_scroll)
	v = VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	facility_scroll.add_child(v)
	lodge_guests = VBoxContainer.new()
	lodge_guests.name = "손님"
	lodge_guests.add_theme_constant_override("separation", 12)
	lodge_tabs.add_child(lodge_guests)
	lodge_history = VBoxContainer.new()
	lodge_history.name = "대화 기록"
	lodge_tabs.add_child(lodge_history)
	_build_contract_tab()
	var items := [
		["extension", "객실 증축", "정원 2 → 3명 · 다음 손님 묶음부터 적용 (1회)"],
		["pasture", "목장 증축", "울타리를 넓혀 양 최대 수를 늘립니다"],
		["bunks", "용병 숙소 증축", "침상 4 → 6 → 8개 · 데리고 있는 용병(활동 중 + 미사용 계약)은 침상 수까지 · %d일차·%d일차부터" % Cfg.BUNK_UNLOCK_DAYS],
		["graves", "묘지 확장", "산장 뒤편 무덤 자리 +4 · 쓰러진 용병의 비석이 놓입니다"],
		["tower_left", "왼쪽 감시탑", "공터에 목재 카드를 적립한 뒤 건설 · 밤에 사냥꾼이 올라가 멀리 쏘고 시야를 밝힘 (1단계 1명 · 2단계 3명)"],
		["tower_right", "오른쪽 감시탑", "공터에 목재 카드를 적립한 뒤 건설 · 밤에 사냥꾼이 올라가 멀리 쏘고 시야를 밝힘 (1단계 1명 · 2단계 3명)"],
		["sheep", "양 구입", "목장 빈자리에 양 1마리 · 다음 낮부터 털 생산"],
		["repair", "산장 수리", "산장 체력 +%d (최대 체력까지)" % int(Cfg.REPAIR_AMOUNT)],
		["heal", "마녀 회복", "마녀 체력 +%d (최대 체력까지)" % int(Cfg.HEAL_AMOUNT)],
	]
	for it in items:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", MoonSkin.row_box())
		v.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 12)
		row.add_child(h)
		h.add_child(Extension.icon("person" if it[0] == "bunks" else it[0], 60))
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 1)
		h.add_child(info)
		var name_row := HBoxContainer.new()
		info.add_child(name_row)
		var name_l := _label(it[1], 19, C_TEXT)
		name_l.add_theme_font_override("font", MoonSkin.font(true))
		name_row.add_child(name_l)
		var state := _label("", 14, MoonSkin.TEAL)
		state.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		state.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		name_row.add_child(state)
		var desc := _label(it[2], 13, C_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(desc)
		var reason := _label("", 13, MoonSkin.BAD)
		info.add_child(reason)
		var btn := _button("", 46)
		btn.custom_minimum_size.x = 176
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var kind: String = it[0]
		btn.pressed.connect(func(): game.economy.buy(kind))
		h.add_child(btn)
		shop_rows[kind] = {"button": btn, "reason": reason, "state": state}
	var close := _button("닫기", 42)
	close.pressed.connect(close_lodge_panel)
	shell.add_child(close)


## 용병 관리 창: 메달 줄에 다 못 그린 용병까지 전원(초상·직업·종족·체력·하는 일·장비). 낮·밤 언제든 열리고 여는 동안 멈춘다.
func _build_merc_panel() -> void:
	merc_panel = _modal(780, 720)
	merc_list = MercPanelScript.new()
	merc_list.game = game
	merc_list.hud = self
	merc_panel.add_child(merc_list)


func _build_pause() -> void:
	pause_panel = _modal(500, 420)
	var v := VBoxContainer.new()
	v.custom_minimum_size.x = 420
	v.add_theme_constant_override("separation", 10)
	pause_panel.add_child(v)
	var t := _title("일시 정지")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var resume := _button("계속하기")
	resume.pressed.connect(_toggle_pause)
	v.add_child(resume)
	var map_btn := _button("지도 보기")
	map_btn.pressed.connect(_open_map_from_pause)
	v.add_child(map_btn)
	settings_btn = _button("화면 설정  ▾")
	settings_btn.pressed.connect(func(): _toggle_section(pause_settings))
	v.add_child(settings_btn)
	pause_settings = VBoxContainer.new()
	pause_settings.add_theme_constant_override("separation", 4)
	pause_settings.visible = false
	v.add_child(pause_settings)
	_build_screen_styles(pause_settings)
	display_btn = _button("디스플레이  ▾")
	display_btn.pressed.connect(func(): _toggle_section(pause_display))
	v.add_child(display_btn)
	pause_display = VBoxContainer.new()
	pause_display.name = "DisplaySettings"
	pause_display.add_theme_constant_override("separation", 4)
	pause_display.visible = false
	v.add_child(pause_display)
	_build_display_settings(pause_display)
	sound_btn = _button("소리 설정  ▾")
	sound_btn.pressed.connect(func(): _toggle_section(pause_sound))
	v.add_child(sound_btn)
	pause_sound = VBoxContainer.new()
	pause_sound.name = "SoundSettings"
	pause_sound.add_theme_constant_override("separation", 4)
	pause_sound.visible = false
	v.add_child(pause_sound)
	_build_sound_settings(pause_sound)
	help_btn = _button("조작법  ▾")
	help_btn.pressed.connect(func(): _toggle_section(pause_help))
	v.add_child(help_btn)
	pause_help = PanelContainer.new()
	pause_help.add_theme_stylebox_override("panel", Extension.paper(14))
	var help_content := VBoxContainer.new()
	pause_help.add_child(help_content)
	var keycaps := HBoxContainer.new()
	keycaps.alignment = BoxContainer.ALIGNMENT_CENTER
	help_content.add_child(keycaps)
	for key in ["W", "A", "S", "D"]:
		var keycap := _label(key, 16, MoonSkin.PAPER_INK)
		keycap.add_theme_stylebox_override("normal", Extension.person())
		keycaps.add_child(keycap)
	var help_text := _label("우클릭: 이동 · 적 우클릭: 평타  ·  A+좌클릭: 공격 이동  ·  S: 정지\n방향키: 이동  ·  휠: 줌  ·  Space: 마녀 보기  ·  C: 사거리  ·  H: 산장  ·  F4: 산장뷰\nM: 지도  ·  카드 드래그: 사용 (우클릭 취소)\n털 난 양 클릭: 수확  ·  손님 클릭: 고용\nEsc: 일시 정지  ·  F1: 디버그\nF2/F3/F5: 화면  ·  F7: 식생 구분선 시안  ·  F11: 전체화면", 13, MoonSkin.PAPER_INK)
	help_content.add_child(help_text)
	pause_help.visible = false
	v.add_child(pause_help)
	v.add_child(HSeparator.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	for pair in [["새 게임", _restart], ["타이틀로", _to_title], ["종료", func(): get_tree().quit()]]:
		var b := _button(pair[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pair[1])
		row.add_child(b)


func _toggle_section(section: Control) -> void:
	section.visible = not section.visible
	settings_btn.text = "화면 설정  " + ("▴" if pause_settings.visible else "▾")
	display_btn.text = "디스플레이  " + ("▴" if pause_display.visible else "▾")
	if pause_display.visible: _sync_display_settings()
	sound_btn.text = "소리 설정  " + ("▴" if pause_sound.visible else "▾")
	help_btn.text = "조작법  " + ("▴" if pause_help.visible else "▾")
	_recenter(pause_panel)


func _recenter(p: Control) -> void:
	Extension.fit_modal(p)


func _build_end() -> void:
	end_panel = _modal(540, 360)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	end_panel.add_child(v)
	end_title = _title("", 32)
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(end_title)
	end_body = _label("", 16, C_TEXT)
	end_body.add_theme_color_override("font_color", MoonSkin.PAPER_INK)
	end_body.add_theme_stylebox_override("normal", Extension.paper(20))
	end_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_body.custom_minimum_size.x = 500
	v.add_child(end_body)
	end_hint = _label("", 16, MoonSkin.CREAM)
	end_hint.name = "EndHint"
	end_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	end_hint.custom_minimum_size.x = 500
	v.add_child(end_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	v.add_child(row)
	retry_btn = _button("다시 도전", 48)
	retry_btn.pressed.connect(_restart)
	title_btn = _button("타이틀로", 48)
	title_btn.pressed.connect(_to_title)
	for b in [retry_btn, title_btn]:
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(b)


func _build_debug() -> void:
	debug_panel = PanelContainer.new()
	debug_panel.add_theme_stylebox_override("panel", MoonSkin.tooltip_box())
	_place(debug_panel, 1, 0, 1, 0, -240, 136, -16, 630)
	debug_panel.visible = false
	root.add_child(debug_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 5)
	debug_panel.add_child(v)
	v.add_child(_label("디버그 (F1)", 16, MoonSkin.GOOD))
	var entries := [
		["골드 +100", game.debug_gold],
		["웨이브 즉시 시작", game.debug_start_wave],
		["용비늘 얻기", game.debug_dragon_scale],
		["산장 피해 50", game.debug_damage_lodge],
		["마녀 피해 25", game.debug_damage_player],
		["적 전체 처치", game.debug_kill_all],
		["카드 지급", game.debug_cards],
		["장비 카드 지급", game.debug_equipment],
		["고블린 카드·용병 지급", game.debug_goblin],
		["종족·언데드 카드 지급", game.debug_race_cards],
		["에린·술 카드 지급", game.debug_tavern_cards],
		["에린 방문 부르기", game.debug_erin_visit],
		["전설 카드·광석 지급", game.debug_legend_cards],
		["용병 키트 종족 4명 지급(누를 때마다 다음 종족)", game.debug_merc_kit],
		["적 경로·공격 지점 표시", game.debug_toggle_draw],
		["달빛 UI 원본 비교", func(): show_reference(moon.visible)],
	]
	for e in entries:
		var b := Button.new()
		b.text = e[0]
		b.add_theme_font_size_override("font_size", 14)
		b.pressed.connect(e[1])
		v.add_child(b)


## 소리 설정: 전체·배경음(음악·환경음)·효과음 음량 슬라이더와 음소거. 바꾸면 바로 들리고 user://settings.cfg 에 저장된다.
func _build_sound_settings(box: VBoxContainer) -> void:
	var sb = game.sounds
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)
	for row in [["master", "전체 음량"], ["music", "배경음"], ["sfx", "효과음"]]:
		var kind: String = row[0]
		grid.add_child(_label(row[1], 14, C_DIM))
		var slider := HSlider.new()
		slider.name = "Volume_" + kind
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 5.0
		slider.custom_minimum_size = Vector2(200, 24)
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(slider)
		var value := _label("", 14, C_TEXT)
		value.custom_minimum_size.x = 44
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(value)
		volume_sliders[kind] = slider
		volume_values[kind] = value
		slider.value = round(float(sb.volumes[kind]) * 100.0) if sb != null else 100.0
		value.text = "%d%%" % int(slider.value)
		slider.value_changed.connect(func(v: float):
			value.text = "%d%%" % int(v)
			if game.sounds != null: game.sounds.set_volume(kind, v / 100.0))
		# 손을 놓으면 효과음 크기를 들려준다
		slider.drag_ended.connect(func(_changed: bool):
			if kind != "music" and game.sounds != null: game.sounds.play("btn_click"))
	mute_toggle = CheckButton.new()
	mute_toggle.name = "MuteToggle"
	mute_toggle.text = "음소거"
	mute_toggle.add_theme_font_size_override("font_size", 14)
	mute_toggle.button_pressed = sb != null and sb.muted
	mute_toggle.toggled.connect(func(on: bool):
		if game.sounds != null: game.sounds.set_muted(on))
	box.add_child(mute_toggle)


## 디스플레이: 화면 모드·창 크기·수직 동기화·프레임 제한·3D 해상도. 바꾸면 바로 적용되고 user://settings.cfg 에 저장된다.
## F11로 바꾼 것도 display.changed 로 따라 맞춘다.
func _build_display_settings(box: VBoxContainer) -> void:
	var ds = game.display
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)
	grid.add_child(_label("화면 모드 · F11", 14, C_DIM))
	display_mode_select = OptionButton.new()
	display_mode_select.name = "DisplayModeSelect"
	for label in WindowModeScript.MODE_NAMES: display_mode_select.add_item(label)
	display_mode_select.item_selected.connect(func(i: int): if game.display != null: game.display.set_mode(WindowModeScript.MODES[i]))
	grid.add_child(display_mode_select)
	grid.add_child(_label("창 크기", 14, C_DIM))
	display_size_select = OptionButton.new()
	display_size_select.name = "DisplaySizeSelect"
	display_size_select.item_selected.connect(func(i: int):
		if game.display != null: game.display.set_window_size(display_size_select.get_item_metadata(i)))
	grid.add_child(display_size_select)
	grid.add_child(_label("프레임 제한", 14, C_DIM))
	display_fps_select = OptionButton.new()
	display_fps_select.name = "DisplayFpsSelect"
	for fps in WindowModeScript.FPS_LIMITS: display_fps_select.add_item("제한 없음" if fps == 0 else "%d FPS" % fps)
	display_fps_select.item_selected.connect(func(i: int): if game.display != null: game.display.set_max_fps(WindowModeScript.FPS_LIMITS[i]))
	grid.add_child(display_fps_select)
	grid.add_child(_label("3D 해상도", 14, C_DIM))
	display_scale_select = OptionButton.new()
	display_scale_select.name = "DisplayScaleSelect"
	for v in WindowModeScript.RENDER_SCALES: display_scale_select.add_item("%d%%" % int(round(v * 100.0)) + ("  (선명)" if v >= 1.0 else ""))
	display_scale_select.item_selected.connect(func(i: int): if game.display != null: game.display.set_render_scale(WindowModeScript.RENDER_SCALES[i]))
	grid.add_child(display_scale_select)
	for select in [display_mode_select, display_size_select, display_fps_select, display_scale_select]:
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.add_theme_font_size_override("font_size", 14)
	display_vsync = CheckButton.new()
	display_vsync.name = "DisplayVsync"
	display_vsync.text = "수직 동기화"
	display_vsync.add_theme_font_size_override("font_size", 14)
	display_vsync.toggled.connect(func(on: bool): if game.display != null: game.display.set_vsync(on))
	box.add_child(display_vsync)
	display_info = _label("", 12, C_DIM)
	display_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(display_info)
	if ds != null:
		ds.changed.connect(_sync_display_settings)
	get_viewport().size_changed.connect(func(): if pause_display.visible: _sync_display_settings())
	_sync_display_settings()


## 저장된 디스플레이 값을 UI에 반영한다(신호를 다시 쏘지 않도록 set_block_signals로 감싼다).
func _sync_display_settings() -> void:
	var ds = game.display
	if ds == null or display_mode_select == null:
		return
	for c in [display_mode_select, display_size_select, display_fps_select, display_scale_select, display_vsync]:
		c.set_block_signals(true)
	display_mode_select.select(WindowModeScript.MODES.find(ds.mode))
	display_size_select.clear()
	var choices: Array = ds.window_size_choices()
	for i in choices.size():
		var sz: Vector2i = choices[i]
		display_size_select.add_item("%d × %d" % [sz.x, sz.y])
		display_size_select.set_item_metadata(i, sz)
		if sz == ds.window_size: display_size_select.select(i)
	display_size_select.disabled = ds.mode != "windowed"
	display_size_select.tooltip_text = "" if ds.mode == "windowed" else "창 모드에서 고를 수 있습니다"
	var fi: int = WindowModeScript.FPS_LIMITS.find(ds.max_fps)
	display_fps_select.select(fi if fi != -1 else 0)
	var best := 0
	for i in WindowModeScript.RENDER_SCALES.size():
		if absf(WindowModeScript.RENDER_SCALES[i] - ds.render_scale) < absf(WindowModeScript.RENDER_SCALES[best] - ds.render_scale): best = i
	display_scale_select.select(best)
	display_vsync.button_pressed = ds.vsync
	for c in [display_mode_select, display_size_select, display_fps_select, display_scale_select, display_vsync]:
		c.set_block_signals(false)
	display_info.text = ds.describe()


func _build_screen_styles(box: VBoxContainer) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 5)
	box.add_child(grid)
	grid.add_child(_label("셰이딩 · F2", 14, C_DIM))
	style_select = OptionButton.new()
	style_select.name = "ScreenStyleSelect"
	for label in ScreenStyle.NAMES: style_select.add_item(label)
	style_select.item_selected.connect(func(index: int): game.world.set_screen_style(ScreenStyle.IDS[index]))
	grid.add_child(style_select)
	_sync_screen_style(ScreenStyle.current_id)
	grid.add_child(_label("카메라 · F3", 14, C_DIM))
	camera_select = OptionButton.new()
	camera_select.name = "CameraStyleSelect"
	for label in CameraStyle.NAMES: camera_select.add_item(label)
	camera_select.item_selected.connect(func(index: int): game.world.set_camera_style(CameraStyle.IDS[index]))
	grid.add_child(camera_select)
	_sync_camera_style(CameraStyle.current_id)
	grid.add_child(_label("공기 원근 · F5", 14, C_DIM))
	air_select = OptionButton.new()
	air_select.name = "AirStyleSelect"
	for label in AirStyle.NAMES: air_select.add_item(label)
	air_select.item_selected.connect(func(index: int): game.world.set_air_style(AirStyle.IDS[index]))
	grid.add_child(air_select)
	_sync_air_style(AirStyle.current_id)
	grid.add_child(_label("카드 질감 · F9", 14, C_DIM))
	var feel_select := OptionButton.new()
	feel_select.name = "CardFeelSelect"
	for label in CardFeel.NAMES: feel_select.add_item(label)
	feel_select.item_selected.connect(func(index: int):
		var node: Node = game.get_node_or_null("CardFeel")
		if node != null: node.set_feel(CardFeel.IDS[index])
		else: CardFeel.apply(CardFeel.IDS[index]))
	# F9 로 바꾼 값도 메뉴를 열 때 맞춰 보인다
	feel_select.draw.connect(func():
		CardFeel.p()
		if feel_select.selected != CardFeel.IDS.find(CardFeel.current_id): feel_select.select(CardFeel.IDS.find(CardFeel.current_id)))
	feel_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feel_select.add_theme_font_size_override("font_size", 14)
	grid.add_child(feel_select)
	# 손패 고민 시간(scripts/ui/hand_focus_time.gd): 손패에 손을 올리면 세상이 1초에 걸쳐 멈춤 · 거의 멈춤 · 끔
	grid.add_child(_label("손패 고민 시간 · F12", 14, C_DIM))
	var hand_time_select := OptionButton.new()
	hand_time_select.name = "HandFocusTimeSelect"
	for label in HandTime.NAMES: hand_time_select.add_item(label)
	hand_time_select.item_selected.connect(func(index: int):
		var node: Node = game.get_node_or_null("HandFocusTime")
		if node != null: node.set_preset(HandTime.IDS[index])
		else: HandTime.apply(HandTime.IDS[index]))
	# F12 로 바꾼 값도 메뉴를 열 때 맞춰 보인다
	hand_time_select.draw.connect(func():
		if hand_time_select.selected != HandTime.IDS.find(HandTime.id()): hand_time_select.select(HandTime.IDS.find(HandTime.id())))
	hand_time_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_time_select.add_theme_font_size_override("font_size", 14)
	grid.add_child(hand_time_select)
	grid.add_child(_label("시간대", 14, C_DIM))
	time_select = OptionButton.new()
	var cycle := preload("res://scripts/visual/day_cycle.gd")
	for label in cycle.NAMES: time_select.add_item(label)
	time_select.item_selected.connect(func(index: int): game.world.day_cycle.set_mode(cycle.IDS[index]))
	grid.add_child(time_select)
	fog_toggle = CheckButton.new()
	fog_toggle.text = "전장의 안개"
	fog_toggle.button_pressed = true
	fog_toggle.toggled.connect(func(value: bool): game.world.fog_of_war.set_enabled(value))
	box.add_child(fog_toggle)
	fog_select = OptionButton.new()
	fog_select.name = "FogStyleSelect"
	var fog := preload("res://scripts/visual/fog_of_war.gd")
	for label in fog.NAMES: fog_select.add_item(label)
	fog_select.item_selected.connect(func(index: int): game.world.fog_of_war.configure(fog.IDS[index]))
	box.add_child(fog_select)
	for select in [style_select, camera_select, air_select, time_select, fog_select]:
		select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		select.add_theme_font_size_override("font_size", 14)


func _sync_screen_style(id: String) -> void:
	style_select.select(ScreenStyle.IDS.find(id))


func _sync_camera_style(id: String) -> void:
	camera_select.select(CameraStyle.IDS.find(id))


func _sync_air_style(id: String) -> void:
	air_select.select(AirStyle.IDS.find(id))


## 기존 탐색 지도는 그대로 쓰되 상시 표시하지 않는다. 일시 정지 '지도 보기' 또는 M으로 열고, 재개 후에도 접을 수 있다.
func _build_exploration_map() -> void:
	map_window = PanelContainer.new()
	map_window.name = "MapWindow"
	map_window.add_theme_stylebox_override("panel", Extension.modal())
	map_window.visible = false
	root.add_child(map_window)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	map_window.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var t := _label("  지도 · 클릭해 이동", 14, MoonSkin.CREAM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := Button.new()
	close.text = "✕"
	close.icon = Extension.scaled("close", 20)
	close.text = ""
	close.tooltip_text = "지도 접기 · M"
	close.custom_minimum_size = Vector2(30, 26)
	close.add_theme_font_size_override("font_size", 13)
	close.pressed.connect(func(): set_map_visible(false))
	head.add_child(close)
	exploration_map = ExplorationMap.new()
	exploration_map.game = game
	exploration_map.custom_minimum_size = Vector2(240, 228)
	v.add_child(exploration_map)
	root.resized.connect(_place_map)
	_place_map()


func _place_map() -> void:
	var view := root.size
	var at := MoonLayout.to_view(MAP_SLOT.position, Vector2(0, 0), view)
	map_window.position = at


func set_map_visible(on: bool) -> void:
	if map_window.visible != on and game.sounds != null:
		game.sounds.play("panel_open" if on else "panel_close")
	map_window.visible = on
	if on:
		_place_map()


func _open_map_from_pause() -> void:
	set_map_visible(true)
	_toggle_pause()


# ───────────────────────── 동작 ─────────────────────────

## 시간 정지는 열린 창으로부터 한 곳에서 계산한다. 낮의 관리·주머니·판매 창과 Esc 메뉴는 정지, 전투 중 주머니 목록은 정지하지 않는다. 마법서적 선택 중은 항상 정지.
func refresh_pause() -> void:
	if game.world.day_cycle != null:
		time_select.select(preload("res://scripts/visual/day_cycle.gd").IDS.find(game.world.day_cycle.mode))
		fog_toggle.set_pressed_no_signal(game.world.fog_of_war.enabled)
		fog_select.select(preload("res://scripts/visual/fog_of_war.gd").IDS.find(game.world.fog_of_war.current_id))
	var prep: bool = game.session.state == SessionScript.State.PREP
	var hold: bool = pause_panel.visible or lodge_panel.visible or merc_panel.visible or game.session.is_over()
	hold = hold or (game.guest_ui != null and game.guest_ui.dialogue_active)
	if card_hand != null:
		hold = hold or card_hand.sale_panel.visible or (prep and card_hand.pocket_panel.visible)
	if game.chest_ui != null:
		hold = hold or game.chest_ui.active
	if game.spellbook_ui != null:
		hold = hold or game.spellbook_ui.active
	if game.mulligan_ui != null:
		hold = hold or game.mulligan_ui.active
	if game.get("altar_ui") != null:
		hold = hold or game.altar_ui.active
	if game.get("offer_ui") != null:
		hold = hold or game.offer_ui.active
	# 도입 연출(프롤로그·새벽)과 첫 고용 튜토리얼은 게임을 멈춘 채 진행한다
	if game.get("opening") != null:
		hold = hold or game.opening.hold
	if game.get("tutorial") != null:
		hold = hold or game.tutorial.hold
	get_tree().paused = hold
	# 배경음은 끄지 않는다. 산장 메뉴 안에서는 실내처럼, 그 밖의 정지 화면에서는 음량만 잠시 낮춘다.
	if game.sounds != null:
		var room: bool = lodge_panel.visible and not pause_panel.visible
		game.sounds.set_room(room, hold and not room)


func open_lodge_panel(tab: int = 0) -> void:
	if game.session.state != SessionScript.State.PREP or pause_panel.visible or end_panel.visible:
		return
	card_hand.close_all()
	lodge_tabs.current_tab = clampi(tab, 0, lodge_tabs.get_tab_count() - 1)
	lodge_panel.visible = true
	_refresh_shop()
	refresh_pause()
	game.sounds.play("panel_open")


func open_merc_panel() -> void:
	if merc_panel.visible or pause_panel.visible or end_panel.visible or game.session.is_over():
		return
	card_hand.close_all()
	merc_list.refresh()
	merc_panel.visible = true
	_recenter(merc_panel)
	game.sounds.play("panel_open")
	refresh_pause()


func close_merc_panel() -> void:
	if not merc_panel.visible:
		return
	merc_panel.visible = false
	game.sounds.play("panel_close")
	refresh_pause()


func close_lodge_panel() -> void:
	if not lodge_panel.visible:
		return
	lodge_panel.visible = false
	game.sounds.play("panel_close")
	refresh_pause()


func _toggle_pause() -> void:
	if end_panel.visible:
		return
	pause_panel.visible = not pause_panel.visible
	if pause_panel.visible:
		_recenter(pause_panel)
	game.sounds.play("pause")
	refresh_pause()


## 다시 도전: 같은 판을 처음부터. 도입이 열렸던 판이면 프롤로그 없이 새벽부터 다시 연다.
func _restart() -> void:
	Flow.opening = game.get("opening") != null
	Flow.prologue = false
	get_tree().paused = false
	get_tree().reload_current_scene.call_deferred()   # 누른 버튼의 효과음이 먼저 나가게 다음 프레임에 다시 연다


func _to_title() -> void:
	Flow.to_title(get_tree())


## 패배 원인별로 다음 판에 해 볼 행동 한 줄(첫 실행 플로우 점검 §6 P0-2).
static func defeat_hint(reason: String) -> String:
	if "산장" in reason:
		return "다음엔 — 낮에 손님을 고용하고, 받은 계약 카드를 산장 앞에 끌어 놓아 용병을 세우세요. 서리 룬·수호 등불은 괴물이 몰리는 산장 곁에 쓰세요."
	if "마녀" in reason:
		return "다음엔 — 마녀는 산장 곁에 머무세요(H 키). 괴물을 쫓아 숲 깊이·독 서식지로 들어가지 마세요. 낮에 산장 관리에서 마녀를 회복할 수 있습니다."
	return "다음엔 — 낮에 손님을 고용해 용병을 산장 앞에 세우세요."


func toast(text: String, color := Color.WHITE) -> void:
	# 알림음: 같은 순간 다른 효과음이 이미 울렸으면(대부분의 알림은 사건과 함께 뜬다) 겹쳐 울리지 않는다
	if game.sounds != null and game.sounds.quiet_for(250):
		var bad := color.r > color.g + 0.15 and color.r > color.b
		game.sounds.play("toast_bad" if bad else "toast_good")
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", MoonSkin.toast_box())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	p.add_child(row)
	var is_bad := color.r > color.g + 0.15 and color.r > color.b
	row.add_child(Extension.icon("warning" if is_bad else "check", 22))
	var l := _label(text, 17, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(l)
	toast_box.add_child(p)
	if toast_box.get_child_count() > 4:
		toast_box.get_child(0).queue_free()
	var tw := p.create_tween().set_ignore_time_scale(true)   # 손패 고민 시간으로 세상이 늦춰져도 알림은 실제 시간으로 사라진다
	tw.tween_interval(2.4)
	tw.tween_property(p, "modulate:a", 0.0, 0.6)
	tw.tween_callback(p.queue_free)


## 열린 창 밖(허공)을 클릭하면 맨 위 창부터 하나 닫는다. 창 안·HUD 버튼 클릭은 GUI가 먼저 받아 여기까지 오지 않는다.
## 지도 창은 띄워 둔 채 월드를 클릭해 움직이는 창이라 닫지 않는다.
func dismiss_top_modal() -> bool:
	if end_panel.visible:
		return false
	if pause_panel.visible:
		_toggle_pause()
	elif card_hand.sale_panel.visible:
		card_hand.close_sale()
	elif lodge_panel.visible:
		close_lodge_panel()
	elif merc_panel.visible:
		close_merc_panel()
	elif card_hand.pocket_panel.visible:
		card_hand.close_pocket()
	else:
		return false
	return true


func _unhandled_input(event: InputEvent) -> void:
	if game.guest_ui != null and game.guest_ui.dialogue_active: return
	if OutsideClick.is_press(event) and dismiss_top_modal():
		get_viewport().set_input_as_handled()
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		match k.keycode:
			KEY_ESCAPE:
				if lodge_panel.visible:
					close_lodge_panel()
				elif merc_panel.visible:
					close_merc_panel()
				elif card_hand.sale_panel.visible:
					card_hand.close_sale()
				elif card_hand.pocket_panel.visible:
					card_hand.close_pocket()
				else:
					_toggle_pause()
				get_viewport().set_input_as_handled()
			KEY_F1:
				debug_panel.visible = not debug_panel.visible
				get_viewport().set_input_as_handled()
			KEY_F2:
				var index := ScreenStyle.IDS.find(ScreenStyle.current_id)
				game.world.set_screen_style(ScreenStyle.IDS[(index+1)%ScreenStyle.IDS.size()])
				get_viewport().set_input_as_handled()
			KEY_F3:
				var index := CameraStyle.IDS.find(CameraStyle.current_id)
				game.world.set_camera_style(CameraStyle.IDS[(index+1)%CameraStyle.IDS.size()])
				get_viewport().set_input_as_handled()
			KEY_F4:
				game.world.player_camera.toggle_overview()
				get_viewport().set_input_as_handled()
			KEY_F5:
				var index := AirStyle.IDS.find(AirStyle.current_id)
				game.world.set_air_style(AirStyle.IDS[(index+1)%AirStyle.IDS.size()])
				get_viewport().set_input_as_handled()
			KEY_F6:
				if k.shift_pressed:
					var shape: String = game.world.cycle_grass_shape()
					if shape != "": toast("풀 모양: " + shape)
				else:
					var tone: String = game.world.cycle_grass_tone()
					if tone != "": toast("잔디 톤: " + tone)
				get_viewport().set_input_as_handled()
			KEY_F7:
				var hedge: String = game.world.cycle_yard_hedges()
				if hedge != "": toast("식생 구분선: " + hedge)
				get_viewport().set_input_as_handled()
			KEY_M:
				if not get_tree().paused:
					set_map_visible(not map_window.visible)
					get_viewport().set_input_as_handled()


func _on_state_changed(state: int) -> void:
	if state == SessionScript.State.VICTORY or state == SessionScript.State.DEFEAT:
		lodge_panel.visible = false
		merc_panel.visible = false
		pause_panel.visible = false
		card_hand.close_all()
		end_panel.visible = true
		var s = game.session
		var stats := "플레이 시간 %d:%02d  ·  번 골드 %dG  ·  잃은 양 %d마리" % [int(s.play_time) / 60, int(s.play_time) % 60, game.economy.total_earned, game.sheep_lost]
		var cs: Dictionary = game.cards.stats
		var ct: Dictionary = game.contracts.stats
		stats += "
고용 %d명 · 목재 %d · 양털 %d(판매 %d) · 괴물 카드 %d
남은 용병 %d · 무덤 %d기 · 시든 하수인 %d · 남은 카드 %d장
사냥 %d · 채집 %d · 벤 나무 %d그루 · 보물상자 %d · 유물 %d" % [cs["hired"], cs["timber"], cs["wool"], cs["wool_sold"], cs["monster"], game.contracts.mercs_alive(), game.world.graveyard.count(), ct["withered"], game.cards.entries.size(), cs["raw_meat"] + cs["rabbit_pelt"], ct["gathered"], ct["trees_felled"], cs["chests"], cs["relics"]]
		if state == SessionScript.State.VICTORY:
			end_title.text = "챕터 1 완료!"
			Extension.title(end_title, "victory_header")
			end_body.text = "%d일을 버텨 봉인석을 지켜 냈습니다. 산장의 창문은 오늘 밤도 따뜻합니다.\n\n" % s.total_days() + stats
			end_hint.text = ""
		else:
			end_title.text = "게임 오버"
			Extension.title(end_title, "defeat_header")
			end_body.text = "%s.\n(%d일차 밤 / %d)\n\n%s" % [s.defeat_reason, s.wave_index, s.total_days(), stats]
			end_hint.text = defeat_hint(s.defeat_reason)
		end_hint.visible = end_hint.text != ""
		_recenter(end_panel)
	if state != SessionScript.State.PREP:
		lodge_panel.visible = false
		refresh_pause()


func _process(_delta: float) -> void:
	if lodge_panel.visible:
		_refresh_shop()


## 관리창: 실제 가격·골드·체력·완료 여부(명세 §4.7). 판정·차감은 economy가 한다.
func _refresh_shop() -> void:
	var eco = game.economy
	lodge_gold.text = "보유 %dG" % eco.gold
	lodge_timber.text = "손패 목재 %d개 · 주머니 %d개" % [eco.timber(), game.cards.pocket_count_of("timber")]
	var lo = game.world.lodge
	var pl = game.player
	var pa = game.world.pasture
	var gy = game.world.graveyard
	var states := {
		"extension": "완료" if lo.extension_built else "정원 %d명" % eco.capacity,
		"pasture": "%d단계 · 양 최대 %d" % [pa.level + 1, pa.capacity()],
		"bunks": "용병 %d/%d명" % [eco.roster_count(), eco.bunk_capacity()],
		"graves": "무덤 %d/%d기" % [gy.count(), gy.capacity()],
		"repair": "산장 %d/%d" % [int(ceil(lo.hp)), int(lo.max_hp)],
		"heal": "마녀 %d/%d" % [int(ceil(pl.hp)), int(pl.max_hp)],
		"sheep": "양 %d/%d" % [pa.alive_count(), pa.capacity()],
	}
	for t in game.world.towers:
		var st := "빈 공터" if t.level == 0 else ("무너짐 %d단계" % t.level if t.collapsed else "%d단계 · 체력 %d/%d" % [t.level, int(ceil(t.hp)), int(t.max_hp)])
		if t.level < t.max_level():
			st += " · 목재 %d/%d" % [t.stock, t.stock_needed()]
		states["tower_" + t.site_id] = st
	for kind in shop_rows:
		var row: Dictionary = shop_rows[kind]
		var r: String = eco.block_reason(kind)
		row["button"].disabled = r != ""
		row["button"].text = eco.price_text(kind)
		row["reason"].text = r
		row["state"].text = states.get(kind, "")
	_refresh_contracts()


## 계약 탭: 계약한 용병(활동 중·미사용 카드)을 보고 해지한다. 해지하면 계약료의 절반을 돌려받는다.
func _build_contract_tab() -> void:
	var scroll := ScrollContainer.new()
	scroll.name = "계약"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lodge_tabs.add_child(scroll)
	lodge_contracts = VBoxContainer.new()
	lodge_contracts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lodge_contracts.add_theme_constant_override("separation", 8)
	scroll.add_child(lodge_contracts)


func _refresh_contracts() -> void:
	var eco = game.economy
	var list: Array = eco.contract_list()
	var key := ""
	for c in list:
		key += "%s:%s:%s;" % [c["kind"], c["person"], str(c.get("uid", c.get("ally").get_instance_id() if c.get("ally") else 0))]
	if key != _contract_key:
		_contract_key = key
		contract_rows.clear()
		for n in lodge_contracts.get_children():
			n.queue_free()
		var head := _label("데리고 있는 용병 %d명 / 침상 %d개 · 해지하면 계약료 %dG 중 %dG를 돌려받습니다" % [
			eco.roster_count(), eco.bunk_capacity(), Cfg.CONTRACT_COST, Cfg.CONTRACT_REFUND], 13, C_DIM)
		head.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lodge_contracts.add_child(head)
		if list.is_empty():
			lodge_contracts.add_child(_label("계약한 용병이 없습니다. 손님의 고용 제안을 받아 계약하세요.", 15, C_TEXT))
		for c in list:
			var row := PanelContainer.new()
			row.add_theme_stylebox_override("panel", MoonSkin.row_box())
			lodge_contracts.add_child(row)
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 12)
			row.add_child(h)
			var info := VBoxContainer.new()
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(info)
			var name_l := _label("%s · %s" % [c["person"], Cfg.JOB_NAMES.get(c["job"], "용병")], 18, C_TEXT)
			name_l.add_theme_font_override("font", MoonSkin.font(true))
			info.add_child(name_l)
			var status := _label("", 13, C_DIM)
			info.add_child(status)
			var btn := _button("해지 +%dG" % Cfg.CONTRACT_REFUND, 44)
			btn.custom_minimum_size.x = 150
			btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			btn.pressed.connect(func(): eco.dismiss_contract(c))
			h.add_child(btn)
			contract_rows.append({"c": c, "status": status, "button": btn})
	for r in contract_rows:
		var c: Dictionary = r["c"]
		var why: String = eco.dismiss_block_reason(c)
		r["button"].disabled = why != ""
		r["button"].tooltip_text = why
		if c["kind"] == "ally" and is_instance_valid(c["ally"]):
			r["status"].text = "활동 중 — " + c["ally"].status_text()
		else:
			r["status"].text = "미사용 계약 카드 (%s)" % ("손패" if game.cards.get_entry(int(c.get("uid", -1))).get("zone", "") == "hand" else "주머니")


# ───────────────────────── 체력 바 오버레이 ─────────────────────────

class HpOverlay extends Control:
	var game
	## world_marks: 월드에 붙는 표시(체력 바·이름표·모닥불 링)만 그린다. 이 인스턴스는 WorldMarks 층(4)에 놓여
	## 자원·양 말풍선(6)과 손님 도착(8)·HUD(10) 아래에 깔린다. false 면 화면 고정 표시(늑대 스킬 바·디버그)만 그린다.
	var world_marks := false

	var _drew_last := true

	func _process(_delta: float) -> void:
		if world_marks:
			queue_redraw()
			return
		# 화면 고정 층은 늑대 스킬·디버그가 있을 때만 그린다. 꺼진 직후 한 번 더 그려 마지막 그림을 지운다.
		var p = game.player
		var want: bool = game.world.debug_draw or (p != null and not p.dead and not game.session.is_over())
		if want or _drew_last:
			queue_redraw()
		_drew_last = want

	func _draw() -> void:
		var cam: Camera3D = game.world.camera
		if not world_marks:
			_draw_wolf_skills()
			if game.world.debug_draw:
				_draw_debug(cam)
			return
		if game.hud != null and not game.hud.visible:
			return   # 별도 층이라 HUD 를 숨겨도 따라 숨지 않으므로 직접 확인
		for n in get_tree().get_nodes_in_group("show_hp"):
			if not is_instance_valid(n) or n.dead:
				continue
			var is_enemy: bool = n.is_in_group("enemies")
			if game.world.fog_of_war != null and not game.world.fog_of_war.is_visible_at(n.global_position): continue
			var is_player: bool = n == game.player
			if not is_enemy and n.hp >= n.max_hp:
				continue
			var wp: Vector3 = n.global_position + Vector3(0, n.hp_offset, 0)
			if cam.is_position_behind(wp):
				continue
			var sp := cam.unproject_position(wp)
			var w := 44.0 if is_enemy else 54.0
			if n == game.world.lodge:
				w = 120.0
			var h := 6.0
			var frac := clampf(n.hp / n.max_hp, 0.0, 1.0)
			var col := Color(0.95, 0.35, 0.45)
			if is_player:
				col = Color(0.75, 0.6, 1.0)
			elif n == game.world.lodge:
				col = Color(1.0, 0.72, 0.4)
			elif n.is_in_group("sheep"):
				col = Color(0.95, 0.95, 0.85)
			elif n.is_in_group("allies"):
				col = Color(0.6, 1.0, 0.6)
			var r := Rect2(sp - Vector2(w * 0.5, 0), Vector2(w, h))
			Extension.draw_bar(self, r, frac, col)
		_draw_cards_world(cam)
		_draw_campfire_gauge(cam)

	## 플레이어 스킬 바(사용자 확정 2026-10-22): 화면 오른쪽 아래, 산장 관리 버튼 왼쪽 빈자리에 정렬한다.
	## 기준점은 달빛 UI 디자인 좌표(1600×800) SKILL_BAR_AT 를 오른쪽·아래 앵커로 붙여, 화면이 넓어져도 산장 관리 곁에 머문다.
	## 보름달 늑대: Q 할퀴기·E 덮치기(docs/wolf-blood-event-design.md §5). 마녀: Q 번개 일격 하나(아이콘 원화가 없으면 번개 문양).
	## 아이콘 원화(assets/ui/skills/)가 없으면 글자만 그린다.
	static var _skill_tex: Dictionary = {}
	const SKILL_BAR_AT := Vector2(1246.0, 732.0)   # 디자인 px, 물약 소품 오른끝(≈1182)과 산장 관리 버튼 왼끝(1315) 사이 가운데
	const SKILL_GAP := 62.0                         # 디자인 px, 늑대 스킬 두 개 사이 간격(둘 다 그 틈 안에 들어간다)

	## 스킬 묶음의 화면 가운데점(디자인 좌표 → 화면). 캡처·검증 스크립트가 같은 계산을 쓴다.
	static func skill_bar_center(view: Vector2) -> Vector2:
		return MoonLayout.to_view(SKILL_BAR_AT, Vector2(1, 1), view)

	func _draw_wolf_skills() -> void:
		var p = game.player
		if p == null or p.dead or game.session.is_over():
			return
		var ui := MoonLayout.ui_scale(size)
		var base := skill_bar_center(size)
		var font := get_theme_default_font()
		var skills := [["Q", "wolf_claw", p.claw_cd, Cfg.WOLF_CLAW_CD, "할퀴기"], ["E", "wolf_pounce", p.pounce_cd, Cfg.WOLF_POUNCE_CD, "덮치기"]]
		if not p.wolf:
			skills = [["Q", "witch_lightning", p.lightning_cd, Cfg.LIGHTNING_CD, "번개 일격"]]
		for i in skills.size():
			var s: Array = skills[i]
			var c := base + Vector2((i - (skills.size() - 1) * 0.5) * SKILL_GAP * ui, 0)
			var r := 27.0 * ui
			draw_circle(c, r + 4.0, Color(0.08, 0.05, 0.14, 0.85))
			draw_circle(c, r, Color(0.3, 0.2, 0.45, 1.0) if p.wolf else Color(0.1, 0.22, 0.42, 1.0))
			var tex = _skill_icon(s[1])
			if tex != null:
				draw_texture_rect(tex, Rect2(c - Vector2(r - 2.0, r - 2.0), Vector2(r - 2.0, r - 2.0) * 2.0), false)
			elif s[1] == "witch_lightning":
				var bolt := PackedVector2Array([Vector2(5, -17), Vector2(-7, 1), Vector2(1, 1), Vector2(-5, 17), Vector2(9, -3), Vector2(1, -3), Vector2(5, -17)])
				for k in bolt.size():
					bolt[k] = bolt[k] * ui + c
				draw_colored_polygon(bolt, Color(0.75, 0.97, 1.0))
				draw_polyline(bolt, Color(0.3, 0.8, 1.0), 2.0, true)
			var cd: float = s[2]
			if cd > 0.0:
				var frac: float = clampf(cd / s[3], 0.0, 1.0)
				draw_arc(c, r * 0.55, -PI * 0.5, -PI * 0.5 + TAU * frac, maxi(6, int(40 * frac)), Color(0.05, 0.03, 0.1, 0.78), r * 1.1, true)
				var t := "%.1f" % cd
				var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
				draw_string(font, c + Vector2(-w * 0.5, 5.0), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, C_TEXT)
			draw_arc(c, r + 1.5, 0.0, TAU, 40, Color(0.85, 0.7, 1.0, 0.9 if cd <= 0.0 else 0.35), 2.0, true)
			var key: String = s[0]
			var kw := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_circle(c + Vector2(r - 4.0, r - 4.0), 10.0, Color(0.95, 0.9, 1.0))
			draw_string(font, c + Vector2(r - 4.0 - kw * 0.5, r + 1.0), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.2, 0.1, 0.3))
			var label: String = tr(s[4])   # 직접 그리는 글자는 auto translate 를 거치지 않는다
			var lw := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
			draw_string(font, c + Vector2(-lw * 0.5, r + 20.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_DIM)

	func _skill_icon(id: String):
		if not _skill_tex.has(id):
			var path := "res://assets/ui/skills/%s.png" % id
			_skill_tex[id] = load(path) if ResourceLoader.exists(path) else null
		return _skill_tex[id]

	## 모닥불 연료 링(docs/resource-uses-expansion-v01.md v0.3): 마녀가 가까이 있거나 목재·생고기 카드를 들고 있을 때
	## 불 위에 꺼지기까지 남은 시간을 링으로 보여 준다. 채움 = 남은 연료 / 최대 연료, 목재를 넣으면 부드럽게 차오른다.
	func _draw_campfire_gauge(cam: Camera3D) -> void:
		var yard = game.world.yard
		if not campfire_gauge_visible():
			return
		var wp: Vector3 = yard.campfire.global_position + Vector3(0, 1.9, 0)
		if cam.is_position_behind(wp):
			return
		var c := cam.unproject_position(wp)
		var r := 17.0
		draw_circle(c, r + 5.0, Color(0.06, 0.04, 0.12, 0.72))
		draw_arc(c, r, 0.0, TAU, 40, Color(MoonSkin.CREAM, 0.22), 4.0, true)
		var ratio: float = yard.gauge_shown
		if ratio > 0.001:
			var col := Color8(240, 200, 116)
			if yard.fuel < Cfg.CAMPFIRE_FUEL_PER_TIMBER * 0.5:
				col = Color8(222, 86, 74)
			elif ratio < 0.5:
				col = Color8(232, 146, 72)
			draw_arc(c, r, -PI * 0.5, -PI * 0.5 + TAU * ratio, maxi(4, int(40 * ratio)), col, 4.0, true)
		var font := get_theme_default_font()
		var text := "%d" % int(ceil(yard.fuel)) if yard.is_lit() else tr("꺼짐")
		var fs := 12
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, c + Vector2(-w * 0.5, fs * 0.38), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT if yard.is_lit() else C_DIM)

	func campfire_gauge_visible() -> bool:
		var yard = game.world.yard
		if yard == null or yard.campfire == null or game.session.is_over():
			return false
		var hand = game.hud.card_hand if game.hud != null else null
		if hand != null and hand.drag_uid >= 0:
			var id: String = game.cards.get_entry(hand.drag_uid).get("id", "")
			if id == "timber" or id == "raw_meat":
				return true
		var p = game.player
		if p == null or p.dead:
			return false
		var d := Vector2(p.global_position.x - yard.campfire.global_position.x, p.global_position.z - yard.campfire.global_position.z).length()
		return d <= Cfg.CAMPFIRE_GAUGE_RANGE

	func _tag(cam: Camera3D, wp: Vector3, text: String, col: Color, size := 14) -> void:
		text = tr(text)
		if game.world.fog_of_war != null and not game.world.fog_of_war.is_visible_at(wp): return
		if cam.is_position_behind(wp):
			return
		var font := get_theme_default_font()
		var sp := cam.unproject_position(wp)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := sp + Vector2(-w * 0.5, 0)
		draw_style_box(Extension.world_tag(), Rect2(at + Vector2(-12, -size - 5), Vector2(w + 24, size + 13)))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

	## 용병 머리 위 문구: 이름과 짧은 상태만(직업·긴 설명은 용병 명부에서). 예: "한스 · 벌목 3초".
	static func ally_tag_text(a) -> String:
		var who: String = a.person if a.kind != "minion" and a.person != "" else a.display_name()
		var st: String = a.short_status()
		return who if st == "" else "%s · %s" % [who, st]

	## 틀 없이 작고 반투명한 글자(외곽선만). 용병처럼 늘 떠 있는 정보가 화면을 덮지 않게 한다.
	func _quiet_tag(cam: Camera3D, wp: Vector3, text: String) -> void:
		text = tr(text)
		if game.world.fog_of_war != null and not game.world.fog_of_war.is_visible_at(wp): return
		if cam.is_position_behind(wp):
			return
		var font := get_theme_default_font()
		var fs := 11
		var sp := cam.unproject_position(wp)
		var at := sp + Vector2(-font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x * 0.5, 0)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0.05, 0.03, 0.1, 0.55))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1.0, 0.93, 0.8, 0.78))

	## 카드와 연결된 월드 정보: 아군 임무·털 난 양·고용을 기다리는 손님·카드 표식 괴물.
	func _draw_cards_world(cam: Camera3D) -> void:
		for a in get_tree().get_nodes_in_group("allies"):
			if a.dead or a.hidden:
				continue
			_quiet_tag(cam, a.global_position + Vector3(0, a.hp_offset + 0.45, 0), ally_tag_text(a))
		if game.session.state == 0 and game.player.harvest_chain:
			_draw_harvest_chain(cam)
		elif game.session.state == 0:
			for s in game.world.pasture.slots:
				if s != null and not s.dead and s.wool_ready and not s.shearing 						and not (game.player.shearing and s.global_position.distance_to(game.player.global_position) < 1.6):
					_tag(cam, s.global_position + Vector3(0, 1.2, 0), "검은 털 수확" if s.is_black else "털 수확", Color(0.82, 0.68, 1.0) if s.is_black else Color(1.0, 0.97, 0.85), 13)
			_draw_shear_gauge(cam)
			for o in game.economy.offers:
				var g = o["guest"]
				if is_instance_valid(g):
					_tag(cam, g.global_position + Vector3(0, 2.1, 0), "%s · 고용 %dG" % [o["person"], game.economy.contract_cost()], Color(1.0, 0.82, 0.5), 14)
		for e in get_tree().get_nodes_in_group("enemies"):
			if not e.dead and e.card_drop != "":
				_tag(cam, e.global_position + Vector3(0, 2.35, 0), "처치 시 카드", Color(0.65, 1.0, 0.55), 13)

	## 연속 수확 중: 지금 깎으러 가는 양은 '수확 중', 남은 털 난 양은 깎을 순서(1, 2, …)를 머리 위에 띄운다.
	## 다른 양을 클릭하면 그 양이 바로 '수확 중'이 되고 번호가 다시 매겨진다. 깎다 만 양은 진행률을 함께 보여 준다.
	func _draw_harvest_chain(cam: Camera3D) -> void:
		var pl = game.player
		var cur = pl.harvest_target
		if cur != null and is_instance_valid(cur) and not (pl.shearing and cur.global_position.distance_to(pl.global_position) < 1.6):
			_tag(cam, cur.global_position + Vector3(0, 1.2, 0), "수확하러 가는 중", Color(1.0, 0.86, 0.45), 13)
		var n := 1
		for s in pl.harvest_plan():
			var label := "%d번째" % n
			if s.shear_progress > 0.0:
				label += " · %d%%" % int(round(s.shear_progress / Cfg.HARVEST_TIME * 100.0))
			_tag(cam, s.global_position + Vector3(0, 1.2, 0), label, Color(0.82, 0.68, 1.0) if s.is_black else Color(1.0, 0.97, 0.85), 13)
			n += 1
		_draw_shear_gauge(cam)

	## 털 깎기 진행: 마녀 머리 위의 작은 게이지.
	func _draw_shear_gauge(cam: Camera3D) -> void:
		var pl = game.player
		if not pl.shearing:
			return
		var wp: Vector3 = pl.global_position + Vector3(0, pl.hp_offset + 0.35, 0)
		if cam.is_position_behind(wp):
			return
		var sp := cam.unproject_position(wp)
		var w := 46.0
		var h := 7.0
		var frac := clampf(pl.harvest_t / Cfg.HARVEST_TIME, 0.0, 1.0)
		var r := Rect2(sp - Vector2(w * 0.5, 0), Vector2(w, h))
		Extension.draw_bar(self, r, frac, Color(1.0, 0.95, 0.78))
		draw_texture_rect(Extension.tex("scissors"), Rect2(sp + Vector2(-w * 0.5 - 24, -6), Vector2(20, 20)), false)

	func _draw_debug(cam: Camera3D) -> void:
		var lodge = game.world.lodge
		for p in lodge.attack_points:
			draw_circle(cam.unproject_position(p), 4.0, Color(1, 0.8, 0.2, 0.9))
		for e in get_tree().get_nodes_in_group("enemies"):
			var a := cam.unproject_position(e.global_position)
			var path: PackedVector3Array = e.agent.get_current_navigation_path()
			var prev := a
			for i in range(e.agent.get_current_navigation_path_index(), path.size()):
				var b := cam.unproject_position(path[i])
				draw_line(prev, b, Color(0.4, 1.0, 0.6, 0.7), 1.5)
				prev = b
			if e.path_failed:
				draw_circle(a, 9.0, Color(1, 0.1, 0.1, 0.8))
				draw_string(get_theme_default_font(), a + Vector2(10, -6), tr("경로 실패"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.4, 0.4))
