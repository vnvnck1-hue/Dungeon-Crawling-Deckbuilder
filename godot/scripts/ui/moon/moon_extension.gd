extends RefCounted
## Approved extension art. Only appearance/layout; all values/actions remain in existing UI controllers.
const DIR := "res://assets/ui/moon_runes/extension_v01/textures/"
const COMMON := "res://assets/ui/moon_runes/common/"
const CREAM := Color8(252, 231, 176)
const PAPER_INK := Color8(48, 30, 44)
static var _textures: Dictionary = {}
static var _boxes: Dictionary = {}

static func tex(id: String) -> Texture2D:
	if not _textures.has(id):
		var path := DIR + id + ".tres"
		if not ResourceLoader.exists(path): path = COMMON + id + ".png"
		_textures[id] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _textures[id]

static func scaled(id: String, width: int) -> Texture2D:
	var key := id + "@" + str(width)
	if not _textures.has(key):
		var original := tex(id)
		if original == null: return null
		var img := original.get_image()
		if original is AtlasTexture:
			var atlas := original as AtlasTexture
			img = atlas.atlas.get_image().get_region(Rect2i(atlas.region))
		img.resize(width, maxi(1, roundi(img.get_height() * float(width) / img.get_width())), Image.INTERPOLATE_LANCZOS)
		_textures[key] = ImageTexture.create_from_image(img)
	return _textures[key]

static func box(id: String, width := 180, margins := Vector4(20, 12, 20, 12), content := Vector4(12, 8, 12, 8), tint := Color.WHITE) -> StyleBoxTexture:
	var key := id + str(width) + str(margins) + str(content) + str(tint)
	if not _boxes.has(key):
		var b := StyleBoxTexture.new()
		b.texture = scaled(id, width)
		b.modulate_color = tint
		for side in 4:
			b.set_texture_margin(side, margins[side])
			b.set_content_margin(side, content[side])
		_boxes[key] = b
	return _boxes[key]

static func modal() -> StyleBoxTexture:
	return box("modal_frame", 284, Vector4(40, 27, 40, 24), Vector4(26, 22, 26, 22))

static func paper(margin := 16) -> StyleBoxTexture:
	return box("tooltip_frame", 263, Vector4(33, 24, 33, 24), Vector4(maxi(margin, 30), maxi(margin, 24), maxi(margin, 30), maxi(margin, 30)))

static func row() -> StyleBoxTexture:
	return box("row_background", 223, Vector4(30, 15, 30, 15), Vector4(26, 10, 26, 10))

static func button(state := "normal") -> StyleBoxTexture:
	return box("button_" + state, 150, Vector4(25, 13, 25, 13), Vector4(30, 10, 30, 10))

## 탭(시설·손님·대화 기록): 버튼보다 큰 틀에 글자 주변 여유를 넉넉히 둔다.
static func tab(state := "normal") -> StyleBoxTexture:
	return box("button_" + state, 200, Vector4(33, 17, 33, 17), Vector4(38, 13, 38, 13))

static func focus() -> StyleBoxTexture:
	if not _boxes.has("keyboard_focus"):
		var b := button().duplicate() as StyleBoxTexture
		b.draw_center = false
		b.modulate_color = Color8(57, 232, 224)
		_boxes["keyboard_focus"] = b
	return _boxes["keyboard_focus"]

## 말풍선: 꼬리(왼쪽 아래)는 아래 여백 안에 둔다. 크림 영역은 그림의 위 11%~아래 73% 이므로 아래 안쪽 여백이 크다.
static func speech() -> StyleBoxTexture:
	return box("speech", 220, Vector4(28, 22, 22, 44), Vector4(38, 18, 34, 46))

static func person() -> StyleBoxTexture:
	return box("person", 70, Vector4(10, 5, 10, 5), Vector4(12, 3, 12, 3))

static func action(tint := Color.WHITE) -> StyleBoxTexture:
	return box("action", 170, Vector4(26, 13, 26, 13), Vector4(30, 10, 30, 10), tint)

## 머리 위 이름표는 매 프레임 여러 번 그리므로 box() 의 문자열 키를 매번 만들지 않게 한 번 받아 둔다.
static var _world_tag: StyleBoxTexture

static func world_tag() -> StyleBoxTexture:
	if _world_tag == null:
		_world_tag = box("action", 80, Vector4(11, 5, 11, 5), Vector4(12, 5, 12, 5))
	return _world_tag

static func toast() -> StyleBoxTexture:
	return box("toast", 180, Vector4(28, 14, 28, 14), Vector4(20, 8, 20, 8))

static func icon(id: String, px := 48) -> TextureRect:
	var t := TextureRect.new()
	t.texture = tex(id)
	t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	t.custom_minimum_size = Vector2(px, px)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t

## 헤더 그림별 기본 높이와 크림 띠(글이 들어가는 영역)의 세로 비율. 그림은 비율을 지켜 가운데에 두고 늘리지 않는다.
const HEADER_SPECS := {
	"header": {"height": 118.0, "band": Vector2(0.52, 0.93)},
	"victory_header": {"height": 134.0, "band": Vector2(0.60, 0.93)},
	"defeat_header": {"height": 124.0, "band": Vector2(0.63, 0.92)},
	"paper_header": {"height": 72.0, "band": Vector2(0.20, 0.87)},
}

static func title(label: Label, kind := "header") -> void:
	label.set_meta("extension_header", kind)
	var spec: Dictionary = HEADER_SPECS.get(kind, HEADER_SPECS["header"])
	var art_tex := tex(kind)
	var h: float = spec["height"]
	var band: Vector2 = spec["band"]
	var w: float = h * 3.6 if art_tex == null else h * float(art_tex.get_width()) / float(art_tex.get_height())
	var art: TextureRect = label.get_node_or_null("HeaderArt")
	if art == null:
		art = TextureRect.new()
		art.name = "HeaderArt"
		art.show_behind_parent = true
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		label.add_child(art)
	art.texture = art_tex
	var sb := StyleBoxEmpty.new()
	sb.content_margin_top = h * band.x
	sb.content_margin_bottom = h * (1.0 - band.y)
	sb.content_margin_left = 40
	sb.content_margin_right = 40
	label.add_theme_stylebox_override("normal", sb)
	label.add_theme_color_override("font_color", PAPER_INK)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(w, h)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL

static func fit_modal(panel: Control) -> void:
	if not is_instance_valid(panel) or not panel.is_inside_tree(): return
	var view := panel.get_viewport_rect().size
	var minimum := panel.get_combined_minimum_size()
	var design: Vector2 = panel.get_meta("extension_design", Vector2.ZERO)
	var desired := minimum.max(design)
	var s := minf(1.0, minf((view.x - 30) / maxf(desired.x, 1), (view.y - 30) / maxf(desired.y, 1)))
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = desired
	panel.scale = Vector2.ONE * s
	panel.position = (view - desired * s) * 0.5

static func draw_bar(canvas: CanvasItem, at: Rect2, value: float, color: Color) -> void:
	var track := tex("bar_track")
	var fill := tex("bar_fill")
	canvas.draw_texture_rect(track, at.grow(2), false)
	var frac := clampf(value, 0, 1)
	if frac > 0:
		var inner := at.grow(-0.8)
		var destination := Rect2(inner.position, Vector2(inner.size.x * frac, inner.size.y))
		canvas.draw_texture_rect_region(fill, destination, Rect2(0, 0, fill.get_width() * frac, fill.get_height()), color)
