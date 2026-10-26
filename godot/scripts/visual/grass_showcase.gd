extends Node3D
## Stand-alone preview for GrassField. Open scenes/props/grass/grass_showcase.tscn and press F6.
## 1/2/3 calm·breeze·storm  P palette  mouse moves the push marker (auto-circles when idle)  wheel zoom

const WIND := [
	{"name": "잔잔함", "wind_strength": .25, "wave_speed": 1.8, "wave_amount": .35, "flutter": .03, "base_lean": .06},
	{"name": "산들바람", "wind_strength": .55, "wave_speed": 3.2, "wave_amount": .55, "flutter": .05, "base_lean": .12},
	{"name": "강풍", "wind_strength": 1.05, "wave_speed": 6.0, "wave_amount": .75, "flutter": .09, "base_lean": .3},
]
const PALETTES := [
	{"name": "초원", "color_root": Color(.06, .17, .10), "color_tip": Color(.38, .62, .26), "color_dry": Color(.66, .66, .30), "color_sheen": Color(.78, .92, .55), "ground": Color(.12, .22, .09), "light": Color(1, .93, .8), "energy": 1.3, "ambient": Color(.42, .48, .62)},
	{"name": "달빛 숲", "color_root": Color(.05, .08, .16), "color_tip": Color(.22, .42, .40), "color_dry": Color(.42, .40, .62), "color_sheen": Color(.62, .80, .95), "ground": Color(.08, .12, .18), "light": Color(.62, .66, 1.0), "energy": 1.1, "ambient": Color(.30, .26, .55)},
]

var grass: GrassField
var marker: MeshInstance3D
var camera: Camera3D
var sun: DirectionalLight3D
var env: Environment
var ground_mat: StandardMaterial3D
var label: Label
var wind_index := 1
var palette_index := 0
var zoom := 22.0
var mouse_idle := 99.0

func _ready() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = .55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.shadow_enabled = true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	ground.mesh = plane
	ground_mat = StandardMaterial3D.new()
	ground_mat.roughness = 1.0
	ground.material_override = ground_mat
	add_child(ground)
	marker = MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = .25
	capsule.height = 1.1
	marker.mesh = capsule
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(.55, .3, .75)
	marker.material_override = mm
	add_child(marker)
	camera = Camera3D.new()
	camera.fov = 34
	add_child(camera)
	grass = GrassField.new()
	grass.size = Vector2(48, 48)
	grass.push_target = marker
	grass.holes = [Vector3(0, 0, 1.6)] # a little clearing where the marker starts
	add_child(grass)
	label = Label.new()
	label.position = Vector2(16, 12)
	label.add_theme_font_size_override("font_size", 18)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	var ui := CanvasLayer.new()
	ui.add_child(label)
	add_child(ui)
	# Optional for captures:  -- wind=0..2 palette=0..1 zoom=22
	for arg in OS.get_cmdline_user_args():
		var kv := arg.split("=")
		if kv.size() != 2: continue
		match kv[0]:
			"wind": wind_index = clampi(kv[1].to_int(), 0, WIND.size() - 1)
			"palette": palette_index = clampi(kv[1].to_int(), 0, PALETTES.size() - 1)
			"zoom": zoom = kv[1].to_float()
	_apply()

func _apply() -> void:
	for k: String in WIND[wind_index]:
		if k != "name": grass.shader_material.set_shader_parameter(k, WIND[wind_index][k])
	var p: Dictionary = PALETTES[palette_index]
	for k in ["color_root", "color_tip", "color_dry", "color_sheen"]:
		grass.shader_material.set_shader_parameter(k, p[k])
	ground_mat.albedo_color = p.ground
	sun.light_color = p.light
	sun.light_energy = p.energy
	env.ambient_light_color = p.ambient
	env.background_color = p.ground.lightened(.25)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3: wind_index = event.keycode - KEY_1; _apply()
			KEY_P: palette_index = (palette_index + 1) % PALETTES.size(); _apply()
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP: zoom = maxf(zoom - 1.5, 8)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN: zoom = minf(zoom + 1.5, 40)
	elif event is InputEventMouseMotion:
		mouse_idle = 0.0

func _process(delta: float) -> void:
	var pitch := deg_to_rad(52.0)
	camera.position = Vector3(0, sin(pitch), cos(pitch)) * zoom
	camera.look_at(Vector3.ZERO)
	mouse_idle += delta
	var target: Vector3
	var hit = Plane.PLANE_XZ.intersects_ray(camera.project_ray_origin(get_viewport().get_mouse_position()), camera.project_ray_normal(get_viewport().get_mouse_position()))
	if mouse_idle < 2.0 and hit != null:
		target = hit
	else:
		var t := Time.get_ticks_msec() / 1000.0 * .45
		target = Vector3(cos(t) * 4.5, 0, sin(t) * 3.0)
	marker.position = marker.position.lerp(target + Vector3.UP * .55, minf(delta * 8.0, 1.0))
	label.text = "잔디 %d 묶음 · %d 청크 · %d FPS\n바람 [1/2/3]: %s   팔레트 [P]: %s   마우스: 밀어내기   휠: 줌" % [
		grass.instance_count, grass.get_child_count(), Engine.get_frames_per_second(), WIND[wind_index].name, PALETTES[palette_index].name]
