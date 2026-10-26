extends Control
## 마녀의 주머니 갤러리(보기 전용): 주머니·손패·활동 중·버림패의 카드를 넓게 펼쳐 보여 준다.
## 마우스를 올린 카드는 제자리에서 들어 올려져 크게 보이고(CardView 스프링), 그 동안 나머지는 어둡게 가라앉는다.
## 카드 상태는 바꾸지 않는다. 툴팁은 CardHand 가 hover_entry 와 lifted_rect() 를 보고 옆에 띄운다.

const Cfg := preload("res://scripts/config.gd")
const CardViewScript := preload("res://scripts/ui/card_view.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")

const CARD := Vector2(150, 225)          # 펼친 카드 한 장(2:3)
const CAPTION_H := 22.0                  # 카드 아래 이름 줄
const GAP := Vector2(18, 22)             # 카드 사이 가로·세로 간격
const LIFT_SCALE := 1.6                  # 올린 카드 확대 배율
const LIFT_RISE := 14.0                  # 올린 카드가 제자리보다 위로 뜨는 높이
const DIM_ALPHA := 0.66                  # 나머지 카드를 가라앉히는 어둠
const DIM_COLOR := Color(0.04, 0.02, 0.09)
const EDGE := 10.0                       # 올린 카드가 창 안쪽에 남길 여백
const DISCARD_TINT := Color(0.6, 0.55, 0.65)
const ZONE_NOTE := {
	"pocket": "아침 드로우를 기다리는 카드 — 원하는 카드를 골라 꺼낼 수는 없습니다",
	"hand": "지금 손패에 있는 카드",
	"in_play": "활동 중 — 활동이 끝나면 버림패로 갑니다",
	"discard": "버림패 — 되돌아오지 않습니다",
}

signal close_requested

var hand                                 # CardHand: game·hud·텍스처 캐시
var list: VBoxContainer                  # 섹션 제목 + 카드 행(검증 스크립트는 CardHand.pocket_list 로 본다)
var scroll: ScrollContainer
var overlay: Control
var dim: ColorRect
var lifted                               # CardView(올린 카드 한 장)
var tiles: Array = []                    # [{node, art, entry, zone}] 펼쳐진 순서
var hover_tile: Dictionary = {}
var hover_entry: Dictionary = {}
var hover_zone := ""
var _dim_a := 0.0
var _forced: Dictionary = {}          # hover_index() 로 고정한 타일(마우스가 움직이면 풀린다)
var _forced_mouse := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var hud = hand.hud
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(v)
	v.add_child(hud._title("마녀의 주머니"))
	var explanation: Label = hud._label("주머니가 곧 덱입니다. 아침마다 무작위로 한 장이 손패(%d장까지)로 오고, 넘친 카드는 주머니에 남습니다. 카드에 마우스를 올리면 크게 볼 수 있습니다." % Cfg.HAND_VISIBLE, 13, MoonSkin.LAVENDER)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(explanation)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 42)
	close.pressed.connect(func(): close_requested.emit())
	v.add_child(close)
	# 카드 위에 겹치는 층: 어둠 + 올린 카드. 입력은 모두 통과시켜 아래 타일이 계속 마우스를 받는다.
	overlay = Control.new()
	overlay.name = "Overlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)
	dim = ColorRect.new()
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.color = Color(DIM_COLOR, 0.0)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.visible = false
	overlay.add_child(dim)
	lifted = CardViewScript.new()
	lifted.name = "Lifted"
	lifted.setup("", null)
	lifted.resize(CARD)
	lifted.visible = false
	overlay.add_child(lifted)
	visibility_changed.connect(func():
		if not is_visible_in_tree():
			_forced = {}
			_clear_hover())


## 카드 목록을 다시 펼친다(열 때와 소유 변화 때).
func fill() -> void:
	_clear_hover()
	tiles.clear()
	for c in list.get_children():
		list.remove_child(c)
		c.queue_free()
	var game = hand.game
	var hud = hand.hud
	var sections := [
		["주머니 %d장 (카드 %d개)" % [game.cards.pocket().size(), game.cards.pocket_units()], game.cards.pocket(), "pocket"],
		["손패 %d/%d" % [game.cards.hand().size(), Cfg.HAND_VISIBLE], game.cards.hand(), "hand"],
		["활동 중 %d장" % game.cards.in_play.size(), game.cards.in_play, "in_play"],
		["버림패 %d장 (되돌아오지 않음)" % game.cards.discard.size(), game.cards.discard, "discard"],
	]
	for sec in sections:
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 8)
		var icon_path: String = "res://assets/ui/icons/icon_discard.png" if sec[2] == "discard" else ""
		if icon_path != "" and ResourceLoader.exists(icon_path):
			var ic := TextureRect.new()
			ic.texture = load(icon_path)
			ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			ic.custom_minimum_size = Vector2(24, 24)
			head.add_child(ic)
		head.add_child(hud._title(sec[0], 16))
		list.add_child(head)
		var entries: Array = sec[1]
		if entries.is_empty():
			list.add_child(hud._label("  (비어 있음)", 13, MoonSkin.LAVENDER))
			continue
		var row := HFlowContainer.new()
		row.add_theme_constant_override("h_separation", int(GAP.x))
		row.add_theme_constant_override("v_separation", int(GAP.y))
		list.add_child(row)
		for e in entries:
			row.add_child(_tile(e, sec[2]))


func _tile(e: Dictionary, zone: String) -> Control:
	var game = hand.game
	var id: String = e["id"]
	var tile := Control.new()
	tile.custom_minimum_size = CARD + Vector2(0, CAPTION_H)
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE   # 오버는 _poll 이 좌표로 판정한다(휠 스크롤이 타일에 막히지 않게)
	var art := TextureRect.new()
	art.texture = hand._surface(id, e.get("person", ""), int(e.get("art", -1)))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_SCALE
	art.size = CARD
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if zone == "discard":
		art.modulate = DISCARD_TINT
	tile.add_child(art)
	var d: Dictionary = game.cards.def(id)
	var caption: String = d.get("name", id)
	if e.get("person", "") != "":
		caption += " · " + e["person"]
	if e.has("count") and game.cards.stackable(id):
		caption += "  ×%d" % e["count"]
	var cap: Label = hand.hud._label(caption, 13, MoonSkin.LAVENDER if zone == "discard" else MoonSkin.CREAM_DIM)
	cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	cap.position = Vector2(-10, CARD.y + 2)
	cap.size = Vector2(CARD.x + 20, CAPTION_H)
	tile.add_child(cap)
	tiles.append({"node": tile, "art": art, "entry": e, "zone": zone})
	return tile


# ───────────────────────── 들어 올리기 ─────────────────────────

func hovering() -> bool:
	return not hover_tile.is_empty()


## 검증·캡처용: i번째 타일에 마우스를 올린 것처럼 한다(-1 = 해제). 마우스가 움직이기 전까지 유지된다.
func hover_index(i: int) -> void:
	if i < 0 or i >= tiles.size():
		_forced = {}
		_clear_hover()
	else:
		_forced = tiles[i]
		_forced_mouse = get_global_mouse_position()
		_enter(tiles[i])


## 매 프레임 마우스 위치로 오버를 판정한다. 올린 카드가 덮는 영역 안에서는 옆 카드로 넘어가지 않는다(확대된 카드를 편히 본다).
func _poll() -> void:
	var m := get_global_mouse_position()
	if not _forced.is_empty():
		if m == _forced_mouse and is_instance_valid(_forced["node"]):
			return
		_forced = {}
	var ml := overlay.get_global_transform().affine_inverse() * m
	if hovering() and lift_target().has_point(ml):
		return
	if scroll.get_global_rect().has_point(m):
		for t in tiles:
			if _tile_rect(t).has_point(ml):
				if hover_tile.is_empty() or hover_tile["node"] != t["node"]:
					_enter(t)
				return
	if hovering():
		_clear_hover()


func _enter(info: Dictionary) -> void:
	if not is_instance_valid(info["node"]):
		return
	hover_tile = info
	hover_entry = info["entry"]
	hover_zone = info["zone"]
	var art: TextureRect = info["art"]
	lifted.card_id = hover_entry["id"]
	lifted.set_legendary_for(hover_entry["id"])   # 전설 카드(에린)는 확대해도 금빛·반짝임
	lifted.art.texture = art.texture
	lifted.burn_glow.texture = art.texture
	lifted.art.modulate = art.modulate
	lifted.mode = CardViewScript.Mode.HAND
	# 제자리(타일 위치, 원래 크기)에서 시작해 스프링으로 커지며 떠오른다
	var at := _tile_rect(info)
	lifted.fade = 1.0
	lifted.t_fade = 1.0
	lifted.lift = 0.0
	lifted.snap(at.position + Vector2(at.size.x * 0.5, at.size.y), 0.0, 1.0)
	lifted.t_lift = 1.0
	lifted.t_glow = 0.0
	lifted.visible = true
	dim.visible = true
	hand.game.sounds.play("card_hover")
	_retarget()


func _clear_hover() -> void:
	hover_tile = {}
	hover_entry = {}
	hover_zone = ""
	if lifted != null:
		lifted.t_fade = 0.0
		lifted.t_lift = 0.0
		lifted.t_scl = 1.0


## 타일의 카드 그림 영역을 overlay 좌표로
func _tile_rect(info: Dictionary) -> Rect2:
	var art: TextureRect = info["art"]
	var inv := overlay.get_global_transform().affine_inverse()
	return Rect2(inv * art.global_position, CARD)


## 올린 카드의 목표 사각형(overlay 좌표): 타일 가운데에서 살짝 위로, 창 밖으로 나가지 않게 민다.
func lift_target() -> Rect2:
	if hover_tile.is_empty():
		return Rect2()
	var at := _tile_rect(hover_tile)
	var sz := CARD * LIFT_SCALE
	var center := at.get_center() - Vector2(0, LIFT_RISE)
	var bounds := Rect2(Vector2.ZERO, overlay.size).grow(-EDGE)
	center.x = clampf(center.x, bounds.position.x + sz.x * 0.5, bounds.end.x - sz.x * 0.5)
	center.y = clampf(center.y, bounds.position.y + sz.y * 0.5, bounds.end.y - sz.y * 0.5)
	return Rect2(center - sz * 0.5, sz)


## 올린 카드의 목표 사각형(화면 좌표). 툴팁 배치용.
func lifted_rect() -> Rect2:
	var r := lift_target()
	var gt := overlay.get_global_transform()
	return Rect2(gt * r.position, r.size * gt.get_scale())


func zone_note() -> String:
	return ZONE_NOTE.get(hover_zone, "")


func _retarget() -> void:
	var r := lift_target()
	lifted.t_pos = Vector2(r.get_center().x, r.end.y)
	lifted.t_scl = LIFT_SCALE
	lifted.t_rot = 0.0


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	if hovering() and not is_instance_valid(hover_tile["node"]):
		_clear_hover()
	_poll()
	if hovering():
		_retarget()   # 스크롤로 타일이 움직여도 따라간다
	var want := DIM_ALPHA if hovering() else 0.0
	_dim_a = lerpf(_dim_a, want, 1.0 - exp(-delta * 12.0))
	dim.color = Color(DIM_COLOR, _dim_a)
	dim.visible = _dim_a > 0.01
	if lifted.visible:
		lifted.step(delta)
		if not hovering() and lifted.fade < 0.03:
			lifted.visible = false
