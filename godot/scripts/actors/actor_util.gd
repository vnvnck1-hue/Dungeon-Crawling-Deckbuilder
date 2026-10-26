extends RefCounted
## 액터 스크립트(마녀·용병·괴물·들짐승·양·독충)가 함께 쓰는 작은 계산 도우미. 상태를 갖지 않는다.
## 사용: const ActorUtil := preload("res://scripts/actors/actor_util.gd")  →  ActorUtil.flat_dist(a, b)

const Cfg := preload("res://scripts/config.gd")
const Fx := preload("res://scripts/visual/fx.gd")


## 높이를 뺀 바닥 평면(XZ) 거리.
static func flat_dist(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


## visual 이 dir(수평 성분) 쪽을 rate 속도로 돌아보게 한다. 모델은 +Z 를 앞으로 본다.
static func face(visual: Node3D, dir: Vector3, delta: float, rate: float) -> void:
	dir.y = 0.0
	if dir.length() < 0.01:
		return
	visual.rotation.y = lerp_angle(visual.rotation.y, atan2(dir.x, dir.z), clampf(delta * rate, 0.0, 1.0))


## 두 액터의 가슴 높이(height) 사이를 장애물(L_OBSTACLE)이 가리지 않으면 true.
static func has_los(from: Node3D, to: Node3D, height := 0.7) -> bool:
	var lift := Vector3(0, height, 0)
	var q := PhysicsRayQueryParameters3D.create(from.global_position + lift, to.global_position + lift, Cfg.L_OBSTACLE)
	return from.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


## 걸을 때 등의 가지에서 나뭇잎이 조금씩 떨어진다(표시 전용, 나무 용병·숲 괴물).
## timer: 남은 시간. 줄인 값(떨어뜨렸으면 새로 뽑은 간격)을 돌려준다.
static func shed_leaves(timer: float, delta: float, at: Vector3, vel: Vector3) -> float:
	timer -= delta
	if timer > 0.0:
		return timer
	var back := -vel.normalized()
	timer = randf_range(0.28, 0.5)
	Fx.leaf_shed(at + Vector3(0, 1.45, 0) + back * 0.35, back, 1 if randf() < 0.7 else 2)
	return timer
