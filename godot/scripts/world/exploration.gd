extends RefCounted
## Sparse forest and four landmarks. Collision/bake ownership stays with World.
const Layout := preload("res://scripts/world/layout.gd")
const Models := preload("res://scripts/visual/models.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Cfg := preload("res://scripts/config.gd")
const Forest := preload("res://scripts/world/forest_composition.gd")


static func build(world, rng: RandomNumberGenerator) -> void:
	Forest.build(world)
	var decor := B.node(world, Vector3.ZERO, Vector3.ZERO, "ExplorationLandmarks")
	for landmark in Layout.LANDMARKS:
		var p: Vector2 = landmark.pos
		var site := B.node(decor, Vector3(p.x,0,p.y), Vector3.ZERO, landmark.id)
		match landmark.id:
			"logging":
				var timber := [[-3.2,-2.0,72.0,.82],[-2.1,-3.2,89.0,.90],[-3.7,-3.8,61.0,.65]]
				for piece in timber:
					var log_prop := Models.make_log()
					log_prop.position = Vector3(piece[0],0,piece[1])
					log_prop.rotation_degrees.y = piece[2]
					log_prop.scale = Vector3.ONE*piece[3]
					site.add_child(log_prop)
				_rock(world, p+Vector2(3,-5.5), 0.85, rng)
				_sign(site, Vector3(-3,0,2.8))
			"shrine":
				for i in 5:
					var a := TAU * i / 5.0
					var at := p + Vector2(cos(a), sin(a)) * 4.5
					_rock(world, at, 0.6 if i % 2 == 0 else 0.8, rng)
				var stone := Models.make_stepping_stone(rng)
				stone.scale = Vector3(2.4,1.0,2.4)
				site.add_child(stone)
				B.torus(site, 0.7, 0.78, Vector3(0,0.12,0), Mats.unshaded(Color(.44,.77,1.0)))
				B.omni(site, Vector3(0,1.1,0), Color(.35,.60,1.0), .65, 6.0)
			"camp":
				for piece in [[-3.0,-1.5,-21.0,.85],[2.7,-2.4,33.0,.88]]:
					var log_prop := Models.make_log()
					log_prop.position = Vector3(piece[0],0,piece[1])
					log_prop.rotation_degrees.y = piece[2]
					log_prop.scale = Vector3.ONE*piece[3]
					site.add_child(log_prop)
				for i in 6:
					var a := TAU*i/6.0
					var stone := Models.make_stepping_stone(rng)
					stone.position = Vector3(cos(a),0,sin(a))*.8
					stone.scale = Vector3.ONE*.5
					site.add_child(stone)
				B.cyl(site, .12,.32,.55, Vector3(0,.32,0), Mats.unshaded(Color(1.0,.5,.13)), 6)
				B.omni(site, Vector3(0,.9,0), Color(1,.55,.23), .9, 7.0)
				_sign(site, Vector3(2.5,0,3))
			"lookout":
				for piece in [[4.0,3.0,.95],[6.5,2.0,.70],[6.0,5.0,.54]]:
					_rock(world,p+Vector2(piece[0],piece[1]),piece[2],rng)
				_sign(site, Vector3(-3,0,3))
	# Signs mark the two outbound paths before the lodge disappears from view.
	_sign(decor, Vector3(-14,0,7.8))
	_sign(decor, Vector3(10.8,0,-15.5))


static func _rock(world, at: Vector2, size: float, rng: RandomNumberGenerator) -> void:
	var body := StaticBody3D.new()
	body.name = "TrailRock"
	body.position = Vector3(at.x,0,at.y)
	body.collision_layer = Cfg.L_OBSTACLE
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.35*size
	shape.height = maxf(Cfg.OBSTACLE_MIN_HEIGHT, 1.6*size)
	cs.shape = shape
	cs.position.y = shape.height*.5
	body.add_child(cs)
	body.add_child(Models.make_rock(size,rng))
	world.nav_region.add_child(body)


static func _sign(parent: Node3D, at: Vector3) -> void:
	var wood := Mats.solid(Color("785441"))
	B.box(parent, Vector3(.18,1.7,.18), at+Vector3(0,.85,0), wood)
	B.box(parent, Vector3(1.5,.4,.18), at+Vector3(0,1.5,0), wood, Vector3(0,-25,0))
	B.sphere(parent, .11, at+Vector3(0,1.95,0), Mats.unshaded(Color(1,.73,.34)), Vector3.ONE, 8, 4)
