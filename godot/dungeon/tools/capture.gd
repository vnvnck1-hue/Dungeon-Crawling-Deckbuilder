extends SceneTree
## 실제 렌더 캡처(헤드리스 더미 렌더러로는 셰이더·안개·입자·카드 글자 굽기를 볼 수 없어서). 장면별 PNG 를 찍고 스스로 닫는다.
## 실행(godot 폴더 기준):  <Godot> --path . --script res://dungeon/tools/capture.gd
## 결과: screenshots/capture/*.png

const D := preload("res://dungeon/data/defs.gd")
const OUT := "res://screenshots/capture/"

var main
var t := 0.0
var step := 0
var wait := 0.0
var shots: Array = []
var memo := {}


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://dungeon/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.set_process_unhandled_input(false)   # 창 위의 실제 마우스가 겨눈 칸을 덮어쓰지 않게


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(OUT + name + ".png")
	shots.append(name)
	print("SHOT " + name)


func _ready_turn() -> bool:
	return main.mode == "battle" and main.battle.phase == "player" and not main.busy


func _key(id: String) -> String:
	for k in main.battle.hand:
		if D.base_id(k) == id:
			return k
	return ""


## 손패를 정해진 카드로 바꿔 넣는다(캡처용).
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


func _play_any() -> void:
	var b = main.battle
	for c in b.hand.duplicate():
		if b.playable(c) and not b.enemies().is_empty():
			var cell := Vector2i(-1, -1)
			for cc in b.target_cells(c):
				if not b.cells_hit(c, cc).is_empty():
					cell = cc
					break
			main._cast(c, cell)
			return
	if b.phase == "player":
		main._on_end_turn()


func _process(delta: float) -> bool:
	t += delta
	wait -= delta
	if wait > 0.0:
		return false
	if t > 240.0:
		quit(1)
		return true
	var b = main.battle
	if main.hud.choosing_card():
		if not memo.has("levelup_shot"):
			memo["levelup_shot"] = true
			wait = 0.8    # 선택지가 떠오르는 연출이 끝난 뒤 찍는다
			return false
		if not memo.has("levelup_taken"):
			memo["levelup_taken"] = true
			_shot("09_level_up")
		main.hud.pick_option(0)
		return false
	match step:
		0:
			wait = 2.0
			step = 1
		1:
			main.hud._select_root.queue_free()
			main.hud._select_root = null
			main._start(D.HERO_ORDER.duplicate())
			wait = 1.0
			step = 2
		2:
			_shot("01_run_in")
			step = 3
		3:
			if _ready_turn():
				_force_hand(["slash", "magic_bolt", "aimed_shot", "frost_rune", "war_cry"])
				wait = 1.6
				step = 4
		4:
			_shot("02_battle_fan")
			# 전사 베기를 집어 먼 적 위로 끌어 올린 상태(딤드 강조)
			var far = b.enemies()[b.enemies().size() - 1]
			memo["far"] = far.cell
			memo["slash"] = _key("slash")
			main.hand.start_drag(memo.slash)
			main.target_card = memo.slash
			main.hand.drag_pos = main.world.camera.unproject_position(main.world.cell_pos(main.room, far.cell)) + Vector2(0, -40)
			main.hand.over_board = true
			main.hover_cell = far.cell
			main._paint()
			wait = 0.7
			step = 5
		5:
			_shot("03_spotlight")
			main.hand.end_drag(false)
			main._cast(memo.slash, memo.far)
			wait = 0.2
			step = 6
		6:
			_shot("04_dash")
			wait = 0.25
			step = 7
		7:
			_shot("05_dash_hit")
			step = 8
		8:
			# 빨리 방 정리: 적 체력 1 → 카드 사용
			if _ready_turn():
				for e in b.enemies():
					e.hp = 1
				_play_any()
			if main.mode == "walk" and main.room == 1:
				wait = 1.3
				step = 9
		9:
			_shot("06_run_path")
			step = 10
		10:
			# 중간 보스 방(3)까지 빠르게
			if _ready_turn() and main.room < 3:
				for e in b.enemies():
					e.hp = 1
				_play_any()
			if main.room == 3 and main.mode == "battle":
				wait = 0.5
				step = 11
		11:
			_shot("07_boss_intro")
			step = 12
		12:
			if _ready_turn():
				wait = 1.5
				step = 13
		13:
			_shot("08_boss_room")
			print("DONE %d shots" % shots.size())
			quit(0)
			return true
	return false
