extends Node3D
## 니벨라(서리 둥지의 여왕) 전투: 체력·피격·공격 패턴. 표시(거미 모델·포효)는 spider_visual, 둥지·진입 연출은 world/boss_room.gd.
## 둥지 한가운데 뿌리내린 채 몸만 돌려 싸운다(몸 충돌·내비 구멍이 움직이지 않게).
##
## 체력: 900 을 세 단(보라 → 주황 → 빨강)으로 나눈다.
##  - 첫 단이 깨지면 격노: 패턴 간격·예고 시간이 짧아진다.
##  - 둘째 단이 깨지면 얼음 갑옷(실드 120)이 덧씌워져 먼저 깨야 체력이 깎인다.
##  - 단이 깨질 때마다 바로 눈보라 폭발로 받아친다.
## 공격 패턴(모두 바닥 예고 장판이 다 차는 순간 떨어진다):
##  1. 서리 내려찍기 — 마녀 쪽 앞 원(반경 3.6m)을 앞다리로 내리찍는다. 가까울 때.
##  2. 얼음 가시 줄 — 마녀 쪽 부채꼴 세 줄을 따라 얼음 송곳이 차례로 솟는다.
##  3. 서리 거미줄 투척 — 마녀 자리와 둘레로 거미줄 덩이 네 개. 맞으면 피해 + 둔화, 떨어진 자리는 한동안 밟으면 느려진다.
##  4. 눈보라 폭발 — 포효하며 둘레 반경 11m 를 휩쓴다. 네 번째마다, 그리고 단이 깨질 때.
const Cfg := preload("res://scripts/config.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const Atk := preload("res://scripts/visual/vfx/nivella_attack_vfx.gd")
const RoarVfx := preload("res://scripts/visual/vfx/nivella_roar_vfx.gd")
const Web := preload("res://scripts/visual/vfx/nivella_web.gd")

signal damaged(amount: float, absorbed: float)
signal stock_broken(stock_left: int)
signal shield_broken
signal died

const MAX_HP := 900.0
const STOCKS := 3
const SHIELD_MAX := 120.0
const CD_CALM := 2.3
const CD_ENRAGED := 1.5

const STOMP := {"radius": 3.6, "damage": 22.0, "time": 1.0}
const SPIKES := {"length": 20.0, "width": 2.4, "spread_deg": 24.0, "step": 1.8, "radius": 1.3, "damage": 16.0, "time": 0.9}
const WEB := {"count": 4, "radius": 2.2, "damage": 12.0, "flight": 1.1, "slow": 0.5, "slow_time": 2.5, "patch_life": 4.5}
const NOVA := {"radius": 11.0, "damage": 28.0, "time": 1.9}

# 적 공통 인터페이스(enemies 그룹을 도는 코드들이 읽는다)
var hp := MAX_HP
var max_hp := MAX_HP
var dead := false
var hp_offset := 5.2
var aim_height := 2.4
var hit_radius := 4.1          # 마녀 사거리·번개·발톱은 몸 가장자리까지로 잰다(player.gd _edge_dist)
var card_drop := ""
var path_failed := false
var agent: NavigationAgent3D
var kind := "nivella"
var is_boss := true

var room                       # world/boss_room.gd
var game
var visual: Node3D             # SpiderVisual
var shield := 0.0
var active := false
var auto_patterns := true      # 검증·캡처에서 패턴을 하나씩 직접 시전할 때 끈다
var enraged := false
var casts := {"stomp": 0, "spikes": 0, "web": 0, "nova": 0}   # 검증용
var player_hits := 0                                          # 검증용
var _cd := 1.6
var _cycle := 0
var _busy := 0.0
var _patches: Array = []       # [위치, 반경, 남은 초]
var _hit_this_cast := {}


func setup(owner_room, g, boss_visual: Node3D, radius: float) -> void:
	room = owner_room
	game = g
	visual = boss_visual
	hit_radius = radius
	name = "NivellaBoss"
	agent = NavigationAgent3D.new()   # 디버그 경로 그리기가 enemies 마다 agent 를 읽는다(쓰지 않음)
	add_child(agent)


func display_name() -> String:
	return "니벨라"


## 남은 단 수(3 → 0). 단 경계 위의 값은 위 단으로 친다.
func stock_left() -> int:
	return clampi(ceili(hp / (max_hp / STOCKS) - 0.0001), 0, STOCKS)


## 지금 단 안에서의 비율(0~1).
func stock_frac() -> float:
	var per := max_hp / STOCKS
	var s := stock_left()
	if s <= 0:
		return 0.0
	return clampf((hp - per * (s - 1)) / per, 0.0, 1.0)


func start_fight() -> void:
	if dead or active:
		return
	active = true
	if not is_in_group("enemies"):
		add_to_group("enemies")
	_cd = 1.4


func pause_fight() -> void:
	active = false


# ───────────────────────── 피격 ─────────────────────────

func take_damage(amount: float) -> void:
	if dead or amount <= 0.0:
		return
	amount = minf(amount, Cfg.BOSS_HIT_CAP)
	var absorbed := 0.0
	if shield > 0.0:
		absorbed = minf(shield, amount)
		shield -= absorbed
		amount -= absorbed
		if shield <= 0.0:
			shield = 0.0
			_break_shield()
	var before := stock_left()
	hp = maxf(hp - amount, 0.0)
	Fx.flash(visual)
	if hp > 0.0 and amount > 0.0 and visual.has_method("hurt") and not visual.is_roaring():
		visual.hurt()
	Fx.damage_number(get_parent(), global_position + Vector3(0, hp_offset, 0), amount + absorbed,
		Color(0.75, 0.88, 1.0) if absorbed > 0.0 else Color(1.0, 0.95, 0.55))
	Sfx.play(self, "mon_hit")
	damaged.emit(amount, absorbed)
	if hp <= 0.0:
		die()
		return
	var after := stock_left()
	if after < before:
		_break_stock(after)


func apply_slow(_source: String, _factor: float, _duration: float) -> void:
	pass   # 뿌리내린 보스는 둔화되지 않는다(서리 룬·번개가 부를 수 있게 이름만 둔다)


func _break_stock(left: int) -> void:
	enraged = left <= 2
	if left == 1:
		shield = SHIELD_MAX
	stock_broken.emit(left)
	Web.shock(global_position, 0.9)
	Sfx.play(self, "frost_burst")
	Sfx.play(self, "mon_big")
	if game.get("world") != null:
		game.world.shake(0.7, 0.6)
	# 단이 깨지면 하던 패턴을 끊고 곧바로 눈보라 폭발로 받아친다
	_busy = 0.0
	_cd = 0.4
	_cycle = 3


func _break_shield() -> void:
	shield_broken.emit()
	Sfx.play(self, "frost_burst")
	Fx.burst(get_parent(), global_position + Vector3(0, 2.2, 0), Color(0.8, 0.9, 1.0), 40, 7.0)
	if game.get("world") != null:
		game.world.shake(0.45, 0.4)


func die() -> void:
	if dead:
		return
	dead = true
	hp = 0.0
	active = false
	shield = 0.0
	remove_from_group("enemies")
	_patches.clear()
	Sfx.play_or(self, "boss_die", "mon_die")
	if visual.has_method("die_curl"):
		visual.die_curl()
	if game.get("world") != null:
		game.world.shake(0.9, 1.0)
	game.toast("니벨라를 쓰러뜨렸습니다!", Color(0.75, 0.9, 1.0))
	# 보스는 용비늘 확정(니벨라는 kill_gold 를 거치지 않는다)
	if game.get("dragon") != null:
		game.dragon.on_enemy_killed(self)
	died.emit()


# ───────────────────────── 패턴 고르기 ─────────────────────────

func _player():
	var p = game.get("player")
	return p if p != null and is_instance_valid(p) and not p.dead else null


func _k() -> float:
	return 0.8 if enraged else 1.0


func _process(delta: float) -> void:
	_tick_patches(delta)
	if not active or dead or not auto_patterns:
		return
	var p = _player()
	if p == null:
		return
	_busy = maxf(_busy - delta, 0.0)
	_cd -= delta
	if _cd > 0.0 or _busy > 0.0 or visual.is_roaring():
		return
	_cycle += 1
	var d := ActorUtil.flat_dist(p.global_position, global_position) - hit_radius
	if _cycle % 4 == 0:
		_nova()
	elif d < 5.5:
		if randf() < 0.7:
			_stomp(p)
		else:
			_spikes(p)
	elif randf() < 0.5:
		_spikes(p)
	else:
		_web(p)
	_cd = CD_ENRAGED if enraged else CD_CALM


func _flat_dir(to: Vector3) -> Vector3:
	var d := to - global_position
	d.y = 0.0
	return d.normalized() if d.length() > 0.01 else visual.global_basis.z.normalized()


func _later(t: float, f: Callable) -> void:
	if t <= 0.0:
		f.call()
	else:
		get_tree().create_timer(t, false).timeout.connect(f)


## 반경 안의 마녀·용병에게 피해. key 가 같은 판정은 한 번만 맞는다(같은 시전의 여러 가시 등).
func _hit_area(center: Vector3, radius: float, damage: float, key := "", slow := 0.0, slow_time := 0.0) -> int:
	if dead:
		return 0
	var n := 0
	var targets: Array = get_tree().get_nodes_in_group("allies")
	var p = _player()
	if p != null:
		targets.append(p)
	for t in targets:
		if not is_instance_valid(t) or t.dead:
			continue
		if ActorUtil.flat_dist(t.global_position, center) > radius + 0.35:
			continue
		var id := "%s:%d" % [key, t.get_instance_id()]
		if key != "" and _hit_this_cast.has(id):
			continue
		_hit_this_cast[id] = true
		t.take_damage(damage)
		if slow > 0.0 and t.has_method("apply_slow"):
			t.apply_slow("nivella_web", slow, slow_time)
		if t == p:
			player_hits += 1
		n += 1
	return n


# ───────────────────────── 1. 서리 내려찍기 ─────────────────────────

func _stomp(p) -> void:
	casts.stomp += 1
	var k := _k()
	var t: float = STOMP.time * k
	var dir := _flat_dir(p.global_position)
	var reach := clampf(ActorUtil.flat_dist(p.global_position, global_position), hit_radius + 1.2, hit_radius + 5.0)
	var center := global_position + dir * reach
	Atk.telegraph_circle(get_parent(), center, STOMP.radius, t)
	_busy = t + 0.5
	# 내리찍는 순간(strike 의 0.36~0.56 구간)이 장판이 다 차는 때와 맞도록 미리 든다
	_later(t - 0.2, func(): if not dead: visual.strike(center))
	_later(t, func():
		if dead: return
		_hit_area(center, STOMP.radius, STOMP.damage)
		RoarVfx.burst(get_parent(), center, STOMP.radius + 1.5, 0.6, 0.5)
		Fx.snow_kick(center + Vector3(0, 0.05, 0), dir, 8, 3.0)
		Sfx.play(self, "mon_big")
		game.world.shake(0.35, 0.3))


# ───────────────────────── 2. 얼음 가시 줄 ─────────────────────────

func _spikes(p) -> void:
	casts.spikes += 1
	_hit_this_cast.clear()
	var key := "spikes%d" % casts.spikes
	var k := _k()
	var t: float = SPIKES.time * k
	var aim := _flat_dir(p.global_position)
	var start := global_position + aim * (hit_radius + 0.6)
	_busy = t + 1.2
	_later(t - 0.2, func(): if not dead: visual.strike(p.global_position))
	for side in [-1.0, 0.0, 1.0]:
		var dir := aim.rotated(Vector3.UP, deg_to_rad(SPIKES.spread_deg) * side)
		Atk.telegraph_line(get_parent(), start, dir, SPIKES.length, SPIKES.width, t)
		var steps := int(SPIKES.length / SPIKES.step)
		for i in steps:
			var at: Vector3 = start + dir * (SPIKES.step * (i + 0.5))
			_later(t + i * 0.055, func():
				if dead: return
				Atk.ice_spike(get_parent(), at, 0.9 + randf() * 0.25)
				_hit_area(at, SPIKES.radius, SPIKES.damage, key))
	_later(t, func():
		Sfx.play(self, "frost_burst")
		Web.shock(start + aim * 6.0, 0.4))


# ───────────────────────── 3. 서리 거미줄 투척 ─────────────────────────

func _web(p) -> void:
	casts.web += 1
	var k := _k()
	var flight: float = WEB.flight * k
	var mouth := global_position + Vector3(0, 3.0, 0) + _flat_dir(p.global_position) * (hit_radius - 0.5)
	var lead: Vector3 = p.velocity * 0.5 if p.get("velocity") != null else Vector3.ZERO
	var spots: Array[Vector3] = [p.global_position + lead]
	for i in WEB.count - 1:
		var a := randf() * TAU
		spots.append(p.global_position + Vector3(cos(a), 0, sin(a)) * randf_range(2.6, 4.8))
	_busy = flight + 0.4
	visual.strike(p.global_position)
	for i in spots.size():
		var spot: Vector3 = spots[i]
		var delay := i * 0.12
		_later(delay, func():
			if dead: return
			Atk.telegraph_circle(get_parent(), spot, WEB.radius, flight)
			Atk.web_glob(get_parent(), mouth, spot, flight, _web_land))
	Sfx.play(self, "mon_attack")


func _web_land(at: Vector3) -> void:
	if dead:
		return
	_hit_area(at, WEB.radius, WEB.damage, "", WEB.slow, WEB.slow_time)
	Atk.web_patch(get_parent(), at, WEB.radius, WEB.patch_life)
	_patches.append([at, WEB.radius, WEB.patch_life])
	Fx.burst(get_parent(), at + Vector3(0, 0.3, 0), Color(0.9, 0.95, 1.0), 10, 2.5)


## 바닥에 남은 거미줄을 밟고 있으면 계속 느려진다.
func _tick_patches(delta: float) -> void:
	if _patches.is_empty():
		return
	var p = _player()
	for i in range(_patches.size() - 1, -1, -1):
		_patches[i][2] -= delta
		if _patches[i][2] <= 0.0:
			_patches.remove_at(i)
			continue
		if p != null and p.has_method("apply_slow") and ActorUtil.flat_dist(p.global_position, _patches[i][0]) <= _patches[i][1]:
			p.apply_slow("nivella_web_patch", WEB.slow, 0.3)


# ───────────────────────── 4. 눈보라 폭발 ─────────────────────────

func _nova() -> void:
	casts.nova += 1
	var t: float = NOVA.time * _k()
	Atk.telegraph_circle(get_parent(), global_position, NOVA.radius, t)
	visual.roar()
	_busy = maxf(t, 2.7)
	_later(t, func():
		if dead: return
		_hit_area(global_position, NOVA.radius, NOVA.damage)
		RoarVfx.burst(get_parent(), global_position, NOVA.radius + 5.0, 0.85, 0.8)
		Sfx.play(self, "frost_burst")
		Sfx.play(self, "boss_roar")
		game.world.shake(0.6, 0.7)
		if room != null and room.has_method("pulse_flash"):
			room.pulse_flash(0.8))
