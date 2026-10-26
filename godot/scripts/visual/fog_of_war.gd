extends Node
## Independent world-space sight mask and exploration memory. Never changes AI or combat.
const Cfg := preload("res://scripts/config.gd")
const SHADER := preload("res://shaders/fog_of_war.gdshader")
const RESOLUTION := 208
const EXTENT := 104.0
const RAYS := 160
const IDS := ["snow_mist", "lavender", "moon_haze"]
const NAMES := ["옅은 설무", "라벤더 안개", "달빛 몽환"]
const DEFAULT_ID := "snow_mist"
var world
var enabled := true
var sight_mult := 1.0   # 안개의 밤(챕터 밤 규칙)에 마녀 시야를 좁힌다
var current_id := DEFAULT_ID
var sight := PackedFloat32Array()
var explored := PackedByteArray()
var texture: ImageTexture
var material: ShaderMaterial
var overlay: MeshInstance3D
var _elapsed := 1.0
# 텍스처로 올리는 RG8 버퍼(R=지금 시야, G=탐색 기억)와 그 그림. 갱신마다 새로 만들지 않고 고쳐 쓴다.
var _data := PackedByteArray()
var _image: Image
# 이번·지난 갱신에서 _reveal 이 건드린 칸 사각형. 시야는 이 안에만 생기므로 지우기·인코딩도 이 안에서만 한다
# (그 밖은 시야 0 이고 탐색 기억도 그대로라 버퍼 값이 바뀌지 않는다).
var _rects: Array[Rect2i] = []
var _prev_rects: Array[Rect2i] = []
var _ray: PhysicsRayQueryParameters3D

static func profile(id: String) -> Dictionary:
	match id:
		"lavender": return {"color":Color(.65,.46,.78),"opacity":.42,"memory_opacity":.14,"feather":6.0,"drift":.12}
		"moon_haze": return {"color":Color(.42,.64,.88),"opacity":.50,"memory_opacity":.18,"feather":11.0,"drift":.18}
	return {"color":Color(.69,.76,.86),"opacity":.25,"memory_opacity":.09,"feather":7.5,"drift":.07}

func configure(id: String) -> bool:
	if id not in IDS: return false
	current_id = id
	var p := profile(id)
	material.set_shader_parameter("mist_color",p.color)
	material.set_shader_parameter("unknown_opacity",p.opacity)
	material.set_shader_parameter("memory_opacity",p.memory_opacity)
	material.set_shader_parameter("feather_meters",p.feather)
	material.set_shader_parameter("drift_strength",p.drift)
	_sync_tint()
	return true

func _sync_tint() -> void:
	# The veil follows the local atmosphere; existing aerial depth fog stays independent.
	material.set_shader_parameter("ambient_tint",world.env.fog_light_color)

func bind(owner_world) -> void:
	world = owner_world
	process_priority = 25
	sight.resize(RESOLUTION*RESOLUTION)
	explored.resize(RESOLUTION*RESOLUTION)
	_data.resize(RESOLUTION*RESOLUTION*2)
	_image = Image.create(RESOLUTION,RESOLUTION,false,Image.FORMAT_RG8)
	texture = ImageTexture.create_from_image(_image)
	_ray = PhysicsRayQueryParameters3D.new()
	_ray.collision_mask = Cfg.L_OBSTACLE
	material = ShaderMaterial.new()
	material.shader = SHADER
	material.render_priority = 127
	material.set_shader_parameter("sight_mask",texture)
	world.outline_mat.render_priority = 126
	overlay = MeshInstance3D.new()
	overlay.name = "FogOfWarOverlay"
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	overlay.mesh = quad
	overlay.material_override = material
	overlay.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	overlay.extra_cull_margin = 16384.0
	overlay.position.z = -1.1
	world.camera.add_child(overlay)
	configure(current_id)
	for arg in OS.get_cmdline_user_args():
		if arg == "--fow=off": set_enabled(false)
		if arg.begins_with("--fow-style="): configure(arg.trim_prefix("--fow-style="))
	# Physics bodies must be registered before raycasting the first sight polygon.
	await get_tree().physics_frame
	refresh()

func set_enabled(value: bool) -> void:
	enabled = value
	if overlay != null: overlay.visible = value
	if world != null: _sync_enemies()

func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= .15:
		_elapsed = 0.0
		refresh()
		_sync_tint()
	else:
		_sync_enemies()

func _cell(pos: Vector3) -> Vector2i:
	return Vector2i(floori((pos.x+EXTENT*.5)/EXTENT*RESOLUTION),floori((pos.z+EXTENT*.5)/EXTENT*RESOLUTION))

func visibility_at(pos: Vector3) -> float:
	if not enabled: return 1.0
	var c := _cell(pos)
	if c.x < 0 or c.y < 0 or c.x >= RESOLUTION or c.y >= RESOLUTION: return 0.0
	return sight[c.y*RESOLUTION+c.x]

func is_visible_at(pos: Vector3) -> bool:
	return visibility_at(pos) >= .35

func is_explored_at(pos: Vector3) -> bool:
	if not enabled: return true
	var c := _cell(pos)
	return c.x >= 0 and c.y >= 0 and c.x < RESOLUTION and c.y < RESOLUTION and explored[c.y*RESOLUTION+c.x] > 0

func refresh() -> void:
	if world.game.player == null: return
	# 지난 갱신이 밝힌 칸만 지운다(나머지는 이미 0).
	for r in _prev_rects:
		for y in range(r.position.y,r.end.y):
			var row := y*RESOLUTION
			for x in range(r.position.x,r.end.x):
				sight[row+x] = 0.0
	_rects.clear()
	# Familiar lodge grounds stay readable even while the witch explores the forest.
	_reveal(Vector3(1.0,0,1.0),7.5,PackedFloat32Array())
	var radius := lerpf(Cfg.WITCH_SIGHT_DAY,Cfg.WITCH_SIGHT_NIGHT,world.day_cycle.night_amount) * sight_mult
	var player_pos: Vector3 = world.game.player.global_position
	var distances := PackedFloat32Array()
	var origin := player_pos + Vector3(0,1.0,0)
	var space: PhysicsDirectSpaceState3D = world.get_world_3d().direct_space_state
	for i in RAYS:
		var angle := TAU*float(i)/RAYS
		_ray.from = origin
		_ray.to = origin + Vector3(cos(angle),0,sin(angle))*radius
		var hit: Dictionary = space.intersect_ray(_ray)
		distances.append(origin.distance_to(hit.position)+.35 if not hit.is_empty() else radius)
	_reveal(player_pos,radius,distances)
	for ally in get_tree().get_nodes_in_group("allies"):
		if not ally.dead: _reveal(ally.global_position,Cfg.ALLY_SIGHT,PackedFloat32Array())
	# Placed light sources (e.g. the ward lantern card) clear a fixed circle around themselves.
	for source in get_tree().get_nodes_in_group("sight_sources"):
		_reveal(source.global_position,source.sight_radius,PackedFloat32Array())
	# 이번에 밝힌 칸과 지난번에 밝혔다가 꺼진 칸만 다시 인코딩한다(겹친 칸은 두 번 써도 같은 값).
	for r in _rects + _prev_rects:
		for y in range(r.position.y,r.end.y):
			var row := y*RESOLUTION
			for x in range(r.position.x,r.end.x):
				var i := row+x
				var s := sight[i]
				if s >= .35: explored[i] = 255
				_data[i*2] = int(s*255.0)
				_data[i*2+1] = explored[i]
	var swap := _prev_rects
	_prev_rects = _rects
	_rects = swap
	_image.set_data(RESOLUTION,RESOLUTION,false,Image.FORMAT_RG8,_data)
	texture.update(_image)
	_sync_enemies()

func _reveal(pos: Vector3, radius: float, distances: PackedFloat32Array) -> void:
	var lo := _cell(pos-Vector3(radius,0,radius)).clamp(Vector2i.ZERO,Vector2i(RESOLUTION-1,RESOLUTION-1))
	var hi := _cell(pos+Vector3(radius,0,radius)).clamp(Vector2i.ZERO,Vector2i(RESOLUTION-1,RESOLUTION-1))
	_rects.append(Rect2i(lo,hi-lo+Vector2i.ONE))
	for y in range(lo.y,hi.y+1):
		for x in range(lo.x,hi.x+1):
			var at := Vector2((x+.5)*EXTENT/RESOLUTION-EXTENT*.5,(y+.5)*EXTENT/RESOLUTION-EXTENT*.5)
			var d := at-Vector2(pos.x,pos.z)
			var limit := radius
			if not distances.is_empty():
				var index := fposmod(d.angle(),TAU)/TAU*RAYS
				var a := floori(index)%RAYS
				limit = lerpf(distances[a],distances[(a+1)%RAYS],index-floorf(index))
			var value := 1.0-smoothstep(maxf(.2,limit-1.5),limit,d.length())
			var id := y*RESOLUTION+x
			sight[id] = maxf(sight[id],value)

func _sync_enemies() -> void:
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.dead: enemy.visible = is_visible_at(enemy.global_position)
