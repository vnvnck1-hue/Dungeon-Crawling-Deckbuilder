extends Control
## Screen-aligned mini-map: paths, clearing markers, lodge, enemies and witch.
const Layout := preload("res://scripts/world/layout.gd")
const NavUtil := preload("res://scripts/world/nav_util.gd")
const CameraStyle := preload("res://scripts/visual/camera_style.gd")
const Hazards := preload("res://scripts/world/hazard_sites.gd")
const Extension := preload("res://scripts/ui/moon/moon_extension.gd")
var game
var region_label: Label
var _last_region := ""
var _paper: StyleBoxTexture
# 지도 회전(카메라 yaw)의 cos·sin. 카메라 스타일이 바뀔 때만 다시 구해, 프레임마다 수백 번 부르는 _map_point 가 함께 쓴다.
var _yaw_id := ""
var _yaw_cos := 1.0
var _yaw_sin := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	tooltip_text = "지도를 클릭해 이동 · 주황색: 산장 · 보라색: 마녀 · 점: 탐색 지점"
	region_label = Label.new()
	region_label.position = Vector2(28,22)
	region_label.add_theme_font_size_override("font_size",14)
	region_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(region_label)
	_paper = Extension.paper(0)


func _process(_delta: float) -> void:
	var p: Vector3 = game.player.global_position
	var name_text := "설산 숲"
	if Vector2(p.x,p.z).distance_to(Layout.MAP_CENTER)<12.0: name_text="마녀산장"
	for landmark in Layout.LANDMARKS:
		if Vector2(p.x,p.z).distance_to(landmark.pos)<7.0: name_text=landmark.name
	var danger:=Hazards.site_at(Vector2(p.x,p.z))
	if not danger.is_empty(): name_text="☠ "+str(danger.label)
	region_label.modulate=Color(.65,.15,.2) if not danger.is_empty() else Extension.PAPER_INK
	var follow: bool = game.world.player_camera.follow_enabled
	region_label.text = name_text + (" · 추적" if follow else " · 산장뷰")
	_last_region = name_text
	queue_redraw()


static func _camera_yaw() -> float:
	return deg_to_rad(CameraStyle.profile(CameraStyle.current_id).yaw)


func _sync_yaw() -> void:
	if _yaw_id == CameraStyle.current_id:
		return
	_yaw_id = CameraStyle.current_id
	var yaw := _camera_yaw()
	_yaw_cos = cos(yaw)
	_yaw_sin = sin(yaw)


func _map_point(p: Vector2) -> Vector2:
	_sync_yaw()
	var d := p-Layout.MAP_CENTER
	return Vector2(size.x*.5,128)+Vector2(d.x*_yaw_cos-d.y*_yaw_sin,d.x*_yaw_sin+d.y*_yaw_cos)*2.15


func _draw() -> void:
	draw_style_box(_paper,Rect2(Vector2.ZERO,size))
	draw_arc(Vector2(size.x*.5,128),Layout.BOUNDARY_RADIUS*2.15,0,TAU,96,Color(.35,.24,.32,.45),1.5,true)
	for path in Layout.EXPLORATION_PATHS:
		for i in range(path.size()-1):
			# Segment the trail so unexplored portions don't reveal the full forest layout.
			var a: Vector2 = path[i]
			var a_screen := _map_point(a)
			for step in 12:
				var b: Vector2 = path[i].lerp(path[i+1],(step+1)/12.0)
				var b_screen := _map_point(b)
				if _known(a): draw_line(a_screen,b_screen,Color(.35,.24,.32,.75),2.0,true)
				a = b
				a_screen = b_screen
	for landmark in Layout.LANDMARKS:
		if _known(landmark.pos): draw_circle(_map_point(landmark.pos),3.5,Color(.58,.8,.85))
	var lodge_at := _map_point(Vector2.ZERO)
	for site in Hazards.SITES:
		if not _known(site.center): continue
		var center:=_map_point(site.center)
		var radius: float=minf(site.radii.x,site.radii.y)*2.15
		draw_circle(center,radius,Color(.35,.65,.10,.16))
		draw_arc(center,radius,0,TAU,32,Color(.65,.9,.2,.8),1.4,true)
		draw_line(center-Vector2(3,3),center+Vector2(3,3),Color(.7,1,.2),2.0,true)
		draw_line(center+Vector2(-3,3),center+Vector2(3,-3),Color(.7,1,.2),2.0,true)
	draw_texture_rect(Extension.tex("extension"), Rect2(lodge_at - Vector2(10, 10), Vector2(20, 20)), false)
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not enemy.dead and (game.world.fog_of_war == null or game.world.fog_of_war.is_visible_at(enemy.global_position)):
			draw_texture_rect(Extension.tex("paw"), Rect2(_map_point(Vector2(enemy.position.x,enemy.position.z)) - Vector2(5, 5), Vector2(10, 10)), false)
	var at := _map_point(Vector2(game.player.global_position.x,game.player.global_position.z))
	draw_texture_rect(Extension.tex("badge"), Rect2(at - Vector2(8, 8), Vector2(16, 16)), false)
	draw_circle(at,4.0,Color(.9,.7,1.0))
	draw_arc(at,8.0,0,TAU,20,Color(.9,.7,1,.5),1.0,true)

func _known(pos: Vector2) -> bool:
	return game.world.fog_of_war == null or game.world.fog_of_war.is_explored_at(Vector3(pos.x,0,pos.y))


func _gui_input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb == null or not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT: return
	accept_event()
	if not game.movement_input_allowed() or game.player.dead: return
	var d := (mb.position-Vector2(size.x*.5,128))/2.15
	var yaw := _camera_yaw()
	var world_p := Layout.MAP_CENTER+Vector2(d.x*cos(yaw)+d.y*sin(yaw),-d.x*sin(yaw)+d.y*cos(yaw))
	var point := Layout.clamp_to_map(Vector3(world_p.x,0,world_p.y))
	var nav_map: RID = game.get_world_3d().navigation_map
	if NavigationServer3D.map_get_iteration_id(nav_map)==0: return
	var dest: Vector3 = NavUtil.ground_or_near(nav_map,point)
	game.player.set_destination(dest)
	game.world.show_click_marker(dest)
