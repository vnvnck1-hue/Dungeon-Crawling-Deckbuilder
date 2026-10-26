extends Node
## 디스플레이 설정: 화면 모드(창·전체 화면 테두리 없음·전용 전체 화면)·창 크기·수직 동기화·프레임 제한·3D 렌더 배율과
## F11 전체 화면 전환(일시 정지·메뉴 중에도 동작). 값은 user://settings.cfg [display] 에 저장되어 다음 실행에 그대로
## 적용된다(소리 설정과 같은 파일이며 다른 구역은 건드리지 않는다). 처음 실행하면 모니터 해상도 그대로 전체 화면(테두리 없음).
##
## 어떤 모니터 비율에서도 정렬이 맞는 원리(project.godot [display]):
## - stretch = canvas_items + expand, 기준 1774×887(2:1). UI 배율은 짧은 쪽(대개 높이)에 맞춰 정해지고, 남는 가로·세로는
##   화면이 넓어지는 쪽으로 쓴다. 3440×1440(21:9) → 보이는 UI 화면 2118×887, 1920×1080(16:9) → 1774×997,
##   1024×768(4:3) → 1774×1330, 5120×1440(32:9) → 3153×887. 기준보다 작아지는 쪽은 없으므로 UI가 잘리지 않는다.
## - 모서리 HUD는 앵커·Layout.ui_scale로, 가운데 펼침 화면은 CenterStage(ui/center_stage.gd)로, 모달은 fit_modal로
##   창 크기가 바뀔 때마다 다시 정렬된다. 3D 카메라는 세로 시야를 유지하고 넓은 화면일수록 좌우를 더 보여 준다.

signal changed

const SETTINGS_PATH := "user://settings.cfg"
const SECTION := "display"
const MODES := ["windowed", "borderless", "fullscreen"]
const MODE_NAMES := ["창 모드", "전체 화면 (테두리 없음)", "전체 화면 (전용)"]
const WINDOW_SIZES := [
	Vector2i(1280, 720), Vector2i(1600, 800), Vector2i(1600, 900), Vector2i(1920, 1080),
	Vector2i(2560, 1080), Vector2i(2560, 1440), Vector2i(3440, 1440), Vector2i(3840, 2160),
]
const FPS_LIMITS := [0, 30, 60, 120, 144, 165, 240]
const RENDER_SCALES := [0.5, 0.67, 0.75, 0.85, 1.0]
const DEFAULT_MODE := "borderless"
const DEFAULT_WINDOW := Vector2i(1600, 800)

var settings_path := SETTINGS_PATH  # 검증에서는 다른 파일을 쓴다
var mode := DEFAULT_MODE
var window_size := DEFAULT_WINDOW
var vsync := true
var max_fps := 0                     # 0 = 제한 없음
var render_scale := 1.0
## 실제 창·GPU에 적용할지. 검증·캡처 실행(--script)에서는 창을 건드리지 않고 값만 다룬다.
var apply_window := true
var _window: Window
var _last_fullscreen := DEFAULT_MODE


func _ready() -> void:
	name = "WindowMode"
	process_mode = Node.PROCESS_MODE_ALWAYS
	_window = get_tree().root
	apply_window = not ("--script" in OS.get_cmdline_args())
	load_settings()
	if "--windowed" in OS.get_cmdline_user_args():
		mode = "windowed"  # 이번 실행만 창 모드(저장하지 않음)
	apply_all()


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY_F11:
		return
	toggle_fullscreen()
	get_viewport().set_input_as_handled()


# ───────────────────────── 바꾸기(UI·단축키가 부른다) ─────────────────────────

## F11: 창 모드 ↔ 마지막으로 쓴 전체 화면 모드.
func toggle_fullscreen() -> void:
	set_mode(_last_fullscreen if mode == "windowed" else "windowed")


func set_mode(m: String, save := true) -> void:
	if not m in MODES:
		return
	mode = m
	if m != "windowed":
		_last_fullscreen = m
	_apply_window_mode()
	_done(save)


func set_window_size(sz: Vector2i, save := true) -> void:
	window_size = Vector2i(maxi(sz.x, 640), maxi(sz.y, 360))
	if mode == "windowed":
		_apply_window_mode()
	_done(save)


func set_vsync(on: bool, save := true) -> void:
	vsync = on
	_apply_vsync()
	_done(save)


func set_max_fps(fps: int, save := true) -> void:
	max_fps = maxi(fps, 0)
	_apply_fps()
	_done(save)


func set_render_scale(v: float, save := true) -> void:
	render_scale = clampf(v, 0.25, 1.0)
	_apply_render_scale()
	_done(save)


func _done(save: bool) -> void:
	if save:
		save_settings()
	changed.emit()


# ───────────────────────── 적용 ─────────────────────────

func apply_all() -> void:
	_apply_window_mode()
	_apply_vsync()
	_apply_fps()
	_apply_render_scale()


func _apply_window_mode() -> void:
	if not apply_window or _window == null:
		return
	match mode:
		"borderless":
			_window.mode = Window.MODE_FULLSCREEN
		"fullscreen":
			_window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN
		_:
			if _window.mode != Window.MODE_WINDOWED:
				_window.mode = Window.MODE_WINDOWED
			# 모드 전환 직후에는 OS가 크기를 덮어쓰므로 한 프레임 뒤에 크기·위치를 잡는다
			_place_window.call_deferred()


## 창 모드: 고른 크기를 지금 모니터의 작업 영역에 맞춰(넘치면 비율 유지 축소) 가운데에 놓는다.
func _place_window() -> void:
	if mode != "windowed" or _window.mode != Window.MODE_WINDOWED:
		return
	var area := DisplayServer.screen_get_usable_rect(_window.current_screen)
	var sz := fit_size(window_size, area.size)
	_window.size = sz
	_window.position = area.position + (area.size - sz) / 2


func _apply_vsync() -> void:
	if apply_window:
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)


func _apply_fps() -> void:
	if apply_window:
		Engine.max_fps = max_fps


func _apply_render_scale() -> void:
	if _window == null:
		return
	_window.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	_window.scaling_3d_scale = render_scale


# ───────────────────────── 계산 도우미(검증에서도 쓴다) ─────────────────────────

## 창 크기 sz가 작업 영역 area 안에 들어가도록 비율을 지켜 줄인다(작업 영역이 0이면 그대로).
static func fit_size(sz: Vector2i, area: Vector2i) -> Vector2i:
	if area.x <= 0 or area.y <= 0:
		return sz
	var s := minf(1.0, minf(float(area.x) / sz.x, float(area.y) / sz.y))
	return Vector2i(int(sz.x * s), int(sz.y * s))


## 창 크기 선택지: 지금 모니터에 들어가는 표준 크기들(+ 지금 저장된 크기).
func window_size_choices() -> Array:
	var screen := DisplayServer.screen_get_size(_window.current_screen if _window != null else 0)
	var out: Array = []
	for sz in WINDOW_SIZES:
		if screen.x <= 0 or (sz.x <= screen.x and sz.y <= screen.y):
			out.append(sz)
	if not window_size in out:
		out.append(window_size)
	if out.is_empty():
		out.append(DEFAULT_WINDOW)
	return out


## 지금 실제 화면(창) 해상도와 UI가 쓰는 화면 크기 — 설정 창 안내 문구용.
func describe() -> String:
	var win := _window.size if _window != null else Vector2i.ZERO
	var ui := _window.get_visible_rect().size if _window != null else Vector2.ZERO
	return "화면 %d×%d · UI 기준 %d×%d" % [win.x, win.y, int(ui.x), int(ui.y)]


# ───────────────────────── 저장 ─────────────────────────

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) != OK:
		return
	var m := str(cfg.get_value(SECTION, "mode", DEFAULT_MODE))
	mode = m if m in MODES else DEFAULT_MODE
	var last := str(cfg.get_value(SECTION, "last_fullscreen", DEFAULT_MODE))
	_last_fullscreen = last if last in MODES and last != "windowed" else DEFAULT_MODE
	var ws = cfg.get_value(SECTION, "window_size", DEFAULT_WINDOW)
	window_size = ws if ws is Vector2i else DEFAULT_WINDOW
	vsync = bool(cfg.get_value(SECTION, "vsync", true))
	max_fps = maxi(int(cfg.get_value(SECTION, "max_fps", 0)), 0)
	render_scale = clampf(float(cfg.get_value(SECTION, "render_scale", 1.0)), 0.25, 1.0)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)  # 다른 구역(소리 등)의 설정은 그대로 둔다
	cfg.set_value(SECTION, "mode", mode)
	cfg.set_value(SECTION, "last_fullscreen", _last_fullscreen)
	cfg.set_value(SECTION, "window_size", window_size)
	cfg.set_value(SECTION, "vsync", vsync)
	cfg.set_value(SECTION, "max_fps", max_fps)
	cfg.set_value(SECTION, "render_scale", render_scale)
	cfg.save(settings_path)
