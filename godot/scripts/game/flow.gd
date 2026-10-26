extends RefCounted
## 장면 사이의 흐름 상태: 타이틀(scenes/title.tscn) → 마녀 선택 → 게임(scenes/main.tscn) → 다시 도전/타이틀로.
## 장면이 바뀌어도 남아야 하는 값만 정적 변수로 둔다. 저장·이어하기는 아직 없다(첫 실행 플로우 보강 범위 밖).
## 첫 판 튜토리얼을 마쳤는지는 user://ftue.cfg [tutorial] done 에 남긴다(타이틀 설정 '튜토리얼 다시 보기'로 지운다).

const TITLE_SCENE := "res://scenes/title.tscn"
const GAME_SCENE := "res://scenes/main.tscn"
const FTUE_PATH := "user://ftue.cfg"

## 게임 장면이 도입(프롤로그 → 새벽 → 첫째 날 카드 → 시작 손패)을 연다. 타이틀이 켜고 main.gd가 읽으면 끈다.
static var opening := false
## 도입에 프롤로그를 포함한다(다시 도전은 프롤로그 없이 새벽부터).
static var prologue := true
## 프롤로그(모션 코믹스 컷씬) 전체 스위치. 2026-10-20 보류 — 다시 켤 때 true 로 바꾼다.
## 꺼 두면 새 이야기도 새벽부터 연다. 프롤로그를 검사하는 검증 도구는 이 값을 직접 켠다.
static var prologue_enabled := false
## 고른 마녀. 지금은 이름 없는 '마녀' 한 명뿐이고 셋은 잠겨 있다(방위 미정).
static var witch_id := "witch"
## 검증 도구는 사용자 기록을 건드리지 않게 다른 파일을 쓴다.
static var ftue_path := FTUE_PATH


static func start_game(tree: SceneTree, with_prologue := true) -> void:
	opening = true
	prologue = with_prologue
	tree.paused = false
	tree.change_scene_to_file.call_deferred(GAME_SCENE)   # 누른 버튼의 효과음이 먼저 나가게 다음 프레임에 바꾼다


static func to_title(tree: SceneTree) -> void:
	opening = false
	tree.paused = false
	tree.change_scene_to_file.call_deferred(TITLE_SCENE)


## main.gd가 시작할 때 한 번 읽는다(읽은 뒤에는 꺼서, 이어지는 장면 재로드가 의도치 않게 도입을 다시 열지 않게 한다).
static func take_opening() -> bool:
	var on := opening
	opening = false
	return on


static func tutorial_done() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(ftue_path) != OK:
		return false
	return bool(cfg.get_value("tutorial", "done", false))


static func set_tutorial_done(done: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(ftue_path)
	cfg.set_value("tutorial", "done", done)
	cfg.save(ftue_path)
