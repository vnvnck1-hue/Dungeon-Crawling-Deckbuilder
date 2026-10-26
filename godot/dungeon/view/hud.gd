extends Control
## 화면 위 글자·막대: 유닛 머리 위 체력·방어·상태·적 의도, 손패 위 캐릭터 패널(체력·행동력), 방 이름·턴, 턴 종료 버튼,
## 가운데 배너, 원정대 선택 화면, 승패 화면. 표시 전용 — 게임 상태는 main.gd 가 넣어 준다.

const CardFace := preload("res://scripts/ui/card_face.gd")
const D := preload("res://dungeon/data/defs.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

signal end_turn_pressed
signal start_pressed(heroes: Array)
signal restart_pressed

const INK := Color(0.08, 0.04, 0.13)
const CREAM := Color(1.0, 0.94, 0.8)
const GOLD := Color(1.0, 0.82, 0.42)
const ALLY_HP := Color(0.55, 0.92, 0.45)
const ENEMY_HP := Color(0.95, 0.3, 0.32)
const BLOCK := Color(0.45, 0.78, 1.0)

var bars: Dictionary = {}          # unit id → {root, fill, back, hp, block, status, intent}
var panels: Dictionary = {}        # hero kind → {root, name, hp, fill, pips, move}
var top_label: Label
var turn_label: Label
var hint_label: Label
var end_button: Button
var banner: Label
var _select_root: Control
var _result_root: Control
var _picked: Array = []


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_label = _label(26, CREAM)
	top_label.position = Vector2(24, 16)
	turn_label = _label(20, GOLD)
	turn_label.position = Vector2(26, 52)
	hint_label = _label(18, CREAM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_button = Button.new()
	end_button.text = "턴 종료"
	end_button.add_theme_font_override("font", CardFace.font())
	end_button.add_theme_font_size_override("font_size", 22)
	end_button.size = Vector2(150, 52)
	end_button.focus_mode = Control.FOCUS_NONE
	_style_button(end_button, Color(0.36, 0.2, 0.6))
	end_button.pressed.connect(func() -> void: end_turn_pressed.emit())
	add_child(end_button)
	banner = _label(54, CREAM)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.modulate.a = 0.0


func _label(size_px: int, col: Color, parent: Node = null) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", CardFace.font())
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", maxi(4, size_px / 4))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	(parent if parent != null else self).add_child(l)
	return l


func _style_button(b: Button, col: Color) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = col.lightened(0.15 if state == "hover" else 0.0).darkened(0.25 if state == "pressed" else 0.0)
		if state == "disabled":
			sb.bg_color = Color(0.22, 0.2, 0.28)
		sb.border_color = GOLD if state != "disabled" else Color(0.4, 0.38, 0.45)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(14)
		sb.shadow_color = Color(0, 0, 0, 0.4)
		sb.shadow_size = 4
		b.add_theme_stylebox_override(state, sb)
	b.add_theme_color_override("font_color", CREAM)
	b.add_theme_color_override("font_disabled_color", Color(0.6, 0.58, 0.66))
	b.add_theme_color_override("font_outline_color", INK)
	b.add_theme_constant_override("outline_size", 5)


func _process(_delta: float) -> void:
	var vs := get_viewport_rect().size
	end_button.position = Vector2(vs.x - 178.0, vs.y - 218.0)
	hint_label.position = Vector2(0, vs.y * 0.62)
	hint_label.size = Vector2(vs.x, 30)
	banner.position = Vector2(0, vs.y * 0.24)
	banner.size = Vector2(vs.x, 80)


# ───────────────────────── 유닛 머리 위 ─────────────────────────

func add_bar(id: int, team: String) -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	move_child(root, 0)
	var back := ColorRect.new()
	back.color = Color(0.06, 0.03, 0.1, 0.85)
	back.size = Vector2(72, 10)
	back.position = Vector2(-36, 0)
	root.add_child(back)
	var fill := ColorRect.new()
	fill.color = ALLY_HP if team == "ally" else ENEMY_HP
	fill.size = Vector2(68, 6)
	fill.position = Vector2(-34, 2)
	root.add_child(fill)
	var hp := _label(14, CREAM, root)
	hp.position = Vector2(-36, 9)
	hp.size = Vector2(72, 18)
	hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var block := _label(15, BLOCK, root)
	block.position = Vector2(38, -6)
	var status := _label(14, Color(1.0, 0.55, 0.4), root)
	status.position = Vector2(-36, 25)
	status.size = Vector2(72, 18)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var intent := _label(18, Color(1.0, 0.86, 0.6), root)
	intent.position = Vector2(-60, -28)
	intent.size = Vector2(120, 24)
	intent.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bars[id] = {"root": root, "fill": fill, "hp": hp, "block": block, "status": status, "intent": intent}


## 딤드 강조 중: 이 유닛들의 막대만 밝게, 나머지는 흐리게. 빈 배열이면 원래대로.
func focus_units(ids: Array) -> void:
	for id in bars:
		bars[id].root.modulate = Color(1, 1, 1, 1) if ids.is_empty() or id in ids else Color(0.5, 0.48, 0.58, 0.35)
	for h in panels:
		panels[h].root.modulate.a = 1.0


func remove_bar(id: int) -> void:
	if bars.has(id):
		bars[id].root.queue_free()
		bars.erase(id)


func clear_bars() -> void:
	for id in bars.keys():
		remove_bar(id)


func place_bar(id: int, screen: Vector2, visible_now: bool) -> void:
	if not bars.has(id):
		return
	bars[id].root.position = screen
	bars[id].root.visible = visible_now


## u: battle.gd Unit. intent: battle.intent(u) 결과(적만).
func update_bar(u, intent := {}) -> void:
	if not bars.has(u.id):
		return
	var b: Dictionary = bars[u.id]
	b.fill.size.x = 68.0 * clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0)
	b.hp.text = "%d/%d" % [u.hp, u.max_hp]
	b.block.text = ("방어 %d" % u.block) if u.block > 0 else ""
	var st: Array = []
	if u.mark > 0:
		st.append("표식")
	if u.frozen:
		st.append("빙결")
	if u.taunt:
		st.append("도발")
	b.status.text = " · ".join(st)
	b.intent.text = _intent_text(intent)
	b.intent.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45) if intent.get("action", "") in ["attack", "roar"] else Color(0.8, 0.85, 1.0))


func _intent_text(it: Dictionary) -> String:
	match String(it.get("action", "")):
		"attack": return "공격 %d" % int(it.amount)
		"roar": return "%s! 전원 %d" % [String(it.get("name", "포효")), int(it.amount)]
		"move": return "전진"
		"frozen": return "빙결"
		"idle": return "대기"
	return ""


# ───────────────────────── 캐릭터 패널(손패 위) ─────────────────────────

func build_panels(heroes: Array) -> void:
	for k in panels.keys():
		panels[k].root.queue_free()
	panels.clear()
	for h in heroes:
		var root := Control.new()
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(root)
		var bg := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.1, 0.06, 0.18, 0.82)
		sb.border_color = Color(D.HEROES[h].color, 0.9)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(10)
		bg.add_theme_stylebox_override("panel", sb)
		bg.size = Vector2(196, 50)
		bg.position = Vector2(-98, 0)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
		var name_l := _label(20, D.HEROES[h].color.lightened(0.25), root)
		name_l.position = Vector2(-90, 2)
		name_l.text = String(D.HEROES[h].name)
		var hp := _label(14, CREAM, root)
		hp.position = Vector2(-90, 28)
		var pips: Array = []
		for i in D.AP_MAX:
			var pip := Panel.new()
			var ps := StyleBoxFlat.new()
			ps.set_corner_radius_all(9)
			ps.set_border_width_all(2)
			ps.border_color = GOLD
			pip.add_theme_stylebox_override("panel", ps)
			pip.size = Vector2(18, 18)
			pip.position = Vector2(20 + i * 23, 8)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			root.add_child(pip)
			pips.append(ps)
		var move := _label(13, Color(0.75, 0.9, 1.0), root)
		move.position = Vector2(20, 28)
		panels[h] = {"root": root, "hp": hp, "pips": pips, "move": move, "style": sb}


## centers: hand.group_centers(). u: Unit 또는 null(쓰러짐)
func update_panel(h: String, u, center_x: float, ap_cap: int) -> void:
	if not panels.has(h):
		return
	var p: Dictionary = panels[h]
	var vs := get_viewport_rect().size
	p.root.position = Vector2(center_x, vs.y - 252.0)
	p.root.visible = center_x > -1000.0
	if u == null:
		return
	p.root.modulate = Color(0.55, 0.5, 0.6) if u.dead else Color.WHITE
	p.hp.text = "체력 %d/%d" % [u.hp, u.max_hp] + (("  방어 %d" % u.block) if u.block > 0 else "")
	for i in p.pips.size():
		var ps: StyleBoxFlat = p.pips[i]
		if i < u.ap:
			ps.bg_color = Color(1.0, 0.78, 0.35)
		elif i < ap_cap:
			ps.bg_color = Color(0.3, 0.22, 0.42)
		else:
			ps.bg_color = Color(0.12, 0.1, 0.16)
		ps.border_color = GOLD if i < ap_cap else Color(0.35, 0.3, 0.42)
	p.move.text = "" if u.dead else ("행동력 %d" % u.ap)


# ───────────────────────── 글자 ─────────────────────────

func set_room(i: int, total: int, name: String) -> void:
	top_label.text = "%s  ·  방 %d/%d" % [name, i + 1, total]


func set_turn(text: String) -> void:
	turn_label.text = text


func hint(text: String) -> void:
	hint_label.text = text


func show_banner(text: String, col := CREAM, hold := 1.1) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", col)
	banner.scale = Vector2.ONE
	banner.pivot_offset = banner.size * 0.5
	var tw := create_tween()
	banner.modulate.a = 0.0
	banner.scale = Vector2(1.25, 1.25)
	tw.tween_property(banner, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(banner, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	tw.tween_property(banner, "modulate:a", 0.0, 0.35)


func set_battle_ui(on: bool) -> void:
	end_button.visible = on
	turn_label.visible = on


# ───────────────────────── 원정대 선택 ─────────────────────────

## 원정대 선택 화면. 카드 그림(원화)과 이름·설명. 셋을 골라야 출발.
func show_select(face_of: Callable) -> void:
	_picked = D.HERO_ORDER.duplicate()
	_select_root = Control.new()
	_select_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_select_root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.1, 0.62)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_select_root.add_child(dim)
	var vs := get_viewport_rect().size
	var title := _label(52, CREAM, _select_root)
	title.text = "숲길 원정대"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(vs.x, 70)
	title.position = Vector2(0, vs.y * 0.08)
	var sub := _label(20, GOLD, _select_root)
	sub.text = "숲을 지날 동료 셋을 고르세요"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.size = Vector2(vs.x, 30)
	sub.position = Vector2(0, vs.y * 0.08 + 72)
	var w := 220.0
	var gap := 60.0
	var x0 := vs.x * 0.5 - (w * 3 + gap * 2) * 0.5
	for i in D.HERO_ORDER.size():
		var h: String = D.HERO_ORDER[i]
		var card := Button.new()
		card.toggle_mode = true
		card.button_pressed = true
		card.focus_mode = Control.FOCUS_NONE
		card.size = Vector2(w, w * 1.5 + 70)
		card.position = Vector2(x0 + i * (w + gap), vs.y * 0.24)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.12, 0.07, 0.2, 0.9)
		sb.set_corner_radius_all(16)
		sb.set_border_width_all(4)
		sb.border_color = D.HEROES[h].color
		var sb_off := sb.duplicate()
		sb_off.border_color = Color(0.3, 0.28, 0.36)
		sb_off.bg_color = Color(0.08, 0.06, 0.1, 0.9)
		card.add_theme_stylebox_override("normal", sb_off)
		card.add_theme_stylebox_override("hover", sb_off)
		card.add_theme_stylebox_override("pressed", sb)
		card.add_theme_stylebox_override("hover_pressed", sb)
		_select_root.add_child(card)
		var art := TextureRect.new()
		art.texture = face_of.call(h)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.size = Vector2(w - 24, (w - 24) * 1.5)
		art.position = Vector2(12, 12)
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(art)
		var nm := _label(30, D.HEROES[h].color.lightened(0.3), card)
		nm.text = String(D.HEROES[h].name)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.size = Vector2(w, 36)
		nm.position = Vector2(0, w * 1.5 - 6)
		var bl := _label(16, CREAM, card)
		bl.text = "%s · 체력 %d" % [D.HEROES[h].blurb, D.HEROES[h].hp]
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bl.size = Vector2(w, 24)
		bl.position = Vector2(0, w * 1.5 + 32)
		card.toggled.connect(func(on: bool) -> void:
			if on and not h in _picked:
				_picked.append(h)
			elif not on:
				_picked.erase(h)
			_refresh_start())
	var start := Button.new()
	start.name = "Start"
	start.text = "출발"
	start.focus_mode = Control.FOCUS_NONE
	start.add_theme_font_override("font", CardFace.font())
	start.add_theme_font_size_override("font_size", 30)
	start.size = Vector2(220, 64)
	start.position = Vector2(vs.x * 0.5 - 110, vs.y * 0.24 + w * 1.5 + 100)
	_style_button(start, Color(0.55, 0.3, 0.18))
	start.pressed.connect(func() -> void:
		if _picked.size() == 3:
			var ordered := D.HERO_ORDER.filter(func(x): return x in _picked)
			_select_root.queue_free()
			_select_root = null
			start_pressed.emit(ordered))
	_select_root.add_child(start)
	_refresh_start()


func _refresh_start() -> void:
	if _select_root == null:
		return
	var b: Button = _select_root.get_node("Start")
	b.disabled = _picked.size() != 3
	b.text = "출발" if _picked.size() == 3 else "%d/3 선택" % _picked.size()


func selecting() -> bool:
	return _select_root != null


# ───────────────────────── 승패 ─────────────────────────

func show_result(won: bool) -> void:
	_result_root = Control.new()
	_result_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_result_root)
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.03, 0.1, 0.0)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_root.add_child(dim)
	create_tween().tween_property(dim, "color:a", 0.6, 0.6)
	var vs := get_viewport_rect().size
	var t := _label(64, GOLD if won else Color(0.9, 0.5, 0.55), _result_root)
	t.text = "숲을 건넜다!" if won else "원정대가 쓰러졌다"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size = Vector2(vs.x, 90)
	t.position = Vector2(0, vs.y * 0.3)
	var b := Button.new()
	b.text = "다시 하기"
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", CardFace.font())
	b.add_theme_font_size_override("font_size", 28)
	b.size = Vector2(220, 60)
	b.position = Vector2(vs.x * 0.5 - 110, vs.y * 0.5)
	_style_button(b, Color(0.36, 0.2, 0.6))
	b.pressed.connect(func() -> void:
		_result_root.queue_free()
		_result_root = null
		restart_pressed.emit())
	_result_root.add_child(b)
