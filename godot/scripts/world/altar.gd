extends Node3D
## 마녀의 제단(볼륨 확장 E2): 달빛 돌 제단 랜드마크 한가운데. 상태는 ChapterDirector가 가진다.
## 잠김(문양 없음) → 해금(바닥에 보랏빛 문양) → 복구(나무 제단·촛불 셋). 표시 전용 + 클릭 요청 처리.
## 클릭하면 마녀가 다가가고, ALTAR_USE_RANGE 안에 들어오면 제단 창이 열린다.

const Cfg := preload("res://scripts/config.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const SessionScript := preload("res://scripts/game/game_session.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")
const Fx := preload("res://scripts/visual/fx.gd")

const C_GLYPH := Color(0.7, 0.45, 1.0)
const C_CANDLE := Color(1.0, 0.78, 0.45)

var game
var requested := false
var _glyph: Node3D
var _table: Node3D
var _flames: Array = []
var _t := 0.0


func _ready() -> void:
	name = "Altar"
	add_to_group("altar")
	_glyph = B.node(self, Vector3(0, 0.06, 0), Vector3.ZERO, "Glyph")
	var gm := Mats.unshaded(Color(C_GLYPH, 0.75), true, true)
	B.torus(_glyph, 1.25, 1.35, Vector3.ZERO, gm)
	for i in 5:
		var a := TAU * i / 5.0
		B.box(_glyph, Vector3(0.06, 0.02, 1.1), Vector3(sin(a), 0, cos(a)) * 0.6, gm, Vector3(0, a, 0))
	_table = B.node(self, Vector3.ZERO, Vector3.ZERO, "Table")
	var wood := Mats.solid(Color("5a4031"), {"noise_amount": 0.08, "rim_strength": 0.25})
	var cloth := Mats.solid(Color("4a2f6a"), {"rim_strength": 0.3, "rim_color": C_GLYPH})
	B.box(_table, Vector3(1.2, 0.12, 0.7), Vector3(0, 0.62, 0), wood)
	for x: float in [-0.5, 0.5]:
		for z: float in [-0.25, 0.25]:
			B.box(_table, Vector3(0.1, 0.6, 0.1), Vector3(x, 0.3, z), wood)
	B.box(_table, Vector3(0.5, 0.02, 0.72), Vector3(0, 0.69, 0), cloth)
	for x: float in [-0.4, 0.0, 0.4]:
		B.cyl(_table, 0.04, 0.04, 0.22, Vector3(x, 0.8, -0.15), Mats.solid(Color("efe6d2")), 6)
		var fl := B.sphere(_table, 0.035, Vector3(x, 0.95, -0.15), Mats.glow(C_CANDLE, 6.0), Vector3(1, 1.6, 1), 6, 3)
		_flames.append(fl)
	B.omni(_table, Vector3(0, 1.2, 0), C_CANDLE, 1.4, 4.0)
	if game.get("chapter") != null and game.chapter != null:
		game.chapter.altar_changed.connect(_sync)
	_sync()


func _sync() -> void:
	var ch = game.chapter
	_glyph.visible = ch.altar_unlocked
	_table.visible = ch.altar_restored


func screen_hit(cam: Camera3D, mp: Vector2) -> bool:
	if cam.is_position_behind(global_position):
		return false
	return cam.unproject_position(global_position + Vector3(0, 0.6, 0)).distance_to(mp) < 70.0


## 클릭: 아직 해금 전이면 안내만. 아니면 마녀가 다가가고 도착하면 창이 열린다.
func request() -> void:
	var ch = game.chapter
	if not ch.altar_unlocked:
		game.toast("달빛 돌 제단 — " + ch.restore_block_reason(), Color(0.8, 0.8, 0.95))
		return
	requested = true
	if ch.player_near_altar():
		_open()
		return
	var to: Vector3 = game.player.global_position - global_position
	to.y = 0.0
	var dest := global_position + to.normalized() * 1.8
	var nav: Vector3 = NavUtil.ground_or_near(get_world_3d().navigation_map, dest)
	game.player.set_destination(nav)
	game.world.show_click_marker(nav)


func _open() -> void:
	requested = false
	if game.get("altar_ui") != null and game.altar_ui != null:
		game.altar_ui.open()


func _process(delta: float) -> void:
	_t += delta
	if _glyph.visible:
		_glyph.rotation.y += delta * 0.2
	for i in _flames.size():
		_flames[i].scale = Vector3(1, 1.6, 1) * (1.0 + sin(_t * 11.0 + i * 2.0) * 0.12)
	if requested:
		if game.session.state != SessionScript.State.PREP or game.get_tree().paused:
			requested = false
		elif game.chapter.player_near_altar():
			_open()
