extends CanvasLayer
## 자원 말풍선: 자원을 들고 있는 용병(나무꾼·사냥꾼·채집가) 머리 위에 작은 말풍선으로 자원 아이콘과 수량을 띄운다.
## 아이콘은 Codex 납품 `assets/ui/icons/icon_<id>.png`를 쓰고, 없으면 손패용 카드 그림을 작게 쓴다.
## 표시 전용. 전달 판정은 ally.gd의 _check_handover()가 한다.

const Cfg := preload("res://scripts/config.gd")
const SkinUI := preload("res://scripts/ui/moon/moon_skin.gd")
const Catalog := preload("res://scripts/ui/card_catalog.gd")
const Extension := preload("res://scripts/ui/moon/moon_extension.gd")

const ICON := 26.0

var game
var _bubbles: Dictionary = {}   # ally instance id -> Bubble
static var _icons: Dictionary = {}


func _ready() -> void:
	name = "CarryBubble"
	layer = 6


static func icon_for(id: String) -> Texture2D:
	if _icons.has(id):
		return _icons[id]
	var path := "res://assets/ui/icons/icon_%s.png" % id
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	else:
		t = Catalog.texture(id, true)
	_icons[id] = t
	return t


func _process(_delta: float) -> void:
	var cam: Camera3D = game.world.camera
	var seen := {}
	for a in get_tree().get_nodes_in_group("allies"):
		if a.dead or a.hidden or a.carry.is_empty():
			continue
		var key := a.get_instance_id()
		seen[key] = true
		var b: Bubble = _bubbles.get(key)
		if b == null:
			b = Bubble.new()
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_theme_stylebox_override("panel", Extension.speech())
			add_child(b)
			_bubbles[key] = b
		if a.carry != b._last:   # set_items 도 같으면 바로 돌아가므로, 아이콘 표를 만들기 전에 거른다
			var texs := {}
			for id in a.carry:
				texs[id] = icon_for(id)
			b.set_items(a.carry, texs)
		var head: Vector3 = a.global_position + Vector3(0, a.hp_offset + 0.95, 0)
		if cam.is_position_behind(head) or (game.world.fog_of_war != null and not game.world.fog_of_war.is_visible_at(a.global_position)):
			b.visible = false
			continue
		b.visible = true
		b.reset_size()
		b.position = cam.unproject_position(head) - Vector2(10, b.size.y + 12)
		# 마녀가 가까우면 살짝 커지며 눈에 띈다
		var near: bool = game.player != null and a.global_position.distance_to(game.player.global_position) < Cfg.HANDOVER_RANGE * 2.0
		b.modulate = Color(1, 1, 1, 1.0) if near else Color(1, 1, 1, 0.85)
	for key in _bubbles.keys():
		if not seen.has(key):
			_bubbles[key].queue_free()
			_bubbles.erase(key)


class Bubble extends PanelContainer:
	var row: HBoxContainer
	var _last := {}

	func _init() -> void:
		row = HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(row)

	func set_items(carry: Dictionary, texs: Dictionary) -> void:
		if carry == _last:
			return
		_last = carry.duplicate()
		for c in row.get_children():
			c.queue_free()
		for id in carry:
			var cell := HBoxContainer.new()
			cell.add_theme_constant_override("separation", 2)
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var icon := TextureRect.new()
			icon.texture = texs.get(id)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.custom_minimum_size = Vector2(ICON, ICON)
			icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(icon)
			var n := Label.new()
			n.text = "×%d" % int(carry[id])
			n.add_theme_font_override("font", SkinUI.font(true))
			n.add_theme_font_size_override("font_size", 14)
			n.add_theme_color_override("font_color", SkinUI.PAPER_INK)
			n.mouse_filter = Control.MOUSE_FILTER_IGNORE
			cell.add_child(n)
			row.add_child(cell)

	func _draw() -> void:
		pass # The tail is included in the artwork.
