extends SceneTree
## 마우스 입력 경로 헤드리스 검증: 실제 InputEvent 를 main._unhandled_input 에 넣는다.
## 카드 끌어 놓기 · 눌러 고른 뒤 적 누르기 · 딤드 강조 · 근접 돌진 · 행동력 부족 카드 거부 · 오른쪽 클릭 취소 ·
## 턴 종료 → 다음 턴 행동력 3·손패 5 · 한 부채꼴 · 피격 넉백(jolt). 손패는 검증용으로 정해 둔 카드로 바꿔 넣는다.
## 실행(godot 폴더 기준):  <Godot> --headless --path . --script res://dungeon/tools/verify_input.gd

const D := preload("res://dungeon/data/defs.gd")

var main
var passed := 0
var total := 0
var t := 0.0
var step := 0
var wait := 0.0
var started := false
var memo := {}


func check(name: String, ok: bool) -> void:
	total += 1
	if ok:
		passed += 1
	print(("PASS " if ok else "FAIL ") + name)


func _initialize() -> void:
	Engine.time_scale = 3.0
	main = load("res://dungeon/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


func _move(p: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = p
	main._unhandled_input(e)


func _button(p: Vector2, pressed: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.position = p
	e.button_index = button
	e.pressed = pressed
	main._unhandled_input(e)


func _key(id: String) -> String:
	for k in main.battle.hand:
		if D.base_id(k) == id:
			return k
	return ""


func _card_pos(id: String) -> Vector2:
	var v: Control = main.hand.views[_key(id)]
	return v.get_global_transform() * (v.size * Vector2(0.5, 0.35))


func _unit_screen(u) -> Vector2:
	return main.world.camera.unproject_position(main.world.cell_pos(main.room, u.cell))


func _ready_turn() -> bool:
	return main.mode == "battle" and not main.busy and main.battle.phase == "player"


## 손패를 정해진 카드로 바꿔 넣는다(뽑은 카드는 뽑을 패로 되돌린다).
func _force_hand(ids: Array) -> void:
	var b = main.battle
	b.draw_pile.append_array(b.hand)
	b.hand.clear()
	var n := 900
	for id in ids:
		b.hand.append("%s#%d" % [id, n])
		n += 1
	main.hand.clear_all()
	main.hand.deal(b.hand)
	main._refresh()


func _process(delta: float) -> bool:
	t += delta
	wait -= delta
	if not started:
		started = true
		main.hud._select_root.queue_free()
		main.hud._select_root = null
		main._start(D.HERO_ORDER.duplicate())
		return false
	if t > 150.0:
		check("제한 시간", false)
		return _done()
	if main.hud.choosing_card():
		main.hud.pick_option(0)
		return false
	if wait > 0.0:
		return false
	var b = main.battle
	match step:
		0:
			if _ready_turn():
				_force_hand(["frost_rune", "magic_bolt", "aimed_shot", "slash", "war_cry"])
				wait = 1.2   # 카드가 손패 자리로 날아와 자리 잡을 때까지
				step = 1
		1:
			check("손패 5장", b.hand.size() == 5 and main.hand.views.size() == 5)
			# ① 행동력 부족 카드를 누르면 거부 + 안내(마법사 행동력을 1로 낮춰서)
			b.hero("mage").ap = 1
			main._refresh()
			var p := _card_pos("frost_rune")
			_move(p)
			_button(p, true)
			_button(p, false)
			check("행동력 부족 카드 거부(안내 문구)", "행동력" in main.hud.hint_label.text and main.target_card == "")
			b.hero("mage").ap = D.AP_MAX
			main._refresh()
			# ② 마력탄을 끌어 적에게 놓는다
			var e = b.enemies()[0]
			memo["e"] = e
			memo["hp"] = e.hp
			memo["ecell"] = e.cell
			var mb := _key("magic_bolt")
			var from := _card_pos("magic_bolt")
			var to := _unit_screen(e)
			_move(from)
			_button(from, true)
			for k in 6:
				_move(from.lerp(to, (k + 1) / 6.0))
			check("끌기 시작(카드가 손에 붙음)", main.hand.dragging == mb and main.target_card == mb)
			check("겨눈 칸 = 적 칸", main.hover_cell == e.cell)
			_button(to, false)
			check("놓으면 사용(손패에서 빠짐)", not mb in b.hand and mb in b.discard)
			memo["jolt_max"] = 0.0
			step = 2
		2:
			# 맞는 동안: 피격 넉백(jolt 오프셋)이 움직였다가 돌아온다
			var ev = memo.e
			if main.views.has(ev.id):
				memo.jolt_max = maxf(memo.jolt_max, main.views[ev.id].jolt.position.length())
			if _ready_turn():
				check("마력탄 피해 적용", memo.e.hp == memo.hp - 5 or memo.e.dead)
				check("피격 넉백(jolt 오프셋 0.2m 이상)", memo.jolt_max > 0.2)
				check("히트스탑 뒤 시간 배율 복구", is_equal_approx(Engine.time_scale, 3.0) and not main._hitstop_on)
				# ③ 눌러 고르고(조준 사격) 적을 누른다
				var aim := _key("aimed_shot")
				var p := _card_pos("aimed_shot")
				_move(p)
				_button(p, true)
				_button(p, false)
				check("눌러서 겨누기 시작", main.target_card == aim and main.hand.selected == aim)
				# 오른쪽 클릭 취소 → 다시 고르기
				_button(p, true, MOUSE_BUTTON_RIGHT)
				check("오른쪽 클릭 취소", main.target_card == "")
				_move(p)
				_button(p, true)
				_button(p, false)
				var e = b.enemies()[0]
				memo["e2"] = e
				memo["hp2"] = e.hp
				var q := _unit_screen(e)
				_move(q)
				_button(q, true)
				_button(q, false)
				check("적을 누르면 사용", not aim in b.hand)
				step = 3
		3:
			if _ready_turn():
				check("조준 사격 피해 적용", memo.e2.dead or memo.e2.hp < memo.hp2)
				# ④ 전사 베기를 집어 올리면 딤드 강조(주인 + 대상 적만)
				var w = b.hero("warrior")
				memo["w"] = w
				memo["home"] = main.views[w.id].global_position
				memo["turn"] = b.turn
				var far = b.enemies()[b.enemies().size() - 1]
				memo["far"] = far
				var sl := _key("slash")
				var from := _card_pos("slash")
				var to := _unit_screen(far)
				_move(from)
				_button(from, true)
				for k in 6:
					_move(from.lerp(to, (k + 1) / 6.0))
				var spot: Array = main.world._spot_nodes
				check("집어 올리면 딤드 강조 켜짐", main._spot_key == sl and main.world._spot_layer.visible)
				check("강조 = 전사 + 적 모두(+격자)", main.views[w.id] in spot and b.enemies().all(func(e): return main.views[e.id] in spot) and not main.views[b.hero("mage").id] in spot)
				check("다른 캐릭터 카드 어둡게", main.hand.focus == "warrior")
				_button(to, false)
				check("놓으면 강조 풀림", main._spot_key == "")
				memo["max_d"] = 0.0
				step = 4
		4:
			# 돌진 중: 전사가 자기 칸에서 멀리 내달렸다가 돌아온다
			var wv = main.views[memo.w.id]
			memo.max_d = maxf(memo.max_d, wv.global_position.distance_to(memo.home))
			if not main.busy and main.battle.phase != "enemy":
				check("근접 카드: 적에게 돌진(3m 이상)", memo.max_d > 3.0)
				check("돌진 후 제자리로 복귀", wv.global_position.distance_to(memo.home) < 0.3)
				check("행동력이 남아 있으면 턴이 끝나지 않음", b.turn == memo.turn and b.total_ap() > 0)
				# ⑤ 턴 종료 → 적 턴(적은 이동 없이 공격) → 다음 아군 턴
				main._on_end_turn()
				step = 5
		5:
			if _ready_turn() and b.turn == memo.turn + 1:
				check("적은 이동하지 않음", b.enemies().all(func(e): return e.id != memo.e.id or e.cell == memo.ecell))
				check("다음 아군 턴: 모두 행동력 3", b.allies().all(func(u): return u.ap == D.AP_MAX))
				check("손패 5장으로 다시 채움", main.hand.views.size() == b.hand.size() and b.hand.size() == 5)
				var fan: Array = main.hand._fan()
				var xs: Array = []
				for id in fan:
					xs.append(main.hand._fan_slot(fan.find(id), fan.size())[0].x)
				var even := true
				for k in range(1, xs.size()):
					if absf((xs[k] - xs[k - 1]) - main.hand.SPACING) > 0.5:
						even = false
				check("하나의 부채꼴(카드 간격이 모두 같음)", even)
				return _done()
	return false


func _done() -> bool:
	print("RESULT %d/%d" % [passed, total])
	Engine.time_scale = 1.0
	quit(0 if passed == total else 1)
	return true
