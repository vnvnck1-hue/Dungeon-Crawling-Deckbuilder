extends Control
## 하단 손패(기획서 v0.3 §9·14): 카드 표시·확대 설명·월드로 드래그·대상 강조/미리보기, 마녀의 주머니(덱)·버림패 목록, 고용 제안, 양털 판매 창.
## 카드의 누르기·드래그·놓기는 모두 여기서 소비하므로 마녀 이동으로 전달되지 않는다.
## 판정과 소비는 CardUseResolver, 소유는 CardInventory가 맡는다(이 UI는 상태를 표시하고 입력만 전달).

const Cfg := preload("res://scripts/config.gd")
const Catalog := preload("res://scripts/ui/card_catalog.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const MoonLayout := preload("res://scripts/ui/moon/moon_layout.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")

const CardViewScript := preload("res://scripts/ui/card_view.gd")
const PocketGallery := preload("res://scripts/ui/pocket_gallery.gd")
const TreeHighlight := preload("res://scripts/visual/tree_highlight.gd")
const FX := preload("res://scripts/ui/card_fx.gd")
const Extension := preload("res://scripts/ui/moon/moon_extension.gd")
const CarryIcons := preload("res://scripts/ui/carry_bubble.gd")
const WaitGauge := preload("res://scripts/ui/wait_gauge.gd")
const Spotlight := preload("res://scripts/ui/card_spotlight.gd")
const HandTime := preload("res://scripts/ui/hand_focus_time.gd")   # 손패 고민 시간: 세상이 늦춰져도 손패는 실제 시간으로 움직인다

## 손패 배치(디자인 px, 하단 중앙 기준). 하스스톤식 부채꼴.
const CARD_DESIGN := Vector2(98, 147)   # 손패 카드 비율 2:3 (assets/cards/hand 256×384)
const CARD_BOTTOM := 772.0         # 가운데 카드의 바닥선(트레이 위)
const HAND_SPREAD := 560.0         # 8장일 때 손패가 차지하는 최대 폭(창고·관리 버튼과 겹치지 않음)
const FAN_OVERLAP := 0.86          # 카드 간격(카드 폭 비율). 1 미만이면 서로 살짝 겹친다
const FAN_STEP_DEG := 4.5          # 카드 한 장당 기울기
const FAN_TOTAL_DEG := 26.0        # 양 끝 카드 사이 최대 각도
const FAN_RADIUS := 1300.0         # 부채꼴 원호 반지름
const HOVER_SCALE := 1.6           # 마우스를 올린 카드 확대
const HOVER_ROT_DEG := 3.5         # 확대 카드가 마우스 쪽으로 살짝 도는 최대 각도
const HOVER_YAW := 0.7             # 확대 카드 3D 기울기(라디안, 카드 끝에서 끝까지): 좌우
const HOVER_PITCH := 0.55          # 〃 위아래
const PUSH := [0.0, 0.52, 0.28, 0.14]   # 확대 카드 옆 카드가 밀려나는 거리(카드 폭 비율, 거리 1·2·3)
const SWEEP_LIFT := 16.0           # 쓸어 만질 때 마우스 근처 카드가 솟는 높이
const DRAG_TILT := 0.026           # 드래그 속도(px/s) → 기울기(도)
const DRAG_TILT_MAX := 26.0
const DRAG_WORLD_SCALE := 0.8      # 월드 위로 끌고 나갔을 때 카드 크기
const REVEAL_AT := Vector2(800, 400)   # 새 카드를 크게 보여 주는 곳(디자인 px, 화면 가운데 기준)
const REVEAL_SCALE := 1.45
const REVEAL_TIME := 0.55
const USE_SHOW_AT := Vector2(1284, 369)   # 사용한 카드를 타기 전에 크게 보여 주는 곳(디자인 px, 화면 오른쪽 기준·카드 중심)
const USE_SHOW_SCALE := 2.0                # 〃 크기(손패 카드 대비)
const SWAP_OUT_STEP := 0.14       # 낮↔밤 전환: 손패 카드가 한 장씩 주머니로 날아가는 간격
const SWAP_GAP := 0.1              # 마지막 카드가 주머니에 다 빨려 든(STASH_TIME) 뒤 첫 카드가 나오기까지
const STASH_TIME := 0.8           # 손패 카드가 휘어 도는 곡선으로 주머니에 빨려 들어가는 시간
const SWAP_IN_STEP := 0.3         # 새 시간대 카드가 한 장씩 주머니에서 나와 공개되는 간격
const HAND_TOP := 606.0            # 이 선 아래에서 놓으면 사용하지 않고 되돌린다
const PEEK_VISIBLE := 0.8          # 평소(마우스가 손패 밖)에는 카드 높이의 이 비율만 화면 아래로 내밀고 나머지는 숨긴다. 설명판(카드 위에서 약 75%)부터 아래만 가려 제목·일러스트는 다 보인다
const PEEK_IN := 9.0               # 손패가 올라오는 빠르기(지수 감쇠)
const PEEK_OUT := 5.0              # 〃 내려가는 빠르기
const PEEK_LINGER := 1.0           # 손패를 확인하고 마우스가 떠난 뒤에도 이 시간(초) 동안은 숨기지 않는다
const PEEK_MARGIN := 14.0          # 손패 윗선보다 이만큼(디자인 px) 위에서부터 마우스를 손패 쪽으로 본다
const OFFER_DESIGN := Rect2(22, 380, 318, 288)   # 고용 제안: 좌측, 창고 위(중앙 영역 밖)
const C_OK := MoonSkin.GOOD
const C_BAD := MoonSkin.BAD
const C_AMBER := MoonSkin.CREAM
const C_DIM := MoonSkin.LAVENDER

var CW := 106.0
var CH := 160.0

var game
var hud
var views: Dictionary = {}          # uid -> CardView(손패에 있는 카드)
var rest: Dictionary = {}           # uid -> {i, pos, rot} 부채꼴 휴식 위치
var cards_root: Control
var fx
var _leaving: Array = []            # 소모·창고 이동 연출 중인 카드(손패에서는 이미 빠짐)
var _swap_out: Dictionary = {}      # 낮↔밤 전환으로 주머니에 갈 uid → 출발 지연(초). phase_swapped 신호로 채우고 _sync가 소비
var _swap_in: Dictionary = {}       # 전환으로 뽑힌 uid → 공개 지연(초)와 순번 {delay, i}
var _pending_out: Array = []        # 제자리에서 차례를 기다리는 카드 [{v, delay}]
var _pending_in: Array = []         # 주머니 안에 숨어 차례를 기다리는 카드 [{v, e, delay, i}]
var _reveal_row: Array = []         # 화면 가운데 공개 줄(왼쪽부터 들어온 순서). 줄의 카드가 모두 손패로 내려가면 새 줄을 시작한다
var _draw_queue_end := 0.0          # 주머니 드로우 대기열: 마지막으로 예약된 카드가 나오기까지 남은 시간(초)
var arrival_hint: Dictionary = {}   # 카드 id → 화면 위치. 시작 손패 화면이 내려보낸 카드는 그 자리에서 손패로 들어온다(가운데 공개 생략)
var _prev_count: Dictionary = {}
var _prev_zone: Dictionary = {}
var _synced_once := false
var _forced_hover := -1
var peek := 0.0                     # 0 = 반쯤 숨김(평소), 1 = 손패가 다 올라옴. 손패 뒤 소품(HandWorkbench)의 투명도도 이 값을 따른다
var _peek_hold := 0.0
var _last_mouse := Vector2.ZERO
var _mouse := Vector2(-9999, -9999)
var mouse_vel := Vector2.ZERO
var textures: Dictionary = {}
var hover_uid := -1
var drag_uid := -1
var drag_pos := Vector2.ZERO
var _hover_snd := -1  # 마지막으로 오버 소리를 낸 카드
var _target_key := ""  # 끄는 중 마지막으로 소리를 낸 유효 대상(같은 대상 위에서는 다시 울리지 않음)
var plan: Dictionary = {}
var draw_layer: Control
var tooltip: PanelContainer
var tip_title: Label
var tip_sub: Label
var tip_body: Label
var tip_use: Label
var preview: PanelContainer
var preview_title: Label
var preview_body: Label
# 드래그 미리보기 판 두 가지. 매 프레임 Extension.action(tint) 의 키를 만들지 않도록 한 번 받아 둔다.
var _preview_ok_box: StyleBoxTexture
var _preview_bad_box: StyleBoxTexture
var offer_box: VBoxContainer
var offer_rows: Array = []
var pocket_panel: PanelContainer
var pocket_gallery            # PocketGallery: 카드를 넓게 펼친 보기 전용 갤러리
var pocket_list: VBoxContainer  # 갤러리의 섹션·카드 행(검증 스크립트 호환)
var sale_panel: PanelContainer
var sale_uid := -1
var sale_qty := 1
var sale_info: Label
var sale_qty_label: Label
var sale_total: Label
var sale_title: Label
var sale_icon: TextureRect
var empty_hint: Label
var spotlight   # CardSpotlight: 대화 중 얻은 카드를 대화 패널 옆에 띄워 두었다가 대화가 끝나면 손패로 보낸다


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	empty_hint = hud._label("손패가 비어 있습니다 — 아침마다 주머니에서 한 장 · 손님 고용 · 양털 수확 · 표식 괴물 처치로 카드를 얻습니다", 14, Color(MoonSkin.CREAM, 0.7))
	empty_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(empty_hint)
	_build_offers()
	_build_pocket()
	_build_sale()
	_build_tooltip()
	draw_layer = DrawLayer.new()
	draw_layer.hand = self
	draw_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	draw_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(draw_layer)
	cards_root = Control.new()
	cards_root.name = "Cards"
	cards_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cards_root)
	cards_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fx = FX.new()
	fx.name = "CardFx"
	add_child(fx)
	fx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_preview()
	spotlight = Spotlight.new()
	spotlight.hand = self
	add_child(spotlight)
	# 카드 위에 떠야 하는 것들은 맨 뒤로(그리기·입력 모두 위). 툴팁은 주머니 갤러리의 올린 카드 옆에도 뜨므로 창들보다 위에 둔다.
	for top in [pocket_panel, sale_panel, tooltip]:
		move_child(top, -1)
	game.cards.phase_swapped.connect(_on_phase_swapped)
	game.cards.changed.connect(_sync)
	game.economy.offers_changed.connect(_sync_offers)
	resized.connect(_relayout)
	_relayout()
	_sync()


## 화면 크기에 맞춰 디자인 px 기준 배치를 다시 계산한다.
func _relayout() -> void:
	var view := size
	var s := MoonLayout.ui_scale(view)
	CW = CARD_DESIGN.x * s
	CH = CARD_DESIGN.y * s
	for v in views.values():
		v.resize(Vector2(CW, CH))
		_layout_badges(v)
	var hint_at := MoonLayout.to_view(Vector2(800, 712), Vector2(0.5, 1), view)
	empty_hint.position = Vector2(hint_at.x - 400.0, hint_at.y - 12.0)
	empty_hint.size = Vector2(800, 24)
	var o0 := MoonLayout.to_view(OFFER_DESIGN.position, Vector2(0, 1), view)
	var o1 := MoonLayout.to_view(OFFER_DESIGN.end, Vector2(0, 1), view)
	offer_box.position = o0
	offer_box.size = o1 - o0


func _tex(id: String, hand := true, art := -1) -> Texture2D:
	var key := id + ("_h" if hand else "") + ("_a%d" % art if art >= 0 else "")
	if not textures.has(key):
		textures[key] = Catalog.variant_texture(id, art, hand) if art >= 0 else Catalog.texture(id, hand)
	return textures[key]


# ───────────────────────── 구성 ─────────────────────────

func _build_tooltip() -> void:
	tooltip = PanelContainer.new()
	tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tooltip.add_theme_stylebox_override("panel", MoonSkin.tooltip_box())
	tooltip.custom_minimum_size = Vector2(320, 0)
	tooltip.visible = false
	add_child(tooltip)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	tooltip.add_child(v)
	tip_title = hud._title("", 21)
	tip_title.add_theme_color_override("font_color", MoonSkin.PAPER_INK)
	v.add_child(tip_title)
	tip_sub = hud._label("", 13, C_DIM)
	tip_sub.add_theme_color_override("font_color", Color8(98, 71, 85))
	tip_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_sub.custom_minimum_size.x = 296
	v.add_child(tip_sub)
	tip_body = hud._label("", 14)
	tip_body.add_theme_color_override("font_color", MoonSkin.PAPER_INK)
	tip_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_body.custom_minimum_size.x = 296
	v.add_child(tip_body)
	tip_use = hud._label("", 14, C_OK)
	tip_use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_use.custom_minimum_size.x = 296
	v.add_child(tip_use)


func _build_preview() -> void:
	_preview_ok_box = Extension.action()
	_preview_bad_box = Extension.action(Color(1, 0.6, 0.7))
	preview = PanelContainer.new()
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.add_theme_stylebox_override("panel", _preview_ok_box)
	preview.visible = false
	add_child(preview)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	preview.add_child(v)
	preview_title = hud._label("", 17, C_OK)
	v.add_child(preview_title)
	preview_body = hud._label("", 14)
	v.add_child(preview_body)


func _build_offers() -> void:
	offer_box = VBoxContainer.new()
	offer_box.alignment = BoxContainer.ALIGNMENT_END
	offer_box.add_theme_constant_override("separation", 6)
	offer_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(offer_box)


func _build_sale() -> void:
	sale_panel = hud._modal(420, 300)
	sale_panel.reparent(self)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	sale_panel.add_child(v)
	sale_title = hud._title("산장 교역 — 양털 판매", 24)
	v.add_child(sale_title)
	sale_icon = Extension.icon("sheep", 58)
	sale_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(sale_icon)
	sale_info = hud._label("", 14, C_DIM)
	sale_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(sale_info)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	for pair in [["−", -1], ["+", 1]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(52, 44)
		var d: int = pair[1]
		b.pressed.connect(func(): _set_qty(sale_qty + d))
		h.add_child(b)
		if d < 0:
			sale_qty_label = hud._label("1", 26)
			sale_qty_label.custom_minimum_size.x = 60
			sale_qty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.add_child(sale_qty_label)
	var all := Button.new()
	all.text = "전부"
	all.custom_minimum_size = Vector2(70, 44)
	all.pressed.connect(func(): _set_qty(999))
	h.add_child(all)
	sale_total = hud._label("", 18, C_AMBER)
	sale_total.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sale_total)
	var h2 := HBoxContainer.new()
	h2.add_theme_constant_override("separation", 10)
	v.add_child(h2)
	var sell := Button.new()
	sell.text = "판매"
	sell.custom_minimum_size = Vector2(0, 44)
	sell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sell.pressed.connect(_confirm_sale)
	h2.add_child(sell)
	var cancel := Button.new()
	cancel.text = "취소"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel.pressed.connect(close_sale)
	h2.add_child(cancel)


func _build_pocket() -> void:
	# 주머니 버튼은 달빛 HUD의 좌하단 초승달 주머니(moon_hud.gd)가 open_pocket()을 호출한다.
	# 카드를 넓게 펼쳐 보는 갤러리라 창이 크다(작은 화면에서는 Extension.fit_modal 이 축소한다).
	pocket_panel = hud._modal(1500, 790)
	pocket_panel.reparent(self)
	pocket_gallery = PocketGallery.new()
	pocket_gallery.name = "PocketGallery"
	pocket_gallery.hand = self
	pocket_panel.add_child(pocket_gallery)
	pocket_list = pocket_gallery.list
	pocket_gallery.close_requested.connect(close_pocket)


# ───────────────────────── 손패 동기화(등장·퇴장 연출) ─────────────────────────

## 인벤토리 변화를 화면 연출로 옮긴다(규칙은 CardInventory가 결정).
## 새 카드: 출처에서 튀어나와 화면 가운데에서 크게 공개된 뒤 손패로. 주머니에서 뽑은 카드: 주머니에서 날아옴.
## 손패에서 빠진 카드: 주머니로 갔으면 주머니로 날아가고, 사용했으면(활동·버림패) 그 자리에서 섬광과 함께 타 없어진다.
## 스택 수량 변화: 복제본이 날아와 합쳐지거나(획득) 그 자리에서 타며(소모) 배지가 튄다.
func _sync() -> void:
	var hand: Array = game.cards.hand()
	var keep := {}
	for e in hand:
		var uid: int = e["uid"]
		keep[uid] = true
		var count := int(e["count"])
		if not views.has(uid):
			var v = _make_view(e)
			if not _synced_once:
				v.snap(_deck_point(), 0.0, 1.0)
			elif arrival_hint.has(e["id"]):
				# 시작 손패 화면에서 내려온 카드: 그 자리에서 바로 손패 부채꼴로 끼어든다
				v.snap(arrival_hint[e["id"]] + Vector2(0, CH * 0.5), 0.0, 0.62)
				v.t_lift = 1.0
				arrival_hint.erase(e["id"])
			elif _swap_in.has(uid):
				# 낮↔밤 전환으로 뽑힌 카드: 주머니 안에 숨어 있다가 차례가 오면 한 장씩 나와 공개된다
				_hold_for_swap(v, e, _swap_in[uid])
				_swap_in.erase(uid)
			elif spotlight.dialogue_active():
				# 손님 대화로 얻은 카드: 대화 패널 옆에 크게 띄워 두고, 대화가 끝나야 손패로 들어온다
				spotlight.hold_view(v, e)
			elif game.cards.last_drawn.has(uid) or _prev_zone.get(uid, "") == "pocket":
				# 주머니에서 뽑은 카드(아침·효과 드로우): 주머니 안에서 차례를 기다렸다가 한 장씩 나와
				# 화면 가운데 줄에 왼쪽부터 놓이고, 나온 순서대로 손패 오른쪽 끝에 쌓인다.
				# 여러 장 드로우는 장마다 따로 changed 신호가 오므로 대기열 시계(_draw_queue_end)로 간격을 잇는다.
				_hold_for_swap(v, e, {"delay": _draw_queue_end, "i": 0})
				_draw_queue_end += Cfg.DRAW_REVEAL_STEP
			else:
				_start_reveal(v, e)
		elif _synced_once:
			var prev: int = _prev_count.get(uid, count)
			if count > prev and spotlight.dialogue_active():
				spotlight.hold_copy(e, "stack", count - prev)
			elif count > prev:
				_stack_gain(views[uid], e, count - prev)
			elif count < prev:
				_stack_loss(views[uid], e, prev - count)
		if views[uid].card_id != e["id"]:
			_reskin(views[uid], e)
		_refresh_labels(views[uid], e)
		_prev_count[uid] = count
	for uid in views.keys():
		if keep.has(uid):
			continue
		var v = views[uid]
		views.erase(uid)
		_prev_count.erase(uid)
		if hover_uid == uid:
			hover_uid = -1
		var still: Dictionary = game.cards.get_entry(uid)
		if v.get_meta("queued", false):
			# 주머니 안에서 나올 차례를 기다리던(보이지 않는) 카드가 그 사이 빠졌다: 대기열에서 빼고 조용히 없앤다
			_pending_in = _pending_in.filter(func(it): return it["v"] != v)
			_reveal_row.erase(v)
			v.queue_free()
		elif _swap_out.has(uid):
			# 낮↔밤 전환으로 주머니에 가는 카드: 제자리에 멈춰 있다가 차례대로 한 장씩 날아간다
			v.mode = CardViewScript.Mode.LEAVING
			v.t_lift = 1.0
			_pending_out.append({"v": v, "delay": _swap_out[uid]})
			_swap_out.erase(uid)
		elif not still.is_empty() and still["zone"] == "pocket":
			_send_to_pocket(v)
		else:
			_consume_view(v)
	if drag_uid != -1 and not keep.has(drag_uid):
		_cancel_drag()
	# 손패가 가득해 손패를 거치지 않고 바로 주머니로 들어간 새 카드: 창고 보관 소리(손패에서 날아간 카드는 _send_to_pocket 이 낸다)
	if _synced_once:
		for e in game.cards.entries:
			if e["zone"] == "pocket" and not _prev_zone.has(e["uid"]):
				if spotlight.dialogue_active():
					spotlight.hold_copy(e, "pocket")
					continue
				game.sounds.play("card_stash")
				break
	_prev_zone.clear()
	for e in game.cards.entries:
		_prev_zone[e["uid"]] = e["zone"]
	game.cards.last_drawn.clear()
	_synced_once = true
	empty_hint.visible = hand.is_empty() and not (game.mulligan_ui != null and game.mulligan_ui.active)
	if pocket_panel.visible:
		_fill_pocket()


func _s() -> float:
	return MoonLayout.ui_scale(size)


func _make_view(e: Dictionary):
	var v = CardViewScript.new()
	v.uid = e["uid"]
	v.setup(e["id"], _surface(e["id"], e.get("person", ""), int(e.get("art", -1))))
	cards_root.add_child(v)
	v.resize(Vector2(CW, CH))
	_badges(v)
	_layout_badges(v)
	views[e["uid"]] = v
	return v


## 같은 uid 의 카드가 다른 카드로 바뀐 경우(길드 증서로 직업 변경): 그 인물 종족의 새 직업 카드 그림으로
## 통째로 갈아 끼우고, 뒷면에서 핑그르르 돌아 새 앞면이 나오게 한다.
func _reskin(v, e: Dictionary) -> void:
	v.card_id = e["id"]
	v.art.texture = _surface(e["id"], e.get("person", ""), int(e.get("art", -1)))
	v.set_legendary_for(e["id"])
	v.flourish("draw")


## person: 계약 카드의 인물 이름. 그 손님의 종족 카드 그림이 있으면 그것을 쓴다(card_catalog.gd race_texture).
## art: 일러스트 변형 번호(술주정 3종, card_inventory.pick_art). -1 이면 기본 그림.
func _surface(id: String, person := "", art := -1) -> Texture2D:
	var race_tex := Catalog.race_texture(id, person, true)
	if race_tex != null:
		return race_tex
	if art >= 0:
		return _tex(id, true, art)
	return MoonSkin.card_surface(id, _tex(id))


func _refresh_labels(v, e: Dictionary) -> void:
	# 수량 배지는 스택 자원만(명세 §4.5). 계약 인물 이름은 별도 이름표.
	v.badge.text = "×%d" % e["count"] if game.cards.stackable(e["id"]) else ""
	v.badge.get_parent().visible = v.badge.text != ""
	# 계약 인물 이름은 카드 그림(규칙 문구) 위에 겹치지 않고 확대 설명(툴팁)에만 보인다.
	_layout_badges(v)


## 카드 획득 출처(화면 좌표). 정확한 사건 위치는 인벤토리가 알려 주지 않으므로 종류별로 가장 그럴듯한 곳.
func _source_point(id: String) -> Vector2:
	var cam: Camera3D = game.world.camera
	var wp := Vector3.INF
	match id:
		"wool", "black_wool":
			wp = game.player.global_position + Vector3(0, 1.0, 0)
		"lumberjack", "hunter", "warrior", "gatherer":
			wp = game.world.lodge.global_position + Vector3(0, 2.0, 0)
		"timber", "raw_meat", "rabbit_pelt", "treasure_chest":
			# 자원은 마녀가 용병에게서 건네받는다(하수인 목재는 제외)
			wp = game.player.global_position + Vector3(0, 1.2, 0)
		"moonlit_charm", "hearth_ember", "old_tree_heart", "wolf_fang_pendant", "frost_queen_tear":
			return get_viewport_rect().size * 0.5
		"poison_mushroom", "old_spellbook":
			return _pocket_point()
	if wp != Vector3.INF and not cam.is_position_behind(wp):
		var p := cam.unproject_position(wp)
		return p.clamp(Vector2(CW, CH), size - Vector2(CW, 0))
	return _deck_point()


## 출처를 알 수 없을 때 카드가 떠오르는 곳(낮밤판 아래)
func _deck_point() -> Vector2:
	return MoonLayout.to_view(Vector2(800, 260), Vector2(0.5, 0), size)


func _pocket_point() -> Vector2:
	return hud.moon.storage_btn.get_global_rect().get_center() - get_global_rect().position


## hold: 나오기 시작해 손패로 내려가기까지(초). 음수면 기본값(새로 얻은 카드는 줄 순번만큼 조금씩 늦게 내려간다).
func _start_reveal(v, e: Dictionary, from_override := Vector2.INF, scale := REVEAL_SCALE, hold := -1.0) -> void:
	var from := _source_point(e["id"]) if from_override == Vector2.INF else from_override
	v.snap(from, randf_range(-14.0, 14.0), 0.3)
	v.mode = CardViewScript.Mode.REVEAL
	v.set_meta("arrived", false)
	v.set_meta("queued", false)
	v.set_meta("reveal_scale", scale)
	if not _reveal_row.has(v):
		_row_add(v)
	v.timer = hold if hold >= 0.0 else REVEAL_TIME + _reveal_row.find(v) * 0.14
	_layout_row()
	v.t_scl = scale
	v.t_rot = 0.0
	v.t_lift = 1.0
	v.glow_color = FX.GOLD
	v.t_glow = 0.55
	# 뒷면으로 튀어나와 핑그르르 돌며 앞면을 드러내고, 공개 줄에서는 마법에 떠받쳐진 듯 둥실 떠 있다
	v.flourish("draw")
	v.t_float = 1.0
	fx.burst(from, _s(), 18, [FX.CREAM, FX.GOLD], 150.0)
	game.sounds.play("card_draw")


## 공개 줄에 카드를 잇는다. 이전 줄의 카드가 모두 손패로 내려갔으면 새 줄을 시작한다.
func _row_add(v) -> void:
	var live := _reveal_row.filter(func(r): return is_instance_valid(r) and views.get(r.uid) == r and r.mode == CardViewScript.Mode.REVEAL)
	if live.is_empty():
		_reveal_row.clear()
	_reveal_row.append(v)


## 공개 줄을 화면 가운데 기준 왼쪽 → 오른쪽 차례로 늘어놓는다(줄이 길어지면 화면 안에 들도록 간격을 좁힌다).
## 아직 주머니 안에서 차례를 기다리는 카드는 자리만 차지하고 움직이지 않는다.
func _layout_row() -> void:
	var n := _reveal_row.size()
	var at := MoonLayout.to_view(REVEAL_AT, Vector2(0.5, 0.5), size)
	for k in n:
		var v = _reveal_row[k]
		if not is_instance_valid(v) or v.mode != CardViewScript.Mode.REVEAL or v.get_meta("queued", false):
			continue
		var sc: float = v.get_meta("reveal_scale", REVEAL_SCALE)
		var gap := CW * sc * 0.86
		if n > 1:
			gap = minf(gap, (size.x * 0.9 - CW * sc) / (n - 1))
		v.t_pos = at + Vector2((k - (n - 1) * 0.5) * gap, CH * sc * 0.5)


## 공개 위치에 도착하는 순간: 빛 고리와 반짝임
func _reveal_arrived(v) -> void:
	v.set_meta("arrived", true)
	var c: Vector2 = v.t_pos - Vector2(0, CH * v.t_scl * 0.5)
	fx.burst(c, _s(), 34)
	fx.card_glow(c, Vector2(CW, CH) * v.t_scl, v.rot)
	game.sounds.play("card_inspect")  # 화면 가운데에서 크게 펼쳐지는 순간


func _finish_reveal(v) -> void:
	v.mode = CardViewScript.Mode.HAND
	v.t_glow = 0.0
	v.t_float = 0.0
	v.flourish("land")


func _stack_gain(v, e: Dictionary, n: int) -> void:
	var from := _source_point(e["id"])
	fx.burst(from, _s(), 12, [FX.CREAM, FX.GOLD], 140.0)
	var target = v
	fx.fly(_surface(e["id"], e.get("person", ""), int(e.get("art", -1))), from, v.pos, Vector2(CW, CH), 0.75, 0.5, 0.5, func():
		if is_instance_valid(target):
			_stack_landed(target, n))


## 스택 복제본이 손패 카드에 닿는 순간: 배지가 튀고 +n 이 떠오른다
func _stack_landed(target, n: int) -> void:
	_pulse_badge(target)
	var c: Vector2 = target.pos - Vector2(0, CH * target.scl * 0.55)
	game.sounds.play("stack_gain")
	fx.burst(c, _s(), 22, [FX.CREAM, FX.TEAL], 170.0, true)
	fx.float_text(c - Vector2(0, CH * 0.35), "+%d" % n, FX.GOLD, _s())


func _stack_loss(v, e: Dictionary, n: int) -> void:
	# 드래그로 쓴 경우 v는 아직 놓은 자리에 있다 → 그 자리에서 복제본이 날아올라 오른쪽에 크게 보인 뒤 타 없어지고 원본은 손패로 돌아간다
	var show := _use_show_center()
	fx.dissolve_copy(_surface(e["id"], e.get("person", ""), int(e.get("art", -1))), v.pos, Vector2(CW, CH), v.rot, v.scl, show, USE_SHOW_SCALE)
	var c: Vector2 = v.pos - Vector2(0, CH * v.scl * 0.5)
	fx.burst(c, _s(), 18, [FX.CREAM, FX.GOLD], 180.0)
	fx.float_text(c - Vector2(0, CH * 0.4), "-%d" % n, MoonSkin.CREAM, _s())
	_pulse_badge(v)
	_burn_flare_later(show, 30, FX.TEAL, 0.8, 0.65)


func _consume_view(v) -> void:
	var c: Vector2 = v.pos - Vector2(0, CH * v.scl * 0.5)
	var show := _use_show_center()
	v.start_dissolve(Callable(), show, USE_SHOW_SCALE)
	_leaving.append(v)
	game.sounds.play("card_consume")
	fx.burst(c, _s(), 18, [FX.CREAM, FX.GOLD], 180.0)
	_burn_flare_later(show, 46, CardViewScript.BURN_GLOW, 1.15, 0.85)


## 사용한 카드를 크게 보여 주는 화면 지점(카드 중심)
func _use_show_center() -> Vector2:
	return MoonLayout.to_view(USE_SHOW_AT, Vector2(1.0, 0.5), size)


## 보여 주기가 끝나 타기 시작하는 순간, 보여 준 자리에서 빛이 터진다
func _burn_flare_later(at: Vector2, amount: int, edge: Color, strength: float, dur: float) -> void:
	get_tree().create_timer(CardViewScript.SHOW_MOVE + CardViewScript.SHOW_HOLD, false, false, true).timeout.connect(func() -> void:
		if not is_instance_valid(fx):
			return
		fx.burst(at, _s(), amount, [Color(1, 1, 0.9), FX.GOLD, FX.TEAL], 300.0)
		fx.card_glow(at, Vector2(CW, CH) * USE_SHOW_SCALE, 0.0, FX.CREAM, FX.GOLD, edge, strength, dur))


## 낮↔밤 전환(CardInventory.phase_swapped): 나가는 카드는 왼쪽부터 SWAP_OUT_STEP 간격, 들어오는 카드는 마지막 카드가 들어간 뒤 SWAP_GAP 쉬고 SWAP_IN_STEP 간격.
func _on_phase_swapped(out_uids: Array, in_uids: Array) -> void:
	for i in out_uids.size():
		_swap_out[out_uids[i]] = i * SWAP_OUT_STEP
	var start: float = ((out_uids.size() - 1) * SWAP_OUT_STEP + STASH_TIME + SWAP_GAP) if not out_uids.is_empty() else 0.0
	for j in in_uids.size():
		_swap_in[in_uids[j]] = {"delay": start + j * SWAP_IN_STEP, "i": j}


## 전환으로 뽑힌 카드를 주머니 안에 숨겨 두고(보이지 않음·공개 대기) 차례를 기다리게 한다.
func _hold_for_swap(v, e: Dictionary, how: Dictionary) -> void:
	v.fade = 0.0
	v.t_fade = 0.0
	v.t_lift = 1.0
	v.snap(_pocket_point() + Vector2(0, CH * 0.12), -24.0, 0.22)   # snap이 _apply()로 투명 상태를 바로 반영
	v.mode = CardViewScript.Mode.REVEAL
	v.timer = 999.0
	v.set_meta("arrived", true)
	v.set_meta("queued", true)
	_row_add(v)   # 나오기 전부터 줄 자리를 잡아 둔다 → 줄 순서 = 나오는 순서 = 손패에 들어가는 순서
	_pending_in.append({"v": v, "e": e, "delay": float(how["delay"]), "i": int(how["i"])})


## 전환 대기열을 진행한다. 나가는 카드는 차례가 오면 주머니로 날아가고, 들어오는 카드는 차례가 오면 주머니에서 나와 가운데에 공개된다.
func _step_swap(delta: float) -> void:
	_draw_queue_end = maxf(_draw_queue_end - delta, 0.0)
	for item in _pending_out.duplicate():
		item["delay"] -= delta
		if item["delay"] <= 0.0:
			_pending_out.erase(item)
			_send_to_pocket(item["v"])
	for item in _pending_in.duplicate():
		item["delay"] -= delta
		if item["delay"] <= 0.0:
			_pending_in.erase(item)
			var v = item["v"]
			if not is_instance_valid(v) or not views.has(v.uid):
				continue
			v.fade = 1.0
			v.t_fade = 1.0
			_start_reveal(v, item["e"], _pocket_point(), Cfg.DRAW_REVEAL_SCALE, Cfg.DRAW_REVEAL_HOLD)


## 전환 연출이 진행 중인가(검증·캡처용).
func swap_animating() -> bool:
	return not _pending_out.is_empty() or not _pending_in.is_empty()


func _send_to_pocket(v) -> void:
	v.mode = CardViewScript.Mode.LEAVING
	v.timer = 0.0
	var to := _pocket_point() + Vector2(0, CH * 0.12)
	v.t_pos = to
	v.t_scl = 0.14
	v.t_rot = -24.0
	v.t_lift = 1.0
	v.t_float = 0.0
	# 곧은 선이 아니라 휘어 도는 곡선으로 빨려 든다(사용자 요청 2026-10-23): 먼저 위·바깥으로 휙 끌려 올랐다가
	# 소용돌이처럼 옆에서 감겨 들어가며 점점 빨라진다. 위치·회전·크기는 _step_suck 이 곡선대로 직접 정한다
	var from: Vector2 = v.pos
	var d := to - from
	var side := Vector2(-d.y, d.x).normalized() if d.length() > 1.0 else Vector2.UP
	if side.y > 0.0:
		side = -side   # 언제나 위로 부푸는 쪽으로 휜다
	var reach := maxf(d.length(), CH)
	v.set_meta("suck", {
		"from": from, "to": to,
		"c1": from + side * reach * 0.3 + Vector2(0, -CH * 0.2),
		"c2": to + side.rotated(-0.6) * reach * 0.3,
		"rot": v.rot, "spin": -200.0 - randf() * 70.0, "scl": v.scl, "done": false})
	v.path_lock = true
	v.flourish("stash", STASH_TIME)   # 휘청 끌려가다 비틀려 꼬이고 끝에 두루마리처럼 말려 든다
	_leaving.append(v)
	game.sounds.play("card_stash")


## 주머니 흡입 곡선을 한 걸음 진행한다: 3차 베지어 위를 갈수록 빨라지며 돌고 작아지고, 끝에서 흐려지며 주머니에 반짝임을 남긴다.
func _step_suck(v, delta: float) -> void:
	var s: Dictionary = v.get_meta("suck")
	var u := clampf(v.timer / STASH_TIME, 0.0, 1.0)
	var e := 0.3 * u * u * (3.0 - 2.0 * u) + 0.7 * pow(u, 2.4)   # 처음 살짝 끌려간 뒤 빨려 들수록 가속
	var a: Vector2 = s["from"]
	var b: Vector2 = s["c1"]
	var c: Vector2 = s["c2"]
	var d: Vector2 = s["to"]
	var k := 1.0 - e
	var p := a * k * k * k + b * 3.0 * k * k * e + c * 3.0 * k * e * e + d * e * e * e
	if delta > 0.0:
		v.vel = (p - v.pos) / delta   # 휨·펄럭임(step_warp)이 곡선 위 실제 속도에 반응하도록
	v.pos = p
	v.rot = float(s["rot"]) + float(s["spin"]) * e
	v.scl = lerpf(float(s["scl"]), 0.14, u * u * (3.0 - 2.0 * u))   # 위치보다 먼저 작아져 멀리서부터 빨려 드는 느낌
	var gone := clampf((u - 0.72) / 0.28, 0.0, 1.0)
	v.fade = 1.0 - gone * gone
	v.t_fade = v.fade
	v.t_glow = 0.6 * sin(PI * u)
	if u >= 0.9 and not s["done"]:
		s["done"] = true
		fx.burst(d, _s(), 14, [Color(0.85, 0.7, 1.0), FX.CREAM, FX.TEAL], 120.0)


func _pulse_badge(v) -> void:
	var b: Control = v.badge.get_parent()
	b.pivot_offset = b.size * 0.5
	b.scale = Vector2.ONE * 1.7
	var tw := b.create_tween().set_ignore_time_scale(true)
	tw.tween_property(b, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


## 수량 배지(시안의 청록 원형 배지 바탕, 카드 위 독립 레이어)와 계약 인물 이름표
func _badges(cv) -> void:
	var holder := TextureRect.new()
	holder.texture = MoonSkin.tex("stack_badge")
	holder.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	holder.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cv.add_child(holder)
	var l: Label = hud._label("", 15, MoonSkin.CREAM)
	l.add_theme_font_override("font", MoonSkin.font(true))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.add_child(l)
	cv.badge = l


## 배지 위치는 카드 크기 비율로. 수량 배지는 왼쪽 아래 모서리(사용자 결정 2026-10-18):
## 부채꼴 손패에서는 오른쪽 카드가 왼쪽 카드의 오른쪽 부분을 덮으므로, 왼쪽 아래가 겹쳐도 항상 보인다.
func _layout_badges(v) -> void:
	var sz: Vector2 = v.size
	var bp: Control = v.badge.get_parent()
	bp.size = Vector2(sz.x * 0.36, sz.x * 0.30)
	bp.position = Vector2(sz.x * 0.02, sz.y - sz.x * 0.33)  # 배지 밑변이 카드 밑변 안쪽에 오도록(부채꼴 끝 카드가 화면 아래로 내려가도 숫자가 보이게)
	v.badge.add_theme_font_size_override("font_size", maxi(11, int(sz.x * 0.15)))


func hand_top() -> float:
	return MoonLayout.to_view(Vector2(800, HAND_TOP), Vector2(0.5, 1), size).y


# ───────────────────────── 부채꼴 배치·마우스 반응 ─────────────────────────

## 손패에 남아 있는 카드(드래그·공개 중인 카드는 빠져 있어 나머지가 자리를 좁힌다)
func _slot_uids() -> Array:
	var out: Array = []
	for e in game.cards.hand():
		var v = views.get(e["uid"])
		if v != null and v.mode == CardViewScript.Mode.HAND and e["uid"] != drag_uid:
			out.append(e["uid"])
	return out


## 부채꼴 휴식 위치: 큰 원호 위에 카드 아래 가운데를 놓고 바깥으로 갈수록 기울인다.
func _compute_rest() -> void:
	rest.clear()
	var s := _s()
	var slots := _slot_uids()
	var n := slots.size()
	var spacing := minf(CW * FAN_OVERLAP, (HAND_SPREAD * s - CW) / maxf(n - 1, 1))
	var step := minf(FAN_STEP_DEG, FAN_TOTAL_DEG / maxf(n - 1, 1))
	var center := MoonLayout.to_view(Vector2(800, CARD_BOTTOM), Vector2(0.5, 1), size) + Vector2(0, _peek_drop())
	var r := FAN_RADIUS * s
	for i in n:
		var t := i - (n - 1) * 0.5
		var dx := t * spacing
		rest[slots[i]] = {"i": i, "pos": Vector2(center.x + dx, center.y + dx * dx / (2.0 * r)), "rot": t * step}


## 반쯤 숨긴 손패가 내려가 있는 거리. 다 숨기면 가운데 카드의 PEEK_VISIBLE 만큼만 화면 아래에 걸친다.
func _peek_drop() -> float:
	var bottom := MoonLayout.to_view(Vector2(800, CARD_BOTTOM), Vector2(0.5, 1), size).y
	var hidden := maxf(0.0, size.y + CH * (1.0 - PEEK_VISIBLE) - bottom)
	return hidden * (1.0 - smoothstep(0.0, 1.0, peek))


## 마우스가 손패 쪽에 있는지: 현재(올라오는 중이면 그만큼 올라간) 손패 윗선 아래, 손패 좌우 폭 안.
## 올라올수록 윗선도 올라가므로 한 번 올라온 손패는 카드 위를 훑는 동안 내려가지 않는다.
func _mouse_near_hand(p: Vector2) -> bool:
	if rest.is_empty() or modal_open() or game.session.is_over():
		return false
	var l := INF
	var rgt := -INF
	var top := INF
	for uid in rest:
		var pos: Vector2 = rest[uid]["pos"]
		l = minf(l, pos.x)
		rgt = maxf(rgt, pos.x)
		top = minf(top, pos.y - CH)
	return p.x >= l - CW and p.x <= rgt + CW and p.y >= top - PEEK_MARGIN * _s() and p.y <= size.y


## 손패 등장·숨김: 마우스가 손패 쪽에 오거나 카드를 확대·드래그 중이면 올라오고, 떠나면 잠깐 머문 뒤 내려간다.
func _update_peek(delta: float) -> void:
	var want := drag_uid != -1 or _forced_hover != -1 or hover_uid != -1 or _mouse_near_hand(_mouse)
	if want:
		_peek_hold = PEEK_LINGER
	else:
		_peek_hold = maxf(0.0, _peek_hold - delta)
	var target := 1.0 if _peek_hold > 0.0 else 0.0
	peek = lerpf(peek, target, 1.0 - exp(-delta * (PEEK_IN if target > peek else PEEK_OUT)))
	if absf(peek - target) < 0.002:
		peek = target


func _in_rest(p: Vector2, r: Dictionary) -> bool:
	var l: Vector2 = (p - r["pos"]).rotated(-deg_to_rad(r["rot"]))
	return absf(l.x) <= CW * 0.5 and l.y >= -CH and l.y <= CH * 0.4


func _hover_rect(uid: int) -> Rect2:
	var t := _hover_target(uid)
	return Rect2(t.x - CW * HOVER_SCALE * 0.5, t.y - CH * HOVER_SCALE, CW * HOVER_SCALE, CH * HOVER_SCALE)


## 확대 카드: 손패 위로 곧게 솟아 화면 아래에 붙고, 화면 끝에서 잘리지 않는다.
func _hover_target(uid: int) -> Vector2:
	var r: Dictionary = rest[uid]
	var half := CW * HOVER_SCALE * 0.5
	return Vector2(clampf(r["pos"].x, half + 8.0, size.x - half - 8.0), size.y - 4.0 * _s())


## 마우스가 가리키는 카드. 휴식 위치(밀려나기 전) 기준이라 확대·밀림에 흔들리지 않는다.
## 오른쪽 카드가 위에 겹쳐 있으므로 오른쪽부터 검사한다. 확대된 카드 위에 머물면 유지한다.
func _pick(p: Vector2) -> int:
	if drag_uid != -1 or modal_open() or game.session.is_over():
		return -1
	if get_viewport().gui_get_hovered_control() != null:
		return -1
	var order: Array = rest.keys()   # _compute_rest 가 i 순서로 넣으므로 이미 정렬돼 있다
	order.reverse()
	for uid in order:
		if _in_rest(p, rest[uid]):
			return uid
	if rest.has(hover_uid) and _hover_rect(hover_uid).has_point(p):
		return hover_uid
	return -1


func _update_hover(delta: float) -> void:
	var mouse := _mouse
	mouse_vel = mouse_vel.lerp((mouse - _last_mouse) / maxf(delta, 0.001), 1.0 - exp(-delta * 12.0))
	if mouse.distance_to(_last_mouse) > 1.5:
		_forced_hover = -1
	_last_mouse = mouse
	if _forced_hover != -1:
		hover_uid = _forced_hover if rest.has(_forced_hover) and drag_uid == -1 else -1
	else:
		hover_uid = _pick(mouse)
	if hover_uid != _hover_snd:
		_hover_snd = hover_uid
		if hover_uid != -1:
			game.sounds.play("card_hover")
			if views.has(hover_uid):
				views[hover_uid].flourish("hover")


func _layout(delta: float) -> void:
	_compute_rest()
	_update_hover(delta)
	_update_peek(delta)
	_compute_rest()
	var s := _s()
	var mouse := _last_mouse
	var hi: int = rest[hover_uid]["i"] if rest.has(hover_uid) else -1
	var span_l := INF
	var span_r := -INF
	for uid in rest:
		span_l = minf(span_l, rest[uid]["pos"].x)
		span_r = maxf(span_r, rest[uid]["pos"].x)
	var center_y := MoonLayout.to_view(Vector2(800, CARD_BOTTOM), Vector2(0.5, 1), size).y + _peek_drop()
	var in_zone := drag_uid == -1 and not rest.is_empty() and mouse.y >= center_y - CH * 1.3 \
		and mouse.x >= span_l - CW and mouse.x <= span_r + CW and _forced_hover == -1
	# 카드마다 get_entry(선형 탐색)를 부르지 않도록 이번 프레임의 uid → 항목 표를 한 번 만든다(get_entry 처럼 먼저 나온 것)
	var by_uid := {}
	for e in game.cards.entries:
		if not by_uid.has(e["uid"]):
			by_uid[e["uid"]] = e
	for uid in rest:
		var v = views[uid]
		var r: Dictionary = rest[uid]
		var tp: Vector2 = r["pos"]
		var tr: float = r["rot"]
		var ts := 1.0
		var lift := 0.0
		var e: Dictionary = by_uid.get(uid, {})
		var playable := not e.is_empty() and _usage_text(e).begins_with("▶")
		var glow := 0.22 if playable else 0.0
		var tilt := Vector2.ZERO
		var yaw3 := 0.0
		var pitch3 := 0.0
		var floaty := 0.0
		if hi != -1 and r["i"] != hi:
			# 확대된 카드 양옆은 거리에 따라 밀려난다
			var d: int = r["i"] - hi
			tp.x += signf(d) * CW * PUSH[mini(absi(d), PUSH.size() - 1)]
		if in_zone:
			# 쓸어 만지기: 마우스 근처 카드가 솟고, 마우스가 지나가는 방향으로 살짝 쓸린다
			var f := exp(-pow((mouse.x - r["pos"].x) / (CW * 0.85), 2.0))
			tp.y -= SWEEP_LIFT * s * f
			tr = tr * (1.0 - 0.4 * f) + clampf(mouse_vel.x * 0.006, -7.0, 7.0) * f
			lift = 0.3 * f
		if uid == hover_uid:
			tp = _hover_target(uid)
			tr = 0.0
			ts = HOVER_SCALE
			lift = 1.0
			glow = 0.6 if playable else 0.25
			# 확대 카드는 마우스가 있는 쪽으로 실제로 살짝 회전한다(만지는 느낌). 원근 셰이더는 쓰지 않는다
			var hr := _hover_rect(uid)
			if hr.has_point(mouse):
				var lx := (mouse.x - hr.get_center().x) / hr.size.x
				tr = clampf(lx * HOVER_ROT_DEG * 2.0, -HOVER_ROT_DEG, HOVER_ROT_DEG) 					+ clampf(mouse_vel.x * 0.003, -1.5, 1.5)
				# 3D 기울기: 마우스가 누르는 쪽 가장자리가 안으로 들어간다(카드를 손끝으로 만지는 입체감)
				var ly := (mouse.y - hr.get_center().y) / hr.size.y
				yaw3 = clampf(lx, -0.5, 0.5) * HOVER_YAW
				pitch3 = -clampf(ly, -0.5, 0.5) * HOVER_PITCH
			floaty = 0.45
		v.t_yaw = yaw3
		v.t_pitch = pitch3
		v.t_float = floaty
		v.t_pos = tp
		v.t_rot = tr
		v.t_scl = ts
		v.t_lift = lift
		v.t_glow = glow
		v.glow_color = FX.TEAL
		v.t_tilt = tilt
	if drag_uid != -1 and views.has(drag_uid):
		_layout_drag(views[drag_uid])
	# 그리기 순서: 손패 왼쪽→오른쪽, 확대 카드, 공개·퇴장 카드, 드래그 카드
	var order: Array = []
	for uid in rest:   # i 순서(왼쪽→오른쪽)로 들어 있다
		if uid != hover_uid:
			order.append(views[uid])
	if rest.has(hover_uid):
		order.append(views[hover_uid])
	for v in views.values():
		if v.mode == CardViewScript.Mode.REVEAL:
			order.append(v)
	order.append_array(_leaving)
	if drag_uid != -1 and views.has(drag_uid):
		order.append(views[drag_uid])
	# 대화 옆에 띄워 둔 카드(CardSpotlight 층)는 순서에서 뺀다
	order = order.filter(func(x): return x.get_parent() == cards_root)
	for j in order.size():
		if order[j].get_index() != j:
			cards_root.move_child(order[j], j)


## 드래그 중인 카드: 커서를 스프링으로 따라오며, 따라오는 속도만큼 관성으로 기운다.
## 손패 위에서는 살짝 크게, 월드 위로 나가면 작아져 대상이 보이게 한다.
func _layout_drag(v) -> void:
	var over_world := drag_pos.y < hand_top()
	v.t_scl = DRAG_WORLD_SCALE if over_world else 1.12
	# 손패 위: 커서가 카드 가운데. 월드 위: 카드가 커서 아래로 비켜 서서 대상 지점이 가려지지 않고 화살표가 위로 가리킨다
	var below: float = CH * v.scl + 26.0 * _s()
	v.t_pos = drag_pos + Vector2(0, below if over_world else CH * v.scl * 0.5)
	v.t_rot = clampf(v.vel.x * DRAG_TILT, -DRAG_TILT_MAX, DRAG_TILT_MAX)
	v.t_tilt = Vector2.ZERO  # 원근 셰이더 대신 실제 회전(관성)만 쓴다
	v.t_lift = 1.0
	# 끄는 동안 마법에 떠받쳐 둥실 일렁이고, 움직임에 따라 휘고 비틀린다(CardView.step_warp)
	v.t_yaw = 0.0
	v.t_pitch = 0.0
	v.t_float = 0.55
	if over_world and not plan.is_empty():
		v.glow_color = FX.TEAL if plan.get("ok", false) else Color(1.0, 0.35, 0.35)
		v.t_glow = 0.7
	else:
		v.glow_color = FX.TEAL
		v.t_glow = 0.35


func _step_views(delta: float) -> void:
	_step_swap(delta)
	_step_flying(delta)
	for v in views.values():
		if v.mode == CardViewScript.Mode.REVEAL:
			v.timer -= delta
			if not v.get_meta("arrived", true) and v.pos.distance_to(v.t_pos) < CH * 0.25:
				_reveal_arrived(v)
			if v.timer <= 0.0:
				_finish_reveal(v)
		v.step(delta)
	for v in (_leaving.duplicate() if not _leaving.is_empty() else _leaving):
		var done := false
		if v.mode == CardViewScript.Mode.DYING:
			v.step(delta)
			done = v.tick_dissolve(delta)
		else:
			v.timer += delta
			if v.has_meta("suck"):
				_step_suck(v, delta)
			v.step(delta)
			done = v.timer >= (STASH_TIME if v.has_meta("suck") else 0.55)
		if done:
			_leaving.erase(v)
			v.queue_free()


# ───────────────────────── 설명(마우스 올림) ─────────────────────────

func _usage_text(e: Dictionary) -> String:
	var st: int = game.session.state
	var day_or_night: bool = st in [SessionScript.State.PREP, SessionScript.State.COMBAT]
	if game.cards.is_corruption(e["id"]):
		return "침식 카드 — 쓸 수 없습니다. 이끼 붕대·장날 정화로 없애세요"
	if game.player != null and game.player.wolf:
		return "늑대는 카드를 쓸 수 없습니다 — 새벽에 마녀로 돌아옵니다"
	if Cfg.EQUIPMENT.has(e["id"]):
		var eqd: Dictionary = Cfg.EQUIPMENT[e["id"]]
		var to: String = {"witch": "마녀", "merc": "용병"}.get(eqd.get("who", "any"), "마녀나 용병")
		return "▶ %s(또는 초상)에게 끌어 %s 칸에 장착 · %s" % [to, Cfg.EQUIP_SLOT_NAMES[eqd["slot"]], game.equipment.effect_text(e["id"])]
	match e["id"]:
		"wolf_blood":
			return "▶ 마녀에게 끌어 달의 힘 3장을 주머니에 (잠시 괴로워함)" if day_or_night else "지금은 쓸 수 없습니다"
		"crescent_moon", "half_moon", "full_moon":
			var why: String = game.moon_powers.block_reason(e["id"])
			if why != "":
				return why
			return {"crescent_moon": "▶ 마녀에게 끌어 오늘 밤 공격 속도 상승 (1회용)",
				"half_moon": "▶ 마녀에게 끌어 오늘 밤 공격·이동 속도 상승 (1회용)",
				"full_moon": "▶ 마녀에게 끌어 오늘 밤 늑대로 변신 · Q 할퀴기 · E 덮치기 (손패 잠김, 1회용)"}[e["id"]]
		"moss_bandage":
			return "▶ 마녀에게 끌어 체력 +%d · 침식 카드 1장 정화" % int(Cfg.MOSS_HEAL) if day_or_night else "지금은 쓸 수 없습니다"
		"resin_torch":
			return "▶ 적이나 지면으로 끌어 송진 불길" if st == SessionScript.State.COMBAT else "송진 횃불은 밤 전투 중에만 쓸 수 있습니다"
		"vine_snare":
			return "▶ 적이나 지면으로 끌어 덩굴로 묶기" if st == SessionScript.State.COMBAT else "덩굴 덫은 밤 전투 중에만 쓸 수 있습니다"
		"thorn_bind":
			return "▶ 적이나 지면으로 끌어 넓게 가시 속박" if st == SessionScript.State.COMBAT else "가시 속박은 밤 전투 중에만 쓸 수 있습니다"
		"firefly_swarm":
			return "▶ 지면으로 끌어 넓은 안개 걷기 (밤 전투가 끝날 때까지)" if day_or_night else "지금은 쓸 수 없습니다"
		"winter_firewood":
			return "▶ 산장으로 끌어 체력 +%d (밤에도 가능)" % int(Cfg.FIREWOOD_REPAIR) if day_or_night else "지금은 쓸 수 없습니다"
		"shroud_cloth":
			return "▶ 아무 땅에나 끌어 오늘 밤 수의 축복" if day_or_night else "지금은 쓸 수 없습니다"
		"red_chalice":
			return "▶ 마녀에게 끌어 오늘 밤 흡혈 축복" if day_or_night else "지금은 쓸 수 없습니다"
		"hibernation_pelt":
			return "▶ 산장으로 끌어 오늘 밤 산장 피해 절반" if day_or_night else "지금은 쓸 수 없습니다"
		"dragon_scale":
			var dr: String = game.dragon.block_reason()
			return "▶ 산장으로 끌어 지붕에 용 부르기 (웨이브당 1번)" if dr == "" else dr
		"sleeping_thorn_seed":
			return "▶ 지면으로 끌어 심기 · 낮에 성장, 밤에 방어" if st == SessionScript.State.PREP else "가시 씨앗은 낮 준비 시간에만 심을 수 있습니다"
		"black_sheep":
			return "▶ 목장으로 끌어 입식 · 다음 날부터 검은 털 생산" if st == SessionScript.State.PREP else "가축 입식은 준비 시간에만 가능합니다"
		"black_wool":
			return "▶ 가시 씨앗이나 방책으로 끌어 강화·전체 회복" if st in [SessionScript.State.PREP, SessionScript.State.COMBAT] else "지금은 의식을 치를 수 없습니다"
		"lumberjack":
			if st == SessionScript.State.PREP:
				return "▶ 벌목할 나무로 끌어 놓기 (둘러싸인 나무는 불가)"
			return "벌목은 낮에만 시작할 수 있습니다"
		"hunter", "warrior":
			if st == SessionScript.State.PREP:
				return "▶ 지면으로 끌어 배치 · 정찰하다 적이 오면 자동 전투"
			if st == SessionScript.State.COMBAT:
				return "▶ 적이나 지면으로 끌어 전투 합류"
		"gatherer":
			if st == SessionScript.State.PREP:
				return "▶ 지면으로 끌어 놓으면 숲 탐색을 떠남 (저녁 전 귀환)"
			return "채집은 낮에만 떠날 수 있습니다"
		"raw_meat":
			if st == SessionScript.State.PREP:
				return "▶ 산장으로 끌어 판매 (1개 %dG) · 마녀에게 끌어 체력 +%d · 켜진 모닥불로 끌어 스튜" % [Cfg.MEAT_PRICE, int(Cfg.MEAT_HEAL)]
			return "▶ 마녀에게 끌어 체력 +%d · 켜진 모닥불로 끌어 스튜 (판매는 낮에만)" % int(Cfg.MEAT_HEAL)
		"meat_stew":
			return "▶ 다친 용병에게 끌어 체력 +최대의 %d%% (밤에도 가능)" % int(Cfg.STEW_HEAL_RATIO * 100.0) if day_or_night else "지금은 쓸 수 없습니다"
		"rabbit_pelt":
			if st == SessionScript.State.PREP:
				return "▶ 산장으로 끌어 판매 (1개 %dG)" % Cfg.PELT_PRICE
			return "판매는 준비 시간에만 가능합니다"
		"treasure_chest":
			return "▶ 땅에 끌어 놓으면 상자가 열림 · 유물 셋 중 하나 선택"
		"poison_mushroom":
			if game.cards.eligible_pocket_empty():
				return "주머니에 지금 뽑을 카드가 없어 사용할 수 없습니다 (비용 없음)"
			return "▶ 마녀에게 끌어 체력 -%d · 주머니에서 1장 드로우" % int(Cfg.MUSHROOM_HP_COST)
		"old_spellbook":
			if game.cards.eligible_pocket_empty():
				return "주머니에 지금 뽑을 카드가 없어 사용할 수 없습니다 (비용 없음)"
			return "▶ 어디든 끌어 놓으면 주머니의 %d장을 펼쳐 1장 복제" % mini(Cfg.SPELLBOOK_CHOICES, game.cards.eligible_pocket().size())
		"forest_monster":
			if st == SessionScript.State.PREP or st == SessionScript.State.COMBAT:
				return "▶ 적이나 지면으로 끌어 하수인 소환"
		"wool":
			if st == SessionScript.State.PREP:
				return "▶ 산장으로 끌어 판매 (1개 %dG)" % Cfg.WOOL_PRICE
			return "판매는 준비 시간에만 가능합니다"
		"timber":
			if st == SessionScript.State.PREP:
				return "▶ 산장으로 끌어 수리 (%d개 → 체력 +%d) · 모닥불로 끌어 장작 +%d초 · 감시탑 공터로 끌어 적립·수리" % [Cfg.TIMBER_REPAIR_COST, int(Cfg.TIMBER_REPAIR_AMOUNT), int(Cfg.CAMPFIRE_FUEL_PER_TIMBER)]
			return "▶ 모닥불로 끌어 장작 +%d초 (수리·적립은 준비 시간에만)" % int(Cfg.CAMPFIRE_FUEL_PER_TIMBER)
		"frost_rune":
			if st == SessionScript.State.COMBAT:
				return "▶ 적이나 지면으로 끌어 서리 룬 폭발"
			return "서리 룬은 밤 전투 중에만 새길 수 있습니다"
		"ward_lantern":
			if st == SessionScript.State.PREP or st == SessionScript.State.COMBAT:
				return "▶ 지면으로 끌어 등불 설치 (밤 전투가 끝날 때까지)"
		"guest_invitation":
			if st == SessionScript.State.PREP:
				return "▶ 산장으로 끌어 손님 초대"
			return "손님 초대는 준비 시간에만 가능합니다"
		"lamb":
			if st == SessionScript.State.PREP:
				return "▶ 목장으로 끌어 새끼양 입식 (%d일 뒤 어른 양)" % Cfg.LAMB_GROW_DAYS
			return "가축 입식은 준비 시간에만 가능합니다"
	return "지금은 사용할 수 없습니다"


func _update_tooltip() -> void:
	if spotlight.update_tooltip():
		return
	if pocket_panel.visible:
		_update_pocket_tooltip()
		return
	if hover_uid == -1 or drag_uid != -1 or not views.has(hover_uid):
		tooltip.visible = false
		return
	var e: Dictionary = game.cards.get_entry(hover_uid)
	if e.is_empty():
		tooltip.visible = false
		return
	_fill_tooltip(e)
	tip_use.text = _usage_text(e)
	MoonSkin.set_font_color(tip_use, Color8(35, 97, 78) if tip_use.text.begins_with("▶") else Color8(98, 71, 85))
	if not rest.has(hover_uid):
		tooltip.visible = false
		return
	_place_tooltip(_hover_rect(hover_uid))


## 주머니 갤러리에서 들어 올린 카드 옆에 툴팁을 띄운다(사용법 대신 카드가 어느 구역에 있는지 적는다).
func _update_pocket_tooltip() -> void:
	if not pocket_gallery.hovering():
		tooltip.visible = false
		return
	_fill_tooltip(pocket_gallery.hover_entry)
	tip_use.text = pocket_gallery.zone_note()
	MoonSkin.set_font_color(tip_use, Color8(98, 71, 85))
	_place_tooltip(pocket_gallery.lifted_rect())


func _fill_tooltip(e: Dictionary) -> void:
	var d: Dictionary = game.cards.def(e["id"])
	tip_title.text = d.get("name", e["id"]) + ("  ×%d" % int(e.get("count", 1)) if game.cards.stackable(e["id"]) else "")
	var sub: String = d.get("category", "")
	if e.get("person", "") != "":
		sub += "  ·  계약 인물: " + e["person"]
	sub += "  ·  획득: " + d.get("acquisition", "")
	tip_sub.text = sub
	tip_body.text = d.get("description", "")


## 카드 사각형(화면 좌표)의 오른쪽에, 자리가 없으면 왼쪽에 툴팁을 둔다. 세로는 카드 위 끝에 맞추되 화면 안에 가둔다.
func _place_tooltip(hr: Rect2) -> void:
	var vp := size
	tooltip.reset_size()
	var x := hr.end.x + 14.0
	if x + tooltip.size.x > vp.x - 16.0:
		x = hr.position.x - 14.0 - tooltip.size.x
	x = clampf(x, 12.0, maxf(12.0, vp.x - tooltip.size.x - 12.0))
	tooltip.position = Vector2(x, clampf(hr.position.y, 12.0, vp.y - tooltip.size.y - 12.0))
	tooltip.visible = true


# ───────────────────────── 드래그 ─────────────────────────

## 보름달 늑대는 손패가 잠긴다(사용자 확정 2026-10-18)
func wolf_locked() -> bool:
	return game.player != null and game.player.wolf


func can_drag() -> bool:
	if wolf_locked():
		return false
	return not game.session.is_over() and not get_tree().paused and not modal_open()


## 늑대의 피: 주머니로 직접 들어간 달 카드 세 장이 마녀 머리 위에서 솟아 주머니 버튼으로 날아가는 연출(인벤토리는 이미 바뀌어 있다).
var _flying: Array = []   # [{v, timer}]

func fly_to_pocket(ids: Array, world_pos: Vector3) -> void:
	var cam: Camera3D = game.world.camera
	var from: Vector2 = get_viewport_rect().size * 0.5
	if not cam.is_position_behind(world_pos):
		from = cam.unproject_position(world_pos) - get_global_rect().position
	for i in ids.size():
		var v = CardViewScript.new()
		v.uid = -1
		v.setup(ids[i], _surface(ids[i]))
		cards_root.add_child(v)
		v.resize(Vector2(CW, CH))
		v.snap(from + Vector2(0, CH * 0.3), randf_range(-10.0, 10.0), 0.2)
		v.mode = CardViewScript.Mode.REVEAL
		v.t_pos = from + Vector2((i - 1) * CW * 0.7, -CH * 0.35)
		v.t_scl = 0.62
		v.t_rot = (i - 1) * 9.0
		v.t_lift = 1.0
		v.glow_color = Color(0.75, 0.6, 1.0)
		v.t_glow = 0.6
		_flying.append({"v": v, "timer": 0.75 + i * 0.22})
	fx.burst(from, _s(), 26, [Color(0.85, 0.7, 1.0), FX.CREAM], 220.0)


func _step_flying(delta: float) -> void:
	for f in _flying.duplicate():
		var v = f["v"]
		f["timer"] -= delta
		v.step(delta)
		if f["timer"] <= 0.0:
			_flying.erase(f)
			_send_to_pocket(v)


func begin_drag(uid: int) -> void:
	if drag_uid != -1:
		return
	if not can_drag():
		return
	if not views.has(uid):
		return
	drag_uid = uid
	drag_pos = get_viewport().get_mouse_position()
	plan = {}
	tooltip.visible = false
	hover_uid = -1
	_forced_hover = -1
	# 카드가 손패에서 빠져나와 커서를 따라간다(나머지 카드는 빈자리를 좁힌다)
	views[uid].mode = CardViewScript.Mode.DRAG
	views[uid].flourish("pickup")
	_target_key = ""
	game.sounds.play("card_pickup")


func _cancel_drag() -> void:
	TreeHighlight.clear()
	if views.has(drag_uid):
		views[drag_uid].mode = CardViewScript.Mode.HAND  # 스프링으로 손패 자리로 날아 돌아간다
	drag_uid = -1
	plan = {}
	_target_key = ""
	preview.visible = false
	draw_layer.queue_redraw()


## 플레이어가 직접 취소했을 때(손패 위에 놓기·우클릭·Esc). 카드가 사라져 끊긴 드래그는 소리 없이 _cancel_drag 만.
func _cancel_by_player() -> void:
	if drag_uid == -1:
		return
	if views.has(drag_uid):
		views[drag_uid].flourish("return")   # 한 바퀴 비틀어 돌며 손패로 돌아간다
	_cancel_drag()
	game.sounds.play("card_cancel")


func _end_drag() -> void:
	var uid := drag_uid
	var pos := drag_pos
	if pos.y >= hand_top():
		_cancel_by_player()
		return  # 손패 위에서 놓으면 사용하지 않고 되돌린다
	# 판정 동안 카드는 놓은 자리에 둔다: 소모되면 그 자리에서 타 없어지고, 아니면 손패로 돌아간다
	drag_uid = -1
	preview.visible = false
	TreeHighlight.clear()
	var result: Dictionary = game.resolver.commit(uid, pos)
	plan = {}
	draw_layer.queue_redraw()
	if views.has(uid):
		# 소모되지 않고 손패에 남은 카드(실패·스택 일부 사용)는 한 바퀴 돌며 손패로 돌아간다
		views[uid].mode = CardViewScript.Mode.HAND
		views[uid].flourish("return")
	_target_key = ""
	if not result["ok"]:
		game.toast(result["reason"], Color(1.0, 0.65, 0.65))
		game.sounds.play("card_deny")
	elif result["action"] == "sell":
		open_sale(uid)


func _input(event: InputEvent) -> void:
	# 마우스 위치는 입력 이벤트로만 추적한다(실제 커서·주입된 테스트 입력 모두 같은 경로)
	if event is InputEventMouse:
		_mouse = (event as InputEventMouse).position
	if drag_uid == -1:
		var press := event as InputEventMouseButton
		if press != null and press.pressed and press.button_index == MOUSE_BUTTON_LEFT and can_drag():
			_compute_rest()
			var uid := _pick(press.position)
			if uid != -1:
				begin_drag(uid)
				drag_pos = press.position
				get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		drag_pos = event.position
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			drag_pos = mb.position
			_end_drag()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cancel_by_player()
			game.toast("카드 사용을 취소했습니다", Color(0.85, 0.82, 1.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_cancel_by_player()
		get_viewport().set_input_as_handled()


func _update_drag() -> void:
	if drag_uid == -1:
		preview.visible = false
		return
	if not can_drag():
		_cancel_drag()
		return
	if drag_pos.y >= hand_top():
		plan = {}
		_target_key = ""
		preview.visible = false
		TreeHighlight.clear()
		draw_layer.queue_redraw()
		return
	plan = game.resolver.evaluate(drag_uid, drag_pos)
	_sync_tree_highlight()
	# 유효 대상에 처음 닿거나 다른 유효 대상으로 옮겼을 때만 한 번 울린다
	var key: String = plan.get("title", "") if plan["ok"] else ""
	if key != "" and key != _target_key:
		game.sounds.play("card_target")
	_target_key = key
	if plan["ok"]:
		preview_title.text = plan["title"]
		MoonSkin.set_font_color(preview_title, C_OK)
		preview_body.text = "\n".join(plan["lines"])
		MoonSkin.set_stylebox(preview, _preview_ok_box)
	else:
		preview_title.text = "사용할 수 없음"
		MoonSkin.set_font_color(preview_title, C_BAD)
		preview_body.text = plan["reason"]
		MoonSkin.set_stylebox(preview, _preview_bad_box)
	preview.reset_size()
	var vp := get_viewport_rect().size
	var p := drag_pos + Vector2(62, -60)
	if p.x + preview.size.x > vp.x - 12:
		p.x = drag_pos.x - 62 - preview.size.x
	p.y = clampf(p.y, 12, vp.y - preview.size.y - 12)
	preview.position = p
	preview.visible = true
	draw_layer.queue_redraw()


## 나무꾼 카드를 끄는 동안 마우스 아래 나무의 모델 전체를 물들이고 외곽선을 두른다.
func _sync_tree_highlight() -> void:
	if drag_uid == -1:
		TreeHighlight.clear()
		return
	var e: Dictionary = game.cards.get_entry(drag_uid)
	if e.is_empty() or e["id"] != "lumberjack":
		TreeHighlight.clear()
		return
	var t = plan.get("tree")
	if t == null or not t is Dictionary or t.is_empty() or t.get("removed", false):
		TreeHighlight.clear()
		return
	TreeHighlight.set_target(t, bool(plan.get("ok", false)))


func _ring(c: Control, cam: Camera3D, center: Vector3, radius: float, color: Color, width := 2.5) -> void:
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * i / 32.0
		pts.append(cam.unproject_position(center + Vector3(cos(a) * radius, 0.05, sin(a) * radius)))
	c.draw_polyline(pts, color, width, true)


## 하스스톤식 대상 화살표: 카드 위쪽에서 대상까지 휘어지는 곡선 위로 갈매기 무늬가 흘러가고 끝에 화살촉.
func _draw_arrow(c: Control, a: Vector2, b: Vector2, col: Color) -> void:
	var dist := a.distance_to(b)
	if dist < 12.0:
		return
	var s := _s()
	var ctrl := a.lerp(b, 0.5) + Vector2(0, -minf(dist * 0.35, 160.0 * s))
	var pts := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		pts.append(a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t))
	c.draw_polyline(pts, Color(col, 0.16), 14.0 * s, true)
	c.draw_polyline(pts, Color(col, 0.35), 5.0 * s, true)
	# 흘러가는 갈매기 무늬
	var gap := 22.0 * s
	var count := int(dist / gap)
	var phase := fmod(Time.get_ticks_msec() / 1000.0 * 2.2, 1.0)
	for k in count:
		var t := clampf((k + phase) / float(count + 1), 0.0, 0.92)
		var p := a.lerp(ctrl, t).lerp(ctrl.lerp(b, t), t)
		var tan := (ctrl - a).lerp(b - ctrl, t).normalized()
		var nrm := Vector2(-tan.y, tan.x)
		var w := 7.0 * s * (0.6 + 0.4 * t)
		var alpha := 0.35 + 0.65 * t
		c.draw_polyline(PackedVector2Array([p - tan * w * 0.6 + nrm * w, p + tan * w * 0.4, p - tan * w * 0.6 - nrm * w]), Color(col, alpha), 3.0 * s, true)
	# 화살촉
	var tb := (b - ctrl).normalized()
	var nb := Vector2(-tb.y, tb.x)
	var h := 18.0 * s
	var head := PackedVector2Array([b, b - tb * h + nb * h * 0.62, b - tb * h * 0.62, b - tb * h - nb * h * 0.62])
	c.draw_colored_polygon(head, Color(col, 0.95))
	c.draw_polyline(PackedVector2Array([head[0], head[1], head[2], head[3], head[0]]), Color(0.05, 0.03, 0.1, 0.8), 1.5 * s, true)


func draw_drag(c: Control) -> void:
	if drag_uid == -1:
		return
	var e: Dictionary = game.cards.get_entry(drag_uid)
	if e.is_empty():
		return
	var cam: Camera3D = game.world.camera
	var st: int = game.session.state
	var font := c.get_theme_default_font()
	# 유효 대상 강조
	if e["id"] == "lumberjack":
		# 마우스 아래 나무만 강조한다(모델 전체 색·외곽선은 TreeHighlight, 여기서는 라벨만). 바닥 고리는 없다.
		var t = plan.get("tree")
		if t != null and t is Dictionary and not t.is_empty() and not t.get("removed", false):
			var ok: bool = plan["ok"]
			var col := Color(1.0, 0.9, 0.55, 0.95) if ok else Color(0.75, 0.7, 0.8, 0.9)
			var lp := cam.unproject_position(t["pos"] + Vector3(0, minf(t["height"] * 0.55, 3.2), 0))
			var txt := "목재 %d" % t["remaining"] if ok else str(plan.get("reason", ""))
			if ok and t["remaining"] < t["max"]:
				txt += " / %d" % t["max"]
			txt = tr(txt)
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			c.draw_string_outline(font, lp + Vector2(-w * 0.5, -8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, 5, Color(0.05, 0.03, 0.1, 0.95))
			c.draw_string(font, lp + Vector2(-w * 0.5, -8), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, col)
	if e["id"] == "raw_meat":
		var pp = game.player
		if pp != null and not pp.dead:
			_ring(c, cam, pp.global_position, 0.7, Color(0.75, 1.0, 0.75, 0.75), 2.5)
	if e["id"] in ["hunter", "warrior", "forest_monster"] and st == SessionScript.State.COMBAT:
		for en in game.get_tree().get_nodes_in_group("enemies"):
			if not en.dead:
				_ring(c, cam, en.global_position, 0.55, Color(1.0, 0.5, 0.45, 0.7), 2.0)
	if e["id"] in ["frost_rune"] and st == SessionScript.State.COMBAT:
		for en in game.get_tree().get_nodes_in_group("enemies"):
			if not en.dead and en.visible:
				_ring(c, cam, en.global_position, 0.55, Color(0.62, 0.86, 1.0, 0.7), 2.0)
	if e["id"] in ["lamb", "black_sheep"] and st == SessionScript.State.PREP:
		var pr: Rect2 = game.world.pasture.rect
		_ring(c, cam, Vector3(pr.get_center().x, 0, pr.get_center().y), maxf(pr.size.x, pr.size.y) * 0.55, Color(1.0, 0.95, 0.75, 0.75), 3.0)
	if e["id"] == "guest_invitation" and st == SessionScript.State.PREP:
		_ring(c, cam, game.world.lodge.global_position, 3.6, Color(1.0, 0.8, 0.45, 0.75), 3.0)
	if e["id"] in ["wool", "timber", "raw_meat", "rabbit_pelt"] and st == SessionScript.State.PREP:
		_ring(c, cam, game.world.lodge.global_position, 3.6, Color(1.0, 0.8, 0.45, 0.75), 3.0)
	# 실제 소환·작업 위치
	if e["id"] == "black_wool":
		for plant in get_tree().get_nodes_in_group("thorn_plants"):
			_ring(c, cam, plant.global_position, 0.75, C_OK if plant.can_receive_offering() else C_DIM, 3.0)
	if plan.has("pos") and plan["pos"] != null:
		var ok: bool = plan["ok"]
		var col2 := C_OK if ok else C_BAD
		var where: Vector3 = plan["pos"]
		if plan.has("radius"):
			_ring(c, cam, where, plan["radius"], Color(col2, 0.85), 3.0)
		if plan.get("action", "") in ["guard", "chop", "gather", "chest"] or not ok:
			_ring(c, cam, where, 0.5, col2, 3.5)
			_ring(c, cam, where, 0.25, Color(col2, 0.5), 2.0)
		var from: Vector2 = views[drag_uid].pos - Vector2(0, CH * views[drag_uid].scl) if views.has(drag_uid) else drag_pos
		_draw_arrow(c, from, cam.unproject_position(where), col2)


# ───────────────────────── 고용 제안 ─────────────────────────

func _sync_offers() -> void:
	for row in offer_rows:
		row["panel"].queue_free()
	offer_rows.clear()
	for o in game.economy.offers:
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", Extension.row())
		offer_box.add_child(p)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 10)
		p.add_child(h)
		var icon := TextureRect.new()
		icon.texture = _surface(game.economy.offer_job(o), o.get("person", ""))
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(48, 72)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(icon)
		var v := VBoxContainer.new()
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		v.add_child(hud._title("손님 %s · 일자리를 찾습니다" % o["person"], 15))
		v.add_child(hud._label(_job_blurb(game.economy.offer_job(o)), 13, C_DIM))
		var t: Label = hud._label("", 13, C_DIM)
		v.add_child(t)
		var gauge := WaitGauge.new()  # 떠나기까지 남은 시간(글 없이도 한눈에)
		gauge.custom_minimum_size = Vector2(0, 6)
		v.add_child(gauge)
		var b := Button.new()
		b.text = "고용 %dG" % game.economy.contract_cost()
		b.custom_minimum_size = Vector2(84, 44)
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.pressed.connect(_on_hire.bind(o))
		h.add_child(b)
		offer_rows.append({"panel": p, "offer": o, "time": t, "gauge": gauge, "button": b})


func _job_blurb(job: String) -> String:
	match job:
		"lumberjack": return "나무꾼 계약 · 벌목, 목재 보관·전달"
		"hunter": return "사냥꾼 계약 · 사냥, 밤에는 활로 방어"
		"warrior": return "전투용병 계약 · 정찰과 근접 전투"
		"gatherer": return "채집가 계약 · 숲 탐색, 보물상자 발견"
	return "용병 계약"


func _on_hire(o: Dictionary) -> void:
	if not game.economy.hire(o):
		game.toast("고용할 수 없습니다 — " + game.economy.hire_block_reason(o), Color(1.0, 0.7, 0.7))


func _update_offers() -> void:
	for row in offer_rows:
		var o: Dictionary = row["offer"]
		var reason: String = game.economy.hire_block_reason(o)
		row["button"].disabled = reason != ""
		var left: float = game.economy.offer_time_left(o)
		row["time"].text = "%d초 뒤 떠남" % int(ceil(left)) + ("  ·  " + reason if reason != "" else "")
		row["gauge"].ratio = left / Cfg.HIRE_WAIT


# ───────────────────────── 창고 ─────────────────────────

func modal_open() -> bool:
	return pocket_panel.visible or sale_panel.visible


func open_pocket() -> void:
	if game.session.is_over() or hud.pause_panel.visible:
		return
	_cancel_drag()
	pocket_panel.visible = true
	game.sounds.play("panel_open")
	_fill_pocket()
	hud.refresh_pause()


func close_pocket() -> void:
	if pocket_panel.visible:
		game.sounds.play("panel_close")
	pocket_panel.visible = false
	hud.refresh_pause()


func _fill_pocket() -> void:
	pocket_gallery.fill()


# ───────────────────────── 재화 판매 ─────────────────────────
# 재화는 한 장에 수량으로 쌓이므로(2026-10-18 묶음 복원) 산장에 놓으면 판매 수량을 고르는 창을 연다.

func open_sale(uid: int) -> void:
	var e: Dictionary = game.cards.get_entry(uid)
	if e.is_empty():
		return
	sale_uid = uid
	sale_panel.visible = true
	game.sounds.play("panel_open")
	_set_qty(int(e["count"]))
	hud.refresh_pause()


func close_sale() -> void:
	if sale_panel.visible:
		game.sounds.play("panel_close")
	sale_panel.visible = false
	sale_uid = -1
	hud.refresh_pause()


func _set_qty(q: int) -> void:
	var e: Dictionary = game.cards.get_entry(sale_uid)
	if e.is_empty():
		close_sale()
		return
	var nq := clampi(q, 1, int(e["count"]))
	if nq != sale_qty and sale_panel.visible:
		game.sounds.play("qty_tick")
	sale_qty = nq
	var price: int = Cfg.SALE_PRICES.get(e["id"], Cfg.WOOL_PRICE)
	var nm: String = game.cards.def(e["id"]).get("name", e["id"])
	sale_icon.texture = CarryIcons.icon_for(e["id"])
	sale_title.text = "산장 교역 — %s 판매" % nm
	sale_info.text = "보유 %s %d개 · 1개 %dG · 판매할 때만 골드를 받습니다" % [nm, e["count"], price]
	sale_qty_label.text = str(sale_qty)
	sale_total.text = "판매 금액 +%dG" % (sale_qty * price)


func _confirm_sale() -> void:
	game.economy.sell_resource(sale_uid, sale_qty)
	close_sale()


func close_all() -> void:
	_cancel_drag()
	pocket_panel.visible = false
	sale_panel.visible = false


# ───────────────────────── 매 프레임 ─────────────────────────

func _process(delta: float) -> void:
	delta = HandTime.ui_delta(delta)
	var over: bool = game.session.is_over()
	cards_root.visible = not over
	offer_box.visible = not over
	# 보름달 늑대: 손패가 어두워져 잠겼음을 보여 준다
	var locked: bool = game.player != null and game.player.wolf
	cards_root.modulate = cards_root.modulate.lerp(Color(0.5, 0.45, 0.6) if locked else Color.WHITE, clampf(delta * 6.0, 0.0, 1.0))
	if sale_panel.visible and game.session.state != SessionScript.State.PREP:
		close_sale()
	_layout(delta)
	_step_views(delta)
	_update_drag()
	_update_tooltip()
	_update_offers()


## 개발·검증용: 마우스를 움직이기 전까지 지정한 카드를 확대 상태로 둔다.
func set_hover(uid: int, on: bool) -> void:
	if on:
		_forced_hover = uid
		_last_mouse = _mouse
	elif _forced_hover == uid:
		_forced_hover = -1
	hover_uid = uid if on else (-1 if hover_uid == uid else hover_uid)


class DrawLayer extends Control:
	var hand

	func _process(_delta: float) -> void:
		if hand.drag_uid != -1:
			queue_redraw()

	func _draw() -> void:
		hand.draw_drag(self)
