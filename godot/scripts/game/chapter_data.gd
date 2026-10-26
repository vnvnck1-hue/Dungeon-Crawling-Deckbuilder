extends RefCounted
## 챕터 데이터(볼륨 확장 E0 — 기획: docs/game-volume-expansion-plan.md §2).
## 한 챕터 = 12일. 하루 = 낮(준비) + 밤(웨이브). 1~3일은 기존 3웨이브(Cfg.WAVES)를 그대로 쓴다.
## 밤 groups = [[출현 시각(초), 인원, 적 종류(생략 시 기본 적 "spider" 서리 거미)], ...]. 적 종류는 monster.gd KINDS.
## marked = 표식 개체(처치하면 숲의 괴물 카드)의 출현 순서. -1이면 없음.
## 모든 수치는 시험값이다.

const Cfg := preload("res://scripts/config.gd")

## 밤 규칙: 같은 적이라도 밤마다 다른 판단을 만드는 한 줄 규칙.
const NIGHT_RULES := {
	"normal": {"name": "습격의 밤", "desc": "숲에서 괴물이 몰려옵니다"},
	"big_raid": {"name": "큰 습격", "desc": "괴물이 쉬지 않고 밀려옵니다 — 용비늘이 있다면 지금입니다"},
	"calm": {"name": "고요한 밤", "desc": "숲이 잠잠합니다. 숨을 고르세요"},
	"cult": {"name": "침식된 자들의 밤", "desc": "촛불을 든 침식된 자들이 산장을 저주합니다 — 주머니가 오염될 수 있습니다"},
	"fog": {"name": "안개의 밤", "desc": "짙은 안개로 시야가 좁아집니다 — 등불이 필요합니다"},
	"sheep_thief": {"name": "양 도둑의 밤", "desc": "괴물들이 목장을 노립니다"},
	"siege": {"name": "포위의 밤", "desc": "느리고 단단한 공성 괴물이 산장 벽을 부수러 옵니다"},
	"seal_raid": {"name": "봉인석 탈취의 밤", "desc": "모든 괴물이 산장 속 봉인석만 노립니다"},
	"boss": {"name": "보스의 밤", "desc": "빈 굴의 주인이 깨어났습니다"},
}

## 챕터 1 · 산장 방어(숲). 12일.
const CHAPTER_1 := {
	"id": "chapter_1",
	"name": "챕터 1 · 산장 방어",
	"boss_name": "빈 굴의 주인",
	"days": [
		# 1~3일 정착: 현재 3웨이브
		{"night": "normal", "hp": 36.0, "sheep": 1, "marked": 2, "groups": [[0.0, 3], [8.0, 2]]},
		{"night": "normal", "hp": 48.0, "sheep": 3, "marked": 4, "groups": [[0.0, 3], [5.0, 3], [10.0, 3]]},
		{"night": "big_raid", "hp": 60.0, "sheep": 4, "marked": 8,
			"groups": [[0.0, 3], [3.0, 3], [6.0, 3], [9.0, 3], [12.0, 3], [15.0, 3]]},
		# 4~6일 가까운 숲: 제단(4일), 침식된 자 첫 등장(5일). 장날은 3일마다 오는 행상 브로크가 대신한다(scripts/game/merchant.gd)
		{"night": "calm", "hp": 56.0, "sheep": 0, "marked": 1, "unlock": "altar", "reward": true,
			"groups": [[0.0, 2], [10.0, 2]]},
		{"night": "cult", "hp": 62.0, "sheep": 2, "marked": 6,
			"groups": [[0.0, 3], [4.0, 2, "cultist"], [8.0, 3], [14.0, 2, "cultist"]]},
		{"night": "fog", "hp": 64.0, "sheep": 3, "marked": 8, "reward": true,
			"groups": [[0.0, 4], [5.0, 3, "insect"], [10.0, 4], [15.0, 3, "insect"]]},
		# 7~9일 세력 접촉
		{"night": "cult", "hp": 68.0, "sheep": 3, "marked": 9,
			"groups": [[0.0, 4], [4.0, 3, "cultist"], [9.0, 4], [14.0, 3, "insect"], [18.0, 3]]},
		{"night": "sheep_thief", "hp": 68.0, "sheep": 9, "marked": 9, "reward": true,
			"groups": [[0.0, 4], [4.0, 4, "insect"], [9.0, 4], [14.0, 3]]},
		{"night": "siege", "hp": 72.0, "sheep": 2, "marked": 13,
			"groups": [[0.0, 4], [3.0, 2, "brute"], [8.0, 4, "cultist"], [12.0, 2, "brute"], [16.0, 5]]},
		# 10~11일 봉인석 위기
		{"night": "seal_raid", "hp": 76.0, "sheep": 0, "marked": 19, "reward": true,
			"groups": [[0.0, 5], [4.0, 2, "brute"], [8.0, 4, "cultist"], [12.0, 5, "insect"], [16.0, 2, "brute"], [20.0, 5]]},
		{"night": "calm", "hp": 70.0, "sheep": 1, "marked": 2,
			"groups": [[0.0, 3], [8.0, 3]]},
		# 12일 보스의 밤
		{"night": "boss", "hp": 78.0, "sheep": 2, "marked": 10,
			"groups": [[0.0, 4], [2.0, 1, "boss"], [10.0, 4, "cultist"], [20.0, 4], [28.0, 3, "brute"]]},
	],
}

## 새벽 보상·장날이 다루는 카드 풀(숲 지역 + 기존 카드).
const FOREST_CARDS := ["moss_bandage", "resin_torch", "firefly_swarm", "vine_snare", "winter_firewood"]
const REWARD_POOL := ["moss_bandage", "resin_torch", "firefly_swarm", "vine_snare", "winter_firewood",
	"frost_rune", "ward_lantern", "guest_invitation", "sleeping_thorn_seed", "poison_mushroom", "old_spellbook", "lamb"]
const REWARD_CHOICES := 3
const MARKET_OFFERS := 4
const MARKET_PRICES := {
	"moss_bandage": 15, "resin_torch": 25, "firefly_swarm": 15, "vine_snare": 20, "winter_firewood": 15,
	"frost_rune": 25, "ward_lantern": 20, "guest_invitation": 20, "sleeping_thorn_seed": 25, "lamb": 15,
	"poison_mushroom": 10, "old_spellbook": 30, "treasure_chest": 45,
	"fire_ale": 20, "golden_mead": 25, "wisp_spirit": 20, "dew_of_forgetting": 25,
}
const MARKET_POOL := ["moss_bandage", "resin_torch", "firefly_swarm", "vine_snare", "winter_firewood",
	"frost_rune", "ward_lantern", "guest_invitation", "sleeping_thorn_seed", "lamb", "poison_mushroom", "old_spellbook", "treasure_chest",
	"fire_ale", "golden_mead", "wisp_spirit", "dew_of_forgetting"]
const PURIFY_PRICE := 15


static func chapter() -> Dictionary:
	return CHAPTER_1


static func total_days() -> int:
	return CHAPTER_1["days"].size()


## d일차(1부터) 설정. 범위를 벗어나면 빈 사전.
static func day_cfg(d: int) -> Dictionary:
	var days: Array = CHAPTER_1["days"]
	if d < 1 or d > days.size():
		return {}
	return days[d - 1]


## 밤 n(1부터)의 출현 인원 합계.
static func night_count(n: int) -> int:
	var total := 0
	for g in day_cfg(n).get("groups", []):
		total += int(g[1])
	return total


static func group_kind(g: Array) -> String:
	return String(g[2]) if g.size() > 2 else "spider"


static func rule(n: int) -> Dictionary:
	return NIGHT_RULES.get(day_cfg(n).get("night", "normal"), NIGHT_RULES["normal"])
