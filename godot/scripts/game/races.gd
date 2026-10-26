extends RefCounted
## 종족 등록부(기획: docs/races-guests-v01.md §2, docs/narrative-pack/world-races-card-formats-v01.md §3·§6).
## 종족은 인물·생물 카드의 '작은 변형'이며 직업·역할과 별개의 축이다. 판정은 외형이 아니라 이 id를 본다.
## 종족 조건부 효과("대상이 고블린이면…")는 아직 넣지 않았다. `id_of_person` 같은 조회는 GuestProfiles가 맡는다.

const ALL := ["human", "dwarf", "fairy", "goblin", "beastfolk", "orc"]

const RACES := {
	"human": {"name": "인간", "emblem": "등불", "accent": Color(0.95, 0.85, 0.6),
		"feel": "마녀를 꺼리면서도 필요로 한다", "voice": "기존 일곱 손님의 말투"},
	"dwarf": {"name": "드워프", "emblem": "망치", "accent": Color(0.85, 0.55, 0.35),
		"feel": "돌·연장·조상. 손으로 만든 것에 대한 자부심, 마법엔 미심쩍음", "voice": "짧고 단단한 문장, 사물을 품평"},
	"fairy": {"name": "요정", "emblem": "씨앗", "accent": Color(0.7, 0.95, 0.7),
		"feel": "숲의 상태에 민감한 작은 자연의 존재. 격식과 장난이 공존", "voice": "수수께끼·비유, 존댓말과 반말이 섞임"},
	"goblin": {"name": "고블린", "emblem": "동전", "accent": Color(0.6, 0.75, 0.3),
		"feel": "부품·거래·셈. 겁이 많지만 의리와 호기심이 큼", "voice": "빠른 수다, 값과 숫자를 붙임"},
	"beastfolk": {"name": "수인", "emblem": "발자국", "accent": Color(1.0, 0.7, 0.3),
		"feel": "동물 혈통이 만든 습성(밤눈·후각·겨울잠)", "voice": "혈통마다 다름 — 늑대 과묵, 여우 능청, 토끼 조급"},
	"orc": {"name": "오크", "emblem": "엄니", "accent": Color(0.8, 0.4, 0.35),
		"feel": "공동체·음식·의식. 약속과 명예를 무겁게 여김", "voice": "크고 직설적, 먹을 것을 권함"},
}

static func has(id: String) -> bool:
	return RACES.has(id)

static func name_of(id: String) -> String:
	return RACES.get(id, {}).get("name", "")

static func emblem_of(id: String) -> String:
	return RACES.get(id, {}).get("emblem", "")

static func accent(id: String) -> Color:
	return RACES.get(id, {}).get("accent", Color(0.9, 0.9, 0.9))

static func info(id: String) -> Dictionary:
	return RACES.get(id, {}).duplicate(true)
