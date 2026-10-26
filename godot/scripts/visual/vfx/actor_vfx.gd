extends Node
## 캐릭터 주변 상시 연출: 눈 위 발자국, 걸음마다 튀는 눈, 차가운 공기 속 입김, 마녀 지팡이의 마력 입자.
## 액터 코드를 바꾸지 않고 위치·방향만 읽어 따라간다(게임 판정과 무관).
## 그 밖의 사건 연출: 골드 증가 시 동전 별(LodgeEconomy.gold_changed 신호를 듣기만 한다).

const Fx := preload("res://scripts/visual/fx.gd")
const Pool := preload("res://scripts/visual/vfx/vfx_pool.gd")
const Layout := preload("res://scripts/world/layout.gd")

## 종류별 보폭·발자국 크기·입김 색과 크기
const PROFILES := {
	"witch": {"stride": 0.42, "foot": 0.46, "gap": 0.11, "breath": Color(1, 1, 1, 0.62), "breath_k": 1.0, "kick": 2},
	"traveler": {"stride": 0.46, "foot": 0.46, "gap": 0.11, "breath": Color(1, 1, 1, 0.55), "breath_k": 0.9, "kick": 1},
	"merc": {"stride": 0.48, "foot": 0.51, "gap": 0.12, "breath": Color(1, 1, 1, 0.58), "breath_k": 1.0, "kick": 2},
	"monster": {"stride": 0.5, "foot": 0.57, "gap": 0.14, "breath": Color(0.62, 0.42, 0.85, 0.55), "breath_k": 1.1, "kick": 2,
		"print": Color(0.28, 0.2, 0.5, 0.5)},
	"minion": {"stride": 0.5, "foot": 0.57, "gap": 0.14, "breath": Color(0.6, 0.95, 0.65, 0.5), "breath_k": 1.0, "kick": 2},
	"sheep": {"stride": 0.24, "foot": 0.27, "gap": 0.07, "breath": Color(1, 1, 1, 0.5), "breath_k": 0.6, "kick": 1},
}

var game
var weather
var breath                        # BreathVapor(기체 입김). 없으면 Fx.breath 입자로 대신한다
var _track: Dictionary = {}
var _gold := -1
var _aura_t := 0.0
var _frame := 0


func _ready() -> void:
	name = "ActorVfx"


func _process(dt: float) -> void:
	if dt <= 0.0 or game == null or game.actors == null:
		return
	_watch_gold()
	_frame += 1
	for a in game.actors.get_children():
		_update(a, dt)
	for s in get_tree().get_nodes_in_group("sheep"):
		_update(s, dt)
	for id in _track.keys():
		if _track[id]["frame"] != _frame:   # 이번 프레임에 보이지 않은 액터는 잊는다(다시 보이면 처음부터)
			_track.erase(id)
	_staff_aura(dt)


func _kind(a: Node) -> String:
	if a == game.player:
		return "witch"
	if a.is_in_group("sheep"):
		return "sheep"
	if "card_drop" in a:
		return "monster"
	if "kind" in a and "task" in a:
		return "minion" if a.kind == "minion" else "merc"
	if "leaving" in a and "route" in a:
		return "traveler"
	return ""


func _update(a: Node, dt: float) -> void:
	if not (a is Node3D) or not a.is_visible_in_tree():
		return
	if "dead" in a and a.dead:
		return
	# 종류는 처음 볼 때 한 번만 가린다(속성 이름 탐색이 여러 번이라 매 프레임 하지 않는다)
	var id := a.get_instance_id()
	var tr: Dictionary = _track.get(id, {})
	var pos: Vector3 = a.global_position
	if tr.is_empty():
		var k := _kind(a)
		if k == "":
			return
		tr = {"kind": k, "last": pos, "acc": 0.0, "side": 1.0, "breath": randf_range(0.3, 2.0), "head": null}
		_track[id] = tr
	tr["frame"] = _frame
	var kind: String = tr["kind"]
	var prof: Dictionary = PROFILES[kind]
	var last: Vector3 = tr["last"]
	var d := Vector3(pos.x - last.x, 0, pos.z - last.z)
	var moved := d.length()
	tr["last"] = pos
	var visual: Node3D = a.visual if "visual" in a else null
	if moved > 2.0:
		tr["acc"] = 0.0
		return
	# 발자국
	if moved > 0.0005:
		tr["acc"] = float(tr["acc"]) + moved
		var stride: float = prof["stride"]
		if tr["acc"] >= stride:
			tr["acc"] = float(tr["acc"]) - stride
			tr["side"] = -float(tr["side"])
			var dir := d / moved
			var right := Vector3(dir.z, 0, -dir.x)
			var at := pos + right * float(prof["gap"]) * float(tr["side"])
			var yaw := atan2(dir.x, dir.z)
			Fx.footprint(at, yaw, prof["foot"], prof.get("print", Fx.C_PRINT))
			Fx.snow_kick(at, -dir, prof["kick"], 1.0 if kind != "sheep" else 0.6)
			# 마녀 발소리: 두 걸음에 한 번(보폭이 짧아 매 걸음은 너무 잦다)
			if kind == "witch" and float(tr["side"]) > 0.0 and game.sounds != null:
				game.sounds.play("witch_step")
	# 입김
	tr["breath"] = float(tr["breath"]) - dt
	if tr["breath"] <= 0.0 and visual != null:
		tr["breath"] = randf_range(1.3, 2.1) if kind != "monster" else randf_range(1.1, 1.7)
		var head: Node3D = tr["head"]
		if head == null or not is_instance_valid(head):
			# 파츠 캐릭터는 Head 가 목 관절이라 입 앞 표식(Mouth)을 먼저 쓴다(character_models.gd).
			head = visual.find_child("Mouth", true, false)
			if head == null: head = visual.find_child("Head", true, false)
			tr["head"] = head
		if head != null:
			var fwd := visual.global_basis.z.normalized()
			var mouth := head.global_position + fwd * 0.22 * float(prof["breath_k"]) + Vector3(0, -0.06, 0)
			var wind: Vector3 = weather.wind_vector() if weather != null else Vector3.ZERO
			if breath != null and breath.is_ready():
				breath.exhale(mouth, fwd + wind * 0.4, prof["breath"], prof["breath_k"])
			else:
				Fx.breath(mouth, fwd + wind * 0.4, prof["breath"], prof["breath_k"])


## 마녀 지팡이 끝에서 피어오르는 보랏빛 마력(레퍼런스의 손 주변 빛 효과).
func _staff_aura(dt: float) -> void:
	var p = game.player
	if p == null or p.dead or p.staff_tip == null or Fx.pool == null:
		return
	_aura_t -= dt
	if _aura_t > 0.0:
		return
	_aura_t = 0.09
	var tip: Vector3 = p.staff_tip.global_position
	Fx.pool.emit(Pool.GLOW, tip, Vector3.ZERO, 0.12, 0.55, Color(0.8, 0.5, 1.0, 0.6), {"additive": true})
	Fx.pool.emit(Pool.SPARKLE if randf() < 0.5 else Pool.GLOW, tip + Fx._rv(0.12), Vector3(0, randf_range(0.4, 0.8), 0) + Fx._rh(0.2),
		randf_range(0.5, 0.8), randf_range(0.08, 0.14), Color(0.85, 0.6, 1.0), {"additive": true, "spin": 5.0, "sway": 0.3})


func _watch_gold() -> void:
	var eco = game.economy
	if eco == null:
		return
	if _gold < 0:
		_gold = eco.gold
		return
	if eco.gold > _gold:
		var gain: int = eco.gold - _gold
		var at := Layout.DOOR_FRONT + Vector3(0, 1.6, 0)
		Fx.gold(at, gain)
		Fx.float_text(game.world, at + Vector3(0, 0.5, 0), "+%dG" % gain, Color(1.0, 0.86, 0.35))
	_gold = eco.gold
