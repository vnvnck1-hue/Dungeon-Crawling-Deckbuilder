extends CharacterBody3D
## 마녀: 롤식 조작(우클릭 이동·대상 평타, A 공격 이동, S 정지) + 선딜·후딜이 있는 마법 평타. 조작 정리는 docs/lol-controls-v01.md.

const Cfg := preload("res://scripts/config.gd")
const ActorUtil := preload("res://scripts/actors/actor_util.gd")
const SoftSep := preload("res://scripts/actors/soft_separation.gd")
const Layout := preload("res://scripts/world/layout.gd")
const Models := preload("res://scripts/visual/models.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const B := preload("res://scripts/visual/build.gd")
const BoltScript := preload("res://scripts/actors/magic_bolt.gd")
const IceLanceScript := preload("res://scripts/actors/ice_lance.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const WolfVisual := preload("res://scripts/visual/wolf_visual.gd")
const WerewolfVisual := preload("res://scripts/visual/werewolf_visual.gd")
const WerewolfVfx := preload("res://scripts/visual/vfx/werewolf_vfx.gd")
const LightningVfx := preload("res://scripts/visual/vfx/lightning_vfx.gd")
const CharacterModels := preload("res://scripts/visual/character_models.gd")

var game
var hp := Cfg.PLAYER_HP
var max_hp := Cfg.PLAYER_HP
var dead := false
var hp_offset := 2.0
var gear: Dictionary = {}   # 장착 장비 {slot: {uid, id}} — 수치는 game.equipment가 합산한다
var agent: NavigationAgent3D
var visual: Node3D
var body: Node3D
var staff: Node3D
var staff_tip: Node3D
## 파츠 캐릭터 모델일 때 팔·다리·머리·등불 애니메이터(없으면 기존 몸 흔들림만).
var rig: Node
var _hand_r: Node3D
var target_enemy = null
var attack_cd := 0.0
var moving := false
var _anim_t := 0.0
var _cast_t := 0.0
var harvest_target = null   # 털 수확을 위해 다가가는 양
var harvest_t := 0.0        # 털 깎기 진행(초). HUD가 작은 게이지로 그린다
var shearing := false
var shears: Node3D
var _shear_blades: Array = []
var _harvest_repath := 0.0
var _shear_fx := 0.0
var _harvest_pathing := false
## 연속 수확: 양 하나를 깎기 시작하면 같은 목장에서 털이 난 양을 가장 가까운 순서로 차례차례 깎는다.
## 체인 도중 다른 털 난 양을 클릭하면 그 양부터 바로 깎고(깎던 양의 진행은 양에 남는다), 그 뒤 다시 가까운 순서로 이어 간다.
## 직접 이동(클릭·키보드)·밤 시작·쓰러짐이면 체인이 끝난다.
var harvest_chain := false
var harvest_done_in_chain := 0   # 이번 체인에서 깎은 양 수(끝날 때 요약 토스트)
## 롤식 전투(docs/lol-controls-v01.md): target_enemy 는 지금 평타 대상. 우클릭으로 직접 잡으면 attack_forced.
## 서 있을 때(이동 명령 없음)만 사거리 안의 적을 스스로 잡는다. 이동 명령은 대상을 해제한다.
const ATTACK_WINDUP := 0.22     # 선딜: 지팡이를 들어 올리는 동안. 이때 이동 명령이 오면 평타가 취소된다
const ATTACK_BACKSWING := 0.14  # 후딜: 발사 뒤 자세. 이동 명령으로 바로 끊을 수 있다
const ATTACK_MOVE_ACQUIRE := 1.0  # 공격 이동은 사거리보다 이만큼 더 넓게 적을 찾는다
var attack_forced := false
var attack_move_active := false
var attack_move_dest := Vector3.ZERO
var attack_windup := 0.0
var attack_backswing := 0.0
var shots_fired := 0
var _chase_repath := 0.0
## 늑대의 피·달 카드(docs/wolf-blood-event-design.md): moon = 오늘 밤 달("" | crescent | half | full), wolf = 보름달 늑대 상태.
## suffering > 0 이면 늑대의 피를 마신 뒤 괴로워하는 중(입력·공격 무시). 늑대는 근접 물기 평타 + Q 할퀴기 + E 덮치기.
var moon := ""
var wolf := false
var suffering := 0.0
var _suffer_total := 0.0
var _suffer_fx := 0.0
var wolf_visual: Node3D
var moon_ring: MeshInstance3D
var _moon_ring_mat: StandardMaterial3D
var claw_cd := 0.0
var pounce_cd := 0.0
var claw_t := 0.0
var claw_hits := 0
var claw_dir := Vector3.FORWARD
var pounce_t := 0.0
var pounce_target = null
var pounce_from := Vector3.ZERO
var claws_done := 0        # 검증용: 할퀴기 시전 횟수
var pounces_done := 0      # 검증용: 덮치기 시전 횟수
var bites := 0             # 검증용: 물기 횟수
## 마녀 Q 번개 일격(사람 모습일 때만). 연출은 visual/vfx/lightning_vfx.gd.
var lightning_cd := 0.0
var lightning_casts := 0   # 검증용: 번개 일격 시전 횟수
var lightning_hits := 0    # 검증용: 번개 일격에 맞은 적 수(누적)
var lightning_preset: int = Cfg.LIGHTNING_PRESET   # 연출 프리셋(0 기본 번개 · 1 뇌창 · 2 흑뢰), Shift+Q 로 바꾼다


func _ready() -> void:
	collision_layer = Cfg.L_ACTOR
	collision_mask = Cfg.L_OBSTACLE | Cfg.L_BOUNDARY
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.2
	cs.shape = cap
	cs.position.y = 0.6
	add_child(cs)
	agent = NavigationAgent3D.new()
	agent.radius = 0.4
	agent.path_desired_distance = 0.3
	agent.target_desired_distance = 0.15
	agent.path_max_distance = 2.0
	add_child(agent)
	var parts := Models.make_witch()
	visual = parts["root"]
	body = parts["body"]
	staff = parts["staff"]
	staff_tip = parts["tip"]
	rig = parts.get("anim")
	_hand_r = parts.get("hand_r")
	visual.scale = Vector3.ONE * 1.3
	add_child(visual)
	add_to_group("readable_characters")   # F10 캐릭터 분리 시험(visual/character_readability.gd)
	add_to_group("readable_lead")
	SoftSep.register(self, 0.3, 4.0)   # 마녀는 무거워서 주로 남을 비켜 세운다
	_build_shears()
	# 보름달 늑대인간: 마녀 visual 아래 숨겨 두고 변신하면 마녀 몸 대신 보인다.
	# 정식 모델(Tripo 늑대인간, visual/werewolf_visual.gd)이 없으면 예전 블록아웃 네발 늑대로 돌아간다.
	if CharacterModels.has_model("werewolf_witch"):
		wolf_visual = WerewolfVisual.new()
	else:
		wolf_visual = WolfVisual.new()
		wolf_visual.scale = Vector3.ONE * 1.6   # 양보다 확실히 큰 늑대(어깨 높이 약 1m)
	wolf_visual.visible = false
	visual.add_child(wolf_visual)
	# 달 효과 표시: 발밑의 은은한 달빛 고리(초승달 흰빛·상현달 노란빛·보름달 보라빛)
	_moon_ring_mat = Mats.unshaded(Color(1, 1, 1, 0.0), true, true)
	_moon_ring_mat.no_depth_test = true
	moon_ring = B.torus(self, 0.55, 0.68, Vector3(0, 0.05, 0), _moon_ring_mat)
	moon_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	moon_ring.scale = Vector3(1.0, 0.1, 1.0)
	moon_ring.visible = false
	# 마녀 주변의 아주 약한 보랏빛(어두운 눈밭 위 가독성)
	B.omni(self, Vector3(0, 1.1, 0.3), Color(0.75, 0.6, 1.0), 0.10, 2.2, false, 1.5)
	add_to_group("show_hp")


## 이동 명령(우클릭 땅·H·지도). 롤처럼 평타 대상·공격 이동·선딜을 모두 풀고 걸어간다.
func set_destination(p: Vector3) -> void:
	if dead:
		return
	cancel_harvest()
	_drop_attack()
	agent.target_position = Layout.clamp_to_map(p)
	moving = true


## 우클릭 적: 그 적을 대상으로 잡고 사거리까지 다가가 평타를 계속한다.
func command_attack(e) -> void:
	if dead or not _alive(e):
		return
	cancel_harvest()
	if e != target_enemy:
		_cancel_windup()
	attack_move_active = false
	target_enemy = e
	attack_forced = true
	_chase_repath = 0.0


## A + 좌클릭: p 로 걸어가며 가까운 적을 만나면 자동으로 잡아 공격하고, 처치하면 다시 p 로 간다.
func command_attack_move(p: Vector3, prefer = null) -> void:
	if dead:
		return
	cancel_harvest()
	_drop_attack()
	attack_move_active = true
	attack_move_dest = Layout.clamp_to_map(p)
	agent.target_position = attack_move_dest
	moving = true
	if _alive(prefer):
		target_enemy = prefer


## S: 정지. 이동·평타·선딜을 모두 끊는다(서 있으면 롤처럼 사거리 안의 적은 다시 자동으로 잡는다).
func command_stop() -> void:
	if dead:
		return
	cancel_harvest()
	_drop_attack()
	moving = false
	agent.target_position = global_position


func _drop_attack() -> void:
	_cancel_windup()
	target_enemy = null
	attack_forced = false
	attack_move_active = false


## 선딜 중 다른 명령이 들어오면 발사하지 않고 끊는다(쿨다운도 소모하지 않음 = 무빙 평타).
func _cancel_windup() -> void:
	if attack_windup > 0.0:
		attack_windup = 0.0
		_cast_t = 0.0


static func _alive(e) -> bool:
	return e != null and is_instance_valid(e) and not e.dead


func attack_range() -> float:
	if wolf:
		return Cfg.WOLF_BITE_RANGE
	return game.relics.bolt_range() if game != null and game.relics != null else Cfg.BOLT_RANGE


## 평타 주기(선딜 포함): 늑대는 물기 간격, 마녀는 마법탄 간격 × 달 배율(초승달·상현달).
func attack_interval() -> float:
	if wolf:
		return Cfg.WOLF_BITE_INTERVAL
	var mult: float = game.moon_powers.attack_interval_mult() if game != null and game.get("moon_powers") != null and game.moon_powers != null else 1.0
	return Cfg.BOLT_INTERVAL * mult


func windup_time() -> float:
	return Cfg.WOLF_BITE_WINDUP if wolf else ATTACK_WINDUP


## 이동 속도: 기본 × 달 배율(상현달 1.3, 늑대 1.6).
func move_speed() -> float:
	var mult: float = game.moon_powers.move_mult() if game != null and game.get("moon_powers") != null and game.moon_powers != null else 1.0
	return Cfg.PLAYER_SPEED * mult * _gear_speed() * slow_factor()


## 둔화(니벨라 거미줄 등): 출처마다 [배율, 끝나는 시각(ms)]. 가장 강한 하나만 적용한다.
var _slows := {}

func apply_slow(source: String, factor: float, duration: float) -> void:
	if dead:
		return
	_slows[source] = [clampf(factor, 0.1, 1.0), Time.get_ticks_msec() + int(duration * 1000.0)]


func slow_factor() -> float:
	if _slows.is_empty():
		return 1.0
	var now := Time.get_ticks_msec()
	var f := 1.0
	for k in _slows.keys():
		if now >= int(_slows[k][1]):
			_slows.erase(k)
		else:
			f = minf(f, float(_slows[k][0]))
	return f


## 적 몸 가장자리까지 거리: 큰 보스(hit_radius)는 몸 바깥에서도 사거리에 든다.
func _edge_dist(e) -> float:
	var r = e.get("hit_radius")
	return _flat_dist(e.global_position) - (float(r) if r != null else 0.0)


static func _hit_radius(e) -> float:
	var r = e.get("hit_radius")
	return float(r) if r != null else 0.0


func _gear_speed() -> float:
	return game.equipment.speed_mult(self) if game != null and game.get("equipment") != null and game.equipment != null else 1.0


# ───────────────────────── 늑대의 피·달 카드 ─────────────────────────

## 늑대의 피를 마심: t초 동안 괴로워한다(이동·공격·수확 모두 멈춤). 달 카드는 moon_powers가 뒤이어 넣는다.
func suffer(t: float) -> void:
	if dead:
		return
	cancel_harvest()
	_drop_attack()
	moving = false
	agent.target_position = global_position
	suffering = t
	_suffer_total = t
	_suffer_fx = 0.0
	Fx.flash(visual)
	Fx.hit(global_position + Vector3(0, 1.0, 0), Color(0.9, 0.3, 0.6), true)
	Sfx.play(self, "witch_hurt")


## 오늘 밤 달 효과 적용/해제(moon_powers가 부른다). "full"이면 늑대로 변신, ""이면 모두 해제.
func apply_moon(kind: String) -> void:
	moon = kind
	set_wolf(kind == "full")
	var col := Color(0, 0, 0, 0)
	match kind:
		"crescent":
			col = Color(0.95, 0.97, 1.0, 0.55)
		"half":
			col = Color(1.0, 0.9, 0.55, 0.6)
		"full":
			col = Color(0.8, 0.55, 1.0, 0.7)
	_moon_ring_mat.albedo_color = col
	moon_ring.visible = kind != ""
	if kind != "" and kind != "full":
		Fx.celebrate(global_position + Vector3(0, 0.6, 0), col, 0.6)
		Sfx.play(self, "witch_heal")


## 늑대 변신/복귀: 마녀 몸(지팡이 포함)을 숨기고 늑대 모델을 보인다. 들고 있던 카드·평타·수확은 모두 놓는다.
func set_wolf(on: bool) -> void:
	if wolf == on or dead:
		return
	wolf = on
	cancel_harvest()
	_drop_attack()
	claw_t = 0.0
	pounce_t = 0.0
	pounce_target = null
	claw_cd = 0.0
	pounce_cd = 0.0
	body.visible = not on
	wolf_visual.visible = on
	hp_offset = 1.5 if on else 2.0
	if game != null and game.hud != null and game.hud.card_hand != null and game.hud.card_hand.drag_uid >= 0:
		game.hud.card_hand._cancel_by_player()
	Fx.poof(global_position + Vector3(0, 0.6, 0), Color(0.6, 0.4, 0.9), 1.1)
	Fx.celebrate(global_position + Vector3(0, 0.8, 0), Color(0.8, 0.55, 1.0), 0.8)
	Sfx.play_or(self, "wolf_transform" if on else "wolf_revert", "mon_big" if on else "witch_heal")
	if on:
		# 변신: 바닥에 보름달 문양, 몸을 감싸는 광기 불꽃, 웅크렸다가 하늘로 울부짖기
		WerewolfVfx.moon_burst(get_parent(), global_position)
		WerewolfVfx.shake(game, 0.12, 0.45)
		if wolf_visual.has_method("roar"):
			wolf_visual.roar()
	if on and game != null:
		game.toast("보름달 — 마녀가 늑대가 되었습니다 · 우클릭 물기 · Q 할퀴기 · E 덮치기 (손패 잠김)", Color(0.85, 0.7, 1.0))
	elif game != null:
		game.toast("새벽 — 늑대가 마녀로 돌아왔습니다", Color(0.9, 0.85, 1.0))


## Q 할퀴기: at(지면 점) 방향(없으면 보는 방향) 전방 부채꼴을 WOLF_CLAW_TIME 동안 WOLF_CLAW_HITS번 할퀸다. 그동안 움직이지 않는다.
func cast_claw(at) -> bool:
	if dead or not wolf or claw_cd > 0.0 or claw_t > 0.0 or pounce_t > 0.0 or suffering > 0.0:
		return false
	var dir := Vector3(sin(visual.rotation.y), 0, cos(visual.rotation.y))
	if at is Vector3:
		var to: Vector3 = at - global_position
		to.y = 0.0
		if to.length() > 0.15:
			dir = to.normalized()
	cancel_harvest()
	_cancel_windup()
	moving = false
	agent.target_position = global_position
	claw_dir = dir
	visual.rotation.y = atan2(dir.x, dir.z)
	claw_t = Cfg.WOLF_CLAW_TIME
	claw_hits = 0
	claw_cd = Cfg.WOLF_CLAW_CD
	claws_done += 1
	return true


## 마녀 Q 번개 일격: at(지면 점) 방향(없으면 보는 방향)으로 LIGHTNING_RANGE 만큼 즉시 뻗는 관통 번개.
## 줄기 폭 안의 적 모두에게 피해 + 짧은 감전(감속). 이동은 끊지 않는다(선딜 없는 스킬샷).
func cast_lightning(at) -> bool:
	if dead or wolf or lightning_cd > 0.0 or suffering > 0.0:
		return false
	var dir := Vector3(sin(visual.rotation.y), 0, cos(visual.rotation.y))
	if at is Vector3:
		var to: Vector3 = at - global_position
		to.y = 0.0
		if to.length() > 0.15:
			dir = to.normalized()
	cancel_harvest()
	_cancel_windup()
	visual.rotation.y = atan2(dir.x, dir.z)
	var from: Vector3 = staff_tip.global_position if staff_tip != null else global_position + Vector3(0, 1.2, 0)
	var origin := Vector3(global_position.x, 0.0, global_position.z)
	var end := origin + dir * Cfg.LIGHTNING_RANGE
	end.y = 0.9
	var dmg := Cfg.LIGHTNING_DAMAGE
	if game != null and game.get("equipment") != null and game.equipment != null:
		dmg *= game.equipment.damage_mult(self)
	var hit_points: Array = []
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var rel: Vector3 = e.global_position - origin
		rel.y = 0.0
		var along := rel.dot(dir)
		var hr := _hit_radius(e)
		if along < -0.3 - hr or along > Cfg.LIGHTNING_RANGE + 0.4 + hr:
			continue
		if (rel - dir * along).length() > Cfg.LIGHTNING_HALF_WIDTH + 0.3 + hr:
			continue
		var aim_height: float = e.get("aim_height") if e.get("aim_height") != null else 0.65
		hit_points.append(e.global_position + Vector3(0, aim_height, 0))
		# 피해는 연출상 그 적에게 닿는 순간에 들어간다(뇌창은 창이 지나갈 때, 흑뢰는 기둥이 꽂힐 때)
		var delay := LightningVfx.hit_delay(lightning_preset, along / Cfg.LIGHTNING_RANGE)
		if delay <= 0.02:
			_lightning_strike(e, dmg)
		else:
			get_tree().create_timer(delay, false).timeout.connect(_lightning_strike.bind(e, dmg))
	LightningVfx.lance(get_parent(), from, end, hit_points, lightning_preset)
	if lightning_preset == LightningVfx.Preset.CLASSIC:
		LightningVfx.shake(game, 0.22 if hit_points.size() > 0 else 0.12, 0.25)
	else:
		LightningVfx.shake(game, 0.06, 0.1)
	Sfx.play_or(self, "lightning_strike", "bolt_hit")
	_cast_t = 0.3
	lightning_cd = Cfg.LIGHTNING_CD
	lightning_casts += 1
	lightning_hits += hit_points.size()
	return true


func _lightning_strike(e, dmg: float) -> void:
	if not _alive(e):
		return
	e.take_damage(dmg)
	if not e.dead and e.has_method("apply_slow"):
		e.apply_slow("lightning", Cfg.LIGHTNING_SLOW, Cfg.LIGHTNING_SLOW_TIME)


## Shift+Q: 번개 일격 연출 프리셋을 차례로 바꾼다(판정은 같고 피해 시점만 연출에 맞춘다).
func cycle_lightning_preset() -> int:
	lightning_preset = (lightning_preset + 1) % LightningVfx.PRESET_NAMES.size()
	return lightning_preset


## E 덮치기: e(없으면 사거리 안의 가장 가까운 적)에게 WOLF_POUNCE_TIME 동안 뛰어들어 물어뜯는다.
func cast_pounce(e) -> bool:
	if dead or not wolf or pounce_cd > 0.0 or pounce_t > 0.0 or claw_t > 0.0 or suffering > 0.0:
		return false
	if not _alive(e) or _edge_dist(e) > Cfg.WOLF_POUNCE_RANGE:
		e = _nearest_enemy(Cfg.WOLF_POUNCE_RANGE)
	if e == null:
		if game != null:
			game.toast("덮칠 적이 사거리 안에 없습니다", Color(1.0, 0.8, 0.8))
		return false
	cancel_harvest()
	_cancel_windup()
	moving = false
	pounce_target = e
	pounce_from = global_position
	pounce_t = Cfg.WOLF_POUNCE_TIME
	pounce_cd = Cfg.WOLF_POUNCE_CD
	pounces_done += 1
	var to: Vector3 = e.global_position - global_position
	visual.rotation.y = atan2(to.x, to.z)
	Fx.snow_kick(global_position, -to.normalized(), 6, 1.6)
	WerewolfVfx.rage_trail(get_parent(), visual, Cfg.WOLF_POUNCE_TIME + 0.05)
	Sfx.play(self, "sheep_flee")
	return true


func _update_claw(delta: float) -> void:
	claw_t = maxf(claw_t - delta, 0.0)
	var step: float = Cfg.WOLF_CLAW_TIME / float(Cfg.WOLF_CLAW_HITS)
	var should: int = mini(Cfg.WOLF_CLAW_HITS, int((Cfg.WOLF_CLAW_TIME - claw_t) / step) + 1)
	while claw_hits < should:
		var side := 1.0 if claw_hits % 2 == 0 else -1.0
		claw_hits += 1
		var half := deg_to_rad(Cfg.WOLF_CLAW_ANGLE * 0.5)
		var struck := 0
		for e in get_tree().get_nodes_in_group("enemies"):
			if e.dead:
				continue
			var to: Vector3 = e.global_position - global_position
			to.y = 0.0
			var d := to.length()
			if d > Cfg.WOLF_CLAW_RADIUS + 0.4 + _hit_radius(e):
				continue
			if d > 0.05 and absf(to.normalized().signed_angle_to(claw_dir, Vector3.UP)) > half:
				continue
			e.take_damage(Cfg.WOLF_CLAW_DAMAGE)
			struck += 1
			Fx.claw(e.global_position + Vector3(0, 0.8, 0), claw_dir, Color(1.0, 0.45, 0.8))
		# 세 줄 발톱 자국(VisualShader)이 휘두르는 팔 쪽에서 안쪽으로 그어진다. 맞힌 적이 있으면 타격 멈춤·흔들림.
		WerewolfVfx.claw_rake(get_parent(), global_position, claw_dir, side)
		Sfx.play_or(self, "wolf_claw", "mon_attack")
		if wolf_visual != null:
			wolf_visual.claw_swipe(side)
			if struck > 0 and wolf_visual.has_method("impact"):
				wolf_visual.impact(0.3)
		if struck > 0:
			WerewolfVfx.shake(game, 0.06, 0.12)


func _update_pounce(delta: float) -> void:
	pounce_t = maxf(pounce_t - delta, 0.0)
	var e = pounce_target
	var k := 1.0 - pounce_t / Cfg.WOLF_POUNCE_TIME
	if wolf_visual != null:
		wolf_visual.set_pounce(k)
	var goal := pounce_from
	if _alive(e):
		var to: Vector3 = e.global_position - pounce_from
		to.y = 0.0
		var stop := 0.8 + _hit_radius(e)   # 큰 보스는 몸 가장자리에 내려앉는다
		goal = e.global_position - to.normalized() * stop if to.length() > stop else pounce_from
		visual.rotation.y = atan2(to.x, to.z)
	var want := pounce_from.lerp(goal, k)
	want = Layout.clamp_to_map(want)
	velocity = (want - global_position) / maxf(delta, 0.001)
	velocity.y = 0.0
	move_and_slide()
	global_position.y = 0.0
	if pounce_t <= 0.0:
		if wolf_visual != null:
			wolf_visual.set_pounce(-1.0)
		# 착지: 지면 충격 고리·균열·발톱 패임(VisualShader) + 흔들림
		var land_dir: Vector3 = (e.global_position - pounce_from) if _alive(e) else (global_position - pounce_from)
		land_dir.y = 0.0
		WerewolfVfx.slam(get_parent(), global_position + land_dir.normalized() * 0.4, land_dir)
		if _alive(e) and _edge_dist(e) <= Cfg.WOLF_BITE_RANGE + 0.6:
			e.take_damage(Cfg.WOLF_POUNCE_DAMAGE)
			if not e.dead and e.has_method("apply_slow"):
				e.apply_slow("wolf_pounce", Cfg.WOLF_POUNCE_SLOW, Cfg.WOLF_POUNCE_SLOW_TIME)
			WerewolfVfx.bite_snap(get_parent(), e.global_position + Vector3(0, 0.85, 0), land_dir, true)
			Fx.claw(e.global_position + Vector3(0, 0.8, 0), e.global_position - global_position, Color(1.0, 0.4, 0.6))
			Sfx.play_or(self, "wolf_pounce", "mon_attack")
			WerewolfVfx.shake(game, 0.28, 0.35)
			if wolf_visual != null:
				wolf_visual.strike()
				if wolf_visual.has_method("impact"):
					wolf_visual.impact(1.0)
			# 덮친 적을 계속 문다
			if not e.dead:
				target_enemy = e
				attack_forced = true
		else:
			WerewolfVfx.shake(game, 0.14, 0.2)
		pounce_target = null
		velocity = Vector3.ZERO


## 늑대 평타: 물기(근접 직접 피해).
func _bite(e) -> void:
	e.take_damage(Cfg.WOLF_BITE_DAMAGE)
	bites += 1
	var to: Vector3 = e.global_position - global_position
	visual.rotation.y = atan2(to.x, to.z)
	WerewolfVfx.bite_snap(get_parent(), e.global_position + Vector3(0, 0.85, 0), to)
	Sfx.play_or(self, "wolf_bite", "mon_attack")
	WerewolfVfx.shake(game, 0.05, 0.12)
	if wolf_visual != null:
		wolf_visual.strike()
		if wolf_visual.has_method("impact"):
			wolf_visual.impact(0.4)


## 늑대의 피를 마신 뒤: 웅크리고 떨며 붉은·보라 섬광. 끝나면 자세를 되돌린다.
func _animate_suffer(delta: float) -> void:
	var k: float = 1.0 - suffering / maxf(_suffer_total, 0.01)
	var shake := sin(suffering * 42.0) * 0.12 * (0.5 + 0.5 * sin(k * PI))
	body.rotation.x = 0.55 * sin(clampf(k * 1.4, 0.0, 1.0) * PI * 0.5) + shake * 0.3
	body.rotation.z = shake
	body.position.y = -0.14 * sin(k * PI)
	body.scale = Vector3(1.0 + shake * 0.2, 1.0 - absf(shake) * 0.3, 1.0)
	staff.rotation_degrees.x = 40.0 + shake * 40.0
	if rig: rig.play("hurt")
	_suffer_fx -= delta
	if _suffer_fx <= 0.0:
		_suffer_fx = 0.3
		Fx.flash(visual, 1.2)
		Fx.hit(global_position + Vector3(0, 1.0, 0), Color(0.95, 0.35, 0.65) if int(k * 10.0) % 2 == 0 else Color(0.7, 0.4, 1.0))
		Sfx.play(self, "witch_hurt")
	if suffering <= 0.0:
		body.rotation.x = 0.0
		body.rotation.z = 0.0
		body.position.y = 0.0
		body.scale = Vector3.ONE
		staff.rotation_degrees.x = 8.0
		Fx.celebrate(global_position + Vector3(0, 1.2, 0), Color(0.85, 0.7, 1.0), 0.7)


## 양 클릭: 목장 문으로 들어가 양 바로 옆까지 다가간 뒤 HARVEST_TIME 동안 털을 깎는다(v0.3 §7).
## 연속 수확을 시작한다. 이미 체인 중이면 클릭한 양을 맨 앞으로 끼워 넣는다(깎던 양은 진행을 남기고 대기열로 돌아간다).
func harvest(sheep) -> void:
	if dead or sheep == null or sheep.dead or not sheep.wool_ready:
		return
	if sheep == harvest_target:
		return
	var continuing := harvest_chain
	_drop_attack()
	_release_target()
	harvest_chain = true
	if not continuing:
		harvest_done_in_chain = 0
	_begin_target(sheep)


func _begin_target(sheep) -> void:
	harvest_target = sheep
	sheep.held = true
	harvest_t = sheep.shear_progress
	shearing = false
	_harvest_repath = 0.0
	_harvest_pathing = false
	moving = true


## 지금 양만 놓는다(체인은 유지). 깎던 진행은 양에 남긴다.
func _release_target() -> void:
	if harvest_target != null and is_instance_valid(harvest_target):
		harvest_target.held = false
		harvest_target.shearing = false
		if harvest_target.wool_ready:
			harvest_target.shear_progress = harvest_t
	harvest_target = null
	harvest_t = 0.0
	shearing = false


## 수확을 완전히 멈춘다(직접 이동·밤·쓰러짐). 체인에서 둘 이상 깎았으면 합계를 알려 준다.
func cancel_harvest() -> void:
	_release_target()
	if harvest_chain and harvest_done_in_chain >= 2 and game != null:
		game.toast("연속 수확 끝 — 양 %d마리" % harvest_done_in_chain, Color(1.0, 0.97, 0.85))
	harvest_chain = false
	harvest_done_in_chain = 0


## 연속 수확의 남은 순서: from 에서 시작해 매번 가장 가까운 털 난 양을 고른다(지금 깎는 양 제외). HUD 번호 표시와 다음 대상 선택이 같이 쓴다.
func harvest_plan(pasture = null, from = null) -> Array:
	var pen = pasture
	if pen == null:
		if harvest_target != null and is_instance_valid(harvest_target):
			pen = harvest_target.pasture
		elif game != null:
			pen = game.world.pasture
	if pen == null:
		return []
	var pos: Vector3 = global_position if from == null else from
	if from == null and harvest_target != null and is_instance_valid(harvest_target):
		pos = harvest_target.global_position
	var left: Array = []
	for s in pen.slots:
		if is_instance_valid(s) and not s.dead and s.wool_ready and s != harvest_target:
			left.append(s)
	var order: Array = []
	while not left.is_empty():
		var best = left[0]
		var best_d := 1e9
		for s in left:
			var d := _flat_dist_between(pos, s.global_position)
			if d < best_d:
				best_d = d
				best = s
		order.append(best)
		left.erase(best)
		pos = best.global_position
	return order


static func _flat_dist_between(a: Vector3, b: Vector3) -> float:
	return ActorUtil.flat_dist(a, b)


## 한 마리를 다 깎은 뒤: 체인이면 다음으로 가장 가까운 털 난 양으로, 없으면 끝.
func _advance_chain(pen) -> void:
	if not harvest_chain:
		return
	var plan := harvest_plan(pen, global_position)
	if plan.is_empty() or game.session.state != 0:
		cancel_harvest()
		moving = false
		return
	_begin_target(plan[0])


## 양 옆의 설 자리: 목장 안쪽이면서 문에서 가까운 쪽의 이동 가능 지점.
func _shear_spot(s) -> Vector3:
	var pen = s.pasture
	var gate: Vector3 = pen.gate_center()
	var best: Vector3 = s.global_position
	var best_d := 1e9
	for dir in [Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0.7, 0, 0.7), Vector3(0.7, 0, -0.7)]:
		var p: Vector3 = s.global_position + dir * 0.6
		if not pen.inside(p, -0.45):
			continue
		var dd := p.distance_to(gate)
		if dd < best_d:
			best_d = dd
			best = p
	var nav := NavigationServer3D.map_get_closest_point(get_world_3d().navigation_map, best)
	nav.y = 0.0
	return nav


func _update_harvest(delta: float) -> void:
	var s = harvest_target
	if game.session.state != 0:
		cancel_harvest()
		moving = false
		return
	if not is_instance_valid(s) or s.dead or not s.wool_ready:
		# 대상이 쓰러졌거나 털이 사라졌으면 체인은 다음 양으로 넘어간다
		var pen = s.pasture if is_instance_valid(s) else game.world.pasture
		_release_target()
		_advance_chain(pen)
		if harvest_target == null:
			moving = false
		return
	var d := _flat_dist(s.global_position)
	# 울타리 너머로 깎지 않도록 목장 안에 들어와 양 옆에 섰을 때만 시작한다
	var in_pen: bool = s.pasture.inside(global_position, 0.0)
	var arrived := in_pen and (d <= Cfg.HARVEST_RANGE or (_harvest_pathing and agent.is_navigation_finished() and d <= 1.3))
	if shearing or arrived:
		moving = false
		shearing = true
		s.held = true
		s.shearing = true
		harvest_t += delta
		var to: Vector3 = s.global_position - global_position
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(to.x, to.z), clampf(delta * 10.0, 0.0, 1.0))
		_shear_fx -= delta
		if _shear_fx <= 0.0:
			_shear_fx = 0.32
			Fx.shear(s.global_position + Vector3(0, 0.55, 0) - to.normalized() * 0.15)
			Sfx.play(self, "shear_loop")
		if harvest_t >= Cfg.HARVEST_TIME:
			s.wool_ready = false
			s.shear_progress = 0.0
			_release_target()
			harvest_done_in_chain += 1
			var wool_id: String = s.wool_card_id()
			game.cards.add(wool_id, 1)
			game.toast("%s +1 (보유 %d)" % ["검은 털" if s.is_black else "양털", game.cards.count_of(wool_id)], Color(0.82, 0.68, 1.0) if s.is_black else Color(1.0, 0.97, 0.85))
			Fx.wool(s.global_position + Vector3(0, 0.6, 0))
			Sfx.play(self, "wool_get")
			_advance_chain(s.pasture)
	else:
		_harvest_repath -= delta
		if _harvest_repath <= 0.0:
			agent.target_position = _shear_spot(s)
			_harvest_repath = 0.3
			_harvest_pathing = true
		moving = true


func _build_shears() -> void:
	# 털 깎는 가위: 평소에는 숨기고 털 깎기 중에만 왼손에 든다
	if _hand_r != null:
		# 파츠 캐릭터: 오른손에 쥐여 팔 동작을 따라가게 한다(손 공간은 모델 배율만큼 커서 그만큼 줄인다).
		shears = B.node(_hand_r, Vector3(0, 0, 0.04), Vector3(-70, 0, 0), "Shears")
	else:
		shears = B.node(body, Vector3(-0.2, 0.42, 0.26), Vector3(-70, 0, 0), "Shears")
	var steel := Mats.solid(Color("d8dcea"), {"rim_strength": 0.6})
	var grip := Mats.solid(Color("8a3a4a"))
	for side: float in [-1.0, 1.0]:
		var blade := B.node(shears, Vector3.ZERO, Vector3(0, 0, side * 12.0), "Blade")
		B.box(blade, Vector3(0.025, 0.2, 0.012), Vector3(0, 0.1, 0), steel)
		B.torus(blade, 0.025, 0.04, Vector3(side * 0.03, -0.04, 0), grip, Vector3(90, 0, 0))
		_shear_blades.append(blade)
	# 손 공간은 모델 배율(witch_north 1.12)만큼 커져 있으므로 같은 세계 크기가 되게 나눈다.
	shears.scale = Vector3.ONE * (1.6 if _hand_r == null else 1.6 / 1.12)
	shears.visible = false


func _physics_process(delta: float) -> void:
	if dead:
		return
	claw_cd = maxf(claw_cd - delta, 0.0)
	pounce_cd = maxf(pounce_cd - delta, 0.0)
	lightning_cd = maxf(lightning_cd - delta, 0.0)
	if suffering > 0.0:
		# 늑대의 피: 괴로워하는 동안 입력·공격을 모두 무시한다
		suffering = maxf(suffering - delta, 0.0)
		velocity = Vector3.ZERO
		_animate_suffer(delta)
		return
	if pounce_t > 0.0:
		_update_pounce(delta)
		if wolf_visual != null:
			wolf_visual.speed = 0.0
		return
	if claw_t > 0.0:
		_update_claw(delta)
		velocity = Vector3.ZERO
		_animate(delta, false)
		return
	var vel := Vector3.ZERO
	var stick := Input.get_vector("walk_left","walk_right","walk_up","walk_down") if game.movement_input_allowed() else Vector2.ZERO
	if stick.length_squared() > 0.01:
		cancel_harvest()
		_drop_attack()
		moving = false
		vel = _keyboard_velocity(stick,delta)
	elif harvest_target != null:
		_update_harvest(delta)
	if moving:
		if agent.is_navigation_finished():
			moving = false
		else:
			var next := agent.get_next_path_position()
			var d := next - global_position
			d.y = 0.0
			if d.length() > 0.02:
				vel = d.normalized() * move_speed()
	velocity = vel + SoftSep.push(self)
	move_and_slide()
	global_position.y = 0.0
	if vel.length() > 0.1:
		var yaw := atan2(vel.x, vel.z)
		visual.rotation.y = lerp_angle(visual.rotation.y, yaw, clampf(delta * 12.0, 0.0, 1.0))
	_update_attack(delta)
	_animate(delta, vel.length() > 0.1)


func _keyboard_velocity(stick: Vector2, delta: float) -> Vector3:
	var cam: Camera3D = game.world.camera
	var right := cam.global_basis.x
	var down := cam.global_basis.z
	right.y = 0.0
	down.y = 0.0
	var direction := (right.normalized()*stick.x + down.normalized()*stick.y).limit_length(1.0)
	var desired := Layout.clamp_to_map(global_position + direction*move_speed()*delta)
	var nav_map := get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) == 0: return Vector3.ZERO
	var closest := NavigationServer3D.map_get_closest_point(nav_map,desired)
	closest.y = 0.0
	# Never snap across a gap or an obstacle to another navigation polygon.
	if closest.distance_to(desired) > .3: return Vector3.ZERO
	return ((closest-global_position)/maxf(delta,.001)).limit_length(move_speed())


func _flat_dist(p: Vector3) -> float:
	return ActorUtil.flat_dist(p, global_position)


func _has_los(e: Node3D) -> bool:
	return ActorUtil.has_los(self, e)


## 롤식 평타: 대상이 사거리·시야 안이면 멈춰 서서 선딜(ATTACK_WINDUP) 뒤 발사, 밖이면 다가간다.
## 평타 주기는 선딜 포함 BOLT_INTERVAL. 선딜 중 이동 명령은 평타를 취소하고(쿨다운 소모 없음), 발사 뒤에는 바로 움직일 수 있다.
func _update_attack(delta: float) -> void:
	attack_cd = maxf(attack_cd - delta, 0.0)
	attack_backswing = maxf(attack_backswing - delta, 0.0)
	var rng := attack_range()
	if target_enemy != null and not _alive(target_enemy):
		target_enemy = null
		attack_forced = false
		_cancel_windup()
		if attack_move_active:
			agent.target_position = attack_move_dest
			moving = true
	if target_enemy != null and attack_move_active and not attack_forced and attack_windup <= 0.0 \
			and _edge_dist(target_enemy) > rng + ATTACK_MOVE_ACQUIRE + 3.0:
		# 공격 이동 중 잡은 적이 멀리 달아나면 놓고 목적지로 돌아간다
		target_enemy = null
		agent.target_position = attack_move_dest
		moving = true
	if target_enemy == null:
		if attack_move_active:
			target_enemy = _nearest_enemy(rng + ATTACK_MOVE_ACQUIRE)
			if target_enemy == null and not moving:
				attack_move_active = false
		elif not moving and harvest_target == null:
			target_enemy = _nearest_enemy(rng)
	if target_enemy == null:
		return
	var e = target_enemy
	var to: Vector3 = e.global_position - global_position
	if attack_windup > 0.0:
		visual.rotation.y = lerp_angle(visual.rotation.y, atan2(to.x, to.z), clampf(delta * 20.0, 0.0, 1.0))
		attack_windup -= delta
		if attack_windup <= 0.0:
			attack_windup = 0.0
			if wolf:
				_bite(e)
			else:
				_fire(e)
			attack_cd = maxf(attack_interval() - windup_time(), 0.0)
			attack_backswing = ATTACK_BACKSWING
		return
	if _edge_dist(e) <= rng and _has_los(e):
		moving = false
		agent.target_position = global_position
		if attack_cd <= 0.0:
			attack_windup = windup_time()
		return
	if not attack_forced and not attack_move_active:
		# 서 있다가 스스로 잡은 대상은 사거리 밖으로 나가면 놓는다(쫓아가지 않음)
		target_enemy = null
		return
	_chase_repath -= delta
	if _chase_repath <= 0.0 or not moving:
		_chase_repath = 0.2
		agent.target_position = Layout.clamp_to_map(e.global_position)
		moving = true


func _nearest_enemy(radius: float):
	var best = null
	var best_d := radius
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead:
			continue
		var d := _edge_dist(e)
		if d <= best_d and _has_los(e):
			best = e
			best_d = d
	return best


func _fire(e) -> void:
	# 서리 여왕의 왕관(docs/legend-cards-v01.md): 마법탄 대신 꿰뚫는 얼음창
	var bolt = IceLanceScript.new() if game != null and game.get("legend") != null and game.legend.frost_queen() else BoltScript.new()
	if bolt is IceLanceScript:
		var ls: Dictionary = game.legend.lance_stats()
		bolt.pierce = ls["pierce"]
		bolt.slow = ls["slow"]
		bolt.slow_time = ls["slow_time"]
		bolt.reach = attack_range() + 2.0
	bolt.target = e
	bolt.caster = self
	if game.get("chapter") != null and game.chapter != null:
		bolt.lifesteal = game.chapter.lifesteal()
	if game.relics != null:
		bolt.damage = game.relics.bolt_damage()
	if game.get("equipment") != null and game.equipment != null:
		bolt.damage *= game.equipment.damage_mult(self)
	game.actors.add_child(bolt)
	bolt.global_position = staff_tip.global_position
	Fx.cast(staff_tip.global_position, global_position)
	game.sounds.play("magic_bolt")
	_cast_t = 0.3
	shots_fired += 1
	var to: Vector3 = e.global_position - global_position
	visual.rotation.y = atan2(to.x, to.z)


func _animate(delta: float, walking: bool) -> void:
	_anim_t += delta * (10.0 if walking else 2.2)
	if wolf:
		# 늑대: 모션은 wolf_visual이 맡는다(속도만 넣는다). 선딜 중엔 대상 쪽으로 몸을 낮춘다
		shears.visible = false
		wolf_visual.speed = velocity.length() if walking else 0.0
		if wolf_visual.has_method("set_windup"):
			wolf_visual.set_windup(1.0 - attack_windup / windup_time() if attack_windup > 0.0 else 0.0)
		return
	if rig:
		if shearing: rig.play("work")
		elif attack_windup > 0.0:
			rig.play("windup")
			rig.amount = 1.0 - attack_windup / ATTACK_WINDUP
		elif _cast_t > 0.0: rig.play("cast")
		else: rig.play("walk" if walking else "idle")
	shears.visible = shearing
	if shearing:
		# 털 깎기: 양 쪽으로 몸을 숙이고 가위를 빠르게 여닫는다
		var k := sin(harvest_t * 18.0)
		body.position.y = -0.06 + absf(sin(harvest_t * 9.0)) * 0.015
		body.rotation.x = 0.32
		body.rotation.z = sin(harvest_t * 4.0) * 0.05
		body.scale = Vector3.ONE
		_shear_blades[0].rotation_degrees.z = -6.0 - k * 10.0
		_shear_blades[1].rotation_degrees.z = 6.0 + k * 10.0
		shears.position.z = 0.26 + sin(harvest_t * 6.0) * 0.04
		staff.rotation_degrees.x = 30.0
		return
	body.rotation.x = 0.0
	if walking:
		body.position.y = absf(sin(_anim_t)) * 0.06
		body.rotation.z = sin(_anim_t) * 0.06
	else:
		body.position.y = 0.0
		body.rotation.z = 0.0
		body.scale = Vector3(1.0, 1.0 + sin(_anim_t) * 0.015, 1.0)
	if attack_windup > 0.0:
		# 선딜: 지팡이를 뒤로 들어 올린다(다 들면 발사)
		staff.rotation_degrees.x = 8.0 + 42.0 * (1.0 - attack_windup / ATTACK_WINDUP)
	elif _cast_t > 0.0:
		_cast_t -= delta
		staff.rotation_degrees.x = 8.0 - 50.0 * sin(clampf(_cast_t / 0.3, 0.0, 1.0) * PI)
	else:
		staff.rotation_degrees.x = 8.0


func take_damage(amount: float) -> void:
	if dead:
		return
	if game.get("equipment") != null and game.equipment != null:
		amount *= game.equipment.taken_mult(self)
	hp = maxf(hp - amount, 0.0)
	if hp <= 0.0 and game.get("chapter") != null and game.chapter != null and game.chapter.try_ward(self):
		hp = 1.0  # 수의: 치명타를 한 번 버틴다
	Fx.flash(visual)
	Fx.hit(global_position + Vector3(0, 0.9, 0), Color(1.0, 0.35, 0.4))
	Sfx.play(self, "animal_hurt" if wolf else "witch_hurt")
	if wolf and wolf_visual != null:
		wolf_visual.hurt()
	Fx.damage_number(get_parent(), global_position + Vector3(0, 2.2, 0), amount, Color(1.0, 0.4, 0.4))
	if hp <= 0.0:
		dead = true
		cancel_harvest()
		pounce_t = 0.0
		claw_t = 0.0
		suffering = 0.0
		velocity = Vector3.ZERO
		visual.rotation_degrees.x = -80.0
		Sfx.play(self, "witch_down")
		game.session.report_defeat("마녀가 쓰러졌습니다")


## 카드 비용으로 체력을 치른다(독버섯). 치명적인 비용은 판정에서 막으므로 여기서는 죽지 않는다.
func pay_hp(amount: float) -> float:
	if dead:
		return 0.0
	var paid := minf(amount, maxf(hp - 1.0, 0.0))
	hp -= paid
	Fx.flash(visual)
	Fx.damage_number(get_parent(), global_position + Vector3(0, 2.2, 0), paid, Color(0.75, 0.5, 0.95))
	Sfx.play(self, "witch_hurt")
	return paid


func heal(amount: float) -> float:
	var actual := minf(amount, max_hp - hp)
	hp += actual
	if actual > 0.0:
		Fx.heal(global_position + Vector3(0, 0.8, 0))
		Sfx.play(self, "witch_heal")
	return actual
