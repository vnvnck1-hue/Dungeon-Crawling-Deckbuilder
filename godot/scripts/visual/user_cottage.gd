extends RefCounted
## User's left-hand cottage, isolated without changing its UVs or texture.
## Geometry is kept except the chimney flue (brown block on the stone crown): its closed top face is cut
## open into a rim + inner walls + sooty floor so the Stable Fluids smoke rises out of a real hole.
const COTTAGE := preload("res://assets/cottage/user_cottage.glb")
const SHADER := preload("res://shaders/user_cottage.gdshader")
const FLUE_SHADER := preload("res://shaders/chimney_flue.gdshader")
const B := preload("res://scripts/visual/build.gd")
static var _material: ShaderMaterial
static var _flue_material: ShaderMaterial
const MODEL_SCALE := 17.0
const MODEL_OFFSET := Vector3(0,0,.35)
const CHIMNEY := Vector3(1.20,5.23,1.28)
const FLUE_TOP_Y := 5.20      # world height of the flue's (former) closed top face
const FLUE_WALL := .055       # rim / wall thickness (m)
const FLUE_DEPTH := .36       # hole depth below the rim (m)

static func build(root: Node3D) -> Dictionary:
	var visual:=B.node(root,Vector3.ZERO,Vector3.ZERO,"LodgeVisual")
	var cottage: Node3D=COTTAGE.instantiate()
	cottage.name="UserCottage"
	cottage.scale=Vector3.ONE*MODEL_SCALE
	cottage.position=MODEL_OFFSET
	visual.add_child(cottage)
	cottage.set_meta("source_variant","left")
	for mesh: MeshInstance3D in cottage.find_children("*","MeshInstance3D",true,false):
		var source: StandardMaterial3D=mesh.mesh.surface_get_material(0)
		if _material==null:
			_material=ShaderMaterial.new()
			_material.resource_name="UserCottageOriginalPaint"
			_material.shader=SHADER
			_material.set_shader_parameter("cottage_paint",source.albedo_texture)
		var flue:=open_flue(mesh,cottage.transform*_to_ancestor(mesh,cottage))
		for i in mesh.mesh.get_surface_count():
			mesh.set_surface_override_material(i,_material)
		if not flue.is_empty():
			if _flue_material==null:
				_flue_material=ShaderMaterial.new()
				_flue_material.resource_name="ChimneyFlueSoot"
				_flue_material.shader=FLUE_SHADER
			mesh.set_surface_override_material(flue.surface,_flue_material)
			cottage.set_meta("flue",flue)
	var lights:=B.node(visual,Vector3.ZERO,Vector3.ZERO,"WarmLights")
	var warm:=Color(1.0,.65,.32)
	B.omni(lights,Vector3(-.72,1.45,2.66),warm,1.0,4.5,true,1.3)
	B.omni(lights,Vector3(2.36,1.35,.0),warm,.7,4.1,false,1.3)
	return {"visual":visual,"lights":lights}

static func _to_ancestor(node: Node3D, ancestor: Node) -> Transform3D:
	var xf:=Transform3D.IDENTITY
	var n: Node=node
	while n!=null and n!=ancestor:
		if n is Node3D: xf=(n as Node3D).transform*xf
		n=n.get_parent()
	return xf

## Cuts the flue's closed top face out of surface 0 and adds, in world units then mapped back to mesh space:
## a stone rim (same paint/UV as the removed face) on surface 0, and inner walls + floor as a new soot surface.
## Returns {"surface", "opening": Rect2 (world x,z of the hole), "top", "floor"} or {} if the face isn't found.
static func open_flue(mi: MeshInstance3D, to_world: Transform3D) -> Dictionary:
	var src: ArrayMesh=mi.mesh
	var a:=src.surface_get_arrays(0)
	var v: PackedVector3Array=a[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array=a[Mesh.ARRAY_NORMAL]
	var tan: PackedFloat32Array=a[Mesh.ARRAY_TANGENT] if a[Mesh.ARRAY_TANGENT]!=null else PackedFloat32Array()
	var uv: PackedVector2Array=a[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array=a[Mesh.ARRAY_INDEX]
	var keep:=PackedInt32Array()
	var lo:=Vector2(INF,INF)
	var hi:=Vector2(-INF,-INF)
	var top_uv:=Vector2.ZERO
	var removed:=0
	for t in range(0,idx.size()-2,3):
		var face:=true
		for k in 3:
			var p:=to_world*v[idx[t+k]]
			if absf(p.y-FLUE_TOP_Y)>.012 or absf(p.x-CHIMNEY.x)>.25 or absf(p.z-CHIMNEY.z)>.25: face=false
		if not face:
			keep.append(idx[t]); keep.append(idx[t+1]); keep.append(idx[t+2])
			continue
		removed+=1
		top_uv=uv[idx[t]]
		for k in 3:
			var p:=to_world*v[idx[t+k]]
			lo=Vector2(minf(lo.x,p.x),minf(lo.y,p.z))
			hi=Vector2(maxf(hi.x,p.x),maxf(hi.y,p.z))
	if removed==0: return {}
	var inv:=to_world.affine_inverse()
	var nb:=inv.basis.inverse().transposed()
	var y:=FLUE_TOP_Y
	var ilo:=lo+Vector2.ONE*FLUE_WALL
	var ihi:=hi-Vector2.ONE*FLUE_WALL
	var fy:=y-FLUE_DEPTH
	# Rim on the paint surface: four strips between the outer face outline and the hole.
	var o:=[Vector3(lo.x,y,lo.y),Vector3(hi.x,y,lo.y),Vector3(hi.x,y,hi.y),Vector3(lo.x,y,hi.y)]
	var i4:=[Vector3(ilo.x,y,ilo.y),Vector3(ihi.x,y,ilo.y),Vector3(ihi.x,y,ihi.y),Vector3(ilo.x,y,ihi.y)]
	var rim:=[]
	for e in 4:
		rim.append([o[e],o[(e+1)%4],i4[(e+1)%4],i4[e]])
	var base:=v.size()
	for q in rim:
		for tri in _quad_tris(q,Vector3.UP):
			for p: Vector3 in tri:
				keep.append(v.size())
				v.append(inv*p)
				nrm.append((nb*Vector3.UP).normalized())
				uv.append(top_uv)
				if not tan.is_empty(): tan.append_array(PackedFloat32Array([1,0,0,1]))
	var out:=ArrayMesh.new()
	var a0:=[]
	a0.resize(Mesh.ARRAY_MAX)
	a0[Mesh.ARRAY_VERTEX]=v
	a0[Mesh.ARRAY_NORMAL]=nrm
	if not tan.is_empty(): a0[Mesh.ARRAY_TANGENT]=tan
	a0[Mesh.ARRAY_TEX_UV]=uv
	a0[Mesh.ARRAY_INDEX]=keep
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a0)
	out.surface_set_material(0,src.surface_get_material(0))
	# Soot surface: inner walls (facing the hole centre) and the floor, darker and warmer with depth.
	var sv:=PackedVector3Array()
	var sn:=PackedVector3Array()
	var sc:=PackedColorArray()
	var rim_c:=Color(.24,.19,.17,0.0)
	var deep_c:=Color(.05,.035,.03,.45)
	var f4:=[]
	for p: Vector3 in i4: f4.append(Vector3(p.x,fy,p.z))
	var centre:=Vector3((ilo.x+ihi.x)*.5,y,(ilo.y+ihi.y)*.5)
	for e in 4:
		var q:=[i4[e],i4[(e+1)%4],f4[(e+1)%4],f4[e]]
		var mid:Vector3=(q[0]+q[1])*.5
		var n:=Vector3(centre.x-mid.x,0,centre.z-mid.z).normalized()
		for tri in _quad_tris(q,n):
			for p: Vector3 in tri:
				sv.append(inv*p); sn.append((nb*n).normalized())
				sc.append(rim_c if p.y>fy+.01 else deep_c)
	for tri in _quad_tris(f4,Vector3.UP):
		for p: Vector3 in tri:
			sv.append(inv*p); sn.append((nb*Vector3.UP).normalized()); sc.append(Color(.07,.04,.03,1.0))
	var a1:=[]
	a1.resize(Mesh.ARRAY_MAX)
	a1[Mesh.ARRAY_VERTEX]=sv
	a1[Mesh.ARRAY_NORMAL]=sn
	a1[Mesh.ARRAY_COLOR]=sc
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a1)
	out.surface_set_name(1,"ChimneyFlueSoot")
	mi.mesh=out
	return {"surface":1,"opening":Rect2(ilo,ihi-ilo),"outer":Rect2(lo,hi-lo),"top":y,"floor":fy,"removed":removed,"rim_vertices":v.size()-base}

## Two triangles for quad (a,b,c,d) wound so their front faces along n (Godot fronts are clockwise).
static func _quad_tris(q: Array, n: Vector3) -> Array:
	var tris:=[[q[0],q[1],q[2]],[q[0],q[2],q[3]]]
	for t in tris:
		if (t[1]-t[0]).cross(t[2]-t[0]).dot(n)>0.0:
			var s=t[1]; t[1]=t[2]; t[2]=s
	return tris
