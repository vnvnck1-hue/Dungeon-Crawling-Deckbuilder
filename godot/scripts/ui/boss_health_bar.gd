extends CanvasLayer
## 화면 위 가운데 보스 체력바(니벨라). 보스 등장 연출(첫 포효)과 함께 나타나며 비어 있던 게이지가 쭉 차오른다.
## 연출 기준: 사용자 제공 「게임 적 체력바 연출 가이드」(2026-10-22)
##  1. 게이지: 2중 지연 게이지(흰 잔상이 0.4초 뒤 따라옴) · 스프링 이징(급감 후 탄성 정착) · 누적 대미지 수치
##  2. 트랜스폼: 히트 셰이크(대미지에 비례) · 큰 타격은 2프레임 히트스탑 뒤 더 크게 · 펀치 스케일
##  3. 셰이더/VFX: 피격 플래시 · 선단 얼음 파편 · 단이 깎일수록 프레임에 금이 간다
##  4. 보스 특화: 3단 스톡(보라 → 주황 → 빨강), 한 단이 다 깎이면 유리처럼 깨지는 파편, 얼음 갑옷 실드 층과 파괴, 빈사(25%↓) 심장 박동 깜빡임
##  5. 노출: 전투를 벗어나면 4초 뒤 페이드아웃, 돌아오면 페이드인
const MoonSkin := preload("res://scripts/ui/moon/moon_skin.gd")

const STOCK_COLORS := [Color("ff4a5a"), Color("ff9a3c"), Color("9b6bff")]   # 남은 단 1·2·3
const GHOST := Color("fff1c4")
const SHIELD := Color("cfe2ff")
const TRACK := Color(0.07, 0.04, 0.14, 0.92)
const FRAME := Color(0.99, 0.91, 0.69)
const INTRO_FILL := 1.3
const GHOST_DELAY := 0.4
const BIG_HIT := 24.0
const HIDE_AFTER := 4.0

var boss                        # nivella_boss.gd
var game
var view: Control
var shown := false              # 검증용
var intro_done := false         # 검증용
var ghost_hits := 0             # 검증용: 잔상 게이지가 실제로 뒤처졌던 피격 수
var shatters := 0               # 검증용
var main_hp := 0.0              # 그려지는 주 게이지(체력 단위)
var ghost_hp := 0.0             # 그려지는 잔상 게이지
var alpha := 0.0
var _alpha_target := 0.0
var _hide_t := -1.0
var _main_v := 0.0
var _ghost_hold := 0.0
var _intro_t := -1.0
var _accum := 0.0
var _accum_t := 0.0
var _shake := 0.0
var _stop_t := 0.0
var _punch := 0.0
var _punch_v := 0.0
var _flash := 0.0
var _beat := 0.0
var _clock := 0.0
var _sparks: Array = []         # {p, v, life, max, c, s}
var _shards: Array = []         # {p, v, r, w, life, pts, c}
var _cracks: Array = []         # 단마다 미리 뽑은 금 선들
var _rng := RandomNumberGenerator.new()


func bind(owner_game, nivella) -> void:
	game = owner_game
	boss = nivella
	name = "BossHealthBar"
	layer = 9                    # HUD(10) 아래: 위쪽 시계 패널이 이 바를 가리지 않는 자리에 둔다
	_rng.seed = 7731
	view = Control.new()
	view.name = "View"
	view.set_anchors_preset(Control.PRESET_FULL_RECT)
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.draw.connect(_draw_bar)
	add_child(view)
	for s in 3:
		_cracks.append(_make_cracks())
	boss.damaged.connect(_on_damaged)
	boss.stock_broken.connect(_on_stock_broken)
	boss.shield_broken.connect(_on_shield_broken)
	boss.died.connect(_on_died)


## 등장: 프레임이 펼쳐지며 나타나고 게이지가 0에서 가득 차오른다.
func intro() -> void:
	shown = true
	_alpha_target = 1.0
	_hide_t = -1.0
	_intro_t = 0.0
	main_hp = 0.0
	ghost_hp = 0.0
	_main_v = 0.0


func show_bar() -> void:
	if boss.dead:
		return
	shown = true
	_alpha_target = 1.0
	_hide_t = -1.0


## 전투를 벗어남: HIDE_AFTER 초 뒤 서서히 사라진다.
func leave() -> void:
	if shown:
		_hide_t = HIDE_AFTER


# ───────────────────────── 사건 ─────────────────────────

func _on_damaged(amount: float, absorbed: float) -> void:
	var total: float = amount + absorbed
	_accum += total
	_accum_t = 1.3
	_ghost_hold = GHOST_DELAY
	if ghost_hp - boss.hp > 0.5:
		ghost_hits += 1
	var k := clampf(total / 40.0, 0.15, 1.0)
	if total >= BIG_HIT:
		_stop_t = 0.034          # 큰 타격: 2프레임 멈췄다가 크게 흔들린다
		_shake = maxf(_shake, 9.0 * k * 1.6)
	else:
		_shake = maxf(_shake, 7.0 * k)
	_punch_v += 6.0 * k
	_flash = 1.0
	# 선단 파편: 깎여 나간 경계에서 얼음 조각이 튄다
	for i in int(4 + total / 4.0):
		_spark(_edge_point(boss.hp), Color(0.85, 0.93, 1.0) if absorbed > 0.0 else GHOST)


func _on_stock_broken(left: int) -> void:
	# 깨진 단 색으로 바 전체가 유리처럼 부서진다
	_shatter(STOCK_COLORS[clampi(left, 0, 2)], 26)
	_flash = 1.0
	_shake = 18.0
	_punch_v += 10.0
	ghost_hp = boss.hp          # 새 단은 잔상 없이 가득 찬 채로
	main_hp = boss.hp
	_main_v = 0.0


func _on_shield_broken() -> void:
	_shatter(SHIELD, 16, true)
	_shake = maxf(_shake, 10.0)
	_flash = 1.0


func _on_died() -> void:
	_shatter(STOCK_COLORS[0], 34)
	_flash = 1.0
	_shake = 20.0
	main_hp = 0.0
	_hide_t = 1.6


# ───────────────────────── 매 프레임 ─────────────────────────

func _process(delta: float) -> void:
	if boss == null:
		return
	_clock += delta
	if _hide_t >= 0.0:
		_hide_t -= delta
		if _hide_t < 0.0:
			_alpha_target = 0.0
			shown = false
	alpha = move_toward(alpha, _alpha_target, delta * (3.5 if _alpha_target > alpha else 1.4))
	var hud_hidden: bool = game != null and game.get("hud") != null and game.hud != null and not game.hud.visible
	view.visible = alpha > 0.001 and not hud_hidden
	if not view.visible and _sparks.is_empty() and _shards.is_empty():
		return
	if _intro_t >= 0.0:
		_tick_intro(delta)
	else:
		_tick_gauges(delta)
	_tick_fx(delta)
	view.queue_redraw()


func _tick_intro(delta: float) -> void:
	_intro_t += delta
	var u := clampf((_intro_t - 0.35) / INTRO_FILL, 0.0, 1.0)
	var e := 1.0 - pow(1.0 - u, 3.0)
	main_hp = boss.max_hp * e
	ghost_hp = main_hp
	if u > 0.0 and u < 1.0 and randf() < 0.7:
		_spark(_edge_point_overall(e), STOCK_COLORS[2].lightened(0.4))
	if u >= 1.0:
		_intro_t = -1.0
		intro_done = true
		main_hp = boss.hp
		ghost_hp = boss.hp
		_flash = 1.0
		_punch_v += 8.0


func _tick_gauges(delta: float) -> void:
	# 주 게이지: 스프링(급감 후 살짝 넘쳤다가 정착)
	var acc: float = (boss.hp - main_hp) * 620.0 - _main_v * 38.0
	_main_v += acc * delta
	main_hp += _main_v * delta
	if absf(boss.hp - main_hp) < 0.05 and absf(_main_v) < 0.5:
		main_hp = boss.hp
		_main_v = 0.0
	# 잔상: 멈춰 있다가 따라 내려간다(히트스탑 동안은 기다린다)
	if _stop_t <= 0.0:
		_ghost_hold -= delta
	if _ghost_hold <= 0.0:
		ghost_hp = lerpf(ghost_hp, boss.hp, clampf(delta * 4.5, 0.0, 1.0))
		if absf(ghost_hp - boss.hp) < 0.3:
			ghost_hp = boss.hp
	ghost_hp = maxf(ghost_hp, boss.hp)
	_accum_t -= delta
	if _accum_t <= 0.0:
		_accum = 0.0
	# 빈사 박동: 두 번 뛰고 쉼
	var low: bool = not boss.dead and boss.hp / boss.max_hp <= 0.25
	if low:
		var t := fmod(_clock, 1.1)
		_beat = exp(-t * 10.0) + (exp(-(t - 0.2) * 10.0) * 0.75 if t > 0.2 else 0.0)
	else:
		_beat = move_toward(_beat, 0.0, delta * 4.0)


func _tick_fx(delta: float) -> void:
	if _stop_t > 0.0:
		_stop_t -= delta
	else:
		_shake = lerpf(_shake, 0.0, clampf(delta * 14.0, 0.0, 1.0))
	_punch_v += (-_punch * 240.0 - _punch_v * 16.0) * delta
	_punch += _punch_v * delta
	_flash = move_toward(_flash, 0.0, delta * 9.0)
	for i in range(_sparks.size() - 1, -1, -1):
		var s: Dictionary = _sparks[i]
		s.life -= delta
		if s.life <= 0.0:
			_sparks.remove_at(i)
			continue
		s.v += Vector2(0, 520.0) * delta
		s.p += s.v * delta
	for i in range(_shards.size() - 1, -1, -1):
		var h: Dictionary = _shards[i]
		h.life -= delta
		if h.life <= 0.0:
			_shards.remove_at(i)
			continue
		h.v += Vector2(0, 900.0) * delta
		h.p += h.v * delta
		h.r += h.w * delta


# ───────────────────────── 배치·파편 ─────────────────────────

func _rect() -> Rect2:
	var vs := view.get_viewport_rect().size
	var w := minf(780.0, vs.x * 0.49)
	var h := clampf(vs.y * 0.019, 12.0, 20.0)
	# 위쪽 가운데 알림(토스트) 줄 바로 아래: 알림이 떠도 이름·게이지를 가리지 않는다
	return Rect2(Vector2((vs.x - w) * 0.5, vs.y * 0.17), Vector2(w, h))


func _per() -> float:
	return boss.max_hp / 3.0


## 지금 단 기준으로 체력 값 v 의 게이지 비율.
func _frac_in_stock(v: float, stock: int) -> float:
	return clampf((v - _per() * (stock - 1)) / _per(), 0.0, 1.0)


func _edge_point(v: float) -> Vector2:
	var r := _rect()
	return Vector2(r.position.x + r.size.x * _frac_in_stock(v, maxi(boss.stock_left(), 1)), r.position.y + r.size.y * 0.5)


func _edge_point_overall(f: float) -> Vector2:
	var r := _rect()
	return Vector2(r.position.x + r.size.x * f, r.position.y + r.size.y * 0.5)


func _spark(at: Vector2, c: Color) -> void:
	var a := _rng.randf_range(-PI * 0.95, -PI * 0.05)
	var sp := _rng.randf_range(120.0, 340.0)
	var life := _rng.randf_range(0.35, 0.7)
	_sparks.append({"p": at, "v": Vector2(cos(a), sin(a)) * sp + Vector2(_rng.randf_range(-40, 90), 0), "life": life, "max": life,
		"c": c, "s": _rng.randf_range(2.0, 4.5)})


func _shatter(c: Color, count: int, silver := false) -> void:
	shatters += 1
	var r := _rect()
	for i in count:
		var x := r.position.x + r.size.x * (float(i) + _rng.randf()) / count
		var pts := PackedVector2Array()
		var n := _rng.randi_range(3, 5)
		var size := _rng.randf_range(5.0, 13.0)
		for k in n:
			var a := TAU * k / n + _rng.randf_range(-0.4, 0.4)
			pts.append(Vector2(cos(a), sin(a)) * size * _rng.randf_range(0.6, 1.2))
		_shards.append({"p": Vector2(x, r.position.y + r.size.y * 0.5), "v": Vector2(_rng.randf_range(-260, 260), _rng.randf_range(-520, -160)),
			"r": 0.0, "w": _rng.randf_range(-10, 10), "life": _rng.randf_range(0.7, 1.2), "pts": pts,
			"c": c.lightened(_rng.randf_range(0.0, 0.35)) if not silver else SHIELD.lerp(Color.WHITE, _rng.randf())})


## 한 단에 쓸 금: 바 테두리에서 안쪽으로 갈라지는 지그재그 선 6개(깎인 만큼 차례로 드러난다).
func _make_cracks() -> Array:
	var out: Array = []
	for i in 6:
		var x := _rng.randf_range(0.06, 0.94)
		var top := _rng.randf() < 0.5
		var pts := PackedVector2Array([Vector2(x, 0.0 if top else 1.0)])
		var p := pts[0]
		for k in _rng.randi_range(3, 5):
			p += Vector2(_rng.randf_range(-0.025, 0.025), (0.28 if top else -0.28) * _rng.randf_range(0.6, 1.1))
			p.y = clampf(p.y, 0.0, 1.0)
			pts.append(p)
		out.append(pts)
	return out


# ───────────────────────── 그리기 ─────────────────────────

func _draw_bar() -> void:
	var r := _rect()
	var center := r.get_center()
	var shake := Vector2(randf_range(-1, 1), randf_range(-1, 1) * 0.6) * _shake if _stop_t <= 0.0 else Vector2.ZERO
	var intro_open := 1.0
	if _intro_t >= 0.0:
		intro_open = 0.55 + 0.45 * (1.0 - pow(1.0 - clampf(_intro_t / 0.35, 0.0, 1.0), 3.0))
	var sc := 1.0 + _punch * 0.05 + _beat * 0.015
	view.draw_set_transform(center + shake, 0.0, Vector2(sc * intro_open, sc))
	var lr := Rect2(r.position - center, r.size)   # 가운데 기준 좌표
	var a := alpha
	var stock: int = maxi(boss.stock_left(), 1) if not boss.dead else 1
	var col: Color = STOCK_COLORS[clampi(stock - 1, 0, 2)]
	var under: Color = STOCK_COLORS[clampi(stock - 2, 0, 2)] if stock >= 2 else TRACK
	# 이름
	var font := MoonSkin.font(true)
	var name_pos := lr.position + Vector2(0, -10)
	view.draw_string_outline(font, name_pos, "니벨라", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, 6, Color(0.05, 0.02, 0.1, a))
	view.draw_string(font, name_pos, "니벨라", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.86, 0.92, 1.0, a))
	view.draw_string_outline(font, name_pos + Vector2(78, -1), "서리 둥지의 여왕", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0.05, 0.02, 0.1, a))
	view.draw_string(font, name_pos + Vector2(78, -1), "서리 둥지의 여왕", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.72, 0.68, 0.86, a))
	# 단 표시(오른쪽 위 마름모 셋)
	for i in 3:
		var c: Vector2 = Vector2(lr.end.x - 10.0 - i * 22.0, lr.position.y - 16.0)
		var alive_stock: bool = i < stock and not boss.dead
		var dia := PackedVector2Array([c + Vector2(0, -7), c + Vector2(7, 0), c + Vector2(0, 7), c + Vector2(-7, 0)])
		view.draw_colored_polygon(dia, (STOCK_COLORS[i] if alive_stock else Color(0.2, 0.15, 0.3)) * Color(1, 1, 1, a))
		view.draw_polyline(dia + PackedVector2Array([dia[0]]), Color(FRAME, 0.8 * a), 1.2)
	# 바탕(다음 단 색이 비쳐 '아직 남은 단'을 보여 준다)
	view.draw_rect(lr.grow(3.0), Color(0.03, 0.01, 0.07, 0.85 * a))
	view.draw_rect(lr, Color(under.darkened(0.55) if stock >= 2 else TRACK, a))
	if stock >= 2:
		view.draw_rect(lr, Color(TRACK, 0.55 * a))
	var main_f: float = _frac_in_stock(main_hp, stock) if _intro_t < 0.0 else main_hp / boss.max_hp
	var ghost_f: float = _frac_in_stock(ghost_hp, stock) if _intro_t < 0.0 else main_f
	var fill_col: Color = col if _intro_t < 0.0 else STOCK_COLORS[2]
	# 잔상 게이지
	if ghost_f > main_f:
		view.draw_rect(Rect2(lr.position + Vector2(lr.size.x * main_f, 0), Vector2(lr.size.x * (ghost_f - main_f), lr.size.y)), Color(GHOST, 0.9 * a))
	# 주 게이지(위가 밝은 두 띠) + 빈사 박동
	if main_f > 0.0:
		var fr := Rect2(lr.position, Vector2(lr.size.x * main_f, lr.size.y))
		var c2 := fill_col.lerp(Color.WHITE, _beat * 0.35)
		view.draw_rect(fr, Color(c2.darkened(0.25), a))
		view.draw_rect(Rect2(fr.position, Vector2(fr.size.x, fr.size.y * 0.45)), Color(c2.lightened(0.18), a))
		# 흐르는 서리 결
		var step := 14.0
		var off := fmod(_clock * 40.0, step)
		var x := -off
		while x < fr.size.x:
			var x0 := maxf(x, 0.0)
			var x1 := minf(x + 4.0, fr.size.x)
			if x1 > x0:
				view.draw_rect(Rect2(fr.position + Vector2(x0, 0), Vector2(x1 - x0, fr.size.y)), Color(1, 1, 1, 0.07 * a))
			x += step
		# 선단 빛 + 피격 플래시
		view.draw_rect(Rect2(fr.position + Vector2(fr.size.x - 2.0, -1.0), Vector2(3.0, fr.size.y + 2.0)), Color(1, 1, 1, (0.5 + _flash * 0.5) * a))
		if _flash > 0.0:
			view.draw_rect(fr, Color(1, 1, 1, _flash * 0.55 * a))
	# 얼음 갑옷 실드 층: 은청색 반투명 띠 + 사슬 마디
	if boss.shield > 0.0:
		var sf: float = boss.shield / boss.SHIELD_MAX
		var sr := Rect2(lr.position + Vector2(0, -3.0), Vector2(lr.size.x * sf, lr.size.y + 6.0))
		view.draw_rect(sr, Color(Color("8fb2e8"), 0.88 * a))
		view.draw_rect(Rect2(sr.position, Vector2(sr.size.x, sr.size.y * 0.4)), Color(Color("e4efff"), 0.6 * a))
		var x2 := 6.0
		while x2 < sr.size.x - 4.0:
			var c3 := sr.position + Vector2(x2, sr.size.y * 0.5)
			view.draw_polyline(PackedVector2Array([c3 + Vector2(-5, 0), c3 + Vector2(0, -4), c3 + Vector2(5, 0), c3 + Vector2(0, 4), c3 + Vector2(-5, 0)]), Color(1, 1, 1, 0.55 * a), 1.2)
			x2 += 14.0
		view.draw_rect(sr, Color(1, 1, 1, 0.7 * a), false, 1.2)
	# 프레임에 금: 지금 단이 깎인 만큼 드러난다
	if _intro_t < 0.0 and not boss.dead:
		var lost := 1.0 - _frac_in_stock(boss.hp, stock)
		var shown_cracks := int(floor(lost * 7.0))
		var crack_set: Array = _cracks[clampi(stock - 1, 0, 2)]
		for i in mini(shown_cracks, crack_set.size()):
			var pts := PackedVector2Array()
			for q in crack_set[i]:
				pts.append(lr.position + Vector2(q.x * lr.size.x, q.y * lr.size.y))
			view.draw_polyline(pts, Color(0.04, 0.02, 0.08, 0.9 * a), 2.2)
			view.draw_polyline(pts, Color(0.8, 0.9, 1.0, 0.35 * a), 0.8)
	# 테두리 + 빈사 붉은 빛
	view.draw_rect(lr.grow(1.5), Color(FRAME, 0.85 * a), false, 1.6)
	if _beat > 0.01:
		view.draw_rect(lr.grow(4.0 + _beat * 3.0), Color(1.0, 0.25, 0.3, _beat * 0.6 * a), false, 2.0 + _beat * 2.0)
	# 누적 대미지
	if _accum > 0.0 and _intro_t < 0.0:
		var t := clampf(_accum_t / 1.3, 0.0, 1.0)
		var ax := lr.position.x + lr.size.x * clampf(ghost_f, 0.06, 0.96)
		var txt := "-%d" % int(round(_accum))
		var tp := Vector2(ax - 20.0, lr.end.y + 22.0 + (1.0 - t) * 6.0)
		view.draw_string_outline(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, Color(0.05, 0.02, 0.1, a * t))
		view.draw_string(font, tp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(GHOST, a * t))
	view.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 파편(화면 좌표)
	for s in _sparks:
		var k: float = s.life / s.max
		view.draw_circle(s.p, s.s * k, Color(s.c, k * maxf(a, 0.6)))
	for h in _shards:
		var pts := PackedVector2Array()
		for q in h.pts:
			pts.append(h.p + q.rotated(h.r))
		var k2: float = clampf(h.life / 0.6, 0.0, 1.0)
		view.draw_colored_polygon(pts, Color(h.c, k2))
		view.draw_polyline(pts + PackedVector2Array([pts[0]]), Color(1, 1, 1, 0.7 * k2), 1.0)
