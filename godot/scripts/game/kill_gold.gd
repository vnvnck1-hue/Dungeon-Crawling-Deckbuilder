extends Node
## 적 처치 골드(2026-10-19 사용자 방향): 적을 쓰러뜨리면 롤 미니언처럼 동전이 흩뿌려지고 소량의 골드를 얻는다.
## 골드는 처치 순간 바로 들어오고(판정·검증이 연출 시간에 기대지 않게), 동전은 튀어 흩어졌다가 마녀에게 빨려 들어가는 표시 전용이다.
## 적 처치 재화 드랍은 다른 작업(별도 세션)이 맡는다 — 말라의 외알 안경 배율은 loot_chance_mult()로 읽어 가면 된다.
## 호출: monster.gd·venom_insect.gd 의 die() → game.kill_gold.on_enemy_killed(self)

const GoblinData := preload("res://scripts/game/goblin_data.gd")
const Fx := preload("res://scripts/visual/fx.gd")

## 적 종류별 처치 골드(시험값). 표에 없는 종류는 DEFAULT. 큰 숲의 괴물(카드 표식)은 BIG.
const GOLD_BY_KIND := {"brute": 3, "boss": 15}
const DEFAULT_GOLD := 1
const BIG_GOLD := 2
const COIN_SOUND_GAP := 0.12          # 여러 마리가 한꺼번에 죽어도 동전 소리가 겹쳐 터지지 않게

var game
var kills := 0
var earned := 0                        # 이번 판 처치로 번 골드(보너스 포함)
var bonus_earned := 0                  # 그중 동전 저울 보너스
var _sound_cd := 0.0
var _coin_mat: StandardMaterial3D
var _coin_mesh: CylinderMesh


func _ready() -> void:
	name = "KillGold"


func _process(delta: float) -> void:
	_sound_cd = maxf(_sound_cd - delta, 0.0)


## 이 적을 쓰러뜨리면 기본으로 얻는 골드.
func base_gold(enemy) -> int:
	if enemy == null:
		return DEFAULT_GOLD
	var k = enemy.get("kind")
	if enemy.get("is_boss") == true:
		return int(GOLD_BY_KIND["boss"])
	if k != null and GOLD_BY_KIND.has(str(k)):
		return int(GOLD_BY_KIND[str(k)])
	if enemy.get("big") == true:
		return BIG_GOLD
	return DEFAULT_GOLD


## 처치 크레딧: 이 적을 노리고 있던(또는 바로 옆에서 싸우던) 살아 있는 용병들.
## 적의 피해 기록에는 가해자가 없으므로 용병의 현재 교전 대상으로 추정한다(사냥꾼 화살도 target 을 쏜다).
func killers_of(enemy) -> Array:
	var out: Array = []
	if game == null or game.get("contracts") == null:
		return out
	for a in game.contracts.allies:
		if not is_instance_valid(a) or a.dead or a.kind != "merc":
			continue
		if a.target == enemy or a.priority == enemy or a.global_position.distance_to(enemy.global_position) <= 1.8:
			out.append(a)
	return out


## 동전 저울을 낀 처치자 수만큼 보너스.
func coin_bonus(enemy) -> int:
	var n := 0
	for a in killers_of(enemy):
		if _wears(a, "mala_coin_scale"):
			n += GoblinData.COIN_SCALE_BONUS
	return n


## 말라의 외알 안경: 처치한 용병이 끼고 있으면 재화 드랍 확률 배율(1.5). 재화 드랍 시스템이 읽어 쓰는 연결 지점.
func loot_chance_mult(enemy) -> float:
	for a in killers_of(enemy):
		if _wears(a, "mala_monocle"):
			return 1.0 + GoblinData.MONOCLE_LOOT_BONUS
	return 1.0


func _wears(a, id: String) -> bool:
	var gear = a.get("gear")
	if gear == null:
		return false
	for slot in gear:
		if gear[slot].get("id", "") == id:
			return true
	return false


## monster.gd·venom_insect.gd 의 die()가 부른다. 반환: 얻은 골드.
func on_enemy_killed(enemy) -> int:
	if game == null or game.get("economy") == null or enemy == null:
		return 0
	if game.session != null and game.session.is_over():
		return 0
	var base := base_gold(enemy)
	var bonus := coin_bonus(enemy)
	var total := base + bonus
	# 종족·언데드 카드 v1: 뼈 던지기 '운명'(처치 골드 ×2), 승리의 함성 중첩, 뼈 방책 회복
	if game.get("race_cards") != null:
		total *= game.race_cards.kill_gold_mult()
		game.race_cards.on_enemy_killed(enemy)
	if game.get("undead") != null:
		game.undead.on_enemy_killed(enemy)
	# 용비늘 드랍(0.1%, 보스 확정) — 용 소환은 이 카드로만 한다
	if game.get("dragon") != null:
		game.dragon.on_enemy_killed(enemy)
	kills += 1
	earned += total
	bonus_earned += bonus
	# 판매·환급과 같은 지갑. 처치마다 큰 보상음(gold_reward)이 울리지 않도록 economy._add_gold 대신 직접 더한다.
	var eco = game.economy
	eco.gold += total
	eco.total_earned += total
	eco.gold_changed.emit(eco.gold)
	var pos: Vector3 = enemy.global_position
	_scatter(pos, total, bonus > 0)
	if _sound_cd <= 0.0 and game.get("sounds") != null:
		_sound_cd = COIN_SOUND_GAP
		game.sounds.play_or("coin_drop", "gold_reward")
	return total


# ───────────────────────── 동전 연출(표시 전용) ─────────────────────────

func _coin_resources() -> void:
	if _coin_mesh != null:
		return
	_coin_mesh = CylinderMesh.new()
	_coin_mesh.top_radius = 0.14
	_coin_mesh.bottom_radius = 0.14
	_coin_mesh.height = 0.04
	_coin_mesh.radial_segments = 12
	_coin_mat = StandardMaterial3D.new()
	_coin_mat.albedo_color = Color(1.0, 0.8, 0.28)
	_coin_mat.metallic = 0.7
	_coin_mat.roughness = 0.3
	_coin_mat.emission_enabled = true
	_coin_mat.emission = Color(1.0, 0.7, 0.2)
	_coin_mat.emission_energy_multiplier = 1.4


## 동전이 사방으로 튀어 흩어졌다가(0.45초) 잠깐 바닥에서 반짝인 뒤 마녀에게 빨려 들어간다. "+NG" 글자.
func _scatter(pos: Vector3, amount: int, bonus: bool) -> void:
	var parent: Node = game.get("actors")
	if parent == null or not parent.is_inside_tree():
		return
	_coin_resources()
	Fx.float_text(parent, pos + Vector3(0, 1.6, 0), "+%dG" % amount, Color(1.0, 0.86, 0.35) if not bonus else Color(1.0, 0.95, 0.55))
	Fx.gold(pos + Vector3(0, 0.6, 0), amount)
	var n := clampi(4 + amount * 2, 5, 14)
	for i in n:
		var coin := MeshInstance3D.new()
		coin.mesh = _coin_mesh
		coin.material_override = _coin_mat
		coin.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(coin)
		var start := pos + Vector3(0, 0.7, 0)
		coin.global_position = start
		var ang := TAU * (float(i) / n) + randf_range(-0.4, 0.4)
		var land := pos + Vector3(cos(ang), 0, sin(ang)) * randf_range(0.8, 1.8)
		land.y = pos.y + 0.03
		var peak := randf_range(1.3, 2.1)
		var spin := Vector3(randf_range(6, 12), randf_range(4, 9), 0)
		var fly_out := func(t: float) -> void:
			if not is_instance_valid(coin):
				return
			var p := start.lerp(land, t)
			p.y += sin(t * PI) * peak
			coin.global_position = p
			coin.rotation = spin * t
		var suck_in := func(t: float) -> void:
			if not is_instance_valid(coin):
				return
			coin.global_position = land.lerp(_collect_point(land), t * t)
			coin.scale = Vector3.ONE * (1.0 - 0.6 * t)
		var tw := coin.create_tween()
		tw.tween_method(fly_out, 0.0, 1.0, randf_range(0.38, 0.5))
		tw.tween_interval(randf_range(0.25, 0.45))
		tw.tween_method(suck_in, 0.0, 1.0, 0.38)
		tw.tween_callback(coin.queue_free)


func _collect_point(fallback: Vector3) -> Vector3:
	var p = game.get("player")
	if p != null and is_instance_valid(p):
		return p.global_position + Vector3(0, 1.0, 0)
	return fallback + Vector3(0, 2.0, 0)
