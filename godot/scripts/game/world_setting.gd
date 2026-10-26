extends RefCounted
## 판마다 바뀌는 월드 설정(로그라이크, 사용자 지시 2026-10-18): 산장 가까이에 마을을 둔 '주요 종족' 둘을 무작위로 고르고,
## 손님은 주요 종족에서 자주(MAJOR_WEIGHT), 나머지 종족에서 가끔(MINOR_WEIGHT) 찾아온다.
## 내부 설정이다(사용자 결정 2026-10-18): 화면에 종족 이름·확률을 보여 주지 않는다. 플레이어는 찾아오는 손님을 보며 이번 판의 결을 스스로 알아챈다.
## 시드: `-- --world-seed=N` 으로 고정, `-- --world=orc,fairy` 로 주요 종족 강제(검증·캡처용). 검증 코드는 force()를 쓴다.

const Races := preload("res://scripts/game/races.gd")

const MAJOR_WEIGHT := 6.0   # 주요 종족 하나의 가중치. 주요 둘 = 12, 나머지 넷 = 4 → 손님의 약 75%가 주요 종족
const MINOR_WEIGHT := 1.0

## 종족별 '산장 가까운 마을' 소식과 이번 판에서 기대할 손님의 결. 마을 위치·이름은 판마다 바뀌는 무대 설정이다.
const VILLAGES := {
	"human": {"place": "남쪽 고갯길의 역참 마을", "hint": "용병·상인·전령이 잦다. 마녀를 꺼리면서도 지붕을 찾는다."},
	"dwarf": {"place": "북쪽 바위산의 드워프 광산", "hint": "연장과 돌을 다루는 손님이 잦다. 말은 짧고 일은 단단하다."},
	"fairy": {"place": "동쪽 고목 숲의 요정 마을", "hint": "숲의 상태에 예민한 작은 손님이 잦다. 격식과 장난이 섞인다."},
	"goblin": {"place": "서쪽 개울가의 고블린 장터", "hint": "흥정과 잡동사니를 들고 오는 손님이 잦다. 겁 많지만 의리가 있다."},
	"beastfolk": {"place": "얼어붙은 호숫가의 수인 사냥터", "hint": "밤눈과 코가 밝은 손님이 잦다. 혈통마다 성격이 다르다."},
	"orc": {"place": "동쪽 골짜기의 오크 부락", "hint": "약속과 음식을 무겁게 여기는 손님이 잦다. 크고 직설적이다."},
}

var seed_value := 0
var majors: Array = []        # 주요 종족 id 둘(순서 = 첫 손님 종족)
var rng := RandomNumberGenerator.new()


## 새 판: 주요 종족 둘을 무작위로 고른다. seed가 0이면 무작위 시드.
func roll(seed: int = 0) -> void:
	seed_value = seed if seed != 0 else int(Time.get_ticks_usec() ^ randi())
	rng.seed = seed_value
	var pool: Array = Races.ALL.duplicate()
	majors.clear()
	for i in 2:
		var idx := rng.randi_range(0, pool.size() - 1)
		majors.append(pool[idx])
		pool.remove_at(idx)


## 주요 종족을 직접 정한다(검증·캡처). rng도 다시 시드한다.
func force(major_ids: Array, seed: int = 1) -> void:
	seed_value = seed
	rng.seed = seed
	majors = major_ids.duplicate()


## 명령줄 인자(--world-seed=N, --world=a,b)를 반영해 새 판을 만든다.
func roll_from_args(args: PackedStringArray) -> void:
	var seed := 0
	var forced: Array = []
	for arg in args:
		if arg.begins_with("--world-seed="):
			seed = int(arg.trim_prefix("--world-seed="))
		elif arg.begins_with("--world="):
			for id in arg.trim_prefix("--world=").split(",", false):
				if Races.has(id) and not id in forced: forced.append(id)
	roll(seed)
	if forced.size() == 2:
		force(forced, seed_value)


func is_major(race: String) -> bool:
	return race in majors


func minors() -> Array:
	return Races.ALL.filter(func(r): return not r in majors)


func weight(race: String) -> float:
	return MAJOR_WEIGHT if is_major(race) else MINOR_WEIGHT


## 한 손님이 주요 종족일 확률(전체 가중치 기준).
func major_share() -> float:
	var total := 0.0
	for r in Races.ALL: total += weight(r)
	return (MAJOR_WEIGHT * majors.size()) / total


## 후보 종족(빈 배열이면 전체) 중 가중치로 하나를 뽑는다.
func pick_race(candidates: Array = []) -> String:
	var pool: Array = candidates if not candidates.is_empty() else Races.ALL
	var total := 0.0
	for r in pool: total += weight(r)
	var x := rng.randf() * total
	for r in pool:
		x -= weight(r)
		if x <= 0.0: return r
	return pool[-1]


func village(race: String) -> Dictionary:
	return VILLAGES.get(race, {"place": "", "hint": ""})


## 한 줄 요약(디버그·검증 로그용, 화면에 쓰지 않는다).
func summary() -> String:
	if majors.size() < 2: return ""
	return "major=%s,%s seed=%d" % [majors[0], majors[1], seed_value]
