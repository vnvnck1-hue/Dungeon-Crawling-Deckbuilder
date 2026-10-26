extends RefCounted
## Card asset catalogue (names, rules text, textures). Ownership lives in game/card_inventory.gd,
## use rules in game/card_use_resolver.gd.

const DATA_PATH := "res://assets/cards/catalog.json"
const GuestProfiles := preload("res://scripts/ui/guest_profiles.gd")
const CardFace := preload("res://scripts/ui/card_face.gd")
const Races := preload("res://scripts/game/races.gd")

## 실행 중 한 번만 읽어 두는 읽기 전용 사본과 id → 항목 색인(find·texture·back 이 쓴다).
## 카드 화면을 열 때마다 카드 장수만큼 33KB JSON 을 다시 읽던 것을 없앤다.
static var _cached: Dictionary = {}
static var _by_id: Dictionary = {}

## 원본 JSON 을 새로 읽어 고쳐도 되는 사본으로 돌려준다(검증·도구용).
static func read() -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if not parsed is Dictionary:
		push_error("Invalid card catalogue: " + DATA_PATH)
		return {}
	return parsed

static func _data() -> Dictionary:
	if _cached.is_empty():
		_cached = read()
		_by_id.clear()
		for entry in _cached.get("cards", []):
			var id: String = entry.get("id", "")
			if not _by_id.has(id):
				_by_id[id] = entry
	return _cached

static func find(card_id: String) -> Dictionary:
	_data()
	var entry = _by_id.get(card_id)
	return entry.duplicate(true) if entry != null else {}

static func texture(card_id: String, hand := false) -> Texture2D:
	var entry := find(card_id)
	var key := "hand_texture" if hand else "texture"
	# 원화가 아직 납품되지 않은 카드는 공용 뒷면으로 대신 보인다.
	if not entry.has(key) or not ResourceLoader.exists(entry[key]):
		return back(hand)
	return _face(entry[key], entry, String(entry.get("badge", "")))

## 종족별 직업 카드(docs/race-job-cards-v01.md): 고용 계약 카드는 그 손님의 종족 그림을 쓴다.
## 경로 res://assets/cards/races/<race>/<job>.png (손패용 .../hand/<job>.png). 인간·이름 풀 밖 인물·미납품이면 null → 기본 카드.
const RACE_JOB_CARDS := ["warrior", "hunter", "lumberjack", "gatherer"]
const RACE_DIR := "res://assets/cards/races/"

static func race_texture_path(card_id: String, race: String, hand := false) -> String:
	if not card_id in RACE_JOB_CARDS or race == "" or race == "human":
		return ""
	return RACE_DIR + race + ("/hand/" if hand else "/") + card_id + ".png"

static func race_texture(card_id: String, person: String, hand := false) -> Texture2D:
	if person == "" or not card_id in RACE_JOB_CARDS:
		return null
	var race := GuestProfiles.race_of(person)
	var path := race_texture_path(card_id, race, hand)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return _face(path, find(card_id), Races.name_of(race))

## 일러스트 변형(술주정 3종 등): 카탈로그 "art_variants" 의 파일 이름 목록. 없으면 0.
static func variant_count(card_id: String) -> int:
	return find(card_id).get("art_variants", []).size()

## 변형 art 번호의 그림. 변형이 없거나 번호가 범위 밖이거나 파일이 없으면 기본 그림.
static func variant_texture(card_id: String, art: int, hand := false) -> Texture2D:
	var names: Array = find(card_id).get("art_variants", [])
	if art >= 0 and art < names.size():
		var path := "res://assets/cards/" + ("hand/" if hand else "") + str(names[art]) + ".png"
		if ResourceLoader.exists(path):
			var entry := find(card_id)
			return _face(path, entry, String(entry.get("badge", "")))
	return texture(card_id, hand)

## 계약 카드 그림: 인물의 종족 그림이 있으면 그것, 없으면 기본 카드.
static func texture_for(card_id: String, person: String, hand := false) -> Texture2D:
	var t := race_texture(card_id, person, hand)
	return t if t != null else texture(card_id, hand)

static func back(hand := false) -> Texture2D:
	var data := _data()
	var key := "back_hand" if hand else "back"
	return load(data[key]) as Texture2D if data.has(key) else null


## ── 실제 텍스트 카드 앞면(docs/card-text-runtime.md) ──
## 카드 PNG 에는 글자가 없다. 그림 위에 카탈로그의 name·category·printed_rules·badge 를 CardFace 로 그려
## 텍스처로 굽고, 같은 그림·이름표는 한 번만 굽는다. 돌려주는 것은 AtlasTexture 한 객체 —
## 처음 몇 프레임은 글자 없는 그림이 보이다가 구워지면 그 객체의 그림이 글자 있는 것으로 바뀐다(소비처 교체 불필요).
## 헤드리스(검증 도구)에서는 렌더러가 없어 글자 없는 그림을 그대로 돌려준다.
static var _faces: Dictionary = {}

static func _face(path: String, entry: Dictionary, badge: String) -> Texture2D:
	var key := path + "|" + badge
	if _faces.has(key):
		return _faces[key]
	var art := load(path) as Texture2D
	if art == null:
		return null
	var t := AtlasTexture.new()
	t.atlas = art
	t.region = Rect2(0, 0, art.get_width(), art.get_height())
	_faces[key] = t
	_sources[key] = [entry, art, badge, path]
	if DisplayServer.get_name() != "headless" and Engine.get_main_loop() is SceneTree:
		_bake(t, entry, art, badge, path)
	return t

## 카드 언어(F8)를 바꾼 뒤: 이미 구운 앞면을 같은 AtlasTexture 객체에 새 언어로 다시 굽는다(소비처 교체 불필요).
## 한꺼번에 굽으면 SubViewport(1024×1536)가 수백 개 생기므로 BATCH 장씩 나눠 굽는다.
const BATCH := 8
static var _sources: Dictionary = {}
static var _rebake_id := 0

static func rebake_faces() -> void:
	if DisplayServer.get_name() == "headless" or not Engine.get_main_loop() is SceneTree:
		return
	_rebake_id += 1
	var my_id := _rebake_id
	var n := 0
	for key in _faces.keys():
		if my_id != _rebake_id:
			return   # 굽는 도중 또 바꿨으면 새 차례에 맡긴다
		var src: Array = _sources[key]
		n += 1
		if n % BATCH == 0:
			await _bake(_faces[key], src[0], src[1], src[2], src[3])
		else:
			_bake(_faces[key], src[0], src[1], src[2], src[3])

static func _bake(target: AtlasTexture, entry: Dictionary, art: Texture2D, badge: String, path: String) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	var vp := SubViewport.new()
	vp.size = Vector2i(art.get_width(), art.get_height())
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var face: Control = CardFace.new()
	face.size = Vector2(vp.size)
	face.setup(entry, art, badge, path)
	vp.add_child(face)
	tree.root.add_child.call_deferred(vp)
	await tree.process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	target.atlas = ImageTexture.create_from_image(vp.get_texture().get_image())
	vp.queue_free()
