extends RefCounted
## 숲길 원정대 데이터: 캐릭터·카드·적·방 구성. 규칙 문서: docs/card-concept-v01.md
## 수치만 바꿀 때는 이 파일만 고친다. 판정 규칙은 core/battle.gd.

const COLS := 8
const ROWS := 4
const ALLY_COLS := 4          # 0..3 아군 지역, 4..7 적 지역
const AP_MAX := 3             # 모든 캐릭터는 매 아군 턴 행동력 3으로 시작
const HAND_SIZE := 5          # 손패 5장. 방에 들어서면 모든 덱을 섞어 5장 뽑고, 턴마다 5장이 될 때까지 다시 뽑는다
const MARK_BONUS := 3
const XP_KILL_BONUS := 3      # 적을 직접 처치한 캐릭터가 더 얻는 경험치
const LEVEL_OPTIONS := 3      # 레벨업 때 고르는 새 카드 수
const HEAL_BETWEEN := 0.3     # 방을 넘어갈 때 잃은 체력 회복 비율 / 쓰러진 동료가 일어나는 체력 비율
## 세 무리를 넘길 때마다 중간 보스. 보스를 쓰러뜨리면 원정대는 모닥불에서 완전히 회복한다.

## 캐릭터. model: dungeon/view/unit_view.gd 가 쓰는 3D 모델 id, props: 손에 쥐는 소품,
## cards: 시작 덱, pool: 레벨업 때 셋 중 하나를 골라 덱에 섞어 넣는 카드
const HEROES := {
	"warrior": {"name": "전사", "hp": 40, "model": "human_common", "props": "warrior", "color": Color(0.95, 0.55, 0.32),
		"blurb": "맨 앞에서 버티는 방패", "art": "res://assets/cards/warrior.png",
		"cards": ["slash", "shield_bash", "war_cry"], "start": Vector2i(3, 1),
		"pool": ["heavy_blow", "iron_wall", "breakthrough", "second_wind", "war_drum"]},
	"archer": {"name": "궁수", "hp": 26, "model": "beastfolk_common", "props": "archer", "color": Color(0.45, 0.85, 0.45),
		"blurb": "줄을 꿰뚫는 사냥꾼", "art": "res://assets/cards/hunter.png",
		"cards": ["aimed_shot", "piercing_arrow", "arrow_rain"], "start": Vector2i(1, 2),
		"pool": ["double_shot", "hunters_mark", "volley", "snipe", "trap_line"]},
	"mage": {"name": "마법사", "hp": 24, "model": "witch_north", "props": "mage", "color": Color(0.7, 0.5, 1.0),
		"blurb": "얼리고 튕기는 술사", "art": "res://assets/cards/old_spellbook.png",
		"cards": ["magic_bolt", "frost_rune", "chain_lightning"], "start": Vector2i(2, 3),
		"pool": ["fireball", "ice_shard", "arcane_shield", "mending_light", "meteor"]},
}
const HERO_ORDER := ["warrior", "archer", "mage"]

## 카드. target: enemy_melee(근접: 적에게 돌진해 친다, 적 1) · enemy_any(원거리 적 1) · row(가로줄) · area3(적 지역 3×3) · cross(적 지역 십자) · none(즉시)
## 효과 키: damage(hits 번) · mark · freeze · push/bump · block(자신) · block_all · heal(자신) · heal_all · taunt · aura(none 카드가 앞 두 열에 주는 피해)
## vfx: card_vfx.gd 가 쓰는 연출 종류(없으면 카드 id 그대로)
const CARDS := {
	"slash": {"hero": "warrior", "cost": 1, "name": "베기", "category": "전사 · 기본 공격", "target": "enemy_melee",
		"damage": 7, "art": "rusty_longsword", "rules": ["적 하나에게 돌진해", "피해 7."]},
	"shield_bash": {"hero": "warrior", "cost": 2, "name": "방패 강타", "category": "전사 · 주 스킬", "target": "enemy_melee",
		"damage": 6, "block": 6, "push": 1, "bump": 4, "art": "ancestor_shield",
		"rules": ["적에게 돌진해 피해 6, 1칸 밀쳐냄.", "뒤가 막히면 피해 +4.", "자신은 방어 6."]},
	"war_cry": {"hero": "warrior", "cost": 3, "name": "불굴의 포효", "category": "전사 · 궁극기", "target": "none",
		"block_all": 8, "aura": 4, "taunt": true, "art": "victory_roar",
		"rules": ["아군 모두 방어 8.", "앞 두 열의 적에게 피해 4.", "다음 적 턴 모든 적이 전사를 노림."]},
	"aimed_shot": {"hero": "archer", "cost": 1, "name": "조준 사격", "category": "궁수 · 기본 공격", "target": "enemy_any",
		"damage": 5, "mark_bonus": 4, "art": "hunter", "rules": ["적 하나에게 피해 5.", "표식이 있으면 +4."]},
	"piercing_arrow": {"hero": "archer", "cost": 2, "name": "꿰뚫는 화살", "category": "궁수 · 주 스킬", "target": "row",
		"damage": 6, "mark": true, "art": "resin_torch", "rules": ["가로줄 하나의 적 모두에게", "피해 6, 표식."]},
	"arrow_rain": {"hero": "archer", "cost": 3, "name": "화살비", "category": "궁수 · 궁극기", "target": "area3",
		"damage": 8, "mark": true, "art": "firefly_swarm", "rules": ["3×3 범위의 적 모두에게", "피해 8, 표식."]},
	"magic_bolt": {"hero": "mage", "cost": 1, "name": "마력탄", "category": "마법사 · 기본 공격", "target": "enemy_any",
		"damage": 5, "art": "oak_staff", "rules": ["적 하나에게 피해 5."]},
	"frost_rune": {"hero": "mage", "cost": 2, "name": "서리 룬", "category": "마법사 · 주 스킬", "target": "cross",
		"damage": 6, "freeze": true, "art": "frost_rune", "rules": ["십자 5칸의 적에게 피해 6.", "다음 적 턴 동안 빙결."]},
	"chain_lightning": {"hero": "mage", "cost": 3, "name": "연쇄 번개", "category": "마법사 · 궁극기", "target": "enemy_any",
		"damage": 12, "jumps": 3, "falloff": 2, "art": "wild_grimoire",
		"rules": ["적 하나에게 피해 12.", "가까운 적으로 3번 튕기며", "2씩 약해짐."]},

	# ── 레벨업 카드(HEROES.pool) ──
	"heavy_blow": {"hero": "warrior", "cost": 2, "name": "강타", "category": "전사 · 레벨업", "target": "enemy_melee",
		"damage": 13, "art": "axe_mercenary", "vfx": "slash", "rules": ["적 하나에게 돌진해", "피해 13."]},
	"iron_wall": {"hero": "warrior", "cost": 1, "name": "철벽", "category": "전사 · 레벨업", "target": "none",
		"block": 10, "art": "stone_wall", "vfx": "guard", "rules": ["자신은 방어 10."]},
	"breakthrough": {"hero": "warrior", "cost": 2, "name": "돌파", "category": "전사 · 레벨업", "target": "row",
		"damage": 6, "art": "rune_hammer", "vfx": "slash", "rules": ["가로줄 하나로 돌진해", "그 줄의 적 모두에게 피해 6."]},
	"second_wind": {"hero": "warrior", "cost": 1, "name": "재기", "category": "전사 · 레벨업", "target": "none",
		"heal": 9, "block": 3, "art": "moss_bandage", "vfx": "guard", "rules": ["자신의 체력 9 회복,", "방어 3."]},
	"war_drum": {"hero": "warrior", "cost": 2, "name": "전고", "category": "전사 · 레벨업", "target": "none",
		"block_all": 5, "taunt": true, "art": "war_drum", "vfx": "war_cry", "rules": ["아군 모두 방어 5.", "다음 적 턴 모든 적이 전사를 노림."]},
	"double_shot": {"hero": "archer", "cost": 1, "name": "연속 사격", "category": "궁수 · 레벨업", "target": "enemy_any",
		"damage": 4, "hits": 2, "art": "bone_throw", "vfx": "aimed_shot", "rules": ["적 하나에게 피해 4,", "두 번."]},
	"hunters_mark": {"hero": "archer", "cost": 1, "name": "사냥꾼의 표식", "category": "궁수 · 레벨업", "target": "enemy_any",
		"damage": 3, "mark": true, "art": "pikl_traps", "vfx": "aimed_shot", "rules": ["적 하나에게 피해 3,", "표식."]},
	"volley": {"hero": "archer", "cost": 2, "name": "일제 사격", "category": "궁수 · 레벨업", "target": "cross",
		"damage": 6, "art": "goblin_firecracker", "vfx": "arrow_rain", "rules": ["십자 5칸의 적 모두에게", "피해 6."]},
	"snipe": {"hero": "archer", "cost": 3, "name": "저격", "category": "궁수 · 레벨업", "target": "enemy_any",
		"damage": 18, "mark_bonus": 4, "art": "crest_banner", "vfx": "aimed_shot", "rules": ["적 하나에게 피해 18.", "표식이 있으면 +4."]},
	"trap_line": {"hero": "archer", "cost": 2, "name": "덫 줄", "category": "궁수 · 레벨업", "target": "row",
		"damage": 4, "freeze": true, "art": "pilgrim_blessing", "vfx": "piercing_arrow", "rules": ["가로줄 하나의 적 모두에게", "피해 4, 빙결."]},
	"fireball": {"hero": "mage", "cost": 2, "name": "화염구", "category": "마법사 · 레벨업", "target": "area3",
		"damage": 7, "art": "fire_brazier", "vfx": "fireball", "rules": ["3×3 범위의 적 모두에게", "피해 7."]},
	"ice_shard": {"hero": "mage", "cost": 1, "name": "얼음 파편", "category": "마법사 · 레벨업", "target": "enemy_any",
		"damage": 4, "freeze": true, "art": "frost_crown", "vfx": "magic_bolt", "rules": ["적 하나에게 피해 4,", "다음 적 턴 동안 빙결."]},
	"arcane_shield": {"hero": "mage", "cost": 1, "name": "마력 보호막", "category": "마법사 · 레벨업", "target": "none",
		"block_all": 5, "art": "wisp_spirit", "vfx": "bless", "rules": ["아군 모두 방어 5."]},
	"mending_light": {"hero": "mage", "cost": 2, "name": "치유의 빛", "category": "마법사 · 레벨업", "target": "none",
		"heal_all": 7, "art": "rise_up", "vfx": "bless", "rules": ["아군 모두 체력 7 회복."]},
	"meteor": {"hero": "mage", "cost": 3, "name": "운석", "category": "마법사 · 레벨업", "target": "area3",
		"damage": 15, "art": "full_moon", "vfx": "fireball", "rules": ["3×3 범위의 적 모두에게", "피해 15."]},
}

## 적. kind: melee · ranged — 둘 다 이동하지 않고 그 자리에서 아군을 친다(근접은 돌진해 치고 돌아온다).
## roar_every: n 번째 적 턴마다 아군 전원 피해 roar. xp: 쓰러뜨리면 살아 있는 아군 모두가 얻는 경험치(직접 처치는 + XP_KILL_BONUS)
const ENEMIES := {
	"goblin": {"name": "고블린 졸개", "hp": 12, "kind": "melee", "damage": 5, "xp": 4, "model": "goblin_common", "scale": 1.0, "props": "club"},
	"thrower": {"name": "고블린 투척꾼", "hp": 9, "kind": "ranged", "damage": 4, "xp": 4, "model": "goblin_common", "scale": 0.95, "props": "bone"},
	"orc": {"name": "오크 도끼잡이", "hp": 24, "kind": "melee", "damage": 9, "xp": 7, "model": "orc_common", "scale": 1.0, "props": "axe"},
	"wolf": {"name": "달빛 늑대인간", "hp": 70, "kind": "melee", "damage": 11, "xp": 20, "model": "werewolf_witch", "scale": 1.8, "props": "",
		"roar_every": 3, "roar": 6, "boss": true, "hp_h": 3.9, "roar_name": "울부짖음"},
	"chief": {"name": "오크 족장", "hp": 90, "kind": "melee", "damage": 13, "xp": 25, "model": "orc_common", "scale": 2.1, "props": "axe",
		"roar_every": 3, "roar": 7, "boss": true, "hp_h": 4.0, "roar_name": "포효"},
}

## 방 구성: [적 id, 칸(열, 행)]
const ROOMS := [
	{"name": "숲 어귀", "enemies": [["goblin", Vector2i(5, 1)], ["goblin", Vector2i(6, 2)]]},
	{"name": "이끼 낀 공터", "enemies": [["goblin", Vector2i(5, 0)], ["goblin", Vector2i(5, 3)], ["thrower", Vector2i(7, 1)]]},
	{"name": "쓰러진 고목 터", "enemies": [["orc", Vector2i(5, 2)], ["thrower", Vector2i(7, 0)], ["thrower", Vector2i(7, 3)]]},
	{"name": "달빛 늑대의 굴", "boss": true, "enemies": [["wolf", Vector2i(6, 1)], ["goblin", Vector2i(5, 3)]]},
	{"name": "바위 능선", "enemies": [["orc", Vector2i(5, 1)], ["goblin", Vector2i(5, 3)], ["thrower", Vector2i(7, 2)]]},
	{"name": "가시덤불 골짜기", "enemies": [["orc", Vector2i(5, 0)], ["orc", Vector2i(6, 3)], ["thrower", Vector2i(7, 1)]]},
	{"name": "얼어붙은 개울", "enemies": [["orc", Vector2i(5, 1)], ["goblin", Vector2i(5, 3)], ["thrower", Vector2i(7, 0)], ["thrower", Vector2i(7, 2)]]},
	{"name": "족장의 둥지", "boss": true, "enemies": [["chief", Vector2i(6, 1)], ["goblin", Vector2i(5, 0)], ["goblin", Vector2i(5, 3)]]},
]


## 손패·덱의 카드 키는 "카드id#번호"(같은 카드가 덱에 여럿 들어갈 수 있어서). 어느 쪽을 넣어도 카드 정의를 돌려준다.
static func card(id: String) -> Dictionary:
	return CARDS.get(base_id(id), {})


static func base_id(key: String) -> String:
	return key.get_slice("#", 0)


## 레벨 lv 에서 다음 레벨까지 필요한 경험치(1→2: 12, 2→3: 18, …). 한 판(적 전부)에 대략 5번 레벨업.
static func xp_to_next(lv: int) -> int:
	return 6 + 6 * lv


static func is_ally_cell(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < ALLY_COLS and c.y >= 0 and c.y < ROWS


static func is_enemy_cell(c: Vector2i) -> bool:
	return c.x >= ALLY_COLS and c.x < COLS and c.y >= 0 and c.y < ROWS


static func in_board(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS
