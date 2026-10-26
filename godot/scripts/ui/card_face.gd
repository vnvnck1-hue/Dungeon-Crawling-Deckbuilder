extends Control
## 글자 없는 카드 그림 위에 카탈로그 문구(제목·분류·설명·종족 이름표)를 실제 텍스트로 얹는 카드 앞면.
## 좌표는 카드 원본 1024×1536 기준이며 컨트롤 크기에 맞춰 글자 크기까지 함께 비례한다.
## 카드마다 크림판 모양이 달라(타원·방패·리본) 글자를 놓을 수 있는 폭이 줄 높이마다 다르다. 그래서
## tools/card_text_strip/measure_plates.py 가 빈 그림에서 잰 판 프로파일(assets/cards/text_layout.json)을 보고
## 줄마다 폭을 맞춘다. 긴 제목은 2줄로 나누고, 그래도 넘치면 글자를 줄인다(번역·새 카드 대비). 결과는 fit 에 남는다.
## 게임에서는 card_catalog.gd 가 이 컨트롤을 SubViewport 에 한 번 그려 텍스처로 굽는다(소비처는 Texture2D 그대로).
## 카드 언어(F8, scripts/ui/card_language.gd): 한국어는 BM 을지로체 한 벌, 영어는 A안(docs/english-font-research-v01.md) —
## 제목 Fraunces Black(SOFT 100·WONK 1·opsz 72), 분류 Alegreya SC Bold, 설명 Alegreya Bold, 이름표 Alegreya ExtraBold. 영문은 assets/cards/catalog_en.json,
## 없는 칸은 한글로 두고 영문 폰트의 fallback 인 을지로체로 그린다.

const CARD_SIZE := Vector2(1024, 1536)
const INK := Color8(28, 20, 18)
const FONT_PATH := "res://assets/fonts/bm/BMEULJIROTTF.ttf"   # 사용자 확정 2026-10-20: BM 을지로체
const LAYOUT_PATH := "res://assets/cards/text_layout.json"
const EN_TEXT_PATH := "res://assets/cards/catalog_en.json"
const LANGS := ["ko", "en"]
const LANG_NAMES := {"ko": "한국어", "en": "English"}
const SETTINGS_PATH := "user://settings.cfg"   # [cards] lang — window_mode.gd 와 같은 파일, 다른 구역
const EN_FONTS := {
	"title": ["res://assets/fonts/en/Fraunces-VF.ttf", {"wght": 900, "SOFT": 100, "WONK": 1, "opsz": 72}],
	"category": ["res://assets/fonts/en/AlegreyaSC-Bold.ttf", {}],
	"badge": ["res://assets/fonts/en/Alegreya-VF.ttf", {"wght": 800}],
	"rules": ["res://assets/fonts/en/Alegreya-VF.ttf", {"wght": 700}],
}

## 1024 기준 글자 크기(나무꾼 원본의 글자 높이에 맞춤)와 줄 간격.
const SIZE := {"title": 136, "category": 50, "badge": 55, "rules": 69}
const MIN_RATIO := {"title": 0.55, "category": 0.6, "badge": 0.5, "rules": 0.6}   # 이 비율 아래로는 줄이지 않는다
## 영문: 라틴 글자는 같은 크기에서 한글보다 작아 보이고(소문자 높이 ≈ 글자 높이의 절반) 문장이 길어, 기준 크기와 줄이는 폭을 따로 둔다.
const SIZE_EN := {"title": 128, "category": 46, "badge": 52, "rules": 66}
const MIN_RATIO_EN := {"title": 0.45, "category": 0.75, "badge": 0.5, "rules": 0.55}
const WRAP_RATIO := 0.86          # 제목이 한 줄로 이만큼 줄어야 들어가면 대신 2줄로 나눈다
const LINE_SPACING := 1.18        # 여러 줄의 줄 간격(폰트 높이 배수)
const TITLE_GAP := 0.1            # 제목과 분류 사이 간격(분류 글자 높이 배수)
const TITLE_ANCHOR := 0.42        # 제목 묶음을 판 세로의 어디에 두나(0 위, 0.5 가운데) — 원본은 살짝 위
const SIDE := 14                  # 판 테두리에서 글자까지 여유(1024 기준)
## 프로파일이 없는 카드(새 그림)에 쓰는 기본 판: 나무꾼 템플릿의 안전 영역.
const DEFAULT := {
	"title": {"y": 60, "step": 4, "runs": [[205, 818]], "h": 190},
	"rules": {"y": 1164, "step": 4, "runs": [[106, 916]], "h": 296},
}

static var _font: Font
static var _en_fonts: Dictionary = {}
static var _en_text: Dictionary = {}
static var _lang := ""
static var _layout: Dictionary = {}
static var _layout_loaded := false

var art: Texture2D
var title := ""
var category := ""
var badge := ""
var rules: PackedStringArray = []
var plates: Dictionary = {}
## 마지막 _draw 에서 칸마다 쓴 글자 크기: {slot: {"target": 기준, "used": 실제, "lines": 줄 수}} (검수용)
var fit: Dictionary = {}


static func font() -> Font:
	if _font == null:
		_font = load(FONT_PATH) as Font
	return _font


## 카드 언어. 처음 부를 때 user://settings.cfg [cards] lang 을 읽는다(없으면 한국어). `-- --card-lang=en` 은 이번 실행만.
static func language() -> String:
	if _lang == "":
		_lang = "ko"
		var cfg := ConfigFile.new()
		if cfg.load(SETTINGS_PATH) == OK and str(cfg.get_value("cards", "lang", "ko")) in LANGS:
			_lang = str(cfg.get_value("cards", "lang", "ko"))
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--card-lang=") and arg.trim_prefix("--card-lang=") in LANGS:
				_lang = arg.trim_prefix("--card-lang=")
	return _lang


## 언어만 바꾼다(저장·다시 굽기는 card_language.gd / card_catalog.gd 가 한다).
static func set_language(l: String) -> void:
	if l in LANGS:
		_lang = l


## 현재 언어의 기준 글자 크기·최소 축소율.
static func sizes() -> Dictionary:
	return SIZE_EN if language() == "en" else SIZE


static func min_ratios() -> Dictionary:
	return MIN_RATIO_EN if language() == "en" else MIN_RATIO


## 칸(title·category·badge·rules)에 쓰는 폰트. 영문 폰트에 없는 글자(한글)는 을지로체로 그린다.
static func font_for(slot: String) -> Font:
	if language() != "en" or not EN_FONTS.has(slot):
		return font()
	if not _en_fonts.has(slot):
		var fv := FontVariation.new()
		fv.base_font = load(EN_FONTS[slot][0]) as FontFile
		var coords := {}
		var ts := TextServerManager.get_primary_interface()
		for axis in EN_FONTS[slot][1]:
			coords[ts.name_to_tag(axis)] = EN_FONTS[slot][1][axis]
		fv.variation_opentype = coords
		fv.fallbacks = [font()]
		_en_fonts[slot] = fv
	return _en_fonts[slot]


## 현재 언어의 카드 문구 [제목, 분류, 설명 줄들, 이름표]. 영문이 없는 칸은 한글 그대로.
static func texts(card: Dictionary, badge_text: String) -> Array:
	var t := [String(card.get("name", "")), String(card.get("category", "")), PackedStringArray(card.get("printed_rules", [])), badge_text]
	if language() != "en":
		return t
	if _en_text.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(EN_TEXT_PATH)) if FileAccess.file_exists(EN_TEXT_PATH) else null
		_en_text = parsed if parsed is Dictionary else {"cards": {}}
	var en: Dictionary = _en_text.get("cards", {}).get(String(card.get("id", "")), {})
	if en.has("name"):
		t[0] = String(en["name"])
	if en.has("category"):
		t[1] = String(en["category"])
	if en.has("printed_rules"):
		t[2] = PackedStringArray(en["printed_rules"])
	t[3] = String(_en_text.get("badges", {}).get(badge_text, badge_text))
	return t


## 그림 경로(res://assets/cards/<key>.png) → 판 프로파일. 없으면 기본 판.
static func plates_for(art_path: String) -> Dictionary:
	if not _layout_loaded:
		_layout_loaded = true
		if FileAccess.file_exists(LAYOUT_PATH):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(LAYOUT_PATH))
			if parsed is Dictionary:
				_layout = parsed
	var key := art_path.trim_prefix("res://assets/cards/").trim_suffix(".png").replace("hand/", "")
	return _layout.get(key, DEFAULT)


func setup(card: Dictionary, blank_art: Texture2D, badge_text := "", art_path := "") -> void:
	art = blank_art
	var t := texts(card, badge_text)
	title = t[0]
	category = t[1]
	rules = t[2]
	badge = t[3]
	plates = plates_for(art_path if art_path != "" else (blank_art.resource_path if blank_art != null else ""))
	queue_redraw()


func _draw() -> void:
	if art != null:
		draw_texture_rect(art, Rect2(Vector2.ZERO, size), false)
	var k := size.x / CARD_SIZE.x
	fit = {}
	var plan := layout(title, category, badge, rules, plates, k)
	for slot in plan:
		fit[slot] = plan[slot]["fit"]
		for line in plan[slot]["lines"]:
			# 실제 글자 크기(정수로 반올림)로 다시 재서 가운데 맞춤. 폭 제한을 주면 반올림 오차로 끝 글자가 잘린다.
			var fs: int = line["size"]
			var lf: Font = line.get("font", font())
			var tw := lf.get_string_size(line["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			var pos: Vector2 = line["pos"] + Vector2((float(line["w"]) - tw) * 0.5, 0)
			draw_string(lf, pos, line["text"], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, INK)


## ── 배치 계산(그리지 않음 — 검증·캡처에서도 쓴다) ──

static func _plate_height(p: Dictionary) -> int:
	return int(p.get("h", p["runs"].size() * int(p["step"])))


## 판 안에서 [ya, yb) 행에 쓸 수 있는 폭과 그 구간의 왼쪽 x(1024 기준). 판 밖이면 폭 0.
static func _avail(p: Dictionary, ya: float, yb: float) -> Array:
	var y0: int = p["y"]
	var step: int = p["step"]
	var runs: Array = p["runs"]
	var h := _plate_height(p)
	if ya < y0 or yb > y0 + h:
		return [0.0, 0.0]
	var i0 := clampi(int(floor((ya - y0) / step)), 0, runs.size() - 1)
	var i1 := clampi(int(ceil((yb - y0) / step)), 0, runs.size() - 1)
	var l := 0.0
	var r := 2000.0
	for i in range(i0, i1 + 1):
		l = maxf(l, runs[i][0])
		r = minf(r, runs[i][1])
	return [maxf(0.0, r - l - 2 * SIDE), l + SIDE]


static func _widest(f: Font, lines: PackedStringArray, fs: int) -> float:
	var w := 0.0
	for l in lines:
		w = maxf(w, f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x)
	return w


## 제목을 가운데에 가장 가까운 공백에서 2줄로 나눈다. 공백이 없으면 그대로.
static func _split2(text: String) -> PackedStringArray:
	var best := -1
	var mid := text.length() / 2
	for i in text.length():
		if text[i] == " " and (best < 0 or absi(i - mid) < absi(best - mid)):
			best = i
	if best < 0:
		return PackedStringArray([text])
	return PackedStringArray([text.substr(0, best), text.substr(best + 1)])


## 줄 묶음을 판 세로 anchor 위치에 놓고 각 줄의 폭이 그 높이에서 쓸 수 있는 폭에 들어가는지 본다.
## 들어가면 [{text, pos, w, size}] 를, 아니면 [] 를 돌려준다. k 는 화면 배율.
## blocks: [{"lines": PackedStringArray, "size": int(1024 기준), "spacing": float, "gap": float, "font": Font(없으면 f0)}]
static func _place(f0: Font, p: Dictionary, blocks: Array, k: float, anchor := 0.5) -> Array:
	var total := 0.0
	for b in blocks:
		total += (b.get("font", f0) as Font).get_height(int(b["size"])) * float(b["spacing"]) * b["lines"].size() + float(b.get("gap", 0.0))
	var y: float = p["y"] + (_plate_height(p) - total) * anchor
	var out := []
	for b in blocks:
		var f: Font = b.get("font", f0)
		var fs: int = b["size"]
		var lh: float = f.get_height(fs) * float(b["spacing"])
		y += float(b.get("gap", 0.0))
		for l in b["lines"]:
			var av := _avail(p, y, y + lh)
			if f.get_string_size(l, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > av[0]:
				return []
			var base: float = y + (lh - f.get_height(fs)) * 0.5 + f.get_ascent(fs)
			out.append({"text": l, "pos": Vector2(av[1], base) * k, "w": av[0] * k, "size": int(round(fs * k)), "font": f})
			y += lh
	return out


static func _open_plate(p: Dictionary) -> Dictionary:
	return {"y": p["y"], "step": p["step"], "runs": [[0, 1024]], "h": _plate_height(p)}


## 모든 칸의 배치. {slot: {"lines": [...], "fit": {"target", "used", "lines"}}}
static func layout(title_t: String, category_t: String, badge_t: String, rules_t: PackedStringArray, pl: Dictionary, k: float) -> Dictionary:
	var f := font_for("title")
	var fc := font_for("category")
	var fr := font_for("rules")
	var sz := sizes()
	var mr := min_ratios()
	var out := {}
	# 제목(+분류): 한 줄 → 안 되면 2줄 → 그래도 안 되면 줄인다
	if title_t != "" and pl.has("title"):
		var p: Dictionary = pl["title"]
		var placed := []
		var used := 0
		var nlines := 1
		var ratio := 1.0
		while ratio >= mr["title"] and placed.is_empty():
			var ts := int(round(sz["title"] * ratio))
			var cs := maxi(int(round(sz["category"] * ratio)), int(sz["category"] * mr["category"]))
			var cands := [PackedStringArray([title_t])]
			if ratio <= WRAP_RATIO:
				cands = [PackedStringArray([title_t]), _split2(title_t)]
			for lines in cands:
				var blocks := [{"lines": lines, "size": ts, "spacing": LINE_SPACING if lines.size() > 1 else 1.0}]
				if category_t != "":
					blocks.append({"lines": PackedStringArray([category_t]), "size": cs, "spacing": 1.0, "gap": fc.get_height(cs) * TITLE_GAP, "font": fc})
				placed = _place(f, p, blocks, k, TITLE_ANCHOR)
				if not placed.is_empty():
					used = ts
					nlines = lines.size()
					break
			ratio -= 0.03
		if placed.is_empty():   # 최소 크기로라도 그린다
			used = int(sz["title"] * mr["title"])
			nlines = 2
			placed = _place(f, _open_plate(p), [{"lines": _split2(title_t), "size": used, "spacing": LINE_SPACING}], k, TITLE_ANCHOR)
		out["title"] = {"lines": placed, "fit": {"target": sz["title"], "used": used, "lines": nlines}}
	# 설명: 줄은 카탈로그대로, 폭·높이에 맞을 때까지 줄인다
	if not rules_t.is_empty() and pl.has("rules"):
		var p: Dictionary = pl["rules"]
		var placed := []
		var used := 0
		var ratio := 1.0
		while ratio >= mr["rules"] and placed.is_empty():
			var rs := int(round(sz["rules"] * ratio))
			placed = _place(fr, p, [{"lines": rules_t, "size": rs, "spacing": LINE_SPACING}], k)
			if not placed.is_empty():
				used = rs
			ratio -= 0.03
		if placed.is_empty():
			used = int(sz["rules"] * mr["rules"])
			placed = _place(fr, _open_plate(p), [{"lines": rules_t, "size": used, "spacing": LINE_SPACING}], k)
		out["rules"] = {"lines": placed, "fit": {"target": sz["rules"], "used": used, "lines": rules_t.size()}}
	# 이름표: 폭만 맞춘다(글자가 판 높이만큼 크다)
	if badge_t != "" and pl.has("badge"):
		var p: Dictionary = pl["badge"]
		f = font_for("badge")
		var cy: float = p["y"] + _plate_height(p) * 0.5
		var bs: int = sz["badge"]
		# 글자가 실제로 차지하는 가운데 띠(글자 높이의 70%)의 폭만 본다 — 타원 판의 위아래 끝은 좁다
		var wide := _avail(p, cy - f.get_height(bs) * 0.35, cy + f.get_height(bs) * 0.35)
		while bs > sz["badge"] * mr["badge"] and _widest(f, PackedStringArray([badge_t]), bs) > wide[0]:
			bs -= 1
			wide = _avail(p, cy - f.get_height(bs) * 0.35, cy + f.get_height(bs) * 0.35)
		var base := cy - f.get_height(bs) * 0.5 + f.get_ascent(bs)
		out["badge"] = {"lines": [{"text": badge_t, "pos": Vector2(wide[1], base) * k, "w": wide[0] * k, "size": int(round(bs * k)), "font": f}],
			"fit": {"target": sz["badge"], "used": bs, "lines": 1}}
	return out


## 카드 문구가 칸에 맞는지 그리지 않고 잰다(헤드리스 검증용). {slot: {"target", "used", "lines"}}
static func measure(card: Dictionary, badge_text := "", art_path := "") -> Dictionary:
	var pl := plates_for(art_path if art_path != "" else String(card.get("texture", "")))
	var t := texts(card, badge_text)
	var plan := layout(t[0], t[1], t[3], t[2], pl, 1.0)
	var out := {}
	for slot in plan:
		out[slot] = plan[slot]["fit"]
	return out
