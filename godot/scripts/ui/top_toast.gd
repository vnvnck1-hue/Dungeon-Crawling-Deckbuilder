extends RefCounted
## 화면 위쪽 가운데에 잠깐 뜨는 알림 글자(F8 언어·F9 카드 질감처럼 타이틀 화면에서도 쓰는 단축키 안내).
## HUD 토스트가 없는 화면에서도 보이도록 주인 노드 아래에 자기 CanvasLayer 를 만든다. 헤드리스에서는 띄우지 않는다.

var _label: Label
var _tween: Tween
var _offset_top := 150.0


func _init(offset_top := 150.0) -> void:
	_offset_top = offset_top


func show_text(owner: Node, text: String) -> void:
	if not owner.is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	if _label == null or not is_instance_valid(_label):
		var layer := CanvasLayer.new()
		layer.layer = 120
		owner.add_child(layer)
		_label = Label.new()
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_label.offset_top = _offset_top
		_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_label.add_theme_font_size_override("font_size", 26)
		_label.add_theme_color_override("font_outline_color", Color(0.08, 0.05, 0.1))
		_label.add_theme_constant_override("outline_size", 8)
		_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_label)
	_label.text = text
	_label.modulate.a = 1.0
	if _tween != null:
		_tween.kill()
	_tween = owner.create_tween()
	_tween.tween_interval(1.4)
	_tween.tween_property(_label, "modulate:a", 0.0, 0.5)
