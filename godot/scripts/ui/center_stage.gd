extends RefCounted
## 화면 가운데에 붙는 무대(크기 0 Control, 앵커 0.5). 가운데 펼침 화면(시작 손패·보물상자·새벽 보상·장날·마법서적)은
## 카드·제목·버튼을 이 무대의 자식으로 두고 '가운데 기준' 좌표로 놓는다. 창 크기·비율이 바뀌면(F11, 창 크기 조절,
## 울트라와이드·4:3 모니터) 무대가 앵커를 따라 새 가운데로 옮겨 가므로 연출 도중에도 정렬이 흐트러지지 않는다.
## 무대 밖으로 그려도 잘리지 않고, 자식은 자기 사각형으로 마우스를 받는다.


static func make(parent: Control) -> Control:
	var s := Control.new()
	s.name = "CenterStage"
	s.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	parent.add_child(s)
	return s


## 화면(전역) 좌표 → 무대 좌표.
static func to_stage(stage: Control, global_point: Vector2) -> Vector2:
	return stage.get_global_transform().affine_inverse() * global_point


## 지금 화면에서 무대가 차지할 수 있는 크기(= 보이는 화면 크기). 가운데 기준이므로 x 범위는 ±size.x/2 이다.
static func view(stage: Control) -> Vector2:
	return stage.get_viewport_rect().size
