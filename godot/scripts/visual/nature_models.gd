extends RefCounted
## Artist-authored Blender props. Cached PackedScenes share geometry and material.
const FOLDER := "res://scenes/props/nature/"
const PINES := ["pine_swept_snow", "pine_broad_snow", "pine_sparse_snow"]
const HEIGHTS := [5.45, 4.24, 5.25]
static var _scenes: Dictionary = {}

static func asset(id: String) -> Node3D:
	if not _scenes.has(id): _scenes[id] = load(FOLDER + id + ".tscn")
	return _scenes[id].instantiate()

static func pine(height: float, rng: RandomNumberGenerator) -> Node3D:
	var index := rng.randi_range(0, PINES.size()-1)
	var node := asset(PINES[index])
	node.scale = Vector3.ONE * height / HEIGHTS[index]
	return node

static func rock(size: float, rng: RandomNumberGenerator) -> Node3D:
	var node := asset("rock_boulder_snow" if rng.randf() < .66 else "rock_shards")
	node.scale = Vector3.ONE * size
	node.rotation.y = rng.randf_range(-PI, PI)
	return node
