extends SceneTree
## 전투 규칙 헤드리스 검증. 실행(godot 폴더 기준):
##   <Godot> --headless --path . --script res://dungeon/tools/verify_battle.gd
## PASS/FAIL 줄과 마지막 RESULT n/m. 실패 시 종료 코드 1.

const Battle := preload("res://dungeon/core/battle.gd")
const D := preload("res://dungeon/data/defs.gd")

var passed := 0
var total := 0


func check(name: String, ok: bool) -> void:
	total += 1
	if ok:
		passed += 1
	print(("PASS " if ok else "FAIL ") + name)


func _init() -> void:
	var b := Battle.new()
	b.setup_party(D.HERO_ORDER)
	b.enter_room(0)
	check("방 입장: 아군 3 · 적 2", b.allies().size() == 3 and b.enemies().size() == 2)
	b.begin_player_turn()
	check("1턴 행동력 1", b.allies().all(func(u): return u.ap == 1))
	check("1턴 손패 9장", b.hand.size() == 9)
	check("1턴 주 스킬 불가(행동력 부족)", not b.affordable("frost_rune"))
	check("1턴 궁극기 불가", not b.affordable("war_cry"))
	check("1턴 기본 공격 가능", b.affordable("magic_bolt"))
	check("전사 베기: 멀리 있는 적에게도 돌진 가능", b.has_targets("slash") and b.target_cells("slash").size() == b.enemies().size())

	var gob = b.at(Vector2i(5, 1))
	var ev := b.play_card("magic_bolt", gob.cell)
	check("마력탄 피해 5", gob.hp == 12 - 5 and ev.size() >= 2)
	check("쓴 카드는 버림패로", "magic_bolt" in b.discard and not "magic_bolt" in b.hand)
	check("마법사 행동력 0", b.hero("mage").ap == 0)
	check("같은 카드 다시 못 냄", b.play_card("magic_bolt", gob.cell).is_empty())

	b.play_card("aimed_shot", gob.cell)
	check("조준 사격 피해 5", gob.hp == 2)

	var eev := b.end_player_turn()
	check("적 턴 사건 발생", eev.size() > 1)
	check("근접 적 전진(5열 → 4열)", b.enemies().any(func(e): return e.cell.x == 4))
	b.begin_player_turn()
	check("2턴 행동력 2", b.allies().all(func(u): return u.ap == 2))
	check("버림패가 손패로 돌아옴", b.hand.size() == 9 and b.discard.is_empty())
	check("2턴 주 스킬 가능", b.affordable("frost_rune"))
	check("2턴 궁극기 불가", not b.affordable("war_cry"))

	# 꿰뚫는 화살: 줄의 적 모두 + 표식
	var row_target: Vector2i = b.enemies()[0].cell
	var before: int = b.enemies()[0].hp
	b.play_card("piercing_arrow", row_target)
	var e0 = b.at(row_target)
	check("꿰뚫는 화살 표식/처치", e0 == null or e0.mark > 0)
	if e0 != null:
		check("꿰뚫는 화살 피해 6", e0.hp == before - 6)

	# 3턴까지 진행해 궁극기 확인
	b.end_player_turn()
	if b.phase == "enemy":
		b.begin_player_turn()
	check("3턴 행동력 3", b.phase != "player" or b.allies().all(func(u): return u.ap == 3))
	if b.phase == "player":
		var w = b.hero("warrior")
		b.play_card("war_cry")
		check("포효: 전원 방어 8", b.allies().all(func(u): return u.block >= 8))
		check("포효: 도발", w.taunt)
		check("포효 후 전사 행동력 0", w.ap == 0)

	# 서리 룬 빙결 → 적 턴 행동 불가
	var b2 := Battle.new()
	b2.setup_party(D.HERO_ORDER)
	b2.enter_room(1)
	b2.begin_player_turn()
	b2.end_player_turn()
	b2.begin_player_turn()
	var target = b2.enemies()[0]
	b2.play_card("frost_rune", target.cell)
	check("서리 룬 빙결", target.dead or target.frozen)
	var cell_before: Vector2i = target.cell
	var ev2 := b2.end_player_turn()
	var acted_frozen := ev2.any(func(x): return x.type == "enemy" and x.unit == target.id and x.action == "frozen")
	check("빙결된 적은 행동 안 함", target.dead or (acted_frozen and target.cell == cell_before))

	# 연쇄 번개: 4번 맞힘(적이 넉넉하면)
	var b3 := Battle.new()
	b3.setup_party(D.HERO_ORDER)
	b3.enter_room(6)
	for i in 3:
		b3.begin_player_turn()
		if i < 2:
			b3.end_player_turn()
	var ev3 := b3.play_card("chain_lightning", b3.enemies()[0].cell)
	var dmg := ev3.filter(func(x): return x.type == "damage")
	check("연쇄 번개 4번 튕김", dmg.size() == 4)

	# 방패 강타 밀쳐내기
	var b4 := Battle.new()
	b4.setup_party(D.HERO_ORDER)
	b4.enter_room(0)
	b4.begin_player_turn()
	b4.end_player_turn()
	b4.begin_player_turn()
	var w4 = b4.hero("warrior")
	var near: Array = b4.enemies()
	if not near.is_empty():
		var e4 = near[0]
		var c4: Vector2i = e4.cell
		b4.play_card("shield_bash", c4)
		check("방패 강타: 밀쳐냄 또는 충돌 피해", e4.dead or e4.cell != c4 or e4.hp <= 12 - 10)
		check("방패 강타: 전사 방어 6", w4.block == 6)
	else:
		check("방패 강타 대상 준비(근접 적)", false)

	# 방 정리 → room_clear
	var b5 := Battle.new()
	b5.setup_party(D.HERO_ORDER)
	b5.enter_room(0)
	b5.begin_player_turn()
	for e in b5.enemies():
		e.hp = 1
	b5.play_card("magic_bolt", b5.enemies()[0].cell)
	var last := b5.play_card("aimed_shot", b5.enemies()[0].cell)
	check("적 전멸 → room_clear", b5.phase == "clear" and last.any(func(x): return x.type == "room_clear"))
	b5.rest_between_rooms()
	b5.enter_room(1)
	check("다음 방 입장: 턴 0, 적 3", b5.turn == 0 and b5.enemies().size() == 3)
	check("4번째·8번째 방은 중간 보스", b5.room_is_boss(3) and b5.room_is_boss(7) and not b5.room_is_boss(2))
	b5.hero("mage").hp = 1
	b5.rest_between_rooms(true)
	check("보스 뒤 모닥불: 완전 회복", b5.allies().all(func(u): return u.hp == u.max_hp))
	b5.begin_player_turn()
	check("새 방 1턴 행동력 1로 다시 시작", b5.allies().all(func(u): return u.ap == 1))

	# 전체 자동 진행(무작위 플레이)으로 오류 없이 끝나는지
	var b6 := Battle.new()
	b6.setup_party(D.HERO_ORDER)
	var rooms_cleared := 0
	var guard := 0
	for r in D.ROOMS.size():
		b6.enter_room(r)
		while b6.phase != "clear" and b6.phase != "defeat" and guard < 400:
			guard += 1
			b6.begin_player_turn()
			for c in b6.hand.duplicate():
				if b6.phase != "player":
					break
				if b6.playable(c):
					var cells := b6.target_cells(c)
					var pick := Vector2i(-1, -1)
					for cc in cells:
						if not b6.cells_hit(c, cc).is_empty():
							pick = cc
							break
					b6.play_card(c, pick)
			if b6.phase == "player":
				b6.end_player_turn()
		if b6.phase == "defeat":
			break
		rooms_cleared += 1
		b6.rest_between_rooms()
	check("자동 진행 무한 루프 없음", guard < 400)
	print("자동 진행: 방 %d/%d 통과" % [rooms_cleared, D.ROOMS.size()])

	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)
