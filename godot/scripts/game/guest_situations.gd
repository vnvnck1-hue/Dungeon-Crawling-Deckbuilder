extends RefCounted
## 상황을 아는 첫마디(docs/pentiment-dialogue-research-v01.md §3.4, 사용자 선택 2026-10-25).
## 손님이 말을 걸 때, 어젯밤 일·산장 형편 중 지금 맞는 상황 하나를 이야기 앞에 먼저 꺼낸다.
## 상황 판단은 guest_events.situation_beats(), 대사는 종족별 파일 arcs/situations_<종족>.gd 의 LINES.
##
## LINES 형식: {상황 키: [{"text": 손님의 말, "thought": 마녀의 생각(생략 가능)}, …]} — 상황마다 3개, 손님 id 로 하나를 고른다.
## "fell"·"fell_kin" 의 text 에는 쓰러진 용병 이름 자리 %s 가 하나 있다(이름 바로 뒤에 조사를 붙이지 않는다).

## 위에서부터 먼저 맞는 상황 하나만 꺼낸다.
const ORDER := [
	"fell_kin",      # 어젯밤 같은 종족 용병이 쓰러졌다
	"fell",          # 어젯밤 용병이 쓰러졌다
	"night_hurt",    # 어젯밤 산장이 크게 다쳤다(최대 체력의 15% 이상)
	"boss_down",     # 북쪽 둥지의 니벨라를 쓰러뜨렸다(손님마다 한 번)
	"big_night",     # 어젯밤이 대습격·포위·봉인 습격·우두머리의 밤이었다
	"fog_night",     # 어젯밤 안개가 끼었다
	"final_nights",  # 남은 밤이 둘 이하(손님마다 한 번)
	"no_meat",       # 생고기가 하나도 없다(3일째부터)
	"night_calm",    # 어젯밤 산장도 용병도 다치지 않았다
]
## 하루에 한 번이 아니라 판 전체에서 손님마다 한 번만 꺼내는 상황
const ONCE := ["boss_down", "final_nights"]
const RACE_FILES := {
	"human": "res://scripts/game/arcs/situations_human.gd",
	"dwarf": "res://scripts/game/arcs/situations_dwarf.gd",
	"fairy": "res://scripts/game/arcs/situations_fairy.gd",
	"goblin": "res://scripts/game/arcs/situations_goblin.gd",
	"beastfolk": "res://scripts/game/arcs/situations_beastfolk.gd",
	"orc": "res://scripts/game/arcs/situations_orc.gd",
}
static var _lines: Dictionary = {}

## 종족 → LINES. 파일이 없는 종족은 인간 것을 쓴다.
static func lines(race: String) -> Dictionary:
	if _lines.is_empty():
		for r in RACE_FILES:
			if ResourceLoader.exists(RACE_FILES[r]):
				_lines[r] = (load(RACE_FILES[r]) as GDScript).get_script_constant_map().get("LINES", {})
	return _lines.get(race, _lines.get("human", {}))

## 이 손님이 이 상황에서 할 말(손님 id 로 고정 선택). 없으면 빈 사전.
static func line(race: String, key: String, id: String) -> Dictionary:
	var options: Array = lines(race).get(key, [])
	if options.is_empty(): return {}
	return options[absi(hash(id + key)) % options.size()]
