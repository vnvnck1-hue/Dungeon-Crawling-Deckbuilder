extends RefCounted
## 대사 필기 타임라인: 줄별 글자 폭으로 "펜 끝이 언제 어디에 있는지"를 미리 짠다(docs/dialogue-handwriting.md).
## 글자마다 조금씩 다른 속도로 긋고, 띄어쓰기에서 펜을 잠깐 들고, 문장부호 뒤와 줄바꿈에서 숨을 쉰다.
## 같은 문장은 늘 같은 리듬(문장 해시를 시드로)이라 검증·녹화가 매번 같다.
const CHAR_TIME := 0.05        # 한글 한 음절을 긋는 기본 시간(초)
const NARROW_TIME := 0.032     # 영문·숫자 등 좁은 글자
const MARK_TIME := 0.03        # 문장부호 자체
const SPACE_PAUSE := 0.07      # 띄어쓰기: 펜을 들고 옮긴다
const MARK_PAUSE := 0.2        # , . ! ? … 뒤 숨
const LINE_PAUSE := 0.24       # 다음 줄로 펜을 옮기는 시간
const JITTER := 0.22           # 글자 시간 ±비율
const MARKS := ",.!?…~·:;"
const DRY_TIME := 0.6         # 줄을 다 쓴 뒤 젖은 잉크가 마르는 시간
const LEAD := 10.0             # 펜 끝이 글자 오른쪽 끝보다 앞서는 픽셀(셰이더 soft + 기울기 반높이)

## 획: 한 글자를 긋는 구간. {line, x0, x1, t0, t1, ink}  ink 는 펜 압력(소리 크기) 0~1, 공백·쉼은 획이 아니다.
var strokes: Array = []
var line_widths: Array[float] = []
var line_ends: Array[float] = []   # 줄마다 마지막 획이 끝나는 시각
var total := 0.0

static func build(lines: Array, font: Font, font_size: int) -> RefCounted:
	var plan := new()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("\n".join(lines))
	var t := 0.0
	for li in lines.size():
		var line: String = lines[li]
		if li > 0 and not line.is_empty(): t += LINE_PAUSE
		var x := 0.0
		for i in line.length():
			var ch := line[i]
			var x1 := font.get_string_size(line.substr(0, i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
			if ch == " ":
				# 펜을 든 채로 건너간다: 경계는 공백 끝으로 옮기되 획(소리)은 없다
				plan.strokes.append({"line": li, "x0": x, "x1": x1, "t0": t, "t1": t + SPACE_PAUSE, "ink": 0.0})
				t += SPACE_PAUSE
			else:
				var base := MARK_TIME if MARKS.contains(ch) else (CHAR_TIME if ch.unicode_at(0) >= 0x1100 else NARROW_TIME)
				var d := base * (1.0 + rng.randf_range(-JITTER, JITTER))
				plan.strokes.append({"line": li, "x0": x, "x1": x1, "t0": t, "t1": t + d, "ink": rng.randf_range(0.7, 1.0)})
				t += d
				if MARKS.contains(ch) and i < line.length() - 1: t += MARK_PAUSE
			x = x1
		plan.line_widths.append(x)
		plan.line_ends.append(t)
		if not line.is_empty() and MARKS.contains(line[line.length() - 1]): t += MARK_PAUSE * 0.6
	plan.total = t
	return plan

## 펜 끝 x: 아직 시작 전인 줄은 -soft(안 보임), 다 쓴 줄은 아주 큰 값(전부 보임·젖은 색도 마름).
func reveal_at(line: int, t: float) -> float:
	if line >= line_ends.size() or t >= line_ends[line] + DRY_TIME: return 100000.0
	var at := -20.0
	for s in strokes:
		if s.line != line: continue
		if t < s.t0: break
		var u: float = clampf((t - s.t0) / maxf(s.t1 - s.t0, 0.001), 0.0, 1.0)
		# 획 안에서 펜이 빨라졌다 느려진다. +LEAD: 경계 번짐·기울기 때문에 글자 끝이 덜 드러나지 않게
		at = lerpf(s.x0, s.x1, u * u * (3.0 - 2.0 * u)) + LEAD
	# 다 쓴 뒤 0.6초 동안은 끝자리에 머물며 젖은 잉크가 마른다(마르는 정도는 wetness)
	return at

## 그 줄 젖은 잉크 남은 정도 1 → 0: 줄을 다 쓰고 나서 DRY_TIME 에 걸쳐 마른다.
func wetness(line: int, t: float) -> float:
	if line >= line_ends.size(): return 0.0
	return 1.0 - smoothstep(line_ends[line], line_ends[line] + DRY_TIME, t)

## 지금 펜 압력(0~1): 획 중간에 가장 세고 글자 사이에서 살짝 끊긴다. 쉼·공백에서는 0.
func pen_at(t: float) -> float:
	for s in strokes:
		if t < s.t0: return 0.0
		if t < s.t1:
			var u: float = (t - s.t0) / maxf(s.t1 - s.t0, 0.001)
			return float(s.ink) * sqrt(sin(PI * u))
	return 0.0

func is_writing(t: float) -> bool:
	return t < total
