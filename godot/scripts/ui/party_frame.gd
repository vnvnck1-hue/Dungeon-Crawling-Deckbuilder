extends Control
## 용병 초상 메달(파티 프레임) — docs/equipment-and-party-frames-v01.md.
## 고용된 용병마다 초상을 둥근 테로 감싸 메인 화면 오른쪽 가장자리에 세로로 늘어놓는다(초상 메달, 사용자 확정 2026-10-19).
## 둥근 초상의 테두리가 체력 고리, 아래 이름표, 장비는 고리 아래 점 3개. 자세한 정보는 올렸을 때 왼쪽으로 뜬다.
## 직업 배지는 메달 왼쪽에 픽토그램(assets/ui/jobs/<job>.png, 없으면 글자)으로. 마녀의 장비 3칸은 상태판 오른쪽에 붙는다.
## 조작: 초상·칸 위에 올리면 설명. 채워진 장비 칸을 누르면 벗겨 손패로. 장비·스튜 카드를 초상 위로 끌어 놓아도 된다(CardUseResolver.frame_holder_at).
## 게임 상태는 갖지 않는다 — 매 프레임 contracts.allies·player·equipment를 읽어 그린다.

const Cfg := preload("res://scripts/config.gd")
const MoonLayout := preload("res://scripts/ui/moon/moon_layout.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")
const Races := preload("res://scripts/game/races.gd")
const EquipmentScript := preload("res://scripts/game/equipment.gd")

## 디자인 px(1600×800 캔버스, MoonLayout 기준)
const MEDAL_X := 1538.0                      # 오른쪽 위 앵커: 메달 중심 x
const MEDAL_TOP := 110.0                     # 첫 메달 바깥 테 위 끝 y(일시 정지 버튼 아래)
const MEDAL_BOTTOM := 676.0                  # 마지막 이름표 아래 끝 한계(산장 관리 버튼 위, 아래 앵커)
const MEDAL_R := 29.0
## 한 칸 높이 = 바깥 테 지름(2×(R+9)) + 장비 점이 테 밖으로 나온 만큼(7) + 틈(4) + 이름표(18) + 다음 메달과의 틈(9)
const MEDAL_STEP := 114.0
const JOB_ICON_DIR := "res://assets/ui/jobs/"
const MEDAL_MAX := 5
const WITCH_GEAR_ORIGIN := Vector2(336, 44)  # 마녀 장비 3칸(상태판 오른쪽)
const SLOT_PX := 26.0

const JOB_COLORS := {"lumberjack": Color(1.0, 0.78, 0.4), "hunter": Color(0.55, 0.92, 0.7),
	"warrior": Color(1.0, 0.52, 0.45), "gatherer": Color(0.78, 0.72, 1.0)}
const JOB_GLYPH := {"lumberjack": "벌", "hunter": "사", "warrior": "전", "gatherer": "채"}
const C_HP := Color(0.52, 0.9, 0.55)
const C_HP_LOW := Color(0.96, 0.4, 0.42)
const C_FRAME := Color(0.86, 0.69, 0.4)       # 금빛 테
const C_MOMENTUM := Color(1.0, 0.86, 0.2)     # 기세(밝은 금빛, 용병 키트 v04) — 금빛 테보다 밝고 진하게
const C_MANA := Color(0.45, 0.7, 1.0)         # 마력(푸른빛)
const C_FRAME_DARK := Color(0.33, 0.21, 0.12)

var game
var _hits: Array = []        # 이번 프레임의 클릭·드롭 영역 [{rect, holder, slot, part(medal·badge·tag, 없으면 마녀 칸)}]
var _hover: Dictionary = {}
var _portraits: Dictionary = {}   # person -> {tex, uv: Rect2}
var _font: Font
var hover_override := Vector2(-1, -1)   # 캡처·검증용: 마우스 대신 이 지점을 올린 것으로 본다
var last_tooltip: Array = []            # 검증용: 이번 프레임에 띄운 툴팁 줄 [text, color, size]
var shown_count := 0                    # 이번 프레임에 메달로 그린 용병 수(나머지는 "+N" → 용병 관리 창)


func _ready() -> void:
	name = "PartyFrame"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	_hover = _hit(_pointer())
	queue_redraw()


func _pointer() -> Vector2:
	return hover_override if hover_override.x >= 0.0 else get_viewport().get_mouse_position()


## 화면 지점 아래의 착용자(마녀·용병). 카드 드롭 대상 판정용. 없으면 null.
func holder_at(sp: Vector2):
	var h := _hit(sp)
	return h.get("holder") if not h.is_empty() else null


func _hit(sp: Vector2) -> Dictionary:
	# 장비 칸이 초상보다 위에 있으므로 칸부터 본다
	for h in _hits:
		if h["slot"] != "" and (h["rect"] as Rect2).has_point(sp):
			return h
	for h in _hits:
		if h["slot"] == "" and (h["rect"] as Rect2).has_point(sp):
			return h
	return {}


func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT or not is_visible_in_tree():
		return
	var hand = game.hud.card_hand if game.get("hud") != null and game.hud != null else null
	if hand != null and hand.drag_uid != -1:
		return
	var h := _hit(mb.position)
	if h.get("part", "") == "more":
		game.hud.open_merc_panel()   # 접힌 "+N" → 용병 관리 창(전원 보기)
		get_viewport().set_input_as_handled()
		return
	if h.is_empty() or h["slot"] == "" or not is_instance_valid(h["holder"]):
		return
	if not game.equipment.equipped(h["holder"], h["slot"]).is_empty():
		game.equipment.unequip(h["holder"], h["slot"])
		game.sounds.play_or("unequip", "card_cancel")
		get_viewport().set_input_as_handled()


func mercs() -> Array:
	if game == null or game.get("contracts") == null or game.contracts == null:
		return []
	return game.contracts.allies.filter(func(a): return is_instance_valid(a) and not a.dead and a.kind == "merc")


# ───────────────────────── 그리기 ─────────────────────────

func _draw() -> void:
	_hits.clear()
	if game == null or game.get("session") == null or game.session.is_over():
		return
	_font = get_theme_default_font()
	var view := size
	var s := MoonLayout.ui_scale(view)
	_draw_witch_gear(view, s)
	_draw_medallions(mercs(), view, s)
	_draw_mana(view, s)
	_draw_tooltip(view, s)


func _drag_target():
	var hand = game.hud.card_hand if game.get("hud") != null and game.hud != null else null
	if hand == null or hand.drag_uid == -1 or not hand.plan.get("ok", false):
		return null
	var t = hand.plan.get("holder", hand.plan.get("ally"))
	return t


## 마녀 장비 3칸: 상태판 오른쪽 위에 세로로 작은 칸 셋.
func _draw_witch_gear(view: Vector2, s: float) -> void:
	var p = game.player
	if p == null or p.dead:
		return
	var o := MoonLayout.to_view(WITCH_GEAR_ORIGIN, Vector2(0, 0), view)
	var px := SLOT_PX * s
	var bg := Rect2(o - Vector2(4, 4) * s, Vector2(px * 3 + 8 * s + 8 * s, px + 8 * s))
	draw_style_box(MoonSkin.flat_shared(Color(MoonSkin.INK, 0.82), Color(MoonSkin.CREAM, 0.55), int(8 * s), 0, 1), bg)
	if _drag_target() == p:
		draw_rect(bg.grow(2 * s), Color(MoonSkin.GOOD, 0.9), false, 2.0 * s)
	_hits.append({"rect": bg, "holder": p, "slot": ""})
	for i in Cfg.EQUIP_SLOTS.size():
		var r := Rect2(o + Vector2(i * (px + 4 * s), 0), Vector2(px, px))
		_draw_slot(r, p, Cfg.EQUIP_SLOTS[i], s)


# ── 초상 메달(오른쪽 세로 줄) ──

func _draw_medallions(list: Array, view: Vector2, s: float) -> void:
	if list.is_empty():
		return
	var r := MEDAL_R * s
	var top := MoonLayout.to_view(Vector2(MEDAL_X, MEDAL_TOP), Vector2(1, 0), view)
	var bottom := MoonLayout.to_view(Vector2(MEDAL_X, MEDAL_BOTTOM), Vector2(1, 1), view).y
	var step := MEDAL_STEP * s
	var fit := maxi(1, int(floor((bottom - top.y + 4 * s) / step)))
	var shown := mini(list.size(), mini(MEDAL_MAX, fit))
	if list.size() > shown:
		shown = maxi(shown - 1, 0)   # 마지막 자리는 "+N" 표시
	shown_count = shown
	for i in shown:
		_draw_medal(list[i], Vector2(top.x, top.y + r + 9 * s + i * step), r, s)
	if list.size() > shown:
		var c := Vector2(top.x, top.y + 22 * s + shown * step)
		var hot: bool = _hover.get("part", "") == "more"
		draw_circle(c, 16 * s, Color(MoonSkin.INK, 0.85) if not hot else Color(MoonSkin.INK, 0.98))
		draw_arc(c, 16 * s, 0, TAU, 32, Color(MoonSkin.CREAM, 0.6) if not hot else C_FRAME, (1.5 if not hot else 2.5) * s, true)
		_text_c("+%d" % (list.size() - shown), c + Vector2(0, 5 * s), 13 * s, MoonSkin.CREAM)
		# 누르면 용병 관리 창(hud.open_merc_panel). holder 가 없어 장비 드롭 대상은 되지 않는다
		_hits.append({"rect": Rect2(c - Vector2(18, 18) * s, Vector2(36, 36) * s), "holder": null, "slot": "", "part": "more"})


func _draw_medal(a, c: Vector2, r: float, s: float) -> void:
	var job_col: Color = JOB_COLORS.get(a.job, MoonSkin.CREAM)
	var dim: bool = a.hidden
	var hovered: bool = _hover.get("holder") == a
	var target: bool = _drag_target() == a
	# 바깥 받침(어두운 원) + 체력 고리 트랙
	draw_circle(c, r + 9 * s, Color(MoonSkin.INK, 0.88))
	var ring_r := r + 5 * s
	draw_arc(c, ring_r, 0, TAU, 56, Color(MoonSkin.TRACK, 1.0), 5.5 * s, true)
	var frac := clampf(a.hp / a.max_hp, 0.0, 1.0)
	var hp_col := C_HP.lerp(C_HP_LOW, clampf((0.6 - frac) / 0.4, 0.0, 1.0))
	if frac > 0.0:
		# 12시 방향에서 시계 방향으로 찬다
		draw_arc(c, ring_r, -PI * 0.5, -PI * 0.5 + TAU * frac, maxi(6, int(56 * frac)), hp_col, 5.5 * s, true)
	_draw_portrait(a, c, r, s, dim)
	draw_arc(c, r, 0, TAU, 48, C_FRAME, 2.0 * s, true)
	_draw_momentum(a, c, r, s)
	draw_arc(c, r + 9 * s, 0, TAU, 56, Color(job_col, 0.95) if not target else MoonSkin.GOOD, (2.0 if not target else 3.0) * s, true)
	if hovered:
		draw_arc(c, r + 11.5 * s, 0, TAU, 56, Color(MoonSkin.CREAM, 0.7), 1.5 * s, true)
	if a.hp < a.max_hp * 0.3 and not dim:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.008)
		draw_circle(c, r, Color(C_HP_LOW, 0.12 + 0.18 * pulse))
	# 직업 배지: 메달 왼쪽(바깥 테에 걸쳐서). 위아래로 튀어나오지 않아 이웃 메달·이름표와 겹치지 않는다
	var bc := c + Vector2(-(r + 9 * s), -4 * s)
	_draw_job_badge(a.job, bc, 11.0 * s, s)
	_hits.append({"rect": Rect2(bc - Vector2(12.5, 12.5) * s, Vector2(25, 25) * s), "holder": a, "slot": "", "part": "badge"})
	_hits.append({"rect": Rect2(c - Vector2(r + 9 * s, r + 9 * s), Vector2(r + 9 * s, r + 9 * s) * 2.0), "holder": a, "slot": "", "part": "medal"})
	# 장비 점 3개(고리 아래쪽)
	var pr := 7.0 * s
	for i in Cfg.EQUIP_SLOTS.size():
		var ang := PI * 0.5 + (i - 1) * 0.42
		var pc := c + Vector2(cos(ang), sin(ang)) * (r + 9 * s)
		var sr := Rect2(pc - Vector2(pr, pr), Vector2(pr, pr) * 2.0)
		_draw_slot(sr, a, Cfg.EQUIP_SLOTS[i], s, true)
	# 이름표(아래)
	var tag_w := maxf(_font.get_string_size(a.person, HORIZONTAL_ALIGNMENT_LEFT, -1, int(13 * s)).x + 16 * s, 2 * r)
	var tag := Rect2(Vector2(c.x - tag_w * 0.5, c.y + r + 20 * s), Vector2(tag_w, 18 * s))
	draw_style_box(MoonSkin.flat_shared(Color(MoonSkin.INK, 0.9), Color(job_col, 0.7), int(9 * s), 0, 1), tag)
	_hits.append({"rect": tag, "holder": a, "slot": "", "part": "tag"})
	_text_c(a.person, Vector2(c.x, tag.position.y + 13.5 * s), 13 * s, MoonSkin.CREAM if not dim else Color(MoonSkin.CREAM, 0.6))
	if dim:
		_text_c("산장 안", Vector2(c.x, c.y + 5 * s), 12 * s, MoonSkin.CREAM)


# ── 공용 부품 ──

## 기세 고리(용병 키트 v04): 초상 테 안쪽 금빛 고리. 가득 차면 깜빡인다(곧 고유 스킬).
func _draw_momentum(a, c: Vector2, r: float, s: float) -> void:
	var mk = game.get("merc_kit")
	if mk == null or not mk.enabled or not mk.KITS.has(a.person):
		return
	var f: float = clampf(mk.momentum_of(a) / mk.MOMENTUM_MAX, 0.0, 1.0)
	# 금빛 테(r) 안쪽에 어두운 홈을 파고 그 안을 채운다: 테와 섞이지 않게
	var rr := r - 6.0 * s
	draw_arc(c, rr, 0, TAU, 48, Color(0.08, 0.04, 0.12, 0.9), 6.0 * s, true)
	if f > 0.0:
		draw_arc(c, rr, -PI * 0.5, -PI * 0.5 + TAU * f, maxi(6, int(48 * f)), C_MOMENTUM, 4.0 * s, true)
	if f >= 1.0:
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.012)
		draw_arc(c, rr, 0, TAU, 48, Color(1.0, 1.0, 0.85, 0.3 + 0.6 * pulse), 6.0 * s, true)
	if mk.shielded(a):
		draw_arc(c, r + 13.5 * s, 0, TAU, 56, Color(C_MOMENTUM, 0.8), 2.0 * s, true)


## 마력(용병 키트 v04): 밤 전투 중에만, 메달 줄 왼쪽에 "마력 n / 10" 과 칸 10개.
func _draw_mana(view: Vector2, s: float) -> void:
	var mk = game.get("merc_kit")
	if mk == null or not mk.enabled or not mk._night():
		return
	var top := MoonLayout.to_view(Vector2(MEDAL_X, MEDAL_TOP), Vector2(1, 0), view)
	var right := top.x - (MEDAL_R + 22.0) * s
	var y := top.y + 12.0 * s
	var cells := int(mk.MANA_MAX)
	var cw := 9.0 * s
	var gap := 3.0 * s
	var x0 := right - cells * (cw + gap)
	draw_style_box(MoonSkin.flat_shared(Color(MoonSkin.INK, 0.8), Color(C_MANA, 0.6), int(6 * s), 0, 1), Rect2(x0 - 8 * s, y - 16 * s, right - x0 + 12 * s, 34 * s))
	_text("마력 %d / %d" % [int(floor(mk.mana)), cells], Vector2(x0, y - 2 * s), 13 * s, C_MANA, true)
	for i in cells:
		var rc := Rect2(x0 + i * (cw + gap), y + 4 * s, cw, 8 * s)
		var fill := clampf(mk.mana - i, 0.0, 1.0)
		draw_rect(rc, Color(MoonSkin.TRACK, 1.0))
		if fill > 0.0:
			draw_rect(Rect2(rc.position, Vector2(rc.size.x * fill, rc.size.y)), C_MANA if fill >= 1.0 else Color(C_MANA, 0.5))


func _draw_job_badge(job: String, c: Vector2, br: float, s: float) -> void:
	var col: Color = JOB_COLORS.get(job, MoonSkin.CREAM)
	draw_circle(c, br + 1.5 * s, C_FRAME_DARK)
	draw_circle(c, br, col.darkened(0.35))
	draw_arc(c, br, 0, TAU, 20, C_FRAME, 1.2 * s, true)
	var icon := job_icon(job)
	if icon != null:
		var k := br * 1.8   # 픽토그램 v02는 캔버스를 꽉 채우므로 원 안쪽 거의 전부를 쓴다
		draw_texture_rect(icon, Rect2(c - Vector2(k, k) * 0.5, Vector2(k, k)), false)
	else:
		_text_c(JOB_GLYPH.get(job, "?"), c + Vector2(0, br * 0.42), br * 1.15, MoonSkin.CREAM, true)


static var _job_icons: Dictionary = {}

## 직업 픽토그램(Codex 납품, docs/handoff/codex-job-pictograms-v01.md). 없으면 null → 글자 배지.
static func job_icon(job: String) -> Texture2D:
	if not _job_icons.has(job):
		var path: String = JOB_ICON_DIR + job + ".png"
		_job_icons[job] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _job_icons[job]


const PORTRAIT_SEGMENTS := 36
static var _circle := PackedVector2Array()

static func _unit_circle() -> PackedVector2Array:
	if _circle.is_empty():
		for i in PORTRAIT_SEGMENTS:
			var t := TAU * i / PORTRAIT_SEGMENTS
			_circle.append(Vector2(cos(t), sin(t)))
	return _circle


## 둥글게 오린 초상. 컷아웃 그림의 머리·어깨 부분을 원 안에 맞춘다.
func _draw_portrait(a, c: Vector2, r: float, s: float, dim: bool) -> void:
	draw_circle(c, r, Color(0.16, 0.11, 0.24))
	draw_circle(c + Vector2(0, -r * 0.25), r * 0.75, Color(0.24, 0.17, 0.34))
	var info := _portrait(a.person)
	if info.is_empty():
		return
	var uvs: PackedVector2Array = info["uvs"]
	var pts := PackedVector2Array()
	pts.resize(PORTRAIT_SEGMENTS)
	var circle := _unit_circle()
	for i in PORTRAIT_SEGMENTS:
		pts[i] = c + circle[i] * (r - 0.5 * s)
	var mod := Color(1, 1, 1) if not dim else Color(0.55, 0.55, 0.65)
	draw_colored_polygon(pts, mod, uvs, info["tex"])


func _portrait(person: String) -> Dictionary:
	if _portraits.has(person):
		return _portraits[person]
	var out := {}
	var path := ""
	for p in GuestProfiles.CATALOG:
		if p.get("person", "") == person:
			path = p.get("portrait", "")
			break
	if path == "":
		path = GuestProfiles.MERC_PORTRAIT
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		var uv := _face_uv(tex)
		var uvs := PackedVector2Array()
		for d in _unit_circle():
			uvs.append(uv.get_center() + d * uv.size * 0.5)
		out = {"tex": tex, "uv": uv, "uvs": uvs}
	_portraits[person] = out
	return out


## 컷아웃의 머리 위치 추정: 불투명 영역 위쪽 띠의 가로 무게중심을 머리 중심으로 보고, 위에서 26% 지점을 원 중심으로 삼는다.
static func _face_uv(tex: Texture2D) -> Rect2:
	var img := tex.get_image()
	if img == null:
		return Rect2(0.2, 0.0, 0.6, 0.6)
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var step := maxi(1, w / 96)
	var top := h
	var bottom := 0
	for y in range(0, h, step):
		for x in range(0, w, step):
			if img.get_pixel(x, y).a > 0.5:
				top = mini(top, y)
				bottom = maxi(bottom, y)
				break
	if top >= bottom:
		return Rect2(0.2, 0.0, 0.6, 0.6)
	var bh := float(bottom - top)
	var sx := 0.0
	var sn := 0.0
	for y in range(top + int(bh * 0.06), top + int(bh * 0.32), step):
		for x in range(0, w, step):
			if img.get_pixel(x, y).a > 0.5:
				sx += x
				sn += 1.0
	var cx := sx / sn if sn > 0.0 else w * 0.5
	var cy := top + bh * 0.26
	var side := bh * 0.56
	return Rect2((cx - side * 0.5) / w, (cy - side * 0.5) / h, side / w, side / h)


## 장비 칸: 비어 있으면 칸 모양 윤곽만, 채워지면 금빛 바탕 + 칸 그림. small = 메달의 점.
func _draw_slot(r: Rect2, holder, slot: String, s: float, small := false) -> void:
	var g: Dictionary = game.equipment.equipped(holder, slot)
	var filled := not g.is_empty()
	var hovered: bool = _hover.get("holder") == holder and _hover.get("slot") == slot
	var c := r.get_center()
	if small:
		var rr := r.size.x * 0.5
		draw_circle(c, rr + 1.0 * s, C_FRAME_DARK)
		draw_circle(c, rr, C_FRAME if filled else Color(MoonSkin.TRACK, 1.0))
		if hovered:
			draw_arc(c, rr + 2.0 * s, 0, TAU, 20, MoonSkin.CREAM, 1.5 * s, true)
		_draw_slot_glyph(slot, c, rr * 0.75, MoonSkin.INK if filled else Color(MoonSkin.LAVENDER, 0.7), s)
	else:
		var bg := Color(0.56, 0.4, 0.2) if filled else Color(MoonSkin.TRACK, 0.95)
		draw_style_box(MoonSkin.flat_shared(bg, C_FRAME if filled else Color(MoonSkin.CREAM, 0.35), int(5 * s), 0, 1), r)
		if hovered:
			draw_rect(r.grow(1.5 * s), MoonSkin.CREAM, false, 1.5 * s)
		_draw_slot_glyph(slot, c, r.size.x * 0.32, MoonSkin.CREAM if filled else Color(MoonSkin.LAVENDER, 0.55), s)
	_hits.append({"rect": r.grow(1.0 * s), "holder": holder, "slot": slot})


## 칸 그림(무기 = 칼, 방어구 = 방패, 장신구 = 고리 달린 부적). 장비 아이콘 원화가 나오기 전의 벡터 표시.
func _draw_slot_glyph(slot: String, c: Vector2, k: float, col: Color, s: float) -> void:
	var lw := maxf(1.2, 0.18 * k)
	match slot:
		"weapon":
			draw_line(c + Vector2(-k, k), c + Vector2(k * 0.8, -k * 0.8), col, lw * 1.4, true)
			draw_line(c + Vector2(-k * 0.65, k * 0.15), c + Vector2(-k * 0.15, k * 0.65), col, lw * 1.2, true)
		"armor":
			var pts := PackedVector2Array([c + Vector2(-k * 0.8, -k * 0.8), c + Vector2(k * 0.8, -k * 0.8),
				c + Vector2(k * 0.7, k * 0.1), c + Vector2(0, k), c + Vector2(-k * 0.7, k * 0.1), c + Vector2(-k * 0.8, -k * 0.8)])
			draw_polyline(pts, col, lw, true)
		_:
			draw_arc(c + Vector2(0, k * 0.25), k * 0.55, 0, TAU, 16, col, lw, true)
			draw_line(c + Vector2(-k * 0.5, -k), c + Vector2(0, -k * 0.3), col, lw * 0.8, true)
			draw_line(c + Vector2(k * 0.5, -k), c + Vector2(0, -k * 0.3), col, lw * 0.8, true)


## 올린 대상의 자세한 정보: 이름·직업·체력·상태·장비 목록. 장비 칸 위면 그 장비 설명.
func _draw_tooltip(view: Vector2, s: float) -> void:
	last_tooltip = []
	if _hover.is_empty():
		return
	var hand = game.hud.card_hand if game.get("hud") != null and game.hud != null else null
	if hand != null and hand.drag_uid != -1:
		return
	var h = _hover["holder"]
	var lines: Array = []   # [text, color, size]
	if _hover.get("part", "") == "more":
		lines.append(["용병 %d명 더" % (mercs().size() - shown_count), MoonSkin.CREAM, 15])
		lines.append(["클릭하면 용병 관리 창에서 전원 보기", MoonSkin.LAVENDER, 12])
	elif not is_instance_valid(h):
		return
	elif _hover["slot"] != "":
		var slot: String = _hover["slot"]
		var g: Dictionary = game.equipment.equipped(h, slot)
		lines.append([Cfg.EQUIP_SLOT_NAMES[slot] + " 칸", MoonSkin.LAVENDER, 12])
		if g.is_empty():
			lines.append(["비어 있음", MoonSkin.CREAM, 14])
			lines.append(["장비 카드를 끌어 놓아 장착", MoonSkin.LAVENDER, 12])
		else:
			lines.append([game.cards.def(g["id"]).get("name", g["id"]), MoonSkin.CREAM, 15])
			lines.append([EquipmentScript.effect_text(g["id"]), MoonSkin.GOOD, 13])
			lines.append(["클릭하면 벗겨 손패로", MoonSkin.LAVENDER, 12])
	else:
		if h == game.player:
			lines.append(["마녀의 장비", MoonSkin.CREAM, 15])
		else:
			lines.append([h.display_name(), MoonSkin.CREAM, 15])
			var race := GuestProfiles.race_of(h.person)
			lines.append(["종족 — " + Races.name_of(race), Races.accent(race), 13])
			lines.append(["체력 %d / %d" % [int(ceil(h.hp)), int(h.max_hp)], C_HP if h.hp >= h.max_hp * 0.3 else C_HP_LOW, 13])
			lines.append([h.status_text(), MoonSkin.LAVENDER, 12])
		for slot in Cfg.EQUIP_SLOTS:
			var g: Dictionary = game.equipment.equipped(h, slot)
			var t: String = Cfg.EQUIP_SLOT_NAMES[slot] + " — " + ("비어 있음" if g.is_empty() else "%s (%s)" % [game.cards.def(g["id"]).get("name", ""), EquipmentScript.effect_text(g["id"])])
			lines.append([t, MoonSkin.CREAM_DIM if g.is_empty() else MoonSkin.CREAM, 12])
	last_tooltip = lines
	var w := 0.0
	var hgt := 0.0
	for l in lines:
		w = maxf(w, _font.get_string_size(l[0], HORIZONTAL_ALIGNMENT_LEFT, -1, int(l[2] * s)).x)
		hgt += (l[2] + 6) * s
	var m := _pointer()
	var box := Rect2(m + Vector2(18, 14) * s, Vector2(w + 24 * s, hgt + 14 * s))
	if box.end.x > view.x - 8:
		box.position.x = m.x - 18 * s - box.size.x
	if box.end.y > view.y - 8:
		box.position.y = view.y - 8 - box.size.y
	draw_style_box(MoonSkin.flat_shared(Color(MoonSkin.INK, 0.96), Color(MoonSkin.CREAM, 0.8), int(10 * s), 0, 1), box)
	var y := box.position.y + 7 * s
	for l in lines:
		y += (l[2] + 2) * s
		_text(l[0], Vector2(box.position.x + 12 * s, y), l[2] * s, l[1], l[2] >= 15)
		y += 4 * s


func _text(t: String, at: Vector2, px: float, col: Color, bold := false) -> void:
	t = tr(t)   # 직접 그리는 글자는 auto translate 를 거치지 않는다
	var f: Font = MoonSkin.font(true) if bold else _font
	draw_string_outline(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px), maxi(2, int(px * 0.22)), Color(0.05, 0.02, 0.1, 0.85))
	draw_string(f, at, t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px), col)


func _text_c(t: String, at: Vector2, px: float, col: Color, bold := false) -> void:
	var f: Font = MoonSkin.font(true) if bold else _font
	var w := f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, int(px)).x
	_text(t, at - Vector2(w * 0.5, 0), px, col, bold)
