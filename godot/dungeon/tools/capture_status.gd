extends SceneTree
## 상태이상·시너지 렌더 캡처(표식 중첩·화상·냉기·빙결·투지가 한눈에 읽히는지, 파쇄·증기 폭발 순간). 장면별 PNG 를 찍고 스스로 닫는다.
## 실행(godot 폴더 기준):  <Godot> --path . --script res://dungeon/tools/capture_status.gd
## 결과: screenshots/capture/status_*.png

const D := preload("res://dungeon/data/defs.gd")
const OUT := "res://screenshots/capture/"

var main
var t := 0.0
var step := 0
var wait := 0.0
var queue: Array = []        # [카드 id, 대상 적 순번(-1 = 즉시 카드), 찍을 이름(""), 찍기까지 초]
var pending_shot := ""
var keep_level := false     # 레벨업 화면을 찍는 동안 자동으로 고르지 않는다


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://dungeon/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.set_process_unhandled_input(false)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(OUT + "status_" + name + ".png")
	print("SHOT status_" + name)


func _ready_turn() -> bool:
	return main.mode == "battle" and main.battle.phase == "player" and not main.busy and not main.hud.choosing_card()


## 카드 하나를 손패에 넣어 바로 쓴다(행동력은 넉넉히).
func _cast(id: String, enemy_index: int) -> void:
	var b = main.battle
	for u in b.allies():
		u.ap = 9
	var key := "%s#%d" % [id, 5000 + int(t * 100)]
	b.hand.append(key)
	main.hand.deal(b.hand)
	main._refresh()
	var cell := Vector2i(-1, -1)
	if enemy_index >= 0:
		cell = b.enemies()[mini(enemy_index, b.enemies().size() - 1)].cell
	main._cast(key, cell)


func _process(delta: float) -> bool:
	t += delta
	wait -= delta
	if wait > 0.0:
		return false
	if t > 300.0:
		quit(1)
		return true
	if main.hud.choosing_card() and not keep_level:
		main.hud.pick_option(0)
		return false
	var b = main.battle
	if pending_shot != "":
		_shot(pending_shot)
		pending_shot = ""
	match step:
		0:
			wait = 1.5
			step = 1
		1:
			main.hud._select_root.queue_free()
			main.hud._select_root = null
			main._start(D.HERO_ORDER.duplicate())
			step = 2
		2:
			# 첫 방은 빨리 정리하고 적 셋인 둘째 방으로
			if _ready_turn() and main.room == 0:
				for e in b.enemies():
					e.hp = 1
				_cast("magic_bolt", 0)
			if main.room == 1 and _ready_turn():
				for e in b.enemies():
					e.hp = 60
					e.max_hp = 60
				queue = [
					["hunters_mark", 0, "", 0.0], ["hunters_mark", 0, "", 0.0], ["expose", 0, "mark_stack", 0.9],
					["ember", 0, "", 0.0], ["fireball", 0, "burn", 1.2],
					["ice_shard", 1, "chill", 1.0],
					["ice_shard", 2, "", 0.0], ["ice_shard", 2, "freeze", 1.0],
					["blood_oath", -1, "fury", 1.0],
					["war_cry", -1, "", 0.0],
				]
				step = 3
		3:
			if not _ready_turn():
				return false
			if queue.is_empty():
				wait = 1.5
				step = 4
				return false
			var a: Array = queue.pop_front()
			_cast(String(a[0]), int(a[1]))
			if String(a[2]) != "":
				pending_shot = String(a[2])
				wait = float(a[3])
		4:
			_shot("all")
			# 파쇄: 빙결된 투척꾼을 어깨 돌진으로 벽에
			_cast("shoulder_charge", 2)
			pending_shot = "shatter"
			wait = 0.75
			step = 5
		5:
			if _ready_turn():
				# 증기 폭발: 냉기 2 인 고블린에 불씨
				_cast("ember", 1)
				pending_shot = "steam"
				wait = 0.9
				step = 6
		6:
			if _ready_turn():
				wait = 1.0
				step = 7
		7:
			_shot("after")
			# 연계: 직전 카드가 마법사(불씨) → 철벽·전고(연계 마법사)가 손패에서 맥동
			b.hand.clear()
			for id in ["iron_wall", "war_drum", "shoulder_charge", "expose", "arrow_storm", "shatter_strike", "meditate"]:
				b.hand.append("%s#%d" % [id, 7000 + b.hand.size()])
			main.hand.clear_all()
			for u in b.allies():
				u.ap = 3
			main.hand.deal(b.hand)
			main._refresh()
			wait = 1.0
			step = 8
		8:
			_shot("combo")
			# 레벨업 화면(새 카드 셋 + 강화)
			var w = b.hero("warrior")
			w.picks = 1
			keep_level = true
			main.hud.show_level_up("warrior", 3, b.level_options(w), main.hand.face, b.upgrade_option(w))
			wait = 1.2
			step = 9
		9:
			_shot("level_up")
			# 고른 카드가 덱 더미로 날아가는 연출(main._offer_level_up 과 같은 경로)
			main.hud._level_root.queue_free()
			main.hud._level_root = null
			var w = b.hero("warrior")
			main._offer_level_up(w)
			wait = 1.2
			step = 10
		10:
			main.hud.pick_option(1)
			wait = 0.15
			step = 11
		11:
			_shot("pick_glow")
			wait = 0.45
			step = 12
		12:
			_shot("pick_fly")
			wait = 0.6
			step = 13
		13:
			_shot("pick_land")
			print("DONE")
			quit(0)
			return true
	return false
