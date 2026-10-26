extends Node3D
## 카드로 세우는 시설(종족 카드 v1, docs/race-cards-v01.md): 돌 성벽 기초 · 갱도 버팀목 · 뼈 방책.
## 고물 방책(junk_barricade.gd)과 같이 적이 노리는 "allies" 그룹에 들어 가까운 적이 산장보다 먼저 두드린다(길은 막지 않음).
## 부서질 때까지 남는다. 외형은 원시 도형 블록아웃(사용자 결정 2026-10-19).
## 돌 속의 노래가 울리는 동안에는 피해를 받지 않는다(game.race_cards.facility_shielded()).

const Data := preload("res://scripts/game/race_card_data.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")

const SPECS := {
	"stone_wall": {"hp": Data.WALL_HP, "name": "돌 성벽", "hp_offset": 1.7},
	"mine_prop": {"hp": Data.PROP_HP, "name": "갱도 버팀목", "hp_offset": 2.3},
	"bone_barricade": {"hp": Data.BONE_BARRICADE_HP, "name": "뼈 방책", "hp_offset": 1.5},
	"fire_brazier": {"hp": 160.0, "name": "불의 정령 화로", "hp_offset": 1.9},
	"log_wall": {"hp": 60.0, "name": "통나무 벽", "hp_offset": 1.3, "width": 3.0},   # 용병 키트(scripts/game/merc_kit.gd): 토르빈
	"timber_wall": {"hp": 200.0, "name": "갱목 방벽", "hp_offset": 1.6, "width": 5.0},   # 토르그림
	"junk_wall": {"hp": 40.0, "name": "급조 방책", "hp_offset": 1.1, "width": 2.0},   # 러스크   # 전설 카드 v1(docs/legend-cards-v01.md). 불덩이는 legend_cards.gd
}

var game
var kind := "stone_wall"
var job := "stone_wall"
var person := ""
var dead := false
var hidden := false
var on_tower := false
var hp := 100.0
var max_hp := 100.0
var hp_offset := 1.5
var carry: Dictionary = {}
var gear: Dictionary = {}
var foe_radius := 0.7
var visual: Node3D


func setup(g, facility: String, pos: Vector3) -> void:
	game = g
	kind = facility
	job = facility
	position = pos
	rotation.y = atan2(pos.x, pos.z)  # 산장(원점)을 등지고 바깥을 향한다
	max_hp = float(SPECS[facility]["hp"])
	if g != null and g.get("merc_kit") != null:
		max_hp *= g.merc_kit.facility_hp_mult(facility)  # 토르그림·드워프 둘
	hp = max_hp
	hp_offset = float(SPECS[facility]["hp_offset"])
	foe_radius = 1.0 if facility in ["stone_wall", "log_wall", "timber_wall", "junk_wall"] else 0.6


func _ready() -> void:
	visual = Node3D.new()
	add_child(visual)
	match kind:
		"stone_wall":
			_build_wall()
		"mine_prop":
			_build_prop()
		"bone_barricade":
			_build_bones()
		"fire_brazier":
			_build_brazier()
		"log_wall", "timber_wall", "junk_wall":
			_build_logs(float(SPECS[kind]["width"]), 2 if kind == "junk_wall" else 3)
	add_to_group("allies")
	add_to_group("show_hp")
	add_to_group("card_facilities")
	Fx.summon(global_position, Color(0.8, 0.8, 0.85) if kind != "bone_barricade" else Color(0.75, 0.7, 0.95))
	Sfx.play_or(self, kind + "_build", "timber_stack")


## 돌 성벽: 다듬은 돌 블록을 두 단으로 쌓고 위에 갓돌
func _build_wall() -> void:
	var stone := Mats.solid(Color(0.58, 0.58, 0.6))
	var stone2 := Mats.solid(Color(0.5, 0.5, 0.53))
	var cap := Mats.solid(Color(0.66, 0.66, 0.68))
	for row in 3:
		var n := 4 if row % 2 == 0 else 3
		for i in n:
			var w := 0.52
			var x := (i - (n - 1) * 0.5) * (w + 0.04)
			B.bevel_box(visual, Vector3(w, 0.36, 0.5), Vector3(x, 0.19 + row * 0.38, 0), stone if (i + row) % 2 == 0 else stone2, 0.05)
	B.bevel_box(visual, Vector3(2.3, 0.14, 0.62), Vector3(0, 1.22, 0), cap, 0.04)
	foe_radius = 1.1


## 갱도 버팀목: 기둥 둘 + 들보 + 대각 버팀. 드워프 룬 하나가 희미하게 빛난다
func _build_prop() -> void:
	var wood := Mats.solid(Color(0.46, 0.33, 0.2))
	var dark := Mats.solid(Color(0.34, 0.25, 0.16))
	var iron := Mats.solid(Color(0.42, 0.42, 0.44))
	for x in [-0.55, 0.55]:
		B.cyl(visual, 0.11, 0.13, 1.9, Vector3(x, 0.95, 0), wood, 8)
		B.box(visual, Vector3(0.3, 0.08, 0.3), Vector3(x, 0.04, 0), iron)
	B.box(visual, Vector3(1.5, 0.2, 0.24), Vector3(0, 1.95, 0), dark)
	B.box(visual, Vector3(0.1, 0.9, 0.1), Vector3(-0.28, 1.45, 0), wood, Vector3(0, 0, deg_to_rad(40)))
	B.box(visual, Vector3(0.1, 0.9, 0.1), Vector3(0.28, 1.45, 0), wood, Vector3(0, 0, deg_to_rad(-40)))
	B.box(visual, Vector3(0.16, 0.16, 0.02), Vector3(0, 1.95, 0.13), Mats.unshaded(Color(1.0, 0.65, 0.35)))


## 뼈 방책: 갈비뼈처럼 휜 뼈 말뚝 줄과 해골 하나
func _build_bones() -> void:
	var bone := Mats.solid(Color(0.86, 0.84, 0.74))
	var dark := Mats.solid(Color(0.35, 0.32, 0.3))
	B.box(visual, Vector3(1.8, 0.12, 0.3), Vector3(0, 0.08, 0), dark)
	for i in 7:
		var x := -0.8 + i * 0.27
		var h := 0.75 + 0.18 * float(i % 3)
		B.cyl(visual, 0.035, 0.06, h, Vector3(x, h * 0.5, 0), bone, 6, Vector3(deg_to_rad(-18), 0, deg_to_rad(randf_range(-8, 8))))
	B.box(visual, Vector3(1.7, 0.06, 0.06), Vector3(0, 0.55, 0.04), bone)
	B.sphere(visual, 0.14, Vector3(0.1, 1.08, 0.12), bone)
	B.sphere(visual, 0.03, Vector3(0.05, 1.1, 0.25), Mats.unshaded(Color(0.65, 0.55, 1.0)))
	B.sphere(visual, 0.03, Vector3(0.15, 1.1, 0.25), Mats.unshaded(Color(0.65, 0.55, 1.0)))


## 통나무 벽: 너비 3m, 통나무 세 단을 눕혀 쌓고 양 끝을 말뚝으로 받친다
func _build_logs(width := 3.0, rows := 3) -> void:
	var wood := Mats.solid(Color(0.47, 0.32, 0.2) if kind != "junk_wall" else Color(0.42, 0.36, 0.3))
	var end := Mats.solid(Color(0.72, 0.58, 0.4))
	for i in rows:
		B.cyl(visual, 0.2, 0.2, width, Vector3(0, 0.2 + i * 0.36, 0), wood, 8, Vector3(0, 0, PI * 0.5))
	for x in [-width * 0.48, width * 0.48]:
		B.cyl(visual, 0.09, 0.11, 0.5 + rows * 0.3, Vector3(x, 0.25 + rows * 0.15, 0.22), end, 6)
	if kind == "junk_wall":
		for x in [-0.6, 0.0, 0.6]:
			B.cyl(visual, 0.18, 0.18, 0.04, Vector3(x, 0.62, 0.24), Mats.solid(Color(0.75, 0.75, 0.78)), 10, Vector3(PI * 0.5, 0, 0))


## 불의 정령 화로: 세 다리 무쇠 화로 위 돌 사발, 그 안에서 일렁이는 불꽃 정령(두 눈)
func _build_brazier() -> void:
	var iron := Mats.solid(Color(0.24, 0.22, 0.22))
	var stone := Mats.solid(Color(0.52, 0.48, 0.45))
	for i in 3:
		var a := TAU * i / 3.0
		B.cyl(visual, 0.05, 0.07, 0.75, Vector3(cos(a) * 0.38, 0.36, sin(a) * 0.38), iron, 6, Vector3(sin(a) * 0.25, 0, -cos(a) * 0.25))
	B.cyl(visual, 0.62, 0.4, 0.38, Vector3(0, 0.88, 0), stone, 10)
	B.torus(visual, 0.56, 0.68, Vector3(0, 1.06, 0), iron)
	var spirit := B.node(visual, Vector3(0, 1.3, 0), Vector3.ZERO, "Spirit")
	B.sphere(spirit, 0.36, Vector3.ZERO, Mats.glow(Color(1.0, 0.55, 0.15), 5.0), Vector3(1.0, 1.4, 1.0), 10, 6)
	B.sphere(spirit, 0.22, Vector3(0, 0.12, 0), Mats.glow(Color(1.0, 0.88, 0.45), 7.0), Vector3(1.0, 1.5, 1.0), 8, 5)
	for x in [-0.11, 0.11]:
		B.sphere(spirit, 0.05, Vector3(x, 0.12, 0.3), Mats.unshaded(Color(1.0, 1.0, 0.85)))
	B.omni(visual, Vector3(0, 1.5, 0), Color(1.0, 0.55, 0.2), 2.2, 6.0, false, 1.2)
	var tw := spirit.create_tween().set_loops()
	tw.tween_property(spirit, "scale", Vector3(1.08, 1.15, 1.08), 0.35).set_trans(Tween.TRANS_SINE)
	tw.tween_property(spirit, "scale", Vector3(0.94, 0.9, 0.94), 0.4).set_trans(Tween.TRANS_SINE)
	foe_radius = 0.75


func display_name() -> String:
	return str(SPECS[kind]["name"])


func short_status() -> String:
	return ""


func status_text() -> String:
	return "%s %d/%d" % [display_name(), int(ceil(hp)), int(max_hp)]


func take_damage(amount: float) -> void:
	if dead:
		return
	if game != null and game.get("race_cards") != null and game.race_cards.facility_shielded():
		Fx.float_text(get_parent(), global_position + Vector3(0, hp_offset, 0), "막음", Color(0.85, 0.9, 1.0))
		return
	hp = maxf(hp - amount, 0.0)
	Fx.flash(visual)
	if kind == "bone_barricade":
		Fx.poof(global_position + Vector3(0, 0.6, 0), Color(0.85, 0.82, 0.75), 0.4)
	else:
		Fx.splinters(global_position + Vector3(0, 0.8, 0))
	Fx.damage_number(get_parent(), global_position + Vector3(0, hp_offset, 0), amount, Color(1.0, 0.75, 0.5))
	if hp <= 0.0:
		collapse(true)


func repair(amount: float) -> float:
	if dead:
		return 0.0
	var actual := minf(amount, max_hp - hp)
	hp += actual
	if actual > 0.0:
		Fx.heal(global_position + Vector3(0, 1.0, 0))
	return actual


## 무너짐. broken=true 면 적에게 부서진 것(갱도 버팀목은 근처 적을 덮친다).
func collapse(broken := false) -> void:
	if dead:
		return
	dead = true
	if broken and game != null and game.get("merc_kit") != null:
		game.merc_kit.on_facility_broken(self)  # 모가 사과의 의식
	remove_from_group("allies")
	remove_from_group("show_hp")
	remove_from_group("card_facilities")
	if game != null and game.get("race_cards") != null:
		game.race_cards.on_facility_collapsed(self, broken)
	Fx.splinters(global_position + Vector3(0, 0.6, 0))
	Sfx.play_or(self, kind + "_break", "goblin_barricade_break")
	Fx.vanish(self, Color(0.6, 0.55, 0.5, 0.8), 0.5)
