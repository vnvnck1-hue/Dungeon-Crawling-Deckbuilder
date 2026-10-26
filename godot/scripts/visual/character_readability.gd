extends Node
## 캐릭터–배경 분리 시험(2026-10-21): F10 으로 기존 → ①림·외곽선 → ①+②발밑 그림자 → ①+②+③따뜻한 강조색을 돌려 비교한다.
## 리서치 근거: TF2 림라이트, Hades·Don't Starve 외곽선, Dota 2 명도 계층, Diablo 캐릭터 빛.
##  ① 림·외곽선: 캐릭터 메시에만 어두운 얇은 외곽선(target_outline) + 위쪽 가장자리 앰버 림(character_rim). material_overlay 사용.
##  ② 발밑 그림자: 몸과 같은 명도로 붙던 실제 그림자를 끄고, 한 단계 밝고 푸른 둥근 그림자(blob_shadow)로 바꾼다.
##  ③ 강조색: 보라 세계의 보색인 앰버 — 주인공(그룹 readable_lead) 랜턴에 작은 빛망울과 발밑을 데우는 점광원.
## 대상은 그룹 readable_characters 의 노드(visual 속성). 나중에 생기는 손님도 주기적으로 훑어 같은 상태로 맞춘다.
## 값은 user://settings.cfg [visual] readability 에 저장. 표시 전용 — 판정·진행에는 관여하지 않는다.

const SETTINGS_PATH := "user://settings.cfg"
const KEY := KEY_F10
const GROUP := "readable_characters"
const LEAD_GROUP := "readable_lead"
const IDS := ["off", "rim", "rim_shadow", "all"]
const NAMES := ["기존", "① 림·외곽선", "①+② 발밑 그림자", "①+②+③ 따뜻한 강조색"]
const DEFAULT_ID := "off"

const OUTLINE_SHADER := preload("res://shaders/target_outline.gdshader")
const RIM_SHADER := preload("res://shaders/character_rim.gdshader")
const BLOB_SHADER := preload("res://shaders/blob_shadow.gdshader")

const OUTLINE_COLOR := Color(0.07, 0.04, 0.12)
const OUTLINE_PX := 1.3   # 2026-10-21 1.8 → 1.3 (사용자: 조금만 더 얇게)
const RIM_COLOR := Color(1.0, 0.68, 0.32)
const ACCENT_COLOR := Color(1.0, 0.64, 0.30)

static var current_id := ""
static var _overlay: ShaderMaterial
static var _blob_mat: ShaderMaterial

var settings_path := SETTINGS_PATH   # 검증에서는 다른 파일을 쓴다
var _scan_t := 0.0
var _toast = preload("res://scripts/ui/top_toast.gd").new(190)


static func id() -> String:
	if current_id == "":
		var cfg := ConfigFile.new()
		var saved := DEFAULT_ID
		if cfg.load(SETTINGS_PATH) == OK:
			saved = str(cfg.get_value("visual", "readability", DEFAULT_ID))
		current_id = saved if saved in IDS else DEFAULT_ID
	return current_id


static func has_rim(mode: String) -> bool: return mode != "off"
static func has_blob(mode: String) -> bool: return mode == "rim_shadow" or mode == "all"
static func has_accent(mode: String) -> bool: return mode == "all"


## 외곽선(overlay) → 림(next_pass) 한 벌. 모든 캐릭터가 같이 쓴다.
static func overlay() -> ShaderMaterial:
	if _overlay == null:
		_overlay = ShaderMaterial.new()
		_overlay.shader = OUTLINE_SHADER
		_overlay.render_priority = 2
		_overlay.set_shader_parameter("line_color", OUTLINE_COLOR)
		_overlay.set_shader_parameter("width_px", OUTLINE_PX)
		_overlay.set_shader_parameter("pulse", 0.0)
		var rim := ShaderMaterial.new()
		rim.shader = RIM_SHADER
		rim.render_priority = 3
		rim.set_shader_parameter("rim_color", RIM_COLOR)
		_overlay.next_pass = rim
	return _overlay


static func blob_material() -> ShaderMaterial:
	if _blob_mat == null:
		_blob_mat = ShaderMaterial.new()
		_blob_mat.shader = BLOB_SHADER
		_blob_mat.render_priority = 1   # -1 이면 바닥 쪽 반투명 층에 가려 보이지 않았다
	return _blob_mat


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--readability=") and arg.trim_prefix("--readability=") in IDS:
			current_id = arg.trim_prefix("--readability=")
	id()


func _process(delta: float) -> void:
	_scan_t -= delta
	if _scan_t > 0.0:
		return
	_scan_t = 0.3
	refresh()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY:
		return
	cycle()
	get_viewport().set_input_as_handled()


func cycle() -> String:
	var next: String = IDS[(IDS.find(id()) + 1) % IDS.size()]
	set_mode(next)
	return next


func set_mode(mode: String, save := true) -> void:
	if not mode in IDS:
		return
	current_id = mode
	if save:
		var cfg := ConfigFile.new()
		cfg.load(settings_path)   # 다른 구역은 그대로 둔다
		cfg.set_value("visual", "readability", mode)
		cfg.save(settings_path)
	refresh()
	_toast.show_text(self, "캐릭터 분리: " + NAMES[IDS.find(mode)] + "  (F10)")


## 그룹의 모든 캐릭터를 지금 상태로 맞춘다(이미 맞춘 캐릭터는 건너뛴다).
func refresh() -> void:
	if not is_inside_tree():
		return
	for actor in get_tree().get_nodes_in_group(GROUP):
		apply(actor, id())


static func apply(actor: Node, mode: String) -> void:
	var vis = actor.get("visual")
	if vis == null or not is_instance_valid(vis) or not (vis is Node3D):
		return
	if str(actor.get_meta("readability_mode", "")) == mode and int(actor.get_meta("readability_meshes", -1)) == _count(vis):
		return
	actor.set_meta("readability_mode", mode)
	var meshes := _meshes(vis)
	actor.set_meta("readability_meshes", meshes.size())
	var ov := overlay()
	for mi: MeshInstance3D in meshes:
		if has_rim(mode):
			if mi.material_overlay == null: mi.material_overlay = ov
		elif mi.material_overlay == ov:
			mi.material_overlay = null
		if has_blob(mode):
			if not mi.has_meta("readability_cast"): mi.set_meta("readability_cast", mi.cast_shadow)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		elif mi.has_meta("readability_cast"):
			mi.cast_shadow = mi.get_meta("readability_cast")
			mi.remove_meta("readability_cast")
	_blob(actor, vis).visible = has_blob(mode)
	if actor.is_in_group(LEAD_GROUP) or actor.get_node_or_null("ReadabilityAccent") != null:
		_accent(actor, vis, has_accent(mode))


static func _count(vis: Node) -> int:
	return _meshes(vis).size()


## 캐릭터 몸 메시(이 모듈이 붙인 강조 빛망울은 뺀다).
static func _meshes(vis: Node) -> Array:
	return vis.find_children("*", "MeshInstance3D", true, false).filter(
		func(m): return not str(m.name).begins_with("Readability"))


static func _blob(actor: Node, vis: Node3D) -> MeshInstance3D:
	var blob := actor.get_node_or_null("ReadabilityBlob") as MeshInstance3D
	if blob != null:
		return blob
	var r := 0.5 * vis.scale.x
	var plane := PlaneMesh.new()
	plane.size = Vector2(r, r) * 2.0
	blob = MeshInstance3D.new()
	blob.name = "ReadabilityBlob"
	blob.mesh = plane
	blob.material_override = blob_material()
	blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	blob.position.y = 0.03   # 돌판에 묻히지 않게 셰이더(lift)가 카메라 쪽으로 당겨 그린다
	actor.add_child(blob)
	return blob


## 주인공 랜턴(없으면 가슴 앞)에 앰버 빛망울 + 발밑을 데우는 점광원.
static func _accent(actor: Node, vis: Node3D, on: bool) -> void:
	var acc := actor.get_node_or_null("ReadabilityAccent") as Node3D
	if acc == null:
		if not on:
			return
		acc = Node3D.new()
		acc.name = "ReadabilityAccent"   # 이름표 역할(주인공 판별) — 실제 빛은 랜턴 피벗 아래에 붙인다
		actor.add_child(acc)
		var anchor: Node3D = null
		var at := Vector3(0, 0.75, 0.3)
		for n in vis.find_children("*", "Node3D", true, false):
			if str(n.get_meta("part_group", "")) == "lantern":
				var mesh := n.get_node_or_null("Mesh") as MeshInstance3D
				if mesh != null and mesh.mesh != null:
					anchor = n
					at = mesh.transform * mesh.mesh.get_aabb().get_center()
				break
		if anchor == null:
			anchor = vis
		var glow := MeshInstance3D.new()
		glow.name = "ReadabilityGlow"
		var sphere := SphereMesh.new()
		sphere.radius = 0.06
		sphere.height = 0.12
		glow.mesh = sphere
		var gm := StandardMaterial3D.new()
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		gm.albedo_color = ACCENT_COLOR * 1.6
		gm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		glow.material_override = gm
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		glow.position = at
		anchor.add_child(glow)
		var light := OmniLight3D.new()
		light.name = "ReadabilityLight"
		light.light_color = ACCENT_COLOR
		light.light_energy = 0.6
		light.omni_range = 2.0
		light.omni_attenuation = 1.3
		light.shadow_enabled = false
		light.position = at
		anchor.add_child(light)
		acc.set_meta("parts", [glow, light])
	for part in acc.get_meta("parts", []):
		if is_instance_valid(part): part.visible = on
