extends Node
## 개발용 화면 캡처. 실행 인자 예:
##   godot --path . -- --shot=out.png --scenario=dragon
## 시나리오: start(기본), guests, combat, dragon, extension, panel

var game
var opts: Dictionary = {}


static func parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1]
	if not out.has("shot"):
		return {}
	return out


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var scenario: String = opts.get("scenario", "start")
	var delay := float(opts.get("delay", "2.5"))
	await get_tree().process_frame
	if opts.get("ui", "on") == "off":
		game.hud.visible = false
	if opts.has("style"):
		preload("res://scripts/visual/screen_style.gd").apply(game.world, opts["style"])
	if opts.get("lighting", "normal") == "flat":
		game.world.env.ssao_enabled = false
		game.world.sun.shadow_enabled = false
	if opts.get("lighting", "normal") == "no_ssao":
		game.world.env.ssao_enabled = false
	if opts.get("lighting", "normal") == "no_shadow":
		game.world.sun.shadow_enabled = false
	match scenario:
		"guests":
			game.session.prep_elapsed = 3.0
			delay = float(opts.get("delay", "7.5"))
		"combat":
			game.session.wave_index = 2
			game.session.start_wave()
			game.player.set_destination(Vector3(-3.0, 0, 4.0))
			Engine.time_scale = 3.0
			delay = float(opts.get("delay", "22"))
		"dragon":
			game.session.wave_index = 2
			game.session.start_wave()
			Engine.time_scale = 3.0
			await get_tree().create_timer(14.0, true, false, false).timeout
			Engine.time_scale = 1.0
			game.dragon.summon()
			delay = float(opts.get("delay", "3.4"))
		"extension":
			game.economy.debug_add_gold(100)
			game.economy.buy("extension")
			delay = float(opts.get("delay", "2.0"))
		"cards":
			# 손패 + 고용 제안 + 털 난 양
			game.debug_cards()
			game.session.wave_index = 1
			game.world.pasture.produce_wool(2)
			game.session.wave_index = 0
			game.session.prep_elapsed = 25.2
			delay = float(opts.get("delay", "2.0"))
		"moon_compare":
			# 달빛 UI 시안 비교 상태: 1일차 낮 · 밤까지 00:35 · 40G · 목재 3 · 양털 2 ·
			# 손패 도끼 용병 → 양털(×2) → 목재(×3) → 숲의 괴물. 값은 실제 게임 상태로 만든다.
			game.cards.add("lumberjack", 1, game.economy._pick_name())
			game.cards.add("wool", 2)
			game.cards.add("timber", 3)
			game.cards.add("forest_monster")
			game.session.prep_elapsed = 55.0
			for c in game.hud.toast_box.get_children():
				c.queue_free()
			await get_tree().create_timer(1.0, true, false, false).timeout
			delay = float(opts.get("delay", "0.6"))
			# 시간을 건너뛰며 생긴 숙박비·고용 제안·알림은 시안 비교 장면에서 정리한다
			game.economy.gold = 40
			for o in game.economy.offers.duplicate():
				game.economy._close_offer(o, false)
			for c in game.hud.toast_box.get_children():
				c.queue_free()
			game.session.prep_elapsed = 55.0 - delay + 0.3  # 캡처 순간 남은 시간 34.7초 → 00:35
		"cards_drag":
			# 용병 카드를 자원 나무 위로 끌고 있는 장면(대상 강조·작업 위치·미리보기)
			game.debug_cards()
			await get_tree().create_timer(1.0, true, false, false).timeout
			var hand = game.hud.card_hand
			for e in game.cards.hand():
				if e["id"] == "lumberjack":
					hand.begin_drag(e["uid"])
			var tree: Dictionary = _nearest_open_tree()
			var at: Vector2 = game.world.camera.unproject_position(tree["pos"] + Vector3(0, minf(tree["height"] * 0.45, 2.4), 0))
			# 실제 마우스 움직임이 미리보기 위치를 덮어쓰지 않도록 매 프레임 고정
			for f in 40:
				hand.drag_pos = at
				await get_tree().process_frame
			delay = float(opts.get("delay", "0.05"))
		"cards_combat":
			# 밤: 손패에서 소환한 용병·하수인이 길을 막는다
			await get_tree().create_timer(0.5, true, false, false).timeout
			game.session.wave_index = 1
			game.session.start_wave()
			for i in 2:
				game.cards.add("lumberjack", 1, game.economy._pick_name())
			game.cards.add("forest_monster")
			var spots := [Vector3(-4.5, 0, 6.6), Vector3(-2.5, 0, 7.2), Vector3(-3.5, 0, 5.4)]
			var i2 := 0
			for e in game.cards.hand().duplicate():
				var r: Dictionary = game.resolver.commit(e["uid"], game.world.camera.unproject_position(spots[i2]))
				print("SHOT summon ", e["id"], " ok=", r["ok"], " ", r.get("reason", ""))
				i2 += 1
			game.player.set_destination(Vector3(-1.5, 0, 5.0))
			Engine.time_scale = 3.0
			delay = float(opts.get("delay", "16"))
		"jobs_day":
			# 낮: 나무꾼이 목재를 들고 벌목 중(말풍선), 사냥꾼이 토끼를 쫓고, 전투용병이 정찰, 채집가가 출발
			game.economy.debug_add_gold(100)
			await get_tree().create_timer(1.0, true, false, false).timeout
			var t0: Dictionary = _nearest_open_tree()
			game.contracts.spawn_chop("토르빈", t0, game.resolver.work_position(t0))
			var lj = game.contracts.allies[0]
			lj.add_carry("timber", 20)
			game.contracts.spawn_guard("merc", "올라프", Vector3(-2.0, 0, 8.0), null, "hunter")
			var hu = game.contracts.allies[1]
			hu.add_carry("raw_meat", 1)
			hu.add_carry("rabbit_pelt", 1)
			game.contracts.spawn_guard("merc", "브람", Vector3(2.0, 0, 8.5), null, "warrior")
			game.wildlife.spawn("rabbit", Vector3(-5.0, 0, 10.0))
			game.wildlife.spawn("deer", Vector3(-7.5, 0, 12.0))
			game.player.set_destination(Vector3(3.0, 0, 7.0))
			delay = float(opts.get("delay", "3.0"))
		"jobs_chest":
			# 보물상자가 열려 물음표 카드 3장이 가운데 늘어선 장면
			game.cards.add("treasure_chest", 1)
			await get_tree().create_timer(0.8, true, false, false).timeout
			var uidc := -1
			for e in game.cards.hand():
				if e["id"] == "treasure_chest":
					uidc = e["uid"]
			game.resolver.commit(uidc, game.world.camera.unproject_position(Vector3(2.0, 0, 8.0)))
			delay = float(opts.get("delay", "2.6"))
		"jobs_reveal":
			game.cards.add("treasure_chest", 1)
			await get_tree().create_timer(0.8, true, false, false).timeout
			var uidr := -1
			for e in game.cards.hand():
				if e["id"] == "treasure_chest":
					uidr = e["uid"]
			game.resolver.commit(uidr, game.world.camera.unproject_position(Vector3(2.0, 0, 8.0)))
			await get_tree().create_timer(2.6, true, false, false).timeout
			game.chest_ui._on_pick(1)
			delay = float(opts.get("delay", "1.2"))
		"monsters":
			# 기본 숲의 괴물(가장 연약)과 카드로 변환되는 큰 숲의 괴물이 나란히 걸어온다(잎 떨어짐)
			var MonsterScript := preload("res://scripts/actors/monster.gd")
			game.player.position = Vector3(4.5, 0, 9.5)
			game.player.set_physics_process(false)
			for k in 2:
				var m = MonsterScript.new()
				m.setup(game, 36.0, false)
				if k == 1:
					m.make_big()
					m.card_drop = "forest_monster"
				m.position = Vector3(-1.0 + k * 1.8, 0, 11.0)
				game.actors.add_child(m)
			for z in 4:
				game.world.player_camera.zoom(-1.0)
			delay = float(opts.get("delay", "1.6"))
		"monster_closeup":
			# 정지 자세 비교: 왼쪽 기본 숲의 괴물, 오른쪽 큰 숲의 괴물(옆모습으로 등 가지 확인)
			var MonsterScript2 := preload("res://scripts/actors/monster.gd")
			game.player.position = Vector3(6.0, 0, 10.5)
			game.player.set_physics_process(false)
			game.player.visible = false
			for k in 2:
				var m2 = MonsterScript2.new()
				m2.setup(game, 36.0, false)
				if k == 1:
					m2.make_big()
				m2.position = Vector3(4.6 + k * 1.9, 0, 9.0 - k * 1.2)
				game.actors.add_child(m2)
				m2.set_physics_process(false)
				m2.visual.rotation.y = deg_to_rad(float(opts.get("yaw", "-60")))
			for z in 8:
				game.world.player_camera.zoom(-1.0)
			if opts.get("closecam", "off") == "on":
				# 모델 검토용 근접 카메라(게임 카메라와 별개)
				var cc := Camera3D.new()
				game.world.add_child(cc)
				cc.fov = 30.0
				var focus := Vector3(5.55, 0.9, 8.4)
				cc.global_position = focus + Vector3(3.2, 2.6, 4.2)
				cc.look_at(focus)
				cc.current = true
			delay = float(opts.get("delay", "1.2"))
		"graves":
			# 산장 뒤편 묘지: 쓰러진 용병 3기 + 확장된 빈 자리
			game.world.graveyard.upgrade()
			for n in ["브람", "올라프", "토르빈"]:
				game.world.graveyard.bury(n, 2)
			game.player.position = Vector3(5.5, 0, -1.0)
			for z in 2:
				game.world.player_camera.zoom(-1.0)
			delay = float(opts.get("delay", "2.0"))
		"shear":
			# 넓어진 목장 안으로 들어가 양 옆에서 털 깎기(게이지 표시)
			game.economy.debug_add_gold(100)
			game.economy.buy("sheep")
			game.session.wave_index = 1
			game.world.pasture.produce_wool(3)
			game.session.wave_index = 0
			game.player.position = Vector3(7.6, 0, 2.2)
			for z in 4:
				game.world.player_camera.zoom(-1.0)
			await get_tree().create_timer(0.5, true, false, false).timeout
			var target_sheep = game.world.pasture.slots[0]
			for sh in game.world.pasture.slots:
				if sh.global_position.distance_to(game.world.pasture.gate_center()) < target_sheep.global_position.distance_to(game.world.pasture.gate_center()):
					target_sheep = sh
			game.player.harvest(target_sheep)
			for f in 600:
				await get_tree().process_frame
				if game.player.harvest_t > 1.1:
					break
			delay = float(opts.get("delay", "0.02"))
		"pasture_max":
			game.economy.debug_add_gold(500)
			game.cards.add("timber", 40)
			game.economy.buy("pasture")
			game.economy.buy("pasture")
			while game.world.pasture.has_empty_slot():
				game.economy.buy("sheep")
			game.player.position = Vector3(9.2, 0, 5.2)
			delay = float(opts.get("delay", "1.5"))
		"panel":
			game.hud.open_lodge_panel()
			delay = float(opts.get("delay", "1.0"))
		"video_wave2":
			# 영상용(--write-movie): 손패 4장으로 2웨이브 시작 → 용병·하수인 카드를 끌어 사용
			await _video_wave2()
			delay = 0.05
	await get_tree().create_timer(delay, true, false, false).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var save_error := img.save_png(opts["shot"])
	if save_error != OK:
		push_error("Screenshot save failed: " + str(save_error) + " " + str(opts["shot"]))
		get_tree().quit(1)
		return
	print("SHOT saved: ", opts["shot"])
	print("SHOT screen style: ", preload("res://scripts/visual/screen_style.gd").current_id)
	print("SHOT camera style: ", preload("res://scripts/visual/camera_style.gd").current_id)
	print("SHOT air style: ", preload("res://scripts/visual/aerial_perspective.gd").current_id)
	print("SHOT air colors: ", "local" if game.world.aerial_perspective.color_bleed_enabled else "uniform")
	print("SHOT time: ", game.world.day_cycle.mode, " progress=", game.world.day_cycle.progress)
	print("SHOT fog of war: ", game.world.fog_of_war.enabled)
	print("SHOT fog preset: ", game.world.fog_of_war.current_id)
	get_tree().quit()


## 산장 가까이에서 접근 가능한(둘러싸이지 않은) 나무.
func _nearest_open_tree() -> Dictionary:
	var best := {}
	var best_d := 1e9
	for t in game.world.harvest_trees:
		if game.world.tree_access(t) != "":
			continue
		var d: float = t["pos"].distance_to(Vector3(0, 0, 4.0))
		if d < best_d:
			best_d = d
			best = t
	return best


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec, true, false, false).timeout


func _video_wave2() -> void:
	var Cfg := preload("res://scripts/config.gd")
	var hand = game.hud.card_hand
	game.session.wave_index = 1
	game.cards.add("warrior", 1, game.economy._pick_name())
	game.cards.add("warrior", 1, game.economy._pick_name())
	game.cards.add("forest_monster")
	game.cards.add("wool", 3)
	# 로딩 프레임을 지나 화면이 안정될 때까지 대기(이 구간은 영상에서 잘라낸다)
	game.session.prep_elapsed = Cfg.PREP_TIME - 3.3
	await _wait(1.5)
	# 준비 시간을 건너뛰며 한꺼번에 뜬 알림은 영상 시작 전에 지운다
	for c in game.hud.toast_box.get_children():
		c.queue_free()
	await get_tree().process_frame
	print("CLIP_START frame=", Engine.get_frames_drawn(), " t=", Time.get_ticks_msec())
	var uids: Array = []
	for e in game.cards.hand():
		uids.append(e["uid"])
	# 0.0~1.6s 준비 시간 끝, 손패 훑어보기
	await _wait(0.3)
	for u in uids:
		hand.set_hover(u, true)
		await _wait(0.28)
		hand.set_hover(u, false)
	# ~1.6s 웨이브 2 시작 → 마녀가 서쪽 길로 마중
	await _wait(0.2)
	game.player.set_destination(Vector3(-8.5, 0, 6.6))
	await _wait(1.4)
	# ~3.2s 용병 카드 → 가장 가까운 적
	var merc_uid := -1
	var minion_uid := -1
	for e in game.cards.hand():
		if e["id"] == "warrior" and merc_uid == -1:
			merc_uid = e["uid"]
		elif e["id"] == "forest_monster":
			minion_uid = e["uid"]
	hand.set_hover(merc_uid, true)
	await _wait(0.35)
	await _drag_card(hand, merc_uid, func(): return _enemy_screen_pos(), 1.1)
	# ~5.5s 하수인 카드 → 길목 지면
	await _wait(0.9)
	hand.set_hover(minion_uid, true)
	await _wait(0.35)
	await _drag_card(hand, minion_uid, func(): return game.world.camera.unproject_position(Vector3(-11.0, 0, 5.9)), 1.1)
	await _wait(3.2)
	print("CLIP_END frame=", Engine.get_frames_drawn())


func _enemy_screen_pos() -> Vector2:
	var cam: Camera3D = game.world.camera
	var best = null
	var best_d := 1e9
	for en in get_tree().get_nodes_in_group("enemies"):
		if en.dead:
			continue
		var d: float = en.global_position.distance_to(game.player.global_position)
		if d < best_d:
			best_d = d
			best = en
	if best == null:
		return cam.unproject_position(Vector3(-12.0, 0, 5.4))
	return cam.unproject_position(best.global_position + Vector3(0, 0.5, 0))


func _drag_card(hand, uid: int, target: Callable, dur: float) -> void:
	if uid == -1 or not hand.views.has(uid):
		return
	var start: Vector2 = hand.views[uid].get_global_rect().get_center()
	hand.set_hover(uid, false)
	hand.begin_drag(uid)
	var t := 0.0
	while t < dur:
		var k := t / dur
		k = k * k * (3.0 - 2.0 * k)
		var to: Vector2 = target.call()
		var mid := start.lerp(to, 0.5) + Vector2(0, -90)
		hand.drag_pos = start.lerp(mid, k).lerp(mid.lerp(to, k), k)
		await get_tree().process_frame
		t += get_process_delta_time()
	# 대상 위에서 잠시 머물러 미리보기를 보여준 뒤 놓는다
	var hold := 0.0
	while hold < 0.45:
		hand.drag_pos = target.call()
		await get_tree().process_frame
		hold += get_process_delta_time()
	hand._end_drag()
