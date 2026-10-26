extends RefCounted
## 어느 노드에서든 효과음을 부르는 도우미. game 참조가 없는 액터·UI도 현재 장면의 SoundBank(main.sounds)를 찾아 쓴다.
## 사용: const Sfx := preload("res://scripts/audio/sfx.gd")  →  Sfx.play(self, "mon_hit")

static func bank(n: Node):
	if n == null or not n.is_inside_tree():
		return null
	var scene := n.get_tree().current_scene
	if scene == null:
		return null
	return scene.get("sounds")


static func play(n: Node, event: String) -> void:
	var b = bank(n)
	if b != null:
		b.play(event)


static func play_or(n: Node, event: String, fallback: String) -> void:
	var b = bank(n)
	if b != null:
		b.play_or(event, fallback)


## 반복음(등불·모닥불·날갯짓 등): 주인이 매 프레임 0~1 무게로 부른다. 부르지 않으면 서서히 꺼진다.
static func loop(n: Node, id: String, event: String, weight: float) -> void:
	var b = bank(n)
	if b != null:
		b.loop(id, event, weight)


## 마녀와의 거리로 반복음 무게를 정한다(near 이내 1, far 밖 0).
static func near_player(n: Node3D, near := 4.0, far := 14.0) -> float:
	var scene = n.get_tree().current_scene if n.is_inside_tree() else null
	if scene == null or scene.get("player") == null or not is_instance_valid(scene.player):
		return 0.0
	var d: float = n.global_position.distance_to(scene.player.global_position)
	return clampf(1.0 - (d - near) / maxf(far - near, 0.01), 0.0, 1.0)
