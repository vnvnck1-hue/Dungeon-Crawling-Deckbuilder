extends CanvasLayer
## 새벽 보상·장날 화면(볼륨 확장 E3 — 기획: docs/game-volume-expansion-plan.md §3.3·3.4).
## - 새벽 보상: 카드 3장 중 1장을 골라 받는다(받지 않을 수도 있음). 받은 카드는 손패 우선.
## - 장날: 행상의 카드 4장을 골드로 산다(여러 장 가능). 침식 카드 정화(골드)도 여기서 한다.
## - 선택(choice): 종족 카드 v1(docs/race-cards-v01.md)의 카드 고르기 — 맞바꿈·꿈 기록장·언데드 보상·소개장·상인 마차·대청소 등.
##   항목 {id, uid?, person?, price?, texture?, label?}, 고르면 on_pick(i) -> bool(true면 닫음). game.race_cards.open_choice()가 연다.
## 열려 있는 동안 게임은 멈춘다(hud.refresh_pause()가 active를 본다).

const ChapterData := preload("res://scripts/game/chapter_data.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const Catalog := preload("res://scripts/ui/card_catalog.gd")
const Stage := preload("res://scripts/ui/center_stage.gd")
const OutsideClick := preload("res://scripts/ui/outside_click.gd")
const CardLift := preload("res://scripts/ui/card_lift.gd")

const CARD := Vector2(200, 300)
const GAP := 34.0

var game
var active := false
var mode := ""              # reward | market | choice
var ids: Array = []         # 새벽 보상 후보
var offers: Array = []      # 장날 [{id, price, sold}]
var root: Control
var stage: Control          # 화면 가운데 무대 — 카드·제목·버튼은 가운데 기준 좌표(창 비율이 바뀌어도 가운데 유지)
var dim: ColorRect
var title: Label
var hint: Label
var row: Control
var buttons: Array = []     # [{btn, price_label}]
var close_btn: Button
var purify_btn: Button
var reroll_btn: Button          # 행상 좌판 다시 펼치기(100G, 방문마다 한 번)
var choice_items: Array = []        # 선택 모드 항목
var _choice_pick := Callable()
var _choice_close := Callable()
var _choice_closable := false
## 떠돌이 행상 브로크의 좌판(docs/merchant-shop-v01.md): 장날 화면에 초상·간판·좌판·가격표를 더한다.
var merchant_mode := false
var merchant_profile: Dictionary = {}
var deco: Control               # 행상 장식(닫을 때 비운다)
const MERCHANT_UI := "res://assets/ui/merchant/"
const MERCHANT_SHIFT := 130.0   # 카드 줄을 오른쪽으로 밀고 왼쪽에 초상을 둔다
const MerchantData := preload("res://scripts/game/merchant_data.gd")


func _ready() -> void:
	name = "OfferScreen"
	layer = 12
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	root.theme = MoonSkin.make_theme()
	root.gui_input.connect(_on_root_input)
	add_child(root)
	dim = ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.02, 0.1, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	stage = Stage.make(root)
	title = _label(30, true, MoonSkin.CREAM)
	hint = _label(16, false, MoonSkin.LAVENDER)
	row = Control.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(row)
	close_btn = Button.new()
	close_btn.custom_minimum_size = Vector2(200, 44)
	close_btn.pressed.connect(close)
	stage.add_child(close_btn)
	purify_btn = Button.new()
	purify_btn.custom_minimum_size = Vector2(260, 44)
	purify_btn.pressed.connect(purify)
	stage.add_child(purify_btn)
	reroll_btn = Button.new()
	reroll_btn.custom_minimum_size = Vector2(260, 44)
	reroll_btn.pressed.connect(reroll)
	reroll_btn.visible = false
	stage.add_child(reroll_btn)


func _label(size: int, bold: bool, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", MoonSkin.font(bold))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	return l


func open_reward(choice_ids: Array) -> void:
	if active or choice_ids.is_empty():
		return
	mode = "reward"
	ids = choice_ids.duplicate()
	offers = []
	_open("새벽의 선물", "밤을 버틴 대가로 숲이 카드를 내밉니다 — 한 장을 고르세요 (손패가 차면 주머니로)",
		ids.map(func(id): return {"id": id, "price": 0, "sold": false}))
	close_btn.text = "받지 않기"
	purify_btn.visible = false


func open_market(market_offers: Array) -> void:
	if active or market_offers.is_empty():
		return
	mode = "market"
	offers = market_offers
	ids = []
	_open("장날 — 떠돌이 행상", "", offers)
	close_btn.text = "장 보기 마침"
	purify_btn.visible = true
	_refresh_market()


## 행상 브로크의 좌판: 장날과 같은 구매·정화 규칙에 초상·간판·좌판·가격표·등급을 더한다(scripts/game/merchant.gd 가 연다).
func open_merchant(merchant_offers: Array, profile: Dictionary) -> void:
	if active or merchant_offers.is_empty():
		return
	mode = "market"
	merchant_mode = true
	merchant_profile = profile
	offers = merchant_offers
	ids = []
	_open("%s의 좌판" % profile.get("person", "행상"), "", offers)
	close_btn.text = "구경 마치기"
	purify_btn.visible = true
	reroll_btn.visible = true
	_refresh_market()


## 좌판 다시 펼치기(검증 도구도 부른다): 행상이 100G 를 받고 5장을 새로 깔면, 같은 화면을 새 카드로 다시 그린다.
func reroll() -> bool:
	if not active or not merchant_mode or game.get("merchant") == null:
		return false
	var why: String = game.merchant.reroll_block_reason()
	if why != "":
		game.toast("다시 펼칠 수 없습니다 — " + why, Color(1.0, 0.7, 0.7))
		game.sounds.play_or("btn_denied", "card_deny")
		return false
	if not game.merchant.reroll():
		return false
	offers = game.merchant.offers
	if deco != null:
		deco.queue_free()
		deco = null
	_open(title.text, "", offers)
	_refresh_market()
	return true


func _merchant_texture(file: String) -> Texture2D:
	var path := MERCHANT_UI + file
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


## 그림 소재가 없으면(코덱스 납품 전) 같은 자리에 단색 판을 대신 그린다.
func _merchant_piece(file: String, at: Rect2, fallback: Color, radius := 10) -> Control:
	var tex := _merchant_texture(file)
	var c: Control
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_SCALE
		c = r
	else:
		var p := Panel.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = fallback
		sb.set_corner_radius_all(radius)
		sb.border_color = fallback.darkened(0.45)
		sb.set_border_width_all(3)
		p.add_theme_stylebox_override("panel", sb)
		c = p
	c.position = at.position
	c.size = at.size
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.add_child(c)
	return c


func _merchant_label(text: String, at: Rect2, font_size: int, color: Color, bold := true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", MoonSkin.font(bold))
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.position = at.position
	l.size = at.size
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.add_child(l)
	return l


## 좌판 장식을 카드 뒤(무대 맨 아래)에 깐다. x0·y0: 첫 카드의 왼쪽 위, total: 카드 줄 너비.
func _decorate_merchant(x0: float, y0: float, total: float) -> void:
	deco = Control.new()
	deco.name = "MerchantDeco"
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(deco)
	stage.move_child(deco, 0)
	# 간판: 제목 뒤
	_merchant_piece("sign_board.png", Rect2(-330 + MERCHANT_SHIFT * 0.5, y0 - 150, 660, 132), Color(0.36, 0.22, 0.13), 14)
	title.position.x += MERCHANT_SHIFT * 0.5
	title.position.y = y0 - 104
	title.add_theme_color_override("font_color", Color(1.0, 0.93, 0.78))
	# 좌판: 카드가 나무 판대 윗면에 서고, 가격표는 앞에 드리운 천에 걸린다(그림 비율 1800×360 유지)
	var stall_w := total + 80.0
	_merchant_piece("stall_board.png", Rect2(x0 - 40, y0 + CARD.y - 40, stall_w, stall_w * 0.2), Color(0.3, 0.18, 0.12), 12)
	# 초상과 한마디
	var px := x0 - 330.0
	var portrait := TextureRect.new()
	portrait.texture = load(str(merchant_profile.get("portrait", ""))) as Texture2D if ResourceLoader.exists(str(merchant_profile.get("portrait", ""))) else null
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.position = Vector2(px, y0 - 40)
	portrait.size = Vector2(300, 375)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	deco.add_child(portrait)
	_merchant_label("%s · %s" % [merchant_profile.get("person", ""), merchant_profile.get("role", "")], Rect2(px, y0 + 338, 300, 30), 19, MoonSkin.CREAM)
	_merchant_label(str(merchant_profile.get("line", "")).replace("\n", " "), Rect2(px - 10, y0 + 368, 320, 64), 15, MoonSkin.LAVENDER, false)
	# 가격표·등급: 카드마다
	for i in buttons.size():
		var b: Dictionary = buttons[i]
		var btn: TextureButton = b["btn"]
		var o: Dictionary = offers[i]
		var tag_at := Rect2(btn.position.x + CARD.x * 0.5 - 72, btn.position.y + CARD.y + 40, 144, 58)
		_merchant_piece("price_tag.png", tag_at, Color(0.9, 0.82, 0.62), 8)
		var has_tag_art := _merchant_texture("price_tag.png") != null
		# 그림 가격표는 왼쪽 동전 자리를 비우고 오른쪽 종이에 쓴다
		var text_at := Rect2(tag_at.position.x + (48 if has_tag_art else 0), tag_at.position.y, tag_at.size.x - (56 if has_tag_art else 0), tag_at.size.y)
		b["price_label"] = _merchant_label("%dG" % int(o["price"]), text_at, 24, Color(0.25, 0.13, 0.06))
		var grade: Dictionary = MerchantData.grade_of(int(o["price"]))
		b["grade_label"] = _merchant_label(str(grade["name"]), Rect2(btn.position.x - 20, btn.position.y - 30, CARD.x + 40, 26), 15, grade["color"])
		# 카드 이름은 가격표 아래로
		b["label"].position = Vector2(-20, CARD.y + 100)
		b["label"].text = game.cards.def(o["id"]).get("name", o["id"])
		btn.tooltip_text = "%s · %s %dG\n%s" % [b["label"].text, grade["name"], int(o["price"]), game.cards.def(o["id"]).get("description", "")]
	close_btn.position.y = y0 + CARD.y + 250
	purify_btn.position.y = y0 + CARD.y + 250
	reroll_btn.position = Vector2(260, y0 + CARD.y + 250)
	# 골드·정화 안내는 간판과 겹치지 않게 좌판 아래·버튼 바로 위로
	hint.position.y = y0 + CARD.y + 200


func open_choice(t: String, h: String, items: Array, on_pick: Callable, closable := false, close_text := "그만두기", on_close := Callable()) -> void:
	if active or items.is_empty():
		return
	mode = "choice"
	choice_items = items
	_choice_pick = on_pick
	_choice_close = on_close
	_choice_closable = closable
	offers = []
	ids = []
	_open(t, h, items)
	close_btn.text = close_text
	close_btn.visible = closable
	close_btn.position.x = -100
	purify_btn.visible = false
	_refresh_choice()


func _refresh_choice() -> void:
	for i in buttons.size():
		var sold: bool = choice_items[i].get("sold", false)
		buttons[i]["btn"].disabled = sold
		buttons[i]["btn"].modulate = Color(0.5, 0.45, 0.6) if sold else Color.WHITE
		if sold:
			buttons[i]["label"].text = _item_name(choice_items[i]) + "\n구매함"
	if choice_items.any(func(it): return it.has("price")):
		hint.text = hint.text.split("\n")[0] + "\n골드 %dG" % game.economy.gold


func _item_name(it: Dictionary) -> String:
	if it.has("label"):
		return str(it["label"])
	var nm: String = game.cards.def(it["id"]).get("name", it["id"])
	return nm + ("\n" + str(it["person"]) if str(it.get("person", "")) != "" else "")


func _item_texture(it: Dictionary) -> Texture2D:
	var path := str(it.get("texture", ""))
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	if int(it.get("art", -1)) >= 0:
		return Catalog.variant_texture(it["id"], int(it["art"]), false)
	if str(it.get("person", "")) != "":
		return Catalog.texture_for(it["id"], it["person"])
	return Catalog.texture(it["id"], false)


func _open(t: String, h: String, items: Array) -> void:
	active = true
	root.visible = true
	title.text = t
	hint.text = h
	for b in buttons:
		b["btn"].queue_free()
	buttons.clear()
	var vp := Stage.view(stage)  # 무대 좌표의 원점이 화면 가운데다
	var n := items.size()
	# 선택 모드에서 카드가 많으면(산장 대청소 등) 여러 줄로 작게 놓는다
	var per_row := n if n <= 6 else 8
	var rows := int(ceil(float(n) / per_row))
	var card := CARD if rows == 1 else CARD * (0.62 if rows == 2 else 0.46)
	var gap := GAP if rows == 1 else GAP * 0.5
	var row_h := card.y + (46.0 if rows > 1 else 0.0)
	var total := mini(n, per_row) * card.x + (mini(n, per_row) - 1) * gap
	var x0 := -total * 0.5 + (MERCHANT_SHIFT if merchant_mode else 0.0)
	var y0 := -(row_h * rows) * 0.5 - 30 if rows > 1 else -CARD.y * 0.5 - 30
	title.size = Vector2(vp.x, 40)
	title.position = Vector2(-vp.x * 0.5, y0 - 100)
	hint.size = Vector2(vp.x - 120, 50)
	hint.position = Vector2(-vp.x * 0.5 + 60, y0 - 52)
	for i in n:
		var it: Dictionary = items[i]
		var d: Dictionary = game.cards.def(it["id"])
		var btn := TextureButton.new()
		btn.texture_normal = _item_texture(it) if mode == "choice" else Catalog.texture(it["id"], false)
		btn.ignore_texture_size = true
		btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		btn.size = card
		btn.position = Vector2(x0 + (i % per_row) * (card.x + gap), y0 + (i / per_row) * row_h)
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.tooltip_text = "%s\n%s" % [d.get("name", it["id"]), d.get("description", "")]
		btn.pressed.connect(_on_card.bind(i))
		CardLift.attach(btn, func(): return active, func(): game.sounds.play("card_hover"))
		stage.add_child(btn)
		var nm := Label.new()
		nm.add_theme_font_override("font", MoonSkin.font(true))
		nm.add_theme_font_size_override("font_size", 17 if rows == 1 else 13)
		nm.add_theme_color_override("font_color", MoonSkin.CREAM)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		nm.size = Vector2(card.x + 40, 50)
		nm.position = Vector2(-20, card.y + 6)
		nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
		nm.text = d.get("name", it["id"]) + ("\n%dG" % int(it["price"]) if mode == "market" else "")
		if mode == "choice":
			nm.text = _item_name(it) + ("\n%dG" % int(it["price"]) if it.has("price") else "")
			btn.tooltip_text = "%s\n%s" % [nm.text, d.get("description", "")]
		btn.add_child(nm)
		buttons.append({"btn": btn, "label": nm})
	close_btn.position = Vector2(20, y0 + (row_h * rows if rows > 1 else CARD.y) + 80)
	purify_btn.position = Vector2(-280, y0 + CARD.y + 80)
	if mode == "reward":
		close_btn.position.x = -100
	if merchant_mode:
		_decorate_merchant(x0, y0, total)
	if game.hud != null:
		game.hud.refresh_pause()
	game.sounds.play_or("panel_open", "card_shuffle")


func _on_card(i: int) -> void:
	if mode == "choice":
		choose(i)
	elif mode == "reward":
		pick(i)
	else:
		buy(i)


## 새벽 보상 i번을 받는다(검증 도구도 이것을 부른다).
func pick(i: int) -> bool:
	if not active or mode != "reward" or i < 0 or i >= ids.size():
		return false
	game.chapter.take_reward(ids[i])
	game.toast("새벽의 선물 — '%s' 카드를 받았습니다" % game.cards.def(ids[i]).get("name", ids[i]), Color(1.0, 0.95, 0.75))
	game.sounds.play("card_draw")
	close()
	return true


## 선택 모드 i번을 고른다(검증 도구도 이것을 부른다). on_pick 이 true 를 돌려주면 닫는다.
func choose(i: int) -> bool:
	if not active or mode != "choice" or i < 0 or i >= choice_items.size():
		return false
	if choice_items[i].get("sold", false):
		return false
	var cb := _choice_pick
	var done := true
	if cb.is_valid():
		done = bool(cb.call(i))
	game.sounds.play("card_draw")
	if done:
		_choice_close = Callable()
		close()
	else:
		_refresh_choice()
	return true


func buy(i: int) -> bool:
	if not active or mode != "market" or i < 0 or i >= offers.size():
		return false
	var why: String = game.chapter.buy_block_reason(offers[i])
	if why != "":
		game.toast("살 수 없습니다 — " + why, Color(1.0, 0.7, 0.7))
		game.sounds.play_or("btn_denied", "card_deny")
		return false
	game.chapter.buy(offers[i])
	if merchant_mode and game.get("merchant") != null:
		game.merchant.on_bought(offers[i])
	game.toast("'%s' 카드를 샀습니다 (-%dG)" % [game.cards.def(offers[i]["id"]).get("name", ""), int(offers[i]["price"])], Color(1.0, 0.9, 0.6))
	_refresh_market()
	return true


func purify() -> String:
	if not active or mode != "market":
		return ""
	var why: String = game.chapter.purify_block_reason()
	if why != "":
		game.toast("정화할 수 없습니다 — " + why, Color(1.0, 0.7, 0.7))
		return ""
	var gone: String = game.chapter.buy_purify()
	game.toast("행상의 향로로 '%s'을(를) 정화했습니다 (-%dG)" % [gone, ChapterData.PURIFY_PRICE], Color(0.85, 0.75, 1.0))
	_refresh_market()
	return gone


func _refresh_market() -> void:
	hint.text = "골드 %dG · 산 카드는 손패로(가득 차면 주머니) · 침식 카드 %d장" % [game.economy.gold, game.chapter.corruption_count()]
	for i in buttons.size():
		var sold: bool = offers[i].get("sold", false)
		buttons[i]["btn"].disabled = sold
		buttons[i]["btn"].modulate = Color(0.5, 0.45, 0.6) if sold else Color.WHITE
		if sold:
			buttons[i]["label"].text = game.cards.def(offers[i]["id"]).get("name", "") + ("" if merchant_mode else "\n구매함")
			if buttons[i].has("price_label"):
				buttons[i]["price_label"].text = "팔림"
		elif buttons[i].has("price_label"):
			# 골드가 모자라면 가격을 붉게
			var short: bool = game.economy.gold < int(offers[i]["price"])
			buttons[i]["price_label"].add_theme_color_override("font_color", Color(0.62, 0.12, 0.08) if short else Color(0.25, 0.13, 0.06))
	purify_btn.text = "침식 정화 %dG" % ChapterData.PURIFY_PRICE
	purify_btn.disabled = game.chapter.purify_block_reason() != ""
	if merchant_mode and game.get("merchant") != null:
		reroll_btn.text = "다시 펼친 좌판" if game.merchant.rerolled else "좌판 다시 펼치기 %dG" % MerchantData.REROLL_PRICE
		reroll_btn.disabled = game.merchant.reroll_block_reason() != ""
		reroll_btn.tooltip_text = "좌판 5장을 새 카드로 바꿉니다 (방문마다 한 번)" + ("
" + game.merchant.reroll_block_reason() if reroll_btn.disabled else "")


func close() -> void:
	if not active:
		return
	if mode == "choice" and _choice_close.is_valid():
		_choice_close.call()
	_choice_close = Callable()
	_choice_pick = Callable()
	close_btn.visible = true
	reroll_btn.visible = false
	active = false
	mode = ""
	var was_merchant := merchant_mode
	merchant_mode = false
	if deco != null:
		deco.queue_free()
		deco = null
	title.add_theme_color_override("font_color", MoonSkin.CREAM)
	root.visible = false
	for b in buttons:
		b["btn"].queue_free()
	buttons.clear()
	if game.hud != null:
		game.hud.refresh_pause()
	game.sounds.play("panel_close")
	# 행상 좌판은 그날 한 번뿐: 닫으면 브로크가 좌판을 거두고 떠난다(scripts/game/merchant.gd)
	if was_merchant and game.get("merchant") != null:
		game.merchant.on_shop_closed()


## 장날 화면은 카드·버튼 둘레 밖(허공)을 클릭하면 '장 보기 마침'처럼 닫힌다.
## 새벽 선물은 잘못 눌러 보상을 잃지 않도록 '받지 않기' 버튼으로만 닫는다.
func _on_root_input(event: InputEvent) -> void:
	if not active or mode != "market" or not OutsideClick.is_press(event):
		return
	var content: Array = [close_btn, purify_btn, reroll_btn]
	for b in buttons:
		content.append(b["btn"])
		content.append(b["label"])
	if not OutsideClick.hits(event.position, content, 24.0):
		root.accept_event()
		close()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton or event is InputEventKey:
		get_viewport().set_input_as_handled()
