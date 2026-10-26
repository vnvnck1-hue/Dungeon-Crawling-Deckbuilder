extends RefCounted
## 창 밖(허공) 클릭으로 닫기 — 공용 판정.
## 닫을 수 있는 창(닫기 버튼이 있는 창)만 쓴다. 상자·멀리건·서적·새벽 선물처럼 반드시 골라야 하는 창은 쓰지 않는다.


## 창을 닫는 클릭인가: 좌·우 버튼을 누른 순간만(뗄 때·휠은 아님).
static func is_press(event: InputEvent) -> bool:
	var mb := event as InputEventMouseButton
	return mb != null and mb.pressed and mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]


## pos(화면 좌표)가 보이는 controls 중 하나라도 덮으면 true. margin 만큼 여유를 둔다.
static func hits(pos: Vector2, controls: Array, margin := 0.0) -> bool:
	for c in controls:
		if c == null or not is_instance_valid(c) or not c.is_visible_in_tree():
			continue
		var r: Rect2 = c.get_global_transform() * Rect2(Vector2.ZERO, c.size)
		if r.grow(margin).has_point(pos):
			return true
	return false
