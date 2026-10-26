extends RefCounted
## 종족·언데드·화합 카드 v1 수치(시험값). 기획·적용 기록: docs/race-cards-v01.md (카드 컨셉 검토 2라운드, 2026-10-19).
## 고블린 수치는 goblin_data.gd 에 따로 있다. 장비 칸·시간대처럼 공용 표가 읽는 값만 config.gd 에 둔다.

# ── 카드 묶음(이벤트 보상·맞바꿈·오래된 기록이 고르는 풀). 사건 카드·침식·시체는 넣지 않는다 ──
const POOLS := {
	"goblin": ["goblin_gang", "goblin_firecracker", "goblin_rush", "shiny_lure", "junk_barricade", "pikl_traps", "junk_sack", "graz_whistle", "pot_helmet"],
	"fairy": ["fae_swap", "dream_journal", "thistle_oath"],
	"dwarf": ["rune_hammer", "dark_ale", "stone_wall", "ancestor_shield", "mine_prop", "stone_song", "ore"],  # ore: 광석(docs/legend-cards-v01.md)
	"orc": ["war_drum", "feast_table", "blood_oath", "victory_roar", "ash_sigil", "spit_roast"],
	"beastfolk": ["pack_scent", "porter_pack"],
	"human": ["guild_writ", "village_militia", "pilgrim_blessing"],
}
const UNDEAD_POOL := ["sacrifice_dagger", "rise_up", "bone_barricade", "soul_jar", "ghoul_feast", "bone_hounds", "ledger_of_dead"]
const UNDEAD_INFAMY := ["death_march"]       # 소문이 '악명'일 때만 후보에 든다
const UNDEAD_CHOICES := 3

# ── 요정 ──
const SWAP_CORRUPT_CHANCE := 0.1
const SWAP_CORRUPTIONS := ["corrupt_prayer", "cursed_whisper"]
const THISTLE_SLOW := 0.6                    # 이동 배율(−40%)
const THISTLE_TIME := 2.5
const PROMISE_CARDS := 2

# ── 드워프 ──
const HAMMER_REPAIR := 40.0
const HAMMER_DWARF_MULT := 2.0
const ALE_HP := 0.3
const ALE_SLOW := 0.85
const WALL_HP := 220.0
const WALL_REPAIR := 30.0
const WALL_REPAIR_AT := 3                    # 드워프 3명 이상이면 새벽 자동 수리(사용자 검수 코멘트)
const SHIELD_ARMOR := 0.3
const SHIELD_AURA := 0.15
const SHIELD_AURA_RADIUS := 4.0
const PROP_HP := 80.0
const PROP_LODGE_HP := 60.0
const PROP_RANGE := 7.0                      # 산장 중심에서 이 안의 땅에만 세운다
const PROP_COLLAPSE_RADIUS := 3.5
const PROP_COLLAPSE_DAMAGE := 45.0
const SONG_TIME := 5.0                       # 사용자 검수 코멘트: 5초, 드워프 4명 이상이면 10초
const SONG_TIME_BONUS := 10.0
const SONG_BONUS_AT := 4

# ── 오크 ──
const DRUM_DAMAGE := 0.3
const DRUM_ORC_DAMAGE := 0.6
const DRUM_KNOCKBACK := 0.8
const FEAST_STEWS := 2                       # 사용자 검수 코멘트: 스튜 2개, 오크 3명 이상이면 1개 더
const FEAST_BONUS_AT := 3
const OATH_HP := 0.5
const OATH_DAMAGE := 0.3
const ROAR_PER_KILL := 0.08                  # 공격 속도 +8%/처치
const ROAR_MAX_STACKS := 8
const SIGIL_RADIUS := 5.0
const SIGIL_FEAR := 4.0
const SIGIL_PUSH := 2.5
const ROAST_MEAT := 3
const ROAST_DAMAGE := 0.2
const PATH_HP := 0.3
const PATH_DAMAGE := 0.2
const PATH_DECLINE_GOLD := 12
const FATE_GOLD_MULT := 2

# ── 수인 ──
const SCENT_PER := 0.1
const SCENT_MAX := 4
const SCENT_RADIUS := 8.0
const PORTER_MULT := 2
const PORTER_SPEED := 0.25
const SLEEP_HP := 40.0

# ── 인간 ──
const MILITIA_COUNT := 2
const MILITIA_HP := 30.0
const MILITIA_DAMAGE := 4.0
const MILITIA_INTERVAL := 1.1
const MILITIA_SPEED := 3.2
const MILITIA_AURA := 4.0                    # 다른 종족 용병이 이 안에 있으면 그 종족 패시브의 절반
## 민병이 곁의 용병 종족에게서 빌리는 패시브(절반 값). 키: damage(피해 배율 가산) · taken(받는 피해 감소) · speed(이동·공격 속도) · slow(공격 둔화)
const MILITIA_PASSIVE := {
	"dwarf": {"taken": 0.15},
	"orc": {"damage": 0.15},
	"beastfolk": {"speed": 0.15},
	"fairy": {"slow": 0.8},
	"goblin": {"speed": 0.1},
}
const BLESSING_REPUTATION := 12
const LETTER_DECLINE_GOLD := 8
const RECORDS_CHOICES := 3
const RECORDS_NO_CORRUPTION_GOLD := 6
const WAGON_OFFERS := 3
const WAGON_PRICE := 18

# ── 브리지 ──
const RATION_HP := 0.4
const RATION_HEAL := 0.5

# ── 화합 ──
const BANNER_RACES := 3
const BANNER_DAMAGE := 0.2
const PEN_SHARED_CHANCE := 0.55
const FESTIVAL_RACES := 4
const FESTIVAL_COST := 20
const FESTIVAL_HP := 20.0
const FESTIVAL_DAMAGE := 0.1
const GIFT_DECLINE_GOLD := 5

# ── 언데드 ──
const SACRIFICE_REPUTATION := -15
const CORPSE_LIFE_DAYS := 1                  # 사용자 검수 코멘트: 하루만 유지(낮에 얻으면 다음 새벽, 밤에 얻으면 그다음 새벽에 썩음)
const SKELETON_HP := 26.0
const SKELETON_DAMAGE := 5.0
const SKELETON_INTERVAL := 1.1
const SKELETON_SPEED := 2.8
const SKELETON_CAP := 16
const HOUND_COUNT := 2
const HOUND_HP := 18.0
const HOUND_DAMAGE := 4.0
const HOUND_INTERVAL := 0.8
const HOUND_SPEED := 5.5
const BONE_BARRICADE_HP := 120.0
const BONE_BARRICADE_CORPSES := 2
const BONE_BARRICADE_HEAL := 12.0
const BONE_BARRICADE_RADIUS := 5.0
const SOUL_JAR_DRAW := 2
const FEAST_HEAL := 0.3
const FEAST_DAMAGE := 0.15
const MARCH_MIN := 5
const MARCH_CAP := 12
const LEDGER_EVERY := 5
const RUMOR_HIRE_COST := 8

# ── 용병 이벤트(전체) ──
const EVENT_CHANCE := 0.4                    # 용병이 있을 때 새벽마다(하루 최대 1건)
const SHARED_CHANCE := 0.3                   # 공용 이벤트(중립·화합·브리지)를 꺼낼 확률
