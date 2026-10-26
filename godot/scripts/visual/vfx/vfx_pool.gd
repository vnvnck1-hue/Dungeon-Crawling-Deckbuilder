extends Node3D
## 카툰 VFX 입자 풀. 표시 전용(게임 판정과 무관).
## 입자는 GDScript에서 움직이고 MultiMesh 두 장(카메라를 향하는 입자 / 지면에 눕는 입자)으로 한 번에 그린다.
## 도형은 shaders/vfx/vfx_shapes.gdshaderinc 의 SDF로 그려 텍스처가 필요 없다.

const SHADER_BB := preload("res://shaders/vfx/vfx_billboard.gdshader")
const SHADER_GROUND := preload("res://shaders/vfx/vfx_ground.gdshader")

# 도형 번호(셰이더와 같은 값)
const GLOW := 0
const PUFF := 1
const STAR := 2
const SPARKLE := 3
const RING := 4
const LEAF := 5
const FOOT := 6
const FLAKE := 7
const STREAK := 8
const SLASH := 9
const SHOCK := 10
const PLUS := 11
const CLOUD := 12
const CLAW := 13
const SCORCH := 14

# 입자 플래그
const F_POP := 1          # 처음 0.12초 동안 튕기듯 커진다(카툰 팝)
const F_ALIGN := 2        # 이동 방향으로 화면 회전(꼬리·바람줄기)
const F_LAND := 4         # 지면(y=0)에 닿으면 멈춘다(나뭇잎·파편)

var billboard: Layer
var ground: Layer
var camera: Camera3D


class Layer:
	const START_INSTANCES := 256
	var cap := 0
	var n := 0
	var mm: MultiMesh
	var buf := PackedFloat32Array()
	var pos := PackedVector3Array()
	var vel := PackedVector3Array()
	var age := PackedFloat32Array()
	var life := PackedFloat32Array()
	var size := PackedVector2Array()
	var grow := PackedFloat32Array()
	var rot := PackedFloat32Array()
	var spin := PackedFloat32Array()
	var col := PackedColorArray()
	var grav := PackedFloat32Array()
	var drag := PackedFloat32Array()
	var curl := PackedFloat32Array()
	var sway := PackedFloat32Array()
	var shape := PackedFloat32Array()
	var fade_in := PackedFloat32Array()
	var flags := PackedInt32Array()

	func _init(parent: Node3D, capacity: int, mesh: Mesh, shader: Shader, priority: int) -> void:
		cap = capacity
		pos.resize(cap); vel.resize(cap); age.resize(cap); life.resize(cap); size.resize(cap)
		grow.resize(cap); rot.resize(cap); spin.resize(cap); col.resize(cap); grav.resize(cap)
		drag.resize(cap); curl.resize(cap); sway.resize(cap); shape.resize(cap); fade_in.resize(cap)
		flags.resize(cap)
		# MultiMesh 는 작게 시작해 살아 있는 입자 수가 넘칠 때만 두 배씩 키운다(최대 cap).
		# 매 프레임 올리는 버퍼가 실제로 쓰는 만큼만 커지게 한다.
		var start := mini(cap, START_INSTANCES)
		buf.resize(start * 20)
		mm = MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = mesh
		mm.instance_count = start
		mm.visible_instance_count = 0
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.render_priority = priority
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 200, 800))
		parent.add_child(mmi)

	func add(shape_id: float, at: Vector3, velocity: Vector3, lifetime: float, sz: Vector2, color: Color,
			g: float, gr: float, dr: float, cu: float, sw: float, r: float, sp: float, fi: float, f: int) -> bool:
		if n >= cap:
			return false
		var i := n
		n += 1
		pos[i] = at; vel[i] = velocity; age[i] = 0.0; life[i] = maxf(lifetime, 0.01); size[i] = sz
		grow[i] = g; rot[i] = r; spin[i] = sp; col[i] = color; grav[i] = gr; drag[i] = dr
		curl[i] = cu; sway[i] = sw; shape[i] = shape_id; fade_in[i] = fi; flags[i] = f
		return true

	func _ensure_instances(count: int) -> void:
		if count <= mm.instance_count:
			return
		var c := maxi(mm.instance_count, 1)
		while c < count:
			c *= 2
		c = mini(c, cap)
		mm.instance_count = c
		buf.resize(c * 20)

	func kill(i: int) -> void:
		var j := n - 1
		if i != j:
			pos[i] = pos[j]; vel[i] = vel[j]; age[i] = age[j]; life[i] = life[j]; size[i] = size[j]
			grow[i] = grow[j]; rot[i] = rot[j]; spin[i] = spin[j]; col[i] = col[j]; grav[i] = grav[j]
			drag[i] = drag[j]; curl[i] = curl[j]; sway[i] = sway[j]; shape[i] = shape[j]
			fade_in[i] = fade_in[j]; flags[i] = flags[j]
		n -= 1

	func step(dt: float, cam_r: Vector3, cam_u: Vector3) -> void:
		var i := 0
		while i < n:
			var a := age[i] + dt
			if a >= life[i]:
				kill(i)
				continue
			age[i] = a
			var v := vel[i]
			var p := pos[i]
			var fl := flags[i]
			var landed := (fl & F_LAND) != 0 and p.y <= 0.03
			if landed:
				v = Vector3.ZERO
				p.y = 0.03
			else:
				v.y += grav[i] * dt
				if drag[i] > 0.0:
					v *= maxf(1.0 - drag[i] * dt, 0.0)
				if curl[i] != 0.0:
					v = v.rotated(Vector3.UP, curl[i] * dt)
				p += v * dt
				if sway[i] != 0.0:
					var ph := a * 2.6 + float(i % 7)
					p += Vector3(cos(ph), 0.0, sin(ph * 0.7)) * sway[i] * dt
				rot[i] += spin[i] * dt
			vel[i] = v
			pos[i] = p
			if (fl & F_ALIGN) != 0 and v.length_squared() > 0.0001:
				rot[i] = atan2(v.dot(cam_u), v.dot(cam_r))
			i += 1
		_ensure_instances(n)
		for k in n:
			var t := age[k] / life[k]
			var s := lerpf(1.0, grow[k], 1.0 - (1.0 - t) * (1.0 - t))
			if (flags[k] & F_POP) != 0:
				var pt := minf(age[k] / 0.12, 1.0) - 1.0
				s *= 0.3 + 0.7 * (1.0 + 2.2 * pt * pt * pt + 1.2 * pt * pt)
			var c := col[k]
			var alpha := c.a * (1.0 - smoothstep(0.62, 1.0, t))
			if fade_in[k] > 0.0:
				alpha *= minf(t / fade_in[k], 1.0)
			var o := k * 20
			var p2 := pos[k]
			var sz := size[k] * s
			buf[o] = 1.0; buf[o + 1] = 0.0; buf[o + 2] = 0.0; buf[o + 3] = p2.x
			buf[o + 4] = 0.0; buf[o + 5] = 1.0; buf[o + 6] = 0.0; buf[o + 7] = p2.y
			buf[o + 8] = 0.0; buf[o + 9] = 0.0; buf[o + 10] = 1.0; buf[o + 11] = p2.z
			buf[o + 12] = c.r; buf[o + 13] = c.g; buf[o + 14] = c.b; buf[o + 15] = alpha
			buf[o + 16] = sz.x; buf[o + 17] = sz.y; buf[o + 18] = rot[k]; buf[o + 19] = shape[k]
		mm.visible_instance_count = n
		if n > 0:
			mm.buffer = buf


func _ready() -> void:
	name = "VfxPool"
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var plane := PlaneMesh.new()
	plane.size = Vector2(1, 1)
	ground = Layer.new(self, 1600, plane, SHADER_GROUND, -2)
	billboard = Layer.new(self, 3200, quad, SHADER_BB, 2)


## 입자 하나. 반환값이 false면 풀이 가득 찼다.
## diameter: 세로 크기(m), opts.aspect: 가로/세로 비(줄기·꼬리용), opts.grow: 수명 끝의 크기 배율.
## 그 밖의 opts: ground, additive, gravity, drag, curl, sway, rot, spin, fade_in, pop, align, land
func emit(shape_id: int, at: Vector3, velocity: Vector3, lifetime: float, diameter: float, color: Color,
		opts: Dictionary = {}) -> bool:
	var L: Layer = ground if opts.get("ground", false) else billboard
	var aspect: float = opts.get("aspect", 1.0)
	var f := 0
	if opts.get("pop", false): f |= F_POP
	if opts.get("align", false): f |= F_ALIGN
	if opts.get("land", false): f |= F_LAND
	var r: float = opts.get("rot", randf() * TAU if shape_id in [STAR, SHOCK, LEAF, SCORCH, SPARKLE] else 0.0)
	return L.add(float(shape_id) + (0.5 if opts.get("additive", false) else 0.0), at, velocity, lifetime,
		Vector2(diameter * aspect, diameter), color, opts.get("grow", 1.0), opts.get("gravity", 0.0),
		opts.get("drag", 0.0), opts.get("curl", 0.0), opts.get("sway", 0.0), r, opts.get("spin", 0.0),
		opts.get("fade_in", 0.0), f)


func _process(delta: float) -> void:
	if camera == null or not is_instance_valid(camera):
		camera = get_viewport().get_camera_3d()
	if delta <= 0.0:
		return
	var cam_r := Vector3.RIGHT
	var cam_u := Vector3.UP
	if camera != null:
		cam_r = camera.global_basis.x
		cam_u = camera.global_basis.y
	billboard.step(delta, cam_r, cam_u)
	ground.step(delta, cam_r, cam_u)


## 월드 방향 v를 화면 회전각으로(꼬리·줄기 정렬용).
func screen_angle(v: Vector3) -> float:
	if camera == null:
		return 0.0
	return atan2(v.dot(camera.global_basis.y), v.dot(camera.global_basis.x))


func active_count() -> int:
	return billboard.n + ground.n

