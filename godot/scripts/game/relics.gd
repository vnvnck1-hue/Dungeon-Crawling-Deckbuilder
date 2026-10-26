extends Node
## Relics: 보물상자에서 고른 유물 5종의 소유와 영구 패시브 효과(기획 §7).
## 효과 중 "매일 낮 시작" 항목은 여기서 처리하고, 전투·벌목 배율은 각 모듈이 has()로 읽는다.

const Cfg := preload("res://scripts/config.gd")

signal changed

var game
var owned: Array = []


func _ready() -> void:
	name = "Relics"


func has(id: String) -> bool:
	return id in owned


func count() -> int:
	return owned.size()


## 아직 없는 유물 중 무작위 n종(상자 선택지). 다 모았으면 빈 배열.
func choices(n := Cfg.CHEST_CHOICES) -> Array:
	var pool: Array = Cfg.RELICS.filter(func(id): return not has(id))
	pool.shuffle()
	return pool.slice(0, mini(n, pool.size()))


func grant(id: String) -> bool:
	if not id in Cfg.RELICS or has(id):
		return false
	owned.append(id)
	game.cards.stats["relics"] += 1
	game.toast("유물 획득 — %s: %s" % [Cfg.RELIC_NAMES[id], Cfg.RELIC_DESC[id]], Color(1.0, 0.9, 0.55))
	game.sounds.play_or("relic_get", "mon_drop")
	changed.emit()
	return true


## 매일 낮 시작(GameSession이 호출): 화로의 온기석 → 산장 회복, 서리 여왕의 눈물 → 서리 룬 1장.
func on_prep_start(day: int) -> void:
	if day <= 1:
		return
	if has("hearth_ember"):
		var r: float = game.world.lodge.repair(Cfg.RELIC_EMBER_LODGE)
		if r > 0.0:
			game.toast("화로의 온기석 — 산장 체력 +%d" % int(r), Color(1.0, 0.8, 0.5))
	if has("frost_queen_tear"):
		game.cards.add("frost_rune", 1)
		game.toast("서리 여왕의 눈물 — 서리 룬 카드 +1", Color(0.7, 0.88, 1.0))


func enemy_speed_mult() -> float:
	return Cfg.RELIC_FROST_SLOW if has("frost_queen_tear") else 1.0


func bolt_damage() -> float:
	return Cfg.BOLT_DAMAGE * (Cfg.RELIC_BOLT_MULT if has("moonlit_charm") else 1.0)


func bolt_range() -> float:
	return Cfg.BOLT_RANGE + (Cfg.RELIC_BOLT_RANGE if has("moonlit_charm") else 0.0)
