extends SceneTree
## 마우스 입력 경로 헤드리스 검증: 실제 InputEvent 를 main._unhandled_input 에 넣는다.
## 카드 끌어 놓기 · 눌러 고른 뒤 적 누르기 · 딤드 강조 · 근접 돌진 · 행동력 부족 카드 거부 · 오른쪽 클릭 취소 · 행동력 0 이면 자동 턴 넘김 · 한 부채꼴.
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


func _card_pos(id: String) -> Vector2:
	var v: Control = main.hand.views[id]
	return v.get_global_transform() * (v.size * Vector2(0.5, 0.35))


func _unit_screen(u) -> Vector2:
	return main.world.camera.unproject_position(main.world.cell_pos(main.room, u.cell))


func _ready_turn() -> bool:
	return main.mode == "battle" and not main.busy and main.battle.phase == "player"


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
	if wait > 0.0:
		return false
	var b = main.battle
	match step:
		0:
			if _ready_turn():
				wait = 1.2   # 카드가 손패 자리로 날아와 자리 잡을 때까지
				step = 1
		1:
			# ① 행동력 부족(서리 룬 2) 카드를 누르면 거부 + 안내
			var p := _card_pos("frost_rune")
			_move(p)
			_button(p, true)
			_button(p, false)
			check("행동력 부족 카드 거부(안내 문구)", "행동력" in main.hud.hint_label.text and main.target_card == "")
			# ② 마력탄을 끌어 적에게 놓는다
			var e = b.enemies()[0]
			memo["e"] = e
			memo["hp"] = e.hp
			var from := _card_pos("magic_bolt")
			var to := _unit_screen(e)
			_move(from)
			_button(from, true)
			for k in 6:
				_move(from.lerp(to, (k + 1) / 6.0))
			check("끌기 시작(카드가 손에 붙음)", main.hand.dragging == "magic_bolt" and main.target_card == "magic_bolt")
			check("겨눈 칸 = 적 칸", main.hover_cell == e.cell)
			_button(to, false)
			check("놓으면 사용(손패에서 빠짐)", not "magic_bolt" in b.hand and "magic_bolt" in b.discard)
			step = 2
		2:
			if _ready_turn():
				check("마력탄 피해 적용", memo.e.hp == memo.hp - 5 or memo.e.dead)
				# ③ 눌러 고르고(조준 사격) 적을 누른다
				var p := _card_pos("aimed_shot")
				_move(p)
				_button(p, true)
				_button(p, false)
				check("눌러서 겨누기 시작", main.target_card == "aimed_shot" and main.hand.selected == "aimed_shot")
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
				check("적을 누르면 사용", not "aimed_shot" in b.hand)
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
				var from := _card_pos("slash")
				var to := _unit_screen(far)
				_move(from)
				_button(from, true)
				for k in 6:
					_move(from.lerp(to, (k + 1) / 6.0))
				var spot: Array = main.world._spot_nodes
				check("집어 올리면 딤드 강조 켜짐", main._spot_key == "slash" and main.world._spot_layer.visible)
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
				step = 5
		5:
			# 셋 다 행동력 1을 썼으므로 자동으로 적 턴 → 다음 아군 턴
			if _ready_turn() and b.turn == memo.turn + 1:
				check("행동력 0 → 자동 적 턴 → 다음 아군 턴(행동력 2)", b.allies().all(func(u): return u.ap == 2))
				check("손패 9장으로 돌아옴", main.hand.views.size() == b.hand.size() and b.hand.size() == 9)
				var xs: Array = []
				for id in main.hand._fan():
					xs.append(main.hand._fan_slot(main.hand._fan().find(id), 9)[0].x)
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
