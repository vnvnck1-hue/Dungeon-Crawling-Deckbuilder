extends "res://scripts/game/card_module.gd"
## 용병 고유 키트 v04 — 24명 전원 + 종족 시너지. docs/mercenary-unique-kit-v04.md(사용자 승인 2026-10-26).
## 용병 = 고유 카드(고용하면 주머니로, 1~2장) + 고유 패시브 + 고유 스킬(기세 100에서 자동). 효과는 모두 눈에 보이는 것 하나.
## 오토배틀 토대:
##  - 기세(0~100): 평타가 맞으면 +20, 피해를 받으면 받은 만큼(1회 최대 +15), 전투직은 싸우는 동안 초당 +3, 비전투직(나무꾼·채집가)은 밤에 초당 +5.
##    (2026-10-26 실전 흐름 검증: 첫날 밤 적 3마리로는 평타 +10 만으로 전투직 스킬이 거의 안 나와 올렸다)
##    100이면 고유 스킬을 쓴다. 쓸 대상이 없으면 100인 채 기다린다.
##  - 마력: 밤 전투 시작 3, 초당 0.5, 최대 10. 이 모듈의 카드만 마력을 쓴다(기존 카드는 그대로).
##  - 전투 중 드로우 없음: 밤 손패는 5장까지만 뽑고(card_inventory.phase_swap), 스택 드로우는 밤에 멈춘다(_count_use).
##    덱에서 더 뽑는 건 피클의 [셈 매듭]뿐.
##  - 생성 카드(gen_*): 용병이 만들어 손패에 넣는 카드. 이번 전투만 — 쓰면 사라지고 전투가 끝나면 손패에서 지운다.
##    손패가 가득하면 대기열(최대 3)에 있다가 자리가 나면 들어온다.
## 적 제어(기절·묶기·느리게·잠·도발·겁먹음)는 monster.apply_slow·attack_cd 와 이 모듈의 표(도발·은신·지대)로 흉내 낸다.
## "enemies" 그룹에는 서식지 맹독 곤충(venom_insect.gd)도 있어 덩치·감속·도발 속성이 없을 수 있다 — 속성은 e.get()으로 읽고, 없으면 피해만 준다.
## 시험 방향이라 --classic-cards 로 끈다(enabled = false 면 아무 훅도 동작하지 않는다). 수치는 모두 시험값이다.

const Fx := preload("res://scripts/visual/fx.gd")
const Cfg := preload("res://scripts/config.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const LureScript := preload("res://scripts/actors/goblin_lure.gd")

static var enabled := true

const MOMENTUM_MAX := 100.0
const HIT_MOMENTUM := 20.0
const FIGHT_MOMENTUM := 3.0       # 전투직: 적과 싸우는 동안(대상이 있을 때) 초당
const HURT_MOMENTUM_CAP := 15.0
const IDLE_MOMENTUM := 5.0        # 비전투직: 밤에 산장 안에서 초당
const MANA_START := 3.0
const MANA_REGEN := 0.5
const MANA_MAX := 10.0
const START_HAND := 5             # 밤 시작 손패(고블린 둘이면 +1, start_hand())
const GEN_QUEUE := 3
const REACH := 22.0               # 스킬이 적을 찾는 거리

# ── 인간 ──
const SHIELD_RADIUS := 4.0
const SHIELD_TIME := 4.0
const SHIELD_TAKEN := 0.5
const HORN_DAMAGE := 15.0
const HORN_RADIUS := 3.0
const HORN_DASH := 0.5
const FIRE_ARROWS := 3
const FIRE_DAMAGE := 12.0
const FIRE_CLUSTER := 3.0
const FIRE_REACH := 20.0
const MARK_TIME := 8.0
const MARK_TAKEN := 1.5
const LOG_DAMAGE := 15.0
const LOG_WIDTH := 1.5
const LOG_LENGTH := 16.0
const LOG_PUSH := 3.0
const HERB_HEAL := 30.0
const CAULDRON_HEAL := 20.0
# ── 드워프 ──
const HARALD_TAKEN := 0.7
const TAUNT_RADIUS := 5.0
const TAUNT_TIME := 5.0
const HOLD_TIME := 4.0
const HOLD_RADIUS := 3.0
const BOLT_DAMAGE := 35.0
const BOLT_WIDTH := 1.2
const BOLT_LENGTH := 20.0
const BOLT_GEN_HITS := 3
const SMALL_BOLT_DAMAGE := 20.0
const ALL_IN_PER_MANA := 10.0
const ALL_IN_MIN := 3
const WALL_HP_MULT := 1.5
const SALVE_HEAL := 20.0
const ROAR_TIME := 5.0
const ROAR_SPEED := 1.5           # 공격 속도 배율
const BITTER_HP := 15.0
# ── 요정 ──
const DUEL_TIME := 6.0
const DUEL_DAMAGE := 1.5
const HEDGE_TIME := 6.0
const HEDGE_RADIUS := 3.0
const HEDGE_SLOW := 0.5
const HEDGE_DPS := 5.0
const RAIN_RADIUS := 3.5
const RAIN_TOTAL := 30.0
const RAIN_TIME := 3.0
const DUST_RANGE := 6.0
const DUST_ANGLE := 0.75          # 부채꼴 반각(라디안)
const DUST_SLOW := 0.5
const DUST_TIME := 4.0
const ROOT_RADIUS := 3.0
const ROOT_TIME := 2.0
const PRUNE_DAMAGE := 40.0
const FLOWER_RADIUS := 2.5
const FLOWER_HPS := 1.5
const FLOWER_TIME := 10.0
const GARDEN_RADIUS := 4.0
const GARDEN_HPS := 3.0
const GARDEN_TIME := 10.0
const SLEEP_RADIUS := 3.0
const SLEEP_TIME := 3.0
# ── 고블린 ──
const BLUFF_COUNT := 3
const BLUFF_RADIUS := 5.0
const BLUFF_DAMAGE := 1.5
const POT_RADIUS := 6.0
const POT_TIME := 3.0
const BOMB_RADIUS := 2.5
const BOMB_DAMAGE := 25.0
const TALLY_EVERY := 3
const SNARE_ARROW_DAMAGE := 30.0
const SNARE_TIME := 3.0
const TRAP_TRIGGER := 0.9
const SAW_DPS := 5.0
const JUNK_SAW_MULT := 2.0
const SAW_WHEEL_DPS := 18.0
const SAW_WHEEL_TIME := 3
const SLIP_TIME := 1.0
const MARBLE_RADIUS := 3.0
const MARBLE_TIME := 2.0
const LURE_TIME := 4.0
# ── 수인 ──
const PACK_RADIUS := 6.0
const PACK_STEP := 0.1
const PACK_MAX := 0.5
const FEAR_RADIUS := 5.0
const FEAR_TIME := 2.0
const FEAR_PUSH := 3.0
const SCENT_RADIUS := 8.0
const SCENT_TIME := 6.0
const SCENT_SPEED := 1.5
const SHADOW_ARROW_DAMAGE := 25.0
const SNIPE_DAMAGE := 45.0
const AMBUSH_TIME := 5.0
const AMBUSH_MULT := 3.0
const HONEY_RADIUS := 3.0
const HONEY_SLOW := 0.4
const HONEY_TIME := 5.0
const THROW_RADIUS := 2.5
const THROW_DAMAGE := 30.0
const THROW_PUSH := 4.0
const HUG_TIME := 3.0
const STARTLE_RADIUS := 4.0
const STARTLE_COOLDOWN := 10.0
const HANDFUL_HEAL := 15.0
const RUN_TIME := 4.0
const RUN_SPEED := 1.6
const RUN_LOW_HP := 0.3
# ── 오크 ──
const OATH_RADIUS := 8.0
const OATH_MULT := 0.3
const GORE_DAMAGE := 25.0
const GORE_PUSH := 3.0
const GUARD_TIME := 8.0
const TROPHY_MANA := 3.0
const SPEAR_SKILL_DAMAGE := 70.0
const BONE_SPEAR_DAMAGE := 45.0
const VINE_RADIUS := 4.0
const VINE_TIME := 3.0
const WHIRL_RADIUS := 3.0
const WHIRL_DAMAGE := 25.0
const CHARM_DAMAGE := 20.0
const CHARM_STUN := 2.0
const ASH_RADIUS := 3.0
const ASH_TIME := 4.0
const ASH_OUT := 0.5
# ── 시너지 ──
const SYN_HUMAN_MANA := 2.0
const SYN_DWARF_WALL := 1.5
const SYN_DWARF_LODGE := 0.85
const SYN_FAIRY_SPEED := 1.3
const SYN_FAIRY_MOMENTUM := 1.3
const SYN_BEAST_HEAL := 3.0
const SYN_BEAST_HEAL_RADIUS := 6.0
const SYN_BEAST_DAMAGE := 1.4
const SYN_ORC_RAGE := 1.5
const SYN_ORC_RAGE_TIME := 10.0
const SYN_ORC_TAKEN := 0.7

## 인물(표시 이름) → 키트. race 는 시너지, cards 는 고용하면 주머니에 넣는 고유 카드와 장수.
const KITS := {
	"브람": {"id": "bram", "race": "human", "cards": {"merc_war_horn": 2}, "skill": "방패벽"},
	"올라프": {"id": "olaf", "race": "human", "cards": {"merc_hunt_mark": 1}, "skill": "불화살"},
	"토르빈": {"id": "torbin", "race": "human", "cards": {"merc_rolling_log": 1}, "skill": "말뚝 깎기"},
	"미라": {"id": "mira", "race": "human", "cards": {"merc_big_cauldron": 1}, "skill": "약초 달이기"},
	"하랄": {"id": "harald", "race": "dwarf", "cards": {"merc_hold_line": 1}, "skill": "철테 방패"},
	"브륀힐드": {"id": "brynhild", "race": "dwarf", "cards": {"merc_all_in": 1}, "skill": "대못 석궁"},
	"토르그림": {"id": "thorgrim", "race": "dwarf", "cards": {"merc_timber_wall": 2}, "skill": "쐐기 박기"},
	"두르가": {"id": "durga", "race": "dwarf", "cards": {"merc_bitter": 1}, "skill": "호통"},
	"티슬": {"id": "thistle", "race": "fairy", "cards": {"merc_thistle_hedge": 1}, "skill": "가시 창 결투"},
	"틸리아": {"id": "tilia", "race": "fairy", "cards": {"merc_moth_dust": 2}, "skill": "화살세례"},
	"라르크": {"id": "larch", "race": "fairy", "cards": {"merc_pruning": 1}, "skill": "뿌리 기르기"},
	"페른": {"id": "fern", "race": "fairy", "cards": {"merc_pollen": 1}, "skill": "씨앗 심기"},
	"그라즈": {"id": "graz", "race": "goblin", "cards": {"merc_junk_bomb": 2}, "skill": "냄비 투구 함성"},
	"피클": {"id": "pikl", "race": "goblin", "cards": {"merc_snare": 2}, "skill": "올가미 화살"},
	"러스크": {"id": "rusk", "race": "goblin", "cards": {"merc_saw_wheel": 1}, "skill": "급조 방책 만들기"},
	"타크": {"id": "tak", "race": "goblin", "cards": {"merc_lure": 1}, "skill": "주머니 뒤지기"},
	"파르그": {"id": "fargh", "race": "beastfolk", "cards": {"merc_blood_scent": 1}, "skill": "울부짖음"},
	"사야": {"id": "saya", "race": "beastfolk", "cards": {"merc_ambush": 1}, "skill": "그림자 사격"},
	"우르소": {"id": "urso", "race": "beastfolk", "cards": {"merc_bear_hug": 1}, "skill": "통나무 던지기"},
	"모미": {"id": "momi", "race": "beastfolk", "cards": {"merc_run": 1}, "skill": "약초 한 줌"},
	"가로크": {"id": "garok", "race": "orc", "cards": {"merc_oath_shield": 2}, "skill": "엄니 돌진"},
	"크라냐": {"id": "kranya", "race": "orc", "cards": {"merc_bone_spear": 1}, "skill": "투창"},
	"모가": {"id": "moga", "race": "orc", "cards": {"merc_axe_whirl": 1}, "skill": "덩굴 기도"},
	"샤가": {"id": "shaga", "race": "orc", "cards": {"merc_ash_blessing": 1}, "skill": "재 구름"},
}
## 전투가 시작되면 손패에 넣는 생성 카드(패시브).
const START_GEN := {
	"브람": ["gen_rally"], "토르빈": ["gen_log_wall", "gen_log_wall"], "미라": ["gen_herb_water", "gen_herb_water"],
	"라르크": ["gen_root", "gen_root"], "우르소": ["gen_honey", "gen_honey"], "샤가": ["gen_ash_charm"],
}
## 카드 → 주인(고유 카드). 주인이 산장에 없으면 쓸 수 없다. -1 마력 = 가진 마력 전부(최소 ALL_IN_MIN).
const OWNER := {
	"merc_war_horn": "브람", "merc_hunt_mark": "올라프", "merc_rolling_log": "토르빈", "merc_big_cauldron": "미라",
	"merc_hold_line": "하랄", "merc_all_in": "브륀힐드", "merc_timber_wall": "토르그림", "merc_bitter": "두르가",
	"merc_thistle_hedge": "티슬", "merc_moth_dust": "틸리아", "merc_pruning": "라르크", "merc_pollen": "페른",
	"merc_junk_bomb": "그라즈", "merc_snare": "피클", "merc_saw_wheel": "러스크", "merc_lure": "타크",
	"merc_blood_scent": "파르그", "merc_ambush": "사야", "merc_bear_hug": "우르소", "merc_run": "모미",
	"merc_oath_shield": "가로크", "merc_bone_spear": "크라냐", "merc_axe_whirl": "모가", "merc_ash_blessing": "샤가",
}
const COST := {
	"merc_war_horn": 2, "merc_hunt_mark": 0, "merc_rolling_log": 2, "merc_big_cauldron": 2,
	"merc_hold_line": 2, "merc_all_in": -1, "merc_timber_wall": 2, "merc_bitter": 0,
	"merc_thistle_hedge": 2, "merc_moth_dust": 1, "merc_pruning": 1, "merc_pollen": 1,
	"merc_junk_bomb": 1, "merc_snare": 0, "merc_saw_wheel": 2, "merc_lure": 1,
	"merc_blood_scent": 1, "merc_ambush": 1, "merc_bear_hug": 2, "merc_run": 1,
	"merc_oath_shield": 1, "merc_bone_spear": 2, "merc_axe_whirl": 2, "merc_ash_blessing": 1,
}
const GENERATED_IDS := ["gen_rally", "gen_log_wall", "gen_herb_water", "gen_bolt", "gen_salve", "gen_root", "gen_junk_wall",
	"gen_marble", "gen_shadow_arrow", "gen_honey", "gen_herb_handful", "gen_trophy", "gen_forgive", "gen_ash_charm"]
const CARD_IDS := ["merc_war_horn", "merc_hunt_mark", "merc_rolling_log", "merc_big_cauldron",
	"merc_hold_line", "merc_all_in", "merc_timber_wall", "merc_bitter",
	"merc_thistle_hedge", "merc_moth_dust", "merc_pruning", "merc_pollen",
	"merc_junk_bomb", "merc_snare", "merc_saw_wheel", "merc_lure",
	"merc_blood_scent", "merc_ambush", "merc_bear_hug", "merc_run",
	"merc_oath_shield", "merc_bone_spear", "merc_axe_whirl", "merc_ash_blessing",
	"gen_rally", "gen_log_wall", "gen_herb_water", "gen_bolt", "gen_salve", "gen_root", "gen_junk_wall",
	"gen_marble", "gen_shadow_arrow", "gen_honey", "gen_herb_handful", "gen_trophy", "gen_forgive", "gen_ash_charm"]
## 벽·방책으로 치는 카드 시설(토르그림·드워프 둘 체력, 러스크 톱날).
const WALL_KINDS := ["log_wall", "timber_wall", "junk_wall", "stone_wall", "bone_barricade"]

var mana := 0.0
var momentum: Dictionary = {}     # ally instance id → 기세
var _clock := 0.0
var _queue: Array = []            # 손패가 가득해 기다리는 생성 카드 [id, person]
var _mark = null                  # 사냥 표식이 붙은 적
var _mark_until := 0.0
var _shield: Dictionary = {}      # ally id → 방패벽 끝 시각
var _buffs: Dictionary = {}       # ally id → {"atk"|"speed"|"dmg": [배율, 끝 시각]}
var _taunt: Dictionary = {}       # enemy id → [ally, 끝 시각]
var _sleep: Dictionary = {}       # enemy id → 끝 시각(맞으면 깸)
var _stealth: Dictionary = {}     # ally id → 끝 시각(첫 공격 3배)
var _guard: Dictionary = {}       # ally id → [대신 맞는 가로크, 끝 시각]
var _ward: Dictionary = {}        # ally id → true(재의 축복 1회)
var _salved: Dictionary = {}      # ally id → true(두르가 [고약] 전투당 1번)
var _zones: Array = []            # {kind, pos, r, until, next}
var oath = null                   # 가로크의 맹세 동료
var _momi_cd := 0.0
var _tally := 0                   # 피클 셈 매듭(이번 전투 카드 사용 수)
var _first_card_done := false     # 인간 둘: 전투마다 처음 쓰는 카드 마력 -1
var _saw_t := 0.0
var _thistle_t := 0.0
var casts_by: Dictionary = {}    # 인물 → 이번 판 고유 스킬 시전 수(검증·밸런스)
var stats := {"casts": 0, "generated": 0, "queued": 0, "dropped": 0, "mana_spent": 0, "marks_returned": 0, "tally_draws": 0}


func _ready() -> void:
	name = "MercKit"
	if "--classic-cards" in OS.get_cmdline_user_args():
		enabled = false
	if game.get("session") != null and game.session != null:
		game.session.state_changed.connect(_on_state)
	if game.get("cards") != null and game.cards != null:
		game.cards.card_used.connect(_on_card_used)


func handles(id: String) -> bool:
	return enabled and id in CARD_IDS


static func is_generated_id(id: String) -> bool:
	return id.begins_with("gen_")


# ───────────────────────── 낮밤 ─────────────────────────

func _on_state(state) -> void:
	if not enabled:
		return
	if state == SessionScript.State.COMBAT:
		start_battle()
	elif state == SessionScript.State.CLEARING or state == SessionScript.State.PREP:
		end_battle()


## 전투 시작: 마력·기세를 처음으로, 맹세 동료, 패시브(전투 시작 생성 카드).
func start_battle() -> void:
	_reset()
	mana = MANA_START + (SYN_HUMAN_MANA if race_count("human") >= 3 else 0.0)
	_pick_oath()
	for a in kit_mercs():
		for id in START_GEN.get(a.person, []):
			generate(id, a.person)


## 전투 끝: 생성 카드를 지우고 대기열·표·지대를 비운다.
func end_battle() -> void:
	_reset()
	purge_generated()


func _reset() -> void:
	_queue.clear()
	_shield.clear()
	_buffs.clear()
	_taunt.clear()
	_sleep.clear()
	_stealth.clear()
	_guard.clear()
	_ward.clear()
	_salved.clear()
	momentum.clear()
	for z in _zones:
		_free_zone(z)
	_zones.clear()
	_mark = null
	_tally = 0
	_first_card_done = false
	_momi_cd = 0.0


func purge_generated() -> int:
	var n := 0
	for e in game.cards.entries.duplicate():
		if e.get("generated", false):
			game.cards.entries.erase(e)
			n += 1
	if n > 0:
		game.cards.changed.emit()
	return n


## 밤 시작 손패 장수(card_inventory.phase_swap). 고블린 둘이면 +1.
func start_hand() -> int:
	return START_HAND + (1 if race_count("goblin") >= 2 else 0)


# ───────────────────────── 매 프레임 ─────────────────────────

func _process(delta: float) -> void:
	if not enabled or game.session == null:
		return
	_clock += delta
	if game.session.state != SessionScript.State.COMBAT:
		return
	mana = minf(mana + MANA_REGEN * delta, MANA_MAX)
	tick(delta)


## 기세 충전(비전투직)·스킬 시전·대기열·표식·지대·상시 패시브. 검증에서 직접 부른다(delta 만큼 시계도 간다).
func tick(delta: float) -> void:
	if not is_processing():
		_clock += delta
	for a in kit_mercs():
		if a.is_noncombat_job():
			add_momentum(a, IDLE_MOMENTUM * delta)
		elif not a.hidden and not _near(a.global_position, 10.0).is_empty():
			add_momentum(a, FIGHT_MOMENTUM * delta)
		if momentum_of(a) >= MOMENTUM_MAX and cast_skill(a):
			momentum[a.get_instance_id()] = 0.0
			stats["casts"] += 1
	_flush_queue()
	_tick_mark()
	_tick_zones(delta)
	_tick_saw(delta)
	_tick_momi(delta)
	_tick_thistle(delta)


func _tick_mark() -> void:
	if _mark == null:
		return
	if not is_instance_valid(_mark):
		_mark = null
	elif _mark.dead:
		# 숲지기의 눈: 표식한 적이 쓰러지면 [사냥 표식]이 돌아온다
		_mark = null
		if alive_merc("올라프") != null:
			generate("merc_hunt_mark", "올라프")
			stats["marks_returned"] += 1
	elif _clock > _mark_until:
		_mark = null


## 러스크 톱날 셋: 아군 벽·방책에 붙은 적이 초당 피해(급조 방책은 2배). 1초마다 한 번에 준다.
func _tick_saw(delta: float) -> void:
	if alive_merc("러스크") == null:
		return
	_saw_t += delta
	if _saw_t < 1.0:
		return
	var secs := floorf(_saw_t)
	_saw_t -= secs
	for f in walls():
		var reach: float = float(f.foe_radius) + 0.9
		for e in _enemies():
			if _flat(e.global_position, f.global_position) <= reach:
				e.take_damage(SAW_DPS * secs * (JUNK_SAW_MULT if f.kind == "junk_wall" else 1.0))


## 모미 깜짝 놀람: 적이 4m 안에 오면 [약초 한 줌](10초에 한 번).
func _tick_momi(delta: float) -> void:
	_momi_cd = maxf(_momi_cd - delta, 0.0)
	var momi = alive_merc("모미")
	if momi == null or _momi_cd > 0.0:
		return
	for e in _enemies():
		if _flat(e.global_position, momi.global_position) <= STARTLE_RADIUS:
			_momi_cd = STARTLE_COOLDOWN
			Fx.float_text(momi.get_parent(), momi.global_position + Vector3(0, 2.2, 0), "깜짝!", Color(1.0, 0.9, 0.9))
			generate("gen_herb_handful", "모미")
			return


## 티슬 결투 예법: 늘 체력이 가장 높은 적을 먼저 노린다.
func _tick_thistle(delta: float) -> void:
	_thistle_t -= delta
	if _thistle_t > 0.0:
		return
	_thistle_t = 0.5
	var t = alive_merc("티슬")
	if t == null:
		return
	var s = strongest(t.global_position)
	if s != null:
		t.priority = s


# ───────────────────────── 용병·적 조회 ─────────────────────────

## 키트가 있는 살아 있는 용병(산장 안 비전투직 포함).
func kit_mercs() -> Array:
	if game.get("contracts") == null:
		return []
	return game.contracts.allies.filter(func(a): return is_instance_valid(a) and not a.dead and a.kind == "merc" and KITS.has(a.person))


func all_mercs() -> Array:
	if game.get("contracts") == null:
		return []
	return game.contracts.allies.filter(func(a): return is_instance_valid(a) and not a.dead and a.kind == "merc")


func alive_merc(person: String):
	for a in kit_mercs():
		if a.person == person:
			return a
	return null


func race_of(a) -> String:
	return str(KITS[a.person]["race"]) if KITS.has(a.person) else ""


## 살아 있는 그 종족 키트 용병 수(시너지).
func race_count(race: String) -> int:
	var n := 0
	for a in kit_mercs():
		if race_of(a) == race:
			n += 1
	return n


func walls() -> Array:
	return game.get_tree().get_nodes_in_group("allies").filter(func(f): return f.get("kind") in WALL_KINDS and not f.dead)


func _enemies() -> Array:
	return game.get_tree().get_nodes_in_group("enemies").filter(func(e): return not e.dead)


func _near(from: Vector3, r: float) -> Array:
	return _enemies().filter(func(e): return _flat(e.global_position, from) <= r)


## 주변 FIRE_CLUSTER 안에 적이 가장 많은 적(사거리 안). 없으면 null.
func densest(from: Vector3, reach := REACH):
	var pool := _near(from, reach)
	var best = null
	var best_n := -1
	for e in pool:
		var n := 0
		for o in pool:
			if _flat(o.global_position, e.global_position) <= FIRE_CLUSTER:
				n += 1
		if n > best_n:
			best_n = n
			best = e
	return best


## 사거리 안에서 체력이 가장 높은 적.
func strongest(from: Vector3, reach := REACH):
	var best = null
	for e in _near(from, reach):
		if best == null or e.hp > best.hp:
			best = e
	return best


## 사거리 안에서 가장 큰 적(덩치 큰 적·보스 우선, 없으면 최대 체력이 가장 큰 적).
func biggest(from: Vector3, reach := REACH):
	var best = null
	for e in _near(from, reach):
		if best == null:
			best = e
			continue
		var eb: bool = e.get("big") == true or e.get("is_boss") == true
		var bb: bool = best.get("big") == true or best.get("is_boss") == true
		if (eb and not bb) or (eb == bb and e.max_hp > best.max_hp):
			best = e
	return best


func farthest(from: Vector3, reach := REACH):
	var best = null
	var best_d := -1.0
	for e in _near(from, reach):
		var d := _flat(e.global_position, from)
		if d > best_d:
			best_d = d
			best = e
	return best


func nearest(from: Vector3, reach := REACH):
	var best = null
	var best_d := INF
	for e in _near(from, reach):
		var d := _flat(e.global_position, from)
		if d < best_d:
			best_d = d
			best = e
	return best


## 체력 비율이 가장 낮은 다친 용병(없으면 null).
func most_hurt():
	var best = null
	var best_f := 1.0
	for a in all_mercs():
		var f: float = a.hp / a.max_hp
		if f < best_f:
			best_f = f
			best = a
	return best


# ───────────────────────── 기세 ─────────────────────────

func momentum_of(a) -> float:
	return float(momentum.get(a.get_instance_id(), 0.0))


func add_momentum(a, amount: float) -> void:
	if not enabled or not KITS.has(a.person):
		return
	var m := amount
	if a.person == "틸리아":
		m *= 2.0   # 나방 날개
	if race_of(a) == "fairy" and race_count("fairy") >= 3:
		m *= SYN_FAIRY_MOMENTUM
	momentum[a.get_instance_id()] = minf(momentum_of(a) + m, MOMENTUM_MAX)


func _fill(a) -> void:
	momentum[a.get_instance_id()] = MOMENTUM_MAX


# ───────────────────────── 훅(ally·monster·facility·lodge 가 부른다) ─────────────────────────

## ally.on_hit: 평타가 적에게 맞음. 쓰러뜨렸으면 처치 패시브.
func on_ally_hit(a, e) -> void:
	if not enabled or not _night():
		return
	add_momentum(a, HIT_MOMENTUM)
	_stealth.erase(a.get_instance_id())   # 매복은 첫 공격 한 번
	if e != null and is_instance_valid(e) and e.dead:
		on_kill(a, e)


## 아군 용병이 적을 쓰러뜨림(평타). 사야 밤눈: 가장 먼 적이면 [그림자 화살].
func on_kill(a, e) -> void:
	if a.person == "사야":
		var far = farthest(a.global_position)
		if far == null or _flat(e.global_position, a.global_position) >= _flat(far.global_position, a.global_position):
			generate("gen_shadow_arrow", "사야")


## monster.die: 적이 쓰러짐(누가 쓰러뜨렸든).
func on_enemy_died(e) -> void:
	if not enabled or not _night():
		return
	var p: Vector3 = e.global_position
	if alive_merc("페른") != null:
		_add_zone("flower", p, FLOWER_RADIUS, FLOWER_TIME)   # 씨앗 주머니
	if (e.get("big") == true or e.get("is_boss") == true) and alive_merc("크라냐") != null:
		generate("gen_trophy", "크라냐")   # 전리품
	if race_count("beastfolk") >= 2:
		for a in all_mercs():
			if _flat(a.global_position, p) <= SYN_BEAST_HEAL_RADIUS:
				_heal(a, SYN_BEAST_HEAL, false)


## ally.take_damage 앞머리: 맹세의 방패가 걸려 있으면 가로크가 대신 맞는다. 반환: 대신 맞은 가로크(없으면 null).
func guard_of(a):
	if not enabled:
		return null
	var g = _guard.get(a.get_instance_id())
	if g == null:
		return null
	var by = g[0]
	if _clock > float(g[1]) or not is_instance_valid(by) or by.dead or by == a or by.hp < by.max_hp * 0.2:
		_guard.erase(a.get_instance_id())
		return null
	return by


## ally.take_damage 가 곱하는 받는 피해 배율.
func taken_mult(a) -> float:
	if not enabled:
		return 1.0
	var m := 1.0
	if float(_shield.get(a.get_instance_id(), -1.0)) > _clock:
		m *= SHIELD_TAKEN
	if a.person == "하랄":
		m *= HARALD_TAKEN
	if a.person == "가로크" and _near_oath(a):
		m *= 1.0 - OATH_MULT
	if a.person == "우르소" and _buff_on(a, "hug"):
		m *= 0.7
	if race_of(a) == "orc" and race_count("orc") >= 3 and a.hp < a.max_hp * 0.5:
		m *= SYN_ORC_TAKEN
	return m


## ally.take_damage: 실제로 받은 피해(배율 적용 뒤, 체력을 깎기 전).
func on_ally_hurt(a, amount: float) -> void:
	if not enabled or not _night():
		return
	add_momentum(a, minf(amount, HURT_MOMENTUM_CAP))
	# 두르가 잔소리 약: 절반 아래로 떨어지는 순간 [고약](용병마다 전투당 한 번)
	var half: float = a.max_hp * 0.5
	if a.hp > half and a.hp - amount <= half and alive_merc("두르가") != null and not _salved.has(a.get_instance_id()):
		_salved[a.get_instance_id()] = true
		generate("gen_salve", "두르가")


## ally.take_damage: 쓰러질 피해를 받음. 재의 축복이면 체력 1로 버티고 true.
func try_save(a) -> bool:
	if not enabled or not _ward.has(a.get_instance_id()):
		return false
	_ward.erase(a.get_instance_id())
	Fx.burst(a.get_parent(), a.global_position + Vector3(0, 1.0, 0), Color(0.6, 0.58, 0.55), 18, 3.0)
	for e in _near(a.global_position, 3.0):
		stun(e, 1.0)
	Fx.float_text(a.get_parent(), a.global_position + Vector3(0, 2.4, 0), "재의 축복", Color(0.85, 0.82, 0.78))
	return true


## ally._damage_mult 가 곱하는 피해 배율.
func damage_mult(a) -> float:
	if not enabled or not _night():
		return 1.0
	var m := _buff(a, "dmg")
	if _stealth.has(a.get_instance_id()) and float(_stealth[a.get_instance_id()]) > _clock:
		m *= AMBUSH_MULT
	match a.person:
		"그라즈":
			if _near(a.global_position, BLUFF_RADIUS).size() >= BLUFF_COUNT:
				m *= BLUFF_DAMAGE
		"파르그":
			var n := 0
			for o in all_mercs():
				if o != a and _flat(o.global_position, a.global_position) <= PACK_RADIUS:
					n += 1
			m *= 1.0 + minf(n * PACK_STEP, PACK_MAX)
		"티슬":
			if a.get("target") != null and a.target == strongest(a.global_position):
				m *= DUEL_DAMAGE
		"가로크":
			if _near_oath(a):
				m *= 1.0 + OATH_MULT
	if race_of(a) == "beastfolk" and race_count("beastfolk") >= 3 and a.hp < a.max_hp * 0.5:
		m *= SYN_BEAST_DAMAGE
	return m


## ally._interval_mult 가 곱하는 공격 간격 배율(작을수록 빠르다).
func interval_mult(a) -> float:
	return 1.0 / _buff(a, "atk") if enabled else 1.0


## ally 이동 속도 배율.
func speed_mult(a) -> float:
	if not enabled:
		return 1.0
	return _buff(a, "speed") * (SYN_FAIRY_SPEED if race_count("fairy") >= 2 and _night() else 1.0)


## monster.take_damage 가 곱하는 받는 피해 배율(사냥 표식). 잠든 적은 맞으면 깬다.
func enemy_taken_mult(e) -> float:
	if not enabled:
		return 1.0
	if _sleep.has(e.get_instance_id()):
		_sleep.erase(e.get_instance_id())
		if e.get("_slows") != null:
			e._slows.erase("merc_sleep")
		if e.get("attack_cd") != null:
			e.attack_cd = minf(float(e.attack_cd), 0.3)
	return MARK_TAKEN if _mark == e and _clock <= _mark_until else 1.0


## monster 가 공격을 넣을 때 곱하는 피해 배율(재 구름 안이면 절반). 타크를 때리면 때린 적이 미끄러진다.
func enemy_out_mult(e, target) -> float:
	if not enabled:
		return 1.0
	if target != null and target.get("person") == "타크" and not target.get("dead"):
		stun(e, SLIP_TIME)
		Fx.float_text(e.get_parent(), e.global_position + Vector3(0, 1.8, 0), "미끌", Color(0.85, 0.9, 1.0))
	for z in _zones:
		if z["kind"] == "ash" and _flat(e.global_position, z["pos"]) <= float(z["r"]):
			return ASH_OUT
	return 1.0


## monster._pick_foe: 도발이 걸려 있으면 그 용병만 노린다.
func taunt_of(e):
	if not enabled:
		return null
	var t = _taunt.get(e.get_instance_id())
	if t == null:
		return null
	if _clock > float(t[1]) or not is_instance_valid(t[0]) or t[0].dead:
		_taunt.erase(e.get_instance_id())
		return null
	return t[0]


## monster._foe_valid: 은신 중인 용병은 노리지 않는다.
func stealthed(a) -> bool:
	return enabled and float(_stealth.get(a.get_instance_id(), -1.0)) > _clock and _buff_on(a, "hide")


## lodge.take_damage 가 곱하는 배율(드워프 셋).
func lodge_taken_mult() -> float:
	return SYN_DWARF_LODGE if enabled and race_count("dwarf") >= 3 else 1.0


## card_facility.setup 이 곱하는 벽·방책 최대 체력 배율(토르그림·드워프 둘).
func facility_hp_mult(kind: String) -> float:
	if not enabled or not kind in WALL_KINDS:
		return 1.0
	var m := 1.0
	if alive_merc("토르그림") != null:
		m *= WALL_HP_MULT
	if race_count("dwarf") >= 2:
		m *= SYN_DWARF_WALL
	return m


## card_facility.collapse: 벽이 부서짐. 모가 사과의 의식: [나무의 용서].
func on_facility_broken(f) -> void:
	if enabled and _night() and f.get("kind") in WALL_KINDS and alive_merc("모가") != null:
		generate("gen_forgive", "모가")


## 카드 사용(card_inventory.card_used): 피클 셈 매듭 — 밤에 3장 쓸 때마다 덱에서 1장.
func _on_card_used(_id: String) -> void:
	if not enabled or not _night() or alive_merc("피클") == null:
		return
	_tally += 1
	if _tally % TALLY_EVERY == 0 and not game.cards.hand_full():
		var got: Array = game.cards.draw(1)
		if not got.is_empty():
			stats["tally_draws"] += 1
			game.toast("피클의 셈 매듭 — '%s'" % game.cards.def(got[0]["id"]).get("name", ""), Color(1.0, 0.92, 0.6))


func shielded(a) -> bool:
	return taken_mult(a) < 1.0 and float(_shield.get(a.get_instance_id(), -1.0)) > _clock


func marked():
	return _mark


# ───────────────────────── 버프·적 제어 공용 ─────────────────────────

func _set_buff(a, key: String, mult: float, time: float) -> void:
	var b: Dictionary = _buffs.get(a.get_instance_id(), {})
	b[key] = [mult, _clock + time]
	_buffs[a.get_instance_id()] = b


func _buff(a, key: String) -> float:
	var b = _buffs.get(a.get_instance_id())
	if b == null or not b.has(key) or float(b[key][1]) < _clock:
		return 1.0
	return float(b[key][0])


func _buff_on(a, key: String) -> bool:
	var b = _buffs.get(a.get_instance_id())
	return b != null and b.has(key) and float(b[key][1]) >= _clock


## 기절: 움직이지도 공격하지도 못한다.
func stun(e, time: float) -> void:
	if e == null or not is_instance_valid(e) or e.dead or not e.has_method("apply_slow"):
		return
	e.apply_slow("merc_stun", 0.0, time)
	if e.get("attack_cd") != null:
		e.attack_cd = maxf(float(e.attack_cd), time)


## 묶기: 움직이지 못한다(공격은 한다).
func root(e, time: float) -> void:
	if e != null and is_instance_valid(e) and not e.dead and e.has_method("apply_slow"):
		e.apply_slow("merc_root", 0.0, time)


func slow(e, factor: float, time: float, key := "merc_slow") -> void:
	if e != null and is_instance_valid(e) and not e.dead and e.has_method("apply_slow"):
		e.apply_slow(key, factor, time)


func taunt(e, to, time: float) -> void:
	if e == null or e.dead or e.get("ignore_units") == true or not ("chase" in e):
		return
	_taunt[e.get_instance_id()] = [to, _clock + time]
	e.chase = to


func push(e, dir: Vector3, dist: float) -> void:
	if e == null or not is_instance_valid(e) or e.dead:
		return
	var d := Vector3(dir.x, 0, dir.z)
	if d.length() < 0.01:
		return
	e.global_position += d.normalized() * dist


func hurt(e, amount: float, color := Color(1.0, 0.75, 0.4)) -> void:
	if e == null or not is_instance_valid(e) or e.dead:
		return
	Fx.hit(e.global_position + Vector3(0, 0.8, 0), color, amount >= 30.0)
	e.take_damage(amount)


func _heal(a, amount: float, show := true) -> void:
	if a.hp >= a.max_hp:
		return
	a.hp = minf(a.hp + amount, a.max_hp)
	if show:
		Fx.heal(a.global_position + Vector3(0, 1.0, 0))
		Fx.float_text(a.get_parent(), a.global_position + Vector3(0, 2.2, 0), "+%d" % int(amount), Color(0.6, 1.0, 0.6))


func _near_oath(a) -> bool:
	return oath != null and is_instance_valid(oath) and not oath.dead and _flat(a.global_position, oath.global_position) <= OATH_RADIUS


## 가로크의 맹세 동료: 전투가 시작될 때 체력 비율이 가장 낮은 다른 용병(맹세의 방패를 쓰면 그 동료로 바뀐다).
func _pick_oath() -> void:
	oath = null
	var g = alive_merc("가로크")
	if g == null:
		return
	var best_f := INF
	for a in all_mercs():
		if a == g:
			continue
		var f: float = a.hp / a.max_hp
		if f < best_f:
			best_f = f
			oath = a


# ───────────────────────── 지대(가시덤불·꽃·재 구름·덫) ─────────────────────────

func _add_zone(kind: String, p: Vector3, r: float, time: float) -> Dictionary:
	var z := {"kind": kind, "pos": Vector3(p.x, 0, p.z), "r": r, "until": _clock + time, "next": _clock + 1.0}
	z["node"] = _zone_visual(kind, z["pos"], r)
	_zones.append(z)
	return z


func zones_of(kind: String) -> Array:
	return _zones.filter(func(z): return z["kind"] == kind)


func _tick_zones(_delta: float) -> void:
	for z in _zones.duplicate():
		if _clock > float(z["until"]):
			_free_zone(z)
			_zones.erase(z)
			continue
		var p: Vector3 = z["pos"]
		var r: float = z["r"]
		match z["kind"]:
			"trap":
				for e in _near(p, TRAP_TRIGGER):
					root(e, SNARE_TIME)
					Fx.float_text(e.get_parent(), e.global_position + Vector3(0, 1.8, 0), "올가미", Color(1.0, 0.9, 0.6))
					_free_zone(z)
					_zones.erase(z)
					break
			"hedge":
				for e in _near(p, r):
					slow(e, HEDGE_SLOW, 0.4, "merc_hedge")
		if _clock < float(z["next"]):
			continue
		z["next"] = float(z["next"]) + 1.0
		match z["kind"]:
			"hedge":
				for e in _near(p, r):
					e.take_damage(HEDGE_DPS)
			"flower", "garden":
				var hps: float = FLOWER_HPS if z["kind"] == "flower" else GARDEN_HPS
				for a in all_mercs():
					if _flat(a.global_position, p) <= r:
						_heal(a, hps, false)


func _free_zone(z: Dictionary) -> void:
	var n = z.get("node")
	if n != null and is_instance_valid(n):
		n.queue_free()


func _zone_visual(kind: String, p: Vector3, r: float) -> Node3D:
	if game.get("actors") == null or game.actors == null:
		return null
	var col := Color(0.4, 0.75, 0.35, 0.35)
	match kind:
		"flower", "garden":
			col = Color(0.95, 0.7, 0.85, 0.35)
		"ash":
			col = Color(0.45, 0.42, 0.4, 0.55)
		"trap":
			col = Color(0.75, 0.6, 0.3, 0.9)
			r = 0.35
	var disc := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = r
	m.bottom_radius = r
	m.height = 0.05 if kind != "ash" else 1.6
	disc.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material_override = mat
	game.actors.add_child(disc)
	disc.global_position = p + Vector3(0, 0.05 if kind != "ash" else 0.8, 0)
	return disc


# ───────────────────────── 고유 스킬(기세 100) ─────────────────────────

## 반환: 썼는가. 쓸 대상이 없으면 기세 100인 채 기다린다.
func cast_skill(a) -> bool:
	var at: Vector3 = a.global_position
	match a.person:
		"브람":   # 방패벽: 4초간 주변 4m 아군 받는 피해 절반
			for m in all_mercs():
				if _flat(m.global_position, at) <= SHIELD_RADIUS:
					_shield[m.get_instance_id()] = _clock + SHIELD_TIME
					Fx.burst(m.get_parent(), m.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.85, 0.35), 10, 2.0)
		"올라프":   # 불화살: 적이 가장 많은 곳에 3발(각 12)
			var hits := fire_targets(at)
			if hits.is_empty():
				return false
			for e in hits:
				hurt(e, FIRE_DAMAGE, Color(1.0, 0.55, 0.2))
		"토르빈":
			generate("gen_log_wall", a.person)
		"미라":
			var t = most_hurt()
			if t == null:
				return false
			_heal(t, HERB_HEAL)
		"하랄":   # 철테 방패: 주변 적이 5초간 하랄만
			var foes := _near(at, TAUNT_RADIUS)
			if foes.is_empty():
				return false
			for e in foes:
				taunt(e, a, TAUNT_TIME)
		"브륀힐드":   # 대못 석궁: 적이 가장 많이 겹치는 줄 관통 35, 3마리 이상이면 [대못]
			var line := best_line(at)
			if line.is_empty():
				return false
			for e in line:
				hurt(e, BOLT_DAMAGE)
			if line.size() >= BOLT_GEN_HITS:
				generate("gen_bolt", a.person)
		"토르그림":   # 쐐기 박기: 가장 부서진 벽을 가득
			var worst = null
			for f in walls():
				if f.hp < f.max_hp and (worst == null or f.hp / f.max_hp < worst.hp / worst.max_hp):
					worst = f
			if worst == null:
				generate("gen_log_wall", a.person)   # 고칠 벽이 없으면 통나무 벽을 깎아 둔다
			else:
				worst.repair(worst.max_hp)
		"두르가":   # 호통: 모든 아군 5초간 공격 속도 +50%
			for m in all_mercs():
				_set_buff(m, "atk", ROAR_SPEED, ROAR_TIME)
		"티슬":   # 가시 창 결투: 가장 강한 적과 6초 1:1
			var s = strongest(at)
			if s == null:
				return false
			taunt(s, a, DUEL_TIME)
			a.priority = s
		"틸리아":   # 화살세례: 3초간 화살비, 적마다 총 30
			var c = densest(at)
			if c == null:
				return false
			arrow_rain(c.global_position)
		"라르크":
			generate("gen_root", a.person)
		"페른":   # 씨앗 심기: 다친 아군 자리에 회복 꽃밭
			var h = most_hurt()
			if h == null:
				return false
			_add_zone("garden", h.global_position, GARDEN_RADIUS, GARDEN_TIME)
		"그라즈":   # 냄비 투구 함성: 주변 적이 3초간 그라즈만
			var foes := _near(at, POT_RADIUS)
			if foes.is_empty():
				return false
			for e in foes:
				taunt(e, a, POT_TIME)
		"피클":   # 올가미 화살: 가장 강한 적 3초 묶고 30
			var s = strongest(at)
			if s == null:
				return false
			root(s, SNARE_TIME)
			hurt(s, SNARE_ARROW_DAMAGE)
		"러스크":
			generate("gen_junk_wall", a.person)
			generate("gen_junk_wall", a.person)
		"타크":
			generate("gen_marble", a.person)
			generate("gen_marble", a.person)
		"파르그":   # 울부짖음: 주변 적 2초 겁먹고 달아남
			var foes := _near(at, FEAR_RADIUS)
			if foes.is_empty():
				return false
			for e in foes:
				fear(e, at)
		"사야":   # 그림자 사격: 가장 먼 적 45(매복 중이면 3배)
			var f = farthest(at)
			if f == null:
				return false
			var dmg := SNIPE_DAMAGE * (AMBUSH_MULT if _stealth.has(a.get_instance_id()) else 1.0)
			_stealth.erase(a.get_instance_id())
			hurt(f, dmg, Color(0.6, 0.5, 0.9))
			if f.dead:
				on_kill(a, f)
		"우르소":   # 통나무 던지기: 가까운 적 떼 30 + 날려 보냄
			var n = nearest(at)
			if n == null:
				return false
			var p: Vector3 = n.global_position
			for e in _near(p, THROW_RADIUS):
				hurt(e, THROW_DAMAGE)
				push(e, e.global_position - at, THROW_PUSH)
		"모미":
			generate("gen_herb_handful", a.person)
			generate("gen_herb_handful", a.person)
		"가로크":   # 엄니 돌진: 맹세 동료를 노리는 적에게
			var guard_at: Vector3 = oath.global_position if _near_oath_valid() else at
			var n = nearest(guard_at)
			if n == null:
				return false
			_dash(a, n.global_position, 0.35)
			hurt(n, GORE_DAMAGE)
			push(n, n.global_position - guard_at, GORE_PUSH)
		"크라냐":   # 투창: 가장 큰 적 70
			var b = biggest(at)
			if b == null:
				return false
			hurt(b, SPEAR_SKILL_DAMAGE)
		"모가":   # 덩굴 기도: 적이 가장 많은 곳 3초 묶음
			var c = densest(at)
			if c == null:
				return false
			for e in _near(c.global_position, VINE_RADIUS):
				root(e, VINE_TIME)
			Fx.burst(game.actors, c.global_position + Vector3(0, 0.3, 0), Color(0.35, 0.7, 0.3), 16, 3.0)
		"샤가":   # 재 구름: 안의 적 공격이 절반
			var c = densest(at)
			if c == null:
				return false
			_add_zone("ash", c.global_position, ASH_RADIUS, ASH_TIME)
		_:
			return false
	_announce(a, str(KITS[a.person]["skill"]))
	casts_by[a.person] = int(casts_by.get(a.person, 0)) + 1
	return true


func _near_oath_valid() -> bool:
	return oath != null and is_instance_valid(oath) and not oath.dead


func _announce(a, skill: String) -> void:
	Fx.float_text(a.get_parent(), a.global_position + Vector3(0, 2.6, 0), skill + "!", Color(1.0, 0.85, 0.4))
	game.sounds.play_or("card_play", "card_play")


## 불화살 대상: 몰린 곳 중심에 가까운 적부터 3마리(적이 적으면 같은 적에게 여러 발).
func fire_targets(from: Vector3) -> Array:
	var center = densest(from, FIRE_REACH)
	if center == null:
		return []
	var near := _near(from, FIRE_REACH)
	near.sort_custom(func(x, y): return _flat(x.global_position, center.global_position) < _flat(y.global_position, center.global_position))
	var out: Array = []
	for i in FIRE_ARROWS:
		out.append(near[i % near.size()])
	return out


## 관통 볼트가 가장 많이 맞히는 줄(사거리 안 적 방향 후보 중). 맞는 적 목록.
func best_line(from: Vector3) -> Array:
	var best: Array = []
	for e in _near(from, BOLT_LENGTH):
		var hits := line_hits(from, e.global_position - from, BOLT_LENGTH, BOLT_WIDTH)
		if hits.size() > best.size():
			best = hits
	return best


func line_hits(from: Vector3, dir: Vector3, length: float, width: float) -> Array:
	var d := Vector3(dir.x, 0, dir.z)
	if d.length() < 0.01:
		return []
	d = d.normalized()
	var out: Array = []
	for e in _enemies():
		var rel := Vector3(e.global_position.x - from.x, 0, e.global_position.z - from.z)
		var along := rel.dot(d)
		if along >= 0.0 and along <= length and (rel - d * along).length() <= width:
			out.append(e)
	return out


func arrow_rain(p: Vector3) -> void:
	var per := RAIN_TOTAL / RAIN_TIME
	for i in int(RAIN_TIME):
		var t: SceneTreeTimer = game.get_tree().create_timer(float(i))
		t.timeout.connect(func():
			Fx.burst(game.actors, p + Vector3(0, 1.5, 0), Color(0.9, 0.85, 0.6), 10, 3.0)
			for e in _near(p, RAIN_RADIUS):
				e.take_damage(per))


func fear(e, from: Vector3) -> void:
	push(e, e.global_position - from, FEAR_PUSH)
	stun(e, FEAR_TIME)
	Fx.float_text(e.get_parent(), e.global_position + Vector3(0, 1.8, 0), "겁먹음", Color(1.0, 0.8, 0.8))


func _dash(a, p: Vector3, time: float) -> void:
	var tw: Tween = a.create_tween()
	tw.tween_property(a, "global_position", Vector3(p.x, a.global_position.y, p.z), time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


# ───────────────────────── 생성 카드 ─────────────────────────

## 용병이 카드를 만들어 손패에 넣는다. 손패가 가득하면 대기열(최대 3), 그것도 차면 버린다. 반환: 손패에 들어간 uid(-1 = 대기·버림).
func generate(id: String, person: String) -> int:
	if game.cards.hand_full():
		if _queue.size() < GEN_QUEUE:
			_queue.append([id, person])
			stats["queued"] += 1
		else:
			stats["dropped"] += 1
		return -1
	return _put_in_hand(id, person)


func _put_in_hand(id: String, person: String) -> int:
	game.cards.add(id, 1, person, "hand")
	var e: Dictionary = game.cards.entries.back()
	e["generated"] = true
	stats["generated"] += 1
	game.toast("%s — '%s'" % [person, game.cards.def(id).get("name", id)], Color(1.0, 0.88, 0.55))
	game.cards.changed.emit()
	return int(e["uid"])


func _flush_queue() -> void:
	while not _queue.is_empty() and not game.cards.hand_full():
		var q: Array = _queue.pop_front()
		_put_in_hand(q[0], q[1])


func queue_size() -> int:
	return _queue.size()


# ───────────────────────── 고용·이별 ─────────────────────────

## 고용(lodge_economy.hire): 고유 카드를 주머니에 넣는다(밤 카드).
func on_hired(person: String) -> void:
	if not enabled or not KITS.has(person):
		return
	var cards: Dictionary = KITS[person]["cards"]
	for id in cards:
		for i in int(cards[id]):
			game.cards.add(id, 1, person, "pocket")
	game.toast("%s의 고유 카드 %d장이 주머니에 들어갔습니다" % [person, _sum(cards)], Color(1.0, 0.85, 0.5))


## 용병이 산장을 떠남(쓰러짐·해고): 그 사람의 고유 카드를 손패·주머니·버림패에서 뺀다.
## 오크 둘: 오크가 쓰러지면 다른 오크가 10초간 피해 +50%, 기세 100.
func on_merc_gone(a) -> void:
	if not enabled or not KITS.has(a.person):
		return
	var person: String = a.person
	if a.dead and race_of(a) == "orc" and _night():
		var orcs: Array = kit_mercs().filter(func(o): return o != a and race_of(o) == "orc")
		if orcs.size() >= 1:
			for o in orcs:
				_set_buff(o, "dmg", SYN_ORC_RAGE, SYN_ORC_RAGE_TIME)
				_fill(o)
	var ids: Dictionary = KITS[person]["cards"]
	var cards = game.cards
	for e in cards.entries.duplicate():
		if ids.has(e["id"]) and e.get("person", "") == person:
			cards.entries.erase(e)
	cards.discard = cards.discard.filter(func(e): return not (ids.has(e["id"]) and e.get("person", "") == person))
	cards.changed.emit()


func _sum(d: Dictionary) -> int:
	var n := 0
	for k in d:
		n += int(d[k])
	return n


# ───────────────────────── 카드 판정 ─────────────────────────

## 지금 낼 마력(인간 둘: 전투 첫 카드 -1, 고블린 셋: 고블린 고유 카드 -1). -1 = 가진 마력 전부.
func cost_of(id: String) -> int:
	var c := int(COST.get(id, 0))
	if c < 0:
		return maxi(int(floor(mana)), ALL_IN_MIN)
	if OWNER.has(id) and race_count("goblin") >= 3 and str(KITS[OWNER[id]]["race"]) == "goblin":
		c -= 1
	if not _first_card_done and race_count("human") >= 2:
		c -= 1
	return maxi(c, 0)


func evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var plan := _evaluate(entry, sp, r)
	if plan.get("ok", false):
		plan["action"] = "merc"
		plan["merc_card"] = entry["id"]
	return plan


func _evaluate(entry: Dictionary, sp: Vector2, r) -> Dictionary:
	var id: String = entry["id"]
	if not _night():
		return _fail("밤 전투 중에만 쓸 수 있습니다")
	var cost := cost_of(id)
	if mana < cost:
		return _fail("마력이 모자랍니다 (%d / %d)" % [int(floor(mana)), cost])
	if OWNER.has(id) and alive_merc(OWNER[id]) == null:
		return _fail("%s이(가) 산장에 없습니다" % OWNER[id])
	var cl := "마력 %d" % cost
	var title: String = game.cards.def(id).get("name", id)
	match id:
		# 지점
		"merc_war_horn", "merc_rolling_log", "merc_hold_line", "merc_all_in", "merc_timber_wall", "merc_thistle_hedge", "merc_moth_dust", \
		"merc_pollen", "merc_junk_bomb", "merc_snare", "merc_saw_wheel", "merc_lure", "merc_axe_whirl", \
		"gen_log_wall", "gen_bolt", "gen_root", "gen_junk_wall", "gen_marble", "gen_honey", "gen_forgive":
			var p = _point(sp, r)
			if p is String:
				return _fail(p)
			return {"ok": true, "pos": p, "title": title, "lines": [_line(id), cl]}
		# 적 하나
		"merc_hunt_mark", "merc_pruning", "merc_bear_hug", "merc_bone_spear", "gen_shadow_arrow", "gen_ash_charm":
			var e = r.enemy_at(sp)
			if e == null:
				return _fail("적 위에 놓으세요")
			return {"ok": true, "pos": e.global_position, "enemy": e, "title": title, "lines": [_line(id), cl]}
		# 아군 하나
		"merc_bitter", "merc_oath_shield", "merc_ash_blessing", "gen_rally", "gen_herb_water", "gen_salve", "gen_herb_handful":
			var a = r.merc_target(sp)
			if a == null:
				return _fail("용병(또는 초상)에 놓으세요")
			if (id == "gen_rally" or id == "merc_bitter") and not KITS.has(a.person):
				return _fail("고유 스킬이 있는 용병에 놓으세요")
			if id == "merc_oath_shield" and a.person == "가로크":
				return _fail("가로크가 지킬 다른 동료에 놓으세요")
			return {"ok": true, "pos": a.global_position, "ally": a, "title": title + " — " + a.person, "lines": [_line(id), cl]}
		# 즉시
		"merc_big_cauldron", "merc_blood_scent", "merc_ambush", "merc_run", "gen_trophy":
			if id == "merc_big_cauldron" and most_hurt() == null:
				return _fail("다친 용병이 없습니다")
			return {"ok": true, "pos": _anywhere(), "title": title, "lines": [_line(id), cl]}
	return _fail("알 수 없는 카드")


## 미리보기 첫 줄: 카탈로그 인쇄 문구 두 줄을 한 줄로.
func _line(id: String) -> String:
	return " ".join(PackedStringArray(game.cards.def(id).get("printed_rules", [])))


func commit(uid: int, plan: Dictionary, _r) -> Dictionary:
	var id: String = plan["merc_card"]
	var cost := cost_of(id)
	if not game.cards.consume(uid):
		return _fail("카드가 없습니다")
	mana -= cost
	stats["mana_spent"] += cost
	_first_card_done = true
	apply_card(id, plan, cost)
	game.sounds.play_or("card_play", "card_play")
	return plan


## 카드 효과(검증에서 직접 부른다). spent 는 [전부 걸어!]에 쓴 마력.
func apply_card(id: String, plan: Dictionary, spent := 0) -> void:
	var p: Vector3 = plan.get("pos", Vector3.ZERO)
	var e = plan.get("enemy")
	var a = plan.get("ally")
	match id:
		"merc_war_horn":
			war_horn(p)
		"merc_hunt_mark":
			mark(e)
		"merc_rolling_log":
			rolling_log(p)
		"merc_big_cauldron":
			for m in all_mercs():
				_heal(m, CAULDRON_HEAL)
		"merc_hold_line":   # 하랄이 달려가 4초간 길을 막는다
			var h = alive_merc("하랄")
			_dash(h, p, 0.4)
			for x in _near(p, HOLD_RADIUS):
				root(x, HOLD_TIME)
				taunt(x, h, HOLD_TIME)
		"merc_all_in":
			var b = alive_merc("브륀힐드")
			var from: Vector3 = b.global_position
			for x in line_hits(from, p - from, BOLT_LENGTH, BOLT_WIDTH * 1.5):
				hurt(x, ALL_IN_PER_MANA * spent, Color(1.0, 0.9, 0.5))
		"merc_timber_wall":
			game.race_cards._build("timber_wall", p)
		"merc_bitter":
			a.hp = maxf(a.hp - BITTER_HP, 1.0)
			_rally(a)
		"merc_thistle_hedge":
			_add_zone("hedge", p, HEDGE_RADIUS, HEDGE_TIME)
		"merc_moth_dust":
			var t = alive_merc("틸리아")
			var f: Vector3 = Vector3(p.x - t.global_position.x, 0, p.z - t.global_position.z).normalized()
			for x in _near(t.global_position, DUST_RANGE):
				var to := Vector3(x.global_position.x - t.global_position.x, 0, x.global_position.z - t.global_position.z)
				if to.length() < 0.01 or f.angle_to(to) <= DUST_ANGLE:
					slow(x, DUST_SLOW, DUST_TIME, "merc_dust")
			Fx.burst(game.actors, t.global_position + f * 2.0 + Vector3(0, 1.0, 0), Color(0.9, 0.9, 0.6), 18, 3.0)
		"merc_pruning":
			hurt(e, PRUNE_DAMAGE)
		"merc_pollen":
			for x in _near(p, SLEEP_RADIUS):
				if not x.has_method("apply_slow"):
					continue
				x.apply_slow("merc_sleep", 0.0, SLEEP_TIME)
				x.attack_cd = maxf(float(x.attack_cd), SLEEP_TIME)
				_sleep[x.get_instance_id()] = _clock + SLEEP_TIME
				Fx.float_text(x.get_parent(), x.global_position + Vector3(0, 1.8, 0), "쿨쿨", Color(0.95, 0.85, 1.0))
		"merc_junk_bomb":
			Fx.explosion(game.actors, p, BOMB_RADIUS)
			for x in _near(p, BOMB_RADIUS):
				x.take_damage(BOMB_DAMAGE)
		"merc_snare":
			_add_zone("trap", p, TRAP_TRIGGER, 999.0)
		"merc_saw_wheel":
			saw_wheel(p)
		"merc_lure":
			var lure := LureScript.new()
			lure.game = game
			lure.position = p
			lure.time_left = LURE_TIME
			game.actors.add_child(lure)
		"merc_blood_scent":
			var fg = alive_merc("파르그")
			for m in all_mercs():
				if _flat(m.global_position, fg.global_position) <= SCENT_RADIUS:
					_set_buff(m, "atk", SCENT_SPEED, SCENT_TIME)
			Fx.burst(game.actors, fg.global_position + Vector3(0, 1.0, 0), Color(0.9, 0.25, 0.2), 18, 3.0)
		"merc_ambush":
			var s = alive_merc("사야")
			_stealth[s.get_instance_id()] = _clock + AMBUSH_TIME
			_set_buff(s, "hide", 1.0, AMBUSH_TIME)
			_fill_partial(s, 50.0)
		"merc_bear_hug":
			var u = alive_merc("우르소")
			_dash(u, e.global_position, 0.4)
			stun(e, HUG_TIME)
			_set_buff(u, "hug", 1.0, HUG_TIME)
		"merc_run":
			for m in all_mercs():
				_set_buff(m, "speed", RUN_SPEED, RUN_TIME)
				if m.hp < m.max_hp * RUN_LOW_HP:
					var back := Vector3(m.global_position.x, 0, m.global_position.z)
					_dash(m, m.global_position - back.normalized() * minf(4.0, back.length()), 0.6)
		"merc_oath_shield":
			_guard[a.get_instance_id()] = [alive_merc("가로크"), _clock + GUARD_TIME]
			oath = a
		"merc_bone_spear":
			hurt(e, BONE_SPEAR_DAMAGE)
		"merc_axe_whirl":
			_dash(alive_merc("모가"), p, 0.4)
			for x in _near(p, WHIRL_RADIUS):
				x.take_damage(WHIRL_DAMAGE)
			Fx.burst(game.actors, p + Vector3(0, 0.8, 0), Color(0.85, 0.85, 0.8), 18, 4.0)
		"merc_ash_blessing":
			_ward[a.get_instance_id()] = true
		"gen_rally":
			_rally(a)
		"gen_log_wall":
			game.race_cards._build("log_wall", p)
		"gen_herb_water":
			_heal(a, HERB_HEAL)
		"gen_bolt":
			var b = alive_merc("브륀힐드")
			var from: Vector3 = b.global_position if b != null else Vector3.ZERO
			for x in line_hits(from, p - from, BOLT_LENGTH, BOLT_WIDTH):
				hurt(x, SMALL_BOLT_DAMAGE)
		"gen_salve":
			_heal(a, SALVE_HEAL)
		"gen_root", "gen_forgive":
			for x in _near(p, ROOT_RADIUS):
				root(x, ROOT_TIME)
			Fx.burst(game.actors, p + Vector3(0, 0.3, 0), Color(0.35, 0.7, 0.3), 14, 3.0)
		"gen_junk_wall":
			game.race_cards._build("junk_wall", p)
		"gen_marble":
			for x in _near(p, MARBLE_RADIUS):
				stun(x, MARBLE_TIME)
			Fx.burst(game.actors, p + Vector3(0, 0.3, 0), Color(0.8, 0.9, 1.0), 16, 3.0)
		"gen_shadow_arrow":
			hurt(e, SHADOW_ARROW_DAMAGE, Color(0.6, 0.5, 0.9))
		"gen_honey":
			for x in _near(p, HONEY_RADIUS):
				slow(x, HONEY_SLOW, HONEY_TIME, "merc_honey")
			Fx.burst(game.actors, p + Vector3(0, 0.3, 0), Color(1.0, 0.75, 0.2), 14, 2.0)
		"gen_herb_handful":
			_heal(a, HANDFUL_HEAL)
			_set_buff(a, "speed", 1.3, 4.0)
		"gen_trophy":
			mana = minf(mana + TROPHY_MANA, MANA_MAX)
		"gen_ash_charm":
			hurt(e, CHARM_DAMAGE, Color(0.6, 0.58, 0.55))
			stun(e, CHARM_STUN)


func _fill_partial(a, amount: float) -> void:
	momentum[a.get_instance_id()] = minf(momentum_of(a) + amount, MOMENTUM_MAX)


## 호령·쓴 약: 기세를 채워 바로 고유 스킬.
func _rally(a) -> void:
	_fill(a)
	if cast_skill(a):
		momentum[a.get_instance_id()] = 0.0
		stats["casts"] += 1


# ───────────────────────── 카드 효과(긴 것) ─────────────────────────

## 진격 나팔: 싸울 수 있는 용병 전원이 지점으로 달려가고(브람이 앞), 도착하면 주변 적 피해.
func war_horn(p: Vector3) -> void:
	var runners: Array = all_mercs().filter(func(a): return not a.hidden and a.is_combat_job())
	var i := 0
	for a in runners:
		var off := Vector3.ZERO if a.person == "브람" else Vector3(cos(i * 1.7), 0, sin(i * 1.7)) * 1.4
		i += 1
		_dash(a, p + off, HORN_DASH)
	var t: SceneTreeTimer = game.get_tree().create_timer(HORN_DASH)
	t.timeout.connect(func(): _horn_impact(p))


func _horn_impact(p: Vector3) -> void:
	Fx.burst(game.actors, p + Vector3(0, 0.6, 0), Color(1.0, 0.85, 0.4), 18, 4.0)
	for e in _near(p, HORN_RADIUS):
		e.take_damage(HORN_DAMAGE)


## 사냥 표식: 8초간 모든 용병이 이 적을 먼저 치고, 이 적은 피해 1.5배.
func mark(e) -> void:
	_mark = e
	_mark_until = _clock + MARK_TIME
	for a in all_mercs():
		if a.is_combat_job():
			a.priority = e
	Fx.float_text(e.get_parent(), e.global_position + Vector3(0, 2.4, 0), "표식", Color(1.0, 0.4, 0.35))


## 굴러가는 통나무: 산장(원점)에서 지점 방향으로 16m. 길 위 적 피해 15, 진행 방향으로 3m 밀림.
func rolling_log(p: Vector3) -> Array:
	var dir := Vector3(p.x, 0, p.z)
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var start := dir * 3.0
	var hit := line_hits(start, dir, LOG_LENGTH, LOG_WIDTH)
	for e in hit:
		e.take_damage(LOG_DAMAGE)
		push(e, dir, LOG_PUSH)
	_roll_visual(start, dir, Color(0.45, 0.3, 0.18), 0.35)
	return hit


## 톱날 바퀴: 산장에서 지점 방향 줄 위의 적이 3초 동안 초당 18.
func saw_wheel(p: Vector3) -> void:
	var dir := Vector3(p.x, 0, p.z)
	if dir.length() < 0.1:
		dir = Vector3.FORWARD
	dir = dir.normalized()
	var start := dir * 3.0
	_roll_visual(start, dir, Color(0.7, 0.7, 0.72), 0.45)
	for i in SAW_WHEEL_TIME:
		var t: SceneTreeTimer = game.get_tree().create_timer(float(i) + 0.05)
		t.timeout.connect(func():
			for e in line_hits(start, dir, LOG_LENGTH, LOG_WIDTH):
				e.take_damage(SAW_WHEEL_DPS))


func _roll_visual(start: Vector3, dir: Vector3, col: Color, radius: float) -> void:
	if game.get("actors") == null or game.actors == null:
		return
	var roller := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 2.4 if radius < 0.4 else 0.25
	roller.mesh = m
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	roller.material_override = mat
	game.actors.add_child(roller)
	roller.global_position = start + Vector3(0, radius, 0)
	roller.look_at(roller.global_position + dir.cross(Vector3.UP), Vector3.UP)
	roller.rotate_object_local(Vector3.RIGHT, PI * 0.5)
	var tw := roller.create_tween()
	tw.tween_property(roller, "global_position", start + dir * LOG_LENGTH + Vector3(0, radius, 0), 0.7)
	tw.tween_callback(roller.queue_free)
