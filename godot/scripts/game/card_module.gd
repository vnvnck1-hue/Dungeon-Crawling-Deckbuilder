extends Node
## 카드 묶음 모듈(고블린·종족·언데드·선술집 카드)이 같이 쓰는 판정 도우미.
## 각 모듈은 이 스크립트를 상속하고 game 을 받아 쓴다. 계획(plan) 사전의 모양은 CardUseResolver 와 같다.

var game


func _fail(reason: String, where = null) -> Dictionary:
	return {"ok": false, "reason": reason, "pos": where}


## 밤 전투 중인가.
func _night() -> bool:
	return game.session.state == preload("res://scripts/game/game_session.gd").State.COMBAT


## 대상 지점이 필요 없는 카드: 마녀 자리에서 쓴다.
func _anywhere() -> Vector3:
	return game.player.global_position


## 적이나 지면 한 점. 실패면 사유 문자열. r 은 CardUseResolver.
func _point(sp: Vector2, r):
	var enemy = r.enemy_at(sp)
	if enemy != null:
		var c: Vector3 = enemy.global_position
		c.y = 0.0
		return c
	var g = r._ground_at(sp)
	if g == null:
		return "대상을 찾지 못했습니다"
	if r._lodge_hit(sp):
		return "산장에는 쓸 수 없습니다"
	return r.valid_ground(g)


## 평면(xz) 거리.
func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## 착용자가 이 장비를 끼고 있으면 {slot, uid}, 아니면 빈 사전.
func _worn(holder, id: String) -> Dictionary:
	var gear = holder.get("gear") if holder != null else null
	if gear == null:
		return {}
	for slot in gear:
		if gear[slot].get("id", "") == id:
			return {"slot": slot, "uid": int(gear[slot]["uid"])}
	return {}
