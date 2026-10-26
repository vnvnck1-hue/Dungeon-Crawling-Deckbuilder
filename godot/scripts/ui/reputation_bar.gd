extends CanvasLayer
## 산장의 소문(평판) 막대 — 사용자 결정(2026-10-19): 수치를 화면에 막대로 표시한다. docs/race-cards-v01.md §3.
## 가운데가 '보통'(0), 왼쪽으로 어두워질수록 음산·악명, 오른쪽으로 밝을수록 환대. 마우스를 올리면 구간 효과를 알려 준다.

const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const Rep := preload("res://scripts/game/reputation.gd")

const W := 220.0
const H := 10.0
const C_DARK := Color(0.45, 0.25, 0.65)
const C_LIGHT := Color(1.0, 0.85, 0.5)

var game
var root: Control
var label: Label
var track: ColorRect
var fill: ColorRect
var marks: Array = []


func _ready() -> void:
	name = "ReputationBar"
	layer = 5
	root = Control.new()
	root.name = "ReputationRoot"
	root.mouse_filter = Control.MOUSE_FILTER_PASS
	# 왼쪽 위 상태판·장비 칸(…~470px) 오른쪽, 가운데 시계 장식(735px~) 왼쪽의 빈자리
	root.position = Vector2(488, 46)
	root.size = Vector2(W, 34)
	add_child(root)
	label = Label.new()
	label.add_theme_font_override("font", MoonSkin.font(true))
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", MoonSkin.CREAM)
	label.add_theme_color_override("font_outline_color", Color(0.05, 0.02, 0.1))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(W, 18)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(label)
	track = ColorRect.new()
	track.color = Color(0.08, 0.05, 0.12, 0.8)
	track.position = Vector2(0, 19)
	track.size = Vector2(W, H)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(track)
	fill = ColorRect.new()
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(fill)
	# 구간 경계(음산·악명·환대)와 가운데
	for v in [Rep.INFAMY_AT, Rep.GLOOM_AT, 0, Rep.WELCOME_AT]:
		var m := ColorRect.new()
		m.color = Color(1, 1, 1, 0.55 if v == 0 else 0.3)
		m.size = Vector2(1, H + 4)
		m.position = Vector2(_x(v), 17)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(m)
		marks.append(m)
	root.tooltip_text = "산장의 소문\n환대(+%d 이상): 고용비 −%dG\n음산(%d 이하): 새벽에 검은 소문이 주머니에 섞임\n악명(%d 이하): 검은 소문 매일 · 죽음의 행진 해금\n제물 −15 · 순례자의 축복 +12 · 검은 소문 정화 +5" % [Rep.WELCOME_AT, Rep.WELCOME_HIRE_DISCOUNT, Rep.GLOOM_AT, Rep.INFAMY_AT]
	if game.get("reputation") != null:
		game.reputation.changed.connect(func(_v): refresh())
	refresh()


func _x(v: int) -> float:
	return (float(v - Rep.MIN) / float(Rep.MAX - Rep.MIN)) * W


func refresh() -> void:
	if game.get("reputation") == null:
		return
	var v: int = game.reputation.value
	var t: String = game.reputation.tier()
	label.text = "산장의 소문 · %s" % Rep.tier_name(t)
	var mid := _x(0)
	var at := _x(v)
	fill.position = Vector2(minf(mid, at), 19)
	fill.size = Vector2(maxf(absf(at - mid), 2.0), H)
	fill.color = C_DARK if v < 0 else C_LIGHT
	if v == 0:
		fill.color = Color(0.8, 0.78, 0.85)


func _process(_delta: float) -> void:
	# 타이틀·프롤로그 같은 첫 화면 연출 중에는 숨긴다(HUD가 보일 때만)
	var hud = game.get("hud")
	root.visible = hud == null or hud.get("visible") != false
