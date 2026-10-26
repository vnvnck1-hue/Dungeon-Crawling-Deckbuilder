extends CanvasLayer
## 대화 중 얻은 카드 보여 주기(사용자 요청 2026-10-20).
## 손님 대화로 카드를 얻으면 대화 패널 오른쪽 위(대답 열 자리)에 카드를 크게 띄워 둔다. 마우스를 올리면 설명(툴팁)을
## 충분히 읽을 수 있고, 대화가 완전히 끝나야(닫혀야) 그때 한 장씩 손패(가득 찼으면 주머니)로 날아 들어간다.
## 대화의 어두운 막(shade 19)·패널(20)·조작부(21)보다 위(22)에 그려 대화 내내 밝게 보인다.
## 판정·소유는 건드리지 않는다: CardHand._sync 가 넘겨준 손패 카드(CardView)와 표시용 복제본만 다룬다.

const CardViewScript := preload("res://scripts/ui/card_view.gd")
const FX := preload("res://scripts/ui/card_fx.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")

const SPOT_CENTER := Vector2(1365, 165)   # 대화 stage 좌표: 대답 열(SIDE_X 1150 · SIDE_W 430) 가운데, 패널 위 끝에 걸침
const SPOT_HEIGHT := 420.0                # 〃 카드 높이('이야기 이어 듣기' 버튼 위 끝 448 에 닿지 않는다)
const SPOT_WIDTH := 480.0                 # 여러 장일 때 늘어놓는 폭
const ENTER_TIME := 0.5                   # 뒷면으로 나타나 돌며 자리 잡기까지
const HOVER_GROW := 1.06                  # 마우스를 올린 카드
const RELEASE_STEP := 0.16                # 대화가 끝난 뒤 한 장씩 떠나는 간격
const FLY_TIME := 0.62                    # 복제본(스택·주머니)이 날아가는 시간
const FLY_BRIGHT := 1.28                  # 손패로 날아가는 동안의 밝기(도착 전까지 또렷하게)
const DIM_TIME := 1.1                     # 손패 자리에 닿은 뒤 손패 밝기로 천천히 가라앉는 시간

var hand    # CardHand
var root: Control
var fx
## {v: CardView, kind: "hand"|"stack"|"pocket", uid, e(획득 당시 항목), n(스택 증가량), tex, age, landed, rect}
## hand: 손패에 새로 생긴 카드 자체를 잠시 이 층으로 옮겨 둔 것. stack·pocket: 표시용 복제본.
var items: Array = []
var hover_item = null
var landing: Array = []   # 손패로 날아가는 중인 카드(이 층에 남아 끝까지 위에 그려진다) {v, uid, dimming}


func _ready() -> void:
	name = "CardSpotlight"
	layer = 22
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = hand.hud.theme_res   # 툴팁을 잠시 옮겨 와도 글꼴·판이 그대로
	add_child(root)
	fx = FX.new()
	fx.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(fx)


func dialogue_active() -> bool:
	var ui = hand.game.get("guest_ui")
	return ui != null and ui.dialogue_active


func holding() -> bool:
	return not items.is_empty()


## 손패에 새로 생긴 카드: 대화가 끝날 때까지 이 층에서 보여 준다.
func hold_view(v, e: Dictionary) -> void:
	v.reparent(root)
	_add({"v": v, "kind": "hand", "uid": e["uid"], "e": e.duplicate(), "n": 1,
		"tex": hand._surface(e["id"], e.get("person", ""), int(e.get("art", -1)))})


## 이미 손패에 있는 스택이 늘었거나(stack), 손패가 가득해 바로 주머니로 간 카드(pocket): 복제본을 보여 준다.
func hold_copy(e: Dictionary, kind: String, n := 1) -> void:
	var tex: Texture2D = hand._surface(e["id"], e.get("person", ""), int(e.get("art", -1)))
	var v = CardViewScript.new()
	v.setup(e["id"], tex)
	root.add_child(v)
	v.resize(Vector2(hand.CW, hand.CH))
	_add({"v": v, "kind": kind, "uid": e["uid"], "e": e.duplicate(), "n": n, "tex": tex})


func _add(item: Dictionary) -> void:
	item["age"] = 0.0
	item["landed"] = false
	item["rect"] = Rect2()
	items.append(item)
	var v = item["v"]
	var sp := _spot()
	var c: Vector2 = sp["center"] + Vector2((items.size() - 1) * sp["w"] * 0.5, 0)
	v.mode = CardViewScript.Mode.REVEAL
	v.timer = INF                 # CardHand 가 공개를 끝내지 않게(놓아줄 때 직접 끝낸다)
	v.set_meta("arrived", true)
	v.set_meta("queued", false)
	v.fade = 1.0
	v.t_fade = 1.0
	v.shadow_mul = 0.0   # 크게 띄운 카드의 그림자가 옆 툴팁·아래 대답 버튼을 덮지 않게(금빛 후광만 남긴다)
	# 뒷면으로 작게 나타나 핑그르르 돌며 앞면을 드러내고, 마법에 떠받쳐진 듯 둥실 떠 있다
	v.snap(c + Vector2(0, sp["h"] * 0.5 + 40.0 * sp["k"]), randf_range(-12.0, 12.0), sp["scl"] * 0.35)
	v.t_lift = 1.0
	v.glow_color = FX.GOLD
	v.t_glow = 0.55
	v.t_float = 1.0
	v.flourish("draw")
	fx.burst(c, hand._s(), 18, [FX.CREAM, FX.GOLD], 150.0)
	hand.game.sounds.play("card_draw")
	_layout()


## 카드 자리(화면 좌표). 대화 stage 와 같은 배율로 따라간다.
func _spot() -> Dictionary:
	var ui = hand.game.get("guest_ui")
	var k: float = 1.0
	var base: Vector2 = Vector2.ZERO
	if ui != null:
		k = ui.buttons.scale.x
		base = ui.buttons.position
	var h: float = SPOT_HEIGHT * k
	var scl: float = h / hand.CH
	return {"center": base + SPOT_CENTER * k, "h": h, "w": hand.CW * scl, "scl": scl, "k": k}


func _layout() -> void:
	var sp := _spot()
	var n := items.size()
	# 여러 장이면 폭 안에 겹치지 않고 나란히 들도록 함께 줄인다
	var fit := minf(1.0, SPOT_WIDTH * sp["k"] / (n * sp["w"] * 1.06))
	sp["scl"] *= fit
	var w: float = sp["w"] * fit
	var h: float = sp["h"] * fit
	var gap := w * 1.06
	for i in n:
		var item: Dictionary = items[i]
		var v = item["v"]
		var c: Vector2 = sp["center"] + Vector2((i - (n - 1) * 0.5) * gap, 0)
		var hot: bool = item == hover_item
		var s: float = sp["scl"] * (HOVER_GROW if hot else 1.0)
		item["rect"] = Rect2(c - Vector2(w, h) * 0.5, Vector2(w, h))
		v.t_pos = c + Vector2(0, h * 0.5 * s / sp["scl"])
		v.t_scl = s
		v.t_rot = 0.0
		v.t_glow = 0.85 if hot else 0.5
		v.glow_color = FX.GOLD
		v.t_float = 0.6 if hot else 1.0
		# 자리 잡는 순간: 빛 고리와 반짝임(가운데 공개와 같은 연출)
		if not item["landed"] and item["age"] >= ENTER_TIME:
			item["landed"] = true
			fx.burst(c, hand._s(), 34)
			fx.card_glow(c, Vector2(w, h), 0.0)
			hand.game.sounds.play("card_inspect")


func _process(delta: float) -> void:
	delta = preload("res://scripts/ui/hand_focus_time.gd").ui_delta(delta)   # 손패 고민 시간으로 세상이 늦춰져도 실제 시간으로
	_step_landing()
	if items.is_empty():
		return
	if not dialogue_active():
		_release_all()
		return
	# 대화 중에 손패에서 빠진 카드(드문 경우)는 CardHand 가 처리하도록 손패 층으로 돌려보낸다
	for item in items.duplicate():
		var v = item["v"]
		if not is_instance_valid(v):
			items.erase(item)
		elif item["kind"] == "hand" and hand.views.get(item["uid"]) != v:
			v.reparent(hand.cards_root)
			items.erase(item)
	for item in items:
		item["age"] += delta
	_pick()
	_layout()
	for item in items:
		if item["kind"] != "hand":
			item["v"].step(delta)   # 손패 카드는 CardHand._step_views 가 움직인다
	if hover_item != null:
		root.move_child(hover_item["v"], -1)
	# 툴팁은 늘 카드보다 위(카드 그림자·후광이 툴팁 판을 덮지 않게)
	if hand.tooltip.get_parent() == root:
		root.move_child(hand.tooltip, -1)


func _pick() -> void:
	var found = null
	for i in range(items.size() - 1, -1, -1):
		if items[i]["landed"] and items[i]["rect"].has_point(hand._mouse):
			found = items[i]
			break
	if found != hover_item:
		hover_item = found
		if found != null:
			hand.game.sounds.play("card_hover")
			found["v"].flourish("hover")


## CardHand._update_tooltip 이 먼저 부른다. 보여 주는 카드에 마우스가 있으면 툴팁을 이 층으로 옮겨 채우고 true.
func update_tooltip() -> bool:
	var tip: Control = hand.tooltip
	if hover_item == null or not dialogue_active():
		_return_tooltip()
		return false
	if tip.get_parent() != root:
		tip.reparent(root, false)
	var e: Dictionary = hover_item["e"]
	if hover_item["kind"] != "pocket":
		var now: Dictionary = hand.game.cards.get_entry(hover_item["uid"])
		if not now.is_empty():
			e = now
	hand._fill_tooltip(e)
	var where := "주머니로" if hover_item["kind"] == "pocket" else "손패로"
	hand.tip_use.text = "새로 얻은 카드 — 대화를 마치면 %s 들어갑니다" % where
	MoonSkin.set_font_color(hand.tip_use, Color8(98, 71, 85))
	hand._place_tooltip(hover_item["rect"])
	return true


func _return_tooltip() -> void:
	var tip: Control = hand.tooltip
	if tip.get_parent() == root:
		tip.visible = false
		tip.reparent(hand, false)
		hand.move_child(tip, -1)


## 대화가 끝났다: 왼쪽부터 한 장씩 손패(주머니)로 보낸다.
func _release_all() -> void:
	_return_tooltip()
	hover_item = null
	var out := items.duplicate()
	items.clear()
	for i in out.size():
		if i == 0:
			_release(out[i])
		else:
			var item: Dictionary = out[i]
			get_tree().create_timer(RELEASE_STEP * i, true, false, true).timeout.connect(func(): _release(item))


func _release(item: Dictionary) -> void:
	var v = item["v"]
	if not is_instance_valid(v):
		return
	v.shadow_mul = 1.0   # 손패로 돌아가면 그림자도 손패 카드처럼
	var size_px := Vector2(hand.CW, hand.CH)
	var c: Vector2 = v.pos - Vector2(0, hand.CH * v.scl * 0.5)
	hand.fx.burst(c, hand._s(), 16, [FX.CREAM, FX.GOLD], 160.0)
	match item["kind"]:
		"hand":
			if hand.views.get(item["uid"]) != v:
				v.reparent(hand.cards_root)
				return
			# 손패 부채꼴 자리로 한 바퀴 비틀며 날아 들어간다(스프링 이동은 CardHand 가 맡는다).
			# 날아가는 동안은 이 층(모든 대화 막·창 위)에 남아 밝게 빛나고, 자리에 닿아서야 천천히 가라앉는다(_step_landing).
			hand._finish_reveal(v)
			v.flourish("return")
			v.modulate = Color(FLY_BRIGHT, FLY_BRIGHT, FLY_BRIGHT, v.modulate.a)
			landing.append({"v": v, "uid": item["uid"], "dimming": false})
			hand.game.sounds.play("card_draw")
		"stack":
			var target = hand.views.get(item["uid"])
			var to: Vector2 = target.pos if target != null else hand._deck_point()
			var n: int = item["n"]
			fx.fly(item["tex"], v.pos, to, size_px, v.scl, 1.0, FLY_TIME, func():
				if is_instance_valid(target):
					hand._stack_landed(target, n))
			v.queue_free()
		"pocket":
			fx.fly(item["tex"], v.pos, hand._pocket_point() + Vector2(0, hand.CH * 0.12), size_px, v.scl, 0.22, FLY_TIME, func():
				hand.game.sounds.play("card_stash"))
			v.queue_free()


## 손패를 덮고 있는 막의 밝기(대화가 다시 열려 어두운 막이 있으면 그만큼 어둡게). 막이 없으면 1.
func _cover_level() -> float:
	var ui = hand.game.get("guest_ui")
	if ui != null and ui.shade.visible:
		return 1.0 - ui.shade.color.a
	return 1.0


## 날아가는 카드가 손패 자리에 닿으면 그때부터 DIM_TIME 동안 손패 밝기(막이 있으면 막 아래 밝기)로 천천히 가라앉고,
## 다 가라앉은 뒤에야 손패 층으로 돌아간다(막 아래로 들어가도 밝기가 같아 이음매가 보이지 않는다).
func _step_landing() -> void:
	for it in landing.duplicate():
		var v = it["v"]
		if not is_instance_valid(v):
			landing.erase(it)
			continue
		if hand.views.get(it["uid"]) != v or v.mode != CardViewScript.Mode.HAND:
			_land(it)
			continue
		if it["dimming"] or v.pos.distance_to(v.t_pos) > hand.CH * 0.08:
			continue
		it["dimming"] = true
		var from: float = v.modulate.r
		var to := _cover_level()
		var tw: Tween = v.create_tween().set_ignore_time_scale(true)
		tw.tween_method(func(x: float):
			if is_instance_valid(v):
				v.modulate = Color(x, x, x, v.modulate.a), from, to, DIM_TIME).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_callback(func(): _land(it))


func _land(it: Dictionary) -> void:
	landing.erase(it)
	var v = it["v"]
	if not is_instance_valid(v):
		return
	if v.get_parent() != hand.cards_root:
		v.reparent(hand.cards_root)
	v.modulate = Color(1, 1, 1, v.modulate.a)


## 손패로 날아가는 중이거나 자리에서 가라앉는 중인가(검증용)
func landing_count() -> int:
	return landing.size()
