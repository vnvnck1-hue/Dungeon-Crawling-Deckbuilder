extends Node
## CardInventory: 소유 카드·수량·손패/주머니의 단일 기록(기획 region-season-pocket-design.md §6).
## 주머니(pocket)가 곧 덱이다. 플레이어가 원하는 카드를 마음대로 넣거나 꺼낼 수 없고,
## 아침 드로우·카드 효과 드로우로만 손패에 들어온다.
## 같은 재화는 한 구역 안에서 한 장에 수량으로 묶는다(stackable). 2026-10-18 한때 1장=1개로 바꿨다가 같은 날 묶음으로 되돌렸다.
## 생산·소비 수치는 그때 줄인 값(docs/resource-single-card-balance-v01.md)을 그대로 쓴다.
## 재화(kind resource, 묶음)는 원재료뿐이다: 양털·검은 털·목재·생고기·토끼 가죽·쇠붙이(사용자 확정 2026-10-20) + 광석(카드 검토 승인 2026-10-25).
## 술·요리·꾸러미 같은 소모품(kind consumable)은 묶지 않는 낱장 카드이고, 쓰면 다른 카드처럼 버림패로 간다.
## 새 카드는 손패에 먼저 들어가고, 손패(8장)가 가득 차면 주머니로 간다(확정 규칙 1·3).
## 자원 외의 사용 카드는 버림패(discard)로 가고 자동으로 재순환하지 않는다(확정 규칙 5·6).
## 용병·입식·설치물처럼 활동이 이어지는 카드는 in_play에 머물다 활동이 끝나면 버림패로 간다.
## entries 에는 손패·주머니 카드만 있다(활동 중·버림패는 별도 목록).
## 손패 흐름 v1(2026-10-18, docs/hand-draw-flow-design-v01.md §7): 낮 손패에는 낮 카드만, 밤 손패에는 밤 카드만(Cfg.CARD_PHASE).
## 들어오는 카드가 지금 시간대에 못 쓰는 카드면 주머니로. 낮↔밤 전환 때 반대 시간대 카드는 주머니로 가고 손패가 찰 때까지 새 시간대 카드를 무작위로 뽑는다(phase_swap).
## 모든 드로우는 지금 시간대에 쓸 수 있는 주머니 카드에서만 뽑는다. 카드를 DRAW_STACK_SIZE장 쓰면 스택 드로우 1장, 켜진 모닥불에 태우면 1장(burn).
## 스택 악용 방지(docs/draw-stack-exploit-review-v01.md, 사용자 확정 2026-10-20 A+B'+C):
##  A. 활동 중이던 카드가 같은 uid로 손패에 돌아오면(장비 벗기기) 다시 써도 세지 않는다.
##  B'. 재화 사용은 재화 종류마다 하루(새벽~새벽) 첫 사용만 센다. 나눠 팔기·장작 하나씩 넣기로 스택을 채울 수 없다.
##  C. 한 번의 사용 확정에 여러 장을 소비해도 begin_use()/end_use()로 묶어 1회만 센다.

const Cfg := preload("res://scripts/config.gd")
const Catalog := preload("res://scripts/ui/card_catalog.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const MercKit := preload("res://scripts/game/merc_kit.gd")

signal changed
signal drawn(uids: Array)   # 주머니에서 손패로 들어온 카드(연출용)
signal stack_changed(count: int)  # 스택 드로우 게이지(0~DRAW_STACK_SIZE)가 바뀜(HUD 연출용)
signal phase_swapped(out_uids: Array, in_uids: Array)  # 낮↔밤 전환: 주머니로 간 손패 uid 순서, 새로 뽑힌 uid 순서(changed 직전, 순차 연출용)
signal card_used(id: String)  # 카드 사용(스택에 세는 소비·활동 시작). 태우기·재료 소비는 내지 않는다(폭주하는 마법서의 주문 세기)

var game
var entries: Array = []      # {uid, id, count, zone("hand"|"pocket"), person}
var in_play: Array = []      # 활동 중인 카드 {uid, id, person}
var discard: Array = []      # 버림패 {uid, id, person}
var defs: Dictionary = {}    # id -> catalog entry
var stats := {"hired": 0, "timber": 0, "wool": 0, "wool_sold": 0, "monster": 0, "used": 0, "raw_meat": 0, "rabbit_pelt": 0, "chests": 0, "relics": 0,
	"drawn": 0, "morning_draws": 0, "skipped_draws": 0, "discarded": 0, "stack_draws": 0, "burns": 0, "swapped_out": 0, "swapped_in": 0}
var last_drawn: Array = []   # 마지막 드로우로 손패에 들어온 uid 목록(손패 UI가 읽고 비운다)
var draw_stack := 0          # 카드 사용 누적(스택). DRAW_STACK_SIZE가 되면 1장 뽑고 0으로
var burns_today := 0         # 오늘 모닥불에 태운 횟수(새벽에 0)
var _count_uses := true      # 태우기·교환 재료처럼 스택에 세지 않을 소비 동안 끈다
var resource_uses_today := {} # B': 오늘 이미 스택에 센 재화 id(새벽에 비움)
var _returned_uids := {}      # A: 활동 중에서 손패로 돌아온 uid. 다음 activate는 세지 않는다
var _use_depth := 0           # C: begin_use() 중첩 깊이
var _use_ids: Array = []      # C: 묶인 사용 동안 소비된 카드 id
var _next_uid := 1


func _ready() -> void:
	name = "CardInventory"
	for entry in Catalog.read().get("cards", []):
		defs[entry["id"]] = entry
	# 가득 찬 스택이 기다리는 중이면 손패·주머니가 바뀐 직후(자리가 나거나 뽑을 카드가 생기면) 뽑는다
	changed.connect(func(): if draw_stack >= Cfg.DRAW_STACK_SIZE: call_deferred("try_stack_draw"))


## 가득 찬 스택이 손패 자리·뽑을 카드를 기다리는 중이면 자리가 나는 순간 뽑는다.
func _process(_delta: float) -> void:
	if draw_stack >= Cfg.DRAW_STACK_SIZE:
		try_stack_draw()


func def(id: String) -> Dictionary:
	return defs.get(id, {})


func stackable(id: String) -> bool:
	return bool(def(id).get("stackable", false))


## 재화 카드(kind == "resource")인지. 재화는 사용하면 버림패로 가지 않고 소멸한다(확정 규칙 5).
func is_resource(id: String) -> bool:
	return str(def(id).get("kind", "")) == "resource"


func hand() -> Array:
	return entries.filter(func(e): return e["zone"] == "hand")


func pocket() -> Array:
	return entries.filter(func(e): return e["zone"] == "pocket")


## pocket().size() 를 배열을 만들지 않고 센다(매 프레임 갱신하는 HUD 용).
func pocket_size() -> int:
	var n := 0
	for e in entries:
		if e["zone"] == "pocket":
			n += 1
	return n


## (구 이름 호환) 창고 = 주머니.
func storage() -> Array:
	return pocket()


func hand_full() -> bool:
	var n := 0   # 손패가 꽉 찬 동안 매 프레임 불리므로 hand() 배열을 만들지 않고 센다
	for e in entries:
		if e["zone"] == "hand":
			n += 1
	return n >= Cfg.HAND_VISIBLE


# ───────────────────────── 시간대(낮·밤 손패) ─────────────────────────

## 카드의 시간대: "day" | "night" | "both" | "none"(침식). 표에 없는 카드는 양쪽.
func phase_of(id: String) -> String:
	return str(Cfg.CARD_PHASE.get(id, "both"))


## 지금 손패의 시간대. 준비 시간은 낮, 밤 전투·정리는 밤. 세션이 없으면(검증 초기) 낮.
func current_phase() -> String:
	if game == null or game.get("session") == null or game.session == null:
		return "day"
	return "day" if game.session.state == SessionScript.State.PREP else "night"


## 이 카드가 그 시간대 손패에 있을 수 있는가(양쪽 카드 포함). 침식 카드는 어느 쪽도 아니다.
func fits_phase(id: String, phase: String) -> bool:
	var p := phase_of(id)
	return p == "both" or p == phase


## 지금 시간대에 쓸 수 있는 카드인가(손패 진입·드로우 후보 기준).
func usable_now(id: String) -> bool:
	return fits_phase(id, current_phase())


## 지금 시간대에 뽑을 수 있는 주머니 카드(양쪽 카드 포함). 모든 드로우는 여기서만 뽑는다.
func eligible_pocket(phase := "") -> Array:
	var ph := phase if phase != "" else current_phase()
	return pocket().filter(func(e): return fits_phase(e["id"], ph))


func eligible_pocket_empty() -> bool:
	var ph := current_phase()   # eligible_pocket().is_empty() 와 같은 조건, 하나 찾으면 바로 끝
	for e in entries:
		if e["zone"] == "pocket" and fits_phase(e["id"], ph):
			return false
	return true


## 주머니 안의 카드 수(묶음 자원은 수량만큼).
func pocket_units() -> int:
	var n := 0
	for e in pocket():
		n += int(e["count"])
	return n


func get_entry(uid: int) -> Dictionary:
	for e in entries:
		if e["uid"] == uid:
			return e
	return {}


## 손패에 뽑힌 수량(확정 규칙 9: 모든 자원 사용은 손패의 자원만 가능).
func hand_count_of(id: String) -> int:
	var n := 0
	for e in entries:
		if e["id"] == id and e["zone"] == "hand":
			n += int(e["count"])
	return n


## 주머니 안의 수량(아직 뽑지 않아 쓸 수 없는 자원).
func pocket_count_of(id: String) -> int:
	return count_of(id) - hand_count_of(id)


## 손패+주머니의 보유 수량. 활동 중·버림패는 세지 않는다.
func count_of(id: String) -> int:
	var n := 0
	for e in entries:
		if e["id"] == id:
			n += int(e["count"])
	return n


func _find_stack(id: String, zone: String) -> Dictionary:
	for e in entries:
		if e["id"] == id and e["zone"] == zone:
			return e
	return {}


func _new_entry(id: String, amount: int, zone: String, person: String) -> Dictionary:
	var e := {"uid": _next_uid, "id": id, "count": amount, "zone": zone, "person": person}
	var arts := pick_art(id)
	if arts >= 0:
		e["art"] = arts
	_next_uid += 1
	entries.append(e)
	return e


## 일러스트 변형이 있는 카드(술주정)의 그림 번호: 지금 손패·주머니에 있는 같은 카드와 겹치지 않는 번호를 무작위로.
## 모든 번호가 이미 쓰이고 있으면 아무 번호나. 변형이 없는 카드는 -1.
func pick_art(id: String) -> int:
	var n: int = def(id).get("art_variants", []).size()
	if n <= 0:
		return -1
	var used := {}
	for e in entries:
		if e["id"] == id and e.has("art"):
			used[int(e["art"])] = true
	var free: Array = []
	for i in n:
		if not used.has(i):
			free.append(i)
	if free.is_empty():
		return randi() % n
	return int(free[randi() % free.size()])


## 획득. 손패에 먼저 넣고, 손패가 가득 차면 주머니로 보낸다. 같은 자원은 그 구역의 기존 카드에 수량을 더한다.
## zone 을 "pocket" 으로 주면 손패를 거치지 않고 주머니에 넣는다(시작 카드). 반환: 넣은 구역.
func add(id: String, amount := 1, person := "", zone := "") -> String:
	if not defs.has(id) or amount <= 0:
		return ""
	match id:
		"lumberjack", "hunter", "warrior", "gatherer": stats["hired"] += 1
		"timber": stats["timber"] += amount
		"wool": stats["wool"] += amount
		"raw_meat": stats["raw_meat"] += amount
		"rabbit_pelt": stats["rabbit_pelt"] += amount
		"treasure_chest": stats["chests"] += 1
		"forest_monster": stats["monster"] += 1
	# 낱장 카드를 여러 장 받으면(채집가가 독버섯 2개를 건넴) 한 장씩 따로 넣는다
	if not stackable(id) and amount > 1:
		var last := ""
		for i in amount:
			last = add(id, 1, person, zone)
		return last
	var target := zone
	var why_pocket := ""
	if target == "":
		# 침식 카드는 시간대와 무관하게 손패를 막는다(기존 규칙). 그 밖의 카드는 지금 시간대에 쓸 수 있어야 손패로 온다.
		if phase_of(id) != "none" and not usable_now(id):
			target = "pocket"
			why_pocket = "%s 카드라" % ("낮" if phase_of(id) == "day" else "밤")
		elif stackable(id) and not _find_stack(id, "hand").is_empty():
			target = "hand"
		else:
			target = "hand" if not hand_full() else "pocket"
			if target == "pocket":
				why_pocket = "손패가 가득 차"
	if stackable(id):
		var stack := _find_stack(id, target)
		if not stack.is_empty():
			stack["count"] += amount
			changed.emit()
			return target
	_new_entry(id, amount, target, person)
	if target == "pocket" and zone == "" and game != null:
		game.toast("%s '%s' 카드를 주머니에 넣었습니다" % [why_pocket, def(id).get("name", id)], Color(0.95, 0.85, 1.0))
	changed.emit()
	return target


## 사용 확정 시에만 호출한다. 재화는 소멸하고, 그 밖의 카드는 버림패로 보낸다. 수량이 부족하면 아무것도 바꾸지 않는다.
## count=false 면 스택에 세지 않는다(요정 교환의 재료처럼 다른 카드 사용의 일부일 때).
func consume(uid: int, amount := 1, count := true) -> bool:
	for i in entries.size():
		var e: Dictionary = entries[i]
		if e["uid"] != uid:
			continue
		if int(e["count"]) < amount:
			return false
		e["count"] -= amount
		if e["count"] <= 0:
			entries.remove_at(i)
			if not is_resource(e["id"]):
				_to_discard(e)
		stats["used"] += 1
		if count:
			_note_use(e["id"])
			if _count_uses:
				card_used.emit(e["id"])
		changed.emit()
		return true
	return false


## 재화를 종류로 N장 소비한다(목재 3장 등). **손패에 뽑힌 재화만** 쓴다(확정 규칙 9). 부족하면 아무것도 바꾸지 않는다.
## 여러 묶음에 걸쳐 빠져도 스택 드로우에는 한 번의 사용으로 센다.
func consume_id(id: String, amount: int) -> bool:
	if amount <= 0:
		return true
	if hand_count_of(id) < amount:
		return false
	var left := amount
	begin_use()
	for e in hand():
		if left <= 0:
			break
		if e["id"] != id:
			continue
		var take := mini(left, int(e["count"]))
		if not consume(e["uid"], take):
			end_use()
			return false
		left -= take
	end_use()
	return true


## 정화: 손패·주머니의 카드를 버림패를 거치지 않고 없앤다(침식 카드 제거). 반환: 없앤 카드 id(없으면 빈 문자열).
func remove_uid(uid: int) -> String:
	for i in entries.size():
		if entries[i]["uid"] == uid:
			var id: String = entries[i]["id"]
			entries.remove_at(i)
			changed.emit()
			if id == "black_rumor" and game != null and game.get("reputation") != null:
				game.reputation.on_rumor_purified()  # 검은 소문을 정화하면 소문이 조금 밝아진다
			return id
	return ""


## 침식 카드인지.
func is_corruption(id: String) -> bool:
	return id in Cfg.CORRUPTION_CARDS


## 활동 카드(용병·하수인·입식·설치물)를 사용: 손패에서 빠져 활동 중 목록으로 간다. 활동이 끝나면 retire()로 버림패에 보낸다.
func activate(uid: int) -> bool:
	for i in entries.size():
		var e: Dictionary = entries[i]
		if e["uid"] != uid:
			continue
		entries.remove_at(i)
		in_play.append({"uid": e["uid"], "id": e["id"], "person": e["person"]})
		stats["used"] += 1
		if _returned_uids.has(uid):
			_returned_uids.erase(uid)  # A: 벗겼다 다시 끼운 장비는 이미 센 카드다
		else:
			_note_use(e["id"])
			card_used.emit(e["id"])
		changed.emit()
		return true
	return false


## 활동 종료(사망·파괴·소멸·자발적 종료): 활동 중 카드를 버림패로 보낸다.
func retire(uid: int) -> bool:
	for i in in_play.size():
		if in_play[i]["uid"] == uid:
			var e: Dictionary = in_play[i]
			in_play.remove_at(i)
			_to_discard(e)
			changed.emit()
			return true
	return false


## 활동 중 카드를 같은 uid 그대로 손패로 되돌린다(장비를 벗김). 손패가 가득 차거나 지금 시간대 카드가 아니면 주머니. 반환: 들어간 구역("" = 없음).
func return_from_play(uid: int) -> String:
	for i in in_play.size():
		if in_play[i]["uid"] != uid:
			continue
		var e: Dictionary = in_play[i]
		in_play.remove_at(i)
		var zone := "hand" if usable_now(e["id"]) and not hand_full() else "pocket"
		_returned_uids[uid] = true
		entries.append({"uid": e["uid"], "id": e["id"], "count": 1, "zone": zone, "person": e.get("person", "")})
		changed.emit()
		return zone
	return ""


## 계약 해지: 활동 중 카드를 버림패로 보내지 않고 없앤다(다시 뽑히지 않는다).
func release(uid: int) -> bool:
	for i in in_play.size():
		if in_play[i]["uid"] == uid:
			in_play.remove_at(i)
			changed.emit()
			return true
	return false


## 손패를 전부 버린다(겨울의 끝 종, docs/legend-cards-v01.md). 재화는 사라지고 그 밖의 카드는 침식까지 버림패로. 반환: 버린 장 수.
func discard_hand() -> int:
	var n := 0
	for e in hand():
		entries.erase(e)
		if not is_resource(e["id"]):
			_to_discard(e)
		n += 1
	if n > 0:
		changed.emit()
	return n


func _to_discard(e: Dictionary) -> void:
	if e.get("generated", false):
		return  # 용병이 만든 생성 카드는 쓰면 사라진다(merc_kit.gd)
	discard.append({"uid": e["uid"], "id": e["id"], "person": e.get("person", "")})
	stats["discarded"] += 1


# ───────────────────────── 스택 드로우(카드 N장 쓰면 1장) ─────────────────────────

## 한 번의 사용 확정을 연다. end_use()까지 소비된 카드는 합쳐서 최대 1회로 센다(C). 중첩 가능.
func begin_use() -> void:
	if _use_depth == 0:
		_use_ids.clear()
	_use_depth += 1


## 묶인 사용을 닫는다. 재화 외 카드가 하나라도 있으면 1회, 재화만이면 오늘 처음 쓴 종류가 있을 때만 1회.
func end_use() -> void:
	_use_depth = maxi(_use_depth - 1, 0)
	if _use_depth > 0:
		return
	var ids := _use_ids.duplicate()
	_use_ids.clear()
	if ids.is_empty():
		return
	for id in ids:
		if not is_resource(id):
			_count_use()
			return
	var fresh := false
	for id in ids:
		if not resource_uses_today.has(id):
			resource_uses_today[id] = true
			fresh = true
	if fresh:
		_count_use()


## 카드 한 장(또는 재화 묶음 일부)의 사용을 스택 규칙에 넘긴다. 재화는 종류마다 하루 첫 사용만 센다(B').
func _note_use(id: String) -> void:
	if not _count_uses:
		return
	if _use_depth > 0:
		_use_ids.append(id)
		return
	if is_resource(id):
		if resource_uses_today.has(id):
			return
		resource_uses_today[id] = true
	_count_use()


## 카드 사용 1회를 스택에 더한다. DRAW_STACK_SIZE가 되면 바로 1장 뽑는다(못 뽑으면 가득 찬 채 기다린다).
func _count_use() -> void:
	if MercKit.enabled and current_phase() == "night":
		return  # 용병 키트 v04: 전투 중 드로우 없음 — 카드는 용병이 만든다
	if draw_stack >= Cfg.DRAW_STACK_SIZE:
		# 가득 찬 채 기다리던 스택: 이 사용으로 자리가 났으면 먼저 뽑고, 이 사용은 다음 스택의 첫 칸이 된다
		if try_stack_draw():
			draw_stack = 1
			stack_changed.emit(draw_stack)
		return
	draw_stack += 1
	stack_changed.emit(draw_stack)
	try_stack_draw()


## 스택이 가득 찼고 뽑을 수 있으면 1장 뽑고 스택을 비운다. 손패가 가득 차거나 지금 시간대에 뽑을 카드가 없으면 기다린다.
## changed 뒤에도 호출되어 자리가 나는 순간 뽑는다. 반환: 뽑았는가.
func try_stack_draw() -> bool:
	if draw_stack < Cfg.DRAW_STACK_SIZE or hand_full() or eligible_pocket_empty():
		return false
	draw_stack = 0
	var got := draw(1)
	if got.is_empty():
		draw_stack = Cfg.DRAW_STACK_SIZE
		return false
	stats["stack_draws"] += 1
	stack_changed.emit(0)
	if game != null:
		game.toast("달빛 스택 %d — '%s' 드로우" % [Cfg.DRAW_STACK_SIZE, def(got[0]["id"]).get("name", "")], Color(1.0, 0.95, 0.8))
		game.sounds.play("card_draw")
	return true


# ───────────────────────── 모닥불에 태우기 ─────────────────────────

func burn_block_reason(uid: int) -> String:
	var e := get_entry(uid)
	if e.is_empty() or e["zone"] != "hand":
		return "손패의 카드만 태울 수 있습니다"
	if burns_today >= Cfg.BURN_DRAW_PER_DAY:
		return "오늘은 더 태울 수 없습니다 (하루 %d회)" % Cfg.BURN_DRAW_PER_DAY
	return ""


## 손패 카드를 태운다: 재화는 1개 소멸, 그 밖은 버림패, 침식 카드는 정화되어 사라진다(버림패 없음).
## 침식이 아니면 지금 시간대에 뽑을 수 있는 카드 1장을 뽑는다. 태우기 자체는 스택에 세지 않는다. 반환: {ok, id, corruption, drew(entry|{})}
func burn(uid: int) -> Dictionary:
	if burn_block_reason(uid) != "":
		return {"ok": false}
	var e := get_entry(uid)
	var id: String = e["id"]
	var corruption := is_corruption(id)
	var prev := _count_uses
	_count_uses = false
	if corruption:
		remove_uid(uid)
	else:
		consume(uid, 1)
	_count_uses = prev
	burns_today += 1
	stats["burns"] += 1
	var drew: Dictionary = {}
	if not corruption:
		var got := draw(1)
		if not got.is_empty():
			drew = got[0]
	changed.emit()
	return {"ok": true, "id": id, "corruption": corruption, "drew": drew}


## 새벽: 태우기 횟수·오늘 센 재화 초기화.
func on_prep_start() -> void:
	burns_today = 0
	resource_uses_today.clear()


# ───────────────────────── 낮↔밤 전환 ─────────────────────────

## 손패를 새 시간대로 바꾼다: 반대 시간대 카드(양쪽·침식 제외)를 모두 주머니로 보내고, 손패가 가득 찰 때까지 새 시간대 카드를 무작위로 뽑는다
## (사용자 결정 2026-10-23: 넣은 장수와 상관없이 언제나 손패 한도까지). fill=false면 뽑지 않는다(첫날 새벽은 시작 손패 화면이 대신).
## 재화 묶음은 묶음째 가고 묶음째 돌아온다(사용자 결정 2026-10-18). 주머니에 새 시간대 카드가 모자라면 있는 만큼만.
## 반환: {out: 보낸 entry 수, in: 뽑은 entry 목록}
func phase_swap(phase: String, fill := true) -> Dictionary:
	var moved: Array = []
	for e in hand():
		var p := phase_of(e["id"])
		if p == "both" or p == "none" or p == phase:
			continue
		moved.append(e)
	var out_uids: Array = moved.map(func(e): return e["uid"])
	for e in moved:
		_stash_entry(e)
	stats["swapped_out"] += moved.size()
	var got: Array = []
	if fill:
		# 용병 키트 v04: 밤 시작 손패는 5장까지만(그 뒤 카드는 용병이 만든다)
		got = _draw_whole(maxi(_start_hand() - hand().size(), 0) if MercKit.enabled and phase == "night" else Cfg.HAND_VISIBLE, phase)
	stats["swapped_in"] += got.size()
	if not moved.is_empty() or not got.is_empty():
		phase_swapped.emit(out_uids, got.map(func(e): return e["uid"]))
		changed.emit()
	if game != null and (not moved.is_empty() or not got.is_empty()):
		var what := ("%s 카드 %d장을 주머니에 넣고 " % ["낮" if phase == "night" else "밤", moved.size()]) if not moved.is_empty() else ""
		game.toast("%s 손패 — %s손패가 찰 때까지 %d장을 뽑았습니다" % ["밤" if phase == "night" else "낮", what, got.size()], Color(0.9, 0.85, 1.0))
		if not got.is_empty():
			game.sounds.play("card_draw")
	return {"out": moved.size(), "in": got}


## 밤 시작 손패 장수(용병 키트: 5장, 고블린 둘이면 6장).
func _start_hand() -> int:
	return game.merc_kit.start_hand() if game != null and game.get("merc_kit") != null else MercKit.START_HAND


## 손패 entry를 주머니로 보낸다. 묶음 재화는 주머니의 같은 묶음에 합친다.
func _stash_entry(e: Dictionary) -> void:
	if stackable(e["id"]):
		var stack := _find_stack(e["id"], "pocket")
		if not stack.is_empty():
			stack["count"] += int(e["count"])
			entries.erase(e)
			return
	e["zone"] = "pocket"


## 손패 카드 한 장을 주머니로 섞어 넣는다(술주정·도깨비불 독주 실패). 반환: 옮겼는지.
func stash_uid(uid: int) -> bool:
	var e := get_entry(uid)
	if e.is_empty() or e["zone"] != "hand":
		return false
	_stash_entry(e)
	changed.emit()
	return true


## 주머니에서 그 시간대 카드 n장을 무작위로 손패로(묶음은 묶음째). 손패가 차거나 후보가 없으면 멈춘다.
func _draw_whole(n: int, phase: String) -> Array:
	var out: Array = []
	for i in n:
		if hand_full():
			break
		var pool := eligible_pocket(phase)
		if pool.is_empty():
			break
		var pick: Dictionary = pool[randi() % pool.size()]
		var into := _move_to_hand_end(pick)
		stats["drawn"] += 1
		last_drawn.append(into["uid"])
		out.append(into)
	if not out.is_empty():
		drawn.emit(out.map(func(e): return e["uid"]))
	return out


# ───────────────────────── 드로우 ─────────────────────────

## 주머니의 카드 한 장(묶음 자원은 1개)을 손패로 가져온다. 손패가 가득 차거나 주머니가 비면 아무것도 하지 않는다.
## 지금 시간대에 못 쓰는 카드는 뽑지 않는다. 반환: 손패에 들어간 entry(빈 사전이면 드로우 없음).
func draw_uid(uid: int) -> Dictionary:
	var e := get_entry(uid)
	if e.is_empty() or e["zone"] != "pocket" or not usable_now(e["id"]):
		return {}
	# 손패가 가득 차도 같은 자원 묶음이 손패에 있으면 그 묶음에 1개 합산한다(새 칸을 쓰지 않음 — 획득 규칙 1과 같은 처리)
	if hand_full() and not (stackable(e["id"]) and not _find_stack(e["id"], "hand").is_empty()):
		return {}
	var into: Dictionary
	if stackable(e["id"]):
		var stack := _find_stack(e["id"], "hand")
		if int(e["count"]) > 1 or not stack.is_empty():
			e["count"] -= 1
			if e["count"] <= 0:
				entries.erase(e)
			if stack.is_empty():
				into = _new_entry(e["id"], 1, "hand", "")
			else:
				stack["count"] += 1
				into = stack
		else:
			into = _move_to_hand_end(e)
	else:
		into = _move_to_hand_end(e)
	stats["drawn"] += 1
	last_drawn.append(into["uid"])
	drawn.emit([into["uid"]])
	changed.emit()
	return into


## 주머니의 카드 한 장(묶음 자원은 1개)을 복제해 손패로 넣는다. 원본은 주머니에 그대로 남는다(오래된 마법서적).
## 손패가 가득 차거나(같은 자원 묶음이 손패에 있으면 합산) 지금 시간대에 못 쓰는 카드면 아무것도 하지 않는다.
## 반환: 손패에 들어간 entry(빈 사전이면 복제 없음).
func copy_uid(uid: int) -> Dictionary:
	var e := get_entry(uid)
	if e.is_empty() or e["zone"] != "pocket" or not usable_now(e["id"]):
		return {}
	var stack := _find_stack(e["id"], "hand") if stackable(e["id"]) else {}
	if hand_full() and stack.is_empty():
		return {}
	var into: Dictionary
	if stack.is_empty():
		into = _new_entry(e["id"], 1, "hand", e.get("person", ""))
	else:
		stack["count"] += 1
		into = stack
	stats["drawn"] += 1
	last_drawn.append(into["uid"])
	drawn.emit([into["uid"]])
	changed.emit()
	return into


## 뽑은 카드는 손패 순서의 맨 뒤(화면 오른쪽 끝)에 쌓인다. 손패 순서 = entries 순서.
func _move_to_hand_end(e: Dictionary) -> Dictionary:
	entries.erase(e)
	e["zone"] = "hand"
	entries.append(e)
	return e


## 주머니에서 지금 시간대에 쓸 수 있는 카드를 무작위로 n장 드로우. 반환: 손패에 들어간 entry 목록.
func draw(n := 1) -> Array:
	var out: Array = []
	for i in n:
		var pool := eligible_pocket()
		if pool.is_empty():
			break
		var pick: Dictionary = pool[randi() % pool.size()]
		var got := draw_uid(pick["uid"])
		if got.is_empty():
			break
		out.append(got)
	return out


## 주머니에서 지금 시간대에 쓸 수 있는 서로 다른 카드 n장을 무작위 후보로 고른다(오래된 마법서적·시작 손패). 부족하면 있는 만큼.
func draw_choices(n := Cfg.SPELLBOOK_CHOICES) -> Array:
	var pool := eligible_pocket().duplicate()
	pool.shuffle()
	return pool.slice(0, mini(n, pool.size()))


## 제외 목록에 없는, 지금 시간대에 쓸 수 있는 주머니 카드 한 장을 무작위로 고른다(시작 손패 교체). 없으면 빈 사전.
func peek_random_pocket(exclude: Array = []) -> Dictionary:
	var pool := eligible_pocket().filter(func(e): return not e["uid"] in exclude)
	if pool.is_empty():
		return {}
	return pool[randi() % pool.size()]


## 아침 드로우(확정 규칙 4): 주머니에 낮에 쓸 수 있는 카드가 있으면 무작위 한 장. 손패가 가득 차면 건너뛰고 카드를 주머니에 보존한다.
func morning_draw() -> Array:
	if eligible_pocket_empty():
		return []
	# 망각의 이슬주(주점 카드 v1): 다음 날 아침 드로우가 줄어든다
	if game != null and game.get("tavern") != null and game.tavern.take_draw_penalty() >= Cfg.MORNING_DRAW:
		stats["skipped_draws"] += 1
		return []
	# 꿈 기록장(종족 카드 v1): 마녀가 끼고 있으면 2장 중 1장을 고르는 창으로 대신한다
	if game != null and game.get("race_cards") != null and game.race_cards.dream_draw():
		stats["morning_draws"] += 1
		return []
	if hand_full():
		stats["skipped_draws"] += 1
		if game != null:
			game.toast("손패가 가득 차 아침 드로우를 건너뜁니다 — 주머니에 %d장 보존" % pocket().size(), Color(0.85, 0.8, 0.95))
		return []
	var got := draw(Cfg.MORNING_DRAW)
	if not got.is_empty():
		stats["morning_draws"] += 1
		if game != null:
			var names: Array = got.map(func(e): return def(e["id"]).get("name", e["id"]))
			game.toast("아침 드로우 — %s" % " · ".join(names), Color(1.0, 0.95, 0.8))
			game.sounds.play("card_draw")
	return got


# ───────────────────────── 조회 ─────────────────────────

## 직업 카드인지(네 직업 계약).
func is_job(id: String) -> bool:
	return id in Cfg.JOB_CARDS


func persons_in_use() -> Array:
	var out: Array = []
	for e in entries + in_play:
		if e["person"] != "":
			out.append(e["person"])
	return out
