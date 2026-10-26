extends Node3D
## Reference-inspired color pools and low ground haze. No gameplay or collision state.
## Built once per world; switching styles disables every light and haze together.
const HAZE_SHADER := preload("res://shaders/ground_haze.gdshader")
const POOLS := [
	{"name":"MagentaLeft", "pos":Vector3(-6.5,2.5,8.5), "range":10.5, "energy":3.8, "magenta":true},
	{"name":"MagentaRight", "pos":Vector3(12.5,2.8,-2.0), "range":11.0, "energy":4.2, "magenta":true},
	{"name":"VioletBack", "pos":Vector3(-3.0,3.5,-9.0), "range":10.0, "energy":2.4, "magenta":true},
	{"name":"BlueClearing", "pos":Vector3(3.5,5.5,6.0), "range":13.5, "energy":1.15, "magenta":false},
	{"name":"BlueForest", "pos":Vector3(-12.0,3.0,1.0), "range":9.0, "energy":.8, "magenta":false}
]
var lights: Array[OmniLight3D] = []
var haze_materials: Array[ShaderMaterial] = []
var haze_meshes: Array[MeshInstance3D] = []

func build() -> void:
	for pool in POOLS:
		var light := OmniLight3D.new()
		light.name = pool.name
		light.position = pool.pos
		light.omni_range = pool.range
		light.omni_attenuation = 1.25
		light.light_specular = 0.0
		light.light_energy = 0.0
		light.shadow_enabled = false
		light.visible = false
		add_child(light)
		lights.append(light)
	# These are translucent world-space planes, occluded by props, below actor heads.
	# Fixed orthographic camera makes a light haze layer sufficient; no global fog cost.
	for at in [Vector3(-6.5,.35,8.5),Vector3(12.5,.45,-2.0),Vector3(-3.0,.40,-9.0)]:
		var mesh := MeshInstance3D.new()
		mesh.name = "GroundHaze"
		var plane := PlaneMesh.new()
		plane.size = Vector2(14.0,10.0)
		mesh.mesh = plane
		mesh.position = at
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := ShaderMaterial.new()
		material.shader = HAZE_SHADER
		mesh.material_override = material
		mesh.visible = false
		add_child(mesh)
		haze_materials.append(material)
		haze_meshes.append(mesh)

func configure(p: Dictionary) -> void:
	var enabled: bool = p.rig_energy > 0.0
	for i in lights.size():
		var pool: Dictionary = POOLS[i]
		lights[i].visible = enabled
		lights[i].light_energy = pool.energy*p.rig_energy
		lights[i].light_color = p.magenta_color if pool.magenta else p.cyan_color
	for i in haze_meshes.size():
		haze_meshes[i].visible = enabled and p.haze_opacity > 0.0
		haze_materials[i].set_shader_parameter("opacity", p.haze_opacity)
		haze_materials[i].set_shader_parameter("haze_color", p.magenta_color)
