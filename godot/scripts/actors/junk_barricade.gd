extends Node3D
## 고물 방책(고블린 카드 v1): 목재 1로 즉시 세우는 허술한 방책. 체력이 낮고(BARRICADE_HP) BARRICADE_DAYS 일 뒤 새벽에 무너진다.
## 적이 노리는 "allies" 그룹에 들어 가까운 적이 산장보다 먼저 두드린다(길을 막지는 않는다 — 내비 메시를 바꾸지 않음).

const GoblinData := preload("res://scripts/game/goblin_data.gd")
const Fx := preload("res://scripts/visual/fx.gd")
const Sfx := preload("res://scripts/audio/sfx.gd")
const B := preload("res://scripts/visual/build.gd")
const Mats := preload("res://scripts/visual/mats.gd")

var game
var kind := "junk_barricade"
var job := "junk_barricade"
var person := ""
var dead := false
var hidden := false
var on_tower := false
var hp := GoblinData.BARRICADE_HP
var max_hp := GoblinData.BARRICADE_HP
var hp_offset := 1.2
var carry: Dictionary = {}
var gear: Dictionary = {}
var foe_radius := 0.5
var built_day := 1
var visual: Node3D


func _ready() -> void:
	visual = Node3D.new()
	add_child(visual)
	var wood := Mats.solid(Color(0.5, 0.36, 0.22))
	var wood2 := Mats.solid(Color(0.4, 0.3, 0.2))
	var tin := Mats.solid(Color(0.55, 0.55, 0.52))
	# 삐뚤빼뚤한 판자 다섯 장 + 가로대 둘 + 찌그러진 냄비 하나
	for i in 5:
		var x := -0.6 + i * 0.3
		B.box(visual, Vector3(0.22, 0.8 + 0.12 * (i % 3), 0.06), Vector3(x, 0.42, 0), wood if i % 2 == 0 else wood2, Vector3(0, 0, deg_to_rad(randf_range(-9, 9))))
	B.box(visual, Vector3(1.5, 0.08, 0.06), Vector3(0, 0.3, 0.05), wood2, Vector3(0, 0, deg_to_rad(4)))
	B.box(visual, Vector3(1.4, 0.08, 0.06), Vector3(0, 0.66, 0.05), wood2, Vector3(0, 0, deg_to_rad(-6)))
	B.cyl(visual, 0.13, 0.11, 0.12, Vector3(0.45, 0.9, 0.02), tin, 8, Vector3(deg_to_rad(20), 0, deg_to_rad(15)))
	add_to_group("allies")
	add_to_group("show_hp")
	add_to_group("junk_barricades")
	Fx.summon(global_position, Color(0.85, 0.7, 0.45))
	Sfx.play_or(self, "goblin_barricade", "timber_stack")


func display_name() -> String:
	return "고물 방책"


func short_status() -> String:
	return ""


func take_damage(amount: float) -> void:
	if dead:
		return
	if game != null and game.get("race_cards") != null and game.race_cards.facility_shielded():
		return  # 돌 속의 노래(종족 카드 v1): 시설이 피해를 받지 않는다
	hp = maxf(hp - amount, 0.0)
	Fx.flash(visual)
	Fx.splinters(global_position + Vector3(0, 0.6, 0))
	Fx.damage_number(get_parent(), global_position + Vector3(0, 1.4, 0), amount, Color(1.0, 0.75, 0.5))
	if hp <= 0.0:
		collapse()


func collapse() -> void:
	if dead:
		return
	dead = true
	remove_from_group("allies")
	remove_from_group("show_hp")
	remove_from_group("junk_barricades")
	Fx.splinters(global_position + Vector3(0, 0.5, 0))
	Sfx.play_or(self, "goblin_barricade_break", "timber_stack")
	Fx.vanish(self, Color(0.6, 0.45, 0.3, 0.8), 0.4)
