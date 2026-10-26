extends RefCounted
## 손님 42명의 이름·종족·초상·소개 문구(기획: docs/races-guests-v01.md §3). 고용/정산 규칙은 LodgeEconomy가 소유한다.
## 종족은 Races 등록부의 id이며 직업과 별개의 축이다. 모든 프로필은 `race`를 갖고 `race_name`은 표시용으로 채운다.
const Races := preload("res://scripts/game/races.gd")
const PORTRAITS := "res://assets/portraits/"
const MERC_PORTRAIT := PORTRAITS + "guest_bram_cutout.png"
const HERBALIST_PORTRAIT := PORTRAITS + "guest_mira_cutout.png"
## 포트레이트가 아직 납품되지 않은 인물은 익명 실루엣으로 대신한다(코덱스 납품 즉시 자동으로 본 초상이 뜬다).
const PLACEHOLDER_PORTRAIT := "res://assets/ui/ftue/witch_locked.png"

## 고용 가능 손님의 등장 순서: 종족을 인간→드워프→요정→고블린→수인→오크로 돌고 직업도 전투→사냥→벌목→채집 블록으로 돈다.
## 1일차 첫 손님은 브람(튜토리얼 유지).
const MERCENARIES := [
	"브람", "하랄", "티슬", "그라즈", "파르그", "가로크",
	"올라프", "브륀힐드", "틸리아", "피클", "사야", "크라냐",
	"토르빈", "토르그림", "라르크", "러스크", "우르소", "모가",
	"미라", "두르가", "페른", "타크", "모미", "샤가",
]
## 인물별 고정 직업(기획 §1). 고용하면 이 직업의 계약 카드를 준다.
const JOBS := {
	"브람": "warrior", "올라프": "hunter", "토르빈": "lumberjack", "미라": "gatherer",
	"하랄": "warrior", "브륀힐드": "hunter", "토르그림": "lumberjack", "두르가": "gatherer",
	"티슬": "warrior", "틸리아": "hunter", "라르크": "lumberjack", "페른": "gatherer",
	"그라즈": "warrior", "피클": "hunter", "러스크": "lumberjack", "타크": "gatherer",
	"파르그": "warrior", "사야": "hunter", "우르소": "lumberjack", "모미": "gatherer",
	"가로크": "warrior", "크라냐": "hunter", "모가": "lumberjack", "샤가": "gatherer",
}
## 여행자(숙박만)의 등장 순서. 같은 식으로 종족을 섞는다.
const TRAVELERS := [
	"neri", "ormu", "willow", "nib", "luka", "ulma",
	"oswin", "ketil", "pip", "grik", "tass", "bardu",
	"sera", "signy", "nivel", "mala", "selen", "eshka",
]

## 특별 손님: 무작위 손님 풀(CATALOG)에 들지 않고, 조건이 차면 묶음에 덧붙어 온다(42명 명부와 별개).
## 에린은 술 카드를 몇 장 쓰면 찾아오는 술 주정뱅이(주점 카드 v1, docs/tavern-cards-v01.md).
const SPECIALS := [
	{"id": "erin", "person": "에린", "race": "human", "role": "떠돌이 술꾼", "detail": "누구나 돌아보는 금발 미인, 그런데 늘 취해 있다",
		"tag": "혀 꼬부라진 친근함", "portrait": PORTRAITS + "guest_erin_cutout.png", "hireable": false,
		"dialogue_portrait_scale": 1.06, "dialogue_portrait_rounded_hem": true,
		# 대화 창 초상 모션(shaders/guest_portrait_motion.gdshader): 숨·흔들림·고개 아이들링과 등장 시 가슴 모핑. 좌표는 원화 UV(1122×1402 기준).
		"portrait_motion": {"idle": 1.0, "chest": 1.0, "head_center": Vector2(0.55, 0.16), "head_radius": 0.17,
			"chest_center": Vector2(0.40, 0.36), "chest_radius": Vector2(0.15, 0.11)},
		"lines": ["딸꾹! 여기가… 그 마녀네 술집이지?
아니라고? 에이, 냄새가 이렇게 좋은데.",
			"또 왔지롱! 딸꾹.
술 냄새 따라왔더니 또 여기네.
이 집은 술이 부르는 집이야.",
			"마녀 언니! 나야 나, 에린!
…오늘은 몇 잔째더라. 딸꾹."]},
	# 떠돌이 행상(docs/merchant-shop-v01.md): 사흘마다 낮 한가운데 혼자 와서 좌판을 펼친다. 묵지도 고용되지도 않는다.
	{"id": "brock", "person": "브로크", "race": "beastfolk", "role": "떠돌이 행상", "detail": "사흘마다 같은 숲길을 도는 오소리 수인 장사꾼",
		"tag": "값을 아는 능청", "portrait": PORTRAITS + "guest_brock_cutout.png", "hireable": false,
		"lines": ["사흘에 한 번 이 길을 돌지요.\n짐 좀 풀어도 되겠소, 마녀 양반?",
			"또 뵙소. 이번 꾸러미는\n고개 너머 장터에서 떼 온 것들이오.",
			"값은 정직하게, 물건은 귀하게.\n자, 천천히 구경하시오."]},
]

const CATALOG := [
	# ── 인간 ──────────────────────────────────────────────
	{"id": "bram", "person": "브람", "race": "human", "role": "전투용병", "detail": "북쪽 숲길을 건너온 여행자",
		"tag": "경계 어린 첫인사", "portrait": MERC_PORTRAIT, "hireable": true,
		"lines": ["마녀의 산장에 묵게 되다니…\n기묘한 일이군.",
			"숲에서 이상한 소리가 들리더군.\n오늘 밤은 지붕 아래서 쉬고 싶소.",
			"소문은 소문일 뿐이지.\n따뜻한 침대 하나면 충분하오."]},
	{"id": "mira", "person": "미라", "race": "human", "role": "채집가", "detail": "숲에서 약초와 쓸 만한 것을 찾는 여행자",
		"tag": "따뜻한 잠자리를 찾아", "portrait": HERBALIST_PORTRAIT, "hireable": true,
		"lines": ["창문 불빛이 보여서\n얼마나 반가웠는지 몰라요.\n오늘 밤, 잘 부탁합니다.",
			"숲에서는 이름을 불러도\n돌아보지 말라던데…\n여기서는 쉬어도 되겠죠?",
			"또 신세를 지게 됐네요.\n이곳의 따뜻한 차가 생각났어요."]},
	{"id": "olaf", "person": "올라프", "race": "human", "role": "사냥꾼", "detail": "교역 마차를 호위해 온 용병",
		"tag": "무뚝뚝한 안도", "portrait": PORTRAITS + "guest_olaf_cutout.png", "hireable": true,
		"lines": ["마녀든 누구든 상관없소.\n불이 켜진 집이면 됐지.\n따뜻한 수프도 있겠지?",
			"길목에 발자국이 있었소.\n들어간 자국만 있더군.",
			"그 수프가 생각나서 왔소.\n방 하나 비어 있겠지?"]},
	{"id": "torbin", "person": "토르빈", "race": "human", "role": "나무꾼", "detail": "오래된 산길을 아는 호위꾼",
		"tag": "말수 적은 경계", "portrait": PORTRAITS + "guest_torbin_cutout.png", "hireable": true,
		"lines": ["문이 튼튼하군.\n오늘 밤은 푹 잘 수 있겠어.",
			"숲에서 종소리를 들었소.\n이 근처에 성당은 없을 텐데.",
			"오늘도 같은 방을 부탁하오.\n창문에서 먼 쪽이면 좋겠군."]},
	{"id": "neri", "person": "네리", "race": "human", "role": "숲길 전령", "detail": "눈 덮인 고개를 넘는 편지 배달부",
		"tag": "겁을 감춘 호기심", "portrait": PORTRAITS + "guest_neri_cutout.png", "hireable": false,
		"lines": ["여기가 그 마녀의 산장이에요?\n생각보다 아늑하네요!\n하룻밤 잘 부탁해요.",
			"숲에서 누가 제 이름을 불렀어요.\n편지 받을 사람은 아니었는데…",
			"오늘은 길을 안 잃었어요!\n굴뚝 연기를 따라왔거든요."]},
	{"id": "oswin", "person": "오스윈", "race": "human", "role": "유적 기록가", "detail": "숲의 옛 문양을 찾아다니는 학자",
		"tag": "조용한 탐구심", "portrait": PORTRAITS + "guest_oswin_cutout.png", "hireable": false,
		"lines": ["마녀가 내어 주는 잠자리라…\n기록할 이야기가 늘겠군요.",
			"폐허에서 같은 문양을 봤지요.\n그런데 올 때와 갈 때가 달랐소.",
			"이번에는 잉크를 넉넉히 챙겼소.\n숲이 자꾸 이야기를 늘려서요."]},
	{"id": "sera", "person": "세라", "race": "human", "role": "떠돌이 교역상", "detail": "마을과 산길 사이를 오가는 상인",
		"tag": "실속 있는 친절", "portrait": PORTRAITS + "guest_sera_cutout.png", "hireable": false,
		"lines": ["소문보다 창문 불빛을 믿어요.\n방 하나 부탁할게요.\n값은 제대로 치를게요.",
			"이상하죠? 숲을 나서면\n가져온 물건이 하나씩 늘어요.",
			"오늘도 불이 켜져 있네요.\n장사 끝에 이보다 반가운 게 없죠."]},

	# ── 드워프 ────────────────────────────────────────────
	{"id": "harald", "person": "하랄", "race": "dwarf", "role": "전투용병", "detail": "광산 경비로 늙은 퇴역 드워프",
		"tag": "돌벽을 두드리는 신중함", "portrait": PORTRAITS + "guest_harald_cutout.png", "hireable": true,
		"lines": ["벽부터 두드려 보지.\n…음, 속이 찼군.\n마녀 집치곤 제대로 지었어.",
			"밖의 것들은 벽을 못 넘어.\n넘는 건 문이지.\n문 옆에 자리를 주게.",
			"또 왔네. 지붕 들보가\n한 치도 안 처졌군.\n그게 내 숙박비 값이야."]},
	{"id": "brynhild", "person": "브륀힐드", "race": "dwarf", "role": "사냥꾼", "detail": "석궁 한 자루로 산을 넘는 드워프",
		"tag": "내기를 거는 호탕함", "portrait": PORTRAITS + "guest_brynhild_cutout.png", "hireable": true,
		"lines": ["내기 하나 하지, 마녀!\n오늘 밤 내가 먼저 자나\n숲이 먼저 조용해지나.",
			"동전 하나 걸고 말하지.\n저 숲엔 다리 여덟 달린 게 있어.\n…맞혔지? 자, 술 사.",
			"또 왔다! 저번 내기는\n내가 졌으니 숙박비는 두 배.\n드워프는 빚을 안 남겨."]},
	{"id": "thorgrim", "person": "토르그림", "race": "dwarf", "role": "나무꾼", "detail": "갱목을 짜던 목수, 이제는 벌목꾼",
		"tag": "나무결을 읽는 눈", "portrait": PORTRAITS + "guest_thorgrim_cutout.png", "hireable": true,
		"lines": ["문짝… 참나무군.\n결을 거슬러 깎았어.\n그래도 쓸 만해.",
			"이 숲 나무는 결이 꼬였소.\n뭔가에 눌리며 자란 거지.\n베기 전에 먼저 들어 봐야 해.",
			"저번에 본 들보 말이오.\n쐐기 하나면 백 년은 가.\n내일 아침에 박아 주지."]},
	{"id": "durga", "person": "두르가", "race": "dwarf", "role": "채집가", "detail": "이끼와 광석을 함께 캐는 드워프 노파",
		"tag": "투덜거리는 돌봄", "portrait": PORTRAITS + "guest_durga_cutout.png", "hireable": true,
		"lines": ["차가 식었잖니.\n…아니, 내가 데우마.\n너는 문이나 잘 잠그고.",
			"창턱 이끼는 왜 안 긁어?\n약으로 쓰면 좋은 건데.\n쯧, 내가 긁어 두마.",
			"또 그 얼굴이구나.\n밤새 안 잤지?\n수프 먹고 앉아 있어."]},
	{"id": "ormu", "person": "오르무", "race": "dwarf", "role": "유적 조사자", "detail": "돌에 새긴 것만 믿는 드워프",
		"tag": "기록보다 돌을 믿는", "portrait": PORTRAITS + "guest_ormu_cutout.png", "hireable": false,
		"lines": ["이 산장 주춧돌…\n사람 손으로 깎은 게 아니군.\n하룻밤 묵으며 살펴보겠소.",
			"종이에 적은 건 믿지 않소.\n돌에 새긴 것만 남지.\n지하에 뭐가 있소?",
			"또 왔소. 그 돌이\n지난번보다 따뜻해졌더군.\n돌은 거짓말을 안 하오."]},
	{"id": "ketil", "person": "케틸", "race": "dwarf", "role": "떠돌이 대장장이", "detail": "모루를 등에 지고 다니는 드워프",
		"tag": "말보다 망치", "portrait": PORTRAITS + "guest_ketil_cutout.png", "hireable": false,
		"lines": ["…방.\n경첩 소리가 나는군.\n아침에 고쳐 주지.",
			"문고리를 바꿨소.\n값은 안 받소.\n잠이 편했으니까.",
			"…또 왔소.\n도끼 날이 무뎌졌더군.\n갈아 두었소."]},
	{"id": "signy", "person": "시그뉘", "race": "dwarf", "role": "양조사", "detail": "술통을 메고 산을 넘는 드워프",
		"tag": "맥주 거품 같은 웃음", "portrait": PORTRAITS + "guest_signy_cutout.png", "hireable": false,
		"lines": ["마녀의 산장!\n술 얘기는 많이 들었어요.\n…아, 없다고요? 제가 있죠!",
			"숲에서 노래를 들었는데\n제 노래보다 음이 낮더라고요.\n한 잔 하고 잊을래요.",
			"지난번 통은 비었어요?\n이번 건 더 진해요.\n굴뚝 연기 보고 달려왔죠."]},

	# ── 요정 ──────────────────────────────────────────────
	{"id": "thistle", "person": "티슬", "race": "fairy", "role": "전투용병", "detail": "엉겅퀴 창을 든 작은 수호자",
		"tag": "작은 몸의 큰 격식", "portrait": PORTRAITS + "guest_thistle_cutout.png", "hireable": true,
		"lines": ["숲의 수호자 티슬,\n산장의 주인께 예를 갖춥니다.\n창은 문 옆에 세워 두겠습니다.",
			"어둠이 뿌리를 뻗고 있습니다.\n제 창은 작지만\n물러선 적이 없습니다.",
			"다시 뵙습니다.\n지난밤 지붕의 까마귀는\n제가 쫓아 두었습니다."]},
	{"id": "tilia", "person": "틸리아", "race": "fairy", "role": "사냥꾼", "detail": "나뭇가지 활을 쏘는 장난꾸러기 요정",
		"tag": "장난 섞인 명중", "portrait": PORTRAITS + "guest_tilia_cutout.png", "hireable": true,
		"lines": ["맞혀 볼까요?\n당신 등 뒤 창문에\n거미줄 셋, 거미 하나.",
			"숲의 눈들이 늘었어요.\n하나는 제가 맞혔고요.\n…농담이에요. 둘이에요.",
			"또 왔어요!\n이번엔 솔잎 화살 백 개.\n하나는 선물로 드릴게요."]},
	{"id": "larch", "person": "라르크", "race": "fairy", "role": "나무꾼", "detail": "병든 가지만 자른다는 요정 정원사",
		"tag": "엄격한 정원사", "portrait": PORTRAITS + "guest_larch_cutout.png", "hireable": true,
		"lines": ["베는 게 아니오. 치는 거지.\n병든 가지만.\n그 차이를 아는 집이면 묵겠소.",
			"저 숲은 가지치기가 안 됐소.\n썩은 가지에 썩은 것이 깃들지.\n내일 톱을 들겠소.",
			"지난번 그 가지,\n잘 아물었더군.\n…칭찬은 나무한테 한 거요."]},
	{"id": "fern", "person": "페른", "race": "fairy", "role": "채집가", "detail": "씨앗 주머니를 품에 안은 요정",
		"tag": "수줍은 씨앗 수집가", "portrait": PORTRAITS + "guest_fern_cutout.png", "hireable": true,
		"lines": ["저… 하룻밤만요.\n씨앗들이 추워해서요.\n…저도요.",
			"창가에서 씨앗 하나가\n자꾸 숲 쪽으로 굴러가요.\n…따라가면 안 되겠죠?",
			"또 왔어요.\n지난번 씨앗이 싹을 냈어요.\n…보여 드려도 돼요?"]},
	{"id": "willow", "person": "윌로우", "race": "fairy", "role": "숲의 사절", "detail": "오염된 숲의 소식을 전하는 요정",
		"tag": "격식 차린 경고", "portrait": PORTRAITS + "guest_willow_cutout.png", "hireable": false,
		"lines": ["숲의 이름으로 묻습니다.\n이 집의 불은\n무엇을 태워 밝힙니까?",
			"북쪽 샘이 검게 변했습니다.\n숲은 당신을 지켜보고 있습니다.\n…좋은 뜻으로요.",
			"다시 왔습니다.\n숲이 당신의 이름을\n나쁘게 부르지 않더군요."]},
	{"id": "pip", "person": "핍", "race": "fairy", "role": "씨앗 배달부", "detail": "도토리 배낭을 멘 숨 가쁜 요정",
		"tag": "숨 가쁜 수다", "portrait": PORTRAITS + "guest_pip_cutout.png", "hireable": false,
		"lines": ["하아, 하아, 도착!\n씨앗 열둘 배달 중이에요.\n하나도 안 잃었어요! …아마도.",
			"숲이 자꾸 길을 바꿔요!\n왼쪽이 오른쪽이 되고요!\n그래도 굴뚝은 안 바뀌죠!",
			"또 왔어요 또 왔어요!\n이번엔 씨앗 스물!\n…열아홉? 어, 어디 갔지."]},
	{"id": "nivel", "person": "니벨", "race": "fairy", "role": "꿈 기록가", "detail": "잠결에 숲의 꿈을 받아 적는 요정",
		"tag": "졸린 수수께끼", "portrait": PORTRAITS + "guest_nivel_cutout.png", "hireable": false,
		"lines": ["…하암. 이 집은\n꿈에서 본 적이 있어요.\n문이 열리기 전부터요.",
			"숲이 꾸는 꿈을 적어요.\n요즘 꿈엔 돌이 나와요.\n…당신 집 아래 돌이요.",
			"또… 하암… 왔어요.\n지난번 꿈의 끝을\n이 집에서 꿔야 해서요."]},

	# ── 고블린 ────────────────────────────────────────────
	{"id": "graz", "person": "그라즈", "race": "goblin", "role": "전투용병", "detail": "고물 갑옷을 짜 맞춘 고블린 용사",
		"tag": "허세 뒤의 의리", "portrait": PORTRAITS + "guest_graz_cutout.png", "hireable": true,
		"medal_portrait": PORTRAITS + "guest_graz_medal.png",  # 말 걸기 메달 전용(시안 03 인물 그대로). 없으면 portrait 사용
		"lines": ["하! 마녀쯤이야!\n…아니, 그게, 존경한다고요.\n방 하나만요. 제일 안쪽으로.",
			"숲의 눈들? 봤죠!\n하나도 안 무서웠어요!\n…둘부턴 좀 무서웠지만.",
			"또 왔어요, 형님… 아니 마녀님.\n지난번 빚진 거 갚으러요.\n이번엔 안 도망쳐요."]},
	{"id": "pikl", "person": "피클", "race": "goblin", "role": "사냥꾼", "detail": "덫과 매듭으로 숫자를 세는 고블린",
		"tag": "모든 걸 세는 버릇", "portrait": PORTRAITS + "guest_pikl_cutout.png", "hireable": true,
		"lines": ["창문 넷, 문 하나, 굴뚝 하나.\n나갈 구멍 여섯. 좋아.\n방 하나 주쇼.",
			"숲에 덫을 일곱 놨는데\n아침에 여덟이 됐소.\n하나는 내 게 아니오.",
			"또 왔소. 셌지.\n이 집 벽돌이 하나 늘었어.\n…안 믿는군. 세 봐."]},
	{"id": "rusk", "person": "러스크", "race": "goblin", "role": "나무꾼", "detail": "톱을 세 자루 지고 다니는 고블린",
		"tag": "톱날에 대한 애정", "portrait": PORTRAITS + "guest_rusk_cutout.png", "hireable": true,
		"lines": ["헤헤, 좋은 집이네.\n들보가 소나무, 바닥이 참나무.\n톱이 좋아하겠어.",
			"숲 나무는 톱날이 무뎌져.\n뭔가가 안에서 버티거든.\n그래도 셋째 톱이면 돼.",
			"또 왔어! 톱 보여 줄까?\n이번에 새로 얻은 거야.\n…어디서냐고? 묻지 마."]},
	{"id": "tak", "person": "타크", "race": "goblin", "role": "채집가", "detail": "주머니마다 반짝이는 것을 넣는 고블린",
		"tag": "주머니 가득한 호기심", "portrait": PORTRAITS + "guest_tak_cutout.png", "hireable": true,
		"lines": ["우와, 저 등불!\n만져 봐도 돼요? 안 돼요?\n…보기만 할게요. 방 주세요.",
			"숲에서 반짝이는 걸 주웠어요.\n…눈이었어요. 누구 눈인진 몰라요.\n주머니 깊이 넣었어요.",
			"또 왔어요! 주머니 하나 늘었어요.\n뭘 넣을진 아직 몰라요.\n여기서 찾을 거예요!"]},
	{"id": "nib", "person": "니브", "race": "goblin", "role": "행상인", "detail": "흥정으로 인사를 대신하는 고블린",
		"tag": "흥정으로 시작하는 인사", "portrait": PORTRAITS + "guest_nib_cutout.png", "hireable": false,
		"lines": ["숙박비요? 반값은 어때요?\n…안 돼요? 그럼 제값에\n이 단추 하나 얹어 드리죠.",
			"숲에서 물건을 잃었어요.\n근데 손해 본 느낌이 아니에요.\n거래를 한 것 같달까.",
			"단골 왔어요, 단골!\n이번엔 좋은 걸 가져왔죠.\n값은… 내일 얘기해요."]},
	{"id": "grik", "person": "그릭", "race": "goblin", "role": "탐험가", "detail": "찢어진 지도를 펼치는 고블린",
		"tag": "부풀려진 모험담", "portrait": PORTRAITS + "guest_grik_cutout.png", "hireable": false,
		"lines": ["이 몸이 바로 그릭!\n백 개의 동굴을 지난 사나이!\n…아흔아홉. 하나는 돌아 나왔어.",
			"숲 안쪽에 문이 있어요.\n열 명이 들어갔죠.\n…저 혼자였지만 열 번쯤 들어갔어요.",
			"또 왔소! 지도가 늘었어!\n여기, 이 집이 그려져 있지.\n…내가 그렸어. 어제."]},
	{"id": "mala", "person": "말라", "race": "goblin", "role": "골동품 수집가", "detail": "외알 안경으로 값을 매기는 고블린",
		"tag": "값을 매기는 눈", "portrait": PORTRAITS + "guest_mala_cutout.png", "hireable": false,
		"lines": ["흠. 문고리는 평범.\n등불은… 오래됐군요.\n방값보다 비싸요. 묵을게요.",
			"숲에서 동전을 주웠어요.\n한 번도 본 적 없는 얼굴이\n새겨져 있더군요. 값은 못 매겨요.",
			"또 왔어요.\n지난번 그 등불, 아직 있죠?\n팔진 마세요. 제가 살 거니까."]},

	# ── 수인 ──────────────────────────────────────────────
	{"id": "fargh", "person": "파르그", "race": "beastfolk", "role": "전투용병", "detail": "찢긴 귀의 늑대 수인 검사",
		"tag": "무리를 지키는 침묵", "portrait": PORTRAITS + "guest_fargh_cutout.png", "hireable": true,
		"lines": ["…문 옆에 눕겠다.\n잠은 얕게 잔다.\n그게 무리의 버릇이다.",
			"숲 냄새가 바뀌었다.\n쇠와 썩은 잎.\n…오늘 밤은 깨어 있겠다.",
			"…또 왔다.\n이 집은 무리 냄새가 난다.\n나쁘지 않군."]},
	{"id": "saya", "person": "사야", "race": "beastfolk", "role": "사냥꾼", "detail": "밤눈이 밝은 삵 수인 궁수",
		"tag": "밤눈 밝은 간결함", "portrait": PORTRAITS + "guest_saya_cutout.png", "hireable": true,
		"lines": ["밤에 더 잘 보여.\n창가 자리면 돼.",
			"숲에 눈이 열둘.\n여덟은 짐승. 넷은 아니야.",
			"또 왔어.\n굴뚝 연기, 제일 먼저 보여."]},
	{"id": "urso", "person": "우르소", "race": "beastfolk", "role": "나무꾼", "detail": "꿀단지를 찬 곰 수인 벌목꾼",
		"tag": "느긋한 힘", "portrait": PORTRAITS + "guest_urso_cutout.png", "hireable": true,
		"lines": ["으음… 따뜻하군.\n겨울잠 자기 좋은 집이야.\n…아, 자러 온 건 아니고.",
			"숲의 것들이 시끄럽더군.\n곰은 겨울에 시끄러운 걸\n안 좋아해. 조용히 시켜야지.",
			"또 왔네. 꿀 좀 줄까?\n…반만. 겨울은 기니까."]},
	{"id": "momi", "person": "모미", "race": "beastfolk", "role": "채집가", "detail": "귀를 접고 두리번대는 토끼 수인",
		"tag": "겁 많은 부지런함", "portrait": PORTRAITS + "guest_momi_cutout.png", "hireable": true,
		"lines": ["저, 저기요!\n방이요, 작아도 돼요.\n구멍 같은 데가 더 좋아요.",
			"숲에서 뭔가가 따라왔어요.\n돌아보진 않았어요.\n대신 약초를 세 배 캤어요!",
			"또 왔어요! 안 늦었죠?\n바구니 가득이에요.\n…뒤에 아무도 없죠?"]},
	{"id": "luka", "person": "루카", "race": "beastfolk", "role": "길잡이", "detail": "숲길을 꿰고 있다는 여우 수인",
		"tag": "능청스러운 길잡이", "portrait": PORTRAITS + "guest_luka_cutout.png", "hireable": false,
		"lines": ["길을 잃은 건 아니에요.\n길이 저를 잃은 거죠.\n덕분에 좋은 집을 찾았네요.",
			"숲길이 자꾸 바뀌어요.\n저야 꼬리로 외우니 괜찮지만\n남들은 글쎄요.",
			"단골이 왔습니다!\n이번엔 지름길로 왔죠.\n…반나절 더 걸렸지만요."]},
	{"id": "tass", "person": "타스", "race": "beastfolk", "role": "짐꾼", "detail": "짐을 절대 내려놓지 않는 오소리 수인",
		"tag": "짐을 놓지 않는 고집", "portrait": PORTRAITS + "guest_tass_cutout.png", "hireable": false,
		"lines": ["짐은 안 내려놔.\n잘 때도.\n방만 넓으면 돼.",
			"숲에서 뭐가 짐을 당겼어.\n안 놨지.\n…뭐였는진 안 봤어.",
			"또 왔어.\n짐이 늘었어.\n묻지 마."]},
	{"id": "selen", "person": "셀렌", "race": "beastfolk", "role": "밤 전령", "detail": "밤에만 날아다니는 올빼미 수인",
		"tag": "밤에 깨어나는 전령", "portrait": PORTRAITS + "guest_selen_cutout.png", "hireable": false,
		"lines": ["낮에 문을 두드려 미안해요.\n해 지면 깨어날게요.\n그때 소식을 전하죠.",
			"밤의 숲에서 들었어요.\n돌을 부르는 소리.\n…당신 집 아래의 돌이요.",
			"또 왔어요. 밤 손님이.\n이 집 창문 불빛은\n하늘에서도 보여요."]},

	# ── 오크 ──────────────────────────────────────────────
	{"id": "garok", "person": "가로크", "race": "orc", "role": "전투용병", "detail": "맹세를 뼈에 새긴 오크 호위대장",
		"tag": "약속을 지키는 무게", "portrait": PORTRAITS + "guest_garok_cutout.png", "hireable": true,
		"lines": ["지붕을 내어 주는 자에게\n내 검을 빚진다.\n그게 우리 법이다.",
			"숲의 것들이 문을 노린다.\n내가 문 앞에 서면\n문은 열리지 않는다.",
			"다시 왔다.\n지난번 빚은 아직 남았다.\n오늘 밤 갚겠다."]},
	{"id": "kranya", "person": "크라냐", "race": "orc", "role": "사냥꾼", "detail": "사냥감을 자랑하는 오크 투창수",
		"tag": "사냥감 자랑", "portrait": PORTRAITS + "guest_kranya_cutout.png", "hireable": true,
		"lines": ["토끼 셋, 꿩 둘!\n오늘 저녁은 내가 낸다.\n솥은 있겠지?",
			"숲의 짐승이 줄었어.\n뭔가가 먼저 사냥하고 있어.\n…내 사냥감을.",
			"또 왔다! 이번엔 사슴!\n…절반은 숲에 두고 왔지.\n뭔가가 가져갔어."]},
	{"id": "moga", "person": "모가", "race": "orc", "role": "나무꾼", "detail": "나무에게 사과하고 베는 오크 거구",
		"tag": "나무에게 사과하는 거구", "portrait": PORTRAITS + "guest_moga_cutout.png", "hireable": true,
		"lines": ["하하! 문이 작군!\n…부쉈나? 아니지? 다행이다.\n조심히 들어가지.",
			"나무를 베기 전엔 말하지.\n미안하다, 고맙다.\n이 숲 나무는 대답을 안 해.",
			"또 왔다, 하하!\n지난번 그 그루터기에\n새싹이 났더군. 용서받았어."]},
	{"id": "shaga", "person": "샤가", "race": "orc", "role": "채집가", "detail": "뿌리와 재를 다루는 오크 견습 주술사",
		"tag": "조용한 견습 주술사", "portrait": PORTRAITS + "guest_shaga_cutout.png", "hireable": true,
		"lines": ["…이 집의 재는 깨끗하군요.\n스승이 말했어요.\n재가 깨끗한 집은 믿으라고.",
			"숲의 뿌리가 검게 물들어요.\n제가 아는 약으론 모자라요.\n…당신은 아시겠죠.",
			"다시 왔어요.\n지난번 재를 가져가\n의식에 썼어요. 잘 됐어요."]},
	{"id": "ulma", "person": "울마", "race": "orc", "role": "주술사", "detail": "뼈를 던져 내일을 읽는 오크 노파",
		"tag": "뼈를 던지는 예언", "portrait": PORTRAITS + "guest_ulma_cutout.png", "hireable": false,
		"lines": ["뼈가 이 집을 가리켰다.\n그래서 왔지.\n이유는 뼈한테 물어.",
			"던져 봤다.\n오늘 밤 문은 세 번 흔들려.\n…네 번째는 열지 마.",
			"또 왔다, 애야.\n뼈가 같은 집을 두 번 가리키면\n그건 집이 아니라 사람이다."]},
	{"id": "bardu", "person": "바르두", "race": "orc", "role": "조상 순례자", "detail": "조상의 발자국을 따라 걷는 오크",
		"tag": "조상의 길을 걷는", "portrait": PORTRAITS + "guest_bardu_cutout.png", "hireable": false,
		"lines": ["조상들이 이 길을 걸었소.\n그때도 여기 불이 있었다지.\n…같은 불이오?",
			"숲의 돌 앞에서 절을 했소.\n조상이 아니라\n더 오래된 것이더군.",
			"다시 왔소.\n순례는 끝나지 않소.\n다만 이 집이 길에 들었을 뿐."]},
	{"id": "eshka", "person": "에쉬카", "race": "orc", "role": "요리사", "detail": "솥째 나눠 먹자는 오크 요리사",
		"tag": "솥째 나누는 환대", "portrait": PORTRAITS + "guest_eshka_cutout.png", "hireable": false,
		"lines": ["부엌! 부엌부터 봅시다!\n…좋아요. 오늘 저녁은\n제가 합니다. 다 같이!",
			"숲의 것들도 배가 고픈 거예요.\n…아니, 먹이진 말고요.\n우리부터 먹어요.",
			"또 왔어요! 국자 들고요!\n지난번 솥, 아직 있죠?\n이번엔 두 배로 끓여요."]},
]

static func character(id: String) -> Dictionary:
	for profile in CATALOG + SPECIALS:
		if profile["id"] == id: return _decorate(profile.duplicate(true))
	return {}

static func all_profiles() -> Array:
	var out: Array = []
	for profile in CATALOG:
		out.append(_decorate(profile.duplicate(true)))
	return out

## 표시용 필드(종족명·보조색)를 채운다. 포트레이트 파일이 아직 없으면 실루엣 경로로 바꾼다.
static func _decorate(profile: Dictionary) -> Dictionary:
	var race: String = profile.get("race", "human")
	profile["race_name"] = Races.name_of(race)
	profile["race_accent"] = Races.accent(race)
	profile["portrait_missing"] = not ResourceLoader.exists(profile["portrait"])
	if profile.has("medal_portrait") and not ResourceLoader.exists(profile["medal_portrait"]):
		profile.erase("medal_portrait")  # 메달 전용 그림이 아직 없으면 일반 초상으로
	if profile["portrait_missing"]:
		profile["portrait"] = PLACEHOLDER_PORTRAIT
	return profile

## 인물 이름 → 직업 카드 id. 이름 풀 밖의 인물(용병 n)은 이름 순서로 네 직업을 돌아가며 받는다.
static func job_of(person: String) -> String:
	if JOBS.has(person):
		return JOBS[person]
	return ["warrior", "hunter", "lumberjack", "gatherer"][absi(person.hash()) % 4]

## 인물 이름 → 종족 id. 카탈로그 밖의 이름(용병 n)은 인간.
static var _race_by_person := {}

## 용병 공격·이동 배율 등에서 자주 불리므로 이름 → 종족 표를 한 번 만들어 쓴다(목록에서 먼저 나온 사람 기준).
static func race_of(person: String) -> String:
	if _race_by_person.is_empty():
		for profile in CATALOG:
			if not _race_by_person.has(profile["person"]):
				_race_by_person[profile["person"]] = profile.get("race", "human")
	return _race_by_person.get(person, "human")

## 종족별 프로필 목록(hireable 로 걸러 쓸 수 있다).
static func profiles_of_race(race: String) -> Array:
	var out: Array = []
	for profile in CATALOG:
		if profile.get("race", "human") == race: out.append(_decorate(profile.duplicate(true)))
	return out

static func greeting(profile: Dictionary, visit: int) -> String:
	var lines: Array = profile["lines"]
	return lines[maxi(visit, 0) % lines.size()]

## 손님 한 명을 고른다(판마다 바뀌는 월드 설정의 종족 가중치, docs/races-guests-v01.md §7).
## hireable: 고용 제안을 할 손님(true) / 여행자(false). job: 직업 고정(빈 문자열이면 무작위).
## exclude: 지금 고를 수 없는 인물 id·이름(이미 계약 중·산장에 묵는 중·같은 묶음). avoid: 되도록 피할 id(오늘 이미 온 손님).
## 후보가 없으면 빈 Dictionary.
static func pick_guest(setting, hireable: bool, exclude: Array, avoid: Array = [], job := "") -> Dictionary:
	var pool: Array = []
	for c in CATALOG:
		if c["hireable"] != hireable: continue
		if job != "" and JOBS.get(c["person"], "") != job: continue
		if c["id"] in exclude or c["person"] in exclude: continue
		pool.append(c)
	if pool.is_empty(): return {}
	var fresh: Array = pool.filter(func(c): return not c["id"] in avoid)
	if not fresh.is_empty(): pool = fresh
	var races: Array = []
	for c in pool:
		if not c["race"] in races: races.append(c["race"])
	var race: String = setting.pick_race(races) if setting != null else races[0]
	var in_race: Array = pool.filter(func(c): return c["race"] == race)
	var rng: RandomNumberGenerator = setting.rng if setting != null else RandomNumberGenerator.new()
	var picked: Dictionary = in_race[rng.randi_range(0, in_race.size() - 1)]
	return guest_profile(picked["id"])


## 손님 id → 도착용 프로필(첫인사·character_id 포함). person_override: 이름 풀 밖의 대체 용병 이름.
static func guest_profile(id: String, person_override := "") -> Dictionary:
	var profile := character(id)
	if profile.is_empty(): return {}
	if person_override != "":
		profile["person"] = person_override
	profile["line"] = greeting(profile, 0)
	profile["character_id"] = profile["id"]
	return profile
