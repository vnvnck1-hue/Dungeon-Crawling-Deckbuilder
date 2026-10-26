extends Node3D
## Terrain/props/VFX are authored here; resident combat is owned by VenomInsect.
const Sites := preload("res://scripts/world/hazard_sites.gd")
const Kit := preload("res://scripts/visual/toxic_kit.gd")
const Insect := preload("res://scripts/actors/venom_insect.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Cfg := preload("res://scripts/config.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const FISSURE := preload("res://shaders/toxic_fissure.gdshader")
const MIST := preload("res://shaders/toxic_mist.gdshader")
const TERRAIN := preload("res://assets/hazards/painted_toxic_slate_v1.png")
const FRACTURES := [
	[Vector2(-.98,-.34),Vector2(-.79,-.22),Vector2(-.62,-.26),Vector2(-.48,-.10),Vector2(-.39,.12),Vector2(-.19,.22),Vector2(-.05,.49),Vector2(.17,.64),Vector2(.24,.85)],
	[Vector2(-.62,-.26),Vector2(-.54,-.48),Vector2(-.33,-.58),Vector2(-.27,-.78)],
	[Vector2(-.39,.12),Vector2(-.57,.32),Vector2(-.58,.54),Vector2(-.77,.66)],
	[Vector2(-.19,.22),Vector2(-.03,.12),Vector2(.08,.19)],
	[Vector2(.85,-.48),Vector2(.61,-.36),Vector2(.59,-.13),Vector2(.36,.01),Vector2(.32,.18),Vector2(.14,.28)],
	[Vector2(.61,-.36),Vector2(.40,-.47),Vector2(.38,-.67),Vector2(.19,-.81)],
	[Vector2(.32,.18),Vector2(.50,.36),Vector2(.71,.33),Vector2(.85,.49)],
	[Vector2(-.10,-.27),Vector2(.05,-.34),Vector2(.13,-.52),Vector2(.25,-.54)],
]
var world
var influence := 0.0
var active_site: Dictionary={}
var inhabitants: Array=[]
var smoke_emitters: Array[CPUParticles3D]=[]
var fissure_materials: Array[ShaderMaterial]=[]
var pulse_lights: Array[OmniLight3D]=[]
var _clock:=0.0
var _last_label:=""
var _bound:=false

func build(owner_world) -> void:
	world=owner_world
	name="HazardRegions"
	process_priority=24 # after day clock and air, before the fog-of-war overlay
	var packets:=PackedVector4Array()
	for site in Sites.SITES:
		packets.append(Vector4(site.center.x,site.center.y,site.radii.x,site.radii.y))
		_build_site(site)
	world.ground_mat.set_shader_parameter("toxic_ground",TERRAIN)
	world.ground_mat.set_shader_parameter("toxic_sites",packets)

func bind_residents() -> void:
	if _bound: return
	_bound=true
	# A freshly baked region reaches NavigationServer on the next physics synchronization.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var nav_map: RID=world.get_world_3d().navigation_map
	NavigationServer3D.map_force_update(nav_map)
	while NavigationServer3D.map_get_iteration_id(nav_map)==0:
		await get_tree().physics_frame
	# Another startup module may replace the mesh (e.g. a rebuilt pasture).
	# Map iteration > 0 alone also describes a synchronized *empty* map.
	var probe:=Vector3(Sites.SITES[0].center.x,0,Sites.SITES[0].center.y)
	for retry in 120:
		NavigationServer3D.map_force_update(nav_map)
		var closest:=NavigationServer3D.map_get_closest_point(nav_map,probe)
		if closest.distance_to(probe)<1.0: break
		await get_tree().physics_frame
	if NavigationServer3D.map_get_closest_point(nav_map,probe).distance_to(probe)>1.0:
		push_error("Hazard residents could not find the baked terrain")
		return
	for site in Sites.SITES:
		for i in int(site.count):
			var angle:=TAU*i/float(site.count)+.4
			var flat: Vector2=site.center+Vector2(cos(angle),sin(angle))*Vector2(site.radii)*(.26 if i%2==0 else .52)
			var at:=NavigationServer3D.map_get_closest_point(nav_map,Vector3(flat.x,0,flat.y))
			at.y=0.0
			var insect:=Insect.new()
			insect.setup(world.game,site,at,i%3==1,i)
			world.game.actors.add_child(insect)
			inhabitants.append(insect)

func _build_site(site: Dictionary) -> void:
	var rng:=RandomNumberGenerator.new()
	rng.seed=int(site.seed)
	var center: Vector2=site.center
	var radii: Vector2=site.radii
	var root:=B.node(self,Vector3(center.x,0,center.y),Vector3.ZERO,str(site.id).to_pascal_case())
	root.set_meta("hazard_site",site.id)
	root.set_meta("label",site.label)
	# Two merged surfaces per site: inky broken lips and narrow living-green fissures.
	var dark_st:=SurfaceTool.new()
	var glow_st:=SurfaceTool.new()
	dark_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	glow_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sources:=PackedVector3Array()
	var rotation:=.0 if site.id=="venom_hollow" else (.65 if site.id=="wing_nest" else -1.1)
	for branch in FRACTURES:
		var points:=PackedVector2Array()
		for p: Vector2 in branch:
			points.append((p.rotated(rotation)*radii)+Vector2(rng.randf_range(-.12,.12),rng.randf_range(-.12,.12)))
		points=_fracture_detail(points,rng)
		_ribbon(dark_st,points,.18,.010,rng)
		_ribbon(glow_st,points,.085,.017,rng)
		for i in range(0,points.size(),2): sources.append(Vector3(points[i].x,.06,points[i].y))
		# Hairline branches taper away from the broken slabs rather than forming straight pipes.
		for i in range(3,points.size()-2,5):
			var a: Vector2=points[i]
			var direction: Vector2=(points[i+1]-points[i-1]).normalized().rotated((1.0 if i%2==0 else -1.0)*rng.randf_range(.8,1.5))
			var end:=a+direction*rng.randf_range(.45,1.05)
			var spur:=PackedVector2Array([a,a.lerp(end,.5)+Vector2(-direction.y,direction.x)*.12,end])
			_ribbon(dark_st,spur,.09,.011,rng)
			_ribbon(glow_st,spur,.04,.018,rng)
	var lip:=B.mi(root,dark_st.commit(),Vector3.ZERO,Mats.unshaded(Color("132b30")))
	lip.name="FissureBrokenEdges"
	lip.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat:=ShaderMaterial.new()
	mat.shader=FISSURE
	mat.set_shader_parameter("phase",rng.randf()*TAU)
	fissure_materials.append(mat)
	var cracks:=B.mi(root,glow_st.commit(),Vector3.ZERO,mat)
	cracks.name="PulsingVenomFissures"
	cracks.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_smoke(root,sources,rng)
	for layer in 3:
		var mist:=ShaderMaterial.new()
		mist.shader=MIST
		mist.set_shader_parameter("phase",rng.randf()*20.0)
		mist.set_shader_parameter("mist_color",Color(.23,.66,.24,.22 if layer==0 else .12))
		var plane:=PlaneMesh.new()
		plane.size=radii*Vector2(2.5,2.5)
		var mesh:=B.mi(root,plane,Vector3(0,.23+layer*.48,0),mist)
		mesh.name="GroundVenomHaze"
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# A few local lights tint rocks and the hanging haze; the emissive core stays sharp.
	for i in 3:
		var p:=sources[int(i*sources.size()/3)]
		var light:=B.omni(root,p+Vector3(0,.5,0),Color("9bd64e"),.28,3.4,false,1.6)
		light.set_meta("phase",rng.randf()*TAU)
		pulse_lights.append(light)
	# Open entrance on the home side; irregular chitin nests and bent trunks frame the rear.
	var toward_home:=(-center).angle()
	for i in 9:
		var angle:=toward_home+.65+float(i)/8.0*(TAU-1.3)
		var flat:=Vector2(cos(angle),sin(angle))*radii*rng.randf_range(.85,1.05)
		if i%3==0:
			var tree:=Kit.dead_tree(rng)
			tree.position=Vector3(flat.x,0,flat.y)
			tree.rotation.y=rng.randf()*TAU
			root.add_child(tree)
			_obstacle(center+flat,.34,2.0)
		else:
			var rock:=Kit.rock(rng)
			rock.position=Vector3(flat.x,0,flat.y)
			rock.scale=Vector3.ONE*rng.randf_range(.9,1.6)
			root.add_child(rock)
	for i in 3:
		var angle:=toward_home+PI+(i-1)*.63
		var flat:=Vector2(cos(angle),sin(angle))*radii*(.6 if i==1 else .72)
		var nest:=Kit.nest()
		nest.position=Vector3(flat.x,0,flat.y)
		nest.rotation.y=rng.randf()*TAU
		root.add_child(nest)
	for i in 23:
		var angle:=rng.randf()*TAU
		var flat:=Vector2(cos(angle),sin(angle))*radii*rng.randf_range(.77,1.18)
		var fern:=Kit.fern(rng)
		fern.position=Vector3(flat.x,.01,flat.y)
		fern.scale=Vector3.ONE*rng.randf_range(.6,1.1)
		root.add_child(fern)
	for i in 5:
		var bones:=Kit.bones()
		bones.position=Vector3(rng.randf_range(-.75,.75)*radii.x,.02,rng.randf_range(-.65,.65)*radii.y)
		bones.rotation.y=rng.randf()*TAU
		root.add_child(bones)

func _obstacle(at: Vector2, radius: float, height: float) -> void:
	var body:=StaticBody3D.new()
	body.name="HazardTrunkCollision"
	body.position=Vector3(at.x,0,at.y)
	body.collision_layer=Cfg.L_OBSTACLE
	body.collision_mask=0
	var cs:=CollisionShape3D.new()
	var shape:=CylinderShape3D.new()
	shape.radius=radius
	shape.height=maxf(Cfg.OBSTACLE_MIN_HEIGHT,height)
	cs.shape=shape
	cs.position.y=shape.height*.5
	body.add_child(cs)
	world.nav_region.add_child(body)

func _fracture_detail(points: PackedVector2Array, rng: RandomNumberGenerator) -> PackedVector2Array:
	var result:=PackedVector2Array()
	for i in points.size()-1:
		var a:=points[i]
		var b:=points[i+1]
		var direction:=(b-a).normalized()
		var perp:=Vector2(-direction.y,direction.x)
		var steps:=maxi(2,ceili(a.distance_to(b)/.42))
		for j in steps:
			var p:=a.lerp(b,j/float(steps))
			if j>0: p+=perp*rng.randf_range(-.115,.115)
			result.append(p)
	result.append(points[-1])
	return result

func _ribbon(st: SurfaceTool, points: PackedVector2Array, width: float, height: float, rng: RandomNumberGenerator) -> void:
	var run:=rng.randf()*9.0
	var offsets:=PackedVector2Array()
	for i in points.size():
		var tangent:=(points[mini(i+1,points.size()-1)]-points[maxi(i-1,0)]).normalized()
		var taper:=smoothstep(0.0,.20,float(points.size()-1-i)/float(points.size()-1))
		var rough:=.60+.40*absf(sin(points[i].dot(Vector2(13.73,7.83))))
		offsets.append(Vector2(-tangent.y,tangent.x)*width*rough*maxf(.025,taper))
	for i in points.size()-1:
		var a:=points[i]
		var b:=points[i+1]
		var vertices:=[a-offsets[i],a+offsets[i],b+offsets[i+1],b-offsets[i+1]]
		var uv:=[Vector2(run,0),Vector2(run,1),Vector2(run+a.distance_to(b),1),Vector2(run+a.distance_to(b),0)]
		for index in [0,1,2,0,2,3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uv[index])
			st.add_vertex(Vector3(vertices[index].x,height,vertices[index].y))
		run+=a.distance_to(b)

func _smoke(root: Node3D, points: PackedVector3Array, rng: RandomNumberGenerator) -> void:
	var particles:=CPUParticles3D.new()
	particles.name="FissurePoisonVapour"
	particles.amount=65
	particles.lifetime=6.0
	particles.preprocess=5.0
	particles.randomness=.6
	particles.local_coords=true
	particles.emission_shape=CPUParticles3D.EMISSION_SHAPE_POINTS
	particles.emission_points=points
	particles.direction=Vector3(.25,1,.10)
	particles.spread=19.0
	particles.gravity=Vector3(.015,.015,0)
	particles.initial_velocity_min=.12
	particles.initial_velocity_max=.28
	particles.scale_amount_min=.6
	particles.scale_amount_max=1.75
	particles.angular_velocity_min=-10
	particles.angular_velocity_max=10
	particles.color=Color(.37,.75,.12,.17)
	var gradient:=Gradient.new()
	gradient.set_color(0,Color(1,1,1,0))
	gradient.add_point(.18,Color.WHITE)
	gradient.add_point(.62,Color(1,1,1,.65))
	gradient.set_color(1,Color(1,1,1,0))
	particles.color_ramp=gradient
	var quad:=QuadMesh.new()
	quad.size=Vector2(1.0,1.0)
	var mat:=Mats.particle(Color.WHITE)
	mat.emission_enabled=true
	mat.emission=Color(.08,.22,.015)
	mat.emission_energy_multiplier=.3
	quad.material=mat
	particles.mesh=quad
	particles.seed=rng.randi()
	root.add_child(particles)
	smoke_emitters.append(particles)

var _sent_influence:=-1.0

func _process(delta: float) -> void:
	if world==null or world.game.player==null or world.day_cycle==null: return
	_clock+=delta
	var player: Vector3=world.game.player.global_position
	var wanted:=Sites.influence_at(Vector2(player.x,player.z))
	influence=move_toward(influence,wanted,delta*.8)
	active_site=Sites.site_at(Vector2(player.x,player.z))
	if influence!=_sent_influence:
		_sent_influence=influence
		world.post_mat.set_shader_parameter("toxic_amount",influence)
	Sfx.loop(self, "hazard_amb", "hazard_amb", influence)
	# The day clock rewrites the base lighting while this blends (day_cycle checks influence). At 0 the lerps are identities.
	if influence>0.0:
		world.env.ambient_light_color=world.env.ambient_light_color.lerp(Color("438879"),influence*.72)
		world.env.ambient_light_energy=lerpf(world.env.ambient_light_energy,.42,influence*.86)
		world.sun.light_color=world.sun.light_color.lerp(Color("9dd6aa"),influence*.88)
		world.sun.light_energy=lerpf(world.sun.light_energy,.54,influence*.9)
		world.env.glow_intensity=lerpf(world.env.glow_intensity,.5,influence)
		world.env.glow_hdr_threshold=lerpf(world.env.glow_hdr_threshold,1.0,influence)
	if world.aerial_perspective!=null:
		var focus: Vector3=world.player_camera.focus if world.player_camera!=null else player
		var color: Color=world.aerial_perspective.color_at(focus-world.camera.global_basis.z*8.0).linear_to_srgb()
		world.env.fog_light_color=color.lerp(Color("44794d"),influence*.83)
	for light in pulse_lights:
		var phase: float=light.get_meta("phase")
		light.light_energy=.25+pow(maxf(0.0,sin(_clock*1.12+phase)),12.0)*.32
	var label: String=str(active_site.get("label",""))
	if label!=_last_label:
		_last_label=label
		if label!="": world.game.toast(label+" · 맹독 곤충 서식지",Color(.65,.95,.25))
		if label!="": Sfx.play(self, "hazard_enter")
