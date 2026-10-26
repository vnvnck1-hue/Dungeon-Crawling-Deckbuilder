extends Control
## 카드 그림 한 장을 격자 메시로 그린다(TextureRect 대신). 정점이 많아 셰이더(card_warp.gdshaderinc)가
## 카드를 휘고·말고·비틀고·360° 돌릴 수 있다. 크기·위치·material·modulate 는 일반 Control 처럼 쓴다.
## 삼각형은 아래 줄부터 그린다: 아래 끝부터 뒤로 말리는 두루마리에서 말린 부분이 평평한 부분 뒤에 가려진다.

const COLS := 12
const ROWS := 18

var texture: Texture2D:
	set(v):
		if texture != null and texture.changed.is_connected(queue_redraw):
			texture.changed.disconnect(queue_redraw)
		texture = v
		# 카드 앞면(card_catalog._face)은 글자를 구운 뒤 같은 AtlasTexture 의 그림을 바꾼다 → 바뀌면 다시 그린다
		if texture != null:
			texture.changed.connect(queue_redraw)
		queue_redraw()

static var _meshes: Dictionary = {}   # Vector2i(크기) → ArrayMesh
static var _crops: Dictionary = {}    # 영역이 일부인 AtlasTexture → 잘라 낸 낱장


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


func _draw() -> void:
	var tex := drawable(texture)
	if tex == null or size.x <= 0.0 or size.y <= 0.0:
		return
	draw_mesh(grid(size), tex)


## draw_mesh 는 AtlasTexture 의 영역을 모른다(아틀라스 전체를 그린다). 영역이 그림 전체면 아틀라스를 그대로,
## 일부면 그 영역만 잘라 낸 낱장을 쓴다.
static func drawable(t: Texture2D) -> Texture2D:
	if not t is AtlasTexture:
		return t
	var at := t as AtlasTexture
	if at.atlas == null:
		return null
	if at.region.position == Vector2.ZERO and at.region.size == at.atlas.get_size():
		return at.atlas
	if not _crops.has(t):
		var img := t.get_image()
		_crops[t] = ImageTexture.create_from_image(img) if img != null else at.atlas
	return _crops[t]


## 크기별 격자 메시(정점 좌표 = 로컬 px, UV 0..1). 크기마다 한 번만 만든다.
static func grid(sz: Vector2) -> ArrayMesh:
	var key := Vector2i(roundi(sz.x * 4.0), roundi(sz.y * 4.0))
	if _meshes.has(key):
		return _meshes[key]
	if _meshes.size() > 96:
		_meshes.clear()
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	for r in ROWS + 1:
		for c in COLS + 1:
			var uv := Vector2(c / float(COLS), r / float(ROWS))
			verts.append(uv * sz)
			uvs.append(uv)
			cols.append(Color.WHITE)
	var idx := PackedInt32Array()
	for r in range(ROWS - 1, -1, -1):
		for c in COLS:
			var a := r * (COLS + 1) + c
			var b := a + 1
			var d := a + COLS + 1
			var e := d + 1
			idx.append_array([a, b, e, a, e, d])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[key] = m
	return m
