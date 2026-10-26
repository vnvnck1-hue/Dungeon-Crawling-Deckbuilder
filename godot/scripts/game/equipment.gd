extends Node
## Equipment: 마녀·용병의 장착 장비 v0(docs/equipment-and-party-frames-v01.md).
## 장비 카드를 마녀나 용병에게 끌어 놓으면 그 장비의 칸(무기·방어구·장신구)에 끼운다. 카드는 손패에서 빠져 활동 중(in_play)이 된다.
## 같은 칸에 이미 있던 장비는 손패로 돌아온다(가득 차면 주머니). 용병이 쓰러지거나 계약을 해지해도 장비는 손패로 돌아온다.
## 장비 상태는 착용자 노드의 gear {slot: {uid, id}} 에 두고, 수치 합산은 여기서 한다. 착용자는 stat()·damage_mult() 등으로 읽는다.

const Cfg := preload("res://scripts/config.gd")
const Fx := preload("res://scripts/visual/fx.gd")

signal changed

var game


func _ready() -> void:
	name = "Equipment"


func _process(delta: float) -> void:
	# 장신구 회복(마가목 부적 등): 살아 있는 착용자에게 초당 regen
	for h in holders():
		if h.get(&"gear") == null or h.gear.is_empty():
			continue   # 아무것도 안 낀 착용자는 stat 이 0
		var r := stat(h, "regen")
		if r > 0.0 and not h.dead and h.hp < h.max_hp:
			h.hp = minf(h.hp + r * delta, h.max_hp)


static func is_equipment(id: String) -> bool:
	return Cfg.EQUIPMENT.has(id)


static func slot_of(id: String) -> String:
	return str(Cfg.EQUIPMENT.get(id, {}).get("slot", ""))


## 장비를 끼울 수 있는 모든 착용자(마녀 + 살아 있는 용병).
func holders() -> Array:
	var out: Array = []
	if game.player != null and not game.player.dead:
		out.append(game.player)
	for a in game.get_tree().get_nodes_in_group("allies"):
		if not a.dead and a.kind == "merc":
			out.append(a)
	return out


func is_witch(holder) -> bool:
	return holder != null and holder == game.player


func holder_name(holder) -> String:
	return "마녀" if is_witch(holder) else holder.display_name()


## 이 착용자에게 끼울 수 없는 이유. 끼울 수 있으면 "".
func block_reason(holder, id: String) -> String:
	if not is_equipment(id):
		return "장비 카드가 아닙니다"
	if holder == null or holder.dead:
		return "장비를 끼울 대상이 없습니다"
	var who: String = Cfg.EQUIPMENT[id].get("who", "any")
	if who == "witch" and not is_witch(holder):
		return "마녀만 쓸 수 있는 장비입니다"
	if who == "merc" and is_witch(holder):
		return "용병만 쓸 수 있는 장비입니다"
	if not is_witch(holder) and holder.get("kind") != "merc":
		return "용병에게만 끼울 수 있습니다"
	if game.player != null and is_witch(holder) and game.player.wolf:
		return "늑대는 장비를 바꿀 수 없습니다"
	return ""


func equipped(holder, slot: String) -> Dictionary:
	if holder == null:
		return {}
	return holder.gear.get(slot, {})


## 착용자의 장비 수치 합(키: max_hp·damage·armor·speed·regen).
func stat(holder, key: String) -> float:
	if holder == null or holder.get("gear") == null:
		return 0.0
	var total := 0.0
	for slot in holder.gear:
		var id: String = holder.gear[slot]["id"]
		total += float(Cfg.EQUIPMENT.get(id, {}).get("stats", {}).get(key, 0.0))
	return total


func damage_mult(holder) -> float:
	var forged: float = game.legend.forge_mult(holder) if game != null and game.get("legend") != null else 1.0  # 광석으로 벼린 무기(docs/legend-cards-v01.md)
	return (1.0 + stat(holder, "damage")) * _race(func(rc): return rc.damage_mult(holder)) * forged


func speed_mult(holder) -> float:
	return (1.0 + stat(holder, "speed")) * _race(func(rc): return rc.speed_mult(holder))


## 종족 카드 v1 배율(docs/race-cards-v01.md — 밤 버프·영구 강화·장신구 효과). 모듈이 없으면 1.
func _race(f: Callable) -> float:
	var rc = game.get("race_cards") if game != null else null
	return float(f.call(rc)) if rc != null else 1.0


## 받는 피해 배율(1 - 감소율, 상한 Cfg.EQUIP_ARMOR_CAP).
func taken_mult(holder) -> float:
	var m := 1.0 - minf(stat(holder, "armor"), Cfg.EQUIP_ARMOR_CAP)
	# 고블린 장비(찌그러진 냄비 투구)처럼 맞을 때마다 닳는 방어. 이 함수는 피격 순간에만 불린다(ally·player take_damage)
	if game != null and game.get("goblin") != null:
		m *= game.goblin.on_hit_taken_mult(holder)
	m *= _race(func(rc): return rc.taken_mult(holder))
	return m


## 장비 한 점의 효과 한 줄(미리보기·툴팁).
static func effect_text(id: String) -> String:
	var st: Dictionary = Cfg.EQUIPMENT.get(id, {}).get("stats", {})
	var parts: Array = []
	if st.has("damage"):
		parts.append("피해 +%d%%" % int(round(st["damage"] * 100.0)))
	if st.has("max_hp"):
		parts.append("최대 체력 +%d" % int(st["max_hp"]))
	if st.has("armor"):
		parts.append("받는 피해 -%d%%" % int(round(st["armor"] * 100.0)))
	if st.has("speed"):
		parts.append("이동 +%d%%" % int(round(st["speed"] * 100.0)))
	if st.has("regen"):
		parts.append("초당 회복 %s" % String.num(st["regen"], 1))
	# 수치 대신 특수 효과만 있는 장비(고블린 카드 v1)는 설정의 text 한 줄
	if parts.is_empty():
		return str(Cfg.EQUIPMENT.get(id, {}).get("text", ""))
	return " · ".join(parts)


## 손패의 장비 카드를 착용자에게 끼운다. 같은 칸의 장비는 손패로 돌려보낸다. 반환: {ok, reason, replaced}
func equip(holder, uid: int) -> Dictionary:
	var entry: Dictionary = game.cards.get_entry(uid)
	if entry.is_empty():
		return {"ok": false, "reason": "카드가 없습니다"}
	var id: String = entry["id"]
	var why := block_reason(holder, id)
	if why != "":
		return {"ok": false, "reason": why}
	var slot := slot_of(id)
	var replaced := ""
	if not equipped(holder, slot).is_empty():
		replaced = equipped(holder, slot)["id"]
		unequip(holder, slot, false)
	if not game.cards.activate(uid):
		return {"ok": false, "reason": "카드가 없습니다"}
	holder.gear[slot] = {"uid": uid, "id": id}
	var add_hp := float(Cfg.EQUIPMENT[id]["stats"].get("max_hp", 0.0))
	if add_hp > 0.0:
		holder.max_hp += add_hp
		holder.hp += add_hp
	Fx.celebrate(holder.global_position + Vector3(0, 1.0, 0), Color(1.0, 0.86, 0.5), 0.45)
	changed.emit()
	return {"ok": true, "replaced": replaced}


## 칸의 장비를 벗겨 카드를 손패로 돌려보낸다(가득 차면 주머니). notify=false면 알림을 띄우지 않는다.
func unequip(holder, slot: String, notify := true) -> bool:
	var g := equipped(holder, slot)
	if g.is_empty():
		return false
	holder.gear.erase(slot)
	var add_hp := float(Cfg.EQUIPMENT.get(g["id"], {}).get("stats", {}).get("max_hp", 0.0))
	if add_hp > 0.0:
		holder.max_hp -= add_hp
		holder.hp = minf(holder.hp, holder.max_hp)
		if not holder.dead:
			holder.hp = maxf(holder.hp, 1.0)
	var zone: String = game.cards.return_from_play(g["uid"])
	if notify:
		var nm: String = game.cards.def(g["id"]).get("name", g["id"])
		game.toast("%s의 '%s'을(를) 벗겼습니다%s" % [holder_name(holder), nm, " — 주머니로" if zone == "pocket" else ""], Color(0.95, 0.88, 0.7))
	changed.emit()
	return true


## 착용자가 사라짐(용병 사망·계약 해지): 끼운 장비를 모두 손패로 돌려보낸다.
func release_all(holder) -> void:
	if holder == null or holder.get("gear") == null or holder.gear.is_empty():
		return
	var names: Array = []
	for slot in holder.gear.keys():
		names.append(game.cards.def(holder.gear[slot]["id"]).get("name", ""))
		unequip(holder, slot, false)
	game.toast("%s의 장비가 돌아왔습니다 — %s" % [holder_name(holder), ", ".join(names)], Color(0.95, 0.88, 0.7))
