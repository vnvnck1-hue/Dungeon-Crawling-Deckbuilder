extends Node
## LodgeEconomy: 숙박 예약·입실·지급의 단일 기록과 골드·구매.
## 각 묶음은 정해진 시각에 도착하고, 도착 시점의 정원만큼 인원이 정해지며, 20초 뒤 한 번만 지불한다.
## 카드 코어 v0.3 §5: 정산을 마친 손님 중 고용 가능한 사람이 문가에서 10초 기다린다. 고용하면 용병 계약 카드.

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const TravelerScript := preload("res://scripts/actors/traveler.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")

signal gold_changed(gold: int)
signal offers_changed
signal contracts_changed
signal batch_arrived(profiles: Array)
signal guest_departed(profile: Dictionary, reason: String)

var game
var gold := Cfg.START_GOLD
var total_earned := 0
var capacity := Cfg.BASE_CAPACITY
var bunk_level := 0         # 용병 숙소 증축 단계(Cfg.BUNK_LEVELS)
var batches: Array = []
var guests: Array = []
var offers: Array = []      # {person, guest, expires}
var prep_time := 0.0
var guest_visit_counts: Dictionary = {} # 첫인사와 재방문 대사. 낮이 바뀌어도 유지한다.
var today_ids: Array = []   # 오늘 이미 찾아온 손님 id(같은 날 같은 손님이 되도록 다시 오지 않게)
var forced_hire_race := ""  # 다음 고용 손님 한 명의 종족 고정(사촌의 사촌, scripts/game/merc_events.gd)


func _ready() -> void:
	name = "LodgeEconomy"


func begin_prep() -> void:
	batches.clear()
	today_ids.clear()
	for t in Cfg.GUEST_ARRIVALS:
		batches.append({"arrive": t, "pay": t + Cfg.GUEST_STAY, "count": 0, "spawned": false, "paid": false, "guests": []})


func update_prep(t: float) -> void:
	prep_time = t
	for o in offers.duplicate():
		if t >= o["expires"]:
			_close_offer(o, false)
	for bi in batches.size():
		var b: Dictionary = batches[bi]
		if not b["spawned"] and t >= b["arrive"]:
			b["spawned"] = true
			b["count"] = capacity
			_spawn_batch(b)
		if b["spawned"] and not b["paid"] and t >= b["pay"]:
			b["paid"] = true
			var amount: int = b["count"] * Cfg.GUEST_FEE
			_add_gold(amount)
			game.toast("+%dG 숙박비 (%d명)" % [amount, b["count"]], Color(1.0, 0.85, 0.45))
			var hire_slot: int = 0 if bi in hire_batches() or b.get("invited", false) else -1
			for i in b["guests"].size():
				var g = b["guests"][i]
				if not is_instance_valid(g):
					continue
				if i == hire_slot:
					_open_offer(g, t)
					continue
				var back: Array = Layout.TRAVELER_ROUTE.duplicate()
				back.reverse()
				g.leave(back, i * 0.5)
				guest_departed.emit(g.profile, "퇴실")


## 숙박 초대장: 손님 한 무리를 지금 바로 부른다. 정원만큼 묵고 숙박비를 내며, 한 명은 고용 제안을 한다.
## 사용 가능 여부는 invite_block_reason()으로 먼저 확인한다.
func invite_block_reason() -> String:
	if game.session.state != SessionScript.State.PREP:
		return "손님 초대는 준비 시간에만 가능합니다"
	if game.session.prep_remaining() < Cfg.INVITE_MIN_TIME:
		return "손님이 묵을 시간이 부족합니다 (남은 시간 %d초 이상 필요)" % int(Cfg.INVITE_MIN_TIME)
	return ""


func invite_batch() -> bool:
	if invite_block_reason() != "":
		return false
	batches.append({"arrive": prep_time, "pay": prep_time + Cfg.GUEST_STAY, "count": 0, "spawned": false, "paid": false,
		"guests": [], "invited": true})
	return true


## 손님 한 명을 판의 월드 설정(주요 종족 가중치)으로 무작위로 고른다(docs/races-guests-v01.md §7).
## 묶음의 첫 손님(hire_slot)은 고용 제안을 할 수 있는 손님, 나머지는 여행자.
## 1일차 첫 묶음의 첫 손님은 첫 번째 주요 종족의 전투용병이다: 판의 결이 바로 보이고, 첫 판 튜토리얼이 '산장 앞에 배치'로 진행된다.
func _roll_guest(hire_slot: bool, batch_index: int, taken: Array) -> Dictionary:
	var setting = game.get("world_setting")
	var exclude: Array = taken + _persons_unavailable()
	for g in guests:
		if is_instance_valid(g): exclude.append(g.profile.get("character_id", ""))
	if hire_slot and batch_index == 0 and game.session.day() == 1 and setting != null and not setting.majors.is_empty():
		for c in GuestProfiles.CATALOG:
			if c["race"] == setting.majors[0] and c["hireable"] and GuestProfiles.job_of(c["person"]) == "warrior" and not c["person"] in exclude:
				return GuestProfiles.guest_profile(c["id"])
	# 사촌의 사촌(고블린 용병 이벤트): 그날 첫 고용 손님을 이 종족으로 한 번 고정한다
	if hire_slot and forced_hire_race != "":
		for c in GuestProfiles.CATALOG:
			if c["race"] == forced_hire_race and c["hireable"] and not c["person"] in exclude and not c["id"] in exclude:
				forced_hire_race = ""
				return GuestProfiles.guest_profile(c["id"])
		forced_hire_race = ""
	var profile: Dictionary = GuestProfiles.pick_guest(setting, hire_slot, exclude, today_ids)
	if profile.is_empty() and hire_slot:
		# 고용 가능 24명이 모두 계약·숙박 중: 예전 이름 풀의 인간 용병(브람 초상 원형)으로 대신한다.
		profile = GuestProfiles.guest_profile("bram", _pick_name())
	elif profile.is_empty():
		profile = GuestProfiles.pick_guest(setting, false, taken)
	return profile


## 지금 손님으로 고를 수 없는 인물 이름(계약 카드·활동 중인 용병·고용 제안 중).
func _persons_unavailable() -> Array:
	var used: Array = game.cards.persons_in_use() + game.contracts.persons_active()
	for o in offers:
		used.append(o["person"])
	return used


func _pick_name(preferred: String = "") -> String:
	var used: Array = game.cards.persons_in_use() + game.contracts.persons_active()
	for o in offers:
		used.append(o["person"])
	for g in guests:
		if is_instance_valid(g) and g.profile.get("hireable", false):
			used.append(g.profile["person"])
	for n in [preferred] + Cfg.MERC_NAMES:
		if n != "" and not n in used:
			return n
	return "용병 %d" % (game.cards.stats["hired"] + 1)


func _open_offer(g, t: float) -> void:
	var person: String = g.profile.get("person", _pick_name())
	var o := {"person": person, "guest": g, "expires": t + Cfg.HIRE_WAIT, "job": GuestProfiles.job_of(person)}
	g.wait_at(Layout.DOOR_FRONT + Vector3(-0.9, 0, 0.7))
	offers.append(o)
	game.toast("손님 %s이(가) 일자리를 찾습니다 — %s 계약 %dG" % [o["person"], Cfg.JOB_NAMES[o["job"]], contract_cost()], Color(1.0, 0.88, 0.6))
	game.sounds.play("offer_open")
	offers_changed.emit()


func _close_offer(o: Dictionary, hired: bool) -> void:
	offers.erase(o)
	var g = o["guest"]
	if is_instance_valid(g):
		if hired:
			g.vanish()
			guest_departed.emit(g.profile, "계약 완료")
		else:
			var back: Array = Layout.TRAVELER_ROUTE.duplicate()
			back.reverse()
			g.leave(back, 0.0)
			guest_departed.emit(g.profile, "퇴실")
			game.sounds.play("offer_expire")
	offers_changed.emit()


func offer_time_left(o: Dictionary) -> float:
	return maxf(o["expires"] - prep_time, 0.0)


## 손님(guest_events 의 visit_uid)이 산장을 떠나기까지 남은 준비 시간(초). 모르면 -1.
## 숙박비를 내면 퇴실하고, 고용 제안을 하는 손님은 그 뒤 HIRE_WAIT 만큼 더 기다린다. 준비 시간이 끝나면 모두 떠난다.
func guest_time_left(visit_uid: int) -> float:
	var left := -1.0
	for o in offers:
		if is_instance_valid(o["guest"]) and int(o["guest"].profile.get("visit_uid", -1)) == visit_uid:
			left = offer_time_left(o)
	for bi in batches.size():
		var b: Dictionary = batches[bi]
		if left >= 0.0 or not b["spawned"] or b["paid"]:
			continue
		for i in b["guests"].size():
			var g = b["guests"][i]
			if is_instance_valid(g) and int(g.profile.get("visit_uid", -1)) == visit_uid:
				var hires: bool = i == 0 and (bi in hire_batches() or b.get("invited", false))
				left = maxf(b["pay"] - prep_time, 0.0) + (Cfg.HIRE_WAIT if hires else 0.0)
	if left < 0.0:
		return -1.0
	return minf(left, game.session.prep_remaining())


func hire_block_reason(o: Dictionary) -> String:
	if game.session.state != SessionScript.State.PREP:
		return "준비 시간에만 고용"
	if not o in offers:
		return "기회 종료"
	if gold < contract_cost():
		return "골드 부족"
	# 용병 숙소 침상 수가 데리고 있을 수 있는 용병 수(살아 있는 용병 + 미사용 계약 카드)다. 넘겨서 고용할 수 없다.
	if roster_count() >= bunk_capacity():
		return "침상 %d개가 모두 찼음 — %s" % [bunk_capacity(), _bunk_hint()]
	return ""


## 용병 숙소 침상 수 = 데리고 있을 수 있는 용병 수.
func bunk_capacity() -> int:
	return Cfg.BUNK_LEVELS[mini(bunk_level, Cfg.BUNK_LEVELS.size() - 1)]


## 다음 숙소 증축이 열리는 일차. 최대 단계면 -1.
func bunk_unlock_day() -> int:
	return Cfg.BUNK_UNLOCK_DAYS[bunk_level] if bunk_level < Cfg.BUNK_UNLOCK_DAYS.size() else -1


func _bunk_hint() -> String:
	var d := bunk_unlock_day()
	if d < 0:
		return "계약을 해지해 자리를 비우세요"
	if game.session.day() < d:
		return "숙소 증축은 %d일차부터" % d
	return "용병 숙소 증축 필요"


## 오늘 고용 제안이 나오는 숙박 묶음 번호. 1일차만 튜토리얼로 두 번.
func hire_batches() -> Array:
	return Cfg.HIRE_BATCHES_FIRST_DAY if game.session.day() <= 1 else Cfg.HIRE_BATCHES


## 계약료: 기본 + 종족 카드 v1의 가감(손패의 검은 소문 +8G/장, 소문 '환대' −5G).
func contract_cost() -> int:
	var d: int = game.race_cards.hire_cost_delta() if game.get("race_cards") != null else 0
	return maxi(Cfg.CONTRACT_COST + d, 0)


## 데리고 있는 용병 수: 활동 중인 용병 + 아직 쓰지 않은 계약 카드.
func roster_count() -> int:
	return game.contracts.mercs_alive() + _merc_cards()


## 아직 사용하지 않은 용병 계약 카드 수(손패·주머니, 네 직업 합계).
func _merc_cards() -> int:
	var n := 0
	for id in Cfg.JOB_CARDS:
		n += game.cards.count_of(id)
	return n


## 고용 제안의 직업 카드 id.
func offer_job(o: Dictionary) -> String:
	return o.get("job", GuestProfiles.job_of(o["person"]))


## 고용: 계약료 1회 결제 → 용병 계약 카드. 숙박비 정산과는 별개다.
func hire(o: Dictionary) -> bool:
	if hire_block_reason(o) != "":
		return false
	gold -= contract_cost()
	gold_changed.emit(gold)
	game.sounds.play("gold_spend")
	game.sounds.play("hire")
	var job := offer_job(o)
	game.cards.add(job, 1, o["person"])
	if game.get("merc_kit") != null:
		game.merc_kit.on_hired(o["person"])  # 고유 카드를 주머니로
	game.toast("%s을(를) 고용했습니다 — %s 계약 카드 획득" % [o["person"], Cfg.JOB_NAMES[job]], Color(1.0, 0.85, 0.5))
	_close_offer(o, true)
	return true


## 계약 목록(산장 관리 '계약' 탭): 활동 중인 용병과 아직 쓰지 않은 계약 카드.
## 각 항목 {kind: "ally"|"card", person, job, ally?, uid?}.
func contract_list() -> Array:
	var out: Array = []
	for a in game.contracts.allies:
		if is_instance_valid(a) and not a.dead and a.kind == "merc":
			out.append({"kind": "ally", "person": a.person, "job": a.job, "ally": a})
	for e in game.cards.entries:
		if e["id"] in Cfg.JOB_CARDS:
			out.append({"kind": "card", "person": e["person"], "job": e["id"], "uid": e["uid"]})
	return out


func dismiss_block_reason(c: Dictionary) -> String:
	if game.session.state != SessionScript.State.PREP:
		return "계약 해지는 낮(준비 시간)에만 가능"
	if game.get("race_cards") != null and game.race_cards.dismiss_block_reason(str(c.get("person", ""))) != "":
		return game.race_cards.dismiss_block_reason(str(c.get("person", "")))
	if c.get("kind") == "ally":
		var a = c.get("ally")
		if a == null or not is_instance_valid(a) or a.dead:
			return "이미 떠난 용병"
	elif game.cards.get_entry(int(c.get("uid", -1))).is_empty():
		return "이미 사용한 계약"
	return ""


## 계약 해지: 용병은 들고 있던 자원을 넘기고 떠나며, 계약 카드는 없어진다. 계약료의 절반(Cfg.CONTRACT_REFUND)을 돌려받는다.
func dismiss_contract(c: Dictionary) -> bool:
	if dismiss_block_reason(c) != "":
		return false
	if c["kind"] == "ally":
		c["ally"].dismiss()
	else:
		game.cards.remove_uid(int(c["uid"]))
	_add_gold(Cfg.CONTRACT_REFUND)
	game.toast("%s %s의 계약을 해지했습니다 — +%dG 환급" % [Cfg.JOB_NAMES.get(c["job"], "용병"), c["person"], Cfg.CONTRACT_REFUND], Color(1.0, 0.88, 0.6))
	contracts_changed.emit()
	return true


## 재화 판매(양털·생고기·토끼 가죽): 판매할 때만 골드가 생긴다(자동 판매 없음).
## 재화 카드는 1장=1개라, 끌어다 놓은 카드 1장 또는 손패의 같은 종류 N장을 판다.
func sell_wool(uid: int, amount: int) -> bool:
	return sell_resource(uid, amount)


func sell_resource(uid: int, amount: int) -> bool:
	var e: Dictionary = game.cards.get_entry(uid)
	if e.is_empty() or e["zone"] != "hand":
		return false
	return sell_id(e["id"], amount)


## 손패의 같은 종류 재화 amount장을 판다. 손패에 그만큼 없으면 아무것도 팔지 않는다.
func sell_id(id: String, amount: int) -> bool:
	if not Cfg.SALE_PRICES.has(id) or amount <= 0 or amount > game.cards.hand_count_of(id):
		return false
	if game.session.state != SessionScript.State.PREP:
		return false
	if not game.cards.consume_id(id, amount):
		return false
	if id == "wool":
		game.cards.stats["wool_sold"] += amount
	var price: int = Cfg.SALE_PRICES[id]
	_add_gold(amount * price)
	game.toast("%s %d장 판매 +%dG" % [game.cards.def(id).get("name", id), amount, amount * price], Color(1.0, 0.85, 0.45))
	game.sounds.play("card_play")
	return true


func _spawn_batch(b: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var arriving: Array = []
	var batch_index := batches.find(b)
	var taken: Array = []   # 이 묶음에서 이미 고른 인물 id
	# 첫 방문 에린(주점 카드): 묶음 맨 앞에서 먼저 걸어와 먼저 소개된다. 상주 손님이라 묶음(정산·퇴실)에는 넣지 않는다
	var lead: Array = game.tavern.lead_guests() if game.get("tavern") != null else []
	for p in lead:
		_spawn_resident(p, 0.0, rng)
		arriving.append(p)
	for i in b["count"]:
		var g := TravelerScript.new()
		g.profile = _roll_guest(i == 0, batch_index, taken)
		taken.append(g.profile["character_id"])
		var visitor_id: String = g.profile["character_id"]
		today_ids.append(visitor_id)
		var visits: int = guest_visit_counts.get(visitor_id, 0)
		g.profile["line"] = _greeting(g.profile, visits)
		guest_visit_counts[visitor_id] = visits + 1
		arriving.append(g.profile)
		var pts: Array = []
		for p in Layout.TRAVELER_ROUTE:
			pts.append(p + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)))
		pts[pts.size() - 1] = Layout.DOOR_FRONT
		g.setup(pts, (i + lead.size()) * 0.55)
		g.position = pts[0]
		game.actors.add_child(g)
		b["guests"].append(g)
		guests.append(g)
	# 꿀술 답례 손님(주점 카드 v1): 정원과 숙박비에 들지 않는 덤 손님으로 묶음 끝에 덧붙는다
	if game.get("tavern") != null:
		for p in game.tavern.extra_guests(taken):
			var g := TravelerScript.new()
			g.profile = p
			var visitor_id: String = p["character_id"]
			today_ids.append(visitor_id)
			if not p.get("mead_gift", false):
				var visits: int = guest_visit_counts.get(visitor_id, 0)
				p["line"] = _greeting(p, visits)
				guest_visit_counts[visitor_id] = visits + 1
			arriving.append(p)
			var i: int = b["guests"].size()
			var pts: Array = []
			for q in Layout.TRAVELER_ROUTE:
				pts.append(q + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)))
			pts[pts.size() - 1] = Layout.DOOR_FRONT
			g.setup(pts, i * 0.55)
			g.position = pts[0]
			game.actors.add_child(g)
			b["guests"].append(g)
			guests.append(g)
	batch_arrived.emit(arriving)


## 상주 손님(첫 방문 에린) 한 명을 숲길로 걸어오게 한다. 묶음·guests 밖이라 정산·준비 시간 끝에 떠나지 않고,
## 문 앞에서 들어가 판이 끝날 때까지 산장에 머문다.
func _spawn_resident(profile: Dictionary, delay: float, rng: RandomNumberGenerator) -> void:
	var visitor_id: String = profile["character_id"]
	today_ids.append(visitor_id)
	var visits: int = guest_visit_counts.get(visitor_id, 0)
	profile["line"] = GuestProfiles.greeting(profile, visits)
	guest_visit_counts[visitor_id] = visits + 1
	var g := TravelerScript.new()
	g.profile = profile
	var pts: Array = []
	for q in Layout.TRAVELER_ROUTE:
		pts.append(q + Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25)))
	pts[pts.size() - 1] = Layout.DOOR_FRONT
	g.setup(pts, delay)
	g.position = pts[0]
	game.actors.add_child(g)


## 묶음을 기다리지 않고 지금 바로 찾아오는 특별 손님(낮에 첫 조건을 채운 에린). 소개 연출을 거쳐 입실한다.
func spawn_extra(profiles: Array) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for p in profiles:
		_spawn_resident(p, 0.0, rng)
	batch_arrived.emit(profiles)


## 준비 시간 종료: 남은 손님 표시를 정리(정상 진행이면 모두 지불·퇴장한 뒤).
func end_prep() -> void:
	for o in offers.duplicate():
		_close_offer(o, false)
	for g in guests:
		if is_instance_valid(g):
			guest_departed.emit(g.profile, "퇴실")
			g.queue_free()
	guests.clear()


func guests_inside() -> int:
	var n := 0
	for b in batches:
		if b["spawned"] and not b["paid"]:
			n += b["count"]
	return n


func next_arrival_in(t: float) -> float:
	for b in batches:
		if not b["spawned"]:
			return b["arrive"] - t
	return -1.0


func next_payment_in(t: float) -> float:
	for b in batches:
		if b["spawned"] and not b["paid"]:
			return b["pay"] - t
	return -1.0


func _add_gold(amount: int) -> void:
	gold += amount
	total_earned += amount
	if amount > 0:
		game.sounds.play("gold_reward")
	gold_changed.emit(gold)


## 골드 지출(장날 구매·정화). 부족하면 아무것도 바꾸지 않는다.
func spend(amount: int) -> bool:
	if amount < 0 or gold < amount:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true


func debug_add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)


# ───────────────────────── 구매 ─────────────────────────

## 건축(생성·증축·업그레이드)의 다음 단계 비용 {gold, timber}. 최대 단계면 빈 사전.
func build_cost(kind: String) -> Dictionary:
	var steps: Array = Cfg.BUILD_COSTS.get(kind, [])
	var step := build_step(kind)
	if step < 0 or step >= steps.size():
		return {}
	return steps[step]


## 다음에 지을 단계 번호(0부터). 건축 항목이 아니면 -1.
func build_step(kind: String) -> int:
	match kind:
		"extension": return 1 if game.world.lodge.extension_built else 0
		"pasture": return game.world.pasture.level
		"graves": return game.world.graveyard.level
		"bunks": return bunk_level
	return -1


func is_build(kind: String) -> bool:
	return Cfg.BUILD_COSTS.has(kind)


## 감시탑 구매 항목("tower_left"·"tower_right")의 탑. 아니면 null.
## 목재는 공터에 미리 적립하므로(카드 끌어 놓기) 여기서는 골드만 낸다.
func tower_of(kind: String):
	if not kind.begins_with("tower_") or game.world == null:
		return null
	for t in game.world.towers:
		if "tower_" + t.site_id == kind:
			return t
	return null


func cost_of(kind: String) -> int:
	if is_build(kind):
		return int(build_cost(kind).get("gold", 0))
	var tower = tower_of(kind)
	if tower != null:
		return int(tower.next_step().get("gold", 0))
	match kind:
		"repair": return Cfg.COST_REPAIR
		"heal": return Cfg.COST_HEAL
		"sheep": return Cfg.COST_SHEEP
	return 0


func timber_cost_of(kind: String) -> int:
	return int(build_cost(kind).get("timber", 0)) if is_build(kind) else 0


## 쓸 수 있는 목재 = 손패에 뽑힌 목재(확정 규칙 9). 주머니 속 목재는 아침 드로우 등으로 손패에 와야 쓴다.
func timber() -> int:
	return game.cards.hand_count_of("timber")


## 버튼 표기: "60G · 목재 10"
func price_text(kind: String) -> String:
	if is_build(kind) and build_cost(kind).is_empty():
		return "완료"
	var tower = tower_of(kind)
	if tower != null:
		return "완료" if tower.level >= tower.max_level() else "%dG" % cost_of(kind)
	var t := timber_cost_of(kind)
	return "%dG" % cost_of(kind) + (" · 목재 %d" % t if t > 0 else "")


## 구매 불가 사유(가능하면 빈 문자열).
func block_reason(kind: String) -> String:
	var s = game.session
	if s.is_over():
		return "게임 종료"
	# 용 소환은 상점 구매가 아니다(2026-10-24): [용비늘] 카드 → card_use_resolver "dragon"
	if s.state != SessionScript.State.PREP:
		return "준비 시간에만 가능"
	if is_build(kind) and build_cost(kind).is_empty():
		return "최대 단계"
	var tower = tower_of(kind)
	if tower != null:
		if tower.level >= tower.max_level():
			return "최대 단계"
		if tower.collapsed:
			return "무너짐 — 목재로 먼저 수리"
		if not tower.stock_full():
			return "공터에 목재 적립 필요 (%d/%d)" % [tower.stock, tower.stock_needed()]
	match kind:
		"repair":
			if game.world.lodge.hp >= game.world.lodge.max_hp:
				return "체력 최대"
		"heal":
			if game.player.hp >= game.player.max_hp:
				return "체력 최대"
		"sheep":
			if not game.world.pasture.has_empty_slot():
				return "목장이 가득 참 — 목장 증축 필요"
		"bunks":
			if s.day() < bunk_unlock_day():
				return "%d일차부터 증축 가능" % bunk_unlock_day()
	if gold < cost_of(kind):
		return "골드 부족"
	if timber() < timber_cost_of(kind):
		return "목재 부족 (%d/%d)" % [timber(), timber_cost_of(kind)]
	return ""


## 조건 확인과 차감·효과를 한 번에 처리한다(연속 클릭에도 1회만 차감).
func buy(kind: String) -> bool:
	if block_reason(kind) != "":
		return false
	var cost := cost_of(kind)
	var wood := timber_cost_of(kind)
	if wood > 0 and not game.cards.consume_id("timber", wood):
		return false
	gold -= cost
	match kind:
		"extension":
			capacity = Cfg.EXT_CAPACITY
			game.world.lodge.build_extension()
			game.toast("객실 증축 완료 (목재 %d) — 다음 손님부터 정원 3명" % wood, Color(1.0, 0.85, 0.5))
		"pasture":
			game.world.pasture.upgrade()
			game.toast("목장 증축 완료 (목재 %d) — 양 최대 %d마리" % [wood, game.world.pasture.capacity()], Color(1.0, 0.9, 0.6))
		"graves":
			game.world.graveyard.upgrade()
			game.toast("묘지 확장 완료 (목재 %d) — 무덤 최대 %d기" % [wood, game.world.graveyard.capacity()], Color(0.85, 0.85, 1.0))
			if game.get("undead") != null:
				game.undead.grant_dagger("묘지를 넓히던 삽 끝")  # 언데드 진입(종족 카드 v1)
		"bunks":
			bunk_level += 1
			game.toast("용병 숙소 증축 완료 (목재 %d) — 침상 %d개" % [wood, bunk_capacity()], Color(1.0, 0.85, 0.5))
		"repair":
			var r: float = game.world.lodge.repair(Cfg.REPAIR_AMOUNT)
			game.toast("산장 수리 +%d" % int(r), Color(0.9, 0.9, 1.0))
		"heal":
			var h: float = game.player.heal(Cfg.HEAL_AMOUNT)
			game.toast("마녀 회복 +%d" % int(h), Color(0.8, 1.0, 0.8))
		"sheep":
			game.world.pasture.add_sheep()
			game.toast("양 한 마리를 들였습니다 (%d/%d)" % [game.world.pasture.alive_count(), game.world.pasture.capacity()], Color(1.0, 1.0, 0.95))
		"tower_left", "tower_right":
			var tower = tower_of(kind)
			tower.construct()
			game.toast("%s %d단계 완공 — 밤에 사냥꾼 %d명이 올라갑니다" % [tower.display_name(), tower.level, tower.slots()], Color(1.0, 0.85, 0.5))
	gold_changed.emit(gold)
	game.sounds.play("shop_buy")
	return true

## 첫인사: 다시 찾아온 손님은 기억 장부(guest_events.memory)에 맞는 인사가 있으면 지난 대답을 꺼낸다.
func _greeting(profile: Dictionary, visits: int) -> String:
	if visits > 0 and game.get("guest_events") != null:
		var remembered: String = game.guest_events.memory_greeting(str(profile.get("character_id", "")))
		if remembered != "": return remembered
	return GuestProfiles.greeting(profile, visits)
