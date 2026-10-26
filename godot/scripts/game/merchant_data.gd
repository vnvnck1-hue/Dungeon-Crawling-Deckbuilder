extends RefCounted
## 떠돌이 행상 브로크의 방문 규칙·상품 풀·가격(기획: docs/merchant-shop-v01.md).
## 가격 = 카드의 가치. 종류(kind)별 기본값 → 종족 이야기 카드 가산 → 개별 보정(VALUE_OVERRIDES) → 되팔기 이득 방지 하한.
## 모든 수치는 시험값이다.

const Cfg := preload("res://scripts/config.gd")

const CHARACTER_ID := "brock"
const VISIT_EVERY_DAYS := 3          # 3·6·9·12일차 낮에 온다
const ARRIVE_AT := Cfg.PREP_TIME * 0.5   # 낮 한가운데(준비 시간 90초 중 45초)에 숲길로 들어선다
const OFFER_COUNT := 5               # 좌판에 펼치는 카드 수
const REROLL_PRICE := 100           # 좌판 다시 펼치기(방문마다 한 번): 5장을 지금 좌판과 겹치지 않는 새 무작위 카드로 바꾼다

## 종류별 기본 가치(G).
const KIND_VALUE := {
	"resource": 8, "consumable": 16, "spell": 22, "structure": 22, "summon": 30, "draw": 18,
	"livestock": 16, "invite": 20, "treasure": 45, "equipment": 32, "relic": 55, "event": 24, "contract": 28,
}
const DEFAULT_VALUE := 20
## 용병 이야기·이벤트에서만 얻던 종족 카드는 조금 더 귀하다(주점 술은 예전 장날 값 그대로).
const RACE_BONUS := 4

## 개별 보정(G). 예전 장날 가격표를 그대로 이어받고, 강하거나 약한 카드를 따로 맞춘다.
const VALUE_OVERRIDES := {
	# 예전 장날(떠돌이 행상) 가격
	"moss_bandage": 15, "resin_torch": 25, "firefly_swarm": 15, "vine_snare": 20, "winter_firewood": 15,
	"frost_rune": 25, "ward_lantern": 20, "guest_invitation": 20, "sleeping_thorn_seed": 25, "lamb": 15,
	"poison_mushroom": 10, "old_spellbook": 30, "treasure_chest": 45,
	"fire_ale": 20, "golden_mead": 25, "wisp_spirit": 20, "dew_of_forgetting": 25,
	# 재화·소모품
	"wool": 12, "timber": 10, "raw_meat": 16, "rabbit_pelt": 20, "scrap": 8, "black_wool": 18,
	"meat_stew": 14, "corpse": 10, "dud_bomb": 12, "junk_sack": 18,
	# 귀한 것
	"black_sheep": 40, "forest_monster": 35, "stone_wall": 30, "village_militia": 34, "bone_hounds": 34,
	"death_march": 40, "goblin_gang": 32,
	# 마녀 장신구·화합 유물
	"dream_journal": 48, "ledger_of_dead": 48, "interpreter_pen": 48, "crest_banner": 55,
	# 전설 카드 5장 + 광석(docs/legend-cards-v01.md). 전설은 아래 price_of 에서 2배
	"ore": 28, "frost_crown": 45, "lich_crown": 45, "wild_grimoire": 35, "fire_brazier": 38, "winter_bell": 30,
}

## 좌판에 오르지 않는 카드: 인물 카드(용병 계약·주점 손님), 내부 상태용 카드, 이야기·의식·보스로만 여는 카드.
const EXCLUDED_IDS := [
	"relic_unknown",                                   # 보물상자를 열 때만 생기는 미공개 유물
	"shroud_cloth", "thorn_bind", "red_chalice",       # 제단 의식 첫 완성 권능
	"hibernation_pelt",                                # 보스 전리품
	"dragon_scale",                                    # 적 처치 0.1%·보스 확정 전리품(용 소환)
	"wolf_blood", "crescent_moon", "half_moon", "full_moon",  # 파르그 이야기로만 받는 늑대의 피
]

## 등급(가격 구간): 표시 이름·색. 위에서부터 처음 맞는 구간.
const GRADES := [
	{"max": 14, "name": "흔한 물건", "color": Color(0.78, 0.76, 0.72)},
	{"max": 24, "name": "쓸 만한 물건", "color": Color(0.62, 0.86, 0.56)},
	{"max": 39, "name": "귀한 물건", "color": Color(0.55, 0.75, 1.0)},
	{"max": 99999, "name": "진귀한 물건", "color": Color(1.0, 0.8, 0.38)},
]


static func is_visit_day(day: int) -> bool:
	return day > 0 and day % VISIT_EVERY_DAYS == 0


## 인물 카드인가: 네 직업 용병 계약과 '인물 ·' 분류(주점 손님 에린).
static func is_person_card(id: String, d: Dictionary) -> bool:
	return id in Cfg.JOB_CARDS or str(d.get("category", "")).begins_with("인물")


## 좌판에 올릴 수 있는 카드인가.
static func sellable(id: String, d: Dictionary) -> bool:
	if d.is_empty() or is_person_card(id, d) or id in EXCLUDED_IDS:
		return false
	return str(d.get("kind", "")) != "corruption"


## 카드 정의(catalog.json 의 한 항목) → 가격(G).
static func price_of(id: String, d: Dictionary) -> int:
	var v: int
	if VALUE_OVERRIDES.has(id):
		v = int(VALUE_OVERRIDES[id])
	else:
		v = int(KIND_VALUE.get(str(d.get("kind", "")), DEFAULT_VALUE))
		var race := str(d.get("race", ""))
		if race != "" and race != "tavern":
			v += RACE_BONUS
	if str(d.get("rarity", "")) == "legendary":
		v *= 2
	# 산 카드를 바로 되팔아 골드를 불리지 못하게, 판매가의 2배 아래로는 팔지 않는다
	return maxi(v, int(Cfg.SALE_PRICES.get(id, 0)) * 2)


static func grade_of(price: int) -> Dictionary:
	for g in GRADES:
		if price <= int(g["max"]):
			return g
	return GRADES[GRADES.size() - 1]


## 좌판에 올릴 수 있는 모든 카드 id(defs: id → 정의).
static func pool(defs: Dictionary) -> Array:
	var out: Array = []
	for id in defs:
		if sellable(id, defs[id]):
			out.append(id)
	out.sort()
	return out


## 서로 다른 카드 OFFER_COUNT 장을 무작위로 고른다. 항목 {id, price, sold}. avoid: 되도록 빼고 고를 id(다시 펼치기 전 좌판).
static func roll_offers(defs: Dictionary, rng: RandomNumberGenerator, avoid: Array = []) -> Array:
	var ids := pool(defs)
	var fresh: Array = ids.filter(func(id): return not id in avoid)
	if fresh.size() >= OFFER_COUNT:
		ids = fresh
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	var out: Array = []
	for id in ids.slice(0, OFFER_COUNT):
		out.append({"id": id, "price": price_of(id, defs[id]), "sold": false})
	return out
