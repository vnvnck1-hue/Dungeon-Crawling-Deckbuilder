extends Node
## Presentation clock reads the existing preparation timer. Combat remains full night.
const Cfg := preload("res://scripts/config.gd")
const Styles := preload("res://scripts/visual/screen_style.gd")
const Session := preload("res://scripts/game/game_session.gd")
const IDS := ["auto", "day", "sunset", "dusk", "night"]
const NAMES := ["자동 · 낮 → 밤", "낮 · 비교용", "노을 · 비교용", "황혼 · 비교용", "밤 · 기준 라이팅"]
const STOPS := [0.0, .45, .68, .82, 1.0]
const ROTATIONS := [Vector3(-60,-25,0), Vector3(-38,20,0), Vector3(-12,70,0), Vector3(-25,115,0), Vector3(-64,145,0)]
var world
var mode := "auto"
var progress := 0.0
var night_amount := 0.0
var _dawn_elapsed := 12.0
# 화면 스타일별 밤 기준 프로필과 시각별 키 프로필(STOPS 순). 매 프레임 다시 만들지 않고 스타일이 바뀔 때만 만든다.
var _profiles_style := ""
var _night_profile: Dictionary
var _key_profiles: Array = []

func bind(owner_world) -> void:
	world = owner_world
	process_priority = 5
	world.game.session.state_changed.connect(_on_state_changed)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="): set_mode(arg.trim_prefix("--time="))
	refresh()

func set_mode(id: String) -> bool:
	if id not in IDS: return false
	mode = id
	if world != null: refresh()
	if world != null and world.aerial_perspective != null: world.aerial_perspective.sync_colors()
	if world != null and world.fog_of_war != null: world.fog_of_war.refresh()
	return true

func _on_state_changed(state: int) -> void:
	if state == Session.State.PREP: _dawn_elapsed = 0.0

func _process(delta: float) -> void:
	_dawn_elapsed = minf(_dawn_elapsed + delta, 12.0)
	# 밤·전투·고정 모드처럼 값이 그대로면 조명 전체(환경·해·셰이더 수십 개)를 다시 쓰지 않는다.
	# 독 지역(hazard_regions)·보스룸(boss_room)은 이 값 위에 섞으므로, 지난 프레임에 섞었으면(influence > 0) 기본값을 다시 깔아야 한다.
	var target := _target()
	var hazard = world.get("hazard_regions")
	var boss = world.get("boss_room")
	var blended: bool = (hazard != null and hazard.influence > 0.0) or (boss != null and boss.influence > 0.0)
	if not blended and target == _applied_target and Styles.current_id == _applied_style and mode == _applied_mode:
		return
	refresh()

var _applied_target := -1.0
var _applied_style := ""
var _applied_mode := ""

## 다른 곳에서 기준 조명을 덮어썼다(화면 스타일 적용 등): 다음 프레임에 시각 조명을 다시 깐다.
func mark_dirty() -> void:
	_applied_style = ""

func _target() -> float:
	var session = world.game.session
	var target := clampf(session.prep_elapsed / Cfg.PREP_TIME, 0.0, 1.0) if session.state == Session.State.PREP else 1.0
	if session.state == Session.State.PREP and _dawn_elapsed < 12.0:
		target = lerpf(1.0, target, smoothstep(0.0, 12.0, _dawn_elapsed))
	if mode != "auto": target = {"day":0.0, "sunset":.68, "dusk":.82, "night":1.0}[mode]
	return target

func refresh() -> void:
	var target := _target()
	_applied_target = target
	_applied_style = Styles.current_id
	_applied_mode = mode
	progress = target
	night_amount = smoothstep(.55, 1.0, progress)
	var segment := 0
	while segment < STOPS.size()-2 and progress > STOPS[segment+1]: segment += 1
	var t := smoothstep(STOPS[segment], STOPS[segment+1], progress)
	_ensure_profiles()
	var a: Dictionary = _key_profiles[segment]
	var b: Dictionary = _key_profiles[segment+1]
	var p := _night_profile.duplicate()
	for key in a:
		if a[key] is Color: p[key] = a[key].lerp(b[key], t)
		elif a[key] is float: p[key] = lerpf(a[key], b[key], t)
	Styles.apply_environment(world, p)
	world.sun.rotation_degrees = ROTATIONS[segment].lerp(ROTATIONS[segment+1], t)

func _ensure_profiles() -> void:
	if _profiles_style == Styles.current_id and not _key_profiles.is_empty():
		return
	_profiles_style = Styles.current_id
	_night_profile = Styles.profile(_profiles_style)
	_key_profiles.clear()
	for i in STOPS.size():
		_key_profiles.append(_key_profile(i, _night_profile))

func _key_profile(index: int, night: Dictionary) -> Dictionary:
	var p := night.duplicate()
	match index:
		0:
			p.merge({"ambient":.42,"ambient_color":Color(.72,.82,1),"moon":1.12,"moon_color":Color(1,.96,.84),"ground_emission":.025,"ground_tint":Color(1,.99,.95),"warm_ground":.10,"vignette":.08,"glow":.10,"rig_energy":night.rig_energy*.10,"haze_opacity":night.haze_opacity*.25,"shadow_opacity":.82},true)
		1:
			p.merge({"ambient":.32,"ambient_color":Color(.65,.68,.89),"moon":1.02,"moon_color":Color(1,.82,.60),"ground_emission":.025,"ground_tint":Color(1,.96,.91),"warm_ground":.20,"vignette":.10,"glow":.12,"rig_energy":night.rig_energy*.20,"haze_opacity":night.haze_opacity*.40,"shadow_opacity":.88},true)
		2:
			p.merge({"ambient":.22,"ambient_color":Color(.58,.40,.72),"moon":.88,"moon_color":Color(1,.46,.22),"ground_emission":.04,"ground_tint":Color(1.02,.88,.95),"warm_ground":.35,"vignette":.16,"glow":.18,"rig_energy":night.rig_energy*.48,"haze_opacity":night.haze_opacity*.65,"shadow_opacity":.92},true)
		3:
			p.merge({"ambient":.12,"ambient_color":Color(.40,.30,.69),"moon":.42,"moon_color":Color(.72,.53,.91),"ground_emission":.055,"ground_tint":Color(.90,.86,1.04),"warm_ground":.48,"vignette":.22,"glow":.22,"rig_energy":night.rig_energy*.85,"haze_opacity":night.haze_opacity*.90,"shadow_opacity":.95},true)
	return p
