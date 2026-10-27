extends SceneTree
## 지형(단·절벽·물·식생) 확인용 렌더 캡처. 첫 방 둘레를 넓게, 방 사이 길, 전투 구도를 찍고 스스로 닫는다.
## 실행(godot 폴더 기준):  <Godot> --path . --script res://dungeon/tools/capture_terrain.gd
## 결과: screenshots/capture/terrain_*.png

const OUT := "res://screenshots/capture/"

var main
var t := 0.0
var step := 0
var wait := 1.5


func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	main = load("res://dungeon/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	main.set_process_unhandled_input(false)


func _shot(name: String) -> void:
	root.get_texture().get_image().save_png(OUT + "terrain_" + name + ".png")
	print("SHOT " + name)


func _view(p: Vector3, height: float) -> void:
	var w = main.world
	w.focus_on(p, true)
	w.set_zoom(height, true)


func _process(delta: float) -> bool:
	t += delta
	wait -= delta
	if wait > 0.0:
		return false
	var w = main.world
	main.hud.visible = false
	match step:
		0:
			_view(w.rooms[0].center, 34.0)
		1:
			_shot("wide_room0")
			_view(w.rooms[0].center.lerp(w.rooms[1].center, 0.5), 30.0)
		2:
			_shot("wide_path01")
			_view(w.room_focus(1), w.CAM_HEIGHT_BATTLE)
		3:
			_shot("battle_room1")
			_view(w.paths[1][3] + w.CAM_FOCUS_OFFSET, w.CAM_HEIGHT)
		4:
			_shot("march_path1")
			_view(w.room_focus(3), w.CAM_HEIGHT_BATTLE)
		5:
			_shot("battle_room3")
			quit()
			return true
	step += 1
	wait = 0.8
	return false
