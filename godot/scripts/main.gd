extends Node3D
## 진입점: 모듈을 만들고 연결한다. 우클릭 이동·평타 / A 공격 이동 / S 정지(롤식, lol_controls.gd) / 산장 클릭 → 관리 패널.
## 털이 자란 양 클릭 → 다가가 수확 / 고용을 기다리는 손님 클릭 → 고용. 카드 드래그는 HUD 손패가 처리한다.

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const WorldScript := preload("res://scripts/world/world.gd")
const PlayerScript := preload("res://scripts/actors/player.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const EconomyScript := preload("res://scripts/game/lodge_economy.gd")
const WaveScript := preload("res://scripts/game/wave_director.gd")
const DragonScript := preload("res://scripts/dragon/dragon_defense.gd")
const HudScript := preload("res://scripts/ui/hud.gd")
const ShotScript := preload("res://scripts/tools/screenshot_runner.gd")
const ScreenStyle := preload("res://scripts/visual/screen_style.gd")
const CameraStyle := preload("res://scripts/visual/camera_style.gd")
const WindowMode := preload("res://scripts/visual/window_mode.gd")
const CardsScript := preload("res://scripts/game/card_inventory.gd")
const ContractsScript := preload("res://scripts/game/contract_director.gd")
const ResolverScript := preload("res://scripts/game/card_use_resolver.gd")
const SoundBankScript := preload("res://scripts/audio/sound_bank.gd")
const GuestArrivalScript := preload("res://scripts/ui/guest_arrival.gd")
const LambBubbleScript := preload("res://scripts/ui/lamb_bubble.gd")
const GuestEventsScript := preload("res://scripts/game/guest_events.gd")
const GuestInteractionsScript := preload("res://scripts/ui/guest_interactions.gd")
const WildlifeScript := preload("res://scripts/game/wildlife_director.gd")
const RelicsScript := preload("res://scripts/game/relics.gd")
const EquipmentScript := preload("res://scripts/game/equipment.gd")
const CarryBubbleScript := preload("res://scripts/ui/carry_bubble.gd")
const ChestOpeningScript := preload("res://scripts/ui/chest_opening.gd")
const SpellbookScript := preload("res://scripts/ui/spellbook_picker.gd")
const MulliganScript := preload("res://scripts/ui/mulligan_screen.gd")
const ChapterScript := preload("res://scripts/game/chapter_director.gd")
const AltarScript := preload("res://scripts/world/altar.gd")
const AltarPanelScript := preload("res://scripts/ui/altar_panel.gd")
const OfferScreenScript := preload("res://scripts/ui/offer_screen.gd")
const Flow := preload("res://scripts/game/flow.gd")
const OpeningScript := preload("res://scripts/game/opening_director.gd")
const TutorialScript := preload("res://scripts/game/tutorial.gd")
const BannerScript := preload("res://scripts/ui/center_banner.gd")
const WorldSettingScript := preload("res://scripts/game/world_setting.gd")
const LolControlsScript := preload("res://scripts/game/lol_controls.gd")
const MoonPowersScript := preload("res://scripts/game/moon_powers.gd")
const GoblinCardsScript := preload("res://scripts/game/goblin_cards.gd")
const MercEventsScript := preload("res://scripts/game/merc_events.gd")
const KillGoldScript := preload("res://scripts/game/kill_gold.gd")
const ReputationScript := preload("res://scripts/game/reputation.gd")
const RaceCardsScript := preload("res://scripts/game/race_cards.gd")
const UndeadCardsScript := preload("res://scripts/game/undead_cards.gd")
const TavernCardsScript := preload("res://scripts/game/tavern_cards.gd")
const MerchantScript := preload("res://scripts/game/merchant.gd")
const LegendCardsScript := preload("res://scripts/game/legend_cards.gd")
const MercKitScript := preload("res://scripts/game/merc_kit.gd")
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")
const ReputationBarScript := preload("res://scripts/ui/reputation_bar.gd")

var world
var actors: Node3D
var player
var session
var economy
var waves
var dragon
var hud
var cards
var contracts
var resolver
var sheep_lost := 0
var sounds
var display        # 디스플레이 설정(화면 모드·창 크기·수직 동기화 등, scripts/visual/window_mode.gd)
var world_setting  # 판마다 바뀌는 월드 설정: 산장 가까운 주요 종족 둘(scripts/game/world_setting.gd)
var guest_arrival
var guest_events
var guest_ui
var wildlife
var relics
var equipment     # 장착 장비(마녀·용병의 무기·방어구·장신구, scripts/game/equipment.gd)
var chest_ui
var spellbook_ui
var mulligan_ui
var chapter        # 12일 챕터: 밤 규칙·제단·침식·새벽 보상·장날(볼륨 확장 E0~E3)
var altar
var altar_ui
var offer_ui
var banner         # 가운데 배너: 첫째 날 타이틀 카드·밤 진입
var tutorial       # 첫 판 고용 튜토리얼 + 단계형 목표
var controls       # 롤식 전투 조작(우클릭 이동·평타, A 공격 이동, S 정지, 적 외곽선)
var opening        # 도입 연출(프롤로그 → 새벽 → 첫째 날 → 시작 손패). 도입을 열지 않는 실행에서는 null
var moon_powers    # 늑대의 피·달 카드(초승달·상현달·보름달=늑대 변신) 기록(scripts/game/moon_powers.gd)
var goblin         # 고블린 카드 v1: 판정·사용·졸개·장비 효과·새벽 정리(scripts/game/goblin_cards.gd)
var merc_events    # 용병 이벤트(고블린): 새벽에 용병이 말을 걸어 카드를 준다(scripts/game/merc_events.gd)
var kill_gold      # 적 처치 골드: 동전이 흩뿌려지며 소량의 골드(scripts/game/kill_gold.gd)
var reputation     # 산장의 소문(평판): 제물로 어두워지고 정화로 밝아진다(scripts/game/reputation.gd)
var race_cards     # 종족·화합 카드 v1: 판정·사용·버프·시설·사건 효과(scripts/game/race_cards.gd)
var undead         # 언데드 카드 v1: 제물·시체·해골(scripts/game/undead_cards.gd)
var tavern         # 술 주정뱅이 에린·주점 카드 v1: 술 카드·에린 방문·꿀술 재방문(scripts/game/tavern_cards.gd)
var merchant       # 떠돌이 행상 브로크: 사흘마다 낮 한가운데 찾아와 카드 5장을 파는 상점(scripts/game/merchant.gd)
var merc_kit       # 용병 고유 키트 v04: 기세·고유 스킬·고유 카드·생성 카드·마력(scripts/game/merc_kit.gd)
var legend         # 전설 카드 5장 + 광석 v1: 왕관 변신·마법서 폭주·화로·종·광석(scripts/game/legend_cards.gd)


func _ready() -> void:
	preload("res://scripts/ui/moon/moon_skin.gd").install_web_font_fallback()
	sounds = _add_module(SoundBankScript)
	display = WindowMode.new()
	display.name = "WindowMode"
	add_child(display)
	var card_language := preload("res://scripts/ui/card_language.gd").new()   # F8 카드 언어 한국어 ↔ English
	card_language.name = "CardLanguage"
	add_child(card_language)
	var card_feel := preload("res://scripts/ui/card_feel.gd").new()   # F9 카드 질감 기존(일렁임) → 단단하게 → 아주 단단하게
	card_feel.name = "CardFeel"
	add_child(card_feel)
	var hand_time := preload("res://scripts/ui/hand_focus_time.gd").new()   # F12 손패 고민 시간: 손패에 손을 올리면 세상이 1초에 걸쳐 멈춘다(멈춤·거의 멈춤·끔)
	hand_time.name = "HandFocusTime"
	add_child(hand_time)
	var readability := preload("res://scripts/visual/character_readability.gd").new()   # F10 캐릭터 분리 시험 기존 → 림·외곽선 → +발밑 그림자 → +강조색
	readability.name = "CharacterReadability"
	add_child(readability)
	_configure_movement_input()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--style=") and arg.trim_prefix("--style=") in ScreenStyle.IDS:
			ScreenStyle.current_id = arg.trim_prefix("--style=")
		if arg.begins_with("--camera=") and arg.trim_prefix("--camera=") in CameraStyle.IDS:
			CameraStyle.current_id = arg.trim_prefix("--camera=")
	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	world.build(self)

	actors = Node3D.new()
	actors.name = "Actors"
	add_child(actors)

	player = PlayerScript.new()
	player.name = "Player"
	player.game = self
	player.position = Layout.PLAYER_START
	actors.add_child(player)
	player.visual.rotation.y = deg_to_rad(200.0)
	world.bind_player_camera(player)
	controls = LolControlsScript.new()
	controls.name = "LolControls"
	controls.game = self
	add_child(controls)

	cards = _add_module(CardsScript)
	contracts = _add_module(ContractsScript)
	resolver = _add_module(ResolverScript)
	relics = _add_module(RelicsScript)
	equipment = _add_module(EquipmentScript)
	wildlife = _add_module(WildlifeScript)
	contracts.bind_lodge()
	# 새 판마다 월드 설정을 굴린다(다시 도전도 장면을 다시 열므로 새로 굴린다).
	world_setting = WorldSettingScript.new()
	world_setting.roll_from_args(OS.get_cmdline_user_args())
	economy = _add_module(EconomyScript)
	waves = _add_module(WaveScript)
	dragon = _add_module(DragonScript)
	chapter = _add_module(ChapterScript)
	session = _add_module(SessionScript)
	altar = AltarScript.new()
	altar.game = self
	altar.position = chapter.altar_pos()
	actors.add_child(altar)
	moon_powers = _add_module(MoonPowersScript)
	guest_events = _add_module(GuestEventsScript)
	# 고블린 카드 v1·용병 이벤트·처치 골드(docs/goblin-cards-v01.md). 세션 낮밤 신호를 받으므로 session 다음에 붙인다
	goblin = _add_module(GoblinCardsScript)
	merc_events = _add_module(MercEventsScript)
	kill_gold = _add_module(KillGoldScript)
	# 종족·언데드·화합 카드 v1(docs/race-cards-v01.md). 세션 낮밤 신호를 받으므로 session 다음에 붙인다
	reputation = _add_module(ReputationScript)
	race_cards = _add_module(RaceCardsScript)
	undead = _add_module(UndeadCardsScript)
	# 술 주정뱅이 에린·주점 카드 v1(docs/tavern-cards-v01.md). 손님 입실 신호를 받으므로 guest_events 다음에 붙인다
	tavern = _add_module(TavernCardsScript)
	# 떠돌이 행상 브로크(docs/merchant-shop-v01.md). 세션 낮밤·손님 입실 신호를 받으므로 guest_events 다음에 붙인다
	merchant = _add_module(MerchantScript)
	# 전설 카드 5장 + 광석(docs/legend-cards-v01.md). 세션 낮밤·카드 사용 신호를 받으므로 session·cards 다음에 붙인다
	legend = _add_module(LegendCardsScript)
	# 용병 고유 키트 v04(docs/mercenary-unique-kit-v04.md). 세션 낮밤 신호를 받으므로 session·contracts 다음에 붙인다
	merc_kit = _add_module(MercKitScript)

	hud = _add_module(HudScript)
	hand_time.hand = hud.card_hand
	guest_arrival = _add_module(GuestArrivalScript)
	_add_module(LambBubbleScript)
	_add_module(CarryBubbleScript)
	chest_ui = _add_module(ChestOpeningScript)
	spellbook_ui = _add_module(SpellbookScript)
	mulligan_ui = _add_module(MulliganScript)
	altar_ui = _add_module(AltarPanelScript)
	offer_ui = _add_module(OfferScreenScript)
	_add_module(ReputationBarScript)
	guest_arrival.guest_admitted.connect(guest_events.admit)
	guest_ui = _add_module(GuestInteractionsScript)

	banner = _add_module(BannerScript)
	tutorial = _add_module(TutorialScript)
	if _opening_enabled():
		opening = _add_module(OpeningScript)
		opening.prepare(Flow.prologue and Flow.prologue_enabled and not "--skip-prologue" in OS.get_cmdline_user_args())

	# 낮·밤 시계를 먼저 연결해야 첫 낮(PREP) 신호를 받아 1일차도 새벽빛에서 시작한다
	world.bind_day_and_sight()
	session.start()
	world.hazard_regions.bind_residents()
	if opening != null:
		opening.begin()
	else:
		_grant_starter_cards()

	var shot := ShotScript.parse_args()
	if not shot.is_empty():
		var runner := ShotScript.new()
		runner.game = self
		runner.opts = shot
		add_child(runner)


## 게임 모듈 하나를 만들어 game 참조를 넘기고 main 아래에 붙인다(붙이는 순서가 _ready·_process 순서다).
func _add_module(script: GDScript) -> Node:
	var module = script.new()
	module.game = self
	add_child(module)
	return module


## 도입(프롤로그·새벽·첫째 날 카드)을 열지: 타이틀에서 들어왔거나 창을 띄운 일반 실행. --script 검증·스크린샷 실행이 main.tscn을 바로 열면 열지 않는다.
func _opening_enabled() -> bool:
	if Flow.take_opening():
		return true
	var user := OS.get_cmdline_user_args()
	if "--script" in OS.get_cmdline_args() or "--no-opening" in user or "--no-starter-cards" in user:
		return false
	return ShotScript.parse_args().is_empty()


## 첫 시작: 시작 카드(Cfg.STARTER_CARDS)를 모두 주머니에 넣고 무작위로 STARTER_DRAW장을 손패로 뽑는다(확정 규칙 2).
## 기존 검증 도구(--script 실행)는 빈 손패를 전제로 하므로 지급하지 않는다(검증 도구는 grant_starter_cards()를 직접 부른다).
func _grant_starter_cards() -> void:
	if "--script" in OS.get_cmdline_args() or "--no-starter-cards" in OS.get_cmdline_user_args():
		return
	grant_starter_cards()


## interactive=true: 시작 손패 고르기 화면(3장 공개 → 1장 교체 가능 → 손패로). false: 연출 없이 바로 3장 드로우(검증용).
func grant_starter_cards(interactive := true) -> void:
	for pair in Cfg.STARTER_CARDS:
		cards.add(pair[0], pair[1], "", "pocket")
	if interactive and mulligan_ui != null:
		mulligan_ui.open()
		return
	var got: Array = cards.draw(Cfg.STARTER_DRAW)
	if not got.is_empty():
		toast("마녀의 주머니에서 시작 손패 %d장을 뽑았습니다 — 나머지 %d장은 아침마다 한 장씩" % [got.size(), cards.pocket().size()], Color(1.0, 0.95, 0.8))


func toast(text: String, color := Color.WHITE) -> void:
	if hud != null:
		hud.toast(text, color)


func on_sheep_died() -> void:
	sheep_lost += 1
	toast("양 한 마리를 잃었습니다", Color(1.0, 0.65, 0.65))


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused or session.is_over() or player.dead:
		return
	if controls != null and controls.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		if key.keycode == KEY_H:
			player.set_destination(Layout.DOOR_FRONT)
			world.show_click_marker(Layout.DOOR_FRONT)
			get_viewport().set_input_as_handled()
		return
	var mb := event as InputEventMouseButton
	if mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		if hud.card_hand.drag_uid < 0:
			world.player_camera.zoom(-1.0 if mb.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0)
			get_viewport().set_input_as_handled()
		return
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if session.is_over() or player.dead:
		return
	var cam: Camera3D = world.camera
	var mp: Vector2 = mb.position
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0, Cfg.L_GROUND | Cfg.L_OBSTACLE)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if session.state == SessionScript.State.PREP:
		for o in economy.offers:
			var g = o["guest"]
			if is_instance_valid(g) and cam.unproject_position(g.global_position + Vector3(0, 0.8, 0)).distance_to(mp) < 44.0:
				if not economy.hire(o):
					toast("고용할 수 없습니다 — " + economy.hire_block_reason(o), Color(1.0, 0.7, 0.7))
				return
		var sheep = _ready_sheep_at(cam, mp)
		if sheep != null:
			player.harvest(sheep)
			world.show_click_marker(sheep.global_position)
			return
	if session.state == SessionScript.State.PREP and altar != null and altar.screen_hit(cam, mp):
		altar.request()
		return
	if not hit.is_empty() and hit["collider"] == world.lodge and session.state == SessionScript.State.PREP:
		hud.open_lodge_panel()
		return
	# 목재가 다 모인 감시탑 공터·탑을 클릭하면 건설하라고 관리창(시설)을 연다
	if session.state == SessionScript.State.PREP:
		var tower = resolver.tower_at(mp)
		if tower != null and tower.stock_full() and not tower.collapsed:
			hud.open_lodge_panel()
			return
	# 롤식 조작: 땅 좌클릭으로는 움직이지 않는다(이동은 우클릭, scripts/game/lol_controls.gd)


## 키보드 이동은 방향키만. A(공격 이동)·S(정지)가 롤 조작이라 WASD 이동은 쓰지 않는다(docs/lol-controls-v01.md).
func _configure_movement_input() -> void:
	var bindings := {"walk_left":[KEY_LEFT], "walk_right":[KEY_RIGHT],
		"walk_up":[KEY_UP], "walk_down":[KEY_DOWN]}
	for action in bindings:
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		for code in bindings[action]:
			var key := InputEventKey.new()
			key.physical_keycode = code
			InputMap.action_add_event(action,key)


func movement_input_allowed() -> bool:
	if session == null or session.is_over() or get_tree().paused: return false
	if hud == null: return true
	var hand = hud.card_hand
	if chest_ui != null and chest_ui.active: return false
	if (altar_ui != null and altar_ui.active) or (offer_ui != null and offer_ui.active): return false
	return not (hud.lodge_panel.visible or hud.pause_panel.visible or hud.end_panel.visible
		or hud.debug_panel.visible or hand.drag_uid >= 0 or hand.pocket_panel.visible or hand.sale_panel.visible
		or hud.camera_select.get_popup().visible or hud.style_select.get_popup().visible)


func _ready_sheep_at(cam: Camera3D, mp: Vector2):
	var best = null
	var best_d := 40.0
	for s in world.pasture.slots:
		if s == null or s.dead or not s.wool_ready:
			continue
		var d := cam.unproject_position(s.global_position + Vector3(0, 0.4, 0)).distance_to(mp)
		if d < best_d:
			best_d = d
			best = s
	return best


# ───────────────────────── 디버그 ─────────────────────────

func debug_gold() -> void:
	economy.debug_add_gold(100)
	toast("[디버그] +100G", Color(0.6, 1.0, 0.7))


func debug_start_wave() -> void:
	if session.state == SessionScript.State.PREP:
		session.start_wave()


## 용 소환 버튼이 없어져(2026-10-24) 시험용으로 [용비늘] 카드 1장을 준다. 밤 전투 중 산장에 끌어 놓으면 용이 온다.
func debug_dragon_scale() -> void:
	cards.add(Cfg.DRAGON_SCALE)
	toast("[디버그] 용비늘 카드 지급", Color(0.6, 1.0, 0.7))


func debug_damage_lodge() -> void:
	world.lodge.take_damage(50.0)


func debug_damage_player() -> void:
	player.take_damage(25.0)


func debug_kill_all() -> void:
	for e in get_tree().get_nodes_in_group("enemies"):
		e.take_damage(99999.0)


func debug_cards() -> void:
	for job in Cfg.JOB_CARDS:
		cards.add(job, 1, economy._pick_name())
	cards.add("forest_monster")
	cards.add("wool", 3)
	cards.add("timber", 10)
	cards.add("raw_meat", 2)
	cards.add("rabbit_pelt", 2)
	cards.add("treasure_chest", 1)
	cards.add("poison_mushroom", 2)
	cards.add("old_spellbook", 1)
	if wildlife != null:
		wildlife.spawn("rabbit", player.global_position + Vector3(4, 0, 2))
		wildlife.spawn("deer", player.global_position + Vector3(-5, 0, 3))
	for pair in Cfg.STARTER_CARDS:
		cards.add(pair[0], pair[1])
	toast("[디버그] 카드 지급", Color(0.6, 1.0, 0.7))


## 장착 장비 시험 카드 5종을 손패(가득 차면 주머니)에 넣는다. 카드 컨셉 확정 전의 시험 지급 경로.
func debug_equipment() -> void:
	for id in Cfg.EQUIPMENT:
		cards.add(id, 1)
	toast("[디버그] 장비 카드 지급", Color(0.6, 1.0, 0.7))


## 고블린 카드 v1 시험 지급: 고블린 계약 카드 2장(고블린 수 시너지·용병 이벤트용) + 고블린 카드 13종(장비 포함). 손패가 차면 주머니.
func debug_goblin() -> void:
	for pair in [["warrior", "그라즈"], ["gatherer", "타크"]]:
		if not pair[1] in cards.persons_in_use() + contracts.persons_active():
			cards.add(pair[0], 1, pair[1])
	for id in ["goblin_gang", "goblin_firecracker", "goblin_rush", "shiny_lure", "junk_barricade", "pikl_traps", "junk_sack",
			"graz_whistle", "pot_helmet", "mala_coin_scale", "mala_monocle", "dud_bomb"]:
		cards.add(id, 1)
	cards.add("timber", 2)
	toast("[디버그] 고블린 카드·고블린 용병 지급", Color(0.6, 1.0, 0.7))


## 종족 카드 v1 시험 지급: 드워프·오크·요정 계약 카드 + 종족·언데드·화합 카드(장비 포함). 손패가 차면 주머니.
func debug_race_cards() -> void:
	for pair in [["warrior", "하랄"], ["warrior", "가로크"], ["hunter", "틸리아"]]:
		if not pair[1] in cards.persons_in_use() + contracts.persons_active():
			cards.add(pair[0], 1, pair[1])
	for id in ["dark_ale", "stone_wall", "mine_prop", "stone_song", "war_drum", "feast_table", "victory_roar", "spit_roast",
			"village_militia", "pilgrim_blessing", "battle_ration", "crest_banner", "fae_swap", "guild_writ",
			"rune_hammer", "ancestor_shield", "thistle_oath", "ash_sigil", "pack_scent", "porter_pack",
			"dream_journal", "interpreter_pen", "ledger_of_dead", "sacrifice_dagger", "rise_up", "bone_hounds", "soul_jar"]:
		cards.add(id, 1)
	undead.give_corpse("이름 모를 나그네")
	undead.give_corpse("이름 모를 사냥꾼")
	cards.add("raw_meat", 3)
	toast("[디버그] 종족·언데드·화합 카드 지급", Color(0.6, 1.0, 0.7))


## 술 주정뱅이 에린·주점 카드 v1 시험 지급(docs/tavern-cards-v01.md): 에린(전설) + 술 4종 + 술주정 2장(서로 다른 그림)
## + 불꽃 에일을 먹일 전투 용병 계약 1장. 손패(8장)가 차면 주머니로 간다.
func debug_tavern_cards() -> void:
	for id in ["drunken_erin", "fire_ale", "golden_mead", "wisp_spirit", "dew_of_forgetting", "drunk_rant", "drunk_rant"]:
		cards.add(id, 1)
	for person in ["브람", "하랄", "가로크"]:
		if not person in cards.persons_in_use() + contracts.persons_active():
			cards.add("warrior", 1, person)
			break
	toast("[디버그] 에린·술 카드 지급 — 꿀술은 손님이 묵는 낮에, 불꽃 에일은 용병에게", Color(1.0, 0.82, 0.5))


## 전설 카드 5장 + 광석 시험 지급(docs/legend-cards-v01.md). 손패(8장)가 차면 주머니로 간다(시간대가 다른 카드도 주머니).
func debug_legend_cards() -> void:
	for id in ["frost_crown", "lich_crown", "wild_grimoire", "fire_brazier", "winter_bell"]:
		cards.add(id, 1)
	cards.add("ore", 3)
	toast("[디버그] 전설 5장·광석 3개 지급 — 왕관은 마녀에게, 마법서·종은 밤에", Color(1.0, 0.82, 0.5))


## 용병 고유 키트 v04 시험: 누를 때마다 다음 종족 4명(인간 → 드워프 → 요정 → 고블린 → 수인 → 오크)의 계약 카드를 손패에, 고유 카드를 주머니에 넣는다.
const DEBUG_KIT_RACES := [["인간", ["브람", "올라프", "토르빈", "미라"]], ["드워프", ["하랄", "브륀힐드", "토르그림", "두르가"]],
	["요정", ["티슬", "틸리아", "라르크", "페른"]], ["고블린", ["그라즈", "피클", "러스크", "타크"]],
	["수인", ["파르그", "사야", "우르소", "모미"]], ["오크", ["가로크", "크라냐", "모가", "샤가"]]]
var _debug_kit_i := 0

func debug_merc_kit() -> void:
	var pick: Array = DEBUG_KIT_RACES[_debug_kit_i % DEBUG_KIT_RACES.size()]
	_debug_kit_i += 1
	for p in pick[1]:
		cards.add(GuestProfiles.job_of(p), 1, p, "hand")
		merc_kit.on_hired(p)
	toast("[디버그] %s 4명 계약 카드 지급 — 낮에 배치하고 밤을 맞으면 기세·고유 스킬·생성 카드·마력 (다시 누르면 다음 종족)" % pick[0], Color(1.0, 0.82, 0.5))


## 에린 방문 시험: 첫 만남 전이면 조건을 채운 것으로 치고 낮이면 지금 바로(밤이면 내일 첫 무리 맨 앞) 부른다.
## 이미 첫 대화를 마쳤으면 술 ERIN_AT 잔을 채운 것으로 쳐 에린 카드가 바로 손패로 들어온다.
func debug_erin_visit() -> void:
	toast("[디버그] " + tavern.debug_call(), Color(1.0, 0.82, 0.5))


func debug_toggle_draw() -> void:
	world.debug_draw = not world.debug_draw
