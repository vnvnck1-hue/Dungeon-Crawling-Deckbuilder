extends Node
## 승인된 효과음만 재생하며 실행 중 선택 변경을 1초마다 반영한다.
## selected.json 의 sounds 에 적힌 이벤트는 모두 쓸 수 있다(이름은 영문 소문자·숫자·_).
const BACKGROUND := ["bgm_field", "bgm_evening", "bgm_combat", "bgm_boss", "ambience_day", "ambience_evening"]
const COMBAT_IN := 6.0     # 밤 웨이브가 시작될 때 전투 곡으로 넘어가는 시간(초)
const BOSS_IN := 1.2       # 보스 둥지에서 등장 연출이 시작되면 보스 곡으로 빠르게 넘어가는 시간(초)
const BOSS_OUT := 4.0      # 둥지를 나가거나 보스가 쓰러지면 원래 곡으로 돌아가는 시간(초)
const COMBAT_OUT := 10.0   # 웨이브가 끝나고 전투 곡이 물러나는 시간(초)
const EVENING_FADE := 8.0  # 낮↔저녁 곡이 시간으로 따라가는 최소 전환 시간(초)
const MUSIC_XF := 4.0      # 같은 곡의 끝→처음을 겹치는 시간(초)
const MAX_VOICES := 32
## 자주 반복되는 바탕 소리: 알림음을 막는 "방금 소리가 났다" 판단에서 뺀다.
const AMBIENT := ["chop", "witch_step", "sheep_bleat", "btn_hover", "card_hover", "shear_loop", "move_click", "gust_soft"]
const DEFAULT_DB := {"magic_bolt": -12.0, "card_play": -10.0, "gold_reward": -10.0, "dragon_arrival": -8.0, "bgm_field": -8.0, "bgm_evening": -8.0, "ambience_day": -18.0, "ambience_evening": -18.0,
	"card_draw": -10.0, "card_pickup": -12.0, "card_target": -12.0, "card_cancel": -12.0, "card_deny": -10.0, "card_stash": -11.0, "card_shuffle": -12.0, "card_inspect": -11.0}
## 배경음은 게임이 멈춰도 끄지 않는다. 산장 메뉴(실내)에서는 살짝 줄이며 고음을 깎아 벽 너머처럼,
## 대화·창고·판매 창·Esc 메뉴 등 그 밖의 정지 화면에서는 음량만 잠시 낮춘다.
const BG_BUS := "Background"
const ROOM_DB := -6.0
const DUCK_DB := -9.0
const ROOM_CUTOFF := 1600.0
const OPEN_CUTOFF := 20000.0
const ROOM_FADE := 0.35
## 플레이어 음량 설정(일시 정지 → 소리 설정). 배경 버스(Background, 실내 감쇠용)는 Music 버스로 보내고,
## 효과음·반복음은 Sfx 버스로 보낸다. 음량은 0~1 선형 값으로 user://settings.cfg [audio] 에 저장된다.
const MUSIC_BUS := "Music"
const SFX_BUS := "Sfx"
const VOLUME_KEYS := ["master", "music", "sfx"]
const SETTINGS_PATH := "user://settings.cfg"
var settings_path := SETTINGS_PATH  # 검증에서는 다른 파일을 쓴다
var volumes := {"master": 1.0, "music": 1.0, "sfx": 1.0}
var muted := false
var game
var room := false
var ducked := false
var _bg_bus := -1
var _bus_db := 0.0
var _cutoff := OPEN_CUTOFF
var _room_tween: Tween
## 산장 관리 메뉴 안의 손님 생활 앰비언스(lodge_ambience): 메뉴가 열린 동안 반복, 게임이 멈춰도 흐른다.
const ROOM_AMB_IN := 1.2
const ROOM_AMB_OUT := 0.6
var _room_amb: AudioStreamPlayer
var _room_amb_tween: Tween
## 바탕음 위에 둘이 나누는 짧은 웃음(lodge_laugh_small)·단체 웃음(lodge_laugh)·건배(lodge_toast)를 3~8초마다 무작위로 얹는다(같은 반복이 매번 달리 들리게).
const ROOM_LIFE := [["lodge_laugh_small", 0.45], ["lodge_laugh", 0.25], ["lodge_toast", 0.30]]
const ROOM_LIFE_GAP := Vector2(3.0, 8.0)
var _room_life: Timer
var background_players: Dictionary = {}
var streams: Dictionary = {}
var gains: Dictionary = {}
var cursors: Dictionary = {}
var last_play: Dictionary = {}
var revision := ""
var elapsed := 0.0
var config_path := ""
var last_event := ""
var play_count := 0
var last_any_ms := -100000
var history: Array = []  # 재생된 이벤트 기록(검증용)
var combat_mix := 0.0
var boss_mix := 0.0       # 니벨라 보스 곡 섞기(0~1): world.boss_room.wants_music()
var evening_mix := -1.0
var _decks: Dictionary = {}  # 음악 이벤트 → 번갈아 쓰는 플레이어 두 개
var _field_day := -1
## 반복음: 주인(id)마다 하나. 주인이 매 프레임 loop() 로 0~1 무게를 알려 주고, 끊기면 서서히 사라진다.
var loops: Dictionary = {}  # id → {player, event, weight, seen}

func _ready() -> void:
	name = "SoundBank"
	config_path = "res://assets/audio/selected.json"
	var sidecar := OS.get_executable_path().get_base_dir().path_join("audio/selected.json")
	if FileAccess.file_exists(sidecar): config_path = sidecar
	_ensure_bus()
	load_settings()
	reload_selection()
	# 모든 버튼에 클릭·오버·불가 소리를 단다(지금 있는 것과 이후에 생기는 것 모두)
	get_tree().node_added.connect(_hook_button)
	_hook_tree.call_deferred(get_tree().root)

func _ensure_bus() -> void:
	for n in [MUSIC_BUS, SFX_BUS]:
		if AudioServer.get_bus_index(n) != -1: continue
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, n)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_bg_bus = AudioServer.get_bus_index(BG_BUS)
	if _bg_bus != -1: return
	AudioServer.add_bus()
	_bg_bus = AudioServer.bus_count - 1
	AudioServer.set_bus_name(_bg_bus, BG_BUS)
	AudioServer.set_bus_send(_bg_bus, MUSIC_BUS)
	var lowpass := AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = OPEN_CUTOFF
	lowpass.resonance = 0.5
	AudioServer.add_bus_effect(_bg_bus, lowpass)

## 음량(0~1)을 바꾸고 저장한다. kind: master·music·sfx
func set_volume(kind: String, value: float, save := true) -> void:
	if not kind in VOLUME_KEYS: return
	volumes[kind] = clampf(value, 0.0, 1.0)
	_apply_volumes()
	if save: save_settings()

func set_muted(on: bool, save := true) -> void:
	muted = on
	_apply_volumes()
	if save: save_settings()

func _apply_volumes() -> void:
	var buses := {"master": "Master", "music": MUSIC_BUS, "sfx": SFX_BUS}
	for kind in VOLUME_KEYS:
		var i := AudioServer.get_bus_index(buses[kind])
		if i == -1: continue
		var v: float = volumes[kind]
		AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(i, v <= 0.001 or (muted and kind == "master"))

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(settings_path) == OK:
		for kind in VOLUME_KEYS:
			volumes[kind] = clampf(float(cfg.get_value("audio", kind, 1.0)), 0.0, 1.0)
		muted = bool(cfg.get_value("audio", "muted", false))
	_apply_volumes()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)  # 다른 구역의 설정은 그대로 둔다
	for kind in VOLUME_KEYS:
		cfg.set_value("audio", kind, volumes[kind])
	cfg.set_value("audio", "muted", muted)
	cfg.save(settings_path)

## 산장 메뉴가 열려 있는지(room), 그 밖의 이유로 화면이 멈췄는지(duck)를 hud.refresh_pause가 매번 알려 준다.
func set_room(on: bool, duck := false) -> void:
	if on == room and duck == ducked: return
	if on != room: _room_ambience(on)
	room = on
	ducked = duck
	var to_db := ROOM_DB if room else (DUCK_DB if ducked else 0.0)
	var to_cutoff := ROOM_CUTOFF if room else OPEN_CUTOFF
	if _room_tween != null and _room_tween.is_valid(): _room_tween.kill()
	_room_tween = create_tween()
	_room_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_room_tween.tween_method(_apply_mix.bind(_bus_db, to_db, _cutoff, to_cutoff), 0.0, 1.0, ROOM_FADE).set_trans(Tween.TRANS_SINE)

func _room_ambience(on: bool) -> void:
	if not streams.has("lodge_ambience") or streams["lodge_ambience"].is_empty(): return
	if _room_amb == null:
		var stream: AudioStream = (streams["lodge_ambience"][0] as AudioStream).duplicate()
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		elif stream is AudioStreamMP3:
			stream.loop = true
		_room_amb = AudioStreamPlayer.new()
		_room_amb.stream = stream
		_room_amb.bus = SFX_BUS
		_room_amb.volume_db = -60.0
		_room_amb.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(_room_amb)
	if _room_amb_tween != null and _room_amb_tween.is_valid(): _room_amb_tween.kill()
	if on and not _room_amb.playing:
		_room_amb.volume_db = -60.0
		_room_amb.play(randf() * _room_amb.stream.get_length())
		if history.size() < 4000: history.append("lodge_ambience")
	_room_amb_tween = create_tween()
	_room_amb_tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	_room_amb_tween.tween_property(_room_amb, "volume_db", gains.get("lodge_ambience", -12.0) if on else -60.0, ROOM_AMB_IN if on else ROOM_AMB_OUT).set_trans(Tween.TRANS_SINE)
	if not on:
		_room_amb_tween.tween_callback(_room_amb.stop)
	_room_life_timer(on)


func _room_life_timer(on: bool) -> void:
	if _room_life == null:
		_room_life = Timer.new()
		_room_life.one_shot = true
		_room_life.process_mode = Node.PROCESS_MODE_ALWAYS
		_room_life.timeout.connect(_room_life_tick)
		add_child(_room_life)
	if on:
		_room_life.start(randf_range(1.5, 3.0))
	else:
		_room_life.stop()


func _room_life_tick() -> void:
	if not room: return
	var r := randf()
	for pair in ROOM_LIFE:
		r -= float(pair[1])
		if r <= 0.0 or pair == ROOM_LIFE.back():
			play(pair[0])
			break
	_room_life.start(randf_range(ROOM_LIFE_GAP.x, ROOM_LIFE_GAP.y))


func _apply_mix(t: float, from_db: float, to_db: float, from_cutoff: float, to_cutoff: float) -> void:
	_bus_db = lerpf(from_db, to_db, t)
	# 차단 주파수는 귀에 고르게 들리도록 로그 간격으로 옮긴다.
	_cutoff = exp(lerpf(log(from_cutoff), log(to_cutoff), t))
	AudioServer.set_bus_volume_db(_bg_bus, _bus_db)
	(AudioServer.get_bus_effect(_bg_bus, 0) as AudioEffectLowPassFilter).cutoff_hz = _cutoff

func _process(delta: float) -> void:
	delta = preload("res://scripts/ui/hand_focus_time.gd").ui_delta(delta)   # 손패 고민 시간으로 세상이 늦춰져도 소리 페이드는 실제 시간으로
	_step_loops(delta)
	elapsed += delta
	if elapsed >= 1.0:
		elapsed = 0.0
		reload_selection()
	if game != null and game.world != null and game.world.day_cycle != null:
		update_background(game.world.day_cycle.progress)

func reload_selection() -> void:
	if not FileAccess.file_exists(config_path): return
	var text := FileAccess.get_file_as_string(config_path)
	if text == revision: return
	var parsed = JSON.parse_string(text)
	if not parsed is Dictionary or not parsed.has("sounds") or not parsed["sounds"] is Dictionary: return
	var next_streams := {}
	var next_gains := {}
	for event in parsed["sounds"].keys():
		var entry = parsed["sounds"][event]
		if not event is String or not entry is Dictionary or not event.is_valid_ascii_identifier(): continue
		var loaded: Array[AudioStream] = []
		# 파일별 음량 보정(trim_db: {파일: dB}) — 같은 이벤트의 곡끼리 크기를 맞춘다
		var trims = entry.get("trim_db", {})
		# 파일별 재생 비율(weights: {파일: 무게}) — 있으면 원샷을 순서 대신 무게대로 무작위로 고른다
		var weights = entry.get("weights", {})
		# seamless: 끝과 처음이 이어지게 만든 곡 — 끝→처음을 겹치지 않고 엔진 반복으로 그대로 돈다
		var seamless: bool = bool(entry.get("seamless", false))
		for filename in entry.get("files", []):
			if not filename is String or filename != filename.get_file() or filename.get_extension() not in ["mp3", "wav"]: continue
			var path: String = config_path.get_base_dir().path_join(filename)
			var stream: AudioStream
			# PCK에서는 원본 오디오 대신 import remap만 있을 수 있다. 외부 선택 파일은 기존 로더를 유지한다.
			if not FileAccess.file_exists(path):
				if ResourceLoader.exists(path): stream = load(path) as AudioStream
			elif filename.ends_with(".mp3"):
				var mp3 := AudioStreamMP3.new()
				mp3.data = FileAccess.get_file_as_bytes(path)
				stream = mp3
			else:
				stream = AudioStreamWAV.load_from_file(path)
			if stream != null and stream.get_length() > 0.0:
				if trims is Dictionary and trims.has(filename): stream.set_meta("trim_db", clampf(float(trims[filename]), -24.0, 12.0))
				if weights is Dictionary and weights.has(filename): stream.set_meta("weight", maxf(float(weights[filename]), 0.0))
				if seamless: stream.set_meta("seamless", true)
				loaded.append(stream)
		if loaded.is_empty(): continue
		next_streams[event] = loaded
		next_gains[event] = clampf(float(entry.get("volume_db", DEFAULT_DB.get(event, -10.0))), -30.0, 0.0)
	streams = next_streams
	gains = next_gains
	cursors.clear()
	revision = text
	background_players.clear()
	_decks.clear()
	_field_day = -1
	evening_mix = -1.0
	loops.clear()
	for child in get_children(): child.queue_free()

## 배경음악·환경음.
## 음악(bgm_*)은 이벤트마다 플레이어 두 개를 번갈아 쓴다: 곡이 끝나기 MUSIC_XF초 전에 다음 회차를 처음부터 겹쳐
## 틀어 끝→처음이 툭 끊기지 않는다. 곡 사이 전환은 사인·코사인(동등 전력) 곡선이라 겹치는 동안 전체 음량이 꺼지지 않는다.
## 낮 곡(bgm_field)에 파일이 여럿이면 새 날마다 그중 하나를 무작위로, 낮 곡이 들리지 않는 동안(밤) 바꾼다.
func update_background(progress: float, step := -1.0) -> void:
	var dt: float = step if step >= 0.0 else get_process_delta_time()  # 검증에서는 고정 시간 간격을 넘긴다
	var target_e := smoothstep(0.58, 0.82, progress)
	# 새벽에 하루 진행도가 0으로 돌아가도 저녁 곡이 한 번에 끊기지 않도록 시간으로 따라간다
	evening_mix = target_e if evening_mix < 0.0 else move_toward(evening_mix, target_e, dt / EVENING_FADE)
	var fighting: bool = game.session != null and game.session.state in [1, 2] and streams.has("bgm_combat")
	var was := combat_mix
	combat_mix = move_toward(combat_mix, 1.0 if fighting else 0.0, dt / (COMBAT_IN if fighting else COMBAT_OUT))
	if was <= 0.0 and combat_mix > 0.0:
		_pick_random_deck("bgm_combat")  # 전투 곡은 시작할 때마다 여러 곡 중 하나를 무작위로, 처음부터
	# 니벨라 보스: 둥지에서 등장 연출이 시작되면 빠르게, 나가거나 쓰러뜨리면 천천히 원래 곡으로
	var br = game.world.get("boss_room") if game.get("world") != null and game.world != null else null
	var boss_on: bool = streams.has("bgm_boss") and br != null and br.has_method("wants_music") and br.wants_music()
	var was_boss := boss_mix
	boss_mix = move_toward(boss_mix, 1.0 if boss_on else 0.0, dt / (BOSS_IN if boss_on else BOSS_OUT))
	if was_boss <= 0.0 and boss_mix > 0.0:
		_pick_random_deck("bgm_boss")  # 들어갈 때마다 처음부터
	var outside_boss := cos(boss_mix * PI * 0.5)
	var e: float = evening_mix if streams.has("bgm_evening") else 0.0
	var rest := cos(combat_mix * PI * 0.5) * outside_boss
	var weights := {
		"bgm_field": rest * cos(e * PI * 0.5),
		"bgm_evening": rest * sin(e * PI * 0.5),
		"bgm_combat": sin(combat_mix * PI * 0.5) * outside_boss,
		"bgm_boss": sin(boss_mix * PI * 0.5),
	}
	# 낮 곡 고르기: 처음 한 번, 그 뒤로는 날이 바뀌었고 낮 곡이 거의 안 들릴 때
	var day: int = game.session.day() if game.session != null and game.session.has_method("day") else 0
	if streams.has("bgm_field") and (not _decks.has("bgm_field") or (day != _field_day and weights["bgm_field"] < 0.02)):
		var options: Array = streams["bgm_field"]
		var pick: AudioStream = options[randi() % options.size()]
		if not _decks.has("bgm_field") or _decks["bgm_field"]["stream"] != pick or options.size() == 1:
			_set_deck_stream("bgm_field", pick)
		_field_day = day
	for ev in weights:
		_music(ev, weights[ev], dt)
	# 환경음: 엔진 반복 재생, 낮·저녁만 섞는다
	var has_evening_amb: bool = streams.has("ambience_evening")
	for i in 2:
		var event: String = ["ambience_day", "ambience_evening"][i]
		if not streams.has(event): continue
		if not background_players.has(event):
			var stream: AudioStream = streams[event][0]
			if stream is AudioStreamMP3:
				stream.loop = true
			elif stream is AudioStreamWAV:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
			var player := _bg_player(event)
			player.stream = stream
			player.play()
			background_players[event] = player
			if history.size() < 4000: history.append(event)
		var weight: float = evening_mix if i == 1 else (1.0 - evening_mix if has_evening_amb else 1.0)
		background_players[event].volume_db = gains[event] + linear_to_db(maxf(weight, 0.0001))

func _bg_player(n: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	p.volume_db = -80.0
	p.bus = BG_BUS
	p.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(p)
	return p

func _deck(event: String) -> Dictionary:
	if not _decks.has(event):
		_decks[event] = {"a": _bg_player(event + "_a"), "b": _bg_player(event + "_b"), "cur": "a", "stream": null, "xf": 0.0}
	return _decks[event]

## 덱의 곡을 바꾸고 처음부터 튼다(끝에서 직접 겹치므로 엔진 반복은 끈다).
func _set_deck_stream(event: String, stream: AudioStream) -> void:
	var d := _deck(event)
	var seamless: bool = stream.get_meta("seamless", false)
	if stream is AudioStreamMP3:
		stream.loop = seamless
	elif stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD if seamless else AudioStreamWAV.LOOP_DISABLED
		if seamless:
			stream.loop_begin = 0
			stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
	d["stream"] = stream
	for k in ["a", "b"]:
		d[k].stop()
		d[k].stream = stream
	d["cur"] = "a"
	d["xf"] = 0.0
	d["a"].play(0.0)
	if history.size() < 4000: history.append(event)

## 이벤트에 곡이 여럿이면 직전 곡과 다른 곡을 무작위로 골라 처음부터 튼다(한 곡이면 그 곡을 다시 처음부터).
func _pick_random_deck(event: String) -> void:
	if not streams.has(event): return
	var options: Array = streams[event]
	var current: AudioStream = _decks[event]["stream"] if _decks.has(event) else null
	var pick: AudioStream = options[randi() % options.size()]
	if options.size() > 1 and pick == current:
		pick = options[(options.find(pick) + 1 + randi() % (options.size() - 1)) % options.size()]
	_set_deck_stream(event, pick)

func _music(event: String, weight: float, dt: float) -> void:
	if not streams.has(event): return
	var d := _deck(event)
	if d["stream"] == null:
		_set_deck_stream(event, streams[event][0])
	var cur: AudioStreamPlayer = d[d["cur"]]
	var nxt: AudioStreamPlayer = d["b" if d["cur"] == "a" else "a"]
	var length: float = (d["stream"] as AudioStream).get_length()
	var xf := minf(MUSIC_XF, length * 0.25)
	var seamless: bool = (d["stream"] as AudioStream).get_meta("seamless", false)
	if not seamless and d["xf"] <= 0.0 and cur.playing and cur.get_playback_position() >= length - xf:
		nxt.play(0.0)
		d["xf"] = 0.0001
	elif d["xf"] <= 0.0 and not cur.playing:
		cur.play(0.0)  # 정지 화면 동안 끝까지 갔으면 다시 처음부터
	var t_cur := 1.0
	var t_nxt := 0.0
	if d["xf"] > 0.0:
		d["xf"] += dt
		var u := clampf(d["xf"] / xf, 0.0, 1.0)
		t_cur = cos(u * PI * 0.5)
		t_nxt = sin(u * PI * 0.5)
		if u >= 1.0:
			cur.stop()
			d["cur"] = "b" if d["cur"] == "a" else "a"
			d["xf"] = 0.0
	var g: float = gains[event] + float((d["stream"] as AudioStream).get_meta("trim_db", 0.0))
	cur.volume_db = g + linear_to_db(maxf(weight * t_cur, 0.0001))
	nxt.volume_db = g + linear_to_db(maxf(weight * t_nxt, 0.0001))

## 새 전용 효과음이 아직 선택되지 않았으면 예전부터 쓰던 소리로 대신한다.
func play_or(event: String, fallback: String) -> bool:
	if streams.has(event) and not streams[event].is_empty(): return play(event)
	return play(fallback)


## 손님 인물 목소리(심즈풍 "흐음~ 아하~"). 인물 id 마다 voice_<id> 이벤트, 없으면 fallback.
func voice(profile: Dictionary, fallback := "") -> bool:
	var id := str(profile.get("character_id", profile.get("id", "")))
	if id != "" and streams.has("voice_" + id) and not streams["voice_" + id].is_empty(): return play("voice_" + id)
	return fallback != "" and play(fallback)


func play(event: String) -> bool:
	if event in BACKGROUND: return false
	# 게임이 멈춘 동안에도 소리를 낼 수 있다. 정지 중에는 월드가 돌지 않아 호출하는 곳이
	# 산장 상점·판매·창고·대화 창과 승패 화면 같은 UI 뿐이고, 그 소리가 막히면 안 된다.
	if not streams.has(event) or streams[event].is_empty(): return false
	var now := Time.get_ticks_msec()
	if now - int(last_play.get(event, -10000)) < 100 or get_child_count() >= MAX_VOICES: return false
	var variants: Array = streams[event]
	var index := _pick_variant(event, variants)
	var player := AudioStreamPlayer.new()
	player.stream = variants[index]
	player.volume_db = gains[event] + float((variants[index] as AudioStream).get_meta("trim_db", 0.0))
	player.bus = SFX_BUS
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	player.finished.connect(player.queue_free)
	player.play()
	last_play[event] = now
	last_event = event
	if not event in AMBIENT: last_any_ms = now
	if history.size() < 4000: history.append(event)
	play_count += 1
	return true

## 원샷 파일 고르기: 무게(weight)가 있으면 무게대로 무작위, 없으면 순서대로 돌아가며.
func _pick_variant(event: String, variants: Array) -> int:
	var total := 0.0
	for s in variants: total += float((s as AudioStream).get_meta("weight", 0.0))
	if total <= 0.0:
		var i := int(cursors.get(event, 0)) % variants.size()
		cursors[event] = i + 1
		return i
	var r := randf() * total
	for i in variants.size():
		r -= float((variants[i] as AudioStream).get_meta("weight", 0.0))
		if r <= 0.0: return i
	return variants.size() - 1

## 반복음 갱신: 주인이 매 프레임 호출한다. weight 0이면 사라진다. 반환값은 실제로 재생 중인지.
func loop(id: String, event: String, weight: float) -> bool:
	if not streams.has(event): return false
	var l: Dictionary = loops.get(id, {})
	if l.is_empty():
		if weight <= 0.01: return false
		var stream: AudioStream = (streams[event][0] as AudioStream).duplicate()
		if stream is AudioStreamWAV:
			stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream.loop_end = int(round(stream.get_length() * stream.mix_rate))
		elif stream is AudioStreamMP3:
			stream.loop = true
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.volume_db = -60.0
		player.bus = SFX_BUS
		add_child(player)
		player.play(randf() * stream.get_length())
		l = {"player": player, "event": event, "weight": 0.0, "target": 0.0}
		if history.size() < 4000: history.append(event)
		loops[id] = l
	l["target"] = clampf(weight, 0.0, 1.0)
	l["seen"] = Time.get_ticks_msec()
	return true

func _step_loops(delta: float) -> void:
	var now := Time.get_ticks_msec()
	for id in loops.keys():
		var l: Dictionary = loops[id]
		# 주인이 0.3초 넘게 소식이 없으면(사라졌거나 멈춤) 끄기로 본다
		var target: float = l["target"] if now - int(l["seen"]) < 300 else 0.0
		l["weight"] = move_toward(l["weight"], target, delta * 2.5)
		var p: AudioStreamPlayer = l["player"]
		if not is_instance_valid(p):
			loops.erase(id)
			continue
		p.volume_db = gains.get(l["event"], -10.0) + linear_to_db(maxf(l["weight"], 0.0001))
		if l["weight"] <= 0.001 and target <= 0.0:
			p.queue_free()
			loops.erase(id)

## 마지막 효과음 뒤로 ms 이상 조용했는지(알림음이 사건 소리와 겹치지 않게).
func quiet_for(ms: int) -> bool:
	return Time.get_ticks_msec() - last_any_ms >= ms

func _hook_tree(n: Node) -> void:
	_hook_button(n)
	for c in n.get_children():
		_hook_tree(c)

## 버튼(기본 BaseButton·달빛 MoonButton): 누르면 클릭, 올리면 오버, 비활성일 때 누르면 불가.
func _hook_button(n: Node) -> void:
	if not (n is Control) or not n.has_signal("pressed") or not ("disabled" in n) or n.has_meta("sfx_hooked"):
		return
	n.set_meta("sfx_hooked", true)
	n.pressed.connect(func(): play("btn_click"))
	n.mouse_entered.connect(func():
		if not n.disabled:
			play("btn_hover"))
	n.gui_input.connect(func(e: InputEvent):
		var mb := e as InputEventMouseButton
		if mb != null and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and n.disabled:
			play("btn_denied"))
