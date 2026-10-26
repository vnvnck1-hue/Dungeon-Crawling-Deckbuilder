extends VBoxContainer
## 용병 관리 창 — 오른쪽 초상 메달 줄이 꽉 차 "+N"으로 접힌 용병까지 전부 본다(사용자 요청 2026-10-24).
## 메달 줄의 "+N" 원을 누르면 열린다(hud.open_merc_panel). 창이 열린 동안은 다른 관리창처럼 시간이 멈춘다.
## 한 사람당 한 줄: 둥근 초상(체력 고리·직업 배지) · 이름·직업 · 종족 · 체력 · 지금 하는 일 · 장비 3칸.
## 게임 상태는 갖지 않는다 — 열려 있는 동안 party_frame.mercs()를 읽어 줄을 맞추고 수치만 갱신한다.

const Cfg := preload("res://scripts/config.gd")
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")
const Races := preload("res://scripts/game/races.gd")
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")
const PartyFrame := preload("res://scripts/ui/party_frame.gd")
const EquipmentScript := preload("res://scripts/game/equipment.gd")

var game
var hud
var count_label: Label
var list: VBoxContainer
var rows: Array = []      # [{ally, medal, hp, status, gear}]
var _key := ""


func _ready() -> void:
	name = "MercPanel"
	add_theme_constant_override("separation", 10)
	add_child(hud._title("용병 관리"))
	count_label = hud._label("", 14, MoonSkin.CREAM_DIM)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(count_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 420)
	add_child(scroll)
	list = VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	var close: Button = hud._button("닫기", 42)
	close.pressed.connect(hud.close_merc_panel)
	add_child(close)


func _process(_delta: float) -> void:
	if is_visible_in_tree():
		refresh()


## 인물 이름 → 카탈로그의 한 줄 소개("찢긴 귀의 늑대 수인 검사"). 없으면 빈 글자.
static func detail_of(person: String) -> String:
	for p in GuestProfiles.CATALOG:
		if p.get("person", "") == person:
			return str(p.get("detail", ""))
	return ""


## 툴팁·창 공용 종족 표기: "드워프", 카탈로그 밖 인물은 인간.
static func race_text(person: String) -> String:
	return Races.name_of(GuestProfiles.race_of(person))


func refresh() -> void:
	var mercs: Array = hud.party_frame.mercs()
	var key := ""
	for a in mercs:
		key += str(a.get_instance_id()) + ";"
	if key != _key:
		_key = key
		_rebuild(mercs)
	count_label.text = "활동 중인 용병 %d명 · 침상 %d개" % [mercs.size(), game.economy.bunk_capacity()]
	for r in rows:
		var a = r["ally"]
		if not is_instance_valid(a):
			continue
		r["hp"].text = "체력 %d / %d" % [int(ceil(a.hp)), int(a.max_hp)]
		r["hp"].add_theme_color_override("font_color", PartyFrame.C_HP if a.hp >= a.max_hp * 0.3 else PartyFrame.C_HP_LOW)
		r["status"].text = ("산장 안 · " if a.hidden else "") + a.status_text()
		var parts: Array = []
		for slot in Cfg.EQUIP_SLOTS:
			var g: Dictionary = game.equipment.equipped(a, slot)
			parts.append(Cfg.EQUIP_SLOT_NAMES[slot] + " " + ("—" if g.is_empty() else "%s (%s)" % [game.cards.def(g["id"]).get("name", ""), EquipmentScript.effect_text(g["id"])]))
		r["gear"].text = "  ·  ".join(parts)
		r["medal"].queue_redraw()


func _rebuild(mercs: Array) -> void:
	rows.clear()
	for n in list.get_children():
		n.queue_free()
	if mercs.is_empty():
		list.add_child(hud._label("활동 중인 용병이 없습니다. 계약 카드를 산장 앞에 끌어 놓아 용병을 세우세요.", 15, MoonSkin.CREAM))
		return
	for a in mercs:
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", MoonSkin.row_box())
		list.add_child(row)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		var medal := MercMedal.new()
		medal.ally = a
		medal.frame = hud.party_frame
		medal.custom_minimum_size = Vector2(84, 84)
		medal.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(medal)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation", 2)
		h.add_child(info)
		var head := HBoxContainer.new()
		head.add_theme_constant_override("separation", 10)
		info.add_child(head)
		var name_l: Label = hud._label(a.person, 19, MoonSkin.CREAM)
		name_l.add_theme_font_override("font", MoonSkin.font(true))
		head.add_child(name_l)
		head.add_child(hud._label(Cfg.JOB_NAMES.get(a.job, "용병"), 15, PartyFrame.JOB_COLORS.get(a.job, MoonSkin.CREAM)))
		var race := GuestProfiles.race_of(a.person)
		head.add_child(hud._label("종족 " + Races.name_of(race), 15, Races.accent(race)))
		var hp: Label = hud._label("", 14, PartyFrame.C_HP)
		hp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		head.add_child(hp)
		var detail := detail_of(a.person)
		if detail != "":
			info.add_child(hud._label(detail, 13, MoonSkin.CREAM_DIM))
		var status: Label = hud._label("", 13, MoonSkin.LAVENDER)
		info.add_child(status)
		var gear: Label = hud._label("", 12, MoonSkin.CREAM)
		gear.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.add_child(gear)
		rows.append({"ally": a, "medal": medal, "hp": hp, "status": status, "gear": gear})


## 창 안의 둥근 초상: 메달 줄과 같은 오림·체력 고리·직업 배지.
class MercMedal extends Control:
	var ally
	var frame   # PartyFrame — 초상 오림 정보(_portrait)를 빌린다

	func _draw() -> void:
		if not is_instance_valid(ally):
			return
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 9.0
		draw_circle(c, r + 8.0, Color(MoonSkin.INK, 0.9))
		draw_arc(c, r + 4.5, 0, TAU, 56, Color(MoonSkin.TRACK, 1.0), 5.0, true)
		var frac := clampf(ally.hp / ally.max_hp, 0.0, 1.0)
		if frac > 0.0:
			var col: Color = PartyFrame.C_HP.lerp(PartyFrame.C_HP_LOW, clampf((0.6 - frac) / 0.4, 0.0, 1.0))
			draw_arc(c, r + 4.5, -PI * 0.5, -PI * 0.5 + TAU * frac, maxi(6, int(56 * frac)), col, 5.0, true)
		draw_circle(c, r, Color(0.16, 0.11, 0.24))
		var info: Dictionary = frame._portrait(ally.person)
		if not info.is_empty():
			var pts := PackedVector2Array()
			for d in PartyFrame._unit_circle():
				pts.append(c + d * (r - 0.5))
			draw_colored_polygon(pts, Color(1, 1, 1) if not ally.hidden else Color(0.55, 0.55, 0.65), info["uvs"], info["tex"])
		draw_arc(c, r, 0, TAU, 48, PartyFrame.C_FRAME, 2.0, true)
		draw_arc(c, r + 8.0, 0, TAU, 56, Color(PartyFrame.JOB_COLORS.get(ally.job, MoonSkin.CREAM), 0.95), 2.0, true)
		# 직업 배지(왼쪽 아래)
		var bc := c + Vector2(-r * 0.78, r * 0.72)
		var br := 11.0
		draw_circle(bc, br + 1.5, PartyFrame.C_FRAME_DARK)
		draw_circle(bc, br, Color(PartyFrame.JOB_COLORS.get(ally.job, MoonSkin.CREAM)).darkened(0.35))
		draw_arc(bc, br, 0, TAU, 20, PartyFrame.C_FRAME, 1.2, true)
		var icon := PartyFrame.job_icon(ally.job)
		if icon != null:
			var k := br * 1.8
			draw_texture_rect(icon, Rect2(bc - Vector2(k, k) * 0.5, Vector2(k, k)), false)
