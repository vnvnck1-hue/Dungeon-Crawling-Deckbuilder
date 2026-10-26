extends SceneTree
## 실제 메인 장면 흐름 헤드리스 검증: 자동 출발 → 숲길 행군 → 방 전투(카드 사용·적 턴) → 적 전멸 → 좁은 길 자동 이동 → … → 승리.
## 실행(godot 폴더 기준):  <Godot> --headless --path . --script res://dungeon/tools/verify_flow.gd
## 빨리 돌리려고 시간 배율 4. 첫 방의 첫 적 턴을 본 뒤에는 적 체력을 1로 낮춰 진행만 확인한다.

const D := preload("res://dungeon/data/defs.gd")

var main
var passed := 0
var total := 0
var t := 0.0
var seen_battle := {}
var seen_enemy_turn := false
var seen_walk_between := false
var cards_played := 0
var acting := false
var last_room := -1
var arrived_ok := true
var walk_start := -1.0
var travel: Array = []      # 방 정리 → 다음 방 첫 아군 턴까지(게임 시간 초)
var boss_big := {}
var levelups := 0
var deck_grew := false
var zoom_battle := false
var zoom_walk := false
var hand_ok := true
var ap_ok := true
var enemy_moved := false
var enemy_cells := {}
var seen_turns := {}


func check(name: String, ok: bool) -> void:
	total += 1
	if ok:
		passed += 1
	print(("PASS " if ok else "FAIL ") + name)


func _initialize() -> void:
	Engine.time_scale = 4.0
	main = load("res://dungeon/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main


var started := false


func _process(delta: float) -> bool:
	t += delta
	if not started:
		started = true
		main._start(D.HERO_ORDER.duplicate())
		check("출발: 아군 3 생성", main.views.size() >= 3 and main.mode == "walk")
		return false
	if t > 400.0:
		check("제한 시간 안에 끝남", false)
		return _done()
	if main.mode == "result":
		check("모든 방 통과 후 승리 화면", main.room == D.ROOMS.size() - 1 and main.battle.phase == "clear")
		check("방 %d개 전투 진입" % D.ROOMS.size(), seen_battle.size() == D.ROOMS.size())
		check("적 턴 연출 진행", seen_enemy_turn)
		check("방 사이 자동 이동(walk)", seen_walk_between)
		check("카드 사용 %d회 이상" % D.ROOMS.size(), cards_played >= D.ROOMS.size())
		check("방 입장 때 아군이 자기 칸에 섬", arrived_ok)
		# travel[k] = 방 k → k+1. 보스 방(3·7) 진입은 등장 연출 1.2초가 더 붙는다
		var ok := travel.size() == D.ROOMS.size() - 1
		for k in travel.size():
			var limit := 6.0 if D.ROOMS[k + 1].get("boss", false) else 4.8
			ok = ok and travel[k] <= limit
		print("방 사이 이동 시간(정리 연출 포함): ", travel)
		check("방 사이 이동이 빠름(일반 4.8초·보스 등장 6초 이하, 이전 약 16초)", ok)
		check("3무리마다 중간 보스(방 4·8, 덩치 1.4배 이상)", boss_big.has(3) and boss_big.has(7) and boss_big[3] >= 1.4 and boss_big[7] >= 1.4)
		check("레벨업 카드 고르기 화면이 뜨고 고르면 덱이 1장 늘어남(%d회)" % levelups, levelups >= 3 and deck_grew)
		check("손패는 턴 시작마다 5장(또는 남은 덱만큼)", hand_ok)
		check("매 턴 모든 캐릭터 행동력 3", ap_ok)
		check("적은 방 안에서 이동하지 않음", not enemy_moved)
		check("전투 중 카메라 줌 당김 · 행군 때 되돌림", zoom_battle and zoom_walk)
		check("히트스탑 뒤 시간 배율 복구", is_equal_approx(Engine.time_scale, 4.0) and not main._hitstop_on)
		return _done()
	if main.mode == "walk" and last_room >= 0 and walk_start < 0.0:
		walk_start = t
	if main.mode == "walk" and last_room >= 0 and main.room > last_room:
		seen_walk_between = true
		zoom_walk = zoom_walk or is_equal_approx(main.world._cam_height_target, main.world.CAM_HEIGHT)
	if main.mode == "battle":
		zoom_battle = zoom_battle or is_equal_approx(main.world._cam_height_target, main.world.CAM_HEIGHT_BATTLE)
	# 레벨업 카드 고르기: 첫 선택지를 고른다
	if main.hud.choosing_card():
		var b0 = main.battle
		var before: int = b0.allies(true).reduce(func(acc, u): return acc + u.deck.size(), 0)
		main.hud.pick_option(0)
		levelups += 1
		deck_grew = deck_grew or b0.allies(true).reduce(func(acc, u): return acc + u.deck.size(), 0) == before + 1
		return false
	if main.mode != "battle" or main.busy or acting or main.battle.phase != "player":
		return false
	var b = main.battle
	if not seen_battle.has(main.room):
		seen_battle[main.room] = true
		if walk_start >= 0.0:
			travel.append(t - walk_start)
			walk_start = -1.0
		if b.room_is_boss():
			for e in b.enemies():
				if e.def().get("boss", false):
					boss_big[main.room] = main.views[e.id].visual.scale.x
		last_room = main.room
		for u in b.allies():
			var v = main.views[u.id]
			if v.global_position.distance_to(main.world.cell_pos(main.room, u.cell)) > 0.3:
				arrived_ok = false
		print("방 %d 전투 시작(적 %d)" % [main.room, b.enemies().size()])
	if b.turn >= 2 and not seen_enemy_turn:
		seen_enemy_turn = true
	if seen_enemy_turn:
		for e in b.enemies():
			e.hp = 1
	# 턴 시작 상태 점검(이번 턴 처음 볼 때): 손패 5장·행동력 3·적 자리
	var turn_key := "%d-%d" % [main.room, b.turn]
	if not seen_turns.has(turn_key):
		seen_turns[turn_key] = true
		var deck_n: int = b.allies().reduce(func(acc, u): return acc + u.deck.size(), 0)
		if b.hand.size() != mini(D.HAND_SIZE, deck_n) or main.hand.views.size() != b.hand.size():
			hand_ok = false
			print("손패 불일치: 방 %d 턴 %d 손패 %d 화면 %d" % [main.room, b.turn, b.hand.size(), main.hand.views.size()])
		if not b.allies().all(func(u): return u.ap == D.AP_MAX):
			ap_ok = false
		# 적 턴 동안 자리가 바뀌지 않았는지(아군 카드의 밀쳐내기는 제외) + 의도에 전진이 없는지
		for e in b.enemies():
			if enemy_cells.has(e.id) and enemy_cells[e.id] != e.cell:
				enemy_moved = true
			if String(b.intent(e).get("action", "")) == "move":
				enemy_moved = true
		enemy_cells.clear()
	_act()
	return false


func _act() -> void:
	acting = true
	var b = main.battle
	for c in b.hand.duplicate():
		if not b.playable(c):
			continue
		var cell := Vector2i(-1, -1)
		if String(D.card(c).target) != "none":
			for cc in b.target_cells(c):
				if not b.cells_hit(c, cc).is_empty():
					cell = cc
					break
		cards_played += 1
		main._cast(c, cell)
		break
	# 낼 카드가 없으면 턴 종료(행동력이 0이면 main 이 알아서 넘긴다). 적 턴 전 자리를 기억해 둔다
	if not main.busy and b.phase == "player" and b.total_ap() > 0:
		for e in b.enemies():
			enemy_cells[e.id] = e.cell
		main._on_end_turn()
	acting = false


func _done() -> bool:
	print("RESULT %d/%d" % [passed, total])
	Engine.time_scale = 1.0
	quit(0 if passed == total else 1)
	return true
