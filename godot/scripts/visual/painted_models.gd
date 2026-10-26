extends RefCounted
## Actual volumetric GLB assets; game state and collisions stay in existing wrappers.
const B := preload("res://scripts/visual/build.gd")
const M := preload("res://scripts/visual/mats.gd")
const PAINT := preload("res://shaders/painted_prop.gdshader")
const PAINT_SNOW := preload("res://shaders/painted_snow.gdshader")
static var scenes: Dictionary = {}
static var materials: Dictionary = {}

static func asset(id: String) -> Node3D:
	if not scenes.has(id):
		scenes[id] = load("res://assets/painted/" + id + ".glb")
	var root: Node3D = scenes[id].instantiate()
	_apply_paint(root,id)
	return root

static func _apply_paint(node: Node,asset_id: String) -> void:
	if node is MeshInstance3D:
		for i in node.mesh.get_surface_count():
			var source: Material = node.mesh.surface_get_material(i)
			if source == null or source.resource_name == "WarmWindow" or source.resource_name.ends_with("_Glow"):
				continue
			if source.resource_name == "Paint_Snow":
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			var key := source.get_instance_id()
			if not materials.has(key):
				var m := ShaderMaterial.new()
				m.shader = PAINT_SNOW if source.resource_name == "Paint_Snow" else PAINT
				m.resource_name = source.resource_name
				if source.resource_name == "Paint_Wood":
					m.set_shader_parameter("paint_gain", .70)
				if source.resource_name == "LodgeWood":
					m.set_shader_parameter("paint_gain",1.35)
					m.set_shader_parameter("texture_mix",.72)
					m.set_shader_parameter("painted_fill",.09)
				if source.resource_name == "LodgeStone":
					m.set_shader_parameter("paint_gain",1.20)
					m.set_shader_parameter("texture_mix",.24)
				if source.resource_name == "Paint_Foliage":
					m.set_shader_parameter("style_band_scale", 0.0)
					m.set_shader_parameter("paint_gain", 3.0)
					m.set_shader_parameter("texture_mix", .65)
					m.set_shader_parameter("painted_fill", .18)
				if source.resource_name == "Paint_Snow":
					m.set_shader_parameter("paint_gain", .76)
					m.set_shader_parameter("texture_mix", .30)
					m.set_shader_parameter("painted_fill", .07)
				if source is StandardMaterial3D:
					m.set_shader_parameter("base_color", source.albedo_color)
					if source.albedo_texture != null:
						m.set_shader_parameter("paint_texture", source.albedo_texture)
						m.set_shader_parameter("use_texture", true)
				if source.resource_name == "Paint_Foliage":
					m.set_shader_parameter("base_color", Color(.22,.38,.34))
				if source.resource_name == "LodgeWood":
					m.set_shader_parameter("base_color",Color(.80,.59,.36))
				if source.resource_name == "LodgeStone":
					m.set_shader_parameter("base_color",Color(.72,.66,.61))
				if source.resource_name == "Paint_Snow":
					var snow_color := Color(.71,.68,.94)
					if asset_id == "snow_pine": snow_color = Color(.63,.67,.82)
					if asset_id == "snow_rocks": snow_color = Color(.67,.65,.83)
					m.set_shader_parameter("base_color",snow_color)
				if source.resource_name == "Paint_Stone":
					m.set_shader_parameter("base_color", Color(.70,.68,.74))
					if asset_id == "snow_rocks":
						m.set_shader_parameter("base_color",Color(.43,.41,.43))
						m.set_shader_parameter("texture_mix",.62)
						m.set_shader_parameter("paint_gain",1.30)
					if asset_id in ["starter_lodge","extension_lodge","step_stone"]:
						m.set_shader_parameter("base_color",Color(.88,.84,.80))
						m.set_shader_parameter("texture_mix",.45)
					if asset_id == "step_stone":
						m.set_shader_parameter("base_color",Color(.65,.61,.70))
				if source.resource_name == "WallStone":
					m.set_shader_parameter("base_color", Color(.85,.75,.64))
					m.set_shader_parameter("texture_mix", .18)
				if source.resource_name in ["DragonHide","DragonScaleA","DragonScaleB","DragonScaleC"]:
					var dragon_color := Color(.80,.25,.17)
					if source.resource_name == "DragonScaleA": dragon_color = Color(.90,.29,.18)
					if source.resource_name == "DragonScaleB": dragon_color = Color(.70,.19,.13)
					if source.resource_name == "DragonScaleC": dragon_color = Color(.93,.34,.19)
					m.set_shader_parameter("base_color",dragon_color)
					m.set_shader_parameter("texture_mix",.65)
				if source.resource_name == "WingLeather":
					m.set_shader_parameter("base_color",Color(.85,.73,.72))
				if source.resource_name in ["ForestLeaf","ForestLeafLight"]:
					m.set_shader_parameter("base_color",Color(.72,.70,.82))
					m.set_shader_parameter("texture_mix",.60)
				if source.resource_name == "DragonBelly":
					m.set_shader_parameter("base_color",Color(.82,.72,.60))
				materials[key] = m
			node.set_surface_override_material(i, materials[key])
	for child in node.get_children():
		_apply_paint(child,asset_id)

static func pine(h: float) -> Node3D:
	var v := asset("snow_pine")
	v.scale = Vector3(1.12,1.0,1.12) * h / 6.4
	return v

static func rock(size: float) -> Node3D:
	var v := asset("snow_rocks")
	v.scale = Vector3(1.00,.84,1.00) * size
	return v

static func lodge(root: Node3D) -> Dictionary:
	return preload("res://scripts/visual/user_cottage.gd").build(root)

static func extension(root: Node3D) -> Node3D:
	var v := asset("extension_lodge")
	v.name = "ExtensionVisual"
	v.position = Vector3(-3.85,0,0)
	root.add_child(v)
	B.omni(v, Vector3(-.3,1.1,2.4),Color(1,.63,.30),.8,4.8,false,1.3)
	B.omni(v, Vector3(-2.3,1.1,0),Color(1,.63,.30),.6,4.0,false,1.3)
	return v

static func witch() -> Dictionary:
	var root := Node3D.new()
	var body := B.node(root, Vector3.ZERO, Vector3.ZERO, "Body")
	body.add_child(asset("witch_body"))
	var staff := B.node(body, Vector3(0.28,0,0.10), Vector3(8,0,0), "Staff")
	staff.add_child(asset("witch_staff"))
	var tip := B.node(staff, Vector3(0,1.14,0), Vector3.ZERO, "Tip")
	var head := B.node(body, Vector3(0,0.68,0), Vector3.ZERO, "Head")
	return {"root": root, "body": body, "head": head, "staff": staff, "tip": tip}

static func traveler() -> Node3D:
	var root := Node3D.new()
	var body := B.node(root,Vector3.ZERO,Vector3.ZERO,"Body")
	body.add_child(asset("winter_traveler"))
	return root

static func monster() -> Node3D:
	var root := Node3D.new()
	var body := B.node(root,Vector3.ZERO,Vector3.ZERO,"Body")
	body.add_child(asset("forest_monster"))
	return root

static func dragon() -> Dictionary:
	var root := Node3D.new()
	var body := B.node(root,Vector3.ZERO,Vector3.ZERO,"Body")
	body.add_child(asset("dragon_body"))
	var neck := B.node(body,Vector3(0,1.75,.95),Vector3(32,0,0),"Neck")
	neck.add_child(asset("dragon_neck"))
	var head := B.node(neck,Vector3(0,2.45,0),Vector3(-30,0,0),"Head")
	head.add_child(asset("dragon_head"))
	var mouth := B.node(head,Vector3(0,-.15,1.7),Vector3.ZERO,"Mouth")
	var wings: Array = []
	for s: float in [-1.0,1.0]:
		var pivot := B.node(body,Vector3(s,2,.2),Vector3(0,s*-12,s*-24),"Wing")
		var wing := asset("dragon_wing")
		wing.scale.x = s
		pivot.add_child(wing)
		wings.append(pivot)
	var ember := B.omni(root,Vector3(0,1.2,1.9),Color(1,.5,.2),2.0,7.0,false,1.2)
	return {"root":root,"body":body,"neck":neck,"head":head,"mouth":mouth,"wings":wings,"ember":ember}

static func sheep() -> Node3D:
	var root := Node3D.new()
	var body := B.node(root,Vector3.ZERO,Vector3.ZERO,"Body")
	var model := asset("sheep")
	body.add_child(model)
	var head := B.node(body,Vector3(0,.47,.47),Vector3.ZERO,"Head")
	for child in model.get_children():
		var label := str(child.name).replace("_"," ").to_lower()
		if child is MeshInstance3D and (label.contains("dark face") or label.contains("forehead wool") or label.contains("small sheep ear")):
			var old_transform: Transform3D = child.transform
			child.owner = null
			child.reparent(head,false)
			child.transform = head.transform.affine_inverse()*old_transform
	return root

static func fence(parent: Node3D, a: Vector3, b: Vector3, skip := false) -> void:
	var wood := M.solid(Color("866045"), {"rim_strength": 0.07, "sky_fill": 0.08})
	var snow := M.solid(Color("beb5ef"), {"rim_strength": 0.03, "sky_fill": 0.08})
	var d := b-a
	var length := d.length()
	var bays := maxi(1, ceili(length/1.4))
	var yaw := rad_to_deg(atan2(d.x,d.z))
	for i in range(bays+1):
		if i == 0 and skip: continue
		var p := a + d * float(i)/bays
		# BevelBoxMesh gives posts/rails the same hand-carved silhouette as imported assets.
		B.bevel_box(parent, Vector3(.24,.9,.24), p+Vector3(0,.45,0), wood,.04)
		B.bevel_box(parent, Vector3(.28,.075,.28),p+Vector3(0,.93,0),snow,.025)
	for y: float in [.30,.65]:
		B.bevel_box(parent,Vector3(.13,.15,length),(a+b)*.5+Vector3(0,y,0),wood,.03,Vector3(0,yaw,0))

static func gate(parent: Node3D, hinge_pos: Vector3, far_post: Vector3) -> void:
	var wood := M.solid(Color("866045"), {"rim_strength": .07, "sky_fill": .08})
	var snow := M.solid(Color("beb5ef"), {"rim_strength": .03, "sky_fill": .08})
	var hinge := B.node(parent,hinge_pos,Vector3(0,105,0),"GateHinge")
	for y: float in [.28,.66]:
		B.bevel_box(hinge,Vector3(.14,.16,1.40),Vector3(0,y,.72),wood,.035)
	for z: float in [.08,.72,1.38]:
		B.bevel_box(hinge,Vector3(.14,.65,.18),Vector3(0,.47,z),wood,.035)
	B.bevel_box(hinge,Vector3(.14,.13,1.45),Vector3(0,.47,.72),wood,.025,Vector3(-25,0,0))
	for p in [hinge_pos,far_post]:
		B.bevel_box(parent,Vector3(.24,.95,.24),p+Vector3(0,.47,0),wood,.04)
		B.bevel_box(parent,Vector3(.28,.075,.28),p+Vector3(0,.98,0),snow,.025)
