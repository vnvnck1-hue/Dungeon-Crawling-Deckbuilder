extends CanvasLayer
## 좌상단 말 걸기, 중앙 선택형 대화, 산장 손님·기록 탭. 도착 알림과 분리된 자발적 대화 UI.
const SkinUI := preload("res://scripts/ui/moon/moon_skin.gd")
const Layout := preload("res://scripts/ui/moon/moon_layout.gd")
const Presenter := preload("res://scripts/ui/guest_arrival.gd")
const Extension := preload("res://scripts/ui/moon/moon_extension.gd")
const OutsideClick := preload("res://scripts/ui/outside_click.gd")
const SpeechMedal := preload("res://scripts/ui/speech_medal.gd")
## 대화 조작부 배치(대화 패널 stage 좌표, 패널은 x 70~1200 · y 78~578)
const CONTROLS_SIZE := Vector2(1200, 760)
const REPLY_TOP := 596.0          # 패널 아래 '마녀의 대답' 머리글 줄
const CHOICE_X := 518.0           # 번호 칩이 대사 글 열(x 524)과 맞물리는 위치
const CHOICE_HEIGHT := 56.0
const CHOICE_GAP := 10.0
const CLOSE_AT := Vector2(1052, 104)  # 패널 안 오른쪽 위 구석
## 왼쪽 말 걸기 알림(사용자 선택 시안 03, 2026-10-22): 초상 메달 + 종이 말풍선(왼쪽 꼬리) + 진입 화살표. 이름·건수·막대 없음.
const NOTIFY_SIZE := Vector2(470, 160)
const MEDAL_CENTER := Vector2(78, 78)   # 메달 중심(알림 좌표). 시안 실측: 화면 왼쪽에서 96 = 알림 x 20 + 76
const BUBBLE_DY := 12.0                  # 말풍선 세로 중심은 메달 중심보다 이만큼 아래(시안 픽셀 실측 +3 화면px, 게임 -7 보정)
const MEDAL_BOX := 156.0                # 메달 컨트롤 한 변(바깥 테 지름 140 + 여유). 알림 버튼 안에 들어온다
const BUBBLE_X := 135.0                 # 말풍선 몸통 왼쪽 끝. 시안 픽셀 실측: 종이 면이 틀 놋쇠 가장자리와 거의 맞닿음(-1 화면px)
## 'side' 배치: 대화 패널을 오른쪽으로 SIDE_EXTEND 만큼 넓히고, 대사 글 열(x 524~1104) 오른쪽에 세로 대답 카드 두 장을 둔다.
const SIDE_EXTEND := 420.0        # 패널 x 70~1620
const SIDE_X := 1150.0
const SIDE_W := 430.0
const SIDE_TOP := 194.0           # 첫 카드 위쪽(머리글은 그 40 위). 카드 묶음이 패널 세로 가운데에 온다
const SIDE_CARD_H := 150.0
const SIDE_GAP := 18.0
## 선택지 배치: "side"(패널 오른쪽 열, 기본) · "below"(패널 아래 목록). 비교용으로 -- --choice-layout=below
var choice_layout := "side"
var game
var dialogue_active := false
var dialogue_phase := ""
var active_uid := -1
var selected_choice := ""
var transcript: Array = []
## 박자 진행(guest_story_arcs.gd 머리말): 이번 단계에 남은 박자, 지금 패널에 선 화자 id, 조건을 통과한 선택지 2개
var beat_queue: Array = []
var speaker_id := ""
var active_choices: Array = []
const THOUGHT_TINT := Color(0.80, 0.74, 0.97)   # 마녀의 생각(괄호 글)
const SCENE_TINT := Color(0.66, 0.84, 0.80)     # 장면 묘사(괄호 글)
var return_to_lodge := false
var notification_uid := -1
var root: Control
var notification: Button
var notify_medal: Control  # 초상 메달(speech_medal.gd): 둥근 초상 + 테두리를 따라 줄어드는 남은 시간 호
var notify_text: Label
var notify_name: Label
var notify_gauge: Control
var _talk_total: Dictionary = {}  # visit_uid → 알림이 처음 보였을 때 남아 있던 시간(게이지 100%)
var notify_bubble: PanelContainer
var badge: PanelContainer
var badge_text: Label
var presenter
var shade_layer: CanvasLayer
var shade: ColorRect
var controls_layer: CanvasLayer
var controls: Control
var buttons: Control
var next_button: ReplyRow
var choices: Control
var choice_buttons: Array[ReplyRow] = []
var close_button: Button
var guest_list: VBoxContainer
var guest_summary: Label
var history_list: VBoxContainer
var guest_buttons: Dictionary = {}
var pulse_age := 10.0
var pulse: Control
var _clock := 0.0
var _erin_drinks_seen := 0  # 에린 칸 술잔이 마지막으로 보여 준 잔 수(새로 찬 잔만 차오르는 연출)

func _ready() -> void:
	name = "GuestInteractions"
	layer = 16
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = SkinUI.make_theme()
	add_child(root)
	_build_notification()
	_build_dialogue()
	_build_hub()
	game.guest_events.changed.connect(_on_changed)
	game.guest_events.admitted.connect(func(_profile): pulse_age = 0.0)
	game.economy.gold_changed.connect(func(_gold): _sync_hub())
	game.economy.offers_changed.connect(_sync_hub)
	if game.get("tavern") != null:
		game.tavern.drinks_changed.connect(_sync_hub)
	game.session.state_changed.connect(func(state: int):
		if state != 0 and dialogue_active:
			return_to_lodge = false
			close_conversation(false))
	_on_changed()

func label_at(parent: Node, text: String, at: Rect2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at.position
	label.size = at.size
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label

func _build_notification() -> void:
	notification = Button.new()
	notification.name = "GuestSpeechNotification"
	notification.size = NOTIFY_SIZE
	notification.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "disabled"]:
		notification.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	notification.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	root.add_child(notification)
	# 초상 메달: 둥근 초상 + 테두리를 따라 줄어드는 '떠나기까지 남은 시간' 호(용병 메달의 체력 고리와 같은 문법)
	notify_medal = SpeechMedal.new()
	notify_medal.name = "SpeechMedal"
	notify_medal.position = MEDAL_CENTER - Vector2.ONE * MEDAL_BOX * 0.5
	notify_medal.size = Vector2.ONE * MEDAL_BOX
	notification.add_child(notify_medal)
	notify_gauge = notify_medal  # 남은 시간은 메달이 ratio 값으로만 들고 있다(테두리 게이지는 사용자 요청으로 뺌, 2026-10-22). 기존 검증 호환
	# 말풍선: 밝은 종이 몸통(승인 PNG 9분할, 없으면 평면 상자) + 메달을 가리키는 왼쪽 꼬리. 글 길이에 맞춰 스스로 커진다.
	notify_bubble = SpeechBubble.new()
	notify_bubble.position = Vector2(BUBBLE_X, 20)
	notify_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notify_bubble.add_theme_stylebox_override("panel", SpeechBubble.body_style())
	notification.add_child(notify_bubble)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 50)  # 시안처럼 꺾쇠는 글에서 떨어져 오른쪽 끝에(몸통 폭 실측 298 화면px)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notify_bubble.add_child(row)
	notify_text = Label.new()
	notify_text.add_theme_font_override("font", SkinUI.font(true))
	notify_text.add_theme_font_size_override("font_size", 23)  # 시안 픽셀 실측 글자 높이 22 화면px(게임 22pt 때 20)
	notify_text.add_theme_color_override("font_color", SkinUI.PAPER_INK)
	notify_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	notify_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(notify_text)
	# 오른쪽 끝 진입 화살표: 말풍선 전체가 클릭 대상임을 알리는 유일한 행동 표시
	# 컨테이너는 자식의 rotation 을 0 으로 되돌리므로 빈 Control 안에 넣어 돌린다
	var arrow_box := Control.new()
	arrow_box.custom_minimum_size = Vector2(19, 19) if Extension.tex("speech_chevron") != null else Vector2(24, 24)
	arrow_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	arrow_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(arrow_box)
	# 시안의 가는 꺾쇠(speech_chevron.png). 아직 없으면 승인 화살표 아이콘을 오른쪽으로 돌려 쓴다.
	var chevron := Extension.tex("speech_chevron") != null
	var arrow := Extension.icon("speech_chevron" if chevron else "arrow", 19 if chevron else 24)  # 시안 꺾쇠 높이 실측 17 화면px
	arrow.name = "EnterArrow"
	arrow.size = arrow_box.custom_minimum_size
	if not chevron:
		arrow.modulate = SkinUI.PAPER_INK
		arrow.pivot_offset = Vector2(12, 12)
		arrow.rotation = -PI * 0.5  # 승인 화살표 그림은 아래를 가리킨다. 오른쪽(진입)으로 돌린다
	arrow_box.add_child(arrow)
	# 이름·건수 줄은 시안 03 에 없다. 글은 툴팁·검증용으로만 채우고 그리지 않는다.
	notify_name = label_at(notification, "", Rect2(0, 0, NOTIFY_SIZE.x, 24), 15, SkinUI.CREAM)
	notify_name.visible = false
	notification.pressed.connect(func(): open_conversation(notification_uid))
	badge = PanelContainer.new()
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_stylebox_override("panel", Extension.box("badge", 40, Vector4(12, 12, 12, 12), Vector4(6, 4, 6, 4)))
	root.add_child(badge)
	badge_text = Label.new()
	badge_text.add_theme_font_override("font", SkinUI.font(true))
	badge_text.add_theme_font_size_override("font_size", 17)
	badge_text.add_theme_color_override("font_color", SkinUI.CREAM)
	badge_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.add_child(badge_text)
	pulse = ArrivalPulse.new()
	pulse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pulse)

func _build_dialogue() -> void:
	shade_layer = CanvasLayer.new()
	shade_layer.layer = 19
	add_child(shade_layer)
	shade = ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.025, 0.015, 0.055, 0.32)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	shade.visible = false
	shade.gui_input.connect(_on_shade_input)
	shade_layer.add_child(shade)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--choice-layout="): choice_layout = arg.trim_prefix("--choice-layout=")
	var side := choice_layout == "side"
	presenter = Presenter.new()
	presenter.presentation_only = true
	if side: presenter.panel_extend = SIDE_EXTEND
	presenter.game = game
	presenter.process_priority = -1  # 패널 시계를 먼저 올려 대답 버튼 잉크가 같은 프레임 위상으로 일렁이게
	add_child(presenter)
	presenter.progress.visible = false
	controls_layer = CanvasLayer.new()
	controls_layer.layer = 21
	add_child(controls_layer)
	controls = Control.new()
	controls.set_anchors_preset(Control.PRESET_FULL_RECT)
	controls.theme = SkinUI.make_theme()
	controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.visible = false
	controls_layer.add_child(controls)
	# 대화 조작부는 대화 패널(stage) 좌표계로 짜고 _layout_dialogue 에서 stage 와 같은 배율로 옮긴다.
	# below: 손님 패널 아래 '마녀의 대답' 목록. side: 패널 오른쪽 끝에 걸친 세로 대답 카드 두 장.
	buttons = Control.new()
	buttons.size = CONTROLS_SIZE
	buttons.mouse_filter = Control.MOUSE_FILTER_IGNORE
	controls.add_child(buttons)
	next_button = ReplyRow.new()
	next_button.compact = true
	next_button.size = Vector2(SIDE_W, 64) if side else Vector2(330, 58)
	next_button.home = Vector2(SIDE_X, SIDE_TOP + SIDE_CARD_H * 2 + SIDE_GAP - 64) if side else Vector2(CONTROLS_SIZE.x - 330, REPLY_TOP + 8)
	next_button.position = next_button.home
	next_button.pressed.connect(advance_dialogue)
	buttons.add_child(next_button)
	# 줄 사이 틈을 누르면 어두운 막(밖 클릭 = 닫기)으로 새지 않게 목록 전체가 입력을 받는다.
	choices = Control.new()
	choices.name = "WitchReplies"
	choices.position = Vector2(SIDE_X, SIDE_TOP - 40) if side else Vector2(CHOICE_X, REPLY_TOP)
	choices.size = Vector2(SIDE_W, 40 + SIDE_CARD_H * 2 + SIDE_GAP) if side else Vector2(CONTROLS_SIZE.x - CHOICE_X, CONTROLS_SIZE.y - REPLY_TOP)
	choices.mouse_filter = Control.MOUSE_FILTER_STOP
	buttons.add_child(choices)
	var heading := HBoxContainer.new()
	heading.position = Vector2(2, 0)
	heading.add_theme_constant_override("separation", 8)
	heading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choices.add_child(heading)
	var quill := Extension.icon("quill", 24)
	quill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	heading.add_child(quill)
	var heading_text := Label.new()
	heading_text.text = "마녀의 대답"
	heading_text.add_theme_font_override("font", SkinUI.font(true))
	heading_text.add_theme_font_size_override("font_size", 19)
	heading_text.add_theme_color_override("font_color", SkinUI.CREAM)
	heading_text.add_theme_color_override("font_outline_color", Color(SkinUI.INK, 0.9))
	heading_text.add_theme_constant_override("outline_size", 7)
	heading.add_child(heading_text)
	var keys_hint := Label.new()
	keys_hint.text = "숫자 키 · ↑↓"
	keys_hint.size = Vector2(240, 28)
	keys_hint.position = Vector2(choices.size.x - 244, 2)
	keys_hint.visible = not side  # side 에선 그 자리에 닫기 버튼이 온다
	keys_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	keys_hint.add_theme_font_size_override("font_size", 15)
	keys_hint.add_theme_color_override("font_color", SkinUI.CREAM_DIM)
	keys_hint.add_theme_color_override("font_outline_color", Color(SkinUI.INK, 0.85))
	keys_hint.add_theme_constant_override("outline_size", 6)
	keys_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	choices.add_child(keys_hint)
	for index in 2:
		var button := ReplyRow.new()
		button.key = str(index + 1)
		button.tall = side
		button.size = Vector2(SIDE_W, SIDE_CARD_H) if side else Vector2(choices.size.x, CHOICE_HEIGHT)
		button.home = Vector2(0, 40 + index * (SIDE_CARD_H + SIDE_GAP)) if side else Vector2(0, 36 + index * (CHOICE_HEIGHT + CHOICE_GAP))
		button.position = button.home
		var selected: int = index
		button.pressed.connect(func(): choose(selected))
		choices.add_child(button)
		choice_buttons.append(button)
	close_button = Button.new()
	close_button.text = "✕  Esc"
	close_button.tooltip_text = "대화를 접고 돌아가기"
	close_button.size = Vector2(118, 44)
	close_button.add_theme_font_size_override("font_size", 20)
	close_button.add_theme_color_override("font_color", SkinUI.CREAM_DIM)
	close_button.add_theme_color_override("font_hover_color", SkinUI.CREAM)
	for state in ["normal", "pressed", "disabled", "focus"]:
		close_button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	close_button.add_theme_stylebox_override("hover", SkinUI.flat(Color(SkinUI.INK_SOFT, 0.85), Color(SkinUI.CREAM, 0.25), 18, 8))
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.position = Vector2(70 + 1130 + SIDE_EXTEND - 148, 104) if side else CLOSE_AT
	if side:
		# 대사와 대답 열을 가르는 옅은 세로 금줄
		var divider := ColorRect.new()
		divider.color = Color8(197, 165, 116, 70)
		divider.position = Vector2(SIDE_X - 24, SIDE_TOP - 30)
		divider.size = Vector2(1, SIDE_CARD_H * 2 + SIDE_GAP + 30)
		divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
		buttons.add_child(divider)
		buttons.move_child(divider, 0)
	close_button.pressed.connect(func(): close_conversation(false))
	buttons.add_child(close_button)

func _build_hub() -> void:
	var target: VBoxContainer = game.hud.lodge_guests
	guest_summary = game.hud._label("", 17, SkinUI.CREAM)
	guest_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	target.add_child(guest_summary)
	guest_list = _scroll_list(target)
	history_list = _scroll_list(game.hud.lodge_history)

func _scroll_list(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 9)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	return list

func _clear(container: Node) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()

func _sync_hub() -> void:
	if guest_list == null: return
	_clear(guest_list)
	_clear(history_list)
	guest_buttons.clear()
	var guests: Array = game.guest_events.current_guests()
	guest_summary.text = "숙박 %d / 정원 %d명    ·    기다리는 대화 %d건" % [game.economy.guests_inside(), game.economy.capacity, game.guest_events.pending_events().size()]
	if guests.is_empty():
		var empty: Label = game.hud._label("아직 손님이 없습니다. 숲길을 따라 찾아올 손님을 기다려 보세요.", 16, SkinUI.LAVENDER)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		guest_list.add_child(empty)
	for entry in guests:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", SkinUI.row_box())
		guest_list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 13)
		row.add_child(h)
		var portrait := TextureRect.new()
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.texture = load(entry.profile.portrait)
		portrait.custom_minimum_size = Vector2(72, 94)
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(portrait)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var race_name: String = str(entry.profile.get("race_name", ""))
		info.add_child(game.hud._label(entry.profile.person + "  ·  " + (race_name + " " if race_name != "" else "") + entry.profile.role, 18, SkinUI.CREAM))
		var detail: Label = game.hud._label(entry.profile.detail, 14, SkinUI.LAVENDER)
		detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(detail)
		info.add_child(game.hud._label(entry.status + (" · 이야기하고 싶어 합니다" if entry.ready and not entry.read else ""), 14, SkinUI.TEAL))
		var tavern = game.get("tavern")
		if tavern != null and tavern.is_erin(entry) and tavern.erin_met:
			info.add_child(_erin_drink_row(tavern))
		var actions := VBoxContainer.new()
		h.add_child(actions)
		var talk: Button = game.hud._button("대화 완료" if entry.get("completed_this_visit", false) else ("안부 묻기" if entry.read else "이야기 듣기"), 40)
		talk.custom_minimum_size.x = 126
		if entry.profile.get("merchant", false): talk.text = "좌판 보기"
		var uid: int = entry.uid
		talk.disabled = not game.guest_events.can_talk(uid) or entry.get("completed_this_visit", false)
		talk.pressed.connect(func(): open_conversation(uid, true))
		actions.add_child(talk)
		guest_buttons[uid] = talk
		for offer in game.economy.offers:
			if is_instance_valid(offer.guest) and int(offer.guest.profile.get("visit_uid", -1)) == uid:
				var hire: Button = game.hud._button("고용 · %dG" % game.economy.contract_cost(), 36)
				hire.disabled = game.economy.hire_block_reason(offer) != ""
				hire.tooltip_text = game.economy.hire_block_reason(offer)
				hire.pressed.connect(func(): game.economy.hire(offer))
				actions.add_child(hire)
	if game.guest_events.history.is_empty():
		var empty: Label = game.hud._label("아직 나눈 이야기가 없습니다. 말풍선을 누르거나 손님 탭에서 대화를 시작하세요.", 16, SkinUI.LAVENDER)
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		history_list.add_child(empty)
	for record in game.guest_events.history.duplicate():
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", Extension.paper(18))
		history_list.add_child(panel)
		var list := VBoxContainer.new()
		panel.add_child(list)
		var heading := HBoxContainer.new()
		heading.add_child(Extension.icon("quill", 26))
		heading.add_child(game.hud._label("%d일차 · %s — %s" % [record.day, record.person, record.title], 18, SkinUI.PAPER_INK))
		list.add_child(heading)
		for line in record.transcript:
			var label: Label = game.hud._label(line, 15, SkinUI.PAPER_INK)
			label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			list.add_child(label)

## 산장 관리 · 에린 칸: 다음 에린 카드까지 쓴 술을 술잔 아이콘으로 센다. 방금 쓴 술의 잔은 차오르며 튀어 오른다.
func _erin_drink_row(tavern) -> Control:
	var total: int = tavern.ERIN_AT
	var filled: int = clampi(tavern.drinks, 0, total)
	var row := HBoxContainer.new()
	row.name = "ErinDrinkMeter"
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var meter := DrinkMeter.new()
	meter.setup(total, filled, filled - 1 if filled > _erin_drinks_seen else -1)
	row.add_child(meter)
	_erin_drinks_seen = filled
	var label: Label = game.hud._label("술 %d / %d  ·  다 채우면 에린 카드가 손패로" % [filled, total], 14, SkinUI.CREAM_DIM)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	row.tooltip_text = "술 카드를 %d장 쓸 때마다 에린이 '술 주정뱅이 에린' 카드를 손패에 넣어 줍니다" % total
	return row

func _on_changed() -> void:
	if dialogue_active:
		var entry: Dictionary = game.guest_events.visit(active_uid)
		if entry.is_empty() or not entry.present: close_conversation(false)
	_sync_hub()

func _available_for_notification() -> bool:
	var hud = game.hud
	# 가운데 펼침 화면(행상 좌판·장날·새벽 보상·보물상자·마법서·제단)이 열려 있으면 메달·말풍선을 숨긴다
	for ui_name in ["offer_ui", "chest_ui", "spellbook_ui", "altar_ui"]:
		var ui = game.get(ui_name)
		if ui != null and ui.active: return false
	return game.session.state == 0 and not dialogue_active and not (hud.pause_panel.visible or hud.lodge_panel.visible or hud.end_panel.visible or hud.debug_panel.visible or hud.card_hand.sale_panel.visible or hud.card_hand.pocket_panel.visible)

func _process(delta: float) -> void:
	_clock += delta
	var view := get_viewport().get_visible_rect().size
	var s := Layout.ui_scale(view)
	var pending: Array = game.guest_events.pending_events()
	notification.visible = not pending.is_empty() and _available_for_notification()
	if not pending.is_empty():
		var entry: Dictionary = pending[0]
		notification_uid = entry.uid
		notify_medal.set_portrait(entry.profile.get("medal_portrait", entry.profile.portrait))  # 메달 전용 컷아웃이 있으면 그것
		if notify_text.text != entry.story.prompt:
			notify_text.text = entry.story.prompt
		notify_bubble.reset_size()
		# 말풍선 세로 가운데(꼬리)가 메달 중심 높이에 오게 한다.
		notify_bubble.position = Vector2(BUBBLE_X, MEDAL_CENTER.y + BUBBLE_DY - notify_bubble.size.y * 0.5)
		# 클릭 범위(버튼)는 긴 첫마디로 넓어진 말풍선까지 덮는다
		notification.size = Vector2(maxf(NOTIFY_SIZE.x, BUBBLE_X + notify_bubble.size.x + 12.0), NOTIFY_SIZE.y)
		notify_name.text = entry.profile.person + " · " + ("좌판 보기" if entry.profile.get("merchant", false) else "이야기 듣기" if pending.size() == 1 else "대화 %d건" % pending.size())
		notification.tooltip_text = entry.profile.person + "와 대화 · " + entry.story.title
		var left: float = game.economy.guest_time_left(entry.uid)
		if left >= 0.0:
			var full: float = maxf(float(_talk_total.get(entry.uid, 0.0)), left)
			_talk_total[entry.uid] = full
			notify_medal.ratio = left / maxf(full, 0.01)
			notification.tooltip_text += "\n%d초 뒤 산장을 떠납니다" % int(ceil(left))
	var factor := 0.8 if not game.economy.offers.is_empty() else 1.0
	notification.scale = Vector2.ONE * s * factor
	notification.position = Vector2(18 * s, Layout.slot_rect("objective", view).end.y + 2 * s + sin(_clock * 1.4) * 1.5)  # 메달 테 위가 할 일 두루마리 아래 13px(시안 실측)
	var target: Rect2 = game.hud.moon.lodge_btn.get_global_rect()
	var count := 0
	for entry in game.guest_events.visits:   # current_guests() 와 같은 조건을 배열 없이 센다
		if entry.present and entry.admitted: count += 1
	badge.visible = count > 0
	badge_text.text = str(count) + (" !" if not pending.is_empty() else "")
	badge.position = target.position + Vector2(target.size.x * 0.74, target.size.y * 0.10)
	badge.scale = Vector2.ONE * s
	badge.size = Vector2(29, 29)
	var was_pulsing := pulse_age < 0.7
	pulse_age += delta
	pulse.position = target.get_center()
	pulse.set("age", pulse_age)
	# 고리는 0.7초 동안만 그린다. 그 뒤 한 번 더 그려 지우고는 다시 그리지 않는다.
	if was_pulsing:
		pulse.queue_redraw()
	if dialogue_active: _layout_dialogue()

func open_conversation(uid: int, from_hub := false) -> void:
	if dialogue_active or not game.guest_events.can_talk(uid) or game.session.is_over(): return
	var entry: Dictionary = game.guest_events.visit(uid)
	# 행상 브로크: 대화 대신 좌판(상점)을 연다(scripts/game/merchant.gd)
	if entry.profile.get("merchant", false):
		if game.get("merchant") != null: game.merchant.open_shop()
		return
	if entry.get("completed_this_visit", false):
		game.sounds.play("talk_open")
		return
	game.guest_events.prepare_talk(uid)  # 산장에 눌러앉은 에린: 말을 걸 때마다 다른 잡담
	# 대화가 열리면 알림음 대신 그 인물의 목소리
	game.sounds.voice(entry.profile, "talk_open")
	active_uid = uid
	return_to_lodge = from_hub or game.hud.lodge_panel.visible
	dialogue_active = true
	dialogue_phase = "opening"
	selected_choice = ""
	transcript = []
	speaker_id = ""
	beat_queue = _beats(entry, entry.story.opening)
	# 상황을 아는 첫마디(guest_situations.gd): 손님 이야기라면 어젯밤 일·산장 형편을 먼저 꺼낸다
	if entry.story.get("special", "") == "":
		beat_queue = game.guest_events.situation_beats(entry) + beat_queue
	game.hud.card_hand.close_all()
	game.hud.close_lodge_panel()
	game.hud.pause_panel.visible = false
	game.guest_arrival.root.visible = false
	notification.visible = false
	shade.visible = true
	controls.visible = true
	game.hud.refresh_pause()
	_show_next_beat()

## 박자 목록을 정리한다: 문자열은 이야기하는 손님의 말, 조건(if)이 안 맞거나 끼어들 손님이 없으면 뺀다.
func _beats(entry: Dictionary, raw) -> Array:
	var out: Array = []
	var main_id := str(entry.profile.get("character_id", ""))
	for beat in (raw if raw is Array else [raw]):
		var b: Dictionary = {"who": "", "text": beat} if beat is String else beat.duplicate()
		if not game.guest_events.cond_ok(b.get("if"), main_id): continue
		var who := str(b.get("who", ""))
		if who == main_id: b["who"] = ""
		elif who not in ["", "witch", "scene"]:
			var other: Dictionary = game.guest_events.present_profile(who, main_id)
			if other.is_empty(): continue
			b["profile"] = other
		out.append(b)
	return out

## 남은 박자 하나를 패널에 적는다. 화자가 바뀌면 초상·이름을 교차 전환하고, 생각·묘사는 지금 초상 그대로 괄호 글로 적는다.
func _show_next_beat() -> void:
	var entry: Dictionary = game.guest_events.visit(active_uid)
	var beat: Dictionary = beat_queue.pop_front()
	var who := str(beat.get("who", ""))
	var text := str(beat["text"])
	var tint := Color.WHITE
	var profile: Dictionary = entry.profile
	if who == "witch" or who == "scene":
		tint = THOUGHT_TINT if who == "witch" else SCENE_TINT
		text = "(" + text + ")"
		transcript.append(("마녀의 생각" if who == "witch" else "장면") + ": " + text.replace("\n", " "))
		if speaker_id != "":
			presenter.update_dialogue(text)
		else:
			speaker_id = str(entry.profile.get("character_id", ""))
			presenter.show_profile(entry.profile, text, entry.story.title)
	else:
		if beat.has("profile"): profile = beat["profile"]
		var id := str(profile.get("character_id", ""))
		transcript.append(str(profile.person) + ": " + text.replace("\n", " "))
		if speaker_id == "":
			presenter.show_profile(profile, text, entry.story.title)
		elif id != speaker_id:
			presenter.swap_speaker(profile, text, entry.story.title)
		else:
			presenter.update_dialogue(text)
			game.sounds.voice(profile)
		speaker_id = id
	presenter.set_dialogue_tint(tint)
	_show_dialogue()

func _show_dialogue() -> void:
	next_button.visible = dialogue_phase != "choices"
	choices.visible = dialogue_phase == "choices"
	next_button.text = "다음" if not beat_queue.is_empty() else {"opening": "대답하기", "reply": "이야기 이어 듣기", "closing": "대화 마치기"}.get(dialogue_phase, "다음")
	if dialogue_phase != "choices":
		next_button.play_enter(0.35)
		next_button.grab_focus()
	_layout_dialogue()

func advance_dialogue() -> void:
	if not dialogue_active: return
	# 대사를 아직 적는 중이면 먼저 남은 글을 마저 적는다(한 번 더 눌러야 넘어간다).
	if presenter.is_writing():
		presenter.finish_writing()
		return
	game.sounds.play("talk_next")
	var entry: Dictionary = game.guest_events.visit(active_uid)
	if not beat_queue.is_empty():
		_show_next_beat()
		return
	match dialogue_phase:
		"opening":
			dialogue_phase = "choices"
			next_button.visible = false
			choices.visible = true
			# 조건(if)을 통과한 선택지 중 앞의 2개
			active_choices = entry.story.choices.filter(func(c): return game.guest_events.cond_ok(c.get("if"), str(entry.profile.get("character_id", "")))).slice(0, choice_buttons.size())
			# 대답 줄이 위에서부터 차례로 스며 나온다. 첫 줄에 포커스를 두되 아직 고르지는 않는다.
			for i in choice_buttons.size():
				choice_buttons[i].set_line(active_choices[i].text)
				choice_buttons[i].play_enter(0.06 + i * 0.09)
			choice_buttons[0].grab_focus()
		"reply":
			dialogue_phase = "closing"
			beat_queue = _beats(entry, entry.story.closing)
			if beat_queue.is_empty(): close_conversation(true)
			else: _show_next_beat()
		"closing":
			close_conversation(true)

func choose(index: int) -> void:
	if not dialogue_active or dialogue_phase != "choices" or index < 0 or index > 1: return
	game.sounds.play("talk_next")
	var entry: Dictionary = game.guest_events.visit(active_uid)
	var branch: Dictionary = active_choices[index] if index < active_choices.size() else entry.story.choices[index]
	selected_choice = branch.text
	transcript.append("마녀: " + branch.text)
	# 효과가 있는 선택지(늑대의 피): 검은 양을 내주고 카드를 받는다. 그사이 양이 없어졌으면 실패 대사
	var reply = branch.reply
	if branch.has("effect") and not game.guest_events.apply_effect(active_uid, branch.effect):
		reply = branch.get("fail_reply", branch.reply)
	# "이 일은 기억될 것이다"(펜티먼트): 연작이 다음 편·재방문 인사에서 이 대답을 꺼낸다
	if branch.has("remember"):
		game.guest_events.remember(str(branch.remember))
		game.toast("✎ %s의 기억에 남았다" % str(entry.profile.person), Color(0.86, 0.80, 1.0))
	dialogue_phase = "reply"
	beat_queue = _beats(entry, reply)
	_show_next_beat()

func _layout_dialogue() -> void:
	var stage: Control = presenter.stage
	var s: float = stage.scale.x
	buttons.position = stage.position
	buttons.scale = Vector2.ONE * s
	# 버튼 잉크 바탕이 뒤 패널과 같은 시계·좌표로 일렁이게
	var frame := Rect2(Presenter.PANEL_RECT.position, Presenter.PANEL_RECT.size + Vector2(presenter.panel_extend, 0))
	for row: ReplyRow in [next_button] + choice_buttons:
		if not row.is_visible_in_tree(): continue
		row.panel_frame = frame
		row.stage_offset = choices.position if row.get_parent() == choices else Vector2.ZERO
		row.sync_ink(presenter.clock)

func close_conversation(completed: bool) -> void:
	if not dialogue_active: return
	game.sounds.play("talk_open")
	var reopen: bool = return_to_lodge and game.session.state == 0 and not game.session.is_over()
	dialogue_active = false
	shade.visible = false
	controls.visible = false
	presenter.finish()
	game.guest_arrival.root.visible = game.guest_arrival.active
	if completed: game.guest_events.complete(active_uid, selected_choice, transcript)
	active_uid = -1
	dialogue_phase = ""
	if reopen: game.hud.open_lodge_panel(1)
	else: game.hud.refresh_pause()
	_sync_hub()

## 대화창(초상·글 패널)·버튼 밖의 어두운 막을 클릭하면 '돌아가기'처럼 닫는다.
func _on_shade_input(event: InputEvent) -> void:
	if dialogue_active and OutsideClick.is_press(event) and not presenter._panel_hit(event.position):
		shade.accept_event()
		close_conversation(false)

func _input(event: InputEvent) -> void:
	if not dialogue_active or not event is InputEventKey: return
	if event.keycode == KEY_F11: return
	if event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE: close_conversation(false)
		elif dialogue_phase == "choices" and event.keycode in [KEY_1, KEY_2, KEY_KP_1, KEY_KP_2]:
			choose(1 if event.keycode in [KEY_2, KEY_KP_2] else 0)
		elif dialogue_phase == "choices":
			var selected := choice_buttons.find(get_viewport().gui_get_focus_owner())
			if event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
				choose(maxi(selected, 0))
			elif event.keycode in [KEY_TAB, KEY_DOWN, KEY_RIGHT, KEY_UP, KEY_LEFT]:
				var direction := -1 if event.keycode in [KEY_UP, KEY_LEFT] or (event.keycode == KEY_TAB and event.shift_pressed) else 1
				choice_buttons[posmod(selected + direction, choice_buttons.size())].grab_focus()
		elif event.keycode in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
			advance_dialogue()
	get_viewport().set_input_as_handled()

## '마녀의 대답' 한 줄: 왼쪽 번호 칩 + 왼쪽 정렬 대사. 포커스(마우스를 올려도 포커스가 따라온다)된 줄만
## 베이지 바탕·▸ 표시로 떠오르고 나머지는 보랏빛 딤드로 가라앉아, 지금 고를 줄이 한눈에 보인다.
## compact 는 번호 없이 오른쪽에 놓이는 '다음' 줄이다.
## 바탕은 정적인 상자가 아니라 뒤 대화 패널과 같은 일렁임 공식 위에 액체 노이즈를 얹은 셰이더(guest_ink_button)로 그린
## 둥근 색 덩어리다. 버튼마다 seed 가 달라 서로 따로 불규칙하게 울렁인다.
class ReplyRow extends Button:
	const InkButton := preload("res://shaders/guest_ink_button.gdshader")
	const INK_PAD := 32.0       # 셰이더 그림 여유(울렁임이 잘리지 않게)
	const NAME_CREAM := Color8(250, 230, 188)  # 포커스(호버) 바탕 = 대화창 손님 이름 글자색(베이지)
	const DIM_PLUM := Color8(62, 44, 78)       # 평소 바탕: 패널 위에 가라앉은 보랏빛 딤드
	const INK_TEXT := Color8(48, 30, 44)       # 베이지 바탕 위 글·번호(종이 잉크)
	const DIM_TEXT := Color8(196, 180, 210)    # 딤드 바탕 위 글·번호
	const STATES := ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]
	var key := ""
	var compact := false
	var tall := false    # side 배치의 세로 카드: 글이 여러 줄로 감기고 바탕이 패널보다 한 톤 밝다
	var line := ""       # 원문 대답(줄바꿈 전)
	var lit := 0.0       # 0 평소 → 1 포커스
	var enter := 1.0     # 등장 0 → 1
	var _delay := 0.0
	var _clock := 0.0
	var home := Vector2.ZERO  # 배치된 자리. 등장·포커스 때 이 자리에서 가로로만 밀린다.
	var panel_frame := Rect2(70, 78, 1550, 500)  # 대화 패널(stage 좌표). 셰이더 일렁임을 패널과 맞춘다
	var stage_offset := Vector2.ZERO              # 이 버튼 부모의 stage 좌표 위치
	var _ink: ColorRect     # 잉크 바탕 + 테두리
	var _shadow: ColorRect  # tall 카드 아래 옅은 잉크 그림자
	var _art: Control  # 바탕·칩은 글자 뒤(show_behind_parent)에서 그린다. Button 의 _draw 는 글 위에 덮인다.

	func _init() -> void:
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		clip_text = true
		add_theme_font_override("font", preload("res://scripts/ui/moon/moon_skin.gd").font(true))
		mouse_entered.connect(func(): if not disabled: grab_focus())
		_shadow = _make_ink()
		_shadow.name = "InkShadow"
		_ink = _make_ink()
		_ink.name = "InkBack"
		_art = Control.new()
		_art.show_behind_parent = true
		_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_art.set_anchors_preset(Control.PRESET_FULL_RECT)
		_art.draw.connect(_paint)
		add_child(_art)

	func _make_ink() -> ColorRect:
		var rect := ColorRect.new()
		rect.show_behind_parent = true
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var mat := ShaderMaterial.new()
		mat.shader = InkButton
		mat.set_shader_parameter("pad_px", INK_PAD)
		mat.set_shader_parameter("radius_px", 52.0) # 큰 둥근 덩어리
		mat.set_shader_parameter("bump_px", 5.5)    # 둘레가 큼직하게 울렁이는 크기
		mat.set_shader_parameter("wobble", 0.45)    # 패널 천 일렁임 대비 비율
		mat.set_shader_parameter("border_color", Color(0, 0, 0, 0))  # 테두리 없이 덩어리 색만
		rect.material = mat
		add_child(rect)
		return rect

	## 패널과 같은 시계·좌표로 잉크 바탕을 맞춘다(대화 중 매 프레임).
	func sync_ink(clock: float) -> void:
		for rect: ColorRect in [_shadow, _ink]:
			var at := Vector2(-6, 10) if rect == _shadow else Vector2.ZERO
			rect.position = at - Vector2.ONE * INK_PAD
			rect.size = size + Vector2.ONE * INK_PAD * 2.0
			var mat := rect.material as ShaderMaterial
			mat.set_shader_parameter("motion_time", clock)
			mat.set_shader_parameter("rect_size", rect.size)
			mat.set_shader_parameter("panel_origin", stage_offset + position + rect.position - panel_frame.position)
			mat.set_shader_parameter("panel_size", panel_frame.size)
			# 버튼마다 다른 흐름(번호·종류로 정한 고정 seed) → 두 버튼이 서로 따로 불규칙하게 울렁인다
			mat.set_shader_parameter("seed", 7.3 if compact else 1.0 + 3.1 * float(key.to_int()))

	func _ready() -> void:
		alignment = HORIZONTAL_ALIGNMENT_CENTER if compact else HORIZONTAL_ALIGNMENT_LEFT
		for state in STATES:
			var box := StyleBoxEmpty.new()
			box.content_margin_left = 22.0 if compact else 66.0
			box.content_margin_right = 44.0
			add_theme_stylebox_override(state, box)
		add_theme_font_size_override("font_size", 22 if compact else (24 if tall else 23))
		if tall: clip_text = false
		_shadow.visible = false  # 덩어리 색만으로 떠 보이게(레퍼런스엔 그림자가 없다)
		if compact:
			# 얇은 '다음' 줄(높이 64): 울렁임을 높이에 맞춰 줄이고 양 끝은 둥근 알약처럼
			var ink_mat := _ink.material as ShaderMaterial
			ink_mat.set_shader_parameter("wobble", 0.25)
			ink_mat.set_shader_parameter("bump_px", 2.6)
			ink_mat.set_shader_parameter("radius_px", 30.0)
		var shadow_mat := _shadow.material as ShaderMaterial
		shadow_mat.set_shader_parameter("fill_color", Color(0, 0, 0, 0.35))
		shadow_mat.set_shader_parameter("border_color", Color(0, 0, 0, 0))
		sync_ink(0.0)
		_apply_colors()

	## 대답 문구를 건다. 세로 카드는 띄어쓰기에서만 줄을 바꾼다(한글 단어 중간이 잘리지 않게).
	func set_line(value: String) -> void:
		line = value
		if not tall:
			text = value
			return
		var font: Font = get_theme_font("font")
		var font_size := get_theme_font_size("font_size")
		var box := get_theme_stylebox("normal")
		var room := size.x - box.content_margin_left - box.content_margin_right - 4.0
		var lines: Array[String] = []
		var current := ""
		for word in value.split(" ", false):
			var candidate: String = word if current.is_empty() else current + " " + word
			if not current.is_empty() and font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > room:
				lines.append(current)
				candidate = word
			current = candidate
		if not current.is_empty(): lines.append(current)
		text = "\n".join(lines)

	func play_enter(delay: float) -> void:
		enter = 0.0
		_delay = delay
		_clock = 0.0
		lit = 0.0
		modulate.a = 0.0
		_apply_colors()
		_art.queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree(): return
		var changed := false
		if enter < 1.0:
			_clock += delta
			enter = clampf((_clock - _delay) / 0.28, 0.0, 1.0)
			modulate.a = enter
			changed = true
		var goal := 1.0 if has_focus() else 0.0
		if not is_equal_approx(lit, goal):
			lit = move_toward(lit, goal, delta * 7.0)
			changed = true
		if changed:
			_apply_colors()
			# 등장할 때 왼쪽에서 살짝 밀려 들어오고, 포커스되면 6px 앞으로 나온다(글과 칩이 함께 움직인다).
			position = home + Vector2((1.0 - (1.0 - pow(1.0 - enter, 3.0))) * -18.0 + lit * 6.0, 0)
			_art.queue_redraw()

	func _apply_colors() -> void:
		for color_name in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			add_theme_color_override(color_name, text_color())
		# 바탕: 평소엔 보랏빛 딤드, 마우스를 올리면(포커스) 손님 이름과 같은 베이지. 테두리 없이 색 덩어리만
		var mat := _ink.material as ShaderMaterial
		mat.set_shader_parameter("fill_color", Color(DIM_PLUM.lerp(NAME_CREAM, lit), 0.95))

	func text_color() -> Color:
		return DIM_TEXT.lerp(INK_TEXT, smoothstep(0.3, 0.7, lit))

	func _paint() -> void:
		var canvas := _art
		var r := Rect2(Vector2.ZERO, size)
		var font: Font = get_theme_font("font")
		if lit > 0.01:
			canvas.draw_string(font, Vector2(r.end.x - 32, r.size.y * 0.5 + 8), "▸", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(INK_TEXT, lit))
		if compact: return
		# 번호 칩: 평소엔 글자색 테두리만, 포커스되면 짙은 잉크로 채워지고 숫자가 베이지가 된다.
		var c := Vector2(r.position.x + 34, r.size.y * 0.5)
		if lit > 0.01: canvas.draw_circle(c, 15.0, Color(INK_TEXT, lit))
		canvas.draw_arc(c, 15.0, 0, TAU, 32, Color(text_color(), 0.6 + 0.4 * lit), 1.6, true)
		var w := font.get_string_size(key, HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
		canvas.draw_string(font, c + Vector2(-w * 0.5, 7), key, HORIZONTAL_ALIGNMENT_LEFT, -1, 19, text_color().lerp(NAME_CREAM, lit))

## 말 걸기 말풍선. 몸통은 시안과 같은 양피지 PNG speech_paper(v02, 9분할) → 없으면 v01 speech_plain → 없으면 평면 상자.
## 왼쪽 꼬리는 speech_paper_tail(v02) → speech_tail_left(v01) → 다각형. 꼬리 그림의 오른쪽 36px 은 외곽선 없는
## 종이 면이라 몸통 왼쪽 선 위에 겹쳐 하나로 이어진다(docs/handoff/codex-speech-notification-v02.md).
class SpeechBubble extends PanelContainer:
	const Ext := preload("res://scripts/ui/moon/moon_extension.gd")
	const PAPER := Color8(246, 232, 198)
	const LINE := Color8(58, 34, 64)
	## v02 그림은 시안의 3배 해상도(몸통 768×256 = 시안 말풍선 약 85px 높이의 3배)라 1/3 로 줄여 쓴다.
	const V02_SCALE := 1.0 / 3.0
	const TAIL_SCALE := 0.42    # 꼬리는 시안 실측(길이 28 화면px)에 맞춰 몸통보다 조금 크게
	const TAIL := Vector2(96, 96)
	const TAIL_OVERLAP := 52.0   # v01 꼬리: 그림의 x=60(종이 면 시작)이 몸통 x=8(선 안쪽)에 오게
	var v02: bool = Ext.tex("speech_paper_tail") != null
	var tail: Texture2D = Ext.tex("speech_paper_tail") if v02 else Ext.tex("speech_tail_left")

	static func body_style() -> StyleBox:
		if Ext.tex("speech_paper") != null:
			# 768 → 256 으로 줄이면 9분할 여백 40px 은 14px, 먹선·글로우도 시안과 같은 두께가 된다
			return Ext.box("speech_paper", 256, Vector4(14, 14, 14, 14), Vector4(38, 26, 19, 26))  # 시안 픽셀 실측 보정: 왼 +4 · 오른 -3 · 높이 +6
		if Ext.tex("speech_plain") != null:
			return Ext.box("speech_plain", 512, Vector4(48, 48, 48, 48), Vector4(30, 14, 26, 14))
		var b := StyleBoxFlat.new()
		b.bg_color = PAPER
		b.border_color = LINE
		b.set_border_width_all(4)
		b.set_corner_radius_all(20)
		b.content_margin_left = 30
		b.content_margin_right = 26
		b.content_margin_top = 14
		b.content_margin_bottom = 14
		return b

	## 꼬리는 그림 위에 그려 몸통의 왼쪽 선을 덮는다(스크립트 _draw 는 PanelContainer 바탕 뒤에 호출된다).
	func _draw() -> void:
		var cy := size.y * 0.5
		if tail != null and v02:
			# 32px 로 줄인 꼬리. 그림의 x=60(종이 면 시작, 1/3 배로 20)이 몸통 x=2(선 안쪽)에 오게
			var sz := TAIL * TAIL_SCALE
			draw_texture_rect(tail, Rect2(Vector2(3.0 - 60.0 * TAIL_SCALE, cy - 6.0 - sz.y * 0.5), sz), false)  # 시안: 꼬리는 가운데보다 6px 위
			return
		if tail != null:
			draw_texture_rect(tail, Rect2(Vector2(-TAIL_OVERLAP, cy - TAIL.y * 0.5), TAIL), false)
			return
		var tip := Vector2(-46, cy)
		var a := Vector2(14, cy - 15)
		var b := Vector2(14, cy + 15)
		draw_colored_polygon(PackedVector2Array([tip, a, b]), PAPER)
		draw_polyline(PackedVector2Array([a, tip, b]), LINE, 4.0, true)

class ArrivalPulse extends Control:
	var age := 10.0
	func _draw() -> void:
		if age >= 0.7: return
		var t := age / 0.7
		draw_arc(Vector2.ZERO, 22.0 + t * 52.0, 0, TAU, 48, Color(0.95, 0.8, 0.5, 1.0 - t), 3.0, true)

## 에린 칸의 술잔 카운터: 빈 잔은 어두운 유리, 찬 잔은 호박빛 에일과 거품. 찬 잔은 살짝 흔들리고,
## 방금 찬 잔(pop_index)은 술이 차오르며 한 번 튀어 오른다.
class DrinkMeter extends Control:
	const MUG := Vector2(30, 36)
	const GAP := 8.0
	const GLASS := Color(0.09, 0.06, 0.15, 0.55)
	const EDGE_EMPTY := Color(0.78, 0.72, 0.62, 0.55)
	const EDGE_FULL := Color(0.96, 0.78, 0.42)
	const ALE := Color(0.93, 0.62, 0.18)
	const ALE_DEEP := Color(0.74, 0.40, 0.10)
	const FOAM := Color(0.99, 0.95, 0.84)
	var total := 3
	var filled := 0
	var pop_index := -1
	var _t := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func setup(n: int, k: int, pop: int) -> void:
		total = n
		filled = k
		pop_index = pop
		custom_minimum_size = Vector2(n * MUG.x + (n - 1) * GAP + 10.0, MUG.y + 10.0)
		queue_redraw()

	func _process(delta: float) -> void:
		_t += delta
		if filled > 0 or pop_index >= 0:   # 빈 잔뿐이면 움직이는 것(흔들림·기포·차오름)이 없다
			queue_redraw()

	func _draw() -> void:
		for i in total:
			var full := i < filled
			var level := 1.0 if full else 0.0
			var grow := 1.0
			if i == pop_index:
				var k := clampf(_t / 0.7, 0.0, 1.0)
				level = k
				grow = 1.0 + 0.28 * sin(k * PI)
			var sway := sin(_t * 2.4 + i * 1.3) * 0.07 if full else 0.0
			draw_set_transform(Vector2(5.0 + i * (MUG.x + GAP) + 13.0, 6.0 + MUG.y), sway, Vector2.ONE * grow)
			_mug(level, full)
		draw_set_transform(Vector2.ZERO)

	## 바닥 가운데를 원점으로 한 맥주잔 하나(몸통 22×28, 오른쪽 손잡이).
	func _mug(level: float, full: bool) -> void:
		var body := Rect2(-11, -28, 22, 28)
		draw_rect(body, GLASS)
		if level > 0.0:
			var h := 25.0 * level
			draw_rect(Rect2(-9, -2 - h, 18, h), ALE)
			draw_rect(Rect2(-9, -2 - h * 0.35, 18, h * 0.35), ALE_DEEP)
			if level > 0.85:
				for c in [Vector3(-6, -27, 4.5), Vector3(0, -29, 5.5), Vector3(6, -27, 4.5)]:
					draw_circle(Vector2(c.x, c.y), c.z, FOAM)
			# 기포 두 알이 천천히 오른다
			for b in 2:
				var y := -4.0 - fmod(_t * 9.0 + b * 11.0, maxf(h - 4.0, 1.0))
				draw_circle(Vector2(-3 + b * 6, y), 1.3, Color(FOAM, 0.7))
		var edge := EDGE_FULL if full or level > 0.0 else EDGE_EMPTY
		draw_rect(body, edge, false, 2.5)
		draw_arc(Vector2(11, -14), 7.0, -PI * 0.5, PI * 0.5, 12, edge, 3.0, true)
		draw_line(Vector2(-13, 0), Vector2(13, 0), edge, 2.5)
