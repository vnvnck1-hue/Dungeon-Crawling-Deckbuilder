extends RefCounted
## 숲길 원정대 데이터: 캐릭터·카드·적·방 구성. 규칙 문서: docs/card-concept-v01.md
## 수치만 바꿀 때는 이 파일만 고친다. 판정 규칙은 core/battle.gd.

const COLS := 8
const ROWS := 4
const ALLY_COLS := 4          # 0..3 아군 지역, 4..7 적 지역
const AP_MAX := 3
const MARK_BONUS := 3
const HEAL_BETWEEN := 0.3     # 방을 넘어갈 때 잃은 체력 회복 비율 / 쓰러진 동료가 일어나는 체력 비율
## 세 무리를 넘길 때마다 중간 보스. 보스를 쓰러뜨리면 원정대는 모닥불에서 완전히 회복한다.

## 캐릭터. model: dungeon/view/unit_view.gd 가 쓰는 3D 모델 id, props: 손에 쥐는 소품
const HEROES := {
	"warrior": {"name": "전사", "hp": 40, "model": "human_common", "props": "warrior", "color": Color(0.95, 0.55, 0.32),
		"blurb": "맨 앞에서 버티는 방패", "art": "res://assets/cards/warrior.png",
		"cards": ["slash", "shield_bash", "war_cry"], "start": Vector2i(3, 1)},
	"archer": {"name": "궁수", "hp": 26, "model": "beastfolk_common", "props": "archer", "color": Color(0.45, 0.85, 0.45),
		"blurb": "줄을 꿰뚫는 사냥꾼", "art": "res://assets/cards/hunter.png",
		"cards": ["aimed_shot", "piercing_arrow", "arrow_rain"], "start": Vector2i(1, 2)},
	"mage": {"name": "마법사", "hp": 24, "model": "witch_north", "props": "mage", "color": Color(0.7, 0.5, 1.0),
		"blurb": "얼리고 튕기는 술사", "art": "res://assets/cards/old_spellbook.png",
		"cards": ["magic_bolt", "frost_rune", "chain_lightning"], "start": Vector2i(2, 3)},
}
const HERO_ORDER := ["warrior", "archer", "mage"]

## 카드. target: enemy_melee(근접: 적에게 돌진해 친다, 적 1) · enemy_any(원거리 적 1) · row(가로줄) · area3(적 지역 3×3) · cross(적 지역 십자) · none(즉시)
const CARDS := {
	"slash": {"hero": "warrior", "cost": 1, "name": "베기", "category": "전사 · 기본 공격", "target": "enemy_melee",
		"damage": 7, "art": "rusty_longsword", "rules": ["적 하나에게 돌진해", "피해 7."]},
	"shield_bash": {"hero": "warrior", "cost": 2, "name": "방패 강타", "category": "전사 · 주 스킬", "target": "enemy_melee",
		"damage": 6, "block": 6, "push": 1, "bump": 4, "art": "ancestor_shield",
		"rules": ["적에게 돌진해 피해 6, 1칸 밀쳐냄.", "뒤가 막히면 피해 +4.", "자신은 방어 6."]},
	"war_cry": {"hero": "warrior", "cost": 3, "name": "불굴의 포효", "category": "전사 · 궁극기", "target": "none",
		"block_all": 8, "aura": 4, "art": "victory_roar",
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
}

## 적. kind: melee · ranged. roar_every: n 번째 적 턴마다 아군 전원 피해 roar
const ENEMIES := {
	"goblin": {"name": "고블린 졸개", "hp": 12, "kind": "melee", "damage": 5, "model": "goblin_common", "scale": 1.0, "props": "club"},
	"thrower": {"name": "고블린 투척꾼", "hp": 9, "kind": "ranged", "damage": 4, "model": "goblin_common", "scale": 0.95, "props": "bone"},
	"orc": {"name": "오크 도끼잡이", "hp": 24, "kind": "melee", "damage": 9, "model": "orc_common", "scale": 1.0, "props": "axe"},
	"wolf": {"name": "달빛 늑대인간", "hp": 70, "kind": "melee", "damage": 11, "model": "werewolf_witch", "scale": 1.8, "props": "",
		"roar_every": 3, "roar": 6, "boss": true, "hp_h": 3.9, "roar_name": "울부짖음"},
	"chief": {"name": "오크 족장", "hp": 90, "kind": "melee", "damage": 13, "model": "orc_common", "scale": 2.1, "props": "axe",
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


static func card(id: String) -> Dictionary:
	return CARDS.get(id, {})


static func is_ally_cell(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < ALLY_COLS and c.y >= 0 and c.y < ROWS


static func is_enemy_cell(c: Vector2i) -> bool:
	return c.x >= ALLY_COLS and c.x < COLS and c.y >= 0 and c.y < ROWS


static func in_board(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS
