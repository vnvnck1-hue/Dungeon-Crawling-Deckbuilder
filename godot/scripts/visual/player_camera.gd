extends Node
## Follow/framing and zoom are independent of the five lens/shading presets.
const Layout := preload("res://scripts/world/layout.gd")
const CameraStyle := preload("res://scripts/visual/camera_style.gd")
const MIN_HEIGHT := 12.0
const MAX_HEIGHT := 28.0
var camera: Camera3D
var target: Node3D
var focus := Vector3.ZERO
var height := 18.0
var desired_height := 18.0
var follow_enabled := true
var occluders: Array = []
## 장소 연출(보스룸 등)이 잠깐 시야를 넓힐 때: 기준 높이에 더할 값과 초점을 끌어당길 지점·비율(0이면 꺼짐).
## 연출 쪽이 매 프레임 원하는 값을 넣고 이 노드가 부드럽게 따라간다. 사용자의 줌(desired_height)은 건드리지 않는다.
var framing_extra := 0.0
var framing_point := Vector3.ZERO
var framing_weight := 0.0


func bind(cam: Camera3D, player: Node3D, trees: Array) -> void:
	camera = cam
	target = player
	occluders = trees
	process_priority = 10
	recenter()


func _target_focus() -> Vector3:
	var forward := -camera.global_basis.z
	forward.y = 0.0
	# Player sits slightly below center, clear of the hand and status HUD.
	var at := target.global_position + forward.normalized() * 1.8
	if framing_weight > 0.0:
		at = at.lerp(Vector3(framing_point.x, 0.0, framing_point.z), framing_weight)
	return Layout.clamp_to_map(at, 0.8)


func recenter() -> void:
	if not is_instance_valid(target): return
	follow_enabled = true
	focus = _target_focus()
	_place()


func toggle_overview() -> void:
	follow_enabled = not follow_enabled
	if not follow_enabled:
		CameraStyle.apply(camera, CameraStyle.current_id)
	else:
		recenter()


func on_lens_changed() -> void:
	if follow_enabled: _place()


func zoom(steps: float) -> void:
	if not follow_enabled: recenter()
	desired_height = clampf(desired_height + steps * 1.5, MIN_HEIGHT, MAX_HEIGHT)


func _process(delta: float) -> void:
	delta = preload("res://scripts/ui/hand_focus_time.gd").ui_delta(delta)   # 손패 고민 시간으로 세상이 늦춰져도 카메라(줌·따라가기)는 실제 시간으로
	if not is_instance_valid(target): return
	if not follow_enabled:
		_update_occlusion(delta)
		return
	var blend := 1.0 - exp(-9.0 * delta)
	focus = focus.lerp(_target_focus(), blend)
	height = lerpf(height, minf(desired_height + framing_extra, MAX_HEIGHT + 6.0), 1.0 - exp(-12.0 * delta))
	_place()
	_update_occlusion(delta)


var _any_faded := true   # 비친 나무가 하나라도 남았나: 따라가기가 꺼졌고 모두 불투명하면 나무를 돌지 않는다

func _update_occlusion(delta: float) -> void:
	if not follow_enabled and not _any_faded:
		return
	var to := target.global_position + Vector3(0,.8,0)
	var any := false
	for tree in occluders:
		var obscured: bool = follow_enabled and tree.bounds.intersects_segment(camera.global_position,to) != null
		var wanted := .78 if obscured else 0.0
		var alpha := move_toward(float(tree.fade),wanted,delta*4.0)
		if not is_equal_approx(alpha,float(tree.fade)):
			tree.fade=alpha
			for mesh in tree.meshes:
				mesh.transparency=alpha
		if float(tree.fade) != 0.0: any = true
	_any_faded = any


func _place() -> void:
	camera.size = height
	var distance := Layout.CAMERA_DISTANCE
	if camera.projection == Camera3D.PROJECTION_PERSPECTIVE:
		distance = height * 0.5 / tan(deg_to_rad(camera.fov) * 0.5)
	camera.global_position = focus + camera.global_basis.z * distance
