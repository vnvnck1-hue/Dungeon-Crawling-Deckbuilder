extends Control
## 손패 뒤 고정 소품. 생성 소품(props-v05)을 승인 v04 시안의 소품 자리에 맞춰 놓는다.
## 손패 수·확대·드래그와 무관하게 움직이지 않으며, CardHand보다 먼저 그려져 카드에 가려진다.
## 손패가 반쯤 숨어 있는 평소에는 반투명하고, 손패가 올라오면(CardHand.peek) 함께 또렷해진다.

const Layout := preload("res://scripts/ui/moon/moon_layout.gd")
const PROPS_DIR := "res://assets/ui/hand_workbench/props-v05/"

# 승인 시안(art/ui/hand-workbench-v04/lowered-cards-props-behind.png, 3장 행) 좌표계.
# 시안 8장 부채꼴 폭과 실제 손패 폭을 맞춘 배율, 시안 카드 바닥 y=499 -> 실제 손패 바닥 y=772.
const ART_SCALE := 0.55
const IDLE_ALPHA := 0.5   # 손패가 숨어 있을 때 소품 불투명도
const ART_CENTER_X := 724.0
const ART_CARD_BOTTOM := 499.0
# 시안 속 각 소품의 실루엣 경계. 소품은 비율을 유지한 채 이 칸 안에 들어가고 바닥·가운데를 맞춘다.
# 배열 순서가 그리기 순서다(뒤에 올수록 앞).
const SPECS := [
	["SpellbookAndCandle", Rect2(66, 316, 271, 192)],
	["PotionsAndHerbs", Rect2(1155, 292, 259, 212)],
	["InkAndQuill", Rect2(315, 357, 129, 144)],
	["DriedHerbs", Rect2(441, 437, 137, 71)],
	["RolledParchment", Rect2(568, 446, 100, 41)],
	["IngredientPouch", Rect2(1001, 391, 88, 106)],
	["MoonCharm", Rect2(1082, 438, 49, 64)],
]

var game
var pieces: Array[Control] = []
var source_canvas: Control


static func fit_rect(slot: Rect2, tex_size: Vector2) -> Rect2:
	var k := minf(slot.size.x / tex_size.x, slot.size.y / tex_size.y)
	var size := tex_size * k
	return Rect2(Vector2(slot.get_center().x - size.x * 0.5, slot.end.y - size.y), size)


func _ready() -> void:
	name = "HandWorkbench"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_canvas = Control.new()
	source_canvas.name = "ApprovedArtCoordinates"
	source_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_canvas.size = Vector2(1448, 543)
	add_child(source_canvas)
	for spec in SPECS:
		var tex: Texture2D = load(PROPS_DIR + spec[0] + ".png")
		var pic := TextureRect.new()
		pic.name = spec[0]
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_SCALE
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var r := fit_rect(spec[1], tex.get_size())
		pic.position = r.position
		pic.size = r.size
		source_canvas.add_child(pic)
		pieces.append(pic)
	resized.connect(_place)
	_place()


func _process(_delta: float) -> void:
	if game != null:
		visible = not game.session.is_over()
		var hand = game.hud.card_hand if game.hud != null else null
		modulate.a = lerpf(IDLE_ALPHA, 1.0, hand.peek) if hand != null else IDLE_ALPHA


func _place() -> void:
	var s := Layout.ui_scale(size)
	source_canvas.position = Layout.to_view(Vector2(800 - ART_CENTER_X * ART_SCALE,
		772 - ART_CARD_BOTTOM * ART_SCALE), Vector2(0.5, 1), size)
	source_canvas.scale = Vector2.ONE * ART_SCALE * s
