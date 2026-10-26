extends Node3D
## 카드·적 행동 연출(표시 전용). 판정은 이미 battle.gd 가 끝냈고, 여기서는 동작 → 투사체 → 맞는 순간 hit(unit_id) 호출만 한다.
## 효과는 모두 마녀산장 모듈: Fx(베기·타격·마법 섬광·혜성 머리·연기·축하), RibbonTrail(투사체 꼬리), LightningVfx(번개 창),
## FrostRuneVfx(서리 룬), 효과음 뱅크(Sfx). 사용: await vfx.play_card(...), await vfx.play_enemy(...)

const Fx := preload("res://scripts/visual/fx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const Ribbon := preload("res://scripts/visual/vfx/ribbon_trail.gd")
const Lightning := preload("res://scripts/visual/vfx/lightning_vfx.gd")
const FrostVfx := preload("res://scripts/visual/vfx/frost_rune_vfx.gd")
const Pool := preload("res://scripts/visual/vfx/vfx_pool.gd")
const D := preload("res://dungeon/data/defs.gd")

const C_ARROW := Color(1.0, 0.82, 0.45)
const C_FIRE := Color(1.0, 0.55, 0.18)
const C_FROST := Color(0.62, 0.86, 1.0)
const C_ELEC := Color(0.45, 0.85, 1.0)
const C_STEEL := Color(1.0, 0.92, 0.65)
const C_BLOCK := Color(0.45, 0.78, 1.0)

var world      # forest_world.gd


class Projectile extends Node3D:
	## 한 점에서 다른 점으로 정해진 시간에 날아가는 투사체(직선 + 위로 볼록한 호). 도착하면 landed.
	signal landed
	var from := Vector3.ZERO
	var to := Vector3.ZERO
	var flight := 0.4
	var arc := 0.6
	var look := "arrow"      # arrow · fire_arrow · bolt · bone · rain
	var spin := 0.0
	var _t := 0.0
	var _shaft: Node3D

	func _ready() -> void:
		global_position = from
		match look:
			"arrow", "fire_arrow", "rain":
				_shaft = B.node(self, Vector3.ZERO, Vector3(0, 180, 0), "Shaft")
				B.cyl(_shaft, 0.014, 0.014, 0.6, Vector3.ZERO, Mats.solid(Color("d8d2c0")), 5, Vector3(90, 0, 0))
				B.cyl(_shaft, 0.0, 0.035, 0.09, Vector3(0, 0, 0.33), Mats.solid(Color("aeb4c4")), 5, Vector3(90, 0, 0))
				B.box(_shaft, Vector3(0.07, 0.012, 0.09), Vector3(0, 0, -0.27), Mats.solid(Color("c9565a")))
				var tail := B.node(self, Vector3(0, 0, 0.22), Vector3.ZERO, "Tail")
				if look == "fire_arrow":
					B.sphere(self, 0.12, Vector3.ZERO, Mats.glow(Color(1.0, 0.6, 0.2), 5.0), Vector3.ONE, 8, 4)
					B.omni(self, Vector3.ZERO, Color(1.0, 0.55, 0.2), 1.6, 3.0)
					Ribbon.follow(get_parent(), tail, Color(1.0, 0.45, 0.12), Color(1.0, 0.95, 0.75), 0.22, 0.4, 2.0)
				else:
					Ribbon.follow(get_parent(), tail, Color(1.0, 0.82, 0.45), Color(1.0, 0.98, 0.9), 0.09, 0.26, 1.4)
			"bolt":
				var core := B.sphere(self, 0.1, Vector3.ZERO, Mats.glow(Color(0.95, 0.8, 1.0), 7.0), Vector3.ONE, 8, 4)
				core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				B.omni(self, Vector3.ZERO, Color(0.8, 0.55, 1.0), 1.4, 2.8)
				Ribbon.follow(get_parent(), self, Color(0.62, 0.3, 1.0), Color(1.0, 0.9, 1.0), 0.3, 0.3, 1.7)
			"bone":
				_shaft = B.node(self, Vector3.ZERO, Vector3.ZERO, "Bone")
				B.cyl(_shaft, 0.03, 0.03, 0.34, Vector3.ZERO, Mats.solid(Color("e6dcc4")), 6, Vector3(0, 0, 90))
				B.sphere(_shaft, 0.05, Vector3(0.17, 0, 0), Mats.solid(Color("e6dcc4")), Vector3.ONE, 6, 4)
				B.sphere(_shaft, 0.05, Vector3(-0.17, 0, 0), Mats.solid(Color("e6dcc4")), Vector3.ONE, 6, 4)
		for c in find_children("*", "GeometryInstance3D", true, false):
			c.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	func _process(delta: float) -> void:
		_t += delta
		var u := clampf(_t / flight, 0.0, 1.0)
		var prev := global_position
		global_position = from.lerp(to, u) + Vector3(0, arc * 4.0 * u * (1.0 - u), 0)
		var vel := global_position - prev
		if look == "bone":
			_shaft.rotation.z += delta * 18.0
		elif vel.length() > 0.0005:
			look_at(global_position + vel, Vector3.UP if absf(vel.normalized().y) < 0.98 else Vector3.RIGHT)
		if look == "bolt" and delta > 0.0:
			Fx.comet_head(global_position, vel / delta, Fx.C_MAGIC, 0.9)
		if u >= 1.0:
			landed.emit()
			queue_free()


func _shoot(from: Vector3, to: Vector3, look: String, speed: float, arc: float) -> Projectile:
	var p := Projectile.new()
	p.from = from
	p.to = to
	p.look = look
	p.flight = clampf(from.distance_to(to) / speed, 0.18, 1.2)
	p.arc = arc
	add_child(p)
	return p


## 돌진: 대상 바로 앞(덩치만큼 떨어진 자리)까지 내달린다.
func _rush(who, target) -> void:
	var from: Vector3 = who.global_position
	var dir: Vector3 = target.global_position - from
	dir.y = 0.0
	var gap := 1.0 + 0.35 * (float(who.visual.scale.x) + float(target.visual.scale.x))
	var to: Vector3 = target.global_position - dir.normalized() * gap
	if from.distance_to(to) < 0.3:
		return
	await who.dash(to, clampf(from.distance_to(to) / 22.0, 0.12, 0.3))


func _return(who, home: Vector3) -> void:
	if who.global_position.distance_to(home) < 0.1:
		return
	await who.dash(home, 0.22)
	who.face(who.facing)


func _wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


# ───────────────────────── 아군 카드 ─────────────────────────

## card_id 연출. caster: unit_view, center: 겨눈 칸의 세계 좌표, targets: 맞는 순서의 unit_view 목록,
## cells: 효과 칸의 세계 좌표, hit: Callable(unit_id) — 그 유닛이 맞는 순간 부른다(피해 숫자·막대·움찔은 main 이).
## allies: 이 카드로 뭔가 받은(방어·회복) 아군 unit_view 목록. 연출 종류는 카드의 vfx(없으면 카드 id).
func play_card(card_id: String, caster, center: Vector3, targets: Array, cells: Array, hit: Callable, block_fx: Callable, allies: Array = []) -> void:
	var card := D.card(card_id)
	var style := String(card.get("vfx", card_id))
	match style:
		"slash", "shield_bash":
			# 근접: 적 바로 앞까지 순식간에 내달려 치고 제자리로 돌아온다. 대상이 여럿(돌파)이면 한 번 휘둘러 모두 벤다
			var t = targets[0]
			var home: Vector3 = caster.global_position
			await _rush(caster, t)
			var imp: float = caster.attack("slash" if style == "slash" else "stab", t.global_position)
			Sfx.play(caster, "ally_attack")
			await _wait(imp)
			var big: bool = int(card.get("damage", 0)) >= 10 or targets.size() > 1
			for k in targets.size():
				var tk = targets[k]
				if style == "slash":
					Fx.slash(tk.chest(), tk.global_position - home, C_STEEL)
					if big:
						Fx.hit(tk.chest(), C_STEEL, true)
				else:
					Fx.hit(tk.chest(), C_STEEL, true)
					Fx.slash(tk.chest(), tk.global_position - home, Color(0.8, 0.9, 1.0))
				hit.call(tk.unit_id)
				if k < targets.size() - 1:
					await _wait(0.07)
			world.shake(0.18 if (style != "slash" or big) else 0.1, 0.25)
			Sfx.play(caster, "mon_hit" if style == "slash" else "lodge_hit")
			if style != "slash":
				block_fx.call()
			await _wait(0.22)
			await _return(caster, home)
		"guard":
			# 자신을 지키는 즉시 카드(철벽·재기): 방패를 세우듯 한 번 들이받는 자세 + 푸른 고리
			var imp: float = caster.attack("stab", caster.global_position + caster.facing)
			await _wait(imp * 0.6)
			Sfx.play_or(caster, "lodge_repair", "purify")
			var P = Fx._p()
			if P != null:
				for k in 2:
					P.emit(Pool.RING, caster.global_position + Vector3(0, 0.08, 0), Vector3.ZERO, 0.5 + k * 0.1, 0.6, Color(0.45, 0.78, 1.0, 0.9),
						{"ground": true, "additive": true, "grow": 4.0 + k})
			Fx.hit(caster.chest(), C_BLOCK)
			block_fx.call()
			hit.call(caster.unit_id)
			await _wait(0.45)
		"bless":
			# 아군 모두에게 걸리는 마법(보호막·치유): 시전 → 모두의 발밑에서 빛이 솟는다
			var imp: float = caster.attack("cast", caster.global_position + caster.facing)
			await _wait(imp)
			Fx.cast(caster.tip_pos(), caster.global_position, Color(0.75, 1.0, 0.8) if card.has("heal_all") else C_BLOCK)
			Sfx.play_or(caster, "purify", "moon_cast")
			await _wait(0.15)
			block_fx.call()
			for a in allies:
				Fx.hit(a.chest(), Color(0.6, 1.0, 0.7) if card.has("heal_all") else C_BLOCK)
				Fx.summon(a.global_position, Color(0.7, 1.0, 0.75) if card.has("heal_all") else C_BLOCK)
				hit.call(a.unit_id)
				await _wait(0.08)
			await _wait(0.5)
		"fireball":
			# 불덩이가 겨눈 칸으로 날아가 터진다(화염구·운석)
			var big: bool = int(card.get("damage", 0)) >= 12
			var imp: float = caster.attack("cast", center)
			await _wait(imp)
			Fx.cast(caster.tip_pos(), caster.global_position, C_FIRE)
			Sfx.play(caster, "magic_bolt")
			var from: Vector3 = caster.tip_pos() + (Vector3(0, 7.0, 0) if big else Vector3.ZERO)
			var p := _shoot(from, center + Vector3(0, 0.3, 0), "fire_arrow", 12.0 if big else 15.0, 0.2 if big else 1.6)
			await p.landed
			Fx.explosion(self, center, 2.4 if big else 1.7)
			Sfx.play_or(caster, "fireball_boom", "lodge_hit")
			world.shake(0.4 if big else 0.22, 0.45 if big else 0.3)
			for t in targets:
				Fx.hit(t.chest(), C_FIRE, true)
				hit.call(t.unit_id)
			await _wait(0.55)
		"war_cry":
			# 적진 앞으로 뛰어들어 내려찍고 돌아온다
			var home: Vector3 = caster.global_position
			await caster.dash(home + caster.facing.normalized() * 1.6, 0.16)
			var imp: float = caster.attack("slash", caster.global_position + caster.facing)
			Sfx.play(caster, "boss_roar")
			await _wait(imp)
			Fx.celebrate(caster.global_position, Color(1.0, 0.66, 0.3), 1.6)
			var P = Fx._p()
			if P != null:
				for k in 3:
					P.emit(Pool.RING, caster.global_position + Vector3(0, 0.08, 0), Vector3.ZERO, 0.55 + k * 0.12, 0.8, Color(1.0, 0.6, 0.25, 0.9),
						{"ground": true, "additive": true, "grow": 5.5 + k * 1.5})
			world.shake(0.22, 0.4)
			block_fx.call()
			for t in targets:
				hit.call(t.unit_id)
				Fx.hit(t.chest(), Color(1.0, 0.6, 0.25))
			await _wait(0.3)
			await _return(caster, home)
		"aimed_shot":
			# 화살 한 대(hits 가 2면 연달아 두 대). 저격처럼 큰 피해는 크게 맞는다
			var t = targets[0]
			var shots := int(card.get("hits", 1))
			var big: bool = int(card.get("damage", 0)) >= 12
			for k in shots:
				var imp: float = caster.attack("draw", t.global_position)
				await _wait(imp if k == 0 else imp * 0.6)
				Sfx.play_or(caster, "bow_shot", "ally_attack")
				var p := _shoot(caster.tip_pos(), t.chest(), "arrow", 34.0 if big else 26.0, 0.2 if big else 0.5)
				await p.landed
				Fx.hit(t.chest(), C_ARROW, big)
				if big:
					world.shake(0.2, 0.25)
				hit.call(t.unit_id)
				Sfx.play_or(caster, "arrow_hit", "bolt_hit")
			await _wait(0.25)
		"piercing_arrow":
			# 불붙은 화살이 줄을 끝까지 꿰뚫는다: 줄의 적을 지나는 순간마다 맞는다
			var dir: Vector3 = (center - caster.global_position)
			dir.y = 0.0
			var end: Vector3 = cells[-1] + dir.normalized() * 3.0 + Vector3(0, 0.9, 0)
			var imp: float = caster.attack("draw", center)
			await _wait(imp)
			Sfx.play_or(caster, "bow_shot", "ally_attack")
			var from: Vector3 = caster.tip_pos()
			var p := _shoot(from, end, "fire_arrow", 30.0, 0.0)
			var total := from.distance_to(end)
			for t in targets:
				var at: float = from.distance_to(t.chest()) / total * p.flight
				get_tree().create_timer(at).timeout.connect(func() -> void:
					Fx.hit(t.chest(), C_FIRE, true)
					hit.call(t.unit_id)
					Sfx.play_or(caster, "arrow_hit", "bolt_hit"))
			await p.landed
			Fx.poof(end, Color(1.0, 0.6, 0.3), 0.5)
			await _wait(0.2)
		"arrow_rain":
			var imp: float = caster.attack("draw", center)
			await _wait(imp)
			Sfx.play_or(caster, "bow_shot", "ally_attack")
			# 하늘로 한 대 → 잠시 뒤 범위 칸마다 화살이 쏟아진다
			_shoot(caster.tip_pos(), caster.tip_pos() + Vector3(0, 9, 0) + (center - caster.global_position) * 0.3, "arrow", 30.0, 0.0)
			await _wait(0.45)
			for c in cells:
				for k in 3:
					var land: Vector3 = c + Vector3(randf_range(-0.7, 0.7), 0.05, randf_range(-0.7, 0.7))
					var p := _shoot(land + Vector3(randf_range(-1.5, -0.5), 8.0, randf_range(0.5, 1.5)), land, "rain", 22.0, 0.0)
					p._t = -randf_range(0.0, 0.35)
					p.landed.connect(func() -> void: Fx.snow_kick(land, Vector3.UP, 2, 0.8))
			await _wait(0.55)
			world.shake(0.12, 0.35)
			for t in targets:
				Fx.hit(t.chest(), C_ARROW, true)
				hit.call(t.unit_id)
			Sfx.play_or(caster, "arrow_hit", "bolt_hit")
			await _wait(0.4)
		"magic_bolt":
			var t = targets[0]
			var frost: bool = card.get("freeze", false)
			var imp: float = caster.attack("cast", t.global_position)
			await _wait(imp)
			Fx.cast(caster.tip_pos(), caster.global_position, C_FROST if frost else Fx.C_MAGIC)
			Sfx.play(caster, "magic_bolt")
			var p := _shoot(caster.tip_pos(), t.chest(), "bolt", 16.0, 0.4)
			await p.landed
			Fx.hit(t.chest(), C_FROST if frost else Fx.C_MAGIC)
			hit.call(t.unit_id)
			Sfx.play(caster, "frost_burst" if frost else "bolt_hit")
			await _wait(0.25)
		"frost_rune":
			var imp: float = caster.attack("cast", center)
			await _wait(imp)
			Fx.cast(caster.tip_pos(), caster.global_position, C_FROST)
			var rune := FrostVfx.new()
			rune.radius = 2.9
			add_child(rune)
			rune.global_position = Vector3(center.x, 0.02, center.z)
			Sfx.play(caster, "frost_burst")
			world.shake(0.12, 0.25)
			await _wait(0.12)
			for t in targets:
				Fx.hit(t.chest(), C_FROST)
				rune.encase(t.global_position)
				hit.call(t.unit_id)
			await _wait(0.6)
		"chain_lightning":
			var imp: float = caster.attack("cast", targets[0].global_position)
			await _wait(imp)
			Fx.cast(caster.tip_pos(), caster.global_position, C_ELEC)
			var from: Vector3 = caster.tip_pos()
			for t in targets:
				var to: Vector3 = t.chest()
				Lightning.lance(self, from, to, [to])
				Sfx.play(caster, "lightning_strike")
				world.shake(0.14, 0.2)
				await _wait(Lightning.hit_delay(0, 1.0))
				hit.call(t.unit_id)
				await _wait(0.12)
				from = to
			await _wait(0.4)
		_:
			for t in targets:
				hit.call(t.unit_id)


# ───────────────────────── 적 행동 ─────────────────────────

## 적 행동 연출. action: attack · roar · move(걷기는 main 이 따로) · frozen
func play_enemy(kind: String, e, target, action: String, hit: Callable, allies: Array) -> void:
	match action:
		"attack":
			if kind == "thrower":
				var imp: float = e.attack("throw", target.global_position)
				await _wait(imp)
				Sfx.play_or(e, "mon_attack", "ally_attack")
				var p := _shoot(e.tip_pos(), target.chest(), "bone", 14.0, 1.4)
				await p.landed
				Fx.hit(target.chest(), Color(1.0, 0.9, 0.75))
				hit.call(target.unit_id)
				Sfx.play(e, "ally_hurt")
			else:
				# 근접: 대상 앞까지 내달려 휘두른 뒤 제자리로
				var home: Vector3 = e.global_position
				await _rush(e, target)
				var imp: float = e.attack("slash", target.global_position)
				Sfx.play(e, "mon_attack")
				await _wait(imp)
				var big := kind in ["orc", "chief"]
				Fx.slash(target.chest(), target.global_position - home, Color(1.0, 0.55, 0.45))
				if big:
					Fx.hit(target.chest(), Color(1.0, 0.45, 0.35), true)
				world.shake(0.2 if big else 0.1, 0.25)
				hit.call(target.unit_id)
				Sfx.play(e, "ally_hurt")
				await _wait(0.2)
				await _return(e, home)
		"roar":
			var imp: float = e.attack("slash", e.global_position + e.facing)
			Sfx.play(e, "boss_roar")
			await _wait(imp)
			var P = Fx._p()
			if P != null:
				for k in 3:
					P.emit(Pool.RING, e.global_position + Vector3(0, 0.08, 0), Vector3.ZERO, 0.6 + k * 0.15, 0.9, Color(0.95, 0.25, 0.3, 0.9),
						{"ground": true, "additive": true, "grow": 9.0 + k * 2.0})
			world.shake(0.35, 0.6)
			await _wait(0.25)
			for a in allies:
				Fx.hit(a.chest(), Color(1.0, 0.35, 0.3))
				hit.call(a.unit_id)
			await _wait(0.5)
		"frozen":
			Fx.hit(e.chest(), C_FROST)
			Sfx.play(e, "slow_apply")
			await _wait(0.45)
		_:
			await _wait(0.1)
