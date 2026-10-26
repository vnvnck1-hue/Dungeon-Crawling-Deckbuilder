extends Node
## 롤(League of Legends)식 전투 조작. 정리 문서: docs/lol-controls-v01.md
## - 우클릭: 땅 = 이동(평타 대상 해제), 적 = 그 적을 대상으로 사거리까지 다가가 평타 계속, 털 난 양(낮) = 수확
## - A → 좌클릭: 공격 이동(커서 근처 적이 있으면 그 적 우선). A 상태에서 우클릭·Esc는 A 취소
## - Q: 마녀 번개 일격(늑대일 때 할퀴기) · Shift+Q: 번개 연출 프리셋 바꾸기
## - S: 정지 · Space: 카메라를 마녀에게 복귀 · C: 공격 사거리 표시 켜기/끄기(A 대기 중에도 표시)
## - 적 마우스오버: 공격 커서 + 붉은 외곽선, 공격 대상: 더 진한 붉은 외곽선 유지
## 좌클릭은 UI·카드 드래그·양 수확·손님 고용·산장/제단 열기 그대로이며, 땅 좌클릭으로는 움직이지 않는다(롤과 같음).

const Cfg := preload("res://scripts/config.gd")
const Layout := preload("res://scripts/world/layout.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const Outline := preload("res://scripts/visual/enemy_outline.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const B := preload("res://scripts/visual/build.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const LightningVfx := preload("res://scripts/visual/vfx/lightning_vfx.gd")

const PICK_MIN_PX := 30.0
const ARMED_RING := Color(1.0, 0.32, 0.26, 0.6)
const RANGE_RING := Color(0.95, 0.92, 1.0, 0.42)

var game
var attack_armed := false   # A를 눌러 다음 좌클릭이 공격 이동이 되는 상태
var show_range := false     # C 토글
var hovered = null          # 커서 아래 적
var range_ring: MeshInstance3D
var cursor_mode := ""       # "" | "attack" (검증용으로 노출)
var _ring_mesh: TorusMesh
var _ring_mat: StandardMaterial3D
var _ring_radius := -1.0
var _cursor_tex: Texture2D
var _outlined: Array = []
var mouse_pos := Vector2(-1, -1)  # 마지막 마우스 위치(움직임 이벤트로 갱신)


func _ready() -> void:
	_ring_mesh = TorusMesh.new()
	_ring_mesh.rings = 48
	_ring_mesh.ring_segments = 6
	_ring_mat = Mats.unshaded(RANGE_RING, true, true)
	_ring_mat.no_depth_test = true
	_ring_mat.render_priority = 3
	range_ring = MeshInstance3D.new()
	range_ring.name = "AttackRange"
	range_ring.mesh = _ring_mesh
	range_ring.material_override = _ring_mat
	range_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	range_ring.position.y = 0.04
	range_ring.scale = Vector3(1.0, 0.08, 1.0)
	range_ring.visible = false
	game.player.add_child(range_ring)
	_cursor_tex = _make_cursor()


## main._unhandled_input 에서 먼저 부른다. 처리했으면 true.
func handle_input(event: InputEvent) -> bool:
	var player = game.player
	var key := event as InputEventKey
	if key != null:
		if not key.pressed or key.echo:
			return false
		var code := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		match code:
			KEY_A:
				attack_armed = true
				return true
			KEY_S:
				attack_armed = false
				player.command_stop()
				return true
			KEY_SPACE:
				game.world.player_camera.recenter()
				return true
			KEY_C:
				show_range = not show_range
				return true
			KEY_Q:
				# 보름달 늑대: 커서 방향 전방 부채꼴을 4번 할퀸다(docs/wolf-blood-event-design.md §4)
				# 마녀: 커서 방향으로 관통 번개 일격(Lightning Lance)
				if key.shift_pressed and not player.wolf:
					# Shift+Q: 번개 일격 연출 프리셋 바꾸기
					var n: int = player.cycle_lightning_preset()
					game.toast(tr("번개 일격 연출: %s") % tr(LightningVfx.preset_name(n)), Color(0.75, 0.9, 1.0))
					return true
				var g = ground_at(mouse_pos) if mouse_pos.x >= 0.0 else null
				if player.wolf:
					player.cast_claw(g)
				else:
					player.cast_lightning(g)
				return true
			KEY_E:
				# 보름달 늑대: 커서 아래 적(없으면 가장 가까운 적)에게 덮쳐 물어뜯는다
				if not player.wolf:
					return false
				player.cast_pounce(enemy_at(mouse_pos) if mouse_pos.x >= 0.0 else null)
				return true
		return false
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed:
		return false
	if mb.button_index == MOUSE_BUTTON_RIGHT:
		if game.hud != null and game.hud.card_hand.drag_uid >= 0:
			return false
		attack_armed = false
		_right_click(mb.position)
		return true
	if mb.button_index == MOUSE_BUTTON_LEFT and attack_armed:
		attack_armed = false
		var prefer = enemy_at(mb.position)
		var dest = prefer.global_position if prefer != null else ground_at(mb.position)
		if dest == null:
			return true
		player.command_attack_move(dest, prefer)
		show_attack_marker(dest)
		return true
	return false


func _right_click(mp: Vector2) -> void:
	var player = game.player
	var e = enemy_at(mp)
	if e != null:
		player.command_attack(e)
		show_attack_marker(e.global_position)
		return
	if game.session.state == 0:
		var sheep = game._ready_sheep_at(game.world.camera, mp)
		if sheep != null:
			player.harvest(sheep)
			game.world.show_click_marker(sheep.global_position)
			return
	var dest = ground_at(mp)
	if dest == null:
		return
	player.set_destination(dest)
	game.world.show_click_marker(dest)


## 화면 좌표 → 이동 가능한 지면 점(없으면 null).
func ground_at(mp: Vector2):
	var cam: Camera3D = game.world.camera
	var from := cam.project_ray_origin(mp)
	var dir := cam.project_ray_normal(mp)
	if absf(dir.y) < 0.001:
		return null
	var t := -from.y / dir.y
	if t <= 0.0:
		return null
	var ground := Layout.clamp_to_map(from + dir * t)
	var nav_map: RID = game.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map) == 0:
		return null
	return NavUtil.ground_or_near(nav_map, ground)


## 커서 아래의 적: 발밑~머리 선분까지의 화면 거리로 고른다(몸집이 크면 판정도 크다).
func enemy_at(mp: Vector2):
	var cam: Camera3D = game.world.camera
	var best = null
	var best_d := INF
	for e in get_tree().get_nodes_in_group("enemies"):
		if e.dead or not e.is_visible_in_tree() or cam.is_position_behind(e.global_position):
			continue
		var h: float = maxf(float(e.get("hp_offset")) * 0.85 if e.get("hp_offset") != null else 1.0, 0.6)
		var a := cam.unproject_position(e.global_position)
		var top := cam.unproject_position(e.global_position + Vector3(0, h, 0))
		var radius := maxf(PICK_MIN_PX, a.distance_to(top) * 0.45)
		var d := Geometry2D.get_closest_point_to_segment(mp, a, top).distance_to(mp)
		if d < radius and d < best_d:
			best_d = d
			best = e
	return best


func pointer_in_world() -> bool:
	if not game.movement_input_allowed() or game.player.dead:
		return false
	return get_viewport().gui_get_hovered_control() == null


## A 대기 중 Esc 는 A 만 취소한다(HUD 의 일시 정지보다 먼저 받도록 단축키 단계에서).
func _shortcut_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if attack_armed and k != null and k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
		attack_armed = false
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		mouse_pos = event.position


func _process(_delta: float) -> void:
	if game.player == null or game.world == null:
		return
	if attack_armed and not game.movement_input_allowed():
		attack_armed = false
	hovered = enemy_at(mouse_pos) if mouse_pos.x >= 0.0 and pointer_in_world() else null
	_sync_outlines()
	_set_cursor("attack" if (hovered != null or attack_armed) else "")
	var r: float = game.player.attack_range()
	if not is_equal_approx(r, _ring_radius):
		_ring_radius = r
		_ring_mesh.inner_radius = r - 0.05
		_ring_mesh.outer_radius = r + 0.05
	range_ring.visible = (attack_armed or show_range) and not game.player.dead
	var ring_color: Color = ARMED_RING if attack_armed else RANGE_RING
	if _ring_mat.albedo_color != ring_color:
		_ring_mat.albedo_color = ring_color


func _sync_outlines() -> void:
	var target = game.player.target_enemy
	var keep: Array = []
	for e in [target, hovered]:
		if e != null and is_instance_valid(e) and not e.dead and not keep.has(e):
			keep.append(e)
	for e in _outlined:
		if not keep.has(e):
			Outline.apply(e, Outline.NONE)
	for e in keep:
		Outline.apply(e, Outline.TARGET if e == target else Outline.HOVER)
	_outlined = keep


func _set_cursor(mode: String) -> void:
	if mode == cursor_mode:
		return
	cursor_mode = mode
	if DisplayServer.get_name() == "headless":
		return
	if mode == "attack":
		Input.set_custom_mouse_cursor(_cursor_tex, Input.CURSOR_ARROW, Vector2(16, 16))
	else:
		Input.set_custom_mouse_cursor(null)


func _exit_tree() -> void:
	if cursor_mode != "" and DisplayServer.get_name() != "headless":
		Input.set_custom_mouse_cursor(null)


## 공격 커서: 붉은 조준 고리 + 네 방향 눈금(어두운 테두리로 눈밭 위에서도 보이게).
static func _make_cursor() -> Texture2D:
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(15.5, 15.5)
	for y in 32:
		for x in 32:
			var p := Vector2(x, y)
			var d := p.distance_to(c)
			var ring := absf(d - 10.0)
			var tick := (absf(p.x - c.x) <= 1.0 and absf(d - 13.0) <= 2.6) or (absf(p.y - c.y) <= 1.0 and absf(d - 13.0) <= 2.6)
			var dot := d <= 1.6
			if ring <= 1.1 or tick or dot:
				img.set_pixel(x, y, Color(1.0, 0.16, 0.1, 1.0))
			elif ring <= 2.3 or (d <= 2.8):
				img.set_pixel(x, y, Color(0.18, 0.02, 0.02, 0.9))
	# 눈금 테두리
	var out := img.duplicate()
	for y in 32:
		for x in 32:
			if img.get_pixel(x, y).a > 0.0:
				continue
			for o: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var q: Vector2i = Vector2i(x, y) + o
				if q.x >= 0 and q.y >= 0 and q.x < 32 and q.y < 32 and img.get_pixelv(q).r > 0.9:
					out.set_pixel(x, y, Color(0.18, 0.02, 0.02, 0.9))
					break
	return ImageTexture.create_from_image(out)


## 공격 명령 표시: 붉은 고리가 조여 든다.
func show_attack_marker(pos: Vector3) -> void:
	Sfx.play(game.world, "move_click")
	var m := Mats.unshaded(Color(1.0, 0.25, 0.18, 0.95), true, true)
	var ring := B.torus(game.world, 0.32, 0.42, pos + Vector3(0, 0.05, 0), m)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.3, 0.2, 1.3)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(0.35, 0.2, 0.35), 0.4).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(m, "albedo_color:a", 0.0, 0.4)
	tw.chain().tween_callback(ring.queue_free)
