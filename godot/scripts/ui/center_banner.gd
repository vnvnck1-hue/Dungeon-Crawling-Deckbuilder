extends CanvasLayer
## 화면 가운데 큰 글씨 배너: 1일차 새벽의 '첫째 날' 타이틀 카드와 밤 진입 배너('첫째 밤 · 습격의 밤').
## 같은 뜻의 토스트 두 줄(챕터 밤 규칙 + "N일차 밤 — 몰려옵니다")을 이 배너 하나로 합쳤다. 게임을 멈추지 않는다.

const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const ChapterData := preload("res://scripts/game/chapter_data.gd")

const ORDINALS := ["첫째", "둘째", "셋째", "넷째", "다섯째", "여섯째", "일곱째", "여덟째", "아홉째", "열째", "열한째", "열두째"]

var game
var root: Control
var box: VBoxContainer
var head: Label
var sub: Label
var note: Label
var history: Array = []   # 검증용: [{kind, head, sub}]
var _tween: Tween


static func ordinal(n: int) -> String:
	return ORDINALS[n - 1] if n >= 1 and n <= ORDINALS.size() else "%d번째" % n


func _ready() -> void:
	name = "CenterBanner"
	layer = 11
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = MoonSkin.make_theme()
	add_child(root)
	box = VBoxContainer.new()
	box.anchor_left = 0.0
	box.anchor_right = 1.0
	box.anchor_top = 0.37
	box.anchor_bottom = 0.37
	box.offset_bottom = 180
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.modulate.a = 0.0
	root.add_child(box)
	head = _line(54, MoonSkin.CREAM, true)
	sub = _line(22, MoonSkin.CREAM_DIM, false)
	note = _line(17, MoonSkin.LAVENDER, false)
	for l in [head, sub, note]:
		box.add_child(l)


func _line(size: int, color: Color, bold: bool) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", MoonSkin.font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0.02, 0.0, 0.06, 0.85))
	l.add_theme_constant_override("shadow_offset_y", 3)
	l.add_theme_constant_override("shadow_outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## 승패 화면이 뜨면 배너를 바로 걷는다(종료 화면 위에 겹치지 않게).
func _process(_delta: float) -> void:
	if is_showing() and game != null and game.session.is_over():
		if _tween != null and _tween.is_valid():
			_tween.kill()
		box.modulate.a = 0.0


func is_showing() -> bool:
	return box.modulate.a > 0.01


## 큰 제목 + 부제 + 작은 설명을 hold초 동안 보여 준다(앞뒤 페이드 포함).
func show_card(kind: String, title: String, subtitle: String, detail := "", hold := 2.0, accent := MoonSkin.CREAM) -> void:
	head.text = title
	head.add_theme_color_override("font_color", accent)
	sub.text = subtitle
	note.text = detail
	note.visible = detail != ""
	history.append({"kind": kind, "head": title, "sub": subtitle, "detail": detail})
	if _tween != null and _tween.is_valid():
		_tween.kill()
	box.scale = Vector2(0.96, 0.96)
	box.pivot_offset = Vector2(root.get_viewport_rect().size.x * 0.5, 90)
	_tween = create_tween()
	_tween.set_parallel(true)
	_tween.tween_property(box, "modulate:a", 1.0, 0.35)
	_tween.tween_property(box, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_tween.chain().tween_interval(hold)
	_tween.chain().tween_property(box, "modulate:a", 0.0, 0.6)


## 1일차 새벽의 타이틀 카드: "첫째 날" + 오늘 밤 예고(멀리건 뒤에 가려지던 '오늘 밤' 토스트를 대신한다).
func day_card(day: int, hold := 2.0) -> void:
	var rule: Dictionary = ChapterData.rule(day)
	var detail: String = rule["desc"] + (" — 산장 아래 봉인석을 지키세요" if day == 1 else "")
	show_card("day", "%s 날" % ordinal(day), "오늘 밤 · %s" % rule["name"], detail, hold)


## 밤 진입 배너(챕터 밤 규칙 토스트 + 'N일차 밤' 토스트를 합친 것).
func night_card(n: int, total: int) -> void:
	var rule: Dictionary = ChapterData.rule(n)
	show_card("night", "%s 밤 · %s" % [ordinal(n), rule["name"]], rule["desc"], "%d / %d일 — 산장과 봉인석을 지키세요" % [n, total], 2.4, Color(1.0, 0.72, 0.68))
