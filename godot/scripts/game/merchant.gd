extends Node
## 떠돌이 행상 브로크(기획: docs/merchant-shop-v01.md).
## 사흘마다(3·6·9·12일차) 낮 한가운데에 혼자 숲길로 걸어와 산장 앞에 좌판을 펼친다.
## 도착 소개가 끝나고 좌판 자리에 닿으면 상점(offer_screen 장날 화면)이 열리고, 무작위 카드 5장을 가치에 맞는 값으로 판다.
## 상점은 그날 한 번뿐이다: 닫으면 브로크는 좌판을 거두고 숲길로 떠나며, 그날은 다시 열 수 없다(사용자 지시 2026-10-24).

const Data := preload("res://scripts/game/merchant_data.gd")
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")
const TravelerScript := preload("res://scripts/actors/traveler.gd")
const Layout := preload("res://scripts/world/layout.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")

## 좌판 자리: 산장 문 오른쪽 앞마당(고용 제안 손님은 문 왼쪽에 선다).
const STALL_SPOT := Layout.DOOR_FRONT + Vector3(1.3, 0.0, 1.1)

var game
var actor                      # 걸어오는 브로크(Traveler). 없으면 null
var profile: Dictionary = {}   # 오늘 방문의 프로필(visit_uid 포함)
var offers: Array = []         # 오늘 좌판 [{id, price, sold}]
var visited_day := 0           # 마지막으로 찾아온 일차(하루 한 번)
var visits := 0                # 이번 판에 찾아온 횟수(인사말이 바뀐다)
var admitted := false          # 도착 소개를 마쳤는가
var auto_opened := false       # 오늘 상점을 처음 자동으로 열었는가
var shop_done := false         # 오늘 상점을 닫았는가(그날은 다시 열지 않는다)
var rerolled := false          # 오늘 좌판을 다시 펼쳤는가(방문마다 한 번)
var stats := {"visits": 0, "opened": 0, "bought": 0, "spent": 0, "rerolls": 0}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	name = "Merchant"
	_rng.randomize()
	game.session.state_changed.connect(_on_state)
	game.guest_events.admitted.connect(_on_admitted)


func present() -> bool:
	return actor != null and is_instance_valid(actor) and not actor.leaving


## 오늘이 행상이 오는 날인가.
func visits_today() -> bool:
	return Data.is_visit_day(game.session.day())


func _on_state(state: int) -> void:
	if state == SessionScript.State.PREP:
		if visits_today():
			game.toast("오늘 낮, 떠돌이 행상 브로크가 좌판을 지고 찾아옵니다", Color(1.0, 0.9, 0.6))
	elif state == SessionScript.State.COMBAT:
		leave("밤이 되어 떠남")


func _process(_delta: float) -> void:
	var s = game.session
	if s.state != SessionScript.State.PREP or s.is_over():
		return
	if visits_today() and visited_day != s.day() and s.prep_elapsed >= Data.ARRIVE_AT:
		arrive()
	if present() and admitted and not auto_opened and at_stall() and _can_open_now():
		auto_opened = true
		open_shop()


## 지금 바로 찾아오게 한다(정해진 시각에 _process 가 부르며, 검증 도구도 부른다).
func arrive() -> void:
	if present():
		return
	visited_day = game.session.day()
	admitted = false
	auto_opened = false
	shop_done = false
	rerolled = false
	offers = Data.roll_offers(game.cards.defs, _rng)
	profile = GuestProfiles.guest_profile(Data.CHARACTER_ID)
	profile["line"] = GuestProfiles.greeting(profile, visits)
	profile["merchant"] = true
	visits += 1
	stats["visits"] += 1
	var g := TravelerScript.new()
	g.profile = profile
	var pts: Array = []
	for p in Layout.TRAVELER_ROUTE:
		pts.append(p + Vector3(_rng.randf_range(-0.2, 0.2), 0, _rng.randf_range(-0.2, 0.2)))
	pts[pts.size() - 1] = STALL_SPOT
	g.setup(pts, 0.0)
	g.waiting = true   # 길 끝(좌판 자리)에서 들어가지 않고 마당을 보며 선다
	g.position = pts[0]
	game.actors.add_child(g)
	actor = g
	game.toast("떠돌이 행상 브로크가 숲길로 들어섭니다", Color(1.0, 0.9, 0.6))
	# 혼자 오는 손님 한 명의 묶음: 도착 소개·손님 탭·말풍선은 기존 손님 흐름을 그대로 쓴다
	game.economy.batch_arrived.emit([profile])


## 길 끝 좌판 자리에 닿았는가.
func at_stall() -> bool:
	return present() and actor.route.is_empty()


func _on_admitted(p: Dictionary) -> void:
	if not p.get("merchant", false):
		return
	admitted = true
	# 손님 기록: 이야기 말풍선을 띄우지 않는다(상점은 좌판 자리에 닿으면 저절로 한 번 열린다)
	var entry: Dictionary = game.guest_events.visit(int(p.get("visit_uid", -1)))
	if not entry.is_empty():
		entry.status = "산장 앞에 좌판을 펼침"
		entry.story = {"title": "행상의 좌판", "prompt": "", "opening": "", "special": "merchant"}
		entry.read = true


## 다른 가운데 화면·대화·관리창이 열려 있지 않을 때만 자동으로 연다.
func _can_open_now() -> bool:
	if game.get_tree().paused:
		return false
	var ui = game.get("offer_ui")
	if ui == null or ui.active:
		return false
	if game.get("guest_ui") != null and game.guest_ui.dialogue_active:
		return false
	var hud = game.get("hud")
	if hud == null:
		return true
	for panel_name in ["pause_panel", "lodge_panel", "merc_panel"]:
		var panel = hud.get(panel_name)
		if panel != null and panel.visible:
			return false
	return true


func shop_block_reason() -> String:
	if game.session.state != SessionScript.State.PREP:
		return "행상은 낮에만 장사합니다"
	if shop_done:
		return "오늘 장사는 끝났습니다"
	if not present():
		return "행상이 산장에 없습니다"
	if game.offer_ui == null or game.offer_ui.active:
		return "다른 화면이 열려 있습니다"
	return ""


## 상점을 연다(자동·말풍선·손님 탭). 성공하면 true.
func open_shop() -> bool:
	if shop_block_reason() != "":
		return false
	if game.get("hud") != null:
		game.hud.close_lodge_panel()
	stats["opened"] += 1
	game.sounds.voice(profile, "talk_open")
	game.offer_ui.open_merchant(offers, profile)
	return true


## 상점을 닫았다(offer_screen.close): 그날 장사는 끝, 좌판을 거두고 숲길로 떠난다.
func on_shop_closed() -> void:
	if shop_done:
		return
	shop_done = true
	game.toast("브로크: 오늘 장사는 여기까지요. 사흘 뒤에 또 오리다", Color(1.0, 0.9, 0.6))
	leave("장사를 마치고 떠남")


func reroll_block_reason() -> String:
	if rerolled:
		return "오늘은 이미 다시 펼쳤습니다"
	if shop_done or not present():
		return "행상이 산장에 없습니다"
	if game.economy.gold < Data.REROLL_PRICE:
		return "골드가 부족합니다 (%dG 필요)" % Data.REROLL_PRICE
	return ""


## 좌판 다시 펼치기: REROLL_PRICE(100G)를 내고 5장을 지금 좌판과 겹치지 않는 새 무작위 카드로 바꾼다(방문마다 한 번). 성공하면 true.
func reroll() -> bool:
	if reroll_block_reason() != "" or not game.economy.spend(Data.REROLL_PRICE):
		return false
	rerolled = true
	stats["rerolls"] += 1
	stats["spent"] += Data.REROLL_PRICE
	offers = Data.roll_offers(game.cards.defs, _rng, offers.map(func(o): return o["id"]))
	game.sounds.play_or("gold_spend", "card_shuffle")
	game.toast("브로크: 좋소, 짐 밑바닥 것도 꺼내 보리다 (-%dG)" % Data.REROLL_PRICE, Color(1.0, 0.9, 0.6))
	return true


## 오늘 좌판에서 아직 팔리지 않은 카드 수.
func unsold() -> int:
	return offers.filter(func(o): return not o.get("sold", false)).size()


## 구매 기록(offer_screen.buy 가 chapter.buy 로 결제한 뒤 부른다).
func on_bought(offer: Dictionary) -> void:
	stats["bought"] += 1
	stats["spent"] += int(offer["price"])
	if unsold() == 0 and present():
		game.toast("브로크: 오늘 짐은 다 팔았소!", Color(1.0, 0.9, 0.6))


## 밤이 되면(또는 판이 끝나면) 숲길로 돌아간다.
func leave(reason: String) -> void:
	if actor == null or not is_instance_valid(actor):
		actor = null
		return
	if not profile.is_empty():
		game.economy.guest_departed.emit(profile, reason)
	var back: Array = Layout.TRAVELER_ROUTE.duplicate()
	back.reverse()
	if game.session.state == SessionScript.State.PREP:
		actor.leave(back, 0.0)
	else:
		actor.queue_free()
	actor = null
