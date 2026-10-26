extends RefCounted
## 손님 초상 셰이더 모션(shaders/guest_portrait_motion.gdshader)의 인물별 값. docs/portrait-motion-all.md
## 에린에 쓴 숨·몸 흔들림·고개 아이들링을 모든 손님에게 켠다(사용자 요청 2026-10-23). 가슴 모핑은 에린만.
## 머리 중심은 tools/portrait_grid_sheet.gd 격자 시트에서 얼굴 중심을 읽은 원화 UV(1122×1402).

## 셰이더 uniform 기본값. 손님이 바뀌면 이 값으로 되돌린 뒤 그 손님 값을 얹는다(앞 손님 값이 남지 않게).
const DEFAULTS := {
	"idle": 0.0, "chest": 0.0, "motion_phase": 0.0,
	"breath_rate": 1.8, "breath_amount": 1.0, "sway_amount": 1.0, "sway_rate": 1.0, "head_amount": 1.0,
	"head_center": Vector2(0.55, 0.16), "head_radius": 0.17,
	"chest_center": Vector2(0.40, 0.36), "chest_radius": Vector2(0.15, 0.11),
	"chest_freq": 9.5, "chest_decay": 2.4, "chest_swing": 0.018,
	"accent_amount": 0.0, "accent_center": Vector2(0.5, 0.3), "accent_radius": Vector2(0.4, 0.25),
	"accent_axis": Vector2(1.0, 0.0), "accent_rate": 5.0, "accent_burst": 0.0, "accent_inner": 0.0,
}

const HEADS := {
	"bram": Vector2(0.55, 0.27), "mira": Vector2(0.33, 0.26), "olaf": Vector2(0.55, 0.28), "torbin": Vector2(0.57, 0.23),
	"neri": Vector2(0.48, 0.25), "oswin": Vector2(0.42, 0.25), "sera": Vector2(0.47, 0.20),
	"harald": Vector2(0.52, 0.24), "brynhild": Vector2(0.45, 0.25), "thorgrim": Vector2(0.37, 0.24), "durga": Vector2(0.47, 0.24),
	"ormu": Vector2(0.43, 0.27), "ketil": Vector2(0.53, 0.32), "signy": Vector2(0.40, 0.25),
	"thistle": Vector2(0.55, 0.29), "tilia": Vector2(0.55, 0.27), "larch": Vector2(0.52, 0.28), "fern": Vector2(0.50, 0.23),
	"willow": Vector2(0.45, 0.17), "pip": Vector2(0.45, 0.25), "nivel": Vector2(0.55, 0.31),
	"graz": Vector2(0.65, 0.32), "pikl": Vector2(0.48, 0.29), "rusk": Vector2(0.43, 0.29), "tak": Vector2(0.42, 0.23),
	"nib": Vector2(0.40, 0.24), "grik": Vector2(0.55, 0.27), "mala": Vector2(0.47, 0.27),
	"fargh": Vector2(0.57, 0.23), "saya": Vector2(0.67, 0.23), "urso": Vector2(0.55, 0.23), "momi": Vector2(0.63, 0.27),
	"luka": Vector2(0.57, 0.31), "tass": Vector2(0.62, 0.28), "selen": Vector2(0.55, 0.25),
	"garok": Vector2(0.47, 0.25), "kranya": Vector2(0.55, 0.19), "moga": Vector2(0.60, 0.31), "shaga": Vector2(0.50, 0.25),
	"ulma": Vector2(0.53, 0.25), "bardu": Vector2(0.57, 0.23), "eshka": Vector2(0.48, 0.23),
}

## 종족 성격: 드워프는 묵직하게 덜 흔들리고, 요정은 가볍게 떠 있으며 날개를 파닥이고,
## 고블린은 부산하게 고개를 까딱이며 귀를 씰룩이고, 수인은 귀를 쫑긋 세우고, 오크는 크고 느리게 숨쉰다.
const RACE_STYLE := {
	"human": {},
	"dwarf": {"breath_rate": 1.5, "breath_amount": 1.15, "sway_amount": 0.6, "sway_rate": 0.85, "head_amount": 0.8},
	"fairy": {"breath_rate": 2.1, "breath_amount": 0.8, "sway_amount": 1.3, "sway_rate": 1.2,
		"accent": "wings", "accent_amount": 0.10, "accent_rate": 4.2, "accent_burst": 0.0},
	"goblin": {"breath_rate": 2.4, "sway_amount": 0.9, "sway_rate": 1.6, "head_amount": 1.5,
		"accent": "side_ears", "accent_amount": 0.16, "accent_rate": 22.0, "accent_burst": 1.0},
	"beastfolk": {"breath_rate": 1.7, "breath_amount": 1.1, "sway_amount": 0.8, "head_amount": 1.2,
		"accent": "top_ears", "accent_amount": 0.30, "accent_rate": 20.0, "accent_burst": 1.0},
	"orc": {"breath_rate": 1.35, "breath_amount": 1.35, "sway_amount": 0.7, "sway_rate": 0.8, "head_amount": 0.9},
}

## 성격에 맞춘 개인 보정: 노인은 느리고 작게, 들뜬 젊은이는 고개를 더.
const PERSON_STYLE := {
	"oswin": {"breath_rate": 1.4, "sway_amount": 0.6, "head_amount": 0.7},
	"durga": {"breath_rate": 1.4, "sway_amount": 0.5},
	"ulma": {"breath_rate": 1.3, "sway_amount": 0.55, "sway_rate": 0.7},
	"torbin": {"sway_amount": 0.7, "head_amount": 0.7},
	"neri": {"sway_rate": 1.3, "head_amount": 1.3},
	"pip": {"sway_rate": 1.5, "head_amount": 1.4, "accent_rate": 5.5},
	"brynhild": {"head_amount": 1.2},
	"willow": {"sway_amount": 1.0, "sway_rate": 0.9, "accent_rate": 3.2},
}


## 프로필 → 셰이더에 실을 모션 값. 프로필에 portrait_motion 이 직접 있으면(에린) 그것이 우선이다.
## 초상이 아직 없는 인물(익명 실루엣)은 움직이지 않는다.
static func for_profile(profile: Dictionary) -> Dictionary:
	if profile.has("portrait_motion"): return profile["portrait_motion"]
	if profile.get("portrait_missing", false): return {}
	var id: String = profile.get("id", "")
	var head: Vector2 = HEADS.get(id, Vector2(0.5, 0.25))
	var m := {"idle": 1.0, "chest": 0.0, "head_center": head, "head_radius": 0.13,
		# 같은 묶음 손님이 같은 박자로 숨쉬지 않게 인물마다 위상을 0~20초로 흩는다
		"motion_phase": float(absi(id.hash()) % 1000) * 0.02}
	var style: Dictionary = RACE_STYLE.get(profile.get("race", "human"), {}).duplicate()
	style.merge(PERSON_STYLE.get(id, {}), true)
	match style.get("accent", ""):
		"wings":  # 몸 뒤 양옆 날개: 얼굴 아래 몸통 중심에서 가로로 펼쳤다 접는다
			m["accent_center"] = Vector2(head.x, head.y + 0.12)
			m["accent_radius"] = Vector2(0.55, 0.32)
			m["accent_axis"] = Vector2(1.0, 0.25)
			m["accent_inner"] = 0.14  # 얼굴·몸통(가운데 약 ±0.1)은 두고 양옆 날개만
		"side_ears":  # 머리 양옆으로 뻗은 고블린 귀: 머리 높이에서 가로로 씰룩
			m["accent_center"] = head
			m["accent_radius"] = Vector2(0.45, 0.11)
			m["accent_axis"] = Vector2(1.0, 0.0)
			m["accent_inner"] = 0.08  # 얼굴은 두고 옆으로 뻗은 귀만
		"top_ears":  # 머리 위 수인 귀: 머리 꼭대기에서 세로로 쫑긋
			m["accent_center"] = head
			m["accent_radius"] = Vector2(0.17, 0.20)
			m["accent_axis"] = Vector2(0.3, 1.0)
			m["accent_inner"] = 0.05  # 얼굴(중심 위 약 0.03까지)은 두고 그 위 귀만
	style.erase("accent")
	m.merge(style, true)
	return m
