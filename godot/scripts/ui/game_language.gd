extends RefCounted
## 게임 전체 언어(F8, card_language.gd): 카드 앞면뿐 아니라 HUD·메뉴·툴팁·대사·3D 글자까지 한국어 ↔ English.
## English 는 ① TranslationServer 에 i18n_translation.gd(원문 한국어 → 영문 사전)를 붙여 locale 을 "en" 으로 두고
## ② UI 글꼴(moon_skin.font)과 엔진 기본 글꼴(ThemeDB.fallback_font)을 Alegreya 로 바꾼다(한글이 남으면 한글 글꼴로 폴백).
## 한국어는 locale "ko"(번역 없음 → 원문)와 원래 글꼴로 되돌린다.

const SkinUI := preload("res://scripts/ui/moon/moon_skin.gd")
const I18nTranslation := preload("res://scripts/ui/i18n_translation.gd")

static var _translation: Translation
static var _engine_font: Font   # 영어로 바꾸기 전 ThemeDB.fallback_font
static var _default_theme_font: Font   # 영어로 바꾸기 전 엔진 기본 테마의 default_font
static var _default_theme_saved := false


static func apply(lang: String) -> void:
	SkinUI.set_language(lang)   # 먼저 — locale 변경 알림을 받는 노드(moon_text_cover)가 새 언어를 읽는다
	if lang == "en":
		if _translation == null:
			_translation = I18nTranslation.new()
		TranslationServer.remove_translation(_translation)   # 두 번 붙지 않게
		TranslationServer.add_translation(_translation)
		TranslationServer.set_locale("en")
		if _engine_font == null:
			_engine_font = ThemeDB.fallback_font
		ThemeDB.fallback_font = SkinUI.font()
		# 달빛 테마 밖의 Control(언어 알림 등)은 엔진 기본 테마 글꼴을 쓴다 — 그것도 바꾼다
		var dt := ThemeDB.get_default_theme()
		if not _default_theme_saved:
			_default_theme_font = dt.default_font
			_default_theme_saved = true
		dt.default_font = SkinUI.font()
	else:
		# 프로젝트 대체 locale 이 en 이라 붙여 두면 한국어에서도 영문으로 옮겨진다 — 떼어 낸다.
		if _translation != null:
			TranslationServer.remove_translation(_translation)
		TranslationServer.set_locale("ko")
		if _engine_font != null:
			ThemeDB.fallback_font = _engine_font
		if _default_theme_saved:
			ThemeDB.get_default_theme().default_font = _default_theme_font


## 엔진 전역(TranslationServer·ThemeDB)에 붙인 스크립트 번역기와 글꼴을 뗀다. 영어 상태로 종료하면 엔진이 정리될 때
## 이미 해제된 스크립트 객체를 건드려 종료 순간 튕긴다(2026-10-20 확인) — card_language.gd 가 장면을 떠날 때 부르고,
## 다음 장면의 card_language 가 _ready 에서 apply 로 다시 붙인다. 언어 값(CardFace.language)은 그대로다.
static func release() -> void:
	if _translation != null:
		TranslationServer.remove_translation(_translation)
	if _engine_font != null:
		ThemeDB.fallback_font = _engine_font
	if _default_theme_saved:
		ThemeDB.get_default_theme().default_font = _default_theme_font


## 지금 언어로 한 문자열을 옮긴다(직접 그리는 draw_string 등 auto translate 를 거치지 않는 곳용).
static func t(s: String) -> String:
	return TranslationServer.translate(s)


static func translation() -> Translation:
	if _translation == null:
		_translation = I18nTranslation.new()
	return _translation
