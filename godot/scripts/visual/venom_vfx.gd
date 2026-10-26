extends RefCounted
## Bounded transient spray and spreading ground ichor, shared by both insect variants.
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Pool := preload("res://scripts/visual/vfx/vfx_pool.gd")
const GREEN := Color(.40,.88,.055)
const LIMIT := 48

static func spray(world, at: Vector3, direction: Vector3, fatal := false) -> void:
	var pool = world.vfx_pool
	if pool == null: return
	for i in (28 if fatal else 13):
		var velocity:=Vector3(randf_range(-1.8,1.8),randf_range(.6,2.7),randf_range(-1.8,1.8))
		velocity+=direction*.7
		pool.emit(Pool.GLOW,at,velocity,randf_range(.35,.85),randf_range(.055,.13),GREEN,
			{"gravity":-6.5,"grow":.45,"align":true,"aspect":.65,"land":true})
	for i in (5 if fatal else 2):
		pool.emit(Pool.PUFF,at,Vector3(randf_range(-.3,.3),.45,randf_range(-.3,.3)),.7,.3,
			Color(.28,.64,.09,.45),{"grow":2.2,"fade_in":.06})
	# Separate impacts leave small spatters; fatal impacts spread a persistent large pool.
	puddle(world,Vector3(at.x,0,at.z),1.1 if fatal else .24)
	if fatal:
		for i in 4:
			var angle:=randf()*TAU
			puddle(world,Vector3(at.x+cos(angle)*randf_range(.55,1.25),0,at.z+sin(angle)*randf_range(.55,1.25)),randf_range(.15,.32))

static func puddle(world, at: Vector3, radius: float) -> void:
	var prior: Array=world.get_tree().get_nodes_in_group("venom_puddles")
	while prior.size()>=LIMIT:
		var old: Node=prior.pop_front()
		old.remove_from_group("venom_puddles")
		old.queue_free()
	var st:=SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var points:=PackedVector3Array()
	var phase:=randf()*TAU
	for i in 24:
		var a:=TAU*i/24.0
		var r:=radius*(.83+.10*sin(a*5.0+phase)+.065*sin(a*9.0+phase))
		points.append(Vector3(cos(a)*r,0,sin(a)*r*.78))
	for i in 24:
		for v: Vector3 in [Vector3.ZERO,points[i],points[(i+1)%24]]:
			st.set_normal(Vector3.UP)
			st.add_vertex(v)
	var mat:=Mats.unshaded(Color(.16,.41,.025),false)
	mat.emission_enabled=true
	mat.emission=Color(.24,.68,.035)
	mat.emission_energy_multiplier=.55
	var mi:=B.mi(world,st.commit(),at+Vector3(0,.027+randf()*.004,0),mat)
	mi.name="VenomIchorPool"
	mi.add_to_group("venom_puddles")
	mi.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.scale=Vector3.ONE*.2
	var tw:=mi.create_tween()
	tw.tween_property(mi,"scale",Vector3.ONE,.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(54.0)
	tw.tween_property(mi,"transparency",1.0,5.0)
	tw.tween_callback(mi.queue_free)
