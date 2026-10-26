extends RefCounted
## 캐릭터끼리의 부드러운 밀어내기(soft separation). 상태를 갖지 않는다.
## 단단한 충돌 대신, 개인 영역(반지름)이 겹친 만큼만 서로를 천천히 밀어낸다.
## 잠깐 겹치는 건 허용해 좁은 길·문 앞에서 끼임·떨림·밀려 날아가는 버그를 막고, 시간이 지나면 자연스럽게 떨어진다.
## 사용: 등록 SoftSep.register(self, 반지름, 무게) → 이동 틱마다 velocity = 원래속도 + SoftSep.push(self)
##       (CharacterBody3D 는 move_and_slide 로 벽을 지키고, Node3D 액터는 push(self) * delta 만큼 직접 옮긴다)

const GROUP := &"soft_bodies"
const STIFFNESS := 3.0     # 겹친 거리 1m 당 밀어내는 속도(m/s). 낮을수록 천천히 떨어진다
const MAX_SPEED := 1.2     # 한 틱에 받는 밀어내기 속도 상한: 여럿에 끼여도 튕겨 나가지 않는다
const SLACK := 0.04        # 이만큼의 겹침은 밀지 않는다: 맞닿은 채 서 있을 때 미세하게 떠는 것을 막는다


## 액터를 밀어내기 대상으로 등록한다. weight 가 클수록 덜 밀리고 상대를 더 민다(마녀·큰 괴물).
static func register(n: Node3D, radius: float, weight := 1.0) -> void:
	n.set_meta(&"sep_r", radius)
	n.set_meta(&"sep_w", weight)
	n.add_to_group(GROUP)


## me 가 지금 받아야 할 밀어내기 속도(수평, m/s). 겹친 상대가 없으면 0.
static func push(me: Node3D) -> Vector3:
	if not active(me):
		return Vector3.ZERO
	var r: float = me.get_meta(&"sep_r", 0.3)
	var w: float = me.get_meta(&"sep_w", 1.0)
	var p := me.global_position
	var out := Vector3.ZERO
	for o: Node3D in me.get_tree().get_nodes_in_group(GROUP):
		if o == me or not active(o):
			continue
		var d := p - o.global_position
		d.y = 0.0
		var min_d: float = r + float(o.get_meta(&"sep_r", 0.3))
		var l2 := d.length_squared()
		if l2 >= min_d * min_d:
			continue
		var l := sqrt(l2)
		var depth := min_d - l - SLACK
		if depth <= 0.0:
			continue
		var dir := d / l if l > 0.001 else _tie_dir(me, o)
		var ow: float = o.get_meta(&"sep_w", 1.0)
		# 무게 비율로 나눠 민다(같은 무게면 1배, 가벼운 쪽이 더 많이 비켜 난다)
		out += dir * depth * STIFFNESS * (2.0 * ow / (w + ow))
	if out.length() > MAX_SPEED:
		out = out.normalized() * MAX_SPEED
	return out


## 밀어내기에 참여 중인가: 죽음·산장 안·탑 위·숨김 상태는 빠진다.
static func active(n: Node3D) -> bool:
	return n.is_inside_tree() and n.is_visible_in_tree() \
		and n.get(&"dead") != true and n.get(&"hidden") != true and n.get(&"on_tower") != true


## 정확히 같은 자리에 겹쳤을 때 쓸 방향. 두 액터가 서로 반대 방향을 얻도록 id 로 정한다.
static func _tie_dir(a: Node, b: Node) -> Vector3:
	var lo := mini(a.get_instance_id(), b.get_instance_id())
	var hi := maxi(a.get_instance_id(), b.get_instance_id())
	var ang := float(posmod(lo * 7919 + hi, 6283)) / 1000.0
	var dir := Vector3(cos(ang), 0.0, sin(ang))
	return dir if a.get_instance_id() == lo else -dir
