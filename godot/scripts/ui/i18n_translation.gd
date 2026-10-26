extends Translation
## 영문판 UI 번역(locale "en"). 원문(한국어) 문자열을 그대로 키로 쓰는 사전 assets/i18n/en.json 을 읽는다.
## Label·Button·RichTextLabel·Label3D·툴팁은 auto translate 로 화면에 그릴 때마다 여기를 거치므로,
## 게임 코드는 지금처럼 한국어 문자열을 넣으면 된다(로직이 비교하는 값은 바뀌지 않는다).
## 조회 순서: ① 통째로 같은 문장 ② 여러 줄이면 줄마다 ③ "%d골드" 같은 서식 원문을 정규식으로 맞춰 값만 옮김
## ④ 그래도 남은 한글은 사전의 낱말·구절을 긴 것부터 바꿔 끼움. 결과는 캐시한다.

const DICT_PATH := "res://assets/i18n/en.json"
const CACHE_MAX := 6000
const _WRAP := {"(": ")", "[": "]", "\"": "\"", "'": "'", "“": "”", "‘": "’", "「": "」"}

var exact: Dictionary = {}          # 원문 → 영문
var _templates: Array = []          # [{re: RegEx, en: String}] — 글자 수 많은(구체적인) 것부터
var _fragments: Array = []          # [[원문, 영문]] — 서식 없는 항목, 긴 것부터
var _cache: Dictionary = {}
var _hangul := RegEx.create_from_string("[\\x{AC00}-\\x{D7A3}\\x{3131}-\\x{318E}]")
var _spec := RegEx.create_from_string("%(%|[-+0#]*\\d*(?:\\.\\d+)?[dsfxXc])")


func _init() -> void:
	locale = "en"
	load_dict(DICT_PATH)


func load_dict(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_warning("i18n: %s 없음" % path)
		return
	var data = JSON.parse_string(f.get_as_text())
	if not data is Dictionary:
		push_warning("i18n: %s 형식 오류" % path)
		return
	exact = data
	_templates.clear()
	_fragments.clear()
	_cache.clear()
	# 코드가 문장을 이어 붙이거나 줄 단위로 나누는 경우를 위해 파생 항목을 더한다:
	# 앞뒤 공백·줄바꿈을 뗀 문장, 줄 수가 같은 여러 줄 문장의 각 줄.
	var derived := {}
	for ko in exact:
		var k := String(ko)
		var en := String(exact[ko])
		var ks := k.strip_edges()
		if ks != k and not ks.is_empty():
			derived[ks] = en.strip_edges()
		# " · 추적" "고용할 수 없습니다 — " 처럼 구분자로 시작·끝나는 조각: 구분자를 뗀 형태도 둔다(조각 번역용)
		var kc := _strip_sep(k)
		if kc != ks and not kc.is_empty() and _hangul.search(kc) != null:
			derived[kc] = _strip_sep(en)
		var kl := k.split("\n")
		var el := en.split("\n")
		if kl.size() > 1 and kl.size() == el.size():
			for i in kl.size():
				var line := kl[i].strip_edges()
				if not line.is_empty() and _hangul.search(line) != null and _spec_count(line) == _spec_count(el[i]):
					derived[line] = el[i].strip_edges()
	for k in derived:
		if not exact.has(k):
			exact[k] = derived[k]
	for ko in exact:
		var en: String = exact[ko]
		var k := String(ko)
		if _spec.search(k) != null:
			var re := _template_regex(k)
			if re != null:
				_templates.append({"re": re, "en": en, "weight": _hangul_count(k)})
		elif k.length() >= 1 and not k.contains("\n"):
			_fragments.append([k, en])
	_templates.sort_custom(func(a, b): return a["weight"] > b["weight"])
	_fragments.sort_custom(func(a, b): return a[0].length() > b[0].length())


func _get_message(src_message: StringName, _context: StringName) -> StringName:
	var s := String(src_message)
	if s.is_empty() or _hangul.search(s) == null:
		return &""   # 번역 없음 → 원문 그대로
	return StringName(translate_text(s))


## 한 문자열을 영문으로. 한글이 없으면 그대로.
func translate_text(s: String) -> String:
	if _hangul.search(s) == null:
		return s
	if exact.has(s):
		return exact[s]
	if s.contains("\r"):   # CRLF 로 저장된 스크립트의 여러 줄 문자열 — 사전은 \r 없이 둔다
		return translate_text(s.replace("\r", ""))
	if _cache.has(s):
		return _cache[s]
	# 구분자로 이은 문장은 조각마다 먼저 — 조각이 모두 옮겨지면 그 결과를 쓴다
	# ("%s 날" 같은 넓은 서식이 "이름와 대화 · 이야기 제목" 전체를 삼키지 않게)
	var out := _by_segments(s)
	if out.is_empty() or _hangul.search(out) != null:
		out = _by_template(s)
	if out.is_empty():
		var core := s.strip_edges()
		if core != s and not core.is_empty():
			# 앞뒤 공백·줄바꿈은 그대로 두고 가운데만 옮긴다
			var head := s.substr(0, s.find(core))
			out = head + translate_text(core) + s.substr(head.length() + core.length())
		elif s.contains("\n"):
			var parts := s.split("\n")
			for i in parts.size():
				parts[i] = translate_text(parts[i])
			out = "\n".join(parts)
		elif s.length() > 2 and _WRAP.has(s[0]) and s.ends_with(_WRAP[s[0]]):
			out = s[0] + translate_text(s.substr(1, s.length() - 2)) + _WRAP[s[0]]   # (…) [ … ] 로 감싼 문장
		else:
			out = _by_segments(s)
			if out.is_empty():
				out = _by_fragments(s)
	if _cache.size() > CACHE_MAX:
		_cache.clear()
	_cache[s] = out
	return out


func _by_template(s: String) -> String:
	for t in _templates:
		var m: RegExMatch = (t["re"] as RegEx).search(s)
		if m == null:
			continue
		var vals: Array = []
		for gi in range(1, m.get_group_count() + 1):
			vals.append(translate_text(m.get_string(gi)))
		return _fill(t["en"], vals)
	return ""


## 영문 서식 문장의 자리표시자를 순서대로 이미 서식이 끝난 값으로 채운다.
func _fill(en: String, vals: Array) -> String:
	var out := ""
	var pos := 0
	var vi := 0
	for m in _spec.search_all(en):
		out += en.substr(pos, m.get_start() - pos)
		if m.get_string(1) == "%":
			out += "%"
		else:
			out += str(vals[vi]) if vi < vals.size() else ""
			vi += 1
		pos = m.get_end()
	return out + en.substr(pos)


## " · " " — " 로 이어 붙인 문장은 조각마다 옮긴다(예: 이름 + "와 대화 · " + 이야기 제목).
func _by_segments(s: String) -> String:
	for sep in ["  ·  ", " · ", " — ", "  "]:   # 넓은 구분자부터(카드 분류 "식물 · 방책" 같은 안쪽 구분자는 통째 유지)
		if s.contains(sep):
			var parts := s.split(sep)
			for i in parts.size():
				parts[i] = translate_text(parts[i])
			return sep.join(parts)
	return ""


func _by_fragments(s: String) -> String:
	var out := s
	for fr in _fragments:
		if _hangul.search(out) == null:
			break
		var k: String = fr[0]
		if k.length() <= out.length() and out.contains(k):
			out = out.replace(k, fr[1])
	return out


## "%d골드 · %s" → ^(-?\d+)골드 · (.*?)$
func _template_regex(k: String) -> RegEx:
	var pat := "(?s)^"
	var pos := 0
	var groups := 0
	for m in _spec.search_all(k):
		pat += _escape(k.substr(pos, m.get_start() - pos))
		var spec := m.get_string(1)
		if spec == "%":
			pat += "%"
		elif spec.ends_with("s") or spec.ends_with("c"):
			pat += "(.*?)"
			groups += 1
		elif spec.ends_with("f"):
			pat += "\\s*([-+]?\\d+(?:\\.\\d+)?)"
			groups += 1
		else:
			pat += "\\s*([-+]?[0-9a-fA-F]+)"
			groups += 1
		pos = m.get_end()
	pat += _escape(k.substr(pos)) + "$"
	if groups == 0 or _hangul.search(k) == null:
		return null
	var re := RegEx.new()
	if re.compile(pat) != OK:
		return null
	return re


func _escape(lit: String) -> String:
	var out := ""
	for ch in lit:
		if "\\^$.|?*+()[]{}".contains(ch):
			out += "\\" + ch
		else:
			out += ch
	return out


func _strip_sep(k: String) -> String:
	var t := k.strip_edges()
	while not t.is_empty() and "·—-:,".contains(t[0]):
		t = t.substr(1).strip_edges()
	while not t.is_empty() and "·—-:,".contains(t[t.length() - 1]):
		t = t.substr(0, t.length() - 1).strip_edges()
	return t


func _spec_count(k: String) -> int:
	var n := 0
	for m in _spec.search_all(k):
		if m.get_string(1) != "%":
			n += 1
	return n


func _hangul_count(k: String) -> int:
	return _hangul.search_all(k).size()
