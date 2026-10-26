extends Control
## 손패(화면 아래). 캐릭터마다 3장씩 묶어 부채꼴로 놓는다. 카드 한 장의 연출은 마녀산장 card_view.gd 그대로
## (스프링·휨·올림 그림자·뽑기 회전·보여 주고 타오르기·재 입자). 글자는 CardFace 로 원화 위에 굽는다(BM 을지로체).
## 입력 판정은 main.gd 가 card_at() 으로 묻고, 이 노드는 배치·상태 표시만 맡는다.

const CardView := preload("res://scripts/ui/card_view.gd")
const CardFace := preload("res://scripts/ui/card_face.gd")
const CardFx := preload("res://scripts/ui/card_fx.gd")
const D := preload("res://dungeon/data/defs.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")

const CARD_SIZE := Vector2(128, 192)
const SPACING := 92.0            # 하나의 부채꼴: 카드 사이 간격
const FAN_DROP := 3.4             # 가장자리 카드가 내려가는 정도(px × 거리²)
const HOVER_SCALE := 1.62
const SELECT_SCALE := 1.28
const FAN_DEG := 3.6
const SHOW_SCALE := 1.75

var views: Dictionary = {}       # card_id → CardView(손패에 있는 카드)
var dying: Array = []            # 타오르는 중인 CardView
var hovered := ""
var selected := ""
var dragging := ""
var drag_pos := Vector2.ZERO
var over_board := false
var order: Array = []            # 화면 왼쪽부터 카드 id
var playable: Dictionary = {}    # card_id → bool(행동력·대상 충족)
var discard_count := 0
var fx: Control                  # card_fx.gd(입자 폭발)
var _faces: Dictionary = {}      # card_id → AtlasTexture(글자 구운 앞면)
var focus := ""                  # 겨누는 카드의 주인(그 캐릭터 카드만 밝게)
var _pile: Control
var _pile_label: Label


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx = CardFx.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_pile()
	add_child(fx)


func _build_pile() -> void:
	_pile = Control.new()
	_pile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pile)
	for i in 3:
		var back := TextureRect.new()
		back.texture = load("res://assets/cards/hand/card_back.png")
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_SCALE
		back.size = CARD_SIZE * 0.5
		back.position = Vector2(i * 2.0, -i * 2.5)
		back.rotation_degrees = -4.0 + i * 3.0
		back.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pile.add_child(back)
	_pile_label = Label.new()
	_pile_label.add_theme_font_override("font", CardFace.font())
	_pile_label.add_theme_font_size_override("font_size", 18)
	_pile_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	_pile_label.add_theme_color_override("font_outline_color", Color(0.08, 0.04, 0.12))
	_pile_label.add_theme_constant_override("outline_size", 6)
	_pile_label.position = Vector2(-6, CARD_SIZE.y * 0.5 + 4)
	_pile_label.size = Vector2(CARD_SIZE.x * 0.5 + 12, 24)
	_pile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pile.add_child(_pile_label)
	_update_pile()


func set_pile_visible(on: bool) -> void:
	_pile.visible = on


func pile_center() -> Vector2:
	return _pile.position + CARD_SIZE * 0.25


func _update_pile() -> void:
	_pile_label.text = "버림패 %d" % discard_count
	_pile.modulate.a = 1.0 if discard_count > 0 else 0.45


# ───────────────────────── 앞면 굽기 ─────────────────────────

## 카드 앞면 텍스처(글자 구운 AtlasTexture). 마녀산장 card_catalog._face 와 같은 방식: 처음엔 빈 그림, 구워지면 그림이 바뀐다.
func face(card_id: String) -> Texture2D:
	var card := D.card(card_id)
	return _face_for(card_id, "res://assets/cards/%s.png" % card.art,
		{"id": card_id, "name": card.name, "category": card.category, "printed_rules": card.rules}, String(D.HEROES[card.hero].name))


## 원정대 선택 화면의 영웅 카드: 같은 방식으로 이름·한 줄 소개·카드 세 장 이름을 굽는다.
func hero_face(h: String) -> Texture2D:
	var def: Dictionary = D.HEROES[h]
	var names: Array = []
	for c in def.cards:
		names.append("%d · %s" % [int(D.card(c).cost), D.card(c).name])
	return _face_for("hero_" + h, String(def.art),
		{"id": "hero_" + h, "name": def.name, "category": "%s · 체력 %d" % [def.blurb, int(def.hp)], "printed_rules": names}, "")


func _face_for(key: String, path: String, entry: Dictionary, badge: String) -> Texture2D:
	if _faces.has(key):
		return _faces[key]
	var art := load(path) as Texture2D
	var t := AtlasTexture.new()
	t.atlas = art
	t.region = Rect2(0, 0, art.get_width(), art.get_height())
	_faces[key] = t
	if DisplayServer.get_name() != "headless":
		_bake(t, entry, badge, art, path)
	return t


func _bake(target: AtlasTexture, entry: Dictionary, badge: String, art: Texture2D, path: String) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(art.get_width(), art.get_height())
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var f: Control = CardFace.new()
	f.size = Vector2(vp.size)
	f.setup(entry, art, badge, path)
	vp.add_child(f)
	add_child(vp)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	target.atlas = ImageTexture.create_from_image(vp.get_texture().get_image())
	vp.queue_free()


# ───────────────────────── 카드 넣고 빼기 ─────────────────────────

## 이번 턴 손패를 채운다: 버림패 더미에서 카드가 핑그르 돌며 날아든다(card_view "draw").
func deal(card_ids: Array) -> void:
	order = card_ids.duplicate()
	var start := pile_center()
	var i := 0
	for id in order:
		if views.has(id):
			continue
		var v := _make_view(id)
		v.snap(start + Vector2(0, CARD_SIZE.y * 0.25), -12.0, 0.45)
		v.visible = false
		var delay := 0.08 * i
		i += 1
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(v):
				v.visible = true
				v.flourish("draw")
				Sfx.play(self, "card_draw"))
	discard_count = 0
	_update_pile()
	_layout()


func _make_view(id: String) -> Control:
	var v: Control = CardView.new()
	v.setup(id, face(id))
	v.resize(CARD_SIZE)
	v.t_float = 0.35
	add_child(v)
	move_child(fx, -1)
	_add_gem(v, id)
	views[id] = v
	return v


## 비용 보석(왼쪽 위): 행동력 숫자. card_view 가 카드가 돌아설 때 badge 의 부모를 감춘다.
func _add_gem(v: Control, id: String) -> void:
	var gem := Control.new()
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem.position = Vector2(-8, -8)
	gem.size = Vector2(34, 34)
	var disc := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.32, 0.18, 0.62)
	sb.border_color = Color(D.HEROES[D.card(id).hero].color).lightened(0.25)
	sb.set_border_width_all(4)
	sb.set_corner_radius_all(17)
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 3
	disc.add_theme_stylebox_override("panel", sb)
	disc.size = gem.size
	disc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem.add_child(disc)
	var l := Label.new()
	l.text = str(D.card(id).cost)
	l.add_theme_font_override("font", CardFace.font())
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.16))
	l.add_theme_constant_override("outline_size", 5)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = gem.size
	gem.add_child(l)
	v.add_child(gem)
	v.badge = l
	v.set_meta("gem", sb)


## 카드를 냈다: 오른쪽 위로 핑그르 날아가 앞면을 보여 준 뒤 보랏빛으로 타올라 버림패로 간다.
func consume(card_id: String) -> void:
	if not views.has(card_id):
		return
	var v: Control = views[card_id]
	views.erase(card_id)
	order.erase(card_id)
	if selected == card_id:
		selected = ""
	if dragging == card_id:
		dragging = ""
	if hovered == card_id:
		hovered = ""
	v.z_index = 50
	v.t_fade = 1.0
	var vs := get_viewport_rect().size
	v.start_dissolve(func() -> void:
		discard_count += 1
		_update_pile()
		v.queue_free(), Vector2(vs.x * 0.8, vs.y * 0.36), SHOW_SCALE)
	dying.append(v)
	Sfx.play(self, "card_play")
	get_tree().create_timer(v.show_time).timeout.connect(func() -> void: Sfx.play(self, "card_burn"))
	_layout()


## 주인이 쓰러진 카드: 손패에서 사라진다(재처럼 흩어짐).
func drop(card_id: String) -> void:
	if not views.has(card_id):
		return
	var v: Control = views[card_id]
	views.erase(card_id)
	order.erase(card_id)
	v.start_dissolve(func() -> void: v.queue_free())
	dying.append(v)
	_layout()


func clear_all() -> void:
	for id in views.keys():
		views[id].queue_free()
	views.clear()
	order.clear()
	hovered = ""
	selected = ""
	dragging = ""


# ───────────────────────── 배치 ─────────────────────────

func _groups() -> Array:
	var out: Array = []
	for h in D.HERO_ORDER:
		var ids := order.filter(func(c): return D.card(c).hero == h)
		if not ids.is_empty():
			out.append([h, ids])
	return out


## 손패 순서(캐릭터 순 → 비용 순)로 한 줄에 늘어선 카드 id.
func _fan() -> Array:
	var out: Array = []
	for g in _groups():
		out.append_array(g[1])
	return out


## 부채꼴 안 k 번째(전체 n 장) 카드의 기본 자리 [위치, 각도].
func _fan_slot(k: int, n: int) -> Array:
	var vs := get_viewport_rect().size
	var u := k - (n - 1) * 0.5
	return [Vector2(vs.x * 0.5 + u * SPACING, vs.y + CARD_SIZE.y * 0.2 + u * u * FAN_DROP), u * FAN_DEG]


## 캐릭터마다 그 카드들의 가운데 x(화면). HUD 의 캐릭터 패널이 그 위에 선다.
func group_centers() -> Dictionary:
	var fan := _fan()
	var out := {}
	for g in _groups():
		var sum := 0.0
		for id in g[1]:
			sum += (_fan_slot(fan.find(id), fan.size())[0] as Vector2).x
		out[g[0]] = sum / g[1].size()
	return out


## 겨누는 동안 그 캐릭터 카드만 밝게(나머지는 어둡게). ""이면 모두 원래대로.
func focus_hero(h: String) -> void:
	focus = h


func _layout() -> void:
	var vs := get_viewport_rect().size
	_pile.position = Vector2(vs.x - 118.0, vs.y - 150.0)
	var fan := _fan()
	var hi := fan.find(hovered)
	for k in fan.size():
		if true:
			var id: String = fan[k]
			var v: Control = views[id]
			if v.mode == CardView.Mode.DYING:
				continue
			var slot := _fan_slot(k, fan.size())
			var p: Vector2 = slot[0]
			var r: float = slot[1]
			var s := 1.0
			v.z_index = 10 + k
			v.t_lift = 0.0
			v.t_glow = 0.0
			# 마우스를 올린 카드 옆 카드는 살짝 비켜선다
			if hi >= 0 and id != hovered:
				p.x += signf(k - hi) * 34.0 / maxf(absf(k - hi), 1.0)
			if id == selected:
				p = Vector2(p.x, vs.y - 14.0)
				r = 0.0
				s = SELECT_SCALE
				v.t_lift = 0.7
				v.t_glow = 1.0
				v.glow_color = Color(1.0, 0.82, 0.42)
				v.z_index = 80
			if id == hovered and id != selected and dragging == "":
				p = Vector2(p.x, vs.y - 6.0)
				r = 0.0
				s = HOVER_SCALE
				v.t_lift = 1.0
				v.z_index = 90
			if id == dragging:
				v.mode = CardView.Mode.DRAG
				p = drag_pos + Vector2(0, CARD_SIZE.y * (0.32 if over_board else 0.5))
				s = 0.62 if over_board else 1.05
				r = 0.0
				v.t_lift = 1.0
				v.t_glow = 1.0 if over_board else 0.4
				v.glow_color = Color(0.45, 0.95, 0.95)
				v.z_index = 100
				v.t_fade = 0.8 if over_board else 1.0
			else:
				v.mode = CardView.Mode.HAND
				v.t_fade = 1.0
			# 낼 수 없는 카드는 어둡게, 비용 보석은 붉게. 겨누는 동안 다른 캐릭터 카드는 더 어둡게 가라앉는다.
			# (카드 셰이더는 노드 modulate 를 곱한다 — card_view 가 alpha 만 쓰므로 RGB 를 여기서 정한다)
			var ok: bool = playable.get(id, false)
			var tone := Color.WHITE if ok else Color(0.55, 0.53, 0.62)
			if focus != "" and D.card(id).hero != focus and id != dragging:
				tone = Color(0.3, 0.28, 0.38)
				p.y += 28.0
			v.modulate = Color(tone.r, tone.g, tone.b, v.modulate.a)
			v.t_pos = p
			v.t_rot = r
			v.t_scl = s
			var sb: StyleBoxFlat = v.get_meta("gem")
			sb.bg_color = Color(0.32, 0.18, 0.62) if ok else Color(0.42, 0.14, 0.18)


func _process(delta: float) -> void:
	_layout()
	for v in views.values():
		v.step(delta)
	for v in dying.duplicate():
		if not is_instance_valid(v):
			dying.erase(v)
			continue
		v.step(delta)
		if v.tick_dissolve(delta):
			dying.erase(v)
			if v.on_done.is_valid():
				v.on_done.call()


# ───────────────────────── 입력 도우미(main.gd 가 부름) ─────────────────────────

## 화면 좌표 아래의 카드 id(맨 위 카드 우선). 없으면 "".
func card_at(p: Vector2) -> String:
	var best := ""
	var best_z := -1
	for id in views:
		var v: Control = views[id]
		if v.mode == CardView.Mode.DYING or not v.visible:
			continue
		var local: Vector2 = v.get_global_transform().affine_inverse() * p
		if Rect2(Vector2.ZERO, v.size).has_point(local) and v.z_index > best_z:
			best = id
			best_z = v.z_index
	return best


func set_hover(id: String) -> void:
	if id == hovered:
		return
	hovered = id
	if id != "" and views.has(id) and dragging == "":
		views[id].flourish("hover")
		Sfx.play(self, "card_hover")


func select(id: String) -> void:
	selected = id
	if id != "" and views.has(id):
		views[id].flourish("pickup")
		Sfx.play(self, "card_pickup")


func start_drag(id: String) -> void:
	dragging = id
	selected = ""
	if views.has(id):
		views[id].flourish("pickup")
		Sfx.play(self, "card_pickup")


func end_drag(returned: bool) -> void:
	if returned and views.has(dragging):
		views[dragging].flourish("return")
		Sfx.play(self, "card_cancel")
	dragging = ""


func deny(id: String) -> void:
	if views.has(id):
		views[id].flourish("land")
		Sfx.play(self, "card_deny")


## 손패 맨 위 가장자리 y(이보다 위면 전장을 겨눈다).
func top_edge() -> float:
	return get_viewport_rect().size.y - CARD_SIZE.y * 0.95
