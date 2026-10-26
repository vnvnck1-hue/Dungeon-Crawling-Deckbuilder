extends Node
## 용병 이벤트 v1 — 고블린(기획: docs/deck-archetypes-v01.md §3.1·§4.1, 적용 기록 docs/goblin-cards-v01.md).
## 고용한 고블린 용병이 새벽에 가끔 말을 걸고, 선택지에 따라 고블린 카드를 준다. 고블린을 많이 데리고 있을수록 고블린 카드가 쌓인다.
## 손님 대화 체계(guest_events·guest_interactions)를 그대로 쓴다: 방문 기록에 "용병 방문" 항목을 넣으면 같은 말풍선·대화창이 열린다.
## 선택지 효과는 "merc:..." 문자열로, guest_events.apply_effect() 가 이 모듈로 넘긴다.
## 말라(고블린 골동품 수집가, 여행자)는 고블린 용병이 있을 때 묵으면 '값을 매기는 눈' 특별 이야기를 꺼낸다.

const GoblinData := preload("res://scripts/game/goblin_data.gd")
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const RaceEvents := preload("res://scripts/game/race_events_data.gd")
const RaceData := preload("res://scripts/game/race_card_data.gd")
## 종족 카드 v1(docs/race-cards-v01.md §2): 고블린 이벤트를 모든 종족·공용(중립·화합·브리지) 이벤트로 넓혔다.
## 대사는 race_events_data.gd. 하루 최대 1건 — 70%는 데리고 있는 용병 한 명이 자기 종족 이벤트, 30%(통역사의 펜 55%)는 공용 이벤트.
const SHARED_RACES := ["neutral", "harmony", "bridge"]

## 고블린 용병 이벤트. who: 말을 거는 고블린 용병 id(고용 가능 4명), 비면 아무 고블린 용병.
## 선택지 effect: merc:card:<id> / merc:gold:<n> / merc:add:<id>:<n> / merc:debt / merc:cousin
const EVENTS := {
	"gang": {"who": ["graz"], "prompt": "주인! 좋은 소식!", "title": "근처에 온 친척들",
		"opening": "숲 건너에 사촌들이 와 있대.\n밥만 주면 밤에 싸워 준대.\n…다 내 사촌은 아니고, 친구들도.",
		"choices": [{"text": "불러 와. 밤에 쓰자.", "effect": "merc:card:goblin_gang", "reply": "헤헤, 표식만 놓으면 와!\n밤에 땅에 놓기만 해.\n셋, 넷은 금방이야."},
			{"text": "너 하나면 충분해.", "effect": "merc:gold:6", "reply": "…그, 그치? 내가 최고지!\n크흠. 사촌들이 보낸 동전이야.\n밥값 아꼈다고."}],
		"closing": "오늘 밤도 내가 앞에 설게.\n…뒤에서 사촌들이 밀어 줄 거고."},
	"whistle": {"who": ["graz"], "prompt": "이거 봐 봐.", "title": "할아버지 호루라기",
		"opening": "할아버지 호루라기야.\n불면 졸개들이 온대.\n…무서워서 한 번도 안 불었어.",
		"choices": [{"text": "같이 불어 보자.", "effect": "merc:card:graz_whistle", "reply": "삐익―! …와, 진짜 온다!\n고블린 목에 걸어 줘.\n셋까지는 따라올 거야."},
			{"text": "소중한 거잖아. 간직해.", "effect": "merc:gold:6", "reply": "…주인은 착하네.\n그럼 이건 감사 인사.\n동전 몇 닢."}],
		"closing": "언젠가 내가 불게.\n할아버지처럼, 크게."},
	"helmet": {"who": ["graz"], "prompt": "냄비 얘기야!", "title": "찌그러진 냄비",
		"opening": "이 냄비, 투구로 딱이야.\n찌그러지면 매일 아침 펴면 돼.\n고블린은 그렇게 살아.",
		"choices": [{"text": "하나 더 만들어 줘.", "effect": "merc:card:pot_helmet", "reply": "자, 여기!\n다섯 대까진 막아 줘.\n고블린이 쓰면 계속 펴서 써."},
			{"text": "그건 그냥 냄비잖아…", "effect": "merc:gold:6", "reply": "냄비라고 무시하지 마!\n…알았어, 팔아서 동전으로 줄게.\n흥."}],
		"closing": "오늘 밤 냄비 소리 나면\n나인 줄 알아."},
	"firecracker": {"who": ["tak"], "prompt": "쉭쉭 소리가 나!", "title": "주머니 속 수상한 통",
		"opening": "주머니에서 이게 나왔어.\n흔들면 쉭쉭 소리가 나.\n…불 붙이면 어떻게 될까?",
		"choices": [{"text": "밤에 적한테 던져 보자.", "effect": "merc:card:goblin_firecracker", "reply": "펑! 할 거야, 아마!\n가까이 있는 친구는… 조심해.\n가끔 우리 쪽으로도 튀어."},
			{"text": "당장 물에 담가!", "effect": "merc:card:junk_sack", "reply": "에이, 알았어…\n대신 주머니 정리한 거 줄게.\n쓸 만한 것도 있을걸."}],
		"closing": "주머니엔 아직 많아.\n다음엔 더 큰 걸로!"},
	"sack": {"who": ["tak"], "prompt": "주머니가 무거워…", "title": "주머니 대청소",
		"opening": "주머니가 너무 무거워.\n반은 버려야 하는데…\n주인이 가져갈래?",
		"choices": [{"text": "다 줘 봐.", "effect": "merc:card:junk_sack", "reply": "여기 한 자루!\n뭐가 나올지는 나도 몰라.\n쇠붙이면… 팔아."},
			{"text": "버리지 말고 팔아.", "effect": "merc:gold:8", "reply": "오, 그 생각을 못 했네!\n팔고 남은 거 나눠 줄게.\n여기 동전."}],
		"closing": "가벼워졌다!\n이제 또 주워야지."},
	"lure": {"who": ["tak"], "prompt": "반짝이는 거!", "title": "반짝이는 것",
		"opening": "반짝이는 걸 보면 다들 멈춰.\n나도, 까마귀도, 괴물도.\n그걸로 뭘 할 수 있을까?",
		"choices": [{"text": "미끼로 쓰자.", "effect": "merc:card:shiny_lure", "reply": "유리구슬을 잔뜩 붙였어.\n던지면 다 몰려와.\n그리고… 펑, 눈이 부셔!"},
			{"text": "넌 멈추지 마.", "effect": "merc:gold:6", "reply": "헤헤, 노력할게.\n대신 이거, 주운 동전.\n반짝이지?"}],
		"closing": "오늘 밤엔 안 멈출게.\n…아마도."},
	"barricade": {"who": ["rusk"], "prompt": "이 톱 봐!", "title": "톱날 자랑",
		"opening": "이 톱 봐, 이 톱!\n고물로도 울타리를 금방 세워.\n…2일이면 무너지지만.",
		"choices": [{"text": "급할 때 쓰게 하나 줘.", "effect": "merc:card:junk_barricade", "reply": "목재 하나면 돼!\n금방 세우고, 금방 무너져.\n고블린 식이야."},
			{"text": "제대로 된 걸 세워야지.", "effect": "merc:add:timber:2", "reply": "흥, 장인 납셨네.\n그럼 남은 판자나 가져가.\n제대로 써."}],
		"closing": "톱날은 오늘도 반짝!\n…아, 내 손가락 조심."},
	"rush": {"who": ["pikl"], "prompt": "셈이 안 맞아.", "title": "졸개 셈",
		"opening": "졸개가 다섯이면 한 마리 몫,\n열이면… 셈이 안 돼.\n한꺼번에 몰면 셈이 쉬워!",
		"choices": [{"text": "한꺼번에 몰아 봐.", "effect": "merc:card:goblin_rush", "reply": "하나, 둘… 에잇, 다 같이!\n졸개가 많을수록 세게 박아.\n없으면 못 써."},
			{"text": "하나씩 세는 게 낫지.", "effect": "merc:gold:6", "reply": "…맞아, 셈은 하나씩.\n센 김에 동전도 셌어.\n여기, 정확히 여섯."}],
		"closing": "오늘 밤 졸개는\n내가 다 셀게."},
	"traps": {"who": ["pikl"], "prompt": "덫 하나가 이상해.", "title": "셋인데 넷",
		"opening": "덫을 셋 놨는데 넷이 걸렸어.\n…하나가 두 번 밟았나 봐.\n산장에도 놔 줄까?",
		"choices": [{"text": "산장 앞에 놔 줘.", "effect": "merc:card:pikl_traps", "reply": "셋! 정확히 셋.\n터지면 내가 새벽에 다시 놓을게.\n고블린이 있으면 말이야."},
			{"text": "사냥감 줄면 곤란해.", "effect": "merc:add:raw_meat:1", "reply": "그럼 걸린 거나 가져가.\n오늘 잡은 고기.\n…넷째 건 비밀이야."},
		],
		"closing": "덫은 세고, 또 세고.\n그게 내 일이야."},
	"debt": {"who": ["pikl", "graz"], "prompt": "문서가 하나 있어.", "title": "빚 문서",
		"opening": "니브 아저씨가 맡긴 문서야.\n서명하면 고블린 하나가 바로 와.\n대신 3일 뒤에 갚아야 해.",
		"choices": [{"text": "서명할게.", "effect": "merc:debt", "reply": "좋아! 바로 계약 카드 줄게.\n3일 뒤 새벽에 %dG.\n못 갚으면… 그 친구는 가.", "fail_reply": "…지금 올 수 있는 고블린이 없대.\n문서는 내가 갖고 있을게.\n다음에 다시 물어볼게."},
			{"text": "찢어 버려.", "reply": "찌익―.\n니브 아저씨한텐 비밀이야.\n…아마 알겠지만."}],
		"closing": "빚은 무서운 거야.\n고블린도 알아."},
	"cousin": {"who": [], "prompt": "부탁 하나만!", "title": "사촌의 사촌",
		"opening": "사촌의 사촌이 일을 찾는대.\n내일 오라고 할까?\n대신 오늘 먹을 걸 좀 나눠 줘.",
		"choices": [{"text": "내일 오라고 해.", "effect": "merc:cousin", "reply": "고마워, 주인!\n내일 꼭 올 거야.\n먹을 건 내가 갖다줄게."},
			{"text": "다음에.", "effect": "merc:gold:10", "reply": "알았어…\n대신 사촌이 보낸 동전.\n미안하대."}],
		"closing": "고블린은 많을수록 좋아.\n…밥은 좀 더 들지만."},
}

## 말라의 특별 이야기(값을 매기는 눈 — 사용자 지정 대화, 2026-10-19 검수 코멘트).
const MALA_STORY := {"prompt": "흠, 마녀님.", "title": "값을 매기는 눈", "special": "merc",
	"opening": "이 산장엔 값나가는 게 꽤 굴러다녀요.\n다들 그냥 밟고 지나가더군요.\n금화를 세는 법, 물건을 알아보는 법. 어느 쪽?",
	"choices": [
		{"text": "금화를 센다.", "effect": "merc:mala:mala_coin_scale", "reply": "현명하시네요.\n동전은 거짓말을 안 하거든요.\n이 저울을 쥐여 주세요."},
		{"text": "물건을 본다.", "effect": "merc:mala:mala_monocle", "reply": "오, 안목이 있으시군요.\n고물 속에 보물이 있는 법이죠.\n이 안경을 씌워 주세요."}],
	"closing": "값을 아는 눈은\n쉽게 속지 않는답니다."}

var game
var done: Dictionary = {}        # 이번 판에 마친 이벤트 키
var today_day := -1              # 마지막으로 이벤트를 띄운 날
var mala_given := false
var cousin_day := -1             # 사촌의 사촌이 오는 날
var first_shown := false         # 고블린을 처음 데리고 맞는 새벽엔 반드시 한 번
var _rng := RandomNumberGenerator.new()
var event_log: Array = []            # [{day, key, person}] 검증·기록용


func _ready() -> void:
	name = "MercEvents"
	_rng.randomize()
	if game.get("session") != null and game.session != null:
		game.session.state_changed.connect(_on_state)


func _on_state(state: int) -> void:
	if state == SessionScript.State.PREP:
		on_dawn(game.session.day())
	elif state == SessionScript.State.COMBAT:
		_close_merc_visits()


## 이 인물 이름의 손님 프로필 id(카탈로그 밖 이름이면 "").
static func character_of(person: String) -> String:
	for c in GuestProfiles.CATALOG:
		if c["person"] == person:
			return c["id"]
	return ""


## 데리고 있는 고블린 용병(활동 중 + 계약 카드)의 [{person, id}].
func goblin_roster() -> Array:
	var out: Array = []
	var seen := {}
	for a in game.contracts.allies:
		if is_instance_valid(a) and not a.dead and a.kind == "merc":
			var cid := character_of(a.person)
			if cid != "" and GuestProfiles.race_of(a.person) == GoblinData.RACE and not seen.has(cid):
				seen[cid] = true
				out.append({"person": a.person, "id": cid})
	for e in game.cards.entries:
		if game.cards.is_job(e["id"]):
			var p: String = str(e.get("person", ""))
			var cid2 := character_of(p)
			if cid2 != "" and GuestProfiles.race_of(p) == GoblinData.RACE and not seen.has(cid2):
				seen[cid2] = true
				out.append({"person": p, "id": cid2})
	return out


## 데리고 있는 모든 용병(활동 중 + 계약 카드)의 [{person, id, race}]. 손님 카탈로그 밖 이름은 빠진다.
func full_roster() -> Array:
	var out: Array = []
	var seen := {}
	var people: Array = []
	for a in game.contracts.allies:
		if is_instance_valid(a) and not a.dead and a.kind == "merc":
			people.append(a.person)
	for e in game.cards.entries:
		if game.cards.is_job(e["id"]):
			people.append(str(e.get("person", "")))
	for p in people:
		var cid := character_of(p)
		if cid == "" or seen.has(cid):
			continue
		seen[cid] = true
		var r := GuestProfiles.race_of(p)
		out.append({"person": p, "id": cid, "race": r if r != "" else "human"})
	return out


## 모든 이벤트(고블린 + 종족 카드 v1). 고블린 이벤트에는 race 를 붙인다.
func all_events() -> Dictionary:
	var out := {}
	for k in EVENTS:
		var ev: Dictionary = EVENTS[k].duplicate()
		ev["race"] = GoblinData.RACE
		out[k] = ev
	for k in RaceEvents.EVENTS:
		out[k] = RaceEvents.EVENTS[k]
	return out


## 새벽: 사촌의 사촌 도착 예약을 걸고, 용병 이벤트를 굴린다(모든 종족 합쳐 하루 최대 1건).
func on_dawn(day: int) -> void:
	if day == cousin_day:
		game.economy.forced_hire_race = GoblinData.RACE
		game.toast("사촌의 사촌이 오늘 산장을 찾아옵니다", Color(0.75, 1.0, 0.5))
	if day <= 1 or today_day == day:
		return
	var roster := full_roster()
	if roster.is_empty():
		return
	if first_shown and _rng.randf() >= RaceData.EVENT_CHANCE:
		return
	if trigger(roster):
		first_shown = true


## 공용 이벤트 확률(통역사의 펜이면 55%).
func shared_chance() -> float:
	if game.get("race_cards") != null and game.race_cards.witch_wears("interpreter_pen"):
		return RaceData.PEN_SHARED_CHANCE
	return RaceData.SHARED_CHANCE


## 이 이벤트의 조건(브리지·화합)을 지금 roster 가 채우는지.
func _need_ok(ev: Dictionary, roster: Array) -> bool:
	var races := {}
	for s in roster:
		races[s["race"]] = true
	match str(ev.get("need", "")):
		"dwarf_orc":
			return races.has("dwarf") and races.has("orc")
		"races3":
			return races.size() >= RaceData.BANNER_RACES
		"races4":
			return races.size() >= RaceData.FESTIVAL_RACES
	return true


## 이 종족의 이벤트를 모두 끝냈는지(그러면 repeat 이벤트가 다시 나올 수 있다).
func _race_exhausted(race: String, evs: Dictionary) -> bool:
	for k in evs:
		if evs[k]["race"] == race and not done.has(k):
			return false
	return true


## 화자 s 가 꺼낼 수 있는 이벤트 키 목록. shared=true 면 공용 이벤트.
func _options_for(s: Dictionary, roster: Array, evs: Dictionary, shared: bool, key := "") -> Array:
	var out: Array = []
	var today: int = game.session.day()
	for k in evs:
		if key != "" and k != key:
			continue
		var ev: Dictionary = evs[k]
		var race: String = ev["race"]
		if shared != (race in SHARED_RACES):
			continue
		if not shared and race != s["race"]:
			continue
		if race == "fairy" and game.get("race_cards") != null and game.race_cards.fairy_pause_day == today:
			continue
		if done.has(k) and not (ev.get("repeat", false) and _race_exhausted(race, evs)):
			continue
		var who: Array = ev.get("who", [])
		if not who.is_empty() and not s["id"] in who:
			continue
		# 이야기 속에 3인칭으로 나오는 인물은 그 이야기의 화자가 될 수 없다("티슬이 가시를 나눠 줬어요"를 티슬이 말하지 않게)
		if _mentions(ev, str(s["person"])):
			continue
		if not _need_ok(ev, roster):
			continue
		# 조상의 길·겨울잠은 떠날 수 있는 용병(피의 맹세 아님)만 꺼낸다
		if k in ["o_path", "b_sleep"] and game.get("race_cards") != null and s["person"] in game.race_cards.oath_persons:
			continue
		out.append(k)
	return out


## 이벤트 글(opening·대답·맺음) 어딘가에 이 이름이 나오는지.
static func _mentions(ev: Dictionary, person: String) -> bool:
	if person == "": return false
	var texts: Array = [ev.get("opening", ""), ev.get("closing", "")]
	for c in ev.get("choices", []):
		texts.append_array([c.get("text", ""), c.get("reply", ""), c.get("fail_reply", "")])
	for t in texts:
		if person in str(t): return true
	return false


## 이벤트 하나를 띄운다(검증 도구가 직접 부를 수 있다). key 를 주면 그 이벤트, 아니면 말할 수 있는 것 중 무작위.
func trigger(roster: Array = [], key := "") -> bool:
	if roster.is_empty():
		roster = full_roster()
	for s in roster:
		if not s.has("race"):
			var r := GuestProfiles.race_of(s["person"])
			s["race"] = r if r != "" else "human"
	if roster.is_empty():
		return false
	var evs := all_events()
	# 키를 지정하면 그 이벤트를 꺼낼 수 있는 화자 중 무작위
	if key != "":
		if not evs.has(key):
			return false
		var shared_k: bool = evs[key]["race"] in SHARED_RACES
		var cands: Array = roster.filter(func(s): return not _options_for(s, roster, evs, shared_k, key).is_empty())
		if cands.is_empty():
			return false
		_open(key, cands[_rng.randi_range(0, cands.size() - 1)])
		return true
	# 70%: 용병 한 명이 자기 종족 이벤트 / 30%: 공용 이벤트. 한쪽이 비면 다른 쪽
	var order := [true, false] if _rng.randf() < shared_chance() else [false, true]
	for shared in order:
		var speakers := roster.duplicate()
		speakers.shuffle()
		for s in speakers:
			var opts := _options_for(s, roster, evs, shared)
			if not opts.is_empty():
				_open(opts[_rng.randi_range(0, opts.size() - 1)], s)
				return true
	return false


func _open(key: String, speaker: Dictionary) -> void:
	var ge = game.guest_events
	var profile: Dictionary = GuestProfiles.guest_profile(speaker["id"])
	profile["person"] = speaker["person"]
	var story: Dictionary = all_events()[key].duplicate(true)
	for k in ["who", "race", "repeat", "need"]:
		story.erase(k)
	story["special"] = "merc"
	if "%s" in str(story.get("opening", "")) and game.get("race_cards") != null:
		story["opening"] = str(story["opening"]) % game.race_cards.event_text(key)
	for c in story["choices"]:
		if c.get("effect", "") == "merc:debt":
			c["reply"] = c["reply"] % GoblinData.DEBT_AMOUNT
	var uid: int = ge._next_uid
	ge._next_uid += 1
	profile["visit_uid"] = uid
	ge.visits.append({"uid": uid, "profile": profile, "day": game.session.day(), "present": true, "admitted": true,
		"ready": true, "read": false, "ready_at": -1.0, "status": "고용 중인 용병", "story": story,
		"merc_event": key, "merc_speaker": speaker.duplicate()})
	today_day = game.session.day()
	event_log.append({"day": today_day, "key": key, "person": speaker["person"]})
	game.sounds.play("story_ready")
	ge.changed.emit()


## 밤이 오면 듣지 않은 용병 이야기는 접는다(다음 새벽에 다시 나올 수 있다 — 끝낸 것만 done).
func _close_merc_visits() -> void:
	var ge = game.guest_events
	var any := false
	for v in ge.visits:
		if v.get("merc_event", "") != "" and v.present:
			v.present = false
			v.ready = false
			v.status = "밤 경계"
			any = true
	if any:
		ge.changed.emit()


func _process(_delta: float) -> void:
	if game == null or game.session == null or game.session.state != SessionScript.State.PREP or mala_given:
		return
	# 말라가 묵으러 들어오면(입실) 고블린 용병이 있을 때 '값을 매기는 눈'을 꺼낸다. 표본 추출을 건너뛰고 바로 말을 건다.
	for v in game.guest_events.visits:
		if not v.present or not v.admitted or v.read or v.get("mala_checked", false):
			continue
		if str(v.profile.get("character_id", "")) != "mala":
			continue
		v["mala_checked"] = true
		if goblin_roster().is_empty():
			continue
		v.story = MALA_STORY.duplicate(true)
		v.ready = true
		v["merc_event"] = "mala"
		game.sounds.play("story_ready")
		game.guest_events.changed.emit()


## guest_events.apply_effect() 가 "merc:" 효과를 넘긴다. 실패하면 false(fail_reply 대사).
func apply_effect(entry: Dictionary, effect: String) -> bool:
	var parts := effect.split(":")
	var key: String = entry.get("merc_event", "")
	var ok := true
	match parts[1]:
		"card":
			_give(parts[2], 1)
		"gold":
			game.economy._add_gold(int(parts[2]))
			game.toast("+%dG" % int(parts[2]), Color(1.0, 0.85, 0.45))
		"add":
			_give(parts[2], int(parts[3]))
		"mala":
			_give(parts[2], 1)
			mala_given = true
		"debt":
			ok = _sign_debt()
		"cousin":
			_accept_cousin()
		"race":
			ok = game.get("race_cards") != null and game.race_cards.event_effect(entry, parts[2], entry.get("merc_speaker", {}))
		_:
			ok = false
	if ok and key != "":
		done[key] = true
	return ok


func _give(id: String, n: int) -> void:
	var zone: String = game.cards.add(id, n)
	game.toast("'%s' %s받았습니다%s" % [game.cards.def(id).get("name", id), ("%d장 " % n) if n > 1 else "", " (주머니로)" if zone == "pocket" else ""], Color(0.8, 1.0, 0.6))


## 빚 문서: 지금 고를 수 있는 고블린 고용 손님 한 명의 계약 카드를 공짜로 받고, 3일 뒤 새벽에 갚는다.
func _sign_debt() -> bool:
	var used: Array = game.economy._persons_unavailable()
	for g in game.economy.guests:
		if is_instance_valid(g):
			used.append(g.profile.get("person", ""))
	for c in GuestProfiles.CATALOG:
		if c["race"] != GoblinData.RACE or not c["hireable"] or c["person"] in used:
			continue
		var job: String = GuestProfiles.job_of(c["person"])
		game.cards.add(job, 1, c["person"])
		game.goblin.add_debt(c["person"])
		game.toast("빚 문서에 서명했습니다 — %s(%s) 계약 카드 · %d일 뒤 새벽 %dG" % [c["person"], game.cards.def(job).get("name", job), GoblinData.DEBT_DAYS, GoblinData.DEBT_AMOUNT], Color(1.0, 0.85, 0.5))
		game.sounds.play("hire")
		return true
	return false


## 사촌의 사촌: 내일 첫 고용 손님을 고블린으로. 오늘 먹일 음식(스튜·생고기 하나), 없으면 골드.
func _accept_cousin() -> void:
	cousin_day = game.session.day() + 1
	for id in GoblinData.COUSIN_FOOD:
		if game.cards.consume_id(id, 1):
			game.toast("사촌의 사촌에게 '%s'을(를) 나눠 줬습니다 — 내일 고블린 손님이 옵니다" % game.cards.def(id).get("name", id), Color(0.85, 1.0, 0.6))
			return
	game.economy.spend(mini(GoblinData.COUSIN_NO_FOOD_GOLD, game.economy.gold))
	game.toast("먹일 게 없어 %dG로 대신했습니다 — 내일 고블린 손님이 옵니다" % GoblinData.COUSIN_NO_FOOD_GOLD, Color(0.85, 1.0, 0.6))
