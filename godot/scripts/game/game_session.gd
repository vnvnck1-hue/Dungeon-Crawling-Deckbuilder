extends Node
## GameSession: 준비 → 웨이브 → (정리 연출) → 준비 … → 완료 / 실패.
## 패배(플레이어 사망·산장 파괴)는 피해가 들어온 즉시 확정되며, 같은 프레임의 웨이브 완료보다 우선한다.

const Cfg := preload("res://scripts/config.gd")
const ChapterData := preload("res://scripts/game/chapter_data.gd")

signal state_changed(state: int)

enum State { PREP, COMBAT, CLEARING, VICTORY, DEFEAT }

var game
var state := State.PREP
var wave_index := 0
var prep_elapsed := 0.0
var clear_timer := 0.0
var defeat_reason := ""
var play_time := 0.0


func _ready() -> void:
	name = "GameSession"


func start() -> void:
	_enter_prep()


func prep_remaining() -> float:
	return maxf(Cfg.PREP_TIME - prep_elapsed, 0.0)


func is_over() -> bool:
	return state == State.VICTORY or state == State.DEFEAT


func day() -> int:
	return wave_index + 1


## 이 챕터의 날(=밤) 수(볼륨 확장: 3 → 12).
func total_days() -> int:
	return ChapterData.total_days()


func _opening_active() -> bool:
	return game.get("opening") != null and game.opening.active


func _enter_prep() -> void:
	state = State.PREP
	prep_elapsed = 0.0
	# 1일차도 새벽음으로 시작한다. 도입 연출이 열려 있으면 프롤로그가 끝나고 새벽이 밝을 때 연출이 직접 울린다.
	if wave_index > 0 or not _opening_active():
		game.sounds.play("dawn")
	game.economy.begin_prep()
	# 새 낮: 생산·고용 기회만 갱신하고 미사용 카드는 그대로 유지한다(v0.3 §10)
	var grown: int = game.world.pasture.grow_lambs(day())
	if grown > 0:
		game.toast("새끼양 %d마리가 어른 양으로 자랐습니다" % grown, Color(1.0, 0.95, 0.8))
	var wool: int = game.world.pasture.produce_wool(day())
	if wool > 0:
		game.toast("양 %d마리의 털이 자랐습니다 — 양을 클릭해 수확" % wool, Color(1.0, 0.97, 0.85))
	game.contracts.on_prep_start()
	# 낮 손패: 밤 카드는 주머니로, 손패가 찰 때까지 낮 카드를 무작위로 뽑는다(아침 드로우보다 먼저; 첫날은 시작 손패 화면이 대신). 태우기 횟수도 새로 센다
	game.cards.on_prep_start()
	game.cards.phase_swap("day", wave_index > 0)
	if game.relics != null:
		game.relics.on_prep_start(day())
	# 챕터 하루 사건: 제단 해금·새벽 보상·장날·새벽 침식(저주의 속삭임은 아침 드로우를 막는다)
	var draw_blocked := false
	if game.get("chapter") != null and game.chapter != null:
		draw_blocked = game.chapter.on_prep_start(day())
	# 아침 드로우(마녀의 주머니): 첫날은 시작 손패 드로우가 대신한다
	if wave_index > 0 and not draw_blocked and not game.cards.hand_full():   # 전환으로 이미 가득 찼으면 조용히 건너뛴다
		game.cards.morning_draw()
	state_changed.emit(state)


func _process(delta: float) -> void:
	if is_over():
		return
	play_time += delta
	match state:
		State.PREP:
			# 첫 판 튜토리얼의 강제 단계(첫 고용·계약 카드 배치) 동안 낮 시계를 멈춘다
			if game.get("tutorial") != null and game.tutorial.holds_clock():
				return
			var warn_at := Cfg.PREP_TIME - 10.0
			if prep_elapsed < warn_at and prep_elapsed + delta >= warn_at:
				game.sounds.play("night_warn")
			prep_elapsed += delta
			game.economy.update_prep(prep_elapsed)
			if prep_elapsed >= Cfg.PREP_TIME:
				start_wave()
		State.COMBAT:
			if game.waves.is_wave_done():
				_on_wave_cleared()
		State.CLEARING:
			clear_timer -= delta
			if clear_timer <= 0.0:
				_after_clear()


func start_wave() -> void:
	if state != State.PREP:
		return
	game.economy.end_prep()
	wave_index += 1
	state = State.COMBAT
	# 밤 손패: 낮 카드는 주머니로, 손패가 찰 때까지 밤 카드를 무작위로 뽑는다
	game.cards.phase_swap("night")
	game.dragon.on_wave_start()
	game.player.cancel_harvest()
	game.contracts.on_wave_start()
	if game.wildlife != null:
		game.wildlife.on_wave_start()
	game.waves.start_wave(wave_index)
	if game.get("chapter") != null and game.chapter != null:
		game.chapter.on_wave_start(wave_index)
	# 밤 진입: 챕터 밤 규칙과 'N일차 밤'을 가운데 배너 하나로 알린다(배너가 없는 구성에서는 토스트 한 줄)
	if game.get("banner") != null and game.banner != null:
		game.banner.night_card(wave_index, total_days())
	else:
		game.toast("%d일차 밤 (%d / %d) — %s" % [wave_index, wave_index, total_days(), ChapterData.rule(wave_index)["desc"]], Color(1.0, 0.6, 0.6))
	game.sounds.play("wave_start")
	state_changed.emit(state)


func _on_wave_cleared() -> void:
	if state != State.COMBAT:
		return
	game.waves.stop()
	state = State.CLEARING
	game.contracts.on_combat_end()
	if game.get("chapter") != null and game.chapter != null:
		game.chapter.on_combat_end()
	var leave: float = game.dragon.dismiss()
	clear_timer = maxf(leave, 2.0)
	game.toast("%d일차 밤 정리!" % wave_index, Color(0.8, 1.0, 0.8))
	game.sounds.play("wave_clear")
	state_changed.emit(state)


func _after_clear() -> void:
	if is_over():
		return
	if wave_index >= total_days():
		state = State.VICTORY
		get_tree().paused = true
		game.sounds.play("victory")
		state_changed.emit(state)
	else:
		_enter_prep()


func report_defeat(reason: String) -> void:
	if is_over():
		return
	state = State.DEFEAT
	defeat_reason = reason
	get_tree().paused = true
	game.sounds.play("defeat")
	state_changed.emit(state)
