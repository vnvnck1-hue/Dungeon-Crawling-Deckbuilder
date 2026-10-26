extends CanvasLayer
## 프롤로그(모션 코믹스 v01, 기획 docs/prologue-motion-comics-design.md): 마녀사냥 이후 살아남은 마녀 → 숲속 산장 → 그 아래 봉인석 →
## 낮엔 나그네, 밤엔 괴물. 자막 4장은 narrative.md §1 도입 초안과 world-races-card-formats-v01.md §1 역사를 실제 리듬에 맞춘 것이다.
## 각 컷은 assets/ui/ftue/motion/cutN.json 매니페스트의 레이어(코덱스 요청서 docs/handoff/codex-prologue-motion-comics-v01.md)를
## 설계 화면 1920×1080 위에 겹쳐 놓고 TRACKS 타임라인으로 순차 등장·이동·전환한다. 매니페스트나 레이어가 없는 컷은
## 기존 정지 그림(assets/ui/ftue/prologue_0N.png), 그것도 없으면 단색 그라데이션으로 대신한다(느린 확대만).
## 클릭·Space·Enter = 다음 컷(현재 컷은 퇴장 전환을 돌리며 다음 컷과 겹친다), Esc·'건너뛰기' = 끝까지 건너뛰기. 각 컷은 정해진 시간 뒤 저절로 넘어간다.
## 끝나면 화면을 검게 둔 채 finished 를 낸다 — 이어지는 새벽 연출(opening_director)이 검은 막을 걷는다.

signal finished(skipped: bool)

const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const Extension := preload("res://scripts/ui/moon/moon_extension.gd")

const SLIDE_TIME := 5.5          # 정지 그림 폴백 한 장의 길이
const FADE := 0.6
const ART_DIR := "res://assets/ui/ftue/"
const MOTION_DIR := "res://assets/ui/ftue/motion/"
const DESIGN := Vector2(1920, 1080)   # 설계 화면
const TYPE_SPEED := 0.025        # 자막 한 글자 간격(초)
## [그림 파일, 자막, 플레이스홀더 위색, 아래색]
const SLIDES := [
	["prologue_01.png", "마녀사냥이 끝났을 때, 살아남은 마녀는 넷뿐이었다.\n넷은 동서남북으로 흩어져 몸을 숨겼다.", Color(0.32, 0.10, 0.12), Color(0.06, 0.03, 0.08)],
	["prologue_02.png", "마을에도 도시에도 마녀가 머물 자리는 없었다.\n당신은 깊은 숲에 작은 산장을 열었다.", Color(0.16, 0.13, 0.34), Color(0.04, 0.05, 0.12)],
	["prologue_03.png", "산장 아래에는 봉인석이 잠들어 있다.\n숲의 오래된 것들이 노리는 돌이다.", Color(0.06, 0.24, 0.28), Color(0.02, 0.03, 0.07)],
	["prologue_04.png", "낮에는 당신을 꺼리는 나그네들이 잠자리를 찾아오고,\n밤이면 숲의 괴물이 봉인석을 노린다.", Color(0.40, 0.20, 0.30), Color(0.05, 0.03, 0.12)],
]

## 컷별 타임라인(기획 §3). 시각은 초, 이동은 설계 화면 픽셀. 트랙 종류:
##  alpha{layer,t0,dur,from,to} · move{layer,t0,dur,from,to,ease} · scale{layer,t0,dur,from,to} · inkin{layer,t0}(알파+0.97→1 스케일)
##  bright{layer,t0,dur,from,to}(모듈레이트 밝기) · drift{layer,t0,vel,amp,period}(연기) · breathe{layer,t0,period,min,max,prop}
##  flicker{layer,t0} · blink{layer,t0} · bob{layer,t0,t1}(걷기 흔들림) · sway{layer,t0,deg,period}(회전 흔들림)
##  cam_zoom{t0,dur,from,to,center} · cam_sway{t0,amp,period} · cam_tilt{t0,dur,from,to}(도) · cut_alpha/cut_move{t0,dur,from,to}(컷 전체) · flash{t0,dur,from,to,color}
##  caption{t0,line}(1·2행 등장) · particles{layer_hint}(불티)
## dur = 자막이 끝나고 다음 컷이 시작되는 시각, exit = 퇴장 전환이 다음 컷과 겹치는 길이.
const CUTS := [
	{"dur": 8.5, "exit": 0.7, "tracks": [
		{"k": "alpha", "layer": "sky", "t0": 0.0, "dur": 0.8, "from": 0.0, "to": 1.0},
		{"k": "inkin", "layer": "village", "t0": 0.6},
		{"k": "breathe", "layer": "village", "t0": 1.2, "period": 1.6, "min": 1.0, "max": 1.25, "prop": "bright"},
		{"k": "inkin", "layer": "smoke", "t0": 0.9},
		{"k": "drift", "layer": "smoke", "t0": 1.0, "vel": Vector2(0, -12), "amp": 0.06, "period": 4.0},
		{"k": "alpha", "layer": "cliff", "t0": 1.4, "dur": 0.8, "from": 0.0, "to": 1.0},
		{"k": "move", "layer": "cliff", "t0": 1.4, "dur": 0.8, "from": Vector2(0, 40), "to": Vector2.ZERO},
		# v02 구도: 비탈을 내려가는 세 마녀(중경 1, 원경 2)가 각자의 길로 멀어진다. 네 번째는 전경의 큰 마녀(witch_fore).
		{"k": "inkin", "layer": "witch_1", "t0": 2.0}, {"k": "inkin", "layer": "witch_2", "t0": 2.0}, {"k": "inkin", "layer": "witch_3", "t0": 2.0},
		{"k": "move", "layer": "witch_1", "t0": 4.0, "dur": 2.2, "from": Vector2.ZERO, "to": Vector2(-180, 60), "ease": "in"},
		{"k": "move", "layer": "witch_2", "t0": 4.0, "dur": 2.2, "from": Vector2.ZERO, "to": Vector2(-90, -40), "ease": "in"},
		{"k": "move", "layer": "witch_3", "t0": 4.0, "dur": 2.2, "from": Vector2.ZERO, "to": Vector2(70, -50), "ease": "in"},
		{"k": "scale", "layer": "witch_1", "t0": 4.0, "dur": 2.2, "from": 1.0, "to": 0.8}, {"k": "scale", "layer": "witch_2", "t0": 4.0, "dur": 2.2, "from": 1.0, "to": 0.8},
		{"k": "scale", "layer": "witch_3", "t0": 4.0, "dur": 2.2, "from": 1.0, "to": 0.8},
		{"k": "alpha", "layer": "witch_1", "t0": 4.0, "dur": 2.2, "from": 1.0, "to": 0.3}, {"k": "alpha", "layer": "witch_2", "t0": 4.0, "dur": 2.2, "from": 1.0, "to": 0.3},
		{"k": "alpha", "layer": "witch_3", "t0": 4.0, "dur": 2.2, "from": 1.0, "to": 0.3},
		{"k": "move", "layer": "witch_fore", "t0": 6.5, "dur": 2.0, "from": Vector2.ZERO, "to": Vector2(80, 0), "ease": "inout"},
		{"k": "particles", "layer_hint": "village"},
		{"k": "caption", "t0": 2.0, "line": 1}, {"k": "caption", "t0": 4.2, "line": 2},
		{"k": "cam_zoom", "t0": 6.5, "dur": 2.0, "from": 1.0, "to": 1.12, "center": Vector2(760, 450)},
		# 퇴장 T1: 연기가 부풀어 오르고 연기 빛(짙은 자주)이 화면 전체를 덮은 뒤 다음 컷 위에서 걷힌다
		{"k": "scale", "layer": "smoke", "t0": 8.5, "dur": 0.7, "from": 1.0, "to": 2.4},
		{"k": "alpha", "layer": "smoke", "t0": 8.5, "dur": 0.7, "from": 1.0, "to": 1.0},
		{"k": "flash", "t0": 8.5, "dur": 0.4, "from": 0.0, "to": 0.92, "color": Color(0.20, 0.07, 0.15)},
		{"k": "cut_alpha", "t0": 8.9, "dur": 0.3, "from": 1.0, "to": 0.0},
	]},
	{"dur": 8.5, "exit": 0.7, "tracks": [
		{"k": "alpha", "layer": "fog", "t0": 0.0, "dur": 1.0, "from": 1.0, "to": 0.0},
		# v02 구도: 전경의 거대한 둥치 둘(trunk_*)이 갈라지고, 중경 나무도 조금 벌어지며, 마녀는 S자 길을 따라 산장 쪽(오른쪽 위)으로 멀어진다.
		{"k": "move", "layer": "trunk_left", "t0": 0.0, "dur": 1.6, "from": Vector2(140, 0), "to": Vector2.ZERO},
		{"k": "move", "layer": "trunk_right", "t0": 0.0, "dur": 1.6, "from": Vector2(-140, 0), "to": Vector2.ZERO},
		{"k": "move", "layer": "trees_left", "t0": 0.0, "dur": 1.4, "from": Vector2(60, 0), "to": Vector2.ZERO},
		{"k": "move", "layer": "trees_right", "t0": 0.0, "dur": 1.4, "from": Vector2(-60, 0), "to": Vector2.ZERO},
		{"k": "inkin", "layer": "lodge", "t0": 0.8},
		{"k": "alpha", "layer": "window_glow", "t0": 4.2, "dur": 0.8, "from": 0.0, "to": 1.0},
		{"k": "flicker", "layer": "window_glow", "t0": 4.2},
		{"k": "alpha", "layer": "smoke", "t0": 4.6, "dur": 1.0, "from": 0.0, "to": 1.0},
		{"k": "drift", "layer": "smoke", "t0": 4.6, "vel": Vector2(0, -10), "amp": 0.04, "period": 3.5},
		{"k": "move", "layer": "witch", "t0": 1.0, "dur": 3.0, "from": Vector2(-150, 70), "to": Vector2.ZERO, "ease": "linear"},
		{"k": "scale", "layer": "witch", "t0": 1.0, "dur": 3.0, "from": 1.0, "to": 0.86},
		{"k": "bob", "layer": "witch", "t0": 1.0, "t1": 4.0},
		{"k": "move", "layer": "lantern_glow", "t0": 1.0, "dur": 3.0, "from": Vector2(-150, 70), "to": Vector2.ZERO, "ease": "linear"},
		{"k": "scale", "layer": "lantern_glow", "t0": 1.0, "dur": 3.0, "from": 1.0, "to": 0.86},
		{"k": "bob", "layer": "lantern_glow", "t0": 1.0, "t1": 4.0},
		{"k": "flicker", "layer": "lantern_glow", "t0": 0.0},
		{"k": "caption", "t0": 1.6, "line": 1}, {"k": "caption", "t0": 4.2, "line": 2},
		{"k": "cam_zoom", "t0": 6.0, "dur": 2.5, "from": 1.0, "to": 1.12, "center": Vector2(1150, 420)},
		# 퇴장 T2: 지하로 내려간다(컷 전체가 위로 밀리며 사라진다)
		{"k": "cut_move", "t0": 8.5, "dur": 0.5, "from": Vector2.ZERO, "to": Vector2(0, -200), "ease": "in"},
		{"k": "cut_alpha", "t0": 8.5, "dur": 0.5, "from": 1.0, "to": 0.0},
	]},
	{"dur": 8.0, "exit": 0.35, "tracks": [
		{"k": "cut_move", "t0": 0.0, "dur": 0.6, "from": Vector2(0, -200), "to": Vector2.ZERO},
		{"k": "cut_alpha", "t0": 0.0, "dur": 0.4, "from": 0.0, "to": 1.0},
		{"k": "alpha", "layer": "beams", "t0": 0.2, "dur": 0.8, "from": 0.0, "to": 1.0},
		{"k": "move", "layer": "beams", "t0": 0.2, "dur": 0.8, "from": Vector2(0, -60), "to": Vector2.ZERO},
		{"k": "alpha", "layer": "shafts", "t0": 0.6, "dur": 1.0, "from": 0.0, "to": 0.8},
		{"k": "sway", "layer": "shafts", "t0": 0.6, "deg": 1.0, "period": 3.0},
		{"k": "inkin", "layer": "stone", "t0": 1.0},
		{"k": "alpha", "layer": "runes", "t0": 1.8, "dur": 0.8, "from": 0.0, "to": 0.9},
		{"k": "breathe", "layer": "runes", "t0": 2.6, "period": 2.2, "min": 0.75, "max": 1.0, "prop": "alpha"},
		{"k": "alpha", "layer": "eyes_1", "t0": 4.0, "dur": 0.4, "from": 0.0, "to": 1.0}, {"k": "blink", "layer": "eyes_1", "t0": 4.4},
		{"k": "alpha", "layer": "eyes_2", "t0": 4.5, "dur": 0.4, "from": 0.0, "to": 1.0}, {"k": "blink", "layer": "eyes_2", "t0": 4.9},
		{"k": "alpha", "layer": "eyes_3", "t0": 5.0, "dur": 0.4, "from": 0.0, "to": 1.0}, {"k": "blink", "layer": "eyes_3", "t0": 5.4},
		{"k": "caption", "t0": 1.8, "line": 1}, {"k": "caption", "t0": 4.0, "line": 2},
		{"k": "cam_zoom", "t0": 5.5, "dur": 2.5, "from": 1.0, "to": 1.12, "center": Vector2(960, 560)},
		{"k": "cam_sway", "t0": 5.5, "amp": 6.0, "period": 1.7},
		# 퇴장 T3: 룬 섬광
		{"k": "flash", "t0": 8.0, "dur": 0.35, "from": 0.0, "to": 1.0, "color": Color(0.78, 1.0, 0.96)},
	]},
	{"dur": 9.0, "exit": 0.6, "tracks": [
		{"k": "flash", "t0": 0.0, "dur": 0.6, "from": 1.0, "to": 0.0, "color": Color(0.78, 1.0, 0.96)},
		{"k": "inkin", "layer": "lodge", "t0": 0.4},
		{"k": "flicker", "layer": "window_glow", "t0": 0.0},
		{"k": "breathe", "layer": "window_glow", "t0": 7.0, "period": 1.2, "min": 1.0, "max": 1.4, "prop": "bright"},
		# v02 구도: 전경의 큰 나그네(traveler_fore)와 중경 둘이 대각선 길로 문에 오르고, 밤이 되면 오른쪽 위에서 거대한 거미 다리가 산장 위로 내려온다.
		{"k": "alpha", "layer": "traveler_1", "t0": 0.8, "dur": 0.3, "from": 0.0, "to": 1.0},
		{"k": "alpha", "layer": "traveler_2", "t0": 1.1, "dur": 0.3, "from": 0.0, "to": 1.0},
		{"k": "move", "layer": "traveler_1", "t0": 0.8, "dur": 2.4, "from": Vector2(-160, 60), "to": Vector2.ZERO, "ease": "linear"},
		{"k": "move", "layer": "traveler_2", "t0": 1.1, "dur": 2.4, "from": Vector2(-160, 60), "to": Vector2.ZERO, "ease": "linear"},
		{"k": "scale", "layer": "traveler_1", "t0": 0.8, "dur": 2.4, "from": 1.08, "to": 1.0}, {"k": "scale", "layer": "traveler_2", "t0": 1.1, "dur": 2.4, "from": 1.08, "to": 1.0},
		{"k": "move", "layer": "traveler_fore", "t0": 0.8, "dur": 2.4, "from": Vector2(-120, 0), "to": Vector2.ZERO, "ease": "linear"},
		{"k": "bob", "layer": "traveler_1", "t0": 0.8, "t1": 3.2}, {"k": "bob", "layer": "traveler_2", "t0": 1.1, "t1": 3.5}, {"k": "bob", "layer": "traveler_fore", "t0": 0.8, "t1": 3.2},
		{"k": "alpha", "layer": "sky_night", "t0": 3.6, "dur": 2.5, "from": 0.0, "to": 1.0},
		{"k": "bright", "layer": "traveler_1", "t0": 3.6, "dur": 2.5, "from": 1.0, "to": 0.6},
		{"k": "bright", "layer": "traveler_2", "t0": 3.6, "dur": 2.5, "from": 1.0, "to": 0.6},
		{"k": "bright", "layer": "traveler_fore", "t0": 3.6, "dur": 2.5, "from": 1.0, "to": 0.5},
		{"k": "bright", "layer": "forest", "t0": 3.6, "dur": 2.5, "from": 1.0, "to": 0.7},
		{"k": "cam_tilt", "t0": 3.6, "dur": 2.5, "from": 0.0, "to": -2.0},
		{"k": "alpha", "layer": "spider_legs", "t0": 4.5, "dur": 0.3, "from": 0.0, "to": 1.0},
		{"k": "move", "layer": "spider_legs", "t0": 4.5, "dur": 2.4, "from": Vector2(220, -260), "to": Vector2.ZERO, "ease": "inout"},
		{"k": "alpha", "layer": "spider", "t0": 4.8, "dur": 0.6, "from": 0.0, "to": 1.0}, {"k": "blink", "layer": "spider", "t0": 5.6},
		{"k": "alpha", "layer": "eyes_1", "t0": 5.0, "dur": 0.4, "from": 0.0, "to": 1.0}, {"k": "blink", "layer": "eyes_1", "t0": 5.4},
		{"k": "alpha", "layer": "eyes_2", "t0": 5.6, "dur": 0.4, "from": 0.0, "to": 1.0}, {"k": "blink", "layer": "eyes_2", "t0": 6.0},
		{"k": "caption", "t0": 0.8, "line": 1}, {"k": "caption", "t0": 4.5, "line": 2},
		{"k": "cam_zoom", "t0": 7.0, "dur": 2.0, "from": 1.0, "to": 1.10, "center": Vector2(1300, 480)},
		# 종료: 검은 막
		{"k": "cut_alpha", "t0": 9.0, "dur": 0.6, "from": 1.0, "to": 0.0},
	]},
]

var active := false
var index := -1
var shown_captions: Array = []   # 검증용: 실제로 화면에 나온 자막
var placeholder_used := false    # 정지 그림조차 없어 그라데이션을 쓴 컷이 있다
var motion_used: Array = []      # 검증용: 레이어 모드로 재생한 컷 번호(0-based)
var root: Control
var black: ColorRect
var stage: Control               # 설계 화면 1920×1080, 창 크기에 맞춰 균등 배율
var frame_overlay: TextureRect   # 먹선 비네트 틀(panel_frame.png)
var caption_panel: PanelContainer
var caption: Label
var art: TextureRect             # 호환용 별칭: 현재 컷의 정지 그림(레이어 모드면 비어 있다)
var skip_btn: Button
var pager: Label
var current: CutView
var outgoing: CutView
var _finishing := false
var _tween: Tween


## 한 컷의 레이어 묶음과 타임라인 평가기.
class CutView extends Control:
	var cut := 0
	var tracks: Array = []
	var dur := 8.0
	var exit_len := 0.6
	var t := 0.0
	var layers: Dictionary = {}       # id → TextureRect
	var bases: Dictionary = {}        # id → 정지 위치(설계 좌표)
	var depths: Dictionary = {}       # id → 깊이 0..1
	var static_mode := false          # 정지 그림 폴백
	var art: TextureRect
	var cam: Control
	var flash: ColorRect
	var embers: CPUParticles2D
	var line_at := [0.0, 0.0]         # 자막 1·2행 시각
	var _rng_seed := 7


	func _init(cut_index: int, data: Dictionary) -> void:
		cut = cut_index
		set_anchors_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = false
		dur = data.get("dur", 8.0)
		exit_len = data.get("exit", 0.6)
		tracks = data.get("tracks", [])
		for tr in tracks:
			if tr["k"] == "caption":
				line_at[int(tr["line"]) - 1] = float(tr["t0"])
		cam = Control.new()
		cam.set_anchors_preset(Control.PRESET_FULL_RECT)
		cam.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(cam)
		flash = ColorRect.new()
		flash.set_anchors_preset(Control.PRESET_FULL_RECT)
		flash.color = Color(1, 1, 1, 0)
		flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(flash)


	## 정지 그림 폴백: 느린 확대(1.00 → 1.05)와 짧은 페이드만.
	func use_static(tex: Texture2D, slide_time: float) -> void:
		static_mode = true
		dur = slide_time
		exit_len = 0.6
		art = TextureRect.new()
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.texture = tex
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cam.add_child(art)
		line_at = [0.35, 0.35 + 1.6]
		tracks = [
			{"k": "cut_alpha", "t0": 0.0, "dur": 0.6, "from": 0.0, "to": 1.0},
			{"k": "cam_zoom", "t0": 0.0, "dur": slide_time, "from": 1.0, "to": 1.05, "center": Vector2(960, 540)},
			{"k": "cut_alpha", "t0": slide_time, "dur": 0.6, "from": 1.0, "to": 0.0},
		]


	## 매니페스트의 레이어를 설계 좌표에 놓는다. 하나라도 못 읽으면 false(호출자가 정지 그림으로 되돌린다).
	func use_layers(manifest: Dictionary, loader: Callable) -> bool:
		var canvas_w: float = float(manifest.get("canvas", [2304, 1296])[0])
		var sx: float = (DESIGN_W * 1.2) / canvas_w   # 캔버스가 2304가 아니어도 120% 규칙으로 맞춘다
		for entry in manifest.get("layers", []):
			var id: String = str(entry.get("id", ""))
			var tex: Texture2D = loader.call(str(entry.get("file", "")))
			if id == "" or tex == null:
				return false
			var tr := TextureRect.new()
			tr.name = id
			tr.texture = tex
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_SCALE
			var pos: Array = entry.get("pos", [0, 0])
			var size_arr: Array = entry.get("size", [tex.get_width(), tex.get_height()])
			var base := (Vector2(float(pos[0]), float(pos[1])) + Vector2(-192, -108) * (canvas_w / 2304.0)) * sx
			tr.position = base
			tr.size = Vector2(float(size_arr[0]), float(size_arr[1])) * sx
			tr.pivot_offset = tr.size * 0.5
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			if str(entry.get("blend", "normal")) == "add":
				var mat := CanvasItemMaterial.new()
				mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
				tr.material = mat
			cam.add_child(tr)
			layers[id] = tr
			bases[id] = base
			depths[id] = float(entry.get("depth", 0.5))
		for tr in tracks:
			if tr["k"] == "particles" and embers == null:
				_make_embers(str(tr.get("layer_hint", "")))
		return not layers.is_empty()


	const DESIGN_W := 1920.0


	func _make_embers(hint: String) -> void:
		embers = CPUParticles2D.new()
		embers.amount = 36
		embers.lifetime = 3.2
		embers.preprocess = 1.5
		embers.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		embers.emission_rect_extents = Vector2(220, 40)
		embers.direction = Vector2(0, -1)
		embers.spread = 25.0
		embers.gravity = Vector2(0, -18)
		embers.initial_velocity_min = 18.0
		embers.initial_velocity_max = 46.0
		embers.scale_amount_min = 1.5
		embers.scale_amount_max = 3.5
		embers.color = Color(1.0, 0.62, 0.22, 0.9)
		var anchor: Vector2 = Vector2(960, 520)
		if layers.has(hint):
			var l: TextureRect = layers[hint]
			anchor = l.position + Vector2(l.size.x * 0.5, l.size.y * 0.6)
		embers.position = anchor
		cam.add_child(embers)


	static func _ease(x: float, kind: String) -> float:
		x = clampf(x, 0.0, 1.0)
		match kind:
			"linear": return x
			"in": return x * x
			"inout": return x * x * (3.0 - 2.0 * x)
			_: return 1.0 - (1.0 - x) * (1.0 - x)


	static func _prog(tr: Dictionary, at: float) -> float:
		var d: float = maxf(float(tr.get("dur", 0.0)), 0.0001)
		return clampf((at - float(tr["t0"])) / d, 0.0, 1.0)


	func _noise(seed_: int, at: float) -> float:
		return 0.5 + 0.5 * sin(at * 23.0 + seed_ * 1.7) * sin(at * 7.3 + seed_)


	## 시각 at 에서의 모든 레이어·카메라 상태를 결정적으로 계산한다(검증이 같은 함수를 부른다).
	func evaluate(at: float) -> Dictionary:
		t = at
		var state: Dictionary = {}
		for id in layers.keys():
			state[id] = {"alpha": 1.0, "off": Vector2.ZERO, "scale": 1.0, "bright": 1.0, "rot": 0.0, "has_alpha": false}
		var zoom := 1.0
		var center := Vector2(960, 540)
		var pan := Vector2.ZERO
		var tilt := 0.0   # 카메라 더치 틸트(도)
		var cut_alpha := 1.0
		var cut_off := Vector2.ZERO
		var flash_a := 0.0
		var flash_c := Color(1, 1, 1)
		for tr in tracks:
			var k: String = tr["k"]
			var t0: float = float(tr.get("t0", 0.0))
			var id: String = str(tr.get("layer", ""))
			var has := state.has(id)
			match k:
				"alpha":
					if has:
						var s: Dictionary = state[id]
						if not s["has_alpha"]:
							s["has_alpha"] = true
							s["alpha"] = float(tr["from"])
						if at >= t0:
							s["alpha"] = lerpf(float(tr["from"]), float(tr["to"]), _ease(_prog(tr, at), "linear"))
				"inkin":
					if has:
						var s: Dictionary = state[id]
						if not s["has_alpha"]:
							s["has_alpha"] = true
							s["alpha"] = 0.0
						if at >= t0:
							var p := clampf((at - t0) / 0.5, 0.0, 1.0)
							s["alpha"] = p
							s["scale"] = s["scale"] * lerpf(0.97, 1.0, _ease(p, "out"))
				"move":
					if has:
						var s: Dictionary = state[id]
						var fr: Vector2 = tr["from"]
						var to: Vector2 = tr["to"]
						if at < t0:
							s["off"] += fr
						else:
							s["off"] += fr.lerp(to, _ease(_prog(tr, at), str(tr.get("ease", "out"))))
				"scale":
					if has and at >= t0:
						state[id]["scale"] = state[id]["scale"] * lerpf(float(tr["from"]), float(tr["to"]), _ease(_prog(tr, at), "out"))
				"bright":
					if has and at >= t0:
						state[id]["bright"] = lerpf(float(tr["from"]), float(tr["to"]), _prog(tr, at))
				"drift":
					if has and at >= t0:
						var e := at - t0
						var vel: Vector2 = tr.get("vel", Vector2.ZERO)
						state[id]["off"] += vel * minf(e, 6.0)
						state[id]["scale"] = state[id]["scale"] * (1.0 + float(tr.get("amp", 0.0)) * (0.5 + 0.5 * sin(e * TAU / float(tr.get("period", 4.0)))))
				"breathe":
					if has and at >= t0:
						var v := lerpf(float(tr["min"]), float(tr["max"]), 0.5 + 0.5 * sin((at - t0) * TAU / float(tr.get("period", 2.0))))
						if str(tr.get("prop", "alpha")) == "bright":
							state[id]["bright"] = state[id]["bright"] * v
						else:
							state[id]["alpha"] = state[id]["alpha"] * v
				"flicker":
					if has and at >= t0:
						state[id]["alpha"] = state[id]["alpha"] * lerpf(0.85, 1.0, _noise(id.hash() % 97, at))
				"blink":
					if has and at >= t0:
						var phase := fmod(at - t0 + float(id.hash() % 13) * 0.37, 2.9)
						if phase < 0.1:
							state[id]["alpha"] = 0.0
				"bob":
					if has and at >= t0 and at <= float(tr.get("t1", t0)):
						state[id]["off"] += Vector2(0, -2.0 * absf(sin((at - t0) * TAU / 0.5)))
				"sway":
					if has and at >= t0:
						state[id]["rot"] = deg_to_rad(float(tr.get("deg", 1.0))) * sin((at - t0) * TAU / float(tr.get("period", 3.0)))
				"cam_zoom":
					if at >= t0:
						zoom = lerpf(float(tr["from"]), float(tr["to"]), _ease(_prog(tr, at), "inout"))
						center = tr.get("center", center)
				"cam_sway":
					if at >= t0:
						var e := at - t0
						pan = Vector2(sin(e * TAU / float(tr.get("period", 1.7))), cos(e * TAU / (float(tr.get("period", 1.7)) * 1.37))) * float(tr.get("amp", 6.0))
				"cam_tilt":
					if at >= t0:
						tilt = lerpf(float(tr["from"]), float(tr["to"]), _ease(_prog(tr, at), "inout"))
				"cut_alpha":
					if at < t0:
						if cut_alpha == 1.0 and float(tr["from"]) < 1.0:
							cut_alpha = float(tr["from"])
					else:
						cut_alpha = lerpf(float(tr["from"]), float(tr["to"]), _prog(tr, at))
				"cut_move":
					var fr: Vector2 = tr["from"]
					cut_off = fr if at < t0 else fr.lerp(tr["to"], _ease(_prog(tr, at), str(tr.get("ease", "out"))))
				"flash":
					flash_c = tr.get("color", flash_c)
					if at < t0:
						if float(tr["from"]) > 0.0:
							flash_a = float(tr["from"])
					else:
						flash_a = lerpf(float(tr["from"]), float(tr["to"]), _prog(tr, at))
				_:
					pass
		# 적용
		for id in layers.keys():
			var s: Dictionary = state[id]
			var tr_node: TextureRect = layers[id]
			var depth: float = depths[id]
			tr_node.position = bases[id] + s["off"] + pan * (0.3 + depth * 0.9)
			tr_node.scale = Vector2.ONE * s["scale"]
			tr_node.rotation = s["rot"]
			var b: float = s["bright"]
			tr_node.modulate = Color(b, b, b, s["alpha"])
		cam.pivot_offset = center
		cam.scale = Vector2.ONE * zoom
		cam.rotation = deg_to_rad(tilt)
		cam.position = cut_off
		modulate.a = cut_alpha
		flash.color = Color(flash_c.r, flash_c.g, flash_c.b, flash_a)
		if art != null:
			art.modulate.a = 1.0
		return {"layers": state, "zoom": zoom, "pan": pan, "tilt": tilt, "cut_alpha": cut_alpha, "cut_off": cut_off, "flash": flash_a}


	func finished_exit() -> bool:
		return t >= dur + exit_len


func _ready() -> void:
	name = "Prologue"
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.theme = MoonSkin.make_theme()
	root.visible = false
	root.gui_input.connect(_on_click)
	add_child(root)
	black = ColorRect.new()
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	black.color = Color(0, 0, 0, 1)
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(black)
	stage = Control.new()
	stage.size = DESIGN
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(stage)
	frame_overlay = TextureRect.new()
	frame_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	frame_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	frame_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame_overlay.texture = _load_texture(MOTION_DIR + "panel_frame.png")
	frame_overlay.visible = frame_overlay.texture != null
	root.add_child(frame_overlay)
	art = TextureRect.new()   # 호환용(옛 검증이 참조할 수 있다); 실제 그림은 CutView 안에 있다
	art.visible = false
	root.add_child(art)
	# 자막: 카드의 크림 종이 패널 + 먹색 글
	caption_panel = PanelContainer.new()
	caption_panel.anchor_left = 0.18
	caption_panel.anchor_right = 0.82
	caption_panel.anchor_top = 0.78
	caption_panel.anchor_bottom = 0.78
	caption_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	caption_panel.add_theme_stylebox_override("panel", Extension.paper(18))
	caption_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_panel.modulate.a = 0.0
	root.add_child(caption_panel)
	caption = Label.new()
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.add_theme_font_override("font", MoonSkin.font(true))
	caption.add_theme_font_size_override("font_size", 30)
	caption.add_theme_color_override("font_color", MoonSkin.PAPER_INK)
	caption.add_theme_constant_override("line_spacing", 8)
	caption.custom_minimum_size = Vector2(0, 96)
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	caption_panel.add_child(caption)
	pager = Label.new()
	pager.anchor_left = 0.0
	pager.anchor_top = 1.0
	pager.anchor_bottom = 1.0
	pager.offset_left = 28
	pager.offset_top = -46
	pager.offset_bottom = -18
	pager.add_theme_font_size_override("font_size", 15)
	pager.add_theme_color_override("font_color", MoonSkin.LAVENDER)
	pager.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(pager)
	skip_btn = Button.new()
	skip_btn.text = "건너뛰기  Esc"
	skip_btn.anchor_left = 1.0
	skip_btn.anchor_right = 1.0
	skip_btn.anchor_top = 1.0
	skip_btn.anchor_bottom = 1.0
	skip_btn.offset_left = -200
	skip_btn.offset_right = -24
	skip_btn.offset_top = -64
	skip_btn.offset_bottom = -20
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.pressed.connect(skip)
	root.add_child(skip_btn)
	_fit_stage()
	get_viewport().size_changed.connect(_fit_stage)


## 설계 화면을 창에 맞춰 균등 배율로 가운데 놓는다(가로·세로 비율이 달라도 레이어가 찌그러지지 않는다).
func _fit_stage() -> void:
	var vp := root.get_viewport_rect().size
	if vp.x <= 0 or vp.y <= 0:
		return
	var s := maxf(vp.x / DESIGN.x, vp.y / DESIGN.y)
	stage.scale = Vector2.ONE * s
	stage.position = (vp - DESIGN * s) * 0.5


static func _gradient(top: Color, bottom: Color, from := 0.0) -> GradientTexture2D:
	var g := Gradient.new()
	g.set_offset(0, from)
	g.set_color(0, top)
	g.set_offset(1, 1.0)
	g.set_color(1, bottom)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill_from = Vector2(0, 0)
	t.fill_to = Vector2(0, 1)
	t.width = 8
	t.height = 256
	return t


## 임포트된 리소스 우선, 없으면(아직 --import 전) 원본 PNG를 직접 읽는다. 둘 다 없으면 null.
static func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			return tex
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			return ImageTexture.create_from_image(img)
	return null


## 컷 매니페스트(assets/ui/ftue/motion/cutN.json). 없거나 깨졌으면 빈 사전.
static func manifest_of(i: int) -> Dictionary:
	var path := MOTION_DIR + "cut%d.json" % (i + 1)
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary and (parsed as Dictionary).get("layers", []) is Array:
		return parsed
	return {}


static func has_motion(i: int) -> bool:
	var m := manifest_of(i)
	if m.is_empty() or m["layers"].is_empty():
		return false
	for entry in m["layers"]:
		if not FileAccess.file_exists(MOTION_DIR + str(entry.get("file", ""))) and not ResourceLoader.exists(MOTION_DIR + str(entry.get("file", ""))):
			return false
	return true


## 슬라이드 그림: 납품된 일러스트, 없으면 그라데이션 플레이스홀더.
static func slide_texture(i: int) -> Texture2D:
	var tex := _load_texture(ART_DIR + SLIDES[i][0])
	if tex != null:
		return tex
	return _gradient(SLIDES[i][2], SLIDES[i][3])


static func has_art(i: int) -> bool:
	return ResourceLoader.exists(ART_DIR + SLIDES[i][0]) or FileAccess.file_exists(ART_DIR + SLIDES[i][0])


func play() -> void:
	active = true
	_finishing = false
	index = -1
	shown_captions.clear()
	motion_used.clear()
	root.visible = true
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	black.color.a = 1.0
	skip_btn.visible = true
	pager.visible = true
	_start_cut(0)


func _build_cut(i: int) -> CutView:
	var view := CutView.new(i, CUTS[i])
	var ok := false
	if has_motion(i):
		ok = view.use_layers(manifest_of(i), func(file: String) -> Texture2D: return _load_texture(MOTION_DIR + file))
		if ok:
			motion_used.append(i)
	if not ok:
		if not has_art(i):
			placeholder_used = true
		view.use_static(slide_texture(i), SLIDE_TIME)
	return view


func _start_cut(i: int) -> void:
	index = i
	if i > 0:
		preload("res://scripts/audio/sfx.gd").play(self, "prologue_page")
	if outgoing != null:
		outgoing.queue_free()
	outgoing = current
	if outgoing != null and outgoing.finished_exit():
		outgoing.queue_free()
		outgoing = null
	current = _build_cut(i)
	stage.add_child(current)
	if outgoing != null:
		stage.move_child(outgoing, stage.get_child_count() - 1)   # 퇴장 컷이 위에서 덮으며 사라진다
	caption.text = SLIDES[i][1]
	caption.visible_characters = 0
	caption_panel.modulate.a = 0.0
	pager.text = "%d / %d" % [i + 1, SLIDES.size()]
	shown_captions.append(SLIDES[i][1])
	current.evaluate(0.0)


func _process(delta: float) -> void:
	if outgoing != null:
		outgoing.evaluate(outgoing.t + delta)
		if outgoing.finished_exit():
			outgoing.queue_free()
			outgoing = null
	if not active or current == null:
		return
	current.evaluate(current.t + delta)
	_update_caption(current.t)
	if current.t >= current.dur:
		next()


## 자막: 1행은 line_at[0]부터, 2행은 line_at[1]부터 한 글자씩. 컷이 끝나면(dur) 패널이 사라진다.
func _update_caption(at: float) -> void:
	var lines := caption.text.split("\n")
	var n1 := lines[0].length()
	var n2 := lines[1].length() if lines.size() > 1 else 0
	var t1: float = current.line_at[0]
	var t2: float = current.line_at[1]
	var vis := 0
	if at >= t1:
		vis = mini(n1, int((at - t1) / TYPE_SPEED))
	if n2 > 0 and at >= t2:
		vis = n1 + 1 + mini(n2, int((at - t2) / TYPE_SPEED))
	caption.visible_characters = vis
	var target: float = 1.0 if at >= t1 and at < current.dur else 0.0
	caption_panel.modulate.a = move_toward(caption_panel.modulate.a, target, 1.0 / FADE * get_process_delta_time())


func next() -> void:
	if not active or _finishing:
		return
	if current != null and current.t < current.dur:
		current.t = current.dur   # 퇴장 전환을 즉시 시작
	if index + 1 >= SLIDES.size():
		_finish(false)
	else:
		_start_cut(index + 1)


func skip() -> void:
	if active:
		_finish(true)


func _finish(skipped: bool) -> void:
	if _finishing:
		return
	_finishing = true
	active = false
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var tw := create_tween().set_parallel(true)
	tw.tween_property(stage, "modulate:a", 0.0, 0.35 if skipped else 0.6)
	tw.tween_property(caption_panel, "modulate:a", 0.0, 0.25)
	skip_btn.visible = false
	pager.visible = false
	tw.chain().tween_callback(func():
		root.mouse_filter = Control.MOUSE_FILTER_IGNORE
		finished.emit(skipped))


## 검은 막까지 걷고 숨긴다(새벽 연출이 따로 막을 걷을 때는 부르지 않아도 된다).
func dismiss() -> void:
	root.visible = false


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	var k := event as InputEventKey
	if k != null and k.pressed and not k.echo:
		if k.keycode == KEY_ESCAPE:
			skip()
		elif k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
			next()
		get_viewport().set_input_as_handled()


func _on_click(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if active and mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
		next()
		root.accept_event()
