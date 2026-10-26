extends Node3D
## 숲길 원정대 진행: 원정대 고르기 → 숲길 행군 → 방 전투(카드·이동·적 턴) → 적 전멸 시 좁은 길로 자동 이동 → … → 승패.
## 판정은 core/battle.gd(사건 목록), 화면은 view/*. 이 파일은 둘을 잇고 입력을 받는다.

const D := preload("res://dungeon/data/defs.gd")
const Battle := preload("res://dungeon/core/battle.gd")
const ForestWorld := preload("res://dungeon/view/forest_world.gd")
const UnitView := preload("res://dungeon/view/unit_view.gd")
const Hand := preload("res://dungeon/view/hand.gd")
const Hud := preload("res://dungeon/view/hud.gd")
const CardVfx := preload("res://dungeon/view/card_vfx.gd")
const SoundBank := preload("res://scripts/audio/sound_bank.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const WindowMode := preload("res://scripts/visual/window_mode.gd")   # 마녀산장 화면 모드: 처음엔 테두리 없는 전체 화면, F11 전환

const HITSTOP_SCALE := 0.04      # 히트스탑 동안의 시간 배율

const C_TARGETABLE := Color(1.0, 0.86, 0.45, 0.45)
const C_AREA := Color(1.0, 0.38, 0.28, 0.95)
const C_ALLY_PICK := Color(1.0, 0.85, 0.45, 0.8)
const DRAG_START := 12.0
const RUN_SPEED := 12.5          # 방 사이 이동: 뛰어서
const RUN_GAP := 0.16            # 줄지어 출발하는 간격(초)

var sounds                      # SoundBank(Sfx.play 가 current_scene.sounds 로 찾는다)
var world: Node3D
var vfx: Node3D
var battle: Battle
var hand: Control
var hud: Control
var views: Dictionary = {}      # unit id → UnitView
var disp: Dictionary = {}       # unit id → 화면에 보이는 값(연출이 따라잡기 전까지 battle 과 다를 수 있다)
var mode := "select"            # select · walk · battle · result
var busy := false
var room := 0
var target_card := ""
var hover_cell := Vector2i(-1, -1)
var _press_card := ""
var _press_pos := Vector2.ZERO
var _pressing := false
var _music: Array = []          # AudioStreamPlayer 두 개(교차 페이드)
var _music_event := ""
var _hover_enemy := 0
var _spot_key := ""             # 지금 강조 중인 카드(바뀔 때만 다시 건다)
var _hitstop_end := 0           # 히트스탑이 끝나는 실제 시각(msec)
var _hitstop_on := false
var _hitstop_base := 1.0        # 히트스탑 전 시간 배율(검증 도구는 4배속으로 돈다)


func _ready() -> void:
	sounds = SoundBank.new()
	add_child(sounds)
	add_child(WindowMode.new())
	world = ForestWorld.new()
	world.name = "World"
	add_child(world)
	world.build()
	vfx = CardVfx.new()
	vfx.world = world
	add_child(vfx)
	var ui := CanvasLayer.new()
	ui.layer = 5
	add_child(ui)
	hud = Hud.new()
	ui.add_child(hud)
	hand = Hand.new()
	ui.add_child(hand)
	hud.end_turn_pressed.connect(_on_end_turn)
	hud.start_pressed.connect(_start)
	hud.restart_pressed.connect(_restart)
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.bus = "Music"
		p.volume_db = -60.0
		add_child(p)
		_music.append(p)
	hud.set_battle_ui(false)
	# 타이틀 뒤 배경: 첫 방 앞 숲길
	world.focus_on(world.entry_path[2] + ForestWorld.CAM_FOCUS_OFFSET, true)
	_play_music("bgm_field")
	if "--autostart" in OS.get_cmdline_user_args():
		_start(D.HERO_ORDER.duplicate())
	else:
		hud.show_select(hand.hero_face)


# ───────────────────────── 흐름 ─────────────────────────

func _start(heroes: Array) -> void:
	battle = Battle.new()
	battle.setup_party(heroes)
	hud.build_panels(heroes)
	hud.set_room(0, D.ROOMS.size(), String(D.ROOMS[0].name))
	var start: Vector3 = world.entry_path[0]
	var k := 0
	for u in battle.allies(true):
		var v := _spawn_view(u)
		v.global_position = start - world.lane * (k * 1.6)
		k += 1
	battle.enter_room(0)
	room = 0
	_spawn_enemies()
	_march(world.entry_path)


func _restart() -> void:
	for id in views.keys():
		views[id].queue_free()
	views.clear()
	disp.clear()
	hud.clear_bars()
	hand.clear_all()
	for i in world.rooms.size():
		world.clear_cells(i)
		world.set_board_reveal(i, 0.0)
	world.focus_on(world.entry_path[2] + ForestWorld.CAM_FOCUS_OFFSET, true)
	world.set_zoom(ForestWorld.CAM_HEIGHT, true)
	hud.set_battle_ui(false)
	mode = "select"
	_play_music("bgm_field")
	hud.show_select(hand.hero_face)


func _spawn_view(u) -> Node3D:
	var v: Node3D = UnitView.new()
	add_child(v)
	v.setup(u.kind, u.team, u.id, world.lane if u.team == "ally" else -world.lane)
	v.breath = world.breath
	v.weather = world.weather
	views[u.id] = v
	disp[u.id] = _snapshot(u)
	hud.add_bar(u.id, u.team)
	return v


func _snapshot(u) -> Dictionary:
	return {"id": u.id, "hp": u.hp, "max_hp": u.max_hp, "block": u.block, "mark": u.mark, "frozen": u.frozen, "taunt": u.taunt}


func _spawn_enemies() -> void:
	for e in battle.enemies():
		var v := _spawn_view(e)
		v.global_position = world.cell_pos(room, e.cell)


## 원정대가 경로(점 목록)를 줄지어 걸어 이번 방의 자기 칸으로 간다. 다 오면 전투 시작.
func _march(path: Array) -> void:
	mode = "walk"
	hud.set_battle_ui(false)
	hud.hint("")
	_play_music("bgm_field")
	world.set_zoom(ForestWorld.CAM_HEIGHT, false, 1.6)
	var allies := battle.allies(true)
	var left := [allies.size()]
	for k in allies.size():
		var u = allies[k]
		var v: Node3D = views[u.id]
		var route: Array = [v.global_position]
		route.append_array(path)
		route.append(world.cell_pos(room, u.cell))
		var delay := k * RUN_GAP
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			v.run(route.slice(1), RUN_SPEED))
		v.arrived.connect(func() -> void:
			left[0] -= 1
			if left[0] == 0:
				_begin_room(), CONNECT_ONE_SHOT)


func _begin_room() -> void:
	mode = "battle"
	hud.set_room(room, D.ROOMS.size(), String(D.ROOMS[room].name))
	world.focus_on(world.room_focus(room), false, 2.4)
	world.set_zoom(ForestWorld.CAM_HEIGHT_BATTLE, false, 1.8)
	var this_room := room
	var tw := create_tween()
	tw.tween_method(func(x: float) -> void: world.set_board_reveal(this_room, x), 0.0, 1.0, 0.9)
	var boss := battle.room_is_boss()
	_play_music("bgm_boss" if boss else "bgm_combat")
	world.set_storm(boss)
	for e in battle.enemies():
		Fx.spawn_portal(views[e.id].global_position)
	if boss:
		# 중간 보스: 붉은 배너 + 울부짖음 + 화면 흔들림
		var b = battle.enemies().filter(func(e): return e.def().get("boss", false))[0]
		Sfx.play(self, "boss_roar")
		world.shake(0.3, 0.7)
		views[b.id].attack("slash", views[b.id].global_position + views[b.id].facing)
		hud.show_banner("중간 보스 · %s" % b.name() if room < D.ROOMS.size() - 1 else "최후의 적 · %s" % b.name(), Color(1.0, 0.45, 0.4), 1.1)
		await get_tree().create_timer(1.2).timeout
	else:
		Sfx.play(self, "wave_start")
		hud.show_banner(String(D.ROOMS[room].name), Color(1.0, 0.86, 0.55), 0.6)
		await get_tree().create_timer(0.4).timeout
	_player_turn()


func _player_turn() -> void:
	battle.begin_player_turn()
	for u in battle.allies():
		disp[u.id] = _snapshot(u)
	hud.set_battle_ui(true)
	hud.set_turn("아군 턴 %d  ·  행동력 %d" % [battle.turn, D.AP_MAX])
	hud.show_banner("아군 턴", Color(1.0, 0.9, 0.6), 0.5)
	hand.deal(battle.hand)
	_refresh()
	hud.hint("카드를 위로 끌어 적에게 놓거나, 눌러 고른 뒤 적을 누르세요")


func _on_end_turn() -> void:
	if mode != "battle" or busy or battle.phase != "player":
		return
	_cancel()
	busy = true
	hud.hint("")
	hud.set_turn("적 턴")
	var ev := battle.end_player_turn()
	await _play_events(ev)
	busy = false
	_after_events()


func _after_events() -> void:
	for id in disp:
		var u = battle.unit(id)
		if u != null:
			disp[id] = _snapshot(u)
	_refresh()
	# 레벨업한 캐릭터가 있으면 순서대로 새 카드를 고른다(고르는 동안 전투는 멈춘다). 전멸했으면 건너뛴다
	while not battle.pending_levelups.is_empty():
		var who = battle.unit(battle.pending_levelups.pop_front())
		if battle.phase != "defeat":
			await _offer_level_up(who)
	match battle.phase:
		"clear":
			_room_cleared()
		"defeat":
			_finish(false)
		"enemy":
			_player_turn()
		"player":
			if battle.total_ap() == 0:
				await get_tree().create_timer(0.35).timeout
				_on_end_turn()


## 레벨업: 그 캐릭터의 pool 에서 셋을 보여 주고, 고른 카드를 덱에 섞어 넣는다.
func _offer_level_up(u) -> void:
	if u == null:
		return
	busy = true
	_cancel()
	var options: Array = battle.level_options(u)
	if options.is_empty():
		busy = false
		return
	if views.has(u.id):
		Fx.celebrate(views[u.id].global_position, D.HEROES[u.kind].color, 1.4)
	hud.show_level_up(u.kind, u.level, options, hand.face)
	var chosen: String = await hud.card_chosen
	battle.add_card(u, chosen)
	Sfx.play_or(self, "card_shuffle", "card_draw")
	hud.show_banner("%s 덱에 [%s] 추가" % [u.name(), String(D.card(chosen).name)], D.HEROES[u.kind].color.lightened(0.3), 0.8)
	await get_tree().create_timer(0.3).timeout
	busy = false
	_refresh()


func _room_cleared() -> void:
	mode = "walk"
	hud.set_battle_ui(false)
	hud.hint("")
	hand.clear_all()
	world.clear_cells(room)
	Sfx.play(self, "wave_clear")
	hud.show_banner("방 정리!", Color(1.0, 0.86, 0.45), 1.0)
	for u in battle.allies():
		Fx.celebrate(views[u.id].global_position, Fx.C_GOLD, 0.8)
	await get_tree().create_timer(0.6).timeout
	if room >= D.ROOMS.size() - 1:
		_finish(true)
		return
	var full := battle.room_is_boss()
	battle.rest_between_rooms(full)
	if full:
		hud.show_banner("모닥불에서 쉬어 간다 · 완전 회복", Color(1.0, 0.8, 0.5), 0.8)
	for u in battle.allies(true):
		var v: Node3D = views[u.id]
		if v.is_dead():
			v.revive()
		disp[u.id] = _snapshot(u)
		Fx.heal(v.global_position)
	Sfx.play(self, "witch_heal")
	var left_room := room
	var tw := create_tween()
	tw.tween_method(func(x: float) -> void: world.set_board_reveal(left_room, x), 1.0, 0.0, 0.6)
	var path: Array = world.paths[room]
	room += 1
	battle.enter_room(room)
	_spawn_enemies()
	_march([world.rooms[room - 1].exit] + path)


func _finish(won: bool) -> void:
	mode = "result"
	hud.set_battle_ui(false)
	hud.hint("")
	Sfx.play(self, "victory" if won else "defeat")
	hud.show_result(won)


# ───────────────────────── 사건 재생 ─────────────────────────

## battle 의 사건 목록을 묶음(카드 사용 / 적 행동)별로 연출한다.
func _play_events(ev: Array) -> void:
	var i := 0
	while i < ev.size():
		var e: Dictionary = ev[i]
		i += 1
		match String(e.type):
			"cast", "enemy":
				var group: Array = []
				while i < ev.size() and not String(ev[i].type) in ["cast", "enemy", "turn", "room_clear", "defeat"]:
					group.append(ev[i])
					i += 1
				if e.type == "cast":
					await _play_cast(e, group)
				else:
					await _play_enemy(e, group)
			"turn":
				if e.side == "enemy":
					hud.show_banner("적 턴", Color(1.0, 0.55, 0.5), 0.5)
					await get_tree().create_timer(0.7).timeout
			_:
				pass


func _by_unit(group: Array) -> Dictionary:
	var out := {}
	for g in group:
		if g.has("unit"):
			if not out.has(g.unit):
				out[g.unit] = []
			out[g.unit].append(g)
	return out


func _play_cast(e: Dictionary, group: Array) -> void:
	var per := _by_unit(group)
	var caster: Node3D = views[e.unit]
	var targets: Array = []
	for id in e.targets:
		if views.has(id):
			targets.append(views[id])
	var cells: Array = []
	for c in e.cells:
		cells.append(world.cell_pos(room, c))
	var center: Vector3 = world.cell_pos(room, e.center) if D.in_board(e.center) else caster.global_position
	var done := {}
	var hit := func(uid: int) -> void:
		if done.has(uid):
			return
		done[uid] = true
		_apply_unit(uid, per.get(uid, []).filter(func(x): return x.type != "block"))
	var block_fx := func() -> void:
		for uid in per:
			for x in per[uid]:
				if x.type == "block":
					_apply_unit(uid, [x])
	var ally_views: Array = []
	for u in battle.allies(true):
		if per.has(u.id) and views.has(u.id):
			ally_views.append(views[u.id])
	world.clear_cells(room)
	await vfx.play_card(String(e.card), caster, center, targets, cells, hit, block_fx, ally_views)
	# 연출이 부르지 않은 나머지(시전자 상태 등)
	for uid in per:
		if not done.has(uid):
			_apply_unit(uid, per[uid].filter(func(x): return x.type != "block" or not _block_shown(uid, x)))
	_refresh()


func _block_shown(uid: int, x: Dictionary) -> bool:
	return int(disp.get(uid, {}).get("block", 0)) >= int(x.total)


func _play_enemy(e: Dictionary, group: Array) -> void:
	var v: Node3D = views.get(e.unit)
	if v == null:
		return
	var per := _by_unit(group)
	world.focus_on(world.room_focus(room) + (v.global_position - world.rooms[room].center) * 0.12, false, 2.0)
	match String(e.action):
		"attack", "roar":
			var target: Node3D = views.get(e.get("target", -1))
			var allies: Array = []
			for u in battle.allies(true):
				if per.has(u.id):
					allies.append(views[u.id])
			var hit := func(uid: int) -> void: _apply_unit(uid, per.get(uid, []))
			await vfx.play_enemy(String(battle.unit(e.unit).kind), v, target, String(e.action), hit, allies)
		"frozen":
			await vfx.play_enemy("", v, null, "frozen", func(_u): pass, [])
			v.set_status("freeze", false)
			disp[e.unit]["frozen"] = false
		_:
			await get_tree().create_timer(0.15).timeout
	_refresh()


## 한 유닛에 떨어진 사건들을 화면에 반영(피해 숫자·막대·움찔·상태·밀림·쓰러짐).
func _apply_unit(uid: int, list: Array) -> void:
	var v: Node3D = views.get(uid)
	if v == null or not is_instance_valid(v):
		return
	var d: Dictionary = disp.get(uid, {})
	for x in list:
		match String(x.type):
			"damage":
				d["hp"] = x.hp
				d["block"] = maxi(0, int(d.get("block", 0)) - int(x.blocked))
				if x.amount > 0:
					Fx.damage_number(world, v.chest() + Vector3(0, 0.6, 0), x.amount,
						Color(1.0, 0.95, 0.55) if v.team == "enemy" else Color(1.0, 0.5, 0.45))
					# 타격감: 피해가 클수록(최대 체력 대비) 세게 — 움찔·넉백·번쩍(unit_view) + 히트스탑·화면 흔들림(여기)
					var ratio: float = float(x.amount) / maxf(float(d.get("max_hp", 20)), 1.0)
					var strength: float = clampf(0.6 + ratio * 2.2 + (0.4 if x.hp <= 0 else 0.0), 0.6, 1.6)
					var src: Node3D = views.get(int(x.get("src", 0)))
					v.hurt(strength, src.global_position if src != null and is_instance_valid(src) else Vector3.INF)
					_hitstop(0.04 + 0.06 * strength)
					world.shake(0.05 + 0.14 * strength, 0.18 + 0.1 * strength)
				if x.blocked > 0:
					Fx.float_text(world, v.chest() + Vector3(0.4, 1.0, 0), "막음 %d" % x.blocked, Color(0.55, 0.82, 1.0))
					if x.amount <= 0:
						Fx.hit(v.chest(), Color(0.45, 0.78, 1.0))
						v.rig.flinch()
			"heal":
				d["hp"] = x.hp
				if x.amount > 0:
					Fx.float_text(world, v.chest() + Vector3(0, 1.0, 0), "+%d" % x.amount, Color(0.6, 1.0, 0.65))
					Fx.heal(v.global_position)
			"xp":
				Fx.float_text(world, v.chest() + Vector3(-0.5, 1.3, 0), "+%d 경험치" % x.amount,
					Color(0.9, 0.75, 1.0) if x.get("killer", false) else Color(0.75, 0.6, 0.95))
			"level_up":
				Sfx.play_or(self, "relic_get", "victory")
				Fx.celebrate(v.global_position, D.HEROES[v.kind].color, 1.2)
				Fx.float_text(world, v.chest() + Vector3(0, 1.8, 0), "레벨 %d!" % x.level, D.HEROES[v.kind].color.lightened(0.3))
			"block":
				d["block"] = x.total
				Fx.float_text(world, v.chest() + Vector3(0, 1.0, 0), "방어 +%d" % x.amount, Color(0.55, 0.82, 1.0))
				Fx.hit(v.chest(), Color(0.45, 0.78, 1.0))
			"status":
				d[{"mark": "mark", "freeze": "frozen", "taunt": "taunt"}[x.status]] = 2 if x.status == "mark" else true
				v.set_status(x.status, true)
			"push":
				if x.bumped:
					var tw := v.create_tween()
					var home: Vector3 = v.global_position
					tw.tween_property(v, "global_position", home + world.lane * 0.35, 0.08)
					tw.tween_property(v, "global_position", home, 0.12)
				else:
					var tw2 := v.create_tween()
					tw2.tween_property(v, "global_position", world.cell_pos(room, x.to), 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
					Fx.snow_kick(v.global_position, -world.lane, 3, 1.0)
			"death":
				v.die()
				Sfx.play(self, "mon_die" if v.team == "enemy" else "merc_die")
				if v.team == "enemy":
					hud.remove_bar(uid)
					views.erase(uid)
					disp.erase(uid)
				else:
					hand.drop_hero(v.kind)
	if disp.has(uid):
		disp[uid] = d


## 히트스탑: 맞는 순간 모든 움직임이 잠깐 멈춘다(실제 시간 sec). 겹치면 더 긴 쪽까지.
func _hitstop(sec: float) -> void:
	if not _hitstop_on:
		_hitstop_on = true
		_hitstop_base = Engine.time_scale
		Engine.time_scale = _hitstop_base * HITSTOP_SCALE
	_hitstop_end = maxi(_hitstop_end, Time.get_ticks_msec() + int(sec * 1000.0))


func _tick_hitstop() -> void:
	if _hitstop_on and Time.get_ticks_msec() >= _hitstop_end:
		_hitstop_on = false
		Engine.time_scale = _hitstop_base


# ───────────────────────── 화면 갱신 ─────────────────────────

func _refresh() -> void:
	if battle == null:
		return
	var pl := {}
	for c in battle.hand:
		pl[c] = battle.playable(c)
	hand.playable = pl
	hand.set_piles(battle.draw_pile.size(), battle.discard.size())
	for u in battle.allies(true):
		if views.has(u.id):
			views[u.id].set_spent(u.ap == 0)
	_paint()


func _process(_delta: float) -> void:
	_tick_hitstop()
	hand.set_pile_visible(mode == "battle")
	if battle == null:
		return
	var cam: Camera3D = world.camera
	for id in views:
		var v: Node3D = views[id]
		if not is_instance_valid(v):
			continue
		var top: Vector3 = v.global_position + Vector3(0, v.hp_offset + 0.25, 0)
		var on: bool = not cam.is_position_behind(top) and mode != "select" and not (v.team == "ally" and v.is_dead() and mode == "walk")
		hud.place_bar(id, cam.unproject_position(top), on)
		if disp.has(id):
			var u = battle.unit(id)
			hud.update_bar(disp[id], battle.intent(u) if (u != null and u.team == "enemy" and mode == "battle" and battle.phase == "player") else {})
	var watch: Array = []
	for id in views:
		if is_instance_valid(views[id]):
			watch.append(views[id].chest())
	world.watch_points = watch
	var centers: Dictionary = hand.group_centers()
	for h in hud.panels:
		var u = battle.hero(h)
		hud.update_panel(h, u, float(centers.get(h, -5000.0)) if mode == "battle" else -5000.0, D.AP_MAX)
	if mode == "walk":
		var sum := Vector3.ZERO
		var n := 0
		for u in battle.allies(true):
			if views.has(u.id):
				sum += views[u.id].global_position
				n += 1
		if n > 0:
			world.focus_on(sum / n + ForestWorld.CAM_FOCUS_OFFSET * 0.6, false, 2.2)


## 칸 강조: 겨누는 카드 / 이동 / 마우스 아래 유닛.
func _paint() -> void:
	if mode != "battle" or battle == null:
		return
	var img_cells: Array = []
	var colors: Array = []
	if target_card != "":
		var t := String(D.card(target_card).target)
		if t == "none":
			var area := battle.area_of(target_card, Vector2i(-1, -1))
			for c in area:
				img_cells.append(c)
				colors.append(C_AREA)
		else:
			for c in battle.target_cells(target_card):
				img_cells.append(c)
				colors.append(C_TARGETABLE)
			if hover_cell in battle.target_cells(target_card):
				for c in battle.area_of(target_card, hover_cell):
					img_cells.append(c)
					colors.append(C_AREA)
		var o = battle.card_owner(target_card)
		if o != null:
			img_cells.append(o.cell)
			colors.append(C_ALLY_PICK)
	world.paint_many(room, img_cells, colors)
	# 적 외곽선: 겨눈 범위 안 = 진한 붉은색, 마우스 아래 = 밝은 붉은색
	var hit_ids := {}
	if target_card != "":
		var center := hover_cell if String(D.card(target_card).target) != "none" else Vector2i(-1, -1)
		var hits: Array = battle.cells_hit(target_card, center) if String(D.card(target_card).target) != "none" else battle.units_in(battle.area_of(target_card, center), "enemy")
		for h in hits:
			hit_ids[h.id] = true
	for e in battle.enemies():
		if views.has(e.id):
			var under: bool = battle.at(hover_cell) == e
			views[e.id].set_hover(hit_ids.has(e.id) or under, hit_ids.has(e.id))
	for a in battle.allies():
		if views.has(a.id):
			views[a.id].set_hover(battle.at(hover_cell) == a)
	_spotlight(hit_ids)


## 카드를 집어 겨누는 동안: 그 카드의 주인과 대상이 될 수 있는 적만 남기고 나머지(숲·지면·다른 유닛·다른 카드·막대)를 어둡게.
func _spotlight(hit_ids: Dictionary) -> void:
	var key := target_card
	if key == _spot_key:
		return
	_spot_key = key
	if key == "":
		world.spotlight([], false)
		hud.focus_units([])
		hand.focus_hero("")
		return
	var o = battle.card_owner(key)
	var ids: Array = [o.id] if o != null else []
	var cells: Array = battle.target_cells(key) if String(D.card(key).target) != "none" else battle.area_of(key, Vector2i(-1, -1))
	for e in battle.enemies():
		if e.cell in cells:
			ids.append(e.id)
	var nodes: Array = []
	for id in ids:
		if views.has(id):
			nodes.append(views[id])
	world.spotlight(nodes, true, room)
	hud.focus_units(ids)
	hand.focus_hero(String(D.card(key).hero))


# ───────────────────────── 입력 ─────────────────────────

func _cell_under(p: Vector2) -> Vector2i:
	var g: Vector3 = world.ground_at(p)
	if not g.is_finite():
		return Vector2i(-1, -1)
	return world.pos_cell(room, g)


func _unhandled_input(event: InputEvent) -> void:
	if mode != "battle" or battle == null or hud.choosing_card():
		return
	if event is InputEventMouseMotion:
		_on_motion(event.position)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_cancel()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_press(mb.position)
			else:
				_on_release(mb.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_cancel()
			KEY_SPACE, KEY_ENTER:
				_on_end_turn()


func _on_motion(p: Vector2) -> void:
	var over_hand: bool = p.y > hand.top_edge()
	hover_cell = _cell_under(p) if not over_hand or hand.dragging != "" else Vector2i(-1, -1)
	if _pressing and hand.dragging == "" and p.distance_to(_press_pos) > DRAG_START and not busy:
		if battle.playable(_press_card):
			hand.start_drag(_press_card)
			target_card = _press_card
			hud.hint(_target_hint(target_card))
		else:
			_explain_unplayable(_press_card)
			_pressing = false
	if hand.dragging != "":
		hand.drag_pos = p
		hand.over_board = not over_hand
	else:
		hand.set_hover(hand.card_at(p) if not busy else "")
	# 마우스 아래 적의 정보
	var u = battle.at(hover_cell)
	if u != null and u.team == "enemy" and target_card == "":
		var it := battle.intent(u)
		hud.hint("%s · 체력 %d/%d · 다음 행동: %s" % [u.name(), u.hp, u.max_hp, hud._intent_text(it)])
		_hover_enemy = u.id
	elif _hover_enemy != 0 and target_card == "":
		_hover_enemy = 0
		hud.hint("")
	_paint()


func _on_press(p: Vector2) -> void:
	if busy:
		return
	var c: String = hand.card_at(p)
	if c != "":
		_press_card = c
		_press_pos = p
		_pressing = true
		return
	if target_card != "":
		_try_cast(target_card, hover_cell, p)


func _on_release(p: Vector2) -> void:
	if hand.dragging != "":
		var c: String = hand.dragging
		var over_board: bool = p.y < hand.top_edge()
		if over_board and _castable_at(c, hover_cell):
			hand.end_drag(false)
			_cast(c, hover_cell)
		else:
			hand.end_drag(true)
			target_card = ""
			hud.hint("")
		_pressing = false
		_paint()
		return
	if _pressing:
		_pressing = false
		var c := _press_card
		if hand.card_at(p) != c or busy:
			return
		if not battle.playable(c):
			_explain_unplayable(c)
			return
		if target_card == c:
			if String(D.card(c).target) == "none":
				_cast(c, Vector2i(-1, -1))
			else:
				_cancel()
			return
		target_card = c
		hand.select(c)
		hud.hint(_target_hint(c))
		_paint()


func _castable_at(c: String, cell: Vector2i) -> bool:
	if String(D.card(c).target) == "none":
		return true
	return not battle.cells_hit(c, cell).is_empty()


func _try_cast(c: String, cell: Vector2i, p: Vector2) -> void:
	if p.y > hand.top_edge():
		_cancel()
		return
	if _castable_at(c, cell):
		_cast(c, cell)
	else:
		Sfx.play(self, "card_deny")
		hud.hint("거기에는 맞힐 적이 없습니다 — " + _target_hint(c))


func _cast(c: String, cell: Vector2i) -> void:
	var ev := battle.play_card(c, cell)
	target_card = ""
	hand.selected = ""
	if ev.is_empty():
		hand.deny(c)
		return
	busy = true
	hud.hint("")
	hand.consume(c)
	_refresh()
	await _play_events(ev)
	busy = false
	_after_events()


func _cancel() -> void:
	if target_card != "":
		Sfx.play(self, "card_cancel")
	target_card = ""
	hand.selected = ""
	hud.hint("")
	_paint()


func _target_hint(c: String) -> String:
	match String(D.card(c).target):
		"enemy_melee": return "%s: 돌진할 적을 고르세요" % D.card(c).name
		"enemy_any": return "%s: 적 하나를 고르세요" % D.card(c).name
		"row": return "%s: 꿰뚫을 가로줄을 고르세요" % D.card(c).name
		"area3": return "%s: 3×3 범위의 가운데를 고르세요" % D.card(c).name
		"cross": return "%s: 십자 범위의 가운데를 고르세요" % D.card(c).name
		"none": return "%s: 다시 누르거나 전장에 놓으면 바로 씁니다" % D.card(c).name
	return ""


func _explain_unplayable(c: String) -> void:
	hand.deny(c)
	var o = battle.card_owner(c)
	if o == null:
		hud.hint("쓰러진 동료의 카드입니다")
	elif o.ap < int(D.card(c).cost):
		hud.hint("%s의 행동력이 부족합니다(%d/%d)" % [o.name(), o.ap, int(D.card(c).cost)])
	elif not battle.has_targets(c):
		hud.hint("%s: 닿는 적이 없습니다" % D.card(c).name)


# ───────────────────────── 음악 ─────────────────────────

## 배경 음악(마녀산장 selected.json 의 bgm_* 곡). 두 플레이어로 교차 페이드.
func _play_music(event: String) -> void:
	if event == _music_event or sounds == null:
		return
	var list: Array = sounds.streams.get(event, [])
	if list.is_empty():
		return
	_music_event = event
	var stream: AudioStream = list[randi() % list.size()].duplicate()
	if stream is AudioStreamMP3:
		stream.loop = true
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	var old: AudioStreamPlayer = _music[0]
	var new: AudioStreamPlayer = _music[1]
	_music.reverse()
	new.stream = stream
	new.volume_db = -40.0
	new.play()
	var gain: float = float(sounds.gains.get(event, -10.0))
	var tw := create_tween().set_parallel(true)
	tw.tween_property(new, "volume_db", gain, 1.6)
	tw.tween_property(old, "volume_db", -60.0, 1.6)
	tw.chain().tween_callback(old.stop)
