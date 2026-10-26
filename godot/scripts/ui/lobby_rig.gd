extends RefCounted
## 로비 인물 아이들링 리그(shaders/lobby_idle.gdshader). docs/lobby.md
## 원화(art/concepts/lobby/races-closeup-distant-v02) 일곱 인물과 부위의 피벗·주기·세기. 좌표는 원화 픽셀(1920×1080).
## 사용자 요청: "천천히 자연스럽게" — 기울기는 1도 미만, 숨 주기 4~6초, 인물마다 위상과 빠르기가 달라 같은 박자로 움직이지 않는다.
## 종족 성격은 손님 초상(portrait_motion.gd)과 같은 결: 드워프 묵직하게, 오크 크고 느리게, 요정 가볍게 떠 있고, 고블린 부산하게.

const CANVAS := Vector2(1920, 1080)
const WEIGHT_DIR := "res://assets/ui/lobby/"
const IDS_PATH := "res://assets/ui/lobby/lobby_character_ids.png"
## 넓은 화면용 왼쪽 확장 지도(2640×1080, 원화가 x=720). 있으면 이것으로 굽는다 — 화면은 lobby_*_wide.png 와 함께 쓴다
const IDS_WIDE_PATH := "res://assets/ui/lobby/lobby_character_ids_wide.png"

## 구역 지도(lobby_character_ids.png)의 R 값 → 구역 번호. 표는 docs/handoff/codex-lobby-layers-v01.md
const ID_VALUES := {20: 0, 40: 1, 60: 2, 80: 3, 100: 4, 120: 5, 160: 6, 180: 7, 200: 8, 220: 9, 240: 10, 140: 11}

## [이름, 피벗 px, 기울기 진폭(도), 기울기 주기(초), 위상(초), 숨 높이(px), 숨 주기(초), 숨 부풂, 씰룩 문(0/1), 부모, 문 주기(초)]
const REGIONS := [
	["human",    Vector2(330, 430),  0.32, 10.5, 0.0, 1.6, 4.8, 0.0035, 0, -1, 0.0],
	["wolf",     Vector2(690, 330),  0.40,  8.6, 2.7, 1.3, 4.3, 0.0030, 0, -1, 0.0],
	["orc",      Vector2(1060, 430), 0.26, 12.0, 5.1, 2.0, 5.8, 0.0045, 0, -1, 0.0],
	["fairy",    Vector2(420, 610),  0.55,  7.2, 1.3, 2.6, 3.4, 0.0040, 0, -1, 0.0],
	["witch",    Vector2(770, 800),  0.30, 11.0, 3.6, 1.5, 5.0, 0.0035, 0, -1, 0.0],
	["hat",      Vector2(830, 540),  0.22, 11.0, 4.3, 0.6, 5.0, 0.0,    0,  4, 0.0],
	["dwarf",    Vector2(330, 1000), 0.20, 13.0, 6.2, 1.8, 5.6, 0.0040, 0, -1, 0.0],
	["goblin",   Vector2(1000, 1070), 0.50, 7.4, 0.8, 1.5, 4.0, 0.0035, 0, -1, 0.0],
	["goblin_ear", Vector2(905, 860), 1.40, 0.9, 0.0, 0.0, 4.0, 0.0,    1,  7, 9.0],
	["wings",    Vector2(300, 480),  1.10,  2.9, 0.4, 0.0, 3.4, 0.0,    0,  3, 0.0],
	["antennae", Vector2(455, 395),  2.00,  4.6, 0.9, 0.0, 3.4, 0.0,    0,  3, 0.0],
	["wolf_ear", Vector2(700, 60),   1.60,  0.8, 2.0, 0.0, 4.3, 0.0,    1,  1, 11.0],
]


## 셰이더 uniform 배열(rig_pivot·rig_breath·rig_extra)을 채운다.
## offset: 인물 레이어 안에서 원화가 시작하는 자리(넓은 레이어면 x 720), canvas: 인물 레이어 크기.
static func apply(mat: ShaderMaterial, offset := Vector2.ZERO, canvas := CANVAS) -> void:
	var pivot := PackedVector4Array()
	var breath := PackedVector4Array()
	var extra := PackedVector4Array()
	for r in REGIONS:
		pivot.append(Vector4(r[1].x + offset.x, r[1].y + offset.y, deg_to_rad(r[2]), TAU / r[3]))
		breath.append(Vector4(r[4], r[5], TAU / r[6], r[7]))
		extra.append(Vector4(r[8], r[9], TAU / r[10] if r[10] > 0.0 else 0.0, 0.0))
	mat.set_shader_parameter("rig_pivot", pivot)
	mat.set_shader_parameter("rig_breath", breath)
	mat.set_shader_parameter("rig_extra", extra)
	mat.set_shader_parameter("canvas_px", canvas)
	for k in 3:
		var path := WEIGHT_DIR + "lobby_weights_%d.png" % k
		if ResourceLoader.exists(path):
			mat.set_shader_parameter("weights_%d" % k, load(path))


static func weights_ready() -> bool:
	for k in 3:
		if not ResourceLoader.exists(WEIGHT_DIR + "lobby_weights_%d.png" % k):
			return false
	return true


## 구역 지도 → 부드러운 가중치 텍스처 3장(480×270 RGBA, 구역 4개씩). tools/build_lobby_weights.gd 가 부른다.
## 1/4 크기에서 구역별 점유율을 세고, 줄였다 키우는 흐림 뒤 정규화한다(경계 약 20px 에 걸쳐 이웃 구역과 섞이고,
## 실루엣 바깥으로도 같은 거리만큼 이어져 가장자리가 움직일 때 배경 쪽 픽셀이 바른 변위를 받는다).
static func build_weights(ids: Image) -> Array:
	ids.convert(Image.FORMAT_RGB8)
	var src := ids.get_data()
	var sw := ids.get_width()
	var sh := ids.get_height()
	const F := 4
	var w := sw / F
	var h := sh / F
	var lut := PackedInt32Array()
	lut.resize(256)
	lut.fill(-1)
	for v in ID_VALUES:
		for dv in range(-9, 10):
			if v + dv >= 0 and v + dv < 256:
				lut[v + dv] = ID_VALUES[v]
	var n := REGIONS.size()
	var cover: Array = []
	for i in n:
		var a := PackedFloat32Array()
		a.resize(w * h)
		cover.append(a)
	var inv := 1.0 / float(F * F)
	for y in sh:
		var row := (y / F) * w
		for x in sw:
			var r := lut[src[(y * sw + x) * 3]]
			if r >= 0:
				cover[r][row + x / F] += inv
	var blurred: Array = []
	var total := PackedFloat32Array()
	total.resize(w * h)
	for i in n:
		var img := Image.create_from_data(w, h, false, Image.FORMAT_RF, cover[i].to_byte_array())
		img.resize(w / 5, h / 5, Image.INTERPOLATE_BILINEAR)
		img.resize(w, h, Image.INTERPOLATE_CUBIC)
		var b := img.get_data().to_float32_array()
		for k in b.size():
			b[k] = maxf(b[k], 0.0)
			total[k] += b[k]
		blurred.append(b)
	var out: Array = []
	for t in 3:
		var bytes := PackedByteArray()
		bytes.resize(w * h * 4)
		for k in w * h:
			var tot: float = total[k]
			var fade := smoothstep(0.01, 0.2, tot)   # 실루엣 바깥 약 15px 에 걸쳐 변위가 0 으로
			for c in 4:
				var i := t * 4 + c
				var v := 0.0
				if i < n and tot > 0.0005:
					v = blurred[i][k] / tot * fade
				bytes[k * 4 + c] = clampi(roundi(v * 255.0), 0, 255)
		out.append(Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, bytes))
	return out


## 구역 지도가 아직 없을 때(개발용) 원화 위 인물 위치를 타원으로 대강 칠한 지도. 뒤에 칠한 것이 앞이다.
static func rough_ids() -> Image:
	var img := Image.create(int(CANVAS.x), int(CANVAS.y), false, Image.FORMAT_RGB8)
	var shapes := [   # [R 값, 중심, 반지름]
		[20, Vector2(250, 260), Vector2(330, 320)],
		[40, Vector2(700, 160), Vector2(260, 200)],
		[60, Vector2(1080, 220), Vector2(200, 260)],
		[20, Vector2(120, 520), Vector2(160, 160)],
		[220, Vector2(170, 490), Vector2(170, 90)],
		[120, Vector2(820, 470), Vector2(330, 130)],
		[100, Vector2(800, 680), Vector2(190, 200)],
		[80, Vector2(410, 500), Vector2(110, 120)],
		[240, Vector2(500, 330), Vector2(110, 70)],
		[160, Vector2(320, 860), Vector2(330, 260)],
		[180, Vector2(990, 900), Vector2(200, 200)],
		[200, Vector2(800, 860), Vector2(110, 40)],
	]
	for s in shapes:
		var col := Color8(s[0], s[0], s[0])
		var c: Vector2 = s[1]
		var r: Vector2 = s[2]
		for y in range(maxi(0, int(c.y - r.y)), mini(int(CANVAS.y), int(c.y + r.y))):
			var dy := (y - c.y) / r.y
			var half := r.x * sqrt(maxf(0.0, 1.0 - dy * dy))
			img.fill_rect(Rect2i(int(c.x - half), y, int(half * 2.0), 1), col)
	return img
