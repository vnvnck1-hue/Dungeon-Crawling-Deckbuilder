extends Node
## 현재 방문과 대화 이벤트의 단일 기록. 입실 연출 후 말 걸기를 예약하고, 퇴실 시 미완료 알림을 정리한다.
const Dialogues := preload("res://scripts/game/guest_dialogues.gd")
const Arcs := preload("res://scripts/game/guest_story_arcs.gd")
const Situations := preload("res://scripts/game/guest_situations.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const ChapterData := preload("res://scripts/game/chapter_data.gd")
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")
const Cfg := preload("res://scripts/config.gd")
signal changed
signal admitted(profile: Dictionary)
var game
var visits: Array = []
var history: Array = []
var completed_stories: Dictionary = {}
## 손님 기억 장부(docs/pentiment-dialogue-research-v01.md §3.2): 선택의 remember 표시와 "heard:<id>"(그 손님 이야기를 들음). 판 동안 유지
var memory: Dictionary = {}
var story_parts: Dictionary = {}  # 손님 id → 마친 연작 편 수(guest_story_arcs.gd)
## 어젯밤 기록(guest_situations.gd): {night, lost(산장 체력 손실), max_hp, fallen[{person, race}], type(밤 종류)}. 새벽에 채운다
var night_log: Dictionary = {}
var _night_start: Dictionary = {}
var _next_uid := 1
var _story_candidates := 0  # 아직 이야기를 안 들은 입실 손님 수. GUEST_STORY_EVERY 명마다 한 번만 이벤트

func _ready() -> void:
	name = "GuestEvents"
	game.economy.batch_arrived.connect(_on_batch)
	game.economy.guest_departed.connect(_on_departed)
	game.session.state_changed.connect(_on_session_state)

func _on_batch(profiles: Array) -> void:
	for profile in profiles:
		profile["visit_uid"] = _next_uid
		visits.append({"uid": _next_uid, "profile": profile.duplicate(true), "day": game.session.day(),
			"present": true, "admitted": false, "ready": false, "read": false, "ready_at": -1.0,
			"status": "도착 중", "story": next_story(profile["character_id"])})
		_next_uid += 1
		if OS.get_cmdline_user_args().has("--guest-intros=off"): admit(profile)
	changed.emit()

func visit(uid: int) -> Dictionary:
	for entry in visits:
		if entry.uid == uid: return entry
	return {}

func admit(profile: Dictionary) -> void:
	var entry := visit(int(profile.get("visit_uid", -1)))
	if entry.is_empty() or entry.admitted or not entry.present: return
	entry.admitted = true
	# 상주 손님(첫 방문 에린)은 산장에 눌러앉고, 들어오자마자 말을 건다
	var resident: bool = entry.profile.get("resident", false)
	entry.status = "산장에 눌러앉음" if resident else "투숙 중"
	entry.ready_at = game.session.play_time + (0.0 if resident else 2.0)
	admitted.emit(profile)
	changed.emit()

func _process(_delta: float) -> void:
	if game.session.state != 0: return
	var updated := false
	for entry in visits:
		if entry.present and entry.admitted and not entry.ready and not entry.read and entry.ready_at <= game.session.play_time:
			if wolf_story_available(entry):
				# 늑대의 피(docs/wolf-blood-event-design.md §2): 한 판 한 번뿐인 특별 이야기는 표본 추출을 건너뛰고 항상 말을 건다
				entry.story = Dialogues.wolf_story()
				entry.ready = true
				game.sounds.play("story_ready")
			elif game.get("tavern") != null and game.tavern.erin_story_available(entry):
				# 술 주정뱅이 에린(docs/tavern-cards-v01.md): 술 카드를 채워 찾아온 에린은 표본 추출 없이 항상 말을 건다
				entry.story = Dialogues.erin_story()
				entry.ready = true
				game.sounds.play("story_ready")
			elif entry.profile.get("mead_gift", false):
				entry.read = true  # 꿀술 답례 손님은 선물만 두고 이야기는 하지 않는다(평소 이야기를 아껴 둔다)
			elif completed_stories.has(entry.profile.character_id):
				entry.read = true
			elif int(story_parts.get(entry.profile.character_id, 0)) > 0:
				# 연작 2편부터는 표본 추출 없이 늘 말을 건다(다시 찾아온 손님은 이어서 할 말이 있다)
				entry.ready = true
				game.sounds.play("story_ready")
			elif _story_candidates % Cfg.GUEST_STORY_EVERY != 0:
				_story_candidates += 1
				entry.read = true
			else:
				_story_candidates += 1
				entry.ready = true
				game.sounds.play("story_ready")
			updated = true
	if updated: changed.emit()

func _on_departed(profile: Dictionary, reason: String) -> void:
	var entry := visit(int(profile.get("visit_uid", -1)))
	if entry.is_empty() or not entry.present: return
	entry.present = false
	entry.ready = false
	entry.status = reason
	changed.emit()

func current_guests() -> Array:
	return visits.filter(func(entry): return entry.present)

func pending_events() -> Array:
	var out: Array = visits.filter(func(entry): return entry.present and entry.admitted and entry.ready and not entry.read)
	# 행상 브로크의 좌판 말풍선(상점 다시 열기)은 밤까지 남으므로, 손님 이야기 말풍선을 가리지 않게 맨 뒤에 둔다
	var shop: Array = out.filter(func(entry): return entry.profile.get("merchant", false))
	return out.filter(func(entry): return not entry.profile.get("merchant", false)) + shop

func can_talk(uid: int) -> bool:
	var entry := visit(uid)
	return not entry.is_empty() and entry.present and entry.admitted and game.session.state == 0

## 늑대의 피 이벤트 조건: 파르그(늑대 수인)가 묵는 중, 목장에 어른 검은 양이 있고, 이번 판에 아직 늑대의 피를 받지 않았을 때.
func wolf_story_available(entry: Dictionary) -> bool:
	if entry.is_empty() or str(entry.profile.get("character_id", "")) != "fargh": return false
	var moon = game.get("moon_powers")
	if moon == null or moon.blood_given: return false
	var pasture = game.world.pasture if game.get("world") != null else null
	return pasture != null and pasture.has_method("black_sheep_count") and pasture.black_sheep_count() > 0

## 선택지의 효과(지금은 "wolf_blood"뿐): 검은 양 한 마리를 내주고 늑대의 피 카드를 받는다. 실패(양이 없음)면 false.
func apply_effect(uid: int, effect: String) -> bool:
	var entry := visit(uid)
	# 용병 이벤트(고블린 카드 v1, scripts/game/merc_events.gd): "merc:..." 효과는 그 모듈이 처리한다
	if not entry.is_empty() and effect.begins_with("merc:") and game.get("merc_events") != null:
		var ok: bool = game.merc_events.apply_effect(entry, effect)
		if ok: changed.emit()
		return ok
	# 술 주정뱅이 에린(주점 카드 v1, scripts/game/tavern_cards.gd): "tavern:..." 효과는 그 모듈이 처리한다
	if not entry.is_empty() and effect.begins_with("tavern:") and game.get("tavern") != null:
		var done: bool = game.tavern.apply_effect(entry, effect)
		if done: changed.emit()
		return done
	if entry.is_empty() or effect != "wolf_blood": return false
	var moon = game.get("moon_powers")
	if moon == null or moon.blood_given: return false
	if not game.world.pasture.take_black_sheep(): return false
	moon.blood_given = true
	entry["wolf_accepted"] = true
	var zone: String = game.cards.add("wolf_blood", 1)
	game.toast("파르그에게 검은 양 한 마리를 내주고 '늑대의 피' 카드를 받았습니다%s" % (" (손패가 가득 차 주머니로)" if zone == "pocket" else ""), Color(0.9, 0.7, 0.8))
	game.sounds.play("mon_drop")
	changed.emit()
	return true

func complete(uid: int, choice: String, transcript: Array) -> bool:
	var entry := visit(uid)
	if entry.is_empty() or not entry.present or entry.get("completed_this_visit", false): return false
	entry.read = true
	entry.ready = false
	entry["completed_this_visit"] = true
	# 늑대의 피 이야기는 파르그의 평소 이야기를 소모하지 않는다. 거절했으면 다음 방문 때 다시 묻는다.
	# 용병 이벤트(special "merc")도 그 인물의 평소 손님 이야기를 소모하지 않는다
	if entry.story.get("special", "") == "":
		var id: String = entry.profile.character_id
		story_parts[id] = int(story_parts.get(id, 0)) + 1
		memory["heard:" + id] = true
		if story_parts[id] >= Arcs.part_count(id):
			completed_stories[id] = true
	# 상주 손님은 날이 지나도 같은 방문이므로 기록에는 대화한 날을 남긴다
	var resident: bool = entry.profile.get("resident", false)
	history.append({"uid": uid, "person": entry.profile.person, "day": game.session.day() if resident else entry.day, "title": entry.story.title,
		"choice": choice, "transcript": transcript.duplicate(true)})
	# 상주 손님(에린)은 판이 끝날 때까지 머물며 말을 걸 때마다 다른 잡담을 한다(prepare_talk)
	if resident:
		entry["completed_this_visit"] = false
	changed.emit()
	return true

## 대화를 열기 직전(guest_interactions.open_conversation): 첫 대화를 마친 에린이면 잡담 하나를 골라 둔다.
func prepare_talk(uid: int) -> void:
	var entry := visit(uid)
	var tavern = game.get("tavern")
	if entry.is_empty() or tavern == null or not tavern.is_erin(entry) or not tavern.erin_met: return
	# 첫 대화에서 카드를 받고 '대화 마치기' 전에 닫았어도, 다음부터는 잡담이다
	entry.read = true
	entry.ready = false
	entry.story = tavern.next_erin_chat()

## 이 손님이 다음에 꺼낼 이야기(연작의 다음 편). 연작을 다 마쳤으면 1편을 자리만 채워 둔다(completed_stories 가 막는다).
func next_story(id: String) -> Dictionary:
	var story := Arcs.part(id, int(story_parts.get(id, 0)), Dialogues.story(id))
	return story if not story.is_empty() else Dialogues.story(id)

func remember(flag: String) -> void:
	if flag != "": memory[flag] = true

## 박자·선택지 조건(guest_story_arcs.gd 머리말). 목록이면 모두 참이어야 한다. speaker_id 는 이야기하는 손님(끼어들기 대상에서 뺀다).
func cond_ok(cond, speaker_id := "") -> bool:
	if cond == null: return true
	if cond is Array:
		for c in cond:
			if not cond_ok(c, speaker_id): return false
		return true
	var text := str(cond)
	if text.begins_with("!"): return not cond_ok(text.substr(1), speaker_id)
	if text.begins_with("mem:"): return memory.has(text.substr(4))
	if text.begins_with("present:"): return not present_profile(text.substr(8), speaker_id).is_empty()
	if text.begins_with("day>="): return game.session.day() >= int(text.substr(5))
	if text.begins_with("day<="): return game.session.day() <= int(text.substr(5))
	match text:
		"merchant_day":
			return game.get("merchant") != null and game.merchant.visited_day == game.session.day()
		"black_sheep":
			var pasture = game.world.pasture if game.get("world") != null else null
			return pasture != null and pasture.has_method("black_sheep_count") and pasture.black_sheep_count() > 0
	return false

## 지금 산장에 들어와 있는 손님 id 의 프로필(이야기하는 손님 자신은 뺀다). 없으면 빈 사전.
func present_profile(id: String, exclude_id := "") -> Dictionary:
	if id == exclude_id: return {}
	for entry in visits:
		if entry.present and entry.admitted and str(entry.profile.get("character_id", "")) == id:
			return entry.profile
	return {}

## 다시 찾아온 손님의 첫인사: 기억 장부에 맞는 인사가 있으면 그 줄, 없으면 "".
func memory_greeting(id: String) -> String:
	for line in Arcs.all_greetings().get(id, []):
		if cond_ok(line.get("if")): return str(line["text"])
	return ""

## 밤이 시작될 때 산장 체력·무덤을 적어 두고, 새벽에 차이로 어젯밤 기록을 만든다(다른 모듈은 건드리지 않는다).
func _on_session_state(state: int) -> void:
	if state == SessionScript.State.COMBAT:
		_night_start = {"hp": _lodge_hp(), "graves": _grave_people(), "night": game.session.wave_index}
	elif state == SessionScript.State.PREP and not _night_start.is_empty():
		var left: Array = _night_start.graves.duplicate()
		var fallen: Array = []
		for person in _grave_people():
			if left.has(person):
				left.erase(person)
				continue
			var race := GuestProfiles.race_of(person)
			fallen.append({"person": person, "race": race if race != "" else "human"})
		var lodge = game.world.get("lodge") if game.get("world") != null else null
		night_log = {"night": int(_night_start.night), "lost": float(_night_start.hp) - _lodge_hp(),
			"max_hp": float(lodge.max_hp) if lodge != null else 300.0, "fallen": fallen,
			"type": str(ChapterData.day_cfg(int(_night_start.night)).get("night", "normal"))}
		_night_start = {}

func _lodge_hp() -> float:
	var lodge = game.world.get("lodge") if game.get("world") != null else null
	return float(lodge.hp) if lodge != null else 0.0

func _grave_people() -> Array:
	var yard = game.world.get("graveyard") if game.get("world") != null else null
	if yard == null: return []
	return yard.graves.map(func(g): return str(g.person))

## 어젯밤 기록이 바로 지난밤 것인지(낮 동안만 참).
func _fresh_night() -> bool:
	return game.session.state == SessionScript.State.PREP and int(night_log.get("night", -1)) == game.session.wave_index and game.session.wave_index >= 1

## 상황 하나가 지금 맞는지. race 는 말하는 손님의 종족.
func situation_holds(key: String, race: String) -> bool:
	var fresh := _fresh_night()
	var fallen: Array = night_log.get("fallen", [])
	match key:
		"fell_kin": return fresh and fallen.any(func(f): return f.race == race)
		"fell": return fresh and not fallen.is_empty()
		"night_hurt": return fresh and float(night_log.get("lost", 0.0)) >= float(night_log.get("max_hp", 300.0)) * 0.15
		"boss_down":
			var room = game.world.get("boss_room") if game.get("world") != null else null
			return room != null and room.combat != null and room.combat.dead
		"big_night": return fresh and str(night_log.get("type", "")) in ["big_raid", "siege", "seal_raid", "boss"]
		"fog_night": return fresh and str(night_log.get("type", "")) == "fog"
		"final_nights": return game.session.state == SessionScript.State.PREP and game.session.total_days() - game.session.wave_index <= 2
		"no_meat": return game.session.day() >= 3 and game.cards.count_of("raw_meat") == 0
		"night_calm": return fresh and float(night_log.get("lost", 0.0)) <= 0.0 and fallen.is_empty()
	return false

## 대화를 열 때 이야기 앞에 꺼낼 상황 박자(없으면 빈 목록). 꺼낸 상황은 기억해 같은 날(ONCE 는 판 전체) 다시 꺼내지 않는다.
func situation_beats(entry: Dictionary) -> Array:
	var id := str(entry.profile.get("character_id", ""))
	var race := str(entry.profile.get("race", "human"))
	for key in Situations.ORDER:
		var seen := ("sit:%s:%s" % [key, id]) if key in Situations.ONCE else ("sit:%s:%s:%d" % [key, id, game.session.day()])
		if memory.has(seen) or not situation_holds(key, race): continue
		var line := Situations.line(race, key, id)
		if line.is_empty(): continue
		memory[seen] = true
		if key == "fell_kin": memory["sit:fell:%s:%d" % [id, game.session.day()]] = true  # 같은 죽음을 두 번 말하지 않게
		var text := str(line.text)
		if "%s" in text:
			var fallen: Array = night_log.get("fallen", [])
			var kin: Array = fallen.filter(func(f): return f.race == race)
			text = text % str((kin if key == "fell_kin" and not kin.is_empty() else fallen)[0].person)
		var beats: Array = [{"who": "", "text": text, "situation": key}]
		if str(line.get("thought", "")) != "": beats.append({"who": "witch", "text": str(line.thought)})
		return beats
	return []
