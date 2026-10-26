@tool
class_name GrassField
extends Node3D
## Clumped, wind-waved ground plants. One small mesh per kind (lance-leaf rosette / broad-leaf / flower / upright spear),
## leaves folded along a midrib and painted in the shader (midrib, veins, brush streaks — see grass_wind.gdshader),
## drawn with MultiMesh per chunk so the camera frustum and visibility range cull whole chunks.
## Wind, push and distance fade all run in shaders/grass_wind.gdshader — no per-instance CPU work per frame.
## Pass a Callable(Vector2) -> float as `height_at` before adding to the tree to sit grass on uneven ground,
## and a Callable(Vector2) -> bool as `keep_out` to keep buildings, paths and props clear (both take world XZ).

const SHADER := preload("res://shaders/grass_wind.gdshader")
enum Kind { GRASS, WEED, FLOWER, SPEAR }
## Horizontal reach per metre of height and wind stiffness, per Kind.
const SPREAD := [1.25, 1.3, .7, .85]
const STIFFNESS := [1.0, 1.35, 1.15, .9]

@export var size := Vector2(40, 40): set = _set_dirty_v2
@export var chunk_size := 8.0
@export var grass_seed := 7: set = _set_dirty_i
@export_group("Clumps")
@export var clump_spacing := 3.0 ## average distance between clump centres
@export var clump_radius := Vector2(1.0, 2.6)
@export var clump_density := 11.0 ## tufts per m² at a clump centre
@export var meadow_density := 1.1 ## sparse low tufts between clumps
@export_range(0, 1) var open_ground := .25 ## fraction of the field left as low meadow / bare
@export var height_range := Vector2(.16, 1.0)
## Old look (2026-10-14): three round-tipped paddle blades per tuft, width not tied to height. Kept for comparison.
@export var classic := false
@export_range(0, 1) var weed_ratio := .14
@export_range(0, 1) var flower_ratio := .035
@export_range(0, 1) var spear_ratio := .16 ## upright sword-leaf plants towards clump centres
@export var holes: Array[Vector3] = [] ## (x, z, radius) in local space kept clear, e.g. paths and buildings
@export var round_edge := false ## fade the field out towards a circle instead of a hard square edge
@export_group("Rendering")
@export var visibility_end := 46.0 ## 0 = never cull by distance (fixed far cameras)
@export var material: ShaderMaterial ## leave empty for the default palette
@export_group("Interaction")
@export var push_target: Node3D ## blades lean away from this node (e.g. the witch)
@export var push_radius := 1.2

var height_at: Callable
var keep_out: Callable
var instance_count := 0
var shader_material: ShaderMaterial ## `material` or a generated default; shared by every chunk
var _dirty := false

func _set_dirty_v2(v: Vector2) -> void: size = v; _queue_rebuild()
func _set_dirty_i(v: int) -> void: grass_seed = v; _queue_rebuild()

func _queue_rebuild() -> void:
	if not is_inside_tree() or _dirty: return
	_dirty = true
	rebuild.call_deferred()

func _ready() -> void:
	rebuild()

var _push_sent := Vector4(INF, INF, INF, INF)
var _push_mat: ShaderMaterial

func _process(_delta: float) -> void:
	if push_target and is_instance_valid(push_target) and shader_material:
		var p := push_target.global_position
		var sphere := Vector4(p.x, p.y, p.z, push_radius)
		if sphere != _push_sent or shader_material != _push_mat:   # 서 있으면 다시 보내지 않는다
			_push_sent = sphere
			_push_mat = shader_material
			shader_material.set_shader_parameter("push_sphere", sphere)

static func default_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = SHADER
	m.set_shader_parameter("wind_noise", make_noise_texture())
	return m

## Seamless value noise generated synchronously (NoiseTexture2D builds on a thread and is blank for the first frames).
static func make_noise_texture() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = .018
	n.fractal_octaves = 3
	var img := n.get_seamless_image(256, 256, false, false, .1, true)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func rebuild() -> void:
	_dirty = false
	for c in get_children():
		if c.has_meta("grass_chunk"): c.queue_free()
	shader_material = material if material else default_material()
	var meshes := [_rosette_mesh(6, 11), _broadleaf_mesh(), _flower_mesh(), _spear_mesh()]
	if classic: meshes = [_classic_tuft_mesh(3, .17, .12, .26), _classic_weed_mesh(), _classic_flower_mesh(), meshes[3]]
	var chunks := {} # Vector2i -> one Array per Kind of [Transform3D, Color]
	var rng := RandomNumberGenerator.new()
	rng.seed = grass_seed
	var noise := FastNoiseLite.new()
	noise.seed = grass_seed
	noise.frequency = .06
	var half := size * .5
	instance_count = 0

	# Clump centres on a jittered grid; low-noise cells become open meadow.
	var cells := Vector2i(ceili(size.x / clump_spacing), ceili(size.y / clump_spacing))
	for gy in cells.y:
		for gx in cells.x:
			var c := Vector2(gx + rng.randf(), gy + rng.randf()) * clump_spacing - half
			var n := noise.get_noise_2d(c.x, c.y) * .5 + .5
			if n < open_ground: continue
			var r := rng.randf_range(clump_radius.x, clump_radius.y) * lerpf(.7, 1.15, n)
			var peak := lerpf(height_range.x * 2.0, height_range.y, clampf((n - open_ground) / (1.0 - open_ground) * rng.randf_range(.7, 1.25), 0, 1))
			var count := int(clump_density * PI * r * r * .5)
			for i in count:
				# Uniform disk sample, thinned towards the rim so clumps have soft edges.
				var d := sqrt(rng.randf())
				if rng.randf() < d * d * .6: continue
				var a := rng.randf() * TAU
				var p := c + Vector2(cos(a), sin(a)) * d * r
				var falloff := pow(1.0 - d, .7)
				var h := peak * lerpf(.3, 1.0, falloff) * rng.randf_range(.8, 1.15)
				var kind := Kind.GRASS
				var roll := rng.randf()
				if roll < weed_ratio * (.4 + falloff): kind = Kind.WEED; h *= 1.15 if classic else .8
				elif roll < (weed_ratio + spear_ratio) * (.4 + falloff) and falloff > .3 and not classic: kind = Kind.SPEAR; h *= 1.25
				elif roll > 1.0 - flower_ratio * (1.6 - falloff): kind = Kind.FLOWER; h = maxf(h * 1.1, height_range.x * 2.5)
				_add(chunks, rng, kind, p, h, n)
	# Thin low meadow between clumps so the ground never looks shaved.
	for i in int(size.x * size.y * meadow_density):
		var p := Vector2(rng.randf_range(-half.x, half.x), rng.randf_range(-half.y, half.y))
		var n := noise.get_noise_2d(p.x, p.y) * .5 + .5
		if rng.randf() > .35 + n: continue
		_add(chunks, rng, Kind.GRASS, p, height_range.x * rng.randf_range(.8, 1.9) * (.7 + n), n)

	var margin := height_range.y * 1.7 # leaves arch out past the root by about their height
	for key: Vector2i in chunks:
		for kind in Kind.size():
			var items: Array = chunks[key][kind]
			if items.is_empty(): continue
			var origin := Vector3((key.x + .5) * chunk_size, 0, (key.y + .5) * chunk_size)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			mm.mesh = meshes[kind]
			mm.instance_count = items.size()
			for i in items.size():
				var t: Transform3D = items[i][0]
				t.origin -= origin
				mm.set_instance_transform(i, t)
				mm.set_instance_custom_data(i, items[i][1])
			var mmi := MultiMeshInstance3D.new()
			mmi.set_meta("grass_chunk", true)
			mmi.name = "Grass_%d_%d_%d" % [key.x, key.y, kind]
			mmi.multimesh = mm
			mmi.material_override = shader_material
			mmi.position = origin
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.visibility_range_end = visibility_end
			mmi.visibility_range_end_margin = 2.0
			# Wind can move tips past the instance AABB; widen it so chunks are not culled early.
			var s := chunk_size * .5 + margin
			mmi.custom_aabb = AABB(Vector3(-s, -.2, -s), Vector3(s * 2, height_range.y * 1.4 + .4, s * 2))
			add_child(mmi)
			instance_count += items.size()

func _add(chunks: Dictionary, rng: RandomNumberGenerator, kind: int, p: Vector2, h: float, n: float) -> void:
	if absf(p.x) > size.x * .5 or absf(p.y) > size.y * .5: return
	for hole in holes:
		if p.distance_to(Vector2(hole.x, hole.y)) < hole.z: return
	if round_edge:
		var e := p.length() / (minf(size.x, size.y) * .5)
		if e > 1.0 or (e > .6 and rng.randf() < (e - .6) / .4): return
		h *= lerpf(1.0, .55, clampf((e - .5) / .5, 0, 1))
	var g := to_global(Vector3(p.x, 0, p.y))
	if keep_out.is_valid() and keep_out.call(Vector2(g.x, g.z)): return
	var y := 0.0
	if height_at.is_valid():
		y = height_at.call(Vector2(g.x, g.z)) - global_position.y
	# Reach grows with height so small plants are small rosettes, not wide flat cards; floor keeps meadow tufts readable.
	var w: float = maxf(h, height_range.x * 1.4) * SPREAD[kind] * rng.randf_range(.85, 1.2)
	if classic: w = rng.randf_range(1.0, 1.35) * lerpf(.85, 1.2, clampf(h / height_range.y, 0, 1))
	var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(w, h, w))
	var stiffness: float = STIFFNESS[kind] * rng.randf_range(.85, 1.15)
	var custom := Color(clampf(n + rng.randf_range(-.3, .3), 0, 1), rng.randf(), stiffness, 0)
	var key := Vector2i(floori(p.x / chunk_size), floori(p.y / chunk_size))
	if not chunks.has(key):
		chunks[key] = []
		for k in Kind.size(): chunks[key].append([])
	chunks[key][kind].append([Transform3D(basis, Vector3(p.x, y, p.y)), custom])

# --- Meshes: about unit height (instance scale.y = metres). UV.x = 0 left edge .. .5 midrib .. 1 right edge,
# UV.y = 0 root .. 1 tip, UV2.x = per-leaf random. The shader paints midrib, veins and brush streaks from these.

## Leaf folded along its midrib: arches up from the root and bends over towards the tip.
## `rise` = start angle above the ground, `droop` = how far it bends over by the tip (radians).
## `belly` = where it is widest (.3 lance .. .6 oval); `blunt` < 1 rounds the tip; `fold` lifts the edges into a shallow V.
func _leaf(st: SurfaceTool, base: Vector3, out: Vector2, length: float, width: float, rise: float, droop: float,
		rnd: float, belly := .38, blunt := 1.0, fold := .4, segments := 5, color := Color(1, 1, 1, 0)) -> void:
	var o := Vector3(out.x, 0, out.y)
	var side := Vector3(-out.y, 0, out.x)
	var shape := log(.5) / log(belly) # sin(PI * t^shape) peaks at t = belly
	var p := base
	var rows := [] # per row: [left, mid, right, left-half normal, right-half normal, t]
	for s in segments + 1:
		var t := float(s) / segments
		var a := rise - droop * pow(t, 1.3)
		var tangent := o * cos(a) + Vector3.UP * sin(a)
		if s > 0:
			var am := rise - droop * pow(t - .5 / segments, 1.3) # step along the mid-segment angle
			p += (o * cos(am) + Vector3.UP * sin(am)) * length / segments
		var hw := width * .5 * maxf(pow(sin(PI * pow(t, shape)), blunt), .12 * (1.0 - t))
		var n := side.cross(tangent).normalized()
		# Edges sit higher than the midrib, so the two halves face slightly apart and catch light differently.
		rows.append([p - side * hw + n * hw * fold, p, p + side * hw + n * hw * fold,
			(n + side * fold).normalized(), (n - side * fold).normalized(), t])
	st.set_color(color)
	for s in segments:
		var r0: Array = rows[s]
		var r1: Array = rows[s + 1]
		var t0: float = r0[5]
		var t1: float = r1[5]
		_lv(st, r0[0], r0[3], Vector2(0, t0), rnd); _lv(st, r0[1], r0[3], Vector2(.5, t0), rnd); _lv(st, r1[1], r1[3], Vector2(.5, t1), rnd)
		_lv(st, r0[0], r0[3], Vector2(0, t0), rnd); _lv(st, r1[1], r1[3], Vector2(.5, t1), rnd); _lv(st, r1[0], r1[3], Vector2(0, t1), rnd)
		_lv(st, r0[1], r0[4], Vector2(.5, t0), rnd); _lv(st, r0[2], r0[4], Vector2(1, t0), rnd); _lv(st, r1[2], r1[4], Vector2(1, t1), rnd)
		_lv(st, r0[1], r0[4], Vector2(.5, t0), rnd); _lv(st, r1[2], r1[4], Vector2(1, t1), rnd); _lv(st, r1[1], r1[4], Vector2(.5, t1), rnd)

func _lv(st: SurfaceTool, p: Vector3, n: Vector3, uv: Vector2, rnd: float) -> void:
	st.set_normal(n)
	_v(st, p, uv, rnd)

## Thin straight stem (flower), UV.x across, flat normal.
func _blade(st: SurfaceTool, out: Vector2, height: float, width: float, lean: float, rnd: float, segments: int) -> void:
	var side := Vector3(-out.y, 0, out.x)
	st.set_color(Color(1, 1, 1, 0))
	st.set_normal(side.cross(Vector3.UP).normalized())
	for s in segments:
		var t0 := float(s) / segments
		var t1 := float(s + 1) / segments
		var p0 := Vector3(out.x, 0, out.y) * lean * t0 * t0 + Vector3.UP * height * t0
		var p1 := Vector3(out.x, 0, out.y) * lean * t1 * t1 + Vector3.UP * height * t1
		var a := p0 - side * width * .5
		var b := p0 + side * width * .5
		var c := p1 - side * width * .5
		var d := p1 + side * width * .5
		_v(st, a, Vector2(0, t0), rnd); _v(st, b, Vector2(1, t0), rnd); _v(st, d, Vector2(1, t1), rnd)
		_v(st, a, Vector2(0, t0), rnd); _v(st, d, Vector2(1, t1), rnd); _v(st, c, Vector2(0, t1), rnd)

func _v(st: SurfaceTool, p: Vector3, uv: Vector2, rnd: float) -> void:
	st.set_uv(uv)
	st.set_uv2(Vector2(rnd, 0))
	st.add_vertex(p)

## The common ground plant: lance leaves splaying from one root. Outer leaves are long and lie low,
## inner ones are shorter and stand up, so the plant reads as a domed rosette from the top-down camera.
func _rosette_mesh(leaves: int, mesh_seed: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = mesh_seed
	for i in leaves:
		var a := TAU * i / leaves + r.randf_range(-.3, .3)
		var out := Vector2(cos(a), sin(a))
		var inner := float(i % 3) / 2.0 * r.randf_range(.8, 1.0) # 0 outer .. 1 inner, interleaved round the plant
		_leaf(st, Vector3(out.x, 0, out.y) * -.03, out, lerpf(1.25, .95, inner) * r.randf_range(.9, 1.1),
			lerpf(.5, .4, inner), deg_to_rad(lerpf(58, 82, inner)), deg_to_rad(lerpf(88, 62, inner)), r.randf(), .4, .9, .4, 6)
	return st.commit()

## Broad oval leaves lying low (hosta-like), a few per plant.
func _broadleaf_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var a: float = TAU * i / 4.0 + [.0, .25, -.15, .4][i]
		var out := Vector2(cos(a), sin(a))
		_leaf(st, Vector3(out.x, 0, out.y) * -.03, out, [1.0, .85, .95, .8][i], [.84, .74, .8, .7][i],
			deg_to_rad(52), deg_to_rad(68), float(i) / 4.0, .55, .55, .25, 6)
	# A young rolled leaf standing in the middle.
	_leaf(st, Vector3.ZERO, Vector2(.3, .95).normalized(), .6, .3, deg_to_rad(82), deg_to_rad(30), .9, .5, .7, .7, 4)
	return st.commit()

## Upright sword leaves: tall, narrow, only the tips bend over.
func _spear_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 23
	for i in 5:
		var a := TAU * i / 5.0 + r.randf_range(-.4, .4)
		var out := Vector2(cos(a), sin(a))
		_leaf(st, Vector3(out.x, 0, out.y) * -.02, out, r.randf_range(.95, 1.2), r.randf_range(.26, .32),
			deg_to_rad(r.randf_range(74, 86)), deg_to_rad(r.randf_range(35, 60)), r.randf(), .3, 1.0, .45, 6)
	return st.commit()

func _flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3: # small lance leaves under the stem
		var a := TAU * i / 3.0 + .3
		_leaf(st, Vector3.ZERO, Vector2(cos(a), sin(a)), .55, .22, deg_to_rad(50), deg_to_rad(70), float(i) / 3.0, .4, 1.0, .4, 3)
	_blade(st, Vector2(1, 0), 1.0, .025, .06, .3, 2)
	# Head: two crossed diamonds at the tip, flagged with COLOR.a = 1 so the shader paints them.
	var tip := Vector3(.06, 1.0, 0)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var s := .09
		var pts := [tip + Vector3.UP * s, tip + axis * s, tip - Vector3.UP * s * .6, tip - axis * s]
		st.set_color(Color(1, 1, 1, 1))
		st.set_normal(axis.cross(Vector3.UP))
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri: _v(st, pts[k], Vector2(.5, 1.0), .7)
	return st.commit()

# --- Classic meshes (classic = true): the 2026-10-14 look, round-tipped paddle blades with one flat normal.

## Chubby paddle leaf: narrower at the root, full at the top, rounded half-disc tip instead of a point.
func _paddle(st: SurfaceTool, base: Vector2, out: Vector2, height: float, width: float, lean: float, rnd: float, segments: int, color := Color(1, 1, 1, 0)) -> void:
	var side := Vector3(-out.y, 0, out.x)
	var widths: Array[float] = []
	for s in segments + 1:
		var t := float(s) / segments
		widths.append(width * (.6 + .45 * smoothstep(0.0, .6, t)))
	var r := widths[segments] * .5 # tip cap radius
	var body := maxf(height - r, height * .5)
	var rows: Array[Vector3] = []
	for s in segments + 1:
		var t := float(s) / segments
		rows.append(Vector3(base.x, 0, base.y) + Vector3(out.x, 0, out.y) * lean * t * t + Vector3.UP * body * t)
	var normal := side.cross(Vector3.UP).normalized() if side.length() > 0 else Vector3.BACK
	var v_body := body / height # UV.y where the cap starts
	st.set_color(color)
	st.set_normal(normal)
	for s in segments:
		var t0 := float(s) / segments * v_body
		var t1 := float(s + 1) / segments * v_body
		var a := rows[s] - side * widths[s] * .5
		var b := rows[s] + side * widths[s] * .5
		var c := rows[s + 1] - side * widths[s + 1] * .5
		var d := rows[s + 1] + side * widths[s + 1] * .5
		_v(st, a, Vector2(0, t0), rnd); _v(st, b, Vector2(1, t0), rnd); _v(st, d, Vector2(1, t1), rnd)
		_v(st, a, Vector2(0, t0), rnd); _v(st, d, Vector2(1, t1), rnd); _v(st, c, Vector2(0, t1), rnd)
	# Rounded tip: half-disc fan continuing the leaf's direction.
	var top := rows[segments]
	var up := (top - rows[segments - 1]).normalized()
	var steps := 6
	for i in steps:
		var a0 := PI * i / steps
		var a1 := PI * (i + 1) / steps
		var p0 := top - side * cos(a0) * r + up * sin(a0) * r
		var p1 := top - side * cos(a1) * r + up * sin(a1) * r
		_v(st, top, Vector2(.5, v_body), rnd)
		_v(st, p0, Vector2(.5 - cos(a0) * .5, v_body + sin(a0) * (1.0 - v_body)), rnd)
		_v(st, p1, Vector2(.5 - cos(a1) * .5, v_body + sin(a1) * (1.0 - v_body)), rnd)

func _classic_tuft_mesh(blades: int, width: float, spread: float, lean: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var r := RandomNumberGenerator.new()
	r.seed = 11
	for i in blades:
		var a := TAU * i / blades + r.randf_range(-.4, .4)
		var out := Vector2(cos(a), sin(a))
		_paddle(st, out * spread * r.randf_range(.1, .5), out, r.randf_range(.65, 1.0), width, lean * r.randf_range(.5, 1.3), r.randf(), 3)
	return st.commit()

func _classic_weed_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var a := TAU * i / 3.0 + .5
		var out := Vector2(cos(a), sin(a))
		_paddle(st, out * .03, out, [1.0, .8, .9][i], .28, .34, float(i) / 3.0, 3)
	return st.commit()

func _classic_flower_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 2: # two leaves under the stem
		var a := PI * i + .3
		_paddle(st, Vector2.ZERO, Vector2(cos(a), sin(a)), .45, .15, .22, float(i) * .5, 2)
	_paddle(st, Vector2.ZERO, Vector2(1, 0), 1.0, .025, .06, .3, 2)
	# Head: two crossed diamonds at the tip, flagged with COLOR.a = 1 so the shader paints them.
	var tip := Vector3(.06, 1.0, 0)
	for axis: Vector3 in [Vector3.RIGHT, Vector3.BACK]:
		var s := .09
		var pts := [tip + Vector3.UP * s, tip + axis * s, tip - Vector3.UP * s * .6, tip - axis * s]
		st.set_color(Color(1, 1, 1, 1))
		st.set_normal(axis.cross(Vector3.UP))
		for tri in [[0, 1, 2], [0, 2, 3]]:
			for k in tri: _v(st, pts[k], Vector2(.5, 1.0), .7)
	return st.commit()
