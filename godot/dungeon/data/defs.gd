extends RefCounted
## 숲길 원정대 데이터: 캐릭터·카드·적·방 구성. 규칙 문서: docs/card-concept-v01.md · 직업 시너지: docs/card-synergy-design-v01.md
## 수치만 바꿀 때는 이 파일만 고친다. 판정 규칙은 core/battle.gd.

const COLS := 8
const ROWS := 4
const ALLY_COLS := 4          # 0..3 아군 지역, 4..7 적 지역
const AP_MAX := 3             # 모든 캐릭터는 매 아군 턴 행동력 3으로 시작
const HAND_SIZE := 5          # 손패 5장. 방에 들어서면 모든 덱을 섞어 5장 뽑고, 턴마다 5장이 될 때까지 다시 뽑는다(생성·뽑기는 HAND_MAX 까지)
const XP_KILL_BONUS := 3      # 적을 직접 처치한 캐릭터가 더 얻는 경험치
const LEVEL_OPTIONS := 3      # 레벨업 때 고르는 새 카드 수
const HEAL_BETWEEN := 0.3     # 방을 넘어갈 때 잃은 체력 회복 비율 / 쓰러진 동료가 일어나는 체력 비율
## 세 무리를 넘길 때마다 중간 보스. 보스를 쓰러뜨리면 원정대는 모닥불에서 완전히 회복한다.

## 캐릭터. model: dungeon/view/unit_view.gd 가 쓰는 3D 모델 id, props: 손에 쥐는 소품,
## cards: 시작 덱, pool: 레벨업 때 셋 중 하나를 골라 덱에 섞어 넣는 카드(카드의 tag·rarity 로 가중치)
## trait: 직업 특성(패시브) 이름·설명. 규칙 문서: docs/card-synergy-design-v01.md
const HEROES := {
	"warrior": {"name": "전사", "hp": 40, "model": "human_common", "props": "warrior", "color": Color(0.95, 0.55, 0.32),
		"blurb": "맞을수록 세지는 방패", "art": "res://assets/cards/warrior.png",
		"trait": "투지", "trait_text": "맞을 때마다 투지 +1. 전사 카드 피해 +투지",
		"tags": {"A": "버티는 자", "B": "몰이꾼"},
		"cards": ["slash", "shield_bash", "war_cry", "iron_wall"], "start": Vector2i(3, 1),
		"pool": ["heavy_blow", "second_wind", "war_drum", "shield_throw", "blood_oath", "thorn_armor", "bulwark",
			"shoulder_charge", "sweep", "pull", "wall_drive", "regroup"]},
	"archer": {"name": "궁수", "hp": 26, "model": "beastfolk_common", "props": "archer", "color": Color(0.45, 0.85, 0.45),
		"blurb": "표식을 쌓는 사냥꾼", "art": "res://assets/cards/hunter.png",
		"trait": "사냥꾼의 눈", "trait_text": "표식이 쌓인다. 표식 적을 처치하면 행동력 +1",
		"tags": {"A": "사냥감 몰이", "B": "연사"},
		"cards": ["aimed_shot", "piercing_arrow", "arrow_rain", "hunters_mark"], "start": Vector2i(1, 2),
		"pool": ["double_shot", "volley", "snipe", "trap_line", "expose", "finisher", "hunt_signal",
			"arrow_bundle", "quick_shot", "arrow_storm", "steady_aim", "fire_tips", "scout"]},
	"mage": {"name": "마법사", "hp": 24, "model": "witch_north", "props": "mage", "color": Color(0.7, 0.5, 1.0),
		"blurb": "얼리고 태우는 술사", "art": "res://assets/cards/old_spellbook.png",
		"trait": "원소 반응", "trait_text": "마법사가 일으킨 증기 폭발은 더 세다",
		"tags": {"A": "서리 술사", "B": "화염 술사"},
		"cards": ["magic_bolt", "frost_rune", "chain_lightning", "ember"], "start": Vector2i(2, 3),
		"pool": ["fireball", "ice_shard", "arcane_shield", "mending_light", "meteor", "shatter_strike", "glacier_armor",
			"chill_aura", "spread", "combust", "wildfire", "meditate"]},
}
const HERO_ORDER := ["warrior", "archer", "mage"]

## ── 쌓이는 상태·교차 반응(규칙 문서 §2) ──
const FURY_MAX := 8           # 전사 투지 상한
const MARK_MAX := 6           # 표식 상한. 표식 N 인 적은 아군에게 맞을 때마다 피해 +N, 아군 턴 끝마다 −1
const CHILL_FREEZE := 3       # 냉기가 이만큼 쌓이면 빙결(냉기는 0으로)
const SHATTER_DAMAGE := 8     # 파쇄: 빙결된 적이 충돌하거나 파쇄 카드에 맞으면 추가 피해(빙결 해제)
const STEAM_MULT := 2         # 증기 폭발: (냉기 + 화상) × 배율. 마법사가 일으키면 STEAM_MULT_MAGE
const STEAM_MULT_MAGE := 3
const BUMP_DAMAGE := 4        # 충돌 기본 피해(밀린 적과 부딪힌 적 모두)
const HAND_MAX := 8           # 생성·뽑기로 늘어날 수 있는 손패 상한(턴 시작 보충은 HAND_SIZE 까지)
const RARITY_WEIGHT := {"common": 1.0, "uncommon": 0.6, "rare": 0.3}
const RARE_FROM_LEVEL := 4    # 희귀 카드는 이 레벨부터 레벨업 선택지에 나온다
const TAG_WEIGHT := 1.5       # 이미 가진 축(tag)의 카드가 나올 확률 배율

## 지속 카드가 켜는 효과(이번 방이 끝날 때까지). 이름은 캐릭터 패널에 뜬다.
const POWERS := {
	"thorns": {"name": "가시 갑옷", "hero": "warrior", "text": "전사가 맞으면 반사 %d"},
	"barricade": {"name": "굳건함", "hero": "warrior", "text": "전사 방어 유지"},
	"wall_drive": {"name": "벽 몰이", "hero": "warrior", "text": "충돌 피해 +%d, 투지 +1"},
	"hunt_signal": {"name": "사냥 신호", "hero": "archer", "text": "표식 적을 치면 방어 +%d"},
	"steady_aim": {"name": "정조준", "hero": "archer", "text": "화살 피해 +%d"},
	"fire_tips": {"name": "불붙은 화살촉", "hero": "archer", "text": "화상 적을 맞히면 화상 +%d"},
	"chill_aura": {"name": "한기", "hero": "mage", "text": "턴 시작마다 적 냉기 +%d"},
	"wildfire": {"name": "들불", "hero": "mage", "text": "화상 피해마다 표식 +%d"},
}

## 카드. target: enemy_melee(근접: 적에게 돌진해 친다, 적 1) · enemy_any(원거리 적 1) · row(가로줄) · area3(적 지역 3×3) · cross(적 지역 십자) · none(즉시)
## tag: A·B(직업의 두 빌드 축, HEROES.tags) · core(공용). rarity: common · uncommon · rare
## 효과 키 — 자신·아군: block · block_all · heal · heal_all · taunt · fury(투지) · self_damage · power{id: 값} · create{card, n}
##   · draw · discard(낼 수 없는 카드부터 자동으로 버림) · cost_cut(이번 턴 다음 같은 직업 카드 비용 −n) · block_per_frozen(빙결 적 수 × n 을 전사 방어로)
## 효과 키 — 적: damage(hits 번) · aura(none 카드가 앞 두 열에 주는 피해) · block_dmg(지금 방어만큼 피해) · fury_mult(투지 배율)
##   · mark_add · mark_if(이미 표식이면 +n) · mark_scale(표식 × n 추가 피해) · mark_double · mark_clear · chill · chill_center(겨눈 칸만)
##   · burn · burn_double · burn_spread(주변 8칸에 같은 화상) · shatter · push · pull · bump(충돌 피해, 기본 BUMP_DAMAGE) · collide_bonus · kill_draw
## combo: {hero, ...} — 연계. 이번 턴 직전에 낸 카드가 그 직업 카드면 숫자는 더하고 참/거짓은 덮어쓴다.
## exhaust: 쓰면 이번 방에서 사라짐(지속 카드·생성 카드도). ethereal: 턴이 끝날 때 손패에 있으면 사라짐. token: 덱에 없는 생성 카드
## vfx: card_vfx.gd 가 쓰는 연출 종류(없으면 카드 id 그대로)
## art: 임시 원화(마녀산장 재사용). 전용 원화가 assets/cards/synergy/<카드 id>.png 로 들어오면 그쪽을 쓴다(hand.gd).
const CARDS := {
	# ── 전사 ──
	"slash": {"hero": "warrior", "cost": 1, "name": "베기", "category": "전사 · 기본 공격", "target": "enemy_melee", "tag": "core",
		"damage": 6, "art": "rusty_longsword", "rules": ["적 하나에게 돌진해", "피해 6."]},
	"shield_bash": {"hero": "warrior", "cost": 2, "name": "방패 강타", "category": "전사 · 몰이꾼", "target": "enemy_melee", "tag": "B",
		"damage": 6, "block": 6, "push": 1, "art": "ancestor_shield",
		"rules": ["돌진해 피해 6, 1칸 밀침.", "막히면 충돌 피해.", "자신은 방어 6."]},
	"war_cry": {"hero": "warrior", "cost": 3, "name": "불굴의 포효", "category": "전사 · 궁극기", "target": "none", "tag": "A",
		"block_all": 8, "aura": 4, "taunt": true, "fury": 2, "art": "victory_roar",
		"rules": ["아군 모두 방어 8.", "앞 두 열의 적 피해 4.", "도발. 투지 +2."]},
	"iron_wall": {"hero": "warrior", "cost": 1, "name": "철벽", "category": "전사 · 버티는 자", "target": "none", "tag": "A",
		"block": 8, "combo": {"hero": "mage", "block": 4}, "art": "stone_wall", "vfx": "guard",
		"rules": ["자신은 방어 8.", "연계(마법사): 방어 +4."]},
	"heavy_blow": {"hero": "warrior", "cost": 2, "name": "강타", "category": "전사 · 레벨업", "target": "enemy_melee", "tag": "core", "rarity": "uncommon",
		"damage": 9, "fury_mult": 3, "art": "axe_mercenary", "vfx": "slash", "rules": ["돌진해 피해 9.", "투지가 3배로 붙는다."]},
	"second_wind": {"hero": "warrior", "cost": 1, "name": "재기", "category": "전사 · 버티는 자", "target": "none", "tag": "A",
		"heal": 9, "block": 3, "art": "moss_bandage", "vfx": "guard", "rules": ["자신의 체력 9 회복,", "방어 3."]},
	"war_drum": {"hero": "warrior", "cost": 2, "name": "전고", "category": "전사 · 버티는 자", "target": "none", "tag": "A",
		"block_all": 5, "taunt": true, "combo": {"hero": "mage", "block_all": 3}, "art": "war_drum", "vfx": "war_cry",
		"rules": ["아군 모두 방어 5. 도발.", "연계(마법사): 방어 8."]},
	"shield_throw": {"hero": "warrior", "cost": 1, "name": "방패 던지기", "category": "전사 · 버티는 자", "target": "enemy_any", "tag": "A",
		"block_dmg": true, "art": "ancestor_shield", "vfx": "shield_throw", "rules": ["적 하나에게", "지금 방어만큼 피해."]},
	"blood_oath": {"hero": "warrior", "cost": 0, "name": "피의 맹세", "category": "전사 · 버티는 자", "target": "none", "tag": "A",
		"self_damage": 4, "fury": 2, "art": "blood_oath", "vfx": "power", "rules": ["체력 4를 잃고", "투지 +2."]},
	"thorn_armor": {"hero": "warrior", "cost": 2, "name": "가시 갑옷", "category": "전사 · 지속", "target": "none", "tag": "A", "rarity": "uncommon",
		"power": {"thorns": 3}, "art": "thorn_bind", "vfx": "power", "rules": ["지속: 전사가 맞을 때마다", "때린 적에게 피해 3."]},
	"bulwark": {"hero": "warrior", "cost": 3, "name": "굳건함", "category": "전사 · 지속", "target": "none", "tag": "A", "rarity": "rare",
		"power": {"barricade": 1}, "art": "bone_barricade", "vfx": "power", "rules": ["지속: 턴이 바뀌어도", "전사의 방어가", "사라지지 않는다."]},
	"shoulder_charge": {"hero": "warrior", "cost": 1, "name": "어깨 돌진", "category": "전사 · 몰이꾼", "target": "enemy_melee", "tag": "B",
		"damage": 4, "push": 2, "collide_bonus": 3, "art": "goblin_rush", "vfx": "shield_bash",
		"rules": ["돌진해 피해 4, 2칸 밀침.", "충돌 피해 +3."]},
	"sweep": {"hero": "warrior", "cost": 2, "name": "휩쓸기", "category": "전사 · 몰이꾼", "target": "row", "tag": "B",
		"damage": 5, "push": 1, "art": "village_militia", "vfx": "slash",
		"rules": ["가로줄로 돌진해", "적 모두 피해 5,", "1칸씩 밀침."]},
	"pull": {"hero": "warrior", "cost": 1, "name": "끌어당기기", "category": "전사 · 몰이꾼", "target": "enemy_any", "tag": "B",
		"pull": 1, "combo": {"hero": "archer", "mark_add": 2}, "art": "vine_snare", "vfx": "pull",
		"rules": ["적 하나를 1칸 당김.", "막히면 충돌 피해.", "연계(궁수): 표식 +2."]},
	"wall_drive": {"hero": "warrior", "cost": 2, "name": "벽 몰이", "category": "전사 · 지속", "target": "none", "tag": "B", "rarity": "uncommon",
		"power": {"wall_drive": 4}, "art": "stone_song", "vfx": "power", "rules": ["지속: 충돌 피해 +4,", "충돌마다 투지 +1."]},
	"regroup": {"hero": "warrior", "cost": 1, "name": "재정비", "category": "전사 · 레벨업", "target": "none", "tag": "core",
		"block": 4, "discard": 1, "draw": 1, "art": "battle_ration", "vfx": "guard",
		"rules": ["방어 4. 낼 수 없는", "카드 1장을 버리고", "1장 뽑기."]},

	# ── 궁수 ──
	"aimed_shot": {"hero": "archer", "cost": 1, "name": "조준 사격", "category": "궁수 · 기본 공격", "target": "enemy_any", "tag": "core",
		"damage": 5, "mark_if": 1, "art": "hunter", "rules": ["적 하나에게 피해 5.", "표식이 있으면 표식 +1."]},
	"piercing_arrow": {"hero": "archer", "cost": 2, "name": "꿰뚫는 화살", "category": "궁수 · 주 스킬", "target": "row", "tag": "A",
		"damage": 6, "mark_add": 1, "art": "resin_torch", "rules": ["가로줄의 적 모두", "피해 6, 표식 +1."]},
	"arrow_rain": {"hero": "archer", "cost": 3, "name": "화살비", "category": "궁수 · 궁극기", "target": "area3", "tag": "A",
		"damage": 7, "mark_add": 2, "art": "firefly_swarm", "rules": ["3×3 범위의 적 모두", "피해 7, 표식 +2."]},
	"hunters_mark": {"hero": "archer", "cost": 1, "name": "사냥꾼의 표식", "category": "궁수 · 사냥감 몰이", "target": "enemy_any", "tag": "A",
		"damage": 3, "mark_add": 2, "art": "pikl_traps", "vfx": "aimed_shot", "rules": ["적 하나에게 피해 3,", "표식 +2."]},
	"double_shot": {"hero": "archer", "cost": 1, "name": "연속 사격", "category": "궁수 · 연사", "target": "enemy_any", "tag": "B",
		"damage": 4, "hits": 2, "art": "bone_throw", "vfx": "aimed_shot", "rules": ["적 하나에게 피해 4,", "두 번."]},
	"volley": {"hero": "archer", "cost": 2, "name": "일제 사격", "category": "궁수 · 레벨업", "target": "cross", "tag": "core",
		"damage": 5, "combo": {"hero": "mage", "burn": 1}, "art": "goblin_firecracker", "vfx": "arrow_rain",
		"rules": ["십자 5칸의 적 모두", "피해 5.", "연계(마법사): 화상 1."]},
	"snipe": {"hero": "archer", "cost": 3, "name": "저격", "category": "궁수 · 사냥감 몰이", "target": "enemy_any", "tag": "A", "rarity": "uncommon",
		"damage": 14, "mark_scale": 3, "art": "crest_banner", "vfx": "aimed_shot", "rules": ["적 하나에게 피해 14.", "표식 × 3 추가 피해."]},
	"trap_line": {"hero": "archer", "cost": 2, "name": "덫 줄", "category": "궁수 · 레벨업", "target": "row", "tag": "core",
		"damage": 4, "chill": 2, "art": "pilgrim_blessing", "vfx": "piercing_arrow", "rules": ["가로줄의 적 모두", "피해 4, 냉기 2."]},
	"expose": {"hero": "archer", "cost": 1, "name": "약점 노출", "category": "궁수 · 사냥감 몰이", "target": "enemy_any", "tag": "A",
		"mark_double": true, "exhaust": true, "art": "mala_monocle", "vfx": "aimed_shot", "rules": ["적 하나의 표식을", "2배로. 소멸."]},
	"finisher": {"hero": "archer", "cost": 2, "name": "마무리 사격", "category": "궁수 · 사냥감 몰이", "target": "enemy_any", "tag": "A",
		"damage": 6, "mark_scale": 3, "mark_clear": true, "kill_draw": 1, "art": "sacrifice_dagger", "vfx": "aimed_shot",
		"rules": ["피해 6 + 표식 × 3,", "표식을 지운다.", "처치하면 1장 뽑기."]},
	"hunt_signal": {"hero": "archer", "cost": 2, "name": "사냥 신호", "category": "궁수 · 지속", "target": "none", "tag": "A", "rarity": "uncommon",
		"power": {"hunt_signal": 2}, "art": "graz_whistle", "vfx": "power", "rules": ["지속: 아군이 표식 적을", "맞힐 때마다", "그 아군 방어 +2."]},
	"arrow_bundle": {"hero": "archer", "cost": 1, "name": "화살 뭉치", "category": "궁수 · 연사", "target": "none", "tag": "B",
		"create": {"card": "arrow", "n": 2}, "art": "porter_pack", "vfx": "create", "rules": ["손패에 「화살」", "2장을 만든다."]},
	"quick_shot": {"hero": "archer", "cost": 0, "name": "속사", "category": "궁수 · 연사", "target": "enemy_any", "tag": "B",
		"damage": 3, "combo": {"hero": "archer", "damage": 3}, "art": "traveler_boots", "vfx": "aimed_shot",
		"rules": ["적 하나에게 피해 3.", "연계(궁수): 피해 +3."]},
	"arrow_storm": {"hero": "archer", "cost": 3, "name": "화살 폭풍", "category": "궁수 · 연사", "target": "none", "tag": "B", "rarity": "uncommon",
		"damage": 3, "storm": 2, "art": "firefly_swarm", "vfx": "arrow_storm",
		"rules": ["무작위 적에게 피해 3을", "(이번 턴 낸 궁수", "카드 수 + 2)번."]},
	"steady_aim": {"hero": "archer", "cost": 1, "name": "정조준", "category": "궁수 · 지속", "target": "none", "tag": "B", "rarity": "uncommon",
		"power": {"steady_aim": 2}, "art": "rowan_charm", "vfx": "power", "rules": ["지속: 「화살」의", "피해 +2."]},
	"fire_tips": {"hero": "archer", "cost": 2, "name": "불붙은 화살촉", "category": "궁수 · 지속", "target": "none", "tag": "B", "rarity": "rare",
		"power": {"fire_tips": 1}, "art": "resin_torch", "vfx": "power", "rules": ["지속: 궁수 공격이", "화상 적을 맞히면", "화상 +1."]},
	"scout": {"hero": "archer", "cost": 0, "name": "정찰", "category": "궁수 · 레벨업", "target": "none", "tag": "core",
		"discard": 1, "draw": 2, "art": "ward_lantern", "vfx": "create", "rules": ["낼 수 없는 카드", "1장을 버리고", "2장 뽑기."]},
	"arrow": {"hero": "archer", "cost": 0, "name": "화살", "category": "궁수 · 생성", "target": "enemy_any", "token": true,
		"damage": 3, "ethereal": true, "exhaust": true, "art": "bone_throw", "vfx": "aimed_shot",
		"rules": ["적 하나에게 피해 3.", "휘발 · 소멸."]},

	# ── 마법사 ──
	"magic_bolt": {"hero": "mage", "cost": 1, "name": "마력탄", "category": "마법사 · 기본 공격", "target": "enemy_any", "tag": "core",
		"damage": 5, "combo": {"hero": "mage", "damage": 3}, "art": "oak_staff", "rules": ["적 하나에게 피해 5.", "연계(마법사): 피해 +3."]},
	"frost_rune": {"hero": "mage", "cost": 2, "name": "서리 룬", "category": "마법사 · 서리 술사", "target": "cross", "tag": "A",
		"damage": 5, "chill": 2, "chill_center": 3, "art": "frost_rune", "rules": ["십자 5칸 피해 5,", "냉기 2.", "가운데는 냉기 3."]},
	"chain_lightning": {"hero": "mage", "cost": 3, "name": "연쇄 번개", "category": "마법사 · 궁극기", "target": "enemy_any", "tag": "core",
		"damage": 12, "jumps": 3, "falloff": 2, "art": "wild_grimoire",
		"rules": ["피해 12, 3번 튕기며", "2씩 약해짐. 전도:", "첫 적의 상태를 옮김."]},
	"ember": {"hero": "mage", "cost": 0, "name": "불씨", "category": "마법사 · 화염 술사", "target": "enemy_any", "tag": "B",
		"burn": 3, "art": "hearth_ember", "vfx": "ember", "rules": ["적 하나에게", "화상 3."]},
	"fireball": {"hero": "mage", "cost": 2, "name": "화염구", "category": "마법사 · 화염 술사", "target": "area3", "tag": "B",
		"damage": 4, "burn": 3, "art": "fire_brazier", "vfx": "fireball", "rules": ["3×3 범위의 적 모두", "피해 4, 화상 3."]},
	"ice_shard": {"hero": "mage", "cost": 1, "name": "얼음 파편", "category": "마법사 · 서리 술사", "target": "enemy_any", "tag": "A",
		"damage": 4, "chill": 2, "art": "frost_crown", "vfx": "magic_bolt", "rules": ["적 하나에게 피해 4,", "냉기 2."]},
	"arcane_shield": {"hero": "mage", "cost": 1, "name": "마력 보호막", "category": "마법사 · 레벨업", "target": "none", "tag": "core",
		"block_all": 5, "combo": {"hero": "warrior", "block_all": 3}, "art": "wisp_spirit", "vfx": "bless",
		"rules": ["아군 모두 방어 5.", "연계(전사): 방어 8."]},
	"mending_light": {"hero": "mage", "cost": 2, "name": "치유의 빛", "category": "마법사 · 레벨업", "target": "none", "tag": "core", "rarity": "uncommon",
		"heal_all": 7, "art": "rise_up", "vfx": "bless", "rules": ["아군 모두 체력 7 회복."]},
	"meteor": {"hero": "mage", "cost": 3, "name": "운석", "category": "마법사 · 화염 술사", "target": "area3", "tag": "B", "rarity": "uncommon",
		"damage": 12, "burn": 2, "art": "full_moon", "vfx": "fireball", "rules": ["3×3 범위의 적 모두", "피해 12, 화상 2."]},
	"shatter_strike": {"hero": "mage", "cost": 2, "name": "동결 파쇄", "category": "마법사 · 서리 술사", "target": "enemy_any", "tag": "A",
		"damage": 6, "shatter": true, "art": "frost_queen_tear", "vfx": "magic_bolt", "rules": ["적 하나에게 피해 6.", "빙결된 적이면 파쇄", "(추가 피해 8)."]},
	"glacier_armor": {"hero": "mage", "cost": 1, "name": "빙하 갑주", "category": "마법사 · 서리 술사", "target": "none", "tag": "A",
		"block_all": 4, "block_per_frozen": 2, "art": "winter_bell", "vfx": "bless",
		"rules": ["아군 모두 방어 4.", "빙결된 적 하나마다", "전사 방어 +2."]},
	"chill_aura": {"hero": "mage", "cost": 2, "name": "한기", "category": "마법사 · 지속", "target": "none", "tag": "A", "rarity": "uncommon",
		"power": {"chill_aura": 1}, "art": "hibernation", "vfx": "power", "rules": ["지속: 아군 턴 시작마다", "모든 적 냉기 +1."]},
	"spread": {"hero": "mage", "cost": 1, "name": "확산", "category": "마법사 · 화염 술사", "target": "enemy_any", "tag": "B",
		"burn_spread": true, "art": "poison_spore", "vfx": "ember", "rules": ["적 하나의 화상을", "주변 적에게", "같은 만큼 옮겨 붙임."]},
	"combust": {"hero": "mage", "cost": 2, "name": "폭연", "category": "마법사 · 화염 술사", "target": "enemy_any", "tag": "B", "rarity": "uncommon",
		"burn_double": true, "exhaust": true, "art": "dud_bomb", "vfx": "ember", "rules": ["적 하나의 화상을", "2배로. 소멸."]},
	"wildfire": {"hero": "mage", "cost": 3, "name": "들불", "category": "마법사 · 지속", "target": "none", "tag": "B", "rarity": "rare",
		"power": {"wildfire": 1}, "art": "ash_sigil", "vfx": "power", "rules": ["지속: 적이 화상 피해를", "입을 때마다", "표식 +1."]},
	"meditate": {"hero": "mage", "cost": 1, "name": "명상", "category": "마법사 · 레벨업", "target": "none", "tag": "core",
		"draw": 2, "cost_cut": 1, "art": "dream_journal", "vfx": "power",
		"rules": ["2장 뽑기. 이번 턴", "다음 마법사 카드", "비용 −1."]},
}

## 강화(+): 레벨업 때 새 카드 대신 덱의 카드 하나를 강화할 수 있다. 비용 2 이상이면 비용 −1,
## 비용 1 이하면 수치(UPGRADE_KEYS)가 약 30% 오른다(작은 수는 +1). 강화한 카드 id 는 "카드id+".
const UPGRADE_KEYS := ["damage", "block", "block_all", "heal", "heal_all", "aura", "mark_add", "chill", "burn", "fury"]


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
## 강화한 카드("카드id+")는 원래 정의에 강화 규칙을 입혀 돌려준다(한 번 만들면 캐시).
static var _upgraded := {}

static func card(id: String) -> Dictionary:
	var b := base_id(id)
	if b.ends_with("+"):
		if not _upgraded.has(b):
			_upgraded[b] = _upgrade(b.trim_suffix("+"))
		return _upgraded[b]
	return CARDS.get(b, {})


static func base_id(key: String) -> String:
	return key.get_slice("#", 0)


## 강화 전 카드 id("slash+#3" → "slash"). 연출·특수 판정은 이 id 로 고른다.
static func root_id(key: String) -> String:
	return base_id(key).trim_suffix("+")


static func can_upgrade(id: String) -> bool:
	var c: Dictionary = CARDS.get(id, {})
	if c.is_empty() or c.get("token", false):
		return false
	if int(c.cost) >= 2:
		return true
	for k in UPGRADE_KEYS:
		if c.has(k):
			return true
	return false


static func _upgrade(id: String) -> Dictionary:
	var c: Dictionary = CARDS.get(id, {}).duplicate(true)
	if c.is_empty():
		return c
	c["vfx"] = String(c.get("vfx", id))
	c["name"] = String(c.name) + "+"
	c["upgraded"] = true
	if int(c.cost) >= 2:
		c["cost"] = int(c.cost) - 1
		return c
	var rules: Array = Array(c.rules).duplicate()
	var swaps := {}   # 옛 숫자 → 새 숫자(규칙 글을 한 번에 바꾸려고 모은다)
	for k in UPGRADE_KEYS:
		if not c.has(k):
			continue
		var v := int(c[k])
		var nv := v + maxi(1, int(ceil(v * 0.3)))
		c[k] = nv
		swaps[v] = nv
	# 규칙 글의 같은 숫자를 바꾼다(숫자 앞뒤가 숫자가 아닐 때만). 바꾼 숫자를 다시 바꾸지 않게 자리표를 거친다
	for v in swaps:
		var re := RegEx.create_from_string("(?<![0-9])%d(?![0-9])" % v)
		for i in rules.size():
			rules[i] = re.sub(String(rules[i]), "{%d}" % v, true)
	for i in rules.size():
		for v in swaps:
			rules[i] = String(rules[i]).replace("{%d}" % v, str(swaps[v]))
	c["rules"] = rules
	return c


## 레벨 lv 에서 다음 레벨까지 필요한 경험치(1→2: 12, 2→3: 18, …). 한 판(적 전부)에 대략 5번 레벨업.
static func xp_to_next(lv: int) -> int:
	return 6 + 6 * lv


static func is_ally_cell(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < ALLY_COLS and c.y >= 0 and c.y < ROWS


static func is_enemy_cell(c: Vector2i) -> bool:
	return c.x >= ALLY_COLS and c.x < COLS and c.y >= 0 and c.y < ROWS


static func in_board(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y >= 0 and c.y < ROWS
