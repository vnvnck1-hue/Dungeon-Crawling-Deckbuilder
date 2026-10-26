extends RefCounted
## Independent camera presets. FOV/distance match the visible height at the ground focus.
## Materials, lights, world layout and gameplay state belong to other modules.
const Layout := preload("res://scripts/world/layout.gd")
const IDS := ["orthographic", "lens_soft", "lens_balanced", "lens_wide", "lens_high"]
const NAMES := ["기존 직교뷰", "약한 원근 · 18°", "균형 원근 · 26°", "넓은 원근 · 34°", "높은 전략뷰 · 26°"]
const DEFAULT_ID := "lens_wide"
static var current_id := DEFAULT_ID

static func profile(id: String) -> Dictionary:
	var p := {"perspective":true,"fov":26.0,"pitch":Layout.CAMERA_PITCH,
		"yaw":Layout.CAMERA_YAW,"height":Layout.CAMERA_SIZE,"target":Layout.CAMERA_TARGET}
	match id:
		"orthographic": p.merge({"perspective":false,"fov":75.0},true)
		"lens_soft": p.fov = 18.0
		"lens_wide": p.fov = 34.0
		"lens_high": p.pitch = 58.0
	p["distance"] = p.height*.5/tan(deg_to_rad(p.fov)*.5) if p.perspective else Layout.CAMERA_DISTANCE
	return p

static func apply(camera: Camera3D, id: String) -> bool:
	if id not in IDS: return false
	var p := profile(id)
	current_id = id
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE if p.perspective else Camera3D.PROJECTION_ORTHOGONAL
	camera.fov = p.fov
	camera.size = p.height
	camera.near = 1.0
	camera.far = 140.0
	camera.h_offset = 0.0
	camera.v_offset = 0.0
	camera.rotation_degrees = Vector3(-p.pitch,p.yaw,0.0)
	camera.position = p.target+camera.transform.basis.z*p.distance
	return true
