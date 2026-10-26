extends Control
## 영문판에서 HUD 이미지에 박힌 한글 글자를 가리고 같은 자리에 영문 글자를 올린다.
## 글자 자리만 글자를 지운 사본(tools/build_ui_notext.gd → NOTEXT_DIR)의 같은 영역으로 덮고, 그 위에 Label(auto translate)을 둔다.
## 한국어일 때는 숨는다. 언어가 바뀌면 NOTIFICATION_TRANSLATION_CHANGED 로 따라간다.

const SkinUI := preload("res://scripts/ui/moon/moon_skin.gd")
const NOTEXT_DIR := "res://assets/ui/moon_runes/notext/"
## 이미지 id → 글자 영역(원본 텍스처 px)과 원문·글자색. px 는 build_ui_notext.gd 가 지우는 영역이기도 하다.
## label 은 영문 글자를 놓을 영역(없으면 px) — 영문이 길어 판 안쪽 전체를 쓴다.
const COVERS := {
	"player_status": [
		{"px": Rect2i(930, 205, 190, 110), "ko": "마녀", "color": "cream", "align": HORIZONTAL_ALIGNMENT_LEFT},
		{"px": Rect2i(930, 418, 190, 115), "ko": "산장", "color": "cream", "align": HORIZONTAL_ALIGNMENT_LEFT},
	],
	"lodge_button": [{"px": Rect2i(62, 112, 102, 36), "label": Rect2i(36, 110, 154, 40), "ko": "산장 관리", "color": "cream"}],
	"storage": [{"px": Rect2i(66, 115, 64, 34), "label": Rect2i(34, 113, 128, 38), "ko": "창고", "color": "cream"}],
	"objective": [{"px": Rect2i(128, 26, 162, 38), "ko": "오늘의 할 일", "color": "ink"}],
}

var tex_id := ""
var _parts: Array = []   # [[TextureRect, Label, cover dict]]


## target(이 이미지를 그리는 TextureRect·버튼 등, 크기 = 이미지 표시 크기)의 자식으로 붙인다.
static func attach(target: Control, id: String) -> Control:
	var c = load("res://scripts/ui/moon/moon_text_cover.gd").new()
	c.tex_id = id
	c.name = "TextCover"
	target.add_child(c)
	return c


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var src: Texture2D = SkinUI.tex(tex_id)
	var clean := load(NOTEXT_DIR + tex_id + ".png") as Texture2D if ResourceLoader.exists(NOTEXT_DIR + tex_id + ".png") else null
	if src == null or clean == null:
		return
	for cv in COVERS.get(tex_id, []):
		var px: Rect2i = cv["px"]
		var patch := TextureRect.new()
		var at := AtlasTexture.new()
		at.atlas = clean
		at.region = Rect2(px)
		patch.texture = at
		patch.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		patch.stretch_mode = TextureRect.STRETCH_SCALE
		patch.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(patch)
		var l := Label.new()
		l.text = cv["ko"]
		l.add_theme_font_override("font", SkinUI.font(true))
		l.add_theme_color_override("font_color", SkinUI.PAPER_INK if cv["color"] == "ink" else SkinUI.CREAM)
		l.horizontal_alignment = cv.get("align", HORIZONTAL_ALIGNMENT_CENTER)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(l)
		_parts.append([patch, l, cv])
	(get_parent() as Control).resized.connect(_layout)
	_layout()
	_sync()


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED and is_node_ready():
		_sync()


func _sync() -> void:
	visible = SkinUI.language() == "en"
	if visible:
		_layout()


func _layout() -> void:
	var src: Texture2D = SkinUI.tex(tex_id)
	if src == null:
		return
	position = Vector2.ZERO
	size = (get_parent() as Control).size   # 이미지를 그리는 부모와 같은 크기
	var k := size / Vector2(src.get_size())
	for p in _parts:
		var px: Rect2i = p[2]["px"]
		var r := Rect2(Vector2(px.position) * k, Vector2(px.size) * k)
		(p[0] as TextureRect).position = r.position
		(p[0] as TextureRect).size = r.size
		var lp: Rect2i = p[2].get("label", px)
		var lr := Rect2(Vector2(lp.position) * k, Vector2(lp.size) * k)
		var l: Label = p[1]
		l.position = lr.position
		l.size = lr.size
		# 원문 글자 높이(영역의 약 75%)에 맞추고, 영문이 길면 폭에 맞게 줄인다
		var fs := maxi(8, int(r.size.y * 0.75))
		var f: Font = l.get_theme_font("font")
		var shown := l.atr(l.text)
		while fs > 8 and f.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > lr.size.x:
			fs -= 1
		l.add_theme_font_size_override("font_size", fs)
