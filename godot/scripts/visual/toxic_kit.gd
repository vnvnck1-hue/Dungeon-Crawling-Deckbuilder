extends RefCounted
## Purpose-built venom biome geometry. No borrowed snow props or insect stand-ins.
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const WING := preload("res://shaders/toxic_wing.gdshader")
static var _wing_mat: ShaderMaterial

static func material(hex: String, emission := 0.0) -> ShaderMaterial:
	var c := Color(hex)
	return Mats.solid(c,{"noise_amount":.12,"noise_scale":2.0,"sky_fill":.35,
		"rim_strength":.25,"rim_color":Color("69a68a"),"emission_color":c,"emission_energy":emission})

## A faceted asymmetric chitin shield with a raised keel, not an ellipsoid.
static func plate(parent: Node3D, at: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	var points := PackedVector3Array([Vector3(0,.10,.64),Vector3(-.45,.02,.24),Vector3(-.5,0,-.22),
		Vector3(-.19,-.06,-.62),Vector3(.19,-.06,-.62),Vector3(.5,0,-.22),Vector3(.45,.02,.24),Vector3(0,.42,-.03)])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 7:
		for index in [i,7,(i+1)%7]:
			st.set_uv(Vector2(points[index].x+.5,points[index].z+.62))
			st.add_vertex(points[index]*size)
	st.generate_normals()
	var mesh := st.commit()
	return B.mi(parent,mesh,at,mat,rot)

static func limb(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material, tip_radius := -1.0) -> MeshInstance3D:
	var length := a.distance_to(b)
	var n := B.cyl(parent,radius*.75 if tip_radius<0.0 else tip_radius,radius,length,(a+b)*.5,mat,6)
	n.quaternion = Quaternion(Vector3.UP,(b-a).normalized())
	return n

## Merge static pieces by material while preserving animated pivots above this root.
static func fuse(root: Node3D) -> void:
	var groups := {}
	for mesh: MeshInstance3D in root.find_children("*","MeshInstance3D",true,false):
		if mesh.material_override == null: continue
		var mat: Material = mesh.material_override
		if not groups.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			groups[mat] = st
		var xf := root.global_transform.affine_inverse()*mesh.global_transform if root.is_inside_tree() else _relative(mesh,root)
		for surface in mesh.mesh.get_surface_count(): groups[mat].append_from(mesh.mesh,surface,xf)
		mesh.get_parent().remove_child(mesh)
		mesh.free()
	for mat: Material in groups:
		var st: SurfaceTool=groups[mat]
		st.index()
		B.mi(root,st.commit(),Vector3.ZERO,mat)

static func _relative(node: Node3D, root: Node3D) -> Transform3D:
	var xf := node.transform
	var parent := node.get_parent()
	while parent != root and parent is Node3D:
		xf = parent.transform*xf
		parent = parent.get_parent()
	return xf

static func insect() -> Node3D:
	var root := Node3D.new()
	root.name="VenomInsect"
	var body := B.node(root,Vector3.ZERO,Vector3.ZERO,"Body")
	var armor := material("567471",.16)
	var ridge := material("819c88",.13)
	var dark := material("202733",.09)
	var purple := material("443452",.08)
	var hot := Mats.glow(Color("a2f555"),1.35)
	var teeth := material("c5c98f",.15)
	var shell := B.node(body,Vector3.ZERO,Vector3.ZERO,"Shell")
	# Long tapered, overlapping abdomen and chunky thorax.
	B.sphere(shell,.38,Vector3(0,.73,-.44),purple,Vector3(.85,.73,1.9),10,5)
	for i in 4:
		var z := -.12-i*.25
		var w := .92-i*.13
		plate(shell,Vector3(0,.97-i*.055,z),Vector3(w,.8,.67),armor)
		plate(shell,Vector3(0,1.12-i*.045,z-.04),Vector3(.13,.32,.55),ridge)
		for side: float in [-1.0,1.0]:
			limb(shell,Vector3(side*w*.34,.91,z-.15),Vector3(side*w*.73,1.12,z-.43),.075,purple,0.0)
	B.sphere(shell,.42,Vector3(0,.85,.25),dark,Vector3(1.0,.8,1.0),10,5)
	plate(shell,Vector3(0,1.0,.25),Vector3(1.0,.78,.95),armor)
	# Mask-shaped head, tall crown horns, mandibles and four compound eyes.
	plate(shell,Vector3(0,.94,.77),Vector3(.69,.7,.75),ridge,Vector3(-28,0,0))
	plate(shell,Vector3(0,.81,.98),Vector3(.37,.5,.5),purple,Vector3(-56,0,0))
	for side: float in [-1.0,1.0]:
		limb(shell,Vector3(side*.24,1.1,.68),Vector3(side*.34,1.72,.45),.12,armor,0.0)
		B.sphere(shell,.11,Vector3(side*.235,1.02,.94),hot,Vector3(.68,1.13,.52),8,4)
		B.sphere(shell,.067,Vector3(side*.32,.94,.85),hot,Vector3.ONE,8,4)
		limb(shell,Vector3(side*.19,.76,.95),Vector3(side*.33,.59,1.22),.09,purple,.055)
		limb(shell,Vector3(side*.33,.59,1.22),Vector3(side*.11,.63,1.36),.062,teeth,0.0)
		limb(shell,Vector3(side*.09,1.15,.84),Vector3(side*.23,1.46,1.13),.023,dark,.009)
	fuse(shell)
	# Four independently jointed splayed legs. The front pair ends in large sickles.
	for side: float in [-1.0,1.0]:
		for front in [true,false]:
			var leg := B.node(body,Vector3(side*.29,.8,.24 if front else -.49),Vector3.ZERO,
				("L" if side<0 else "R")+("Front" if front else "Back"))
			leg.set_meta("side",side)
			leg.set_meta("front",front)
			var knee := Vector3(side*.58,.13,.36 if front else -.38)
			var ankle := Vector3(side*.87,-.66,.75 if front else -.58)
			limb(leg,Vector3.ZERO,knee,.115,dark,.075)
			B.sphere(leg,.15,knee,purple,Vector3.ONE,8,4)
			limb(leg,knee,ankle,.20 if front else .145,armor,.042)
			plate(leg,knee+Vector3(side*.06,-.2,.16 if front else -.1),Vector3(.54,1.1,1.0) if front else Vector3(.37,1.0,.76),armor,Vector3(48 if front else -45,0,side*23))
			limb(leg,ankle,ankle+Vector3(-side*.14,-.1,.32),.07,purple,0.0)
			for i in 2:
				var p := knee.lerp(ankle,.3+i*.24)
				limb(leg,p,p+Vector3(side*.23,.04,-.18),.07,purple,0.0)
			fuse(leg)
	# The leaf-like silhouette and shader veins remain visible from the gameplay camera.
	if _wing_mat == null:
		_wing_mat=ShaderMaterial.new()
		_wing_mat.shader=WING
	for side: float in [-1.0,1.0]:
		for front in [true,false]:
			var wing := B.node(body,Vector3(side*.18,1.08,-.12),Vector3.ZERO,
				("L" if side<0 else "R")+("WingA" if front else "WingB"))
			wing.set_meta("side",side)
			wing.set_meta("front",front)
			var outline := PackedVector3Array([Vector3.ZERO,Vector3(side*.48,.09,.32),Vector3(side*1.19,.16,.26),
				Vector3(side*1.85,.22,-.22),Vector3(side*1.48,.14,-.36),Vector3(side*.99,.06,-.55),Vector3(side*.36,0,-.40)])
			var factor := 1.0 if front else .74
			var angle := -.16*side if front else .62*side
			for i in outline.size(): outline[i]=(outline[i]*factor).rotated(Vector3.UP,angle)
			var st:=SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for i in range(1,outline.size()-1):
				for k in [0,i,i+1]:
					st.set_uv(Vector2(absf(outline[k].x)/1.85,(outline[k].z+.6)/1.0))
					st.add_vertex(outline[k])
			st.generate_normals()
			B.mi(wing,st.commit(),Vector3.ZERO,_wing_mat)
			for i in range(outline.size()-1): limb(wing,outline[i],outline[i+1],.018,dark,.014)
			limb(wing,outline[0],outline[3],.027,armor,.009)
			# Keep membrane separate, combine the dark wing frame only.
			fuse(wing)
	root.set_meta("asset","venom_quadruped_v1")
	return root

static func nest() -> Node3D:
	var root:=Node3D.new()
	root.name="ChitinBroodNest"
	var bark:=material("252d43",.1)
	var rim:=material("4d5964",.1)
	var pulp:=material("53672c",.2)
	var hot:=Mats.glow(Color("85dc33"),1.25)
	# Ribbed open shell, luminous egg clusters and pointed exoskeleton rim.
	B.sphere(root,.9,Vector3(0,.15,0),bark,Vector3(1.4,.32,1.15),12,5)
	for i in 9:
		var a:=TAU*i/9.0
		var p:=Vector3(cos(a)*1.06,.12,sin(a)*.88)
		var peak:=p*.74+Vector3(0,.72+sin(i*2.0)*.15,0)
		limb(root,p,peak,.16,rim,.015)
		plate(root,p,Vector3(.58,.6,.72),bark,Vector3(-12,-rad_to_deg(a)+90,0))
	for i in 7:
		var a:=i*2.4
		var p:=Vector3(cos(a)*.54,.27,sin(a)*.45)
		B.sphere(root,.23,p,pulp,Vector3(.85,1.65,.85),9,5)
		B.sphere(root,.16,p+Vector3(0,.10,0),hot,Vector3(.78,1.25,.78),9,5)
	fuse(root)
	root.set_meta("asset","chitin_brood_nest_v1")
	return root

static func dead_tree(rng: RandomNumberGenerator) -> Node3D:
	var root:=Node3D.new()
	root.name="VenomSplitTrunk"
	var bark:=material("2b2944",.10)
	var edge:=material("41435b",.12)
	var glow:=Mats.glow(Color("78d538"),1.5)
	var height:=rng.randf_range(2.6,4.5)
	var bend:=Vector3(rng.randf_range(-.6,.6),height*.66,rng.randf_range(-.4,.4))
	limb(root,Vector3.ZERO,bend,.37,bark,.22)
	limb(root,bend,bend+Vector3(.38,height*.34,-.12),.23,bark,0.0)
	for side: float in [-1.0,1.0]:
		var joint:=bend*.6
		var end:=joint+Vector3(side*.96,.7,.12)
		limb(root,joint,end,.17,edge,.075)
		limb(root,end,end+Vector3(side*.42,.6,-.3),.08,bark,0.0)
		limb(root,end,end+Vector3(side*.47,-.07,.32),.06,bark,0.0)
	for i in 5:
		var a:=TAU*i/5.0
		limb(root,Vector3(0,.22,0),Vector3(cos(a)*1.18,.05,sin(a)*1.18),.19,bark,.015)
	# Uneven glowing splits along the face of the poisoned trunk.
	for i in 4:
		var y:=.4+i*.45
		limb(root,Vector3(.17,y,.22),Vector3(.09,y+.28,.25),.033,glow,.015)
	fuse(root)
	root.set_meta("asset","venom_split_trunk_v1")
	return root

static func fern(rng: RandomNumberGenerator) -> Node3D:
	var root:=Node3D.new()
	root.name="ToxicSwordFern"
	var green:=material("235952",.12)
	var tip:=material("418d6d",.1)
	for i in 7:
		var a:=TAU*i/7.0+rng.randf_range(-.12,.12)
		var frond:=B.node(root,Vector3.ZERO,Vector3(0,rad_to_deg(a),0))
		var len:=rng.randf_range(.6,1.15)
		limb(frond,Vector3.ZERO,Vector3(0,.26,len),.015,tip,.003)
		for j in 4:
			for side: float in [-1,1]:
				var t:=.12+j*.19
				plate(frond,Vector3(side*.12,.17+t*.1,t*len),Vector3(.24*(1-t*.6),.10,.40),green,
					Vector3(-14,side*(35+j*5),0))
	fuse(root)
	return root

static func rock(rng: RandomNumberGenerator) -> Node3D:
	var root:=Node3D.new()
	root.name="BlightSlate"
	var stone:=material("354b59",.10)
	var face:=material("536b70",.12)
	var hot:=Mats.glow(Color("88d932"),1.3)
	B.sphere(root,.72,Vector3(0,.35,0),stone,Vector3(1.3,.65,.88),7,4)
	plate(root,Vector3(0,.65,0),Vector3(1.0,.20,1.0),face)
	limb(root,Vector3(-.3,.65,.1),Vector3(.17,.73,-.14),.024,hot,.012)
	root.rotation.y=rng.randf_range(-PI,PI)
	fuse(root)
	return root

static func bones() -> Node3D:
	var root:=Node3D.new()
	root.name="BleachedRemains"
	var bone:=material("9aa687",.13)
	var dark:=material("252f39",.1)
	B.sphere(root,.19,Vector3(0,.12,.35),bone,Vector3(1.15,.78,1.3),9,5)
	for side: float in [-1,1]:
		B.sphere(root,.07,Vector3(side*.085,.22,.43),dark,Vector3(1,.25,1),8,4)
		limb(root,Vector3(side*.18,.06,-.12),Vector3(side*.44,.065,-.7),.04,bone,.04)
	for i in 4:
		var z:=-.04-i*.14
		limb(root,Vector3(-.21,.06,z),Vector3(0,.25,z),.035,bone,.025)
		limb(root,Vector3(.21,.06,z),Vector3(0,.25,z),.035,bone,.025)
	limb(root,Vector3(0,.13,-.7),Vector3(0,.13,.17),.045,bone,.045)
	fuse(root)
	return root
