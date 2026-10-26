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


## 손패에서 카드 id 의 키를 찾는다(없으면 "").
func key_of(b, id: String) -> String:
	for k in b.hand:
		if D.base_id(k) == id:
			return k
	return ""


## 손패에 그 카드가 오도록 뽑을 패를 조작한다(검증용).
func force_hand(b, ids: Array) -> void:
	b.hand.clear()
	b.discard.clear()
	b.draw_pile.clear()
	var n := 1000
	for id in ids:
		b.hand.append("%s#%d" % [id, n])
		n += 1


func _init() -> void:
	var b := Battle.new()
	b.setup_party(D.HERO_ORDER)
	b.enter_room(0)
	check("방 입장: 아군 3 · 적 2", b.allies().size() == 3 and b.enemies().size() == 2)
	check("방 입장: 손패 5장, 뽑을 패 4장(덱 9장)", b.hand.size() == D.HAND_SIZE and b.draw_pile.size() == 9 - D.HAND_SIZE)
	b.begin_player_turn()
	check("1턴 행동력 3(모두)", b.allies().all(func(u): return u.ap == D.AP_MAX))
	check("손패 키는 카드id#번호", b.hand.all(func(k): return "#" in k and not D.card(k).is_empty()))
	force_hand(b, ["magic_bolt", "aimed_shot", "frost_rune", "war_cry", "slash"])
	check("1턴에도 궁극기 가능(행동력 3)", b.affordable(key_of(b, "war_cry")))
	check("전사 베기: 멀리 있는 적에게도 돌진 가능", b.has_targets(key_of(b, "slash")) and b.target_cells(key_of(b, "slash")).size() == b.enemies().size())

	var gob = b.at(Vector2i(5, 1))
	var mb := key_of(b, "magic_bolt")
	var ev := b.play_card(mb, gob.cell)
	check("마력탄 피해 5", gob.hp == 12 - 5 and ev.size() >= 2)
	check("cast 사건의 card 는 카드 id", ev[0].card == "magic_bolt")
	check("쓴 카드는 버림패로", mb in b.discard and not mb in b.hand)
	check("마법사 행동력 2", b.hero("mage").ap == 2)
	check("같은 카드 다시 못 냄", b.play_card(mb, gob.cell).is_empty())

	b.play_card(key_of(b, "aimed_shot"), gob.cell)
	check("조준 사격 피해 5", gob.hp == 2)
	# 처치 → 경험치(직접 처치는 보너스)
	var w = b.hero("warrior")
	var sl := key_of(b, "slash")
	var kev := b.play_card(sl, gob.cell)
	check("베기로 처치", gob.dead)
	var xps := kev.filter(func(x): return x.type == "xp")
	check("처치 시 살아 있는 아군 3명 모두 경험치", xps.size() == 3)
	check("직접 처치한 전사는 보너스 경험치", w.xp == 4 + D.XP_KILL_BONUS and b.hero("mage").xp == 4)

	var cells_before := {}
	for e in b.enemies():
		cells_before[e.id] = e.cell
	var eev := b.end_player_turn()
	check("적 턴 사건 발생", eev.size() > 1)
	check("적은 이동하지 않는다", b.enemies().all(func(e): return e.cell == cells_before[e.id]))
	check("근접 적이 멀리서도 바로 공격", eev.any(func(x): return x.type == "enemy" and x.action == "attack"))
	check("적 의도에 전진 없음", b.enemies().all(func(e): return b.intent(e).action != "move"))
	b.begin_player_turn()
	check("2턴 행동력 3", b.allies().all(func(u): return u.ap == D.AP_MAX))
	check("2턴 손패 5장으로 다시 채움", b.hand.size() == D.HAND_SIZE)

	# 꿰뚫는 화살: 줄의 적 모두 + 표식
	force_hand(b, ["piercing_arrow"])
	var row_target: Vector2i = b.enemies()[0].cell
	var before: int = b.enemies()[0].hp
	b.play_card(key_of(b, "piercing_arrow"), row_target)
	var e0 = b.at(row_target)
	check("꿰뚫는 화살 표식/처치", e0 == null or e0.mark > 0)
	if e0 != null:
		check("꿰뚫는 화살 피해 6", e0.hp == before - 6)

	# 포효(즉시 카드)
	force_hand(b, ["war_cry"])
	b.play_card(key_of(b, "war_cry"))
	check("포효: 전원 방어 8", b.allies().all(func(u): return u.block >= 8))
	check("포효: 도발", w.taunt)

	# 서리 룬 빙결 → 적 턴 행동 불가
	var b2 := Battle.new()
	b2.setup_party(D.HERO_ORDER)
	b2.enter_room(1)
	b2.begin_player_turn()
	force_hand(b2, ["frost_rune"])
	var target = b2.enemies()[0]
	b2.play_card(key_of(b2, "frost_rune"), target.cell)
	check("서리 룬 빙결", target.dead or target.frozen)
	var ev2 := b2.end_player_turn()
	var acted_frozen := ev2.any(func(x): return x.type == "enemy" and x.unit == target.id and x.action == "frozen")
	check("빙결된 적은 행동 안 함", target.dead or acted_frozen)

	# 연쇄 번개: 4번 맞힘(적이 넉넉하면)
	var b3 := Battle.new()
	b3.setup_party(D.HERO_ORDER)
	b3.enter_room(6)
	b3.begin_player_turn()
	force_hand(b3, ["chain_lightning"])
	var ev3 := b3.play_card(key_of(b3, "chain_lightning"), b3.enemies()[0].cell)
	var dmg := ev3.filter(func(x): return x.type == "damage")
	check("연쇄 번개 4번 튕김", dmg.size() == 4)

	# 방패 강타 밀쳐내기
	var b4 := Battle.new()
	b4.setup_party(D.HERO_ORDER)
	b4.enter_room(0)
	b4.begin_player_turn()
	force_hand(b4, ["shield_bash"])
	var w4 = b4.hero("warrior")
	var e4 = b4.enemies()[0]
	var c4: Vector2i = e4.cell
	b4.play_card(key_of(b4, "shield_bash"), c4)
	check("방패 강타: 밀쳐냄 또는 충돌 피해", e4.dead or e4.cell != c4 or e4.hp <= 12 - 10)
	check("방패 강타: 전사 방어 6", w4.block == 6)

	# 레벨업 카드: 새 효과(회복·두 번 침·빙결 줄·전원 방어)
	var b7 := Battle.new()
	b7.setup_party(D.HERO_ORDER)
	b7.enter_room(2)
	b7.begin_player_turn()
	force_hand(b7, ["second_wind", "double_shot", "arcane_shield", "trap_line", "fireball"])
	var w7 = b7.hero("warrior")
	w7.hp = 20
	var hev := b7.play_card(key_of(b7, "second_wind"))
	check("재기: 체력 9 회복 + 방어 3", w7.hp == 29 and w7.block == 3 and hev.any(func(x): return x.type == "heal"))
	var orc = b7.enemies().filter(func(e): return e.kind == "orc")[0]
	var dev := b7.play_card(key_of(b7, "double_shot"), orc.cell)
	check("연속 사격: 두 번 피해(4+4)", orc.hp == 24 - 8 and dev.filter(func(x): return x.type == "damage").size() == 2)
	b7.play_card(key_of(b7, "arcane_shield"))
	check("마력 보호막: 전원 방어 5", b7.allies().all(func(u): return u.block >= 5))
	b7.play_card(key_of(b7, "trap_line"), orc.cell)
	check("덫 줄: 줄의 적 빙결", orc.dead or orc.frozen)
	check("화염구(3×3): 대상 칸이 적 지역 전부", b7.target_cells(key_of(b7, "fireball")).size() == 16)
	# 레벨업 → 카드 고르기 → 덱에 추가
	var m7 = b7.hero("mage")
	var pend := b7.pending_levelups.size()
	m7.xp = m7.xp_next() - 1
	for e in b7.enemies():
		e.hp = 1
	force_hand(b7, ["magic_bolt"])
	var lev := b7.play_card(key_of(b7, "magic_bolt"), b7.enemies()[0].cell)
	check("경험치가 차면 레벨업 사건", lev.any(func(x): return x.type == "level_up" and x.unit == m7.id) and m7.level == 2)
	check("레벨업 대기 목록에 쌓임", b7.pending_levelups.size() == pend + 1 and m7.id in b7.pending_levelups)
	var opts := b7.level_options(m7)
	check("레벨업 선택지 3장(마법사 pool)", opts.size() == 3 and opts.all(func(c): return c in D.HEROES.mage.pool))
	var deck_n: int = m7.deck.size()
	var pile_n: int = b7.draw_pile.size()
	b7.add_card(m7, opts[0])
	check("고른 카드가 덱과 뽑을 패에 들어감", m7.deck.size() == deck_n + 1 and b7.draw_pile.size() == pile_n + 1)
	check("경험치 표: 1→2 12, 2→3 18", D.xp_to_next(1) == 12 and D.xp_to_next(2) == 18)

	# 같은 카드 둘이 덱에 있어도 손패 키가 다르다
	var b8 := Battle.new()
	b8.setup_party(D.HERO_ORDER)
	b8.hero("mage").deck.append("magic_bolt")
	b8.enter_room(0)
	var keys := {}
	for k in b8.hand + b8.draw_pile:
		keys[k] = true
	check("덱의 같은 카드도 키가 서로 다름", keys.size() == 10)
	# 버림패가 비고 뽑을 패도 비면 손패는 덱 크기만큼만
	b8.begin_player_turn()
	for k in b8.hand.duplicate():
		b8.hand.erase(k)
		b8.discard.append(k)
	b8.draw_to_hand()
	check("뽑을 패가 비면 버림패를 섞어 다시 뽑음", b8.hand.size() == D.HAND_SIZE)
	# 쓰러진 동료의 카드는 뽑지 않는다
	b8.hero("mage").dead = true
	b8.hand.clear()
	b8.draw_pile = b8.draw_pile + b8.discard
	b8.discard.clear()
	b8.draw_to_hand()
	check("쓰러진 동료의 카드는 손패에 오지 않음", b8.hand.all(func(k): return D.card(k).hero != "mage"))

	# 방 정리 → room_clear
	var b5 := Battle.new()
	b5.setup_party(D.HERO_ORDER)
	b5.enter_room(0)
	b5.begin_player_turn()
	for e in b5.enemies():
		e.hp = 1
	force_hand(b5, ["magic_bolt", "aimed_shot"])
	b5.play_card(key_of(b5, "magic_bolt"), b5.enemies()[0].cell)
	var last := b5.play_card(key_of(b5, "aimed_shot"), b5.enemies()[0].cell)
	check("적 전멸 → room_clear", b5.phase == "clear" and last.any(func(x): return x.type == "room_clear"))
	b5.rest_between_rooms()
	b5.enter_room(1)
	check("다음 방 입장: 턴 0, 적 3, 손패 5", b5.turn == 0 and b5.enemies().size() == 3 and b5.hand.size() == D.HAND_SIZE)
	check("4번째·8번째 방은 중간 보스", b5.room_is_boss(3) and b5.room_is_boss(7) and not b5.room_is_boss(2))
	b5.hero("mage").hp = 1
	b5.rest_between_rooms(true)
	check("보스 뒤 모닥불: 완전 회복", b5.allies().all(func(u): return u.hp == u.max_hp))

	# 전체 자동 진행(무작위 플레이)으로 오류 없이 끝나는지. 레벨업 때는 첫 선택지를 고른다.
	var b6 := Battle.new()
	b6.setup_party(D.HERO_ORDER)
	var rooms_cleared := 0
	var guard := 0
	var levelups := 0
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
				while not b6.pending_levelups.is_empty():
					var u = b6.unit(b6.pending_levelups.pop_front())
					b6.add_card(u, b6.level_options(u)[0])
					levelups += 1
			if b6.phase == "player":
				b6.end_player_turn()
		if b6.phase == "defeat":
			break
		rooms_cleared += 1
		b6.rest_between_rooms()
	check("자동 진행 무한 루프 없음", guard < 400)
	check("자동 진행 중 레벨업 발생", levelups >= 3)
	print("자동 진행: 방 %d/%d 통과 · 레벨업 %d회 · 덱 크기 %s" % [rooms_cleared, D.ROOMS.size(), levelups,
		str(b6.allies(true).map(func(u): return u.deck.size()))])

	print("RESULT %d/%d" % [passed, total])
	quit(0 if passed == total else 1)
