extends RefCounted
## Data-authored forest islands. World owns obstacle bodies and camera occluders.
const DATA := "res://assets/environment/forest_layout.json"
const Nature := preload("res://scripts/visual/nature_models.gd")
const Cfg := preload("res://scripts/config.gd")
const Hazards := preload("res://scripts/world/hazard_sites.gd")
static var _layout: Dictionary = {}

static func layout() -> Dictionary:
	if _layout.is_empty():
		_layout = JSON.parse_string(FileAccess.get_file_as_string(DATA))
	return _layout

static func vector(values: Array) -> Vector3:
	return Vector3(values[0],values[1],values[2])

static func build(world) -> void:
	var decor := Node3D.new()
	decor.name = "ForestComposition"
	world.add_child(decor)
	for group in layout().groups:
		var group_node := Node3D.new()
		group_node.name = str(group.id).to_pascal_case()
		group_node.set_meta("forest_cluster",group.id)
		group_node.set_meta("motif",group.motif)
		group_node.set_meta("label",group.label)
		decor.add_child(group_node)
		if group.linked_harvest != null:
			var at := Vector3(group.linked_harvest[0],0,group.linked_harvest[1])
			for tree in world.harvest_trees:
				if tree.pos.distance_to(at)<.05:
					tree.body.set_meta("forest_cluster",group.id)
					tree.visual.set_meta("forest_cluster",group.id)
					tree.visual.set_meta("placement_role","resource_anchor")
		for part: Dictionary in group.parts:
			var at := Vector2(part.position[0],part.position[1])
			if Hazards.clearing_at(at): continue
			var scale := vector(part.scale)
			var rotation := vector(part.rotation)
			if part.kind == "tree":
				var tree: Dictionary = world._add_tree(at,part.height,part.asset,scale,rotation,part.canopy_radius)
				tree.body.name = str(group.id).to_pascal_case()+"Tree"
				tree.body.set_meta("forest_cluster",group.id)
				tree.visual.set_meta("forest_cluster",group.id)
				tree.visual.set_meta("placement_role",part.role)
			elif part.kind == "rock":
				var body := StaticBody3D.new()
				body.name = str(group.id).to_pascal_case()+"Rock"
				body.position = Vector3(at.x,0,at.y)
				body.collision_layer = Cfg.L_OBSTACLE
				body.collision_mask = 0
				body.set_meta("forest_cluster",group.id)
				var shape := CylinderShape3D.new()
				shape.radius = part.collider_radius
				shape.height = clampf(part.height,Cfg.OBSTACLE_MIN_HEIGHT,3.0)
				var cs := CollisionShape3D.new()
				cs.shape = shape
				cs.position.y = shape.height*.5
				body.add_child(cs)
				var model := Nature.asset(part.asset)
				model.scale = scale
				model.rotation_degrees = rotation
				model.set_meta("forest_cluster",group.id)
				model.set_meta("placement_role",part.role)
				body.add_child(model)
				world.nav_region.add_child(body)
			else:
				var model := Nature.asset(part.asset)
				model.position = Vector3(at.x,0,at.y)
				model.scale = scale
				model.rotation_degrees = rotation
				model.set_meta("forest_cluster",group.id)
				model.set_meta("placement_role",part.role)
				group_node.add_child(model)
