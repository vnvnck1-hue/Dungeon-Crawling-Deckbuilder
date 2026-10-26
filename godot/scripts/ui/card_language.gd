extends Node
## 카드 언어 프리셋: F8 로 한국어(BM 을지로체) ↔ English(Fraunces + Alegreya, docs/english-font-research-v01.md) 전환.
## 타이틀·게임·일시 정지·메뉴 어디서든 동작한다(F11 과 같은 방식). 이미 보이는 카드도 그 자리에서 새 언어로 다시 구워진다.
## 값은 user://settings.cfg [cards] lang 에 저장되어 다음 실행에 그대로 쓴다.
## 카드 앞면과 함께 HUD·메뉴·툴팁·대사·3D 글자도 같은 언어·글꼴로 바뀐다(game_language.gd).

const CardFace := preload("res://scripts/ui/card_face.gd")
const Catalog := preload("res://scripts/ui/card_catalog.gd")
const GameLanguage := preload("res://scripts/ui/game_language.gd")
const KEY := KEY_F8

var settings_path := CardFace.SETTINGS_PATH   # 검증에서는 다른 파일을 쓴다
var _toast = preload("res://scripts/ui/top_toast.gd").new(150)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameLanguage.apply(CardFace.language())   # 저장된 언어로 시작


func _exit_tree() -> void:
	GameLanguage.release()   # 종료·장면 전환 때 엔진 전역에서 뗀다(다음 장면 _ready 가 다시 붙임)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or key.keycode != KEY:
		return
	toggle()
	get_viewport().set_input_as_handled()


## 다음 언어로. 바꾼 언어 id 를 돌려준다.
func toggle() -> String:
	var langs: Array = CardFace.LANGS
	var next: String = langs[(langs.find(CardFace.language()) + 1) % langs.size()]
	set_language(next)
	return next


func set_language(lang: String, save := true) -> void:
	if not lang in CardFace.LANGS:
		return
	CardFace.set_language(lang)
	GameLanguage.apply(lang)
	if save:
		var cfg := ConfigFile.new()
		cfg.load(settings_path)   # 다른 구역(소리·디스플레이)은 그대로 둔다
		cfg.set_value("cards", "lang", lang)
		cfg.save(settings_path)
	Catalog.rebake_faces()
	_show(("Language: " if lang == "en" else "언어: ") + String(CardFace.LANG_NAMES[lang]) + "  (F8)")


## 화면 위쪽 가운데에 잠깐 뜨는 알림(타이틀 화면에도 HUD 토스트가 없어 따로 둔다).
func _show(text: String) -> void:
	_toast.show_text(self, text)
