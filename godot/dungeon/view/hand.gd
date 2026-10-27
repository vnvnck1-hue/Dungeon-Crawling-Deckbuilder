extends Control
## 손패(화면 아래). 캐릭터별로 묶어 한 부채꼴로 놓는다(최대 HAND_SIZE 장). 카드 한 장의 연출은 마녀산장 card_view.gd 그대로
## (스프링·휨·올림 그림자·뽑기 회전·보여 주고 타오르기·재 입자). 글자는 CardFace 로 원화 위에 굽는다(BM 을지로체).
## 카드는 battle.hand 의 키("카드id#번호", 같은 카드가 여럿일 수 있다)로 다룬다. 앞면 텍스처는 카드 id 로 한 번만 굽는다.
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
var combo: Dictionary = {}       # card_id → bool(연계 조건이 맞음 — 금빛·붉은빛으로 맥동)
var costs: Dictionary = {}       # card_id → 지금 비용(명상 등으로 줄면 보석 숫자가 바뀐다)
var discard_count := 0
var draw_count := 0
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
	_pile_label.position = Vector2(-50, CARD_SIZE.y * 0.5 + 4)
	_pile_label.size = Vector2(CARD_SIZE.x * 0.5 + 100, 24)
	_pile_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pile.add_child(_pile_label)
	_update_pile()


func set_pile_visible(on: bool) -> void:
	_pile.visible = on


func pile_center() -> Vector2:
	return _pile.position + CARD_SIZE * 0.25


## 뽑을 패·버림패 장수(battle 의 더미 크기). main 이 화면을 갱신할 때 넣어 준다.
func set_piles(draw_n: int, discard_n: int) -> void:
	draw_count = draw_n
	discard_count = discard_n
	_update_pile()


func _update_pile() -> void:
	_pile_label.text = "뽑을 패 %d · 버림패 %d" % [draw_count, discard_count]
	_pile.modulate.a = 1.0 if draw_count + discard_count > 0 else 0.45


# ───────────────────────── 앞면 굽기 ─────────────────────────

## 카드 앞면 텍스처(글자 구운 AtlasTexture). 마녀산장 card_catalog._face 와 같은 방식: 처음엔 빈 그림, 구워지면 그림이 바뀐다.
## 원화: 전용 원화(assets/cards/synergy/<카드 id>.png, Codex 요청서 docs/art-requests/synergy-cards.md)가 있으면 그것, 없으면 임시 원화.
func face(card_key: String) -> Texture2D:
	var card := D.card(card_key)
	var card_id := D.base_id(card_key)
	var own := "res://assets/cards/synergy/%s.png" % D.root_id(card_key)
	return _face_for(card_id, own if ResourceLoader.exists(own) else "res://assets/cards/%s.png" % card.art,
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

## 손패를 battle.hand 와 맞춘다: 새로 뽑은 카드는 더미에서 핑그르 돌며 날아든다(card_view "draw"). 이미 있는 카드는 그대로.
func deal(card_keys: Array) -> void:
	order = card_keys.duplicate()
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


## 비용 보석(왼쪽 위): 숲 보석 메달(assets/ui/cost_badge, 256 캔버스에 나무 본체 반경 112) 위에 행동력 숫자.
## 본체 지름이 GEM_BODY 가 되게 텍스처를 키우고, 본체 오른쪽 끝이 제목 글자 시작(카드 폭의 20%)보다 왼쪽에 오게 둔다.
## 보석 링만 cost_gem 셰이더가 영웅색으로 물들여 천천히 반짝인다. card_view 가 카드가 돌아설 때 badge 의 부모를 감춘다.
const GEM_BODY := 34.0
const GEM_CENTER := Vector2(8, 8)
const GEM_DIR := "res://assets/ui/cost_badge/"
const GEM_SHADER := preload("res://dungeon/shaders/cost_gem.gdshader")

func _add_gem(v: Control, id: String) -> void:
	var gem := Control.new()
	gem.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gem.size = Vector2.ONE * round(GEM_BODY * 256.0 / 224.0)
	gem.position = GEM_CENTER - gem.size * 0.5
	var mat := ShaderMaterial.new()
	mat.shader = GEM_SHADER
	mat.set_shader_parameter("hero", Color(D.HEROES[D.card(id).hero].color))
	mat.set_shader_parameter("seed", float(views.size()) * 1.37 + randf())
	for layer in ["badge_face", "badge_gem", "badge_frame"]:
		var t := TextureRect.new()
		t.texture = load(GEM_DIR + layer + ".png")
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_SCALE
		t.size = gem.size
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if layer == "badge_gem":
			t.material = mat
		gem.add_child(t)
	var l := Label.new()
	l.text = str(D.card(id).cost)
	l.add_theme_font_override("font", CardFace.font())
	l.add_theme_font_size_override("font_size", 20)
	l.add_theme_color_override("font_color", Color(1.0, 0.95, 0.82))
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.04, 0.16))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = gem.size
	gem.add_child(l)
	v.add_child(gem)
	v.badge = l
	v.set_meta("gem", mat)


## 레벨업으로 고른 카드가 덱에 들어가는 연출: 고른 자리에서 빛나며 떠올랐다가 핑그르 돌며 덱 더미로 날아가 꽂힌다.
## 도착하면 더미가 튕기고 반짝이며 label(예: "+ 강타")이 떠오른다. 연출이 끝날 때까지 기다린다.
func fly_to_pile(tex: Texture2D, from: Vector2, s0: float, label: String, col: Color) -> void:
	if tex == null:
		return
	var to := pile_center()
	fx.z_index = 200   # 어두운 레벨업 화면(같은 CanvasLayer 의 뒤 형제)보다 위에서 날아가게
	# 1) 고른 카드가 제자리에서 빛나며 살짝 커진다
	var pop := TextureRect.new()
	pop.texture = tex
	pop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pop.stretch_mode = TextureRect.STRETCH_SCALE
	pop.size = CARD_SIZE * s0
	pop.pivot_offset = pop.size * 0.5
	pop.position = from - pop.size * 0.5
	pop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fx.add_child(pop)
	fx.card_glow(from, CARD_SIZE * s0, 0.0, CardFx.CREAM, col.lightened(0.3), col, 1.2, 0.7)
	var tw := pop.create_tween()
	tw.tween_property(pop, "scale", Vector2(1.12, 1.12), 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(pop, "scale", Vector2(1.0, 1.0), 0.14)
	await tw.finished
	pop.queue_free()
	# 2) 핑그르 돌며 덱 더미로 휘어 날아간다
	Sfx.play(self, "card_draw")
	var landed := [false]
	fx.fly(tex, from, to, CARD_SIZE, s0, 0.5, 0.75, func() -> void: landed[0] = true)
	while not landed[0]:
		await get_tree().process_frame
	# 3) 더미에 꽂힌다: 반짝임 + 더미가 튕기고 카드 이름이 더미 왼쪽에 떠오른다
	fx.burst(to, 1.0, 36, [CardFx.CREAM, col.lightened(0.3), CardFx.GOLD])
	fx.float_text(to + Vector2(-CARD_SIZE.x * 1.3, -CARD_SIZE.y * 0.1), label, col.lightened(0.35), 1.1)
	Sfx.play_or(self, "card_shuffle", "card_draw")
	_pile.pivot_offset = CARD_SIZE * 0.25
	var bt := _pile.create_tween()
	bt.tween_property(_pile, "scale", Vector2(1.25, 1.25), 0.08).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bt.tween_property(_pile, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(0.25).timeout
	fx.z_index = 0


## 손패를 battle.hand 와 맞춘다: 없어진 카드(버림·휘발·강화로 바뀐 키)는 흩어지고, 새 카드(뽑기·생성)는 더미에서 날아든다.
func sync(card_keys: Array) -> void:
	for key in views.keys():
		if not key in card_keys:
			drop(key)
	deal(card_keys)


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
		v.queue_free(), Vector2(vs.x * 0.8, vs.y * 0.36), SHOW_SCALE)
	dying.append(v)
	Sfx.play(self, "card_play")
	get_tree().create_timer(v.show_time).timeout.connect(func() -> void: Sfx.play(self, "card_burn"))
	_layout()


## 주인이 쓰러진 카드: 손패에서 사라진다(재처럼 흩어짐).
func drop(card_key: String) -> void:
	if not views.has(card_key):
		return
	var v: Control = views[card_key]
	views.erase(card_key)
	order.erase(card_key)
	v.start_dissolve(func() -> void: v.queue_free())
	dying.append(v)
	_layout()


## 그 캐릭터의 카드를 모두 손패에서 떨어뜨린다(쓰러졌을 때).
func drop_hero(h: String) -> void:
	for key in views.keys():
		if String(D.card(key).hero) == h:
			drop(key)


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
			# 낼 수 없는 카드는 어둡게, 비용 보석은 빛이 꺼진 회색으로. 겨누는 동안 다른 캐릭터 카드는 더 어둡게 가라앉는다.
			# (카드 셰이더는 노드 modulate 를 곱한다 — card_view 가 alpha 만 쓰므로 RGB 를 여기서 정한다)
			var ok: bool = playable.get(id, false)
			var tone := Color.WHITE if ok else Color(0.55, 0.53, 0.62)
			# 연계 조건이 맞는 카드: 금빛·붉은빛으로 맥동하며 살짝 떠오른다
			if ok and combo.get(id, false) and id != selected and id != dragging and id != hovered:
				var beat := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
				v.t_glow = 0.55 + 0.45 * beat
				v.glow_color = Color(1.0, 0.55 + 0.25 * beat, 0.2)
				p.y -= 14.0
			if v.badge != null:
				var cst := int(costs.get(id, D.card(id).cost))
				v.badge.text = str(cst)
				v.badge.add_theme_color_override("font_color", Color(0.55, 1.0, 0.6) if cst < int(D.card(id).cost) else Color(1.0, 0.95, 0.82))
			if focus != "" and D.card(id).hero != focus and id != dragging:
				tone = Color(0.3, 0.28, 0.38)
				p.y += 28.0
			v.modulate = Color(tone.r, tone.g, tone.b, v.modulate.a)
			v.t_pos = p
			v.t_rot = r
			v.t_scl = s
			var mat: ShaderMaterial = v.get_meta("gem")
			mat.set_shader_parameter("active", 1.0 if ok else 0.0)


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
