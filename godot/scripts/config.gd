extends RefCounted
## 밸런스 초기값. 인수인계 문서 6~10절의 "초기 설계" 수치이며 플레이테스트로 조정한다.

# 준비·숙박
const PREP_TIME := 90.0
const GUEST_ARRIVALS := [5.0, 30.0, 60.0]
const GUEST_STAY := 20.0
const GUEST_FEE := 15
const BASE_CAPACITY := 2
const EXT_CAPACITY := 3
const GUEST_WALK_SPEED := 2.2
const GUEST_STORY_EVERY := 2  # 대화 대상 손님 N명 중 1명만 말 걸기 이벤트를 띄운다

# 구매
const COST_REPAIR := 10
const COST_HEAL := 10
const COST_SHEEP := 20
const LODGE_REPAIR_EFFICIENCY := 0.2  # 산장 수리 효율(사용자 요청 2026-10-22: 기존의 20%). 산장에 들어가는 모든 수리량에 곱한다
const REPAIR_AMOUNT := 50.0 * LODGE_REPAIR_EFFICIENCY
const HEAL_AMOUNT := 50.0

# 플레이어
const PLAYER_HP := 100.0
const PLAYER_SPEED := 3.5
const BOLT_DAMAGE := 12.0
const BOLT_INTERVAL := 1.0
const BOLT_RANGE := 4.0
const BOLT_SPEED := 10.0
# 마녀 Q 번개 일격(Lightning Lance): 커서 방향으로 즉시 뻗는 관통 번개. 맞은 적 모두 피해 + 잠깐 감전(감속).
const LIGHTNING_RANGE := 8.0
const LIGHTNING_HALF_WIDTH := 0.75    # 줄기 중심선에서 이 거리 안(+적 몸 반지름)이면 맞는다
const LIGHTNING_DAMAGE := 26.0
const LIGHTNING_SLOW := 0.45          # 감전된 적 이동 속도 배율
const LIGHTNING_SLOW_TIME := 0.7
const LIGHTNING_CD := 5.0
const LIGHTNING_PRESET := 1           # 연출 프리셋 기본값: 0 기본 번개 · 1 뇌창 · 2 흑뢰 (게임 중 Shift+Q 로 바꿈)

# 산장·양
const LODGE_HP := 300.0
const SHEEP_HP := 30.0
const SHEEP_START := 3

# 목장 단계: 울타리 영역(x, z, 가로, 세로)과 최대 양 수. 산장 +X 벽을 한 변으로 공유한다.
const PASTURE_LEVELS := [
	{"rect": Rect2(2.45, -2.0, 3.7, 4.6), "cap": 4},
	{"rect": Rect2(2.45, -2.4, 4.5, 5.2), "cap": 6},
	{"rect": Rect2(2.45, -2.9, 5.3, 5.8), "cap": 8},
]
# 묘지 단계별 최대 무덤 수(산장 뒤편)
const GRAVE_LEVELS := [8, 12, 16]   # 무덤 자리 수만 정한다. 고용 상한은 용병 숙소 침상(BUNK_LEVELS)이 맡는다
# 용병 숙소 침상(docs/merc-count-balance-v01.md, 사용자 확정 2026-10-22): 살아 있는 용병 + 미사용 계약 카드는 침상 수까지.
# 침상이 꽉 차면 고용할 수 없다(넘침 고용 없음). 증축은 해당 일차부터 열린다 — 6일차까지 5명 안팎
const BUNK_LEVELS := [4, 6, 8]
const BUNK_UNLOCK_DAYS := [6, 9]    # 1단계(6침상)·2단계(8침상) 증축이 열리는 일차

# 건축: 생성·증축·업그레이드는 골드와 함께 목재가 든다. 키 = 구매 종류, 배열 = 다음 단계별 비용
## 재화 1장=1개 전환(docs/resource-single-card-balance-v01.md, 2026-10-18): 목재는 낱장이라 최고 3장으로 맞춘다.
const BUILD_COSTS := {
	"extension": [{"gold": 60, "timber": 3}],
	"pasture": [{"gold": 40, "timber": 2}, {"gold": 60, "timber": 3}],
	"graves": [{"gold": 30, "timber": 2}, {"gold": 45, "timber": 3}],
	"bunks": [{"gold": 80, "timber": 3}, {"gold": 140, "timber": 3}],
}

# 몬스터
const MONSTER_SPEED := 1.7
const MONSTER_MELEE := 1.2
const MONSTER_AGGRO := 5.0            # 괴물이 가는 길 이 반경 안에 마녀·용병·하수인·가시덩굴이 있으면 먼저 쫓아가 공격한다
const MONSTER_LEASH := 8.0            # 쫓던 대상이 이보다 멀어지면 포기하고 원래 목표(산장·양)로 돌아간다
const MONSTER_DAMAGE := 5.0
const MONSTER_INTERVAL := 2.0

# 웨이브: groups = [[출현 시각(초), 인원], ...]
const WAVES := [
	{"count": 5, "hp": 36.0, "sheep": 1, "groups": [[0.0, 3], [8.0, 2]]},
	{"count": 9, "hp": 48.0, "sheep": 3, "groups": [[0.0, 3], [5.0, 3], [10.0, 3]]},
	{"count": 18, "hp": 60.0, "sheep": 4,
		"groups": [[0.0, 3], [3.0, 3], [6.0, 3], [9.0, 3], [12.0, 3], [15.0, 3]]},
]

# 용(2026-10-24 사용자 확정): 소환 버튼·골드 공물 없이 [용비늘] 카드를 밤 전투 중 산장에 놓아 소환한다.
# 용비늘은 적 처치 시 DRAGON_SCALE_DROP 확률(말라의 외알 안경 배율 적용), 보스는 확정으로 얻는다.
const DRAGON_SCALE := "dragon_scale"
const DRAGON_SCALE_DROP := 0.001
const DRAGON_SUMMON_TIME := 1.0
const DRAGON_FIRE_INTERVAL := 2.0
const DRAGON_LEAVE_TIME := 3.0
const FIREBALL_DAMAGE := 200.0
const FIREBALL_RADIUS := 5.0
const FIREBALL_RANGE := 30.0
const FIREBALL_SPEED := 12.0

# 카드 코어 C0 — 기획서 v0.3 §5~9·11·12의 시험값
const START_GOLD := 40
const CONTRACT_COST := 30
const CONTRACT_REFUND := 15           # 산장 관리에서 계약을 해지하면 돌려받는 골드(계약료의 절반)
const HIRE_WAIT := 10.0
const HIRE_BATCHES := [0]             # 2일차부터 하루 1명: 첫 숙박 묶음에서 고용 기회(숙박 초대장 등 계기로 더 열린다)
const HIRE_BATCHES_FIRST_DAY := [0, 1] # 1일차만 2명(튜토리얼): 첫·둘째 숙박 묶음
const MERC_NAMES := ["브람", "올라프", "토르빈", "하겐", "에이릭", "군나르", "울프", "스벤", "레이프", "비요른"]
const ACTIVE_LIMIT := 16              # 월드에서 활동 중인 용병 상한(미사용 카드·숲의 괴물 하수인은 제외). 6에서 완화
const HAND_VISIBLE := 8               # 손패 한도(확정 규칙 3). 넘치면 주머니에 보관
const CHOP_TIME := 15.0              # 벌목 1회(목재 1개) 시간. 재화 1장=1개 전환으로 15초로 되돌림(하루 최대 6회)
const CHOP_YIELD := 1                # 벌목 1회에 얻는 목재(항상 1개)
const LUMBERJACK_CARRY := 3          # 나무꾼이 들고 있을 수 있는 목재 최대치(사용자 결정 2026-10-24: 1개→3개). 가득 차면 산장 마당에서 쉬며 마녀를 기다린다
const TREE_TIMBER := 40               # (구) 자원 나무 기준 목재량. 직업 분화 v1부터 높이별 tree_yield()를 쓴다
const HARVEST_TREES := [[-7.9, -1.5], [-1.9, -9.6], [-3.4, 11.8]]
const WOOL_PRICE := 6                # 재화 1장=1개 전환으로 1장 가치 상향(4→6)
const HARVEST_RANGE := 0.8           # 목장 안에서 양 바로 옆까지 다가간다
const HARVEST_TIME := 2.2            # 털 깎기 모션 시간(진행 게이지 표시)
const TIMBER_REPAIR_COST := 1        # 목재 카드 1장으로 수리(겨울 장작과 같은 단가)
const TIMBER_REPAIR_AMOUNT := 60.0 * LODGE_REPAIR_EFFICIENCY
const MERC_HP := 40.0
const MERC_DAMAGE := 8.0
const MERC_INTERVAL := 1.5
const MERC_SPEED := 2.6
const MERC_REGEN := 1.0               # 밤에 산장 안으로 대피한 용병의 초당 회복. 낮 회복은 켜진 모닥불 곁에서만(CAMPFIRE_HEAL_PER_SEC)
const MINION_HP := 48.0
const MINION_DAMAGE := 6.0
const MINION_INTERVAL := 1.6
const MINION_TIMBER := 1              # 숲의 괴물 하수인은 죽거나 낮이 되면 목재 1개가 된다
# 큰 숲의 괴물: 카드로 변환되는 표식 개체(기본 숲의 괴물보다 크고 등에 가지가 돋음)
const BIG_MONSTER_HP_MULT := 1.7
const BIG_MONSTER_SCALE := 1.32
const BIG_MONSTER_SPEED := 1.5
const BIG_MONSTER_DAMAGE := 7.0
const ALLY_MELEE := 1.3
const ALLY_AGGRO := 6.0               # 기준 지점에서 적을 찾는 반경(기획의 사거리6m 비교값)
const ALLY_LEASH := 8.0
const CARD_MONSTER_INDEX := [2, 4, 8] # 웨이브별 카드 획득 대상(출현 순서). 표식이 붙은 개체

# 신규 카드 v01 — 서리 룬·수호 등불·숙박 초대장·새끼양(시험값)
const STARTER_CARDS := [["frost_rune", 1], ["ward_lantern", 1], ["guest_invitation", 1], ["lamb", 1], ["sleeping_thorn_seed", 1], ["black_sheep", 1]]
const FROST_RADIUS := 2.6
const FROST_DAMAGE := 18.0
const FROST_SLOW := 0.45              # 이동 속도 배율
const FROST_SLOW_TIME := 5.0
const LANTERN_RADIUS := 3.5
const LANTERN_SLOW := 0.65            # 빛 안의 적 이동 속도 배율
const WITCH_SIGHT_DAY := 20.0          # 마녀 안개 시야 반경(낮). 사용자 요청 2026-10-22: 멀리 있는 적도 보이게 12→20
const WITCH_SIGHT_NIGHT := 15.0        # 마녀 안개 시야 반경(밤). 9→15
const ALLY_SIGHT := 6.0                # 용병·아군 주변 시야 반경(4→6)
const LANTERN_SIGHT := 5.0            # 안개를 걷어 내는 반경
const LANTERN_LIMIT := 2              # 동시에 켜 둘 수 있는 등불 수(밤 전투가 끝나면 꺼진다)
const INVITE_MIN_TIME := GUEST_STAY + 2.0  # 손님이 숙박비를 낼 수 있도록 남아 있어야 할 준비 시간
const LAMB_GROW_DAYS := 2             # 들인 날로부터 이틀 뒤 낮에 어른 양이 된다
const LAMB_HP := 15.0
const LAMB_SCALE := 0.6

# 숲 확장 카드: 낮 성장 → 밤 방책, 검은 털을 공물로 강화(시험값).
const THORN_GROW_TIME := 18.0
const THORN_LIMIT := 4
const THORN_SPACING := 1.6
const THORN_HP := 90.0
const THORN_RADIUS := 2.1
const THORN_DAMAGE := 6.0
const THORN_INTERVAL := 1.2
const THORN_SLOW := 0.35
const THORN_RITUAL_HP := 130.0
const THORN_RITUAL_DAMAGE := 10.0

# 직업 분화 v1 — 네 직업·야생 동물·채집·유물(시험값). 기획: docs/mercenary-jobs-design.md
const JOB_CARDS := ["lumberjack", "hunter", "warrior", "gatherer"]
const JOB_NAMES := {"lumberjack": "나무꾼", "hunter": "사냥꾼", "warrior": "전투용병", "gatherer": "채집가"}
const JOB_HP := {"lumberjack": 40.0, "hunter": 36.0, "warrior": 56.0, "gatherer": 34.0}
const HUNTER_RANGE := 7.0             # 활 사거리
const HUNTER_KITE := 2.0              # 이보다 가까이 붙으면 물러나며 쏜다
const HUNTER_DAMAGE := 6.0
const HUNTER_INTERVAL := 1.2
const ARROW_SPEED := 16.0             # (예전 직선 화살 속도 — 지금은 아래 포물선 값을 쓴다)
## 화살 포물선(2026-10-21 사용자: 살짝 포물선, 도착을 조금 늦춰 쏘는 게 보이게). 비행 시간 = 거리 / 속도(최소·최대 사이).
const ARROW_FLIGHT_SPEED := 9.0       # 평균 수평 속도(예전 16 → 7m 거리 0.44초 → 0.78초)
const ARROW_FLIGHT_MIN := 0.35
const ARROW_FLIGHT_MAX := 1.0
const ARROW_ARC := 0.09               # 꼭대기 높이 = 거리 × 이 값 + 0.2(최대 ARROW_ARC_MAX) — 7m 에서 약 0.8m
const ARROW_ARC_MAX := 1.0
const WARRIOR_DAMAGE := 10.0
const WARRIOR_INTERVAL := 1.3
const PATROL_RADIUS := [5.5, 8.0]     # 산장 중심에서 정찰 지점 반경
const PATROL_PAUSE := [1.0, 2.0]
const ENGAGE_RADIUS := 14.0           # 산장 중심 기준 적 발견 반경
const DISENGAGE_RADIUS := 18.0        # 대상이 이보다 멀어지면 놓아준다
const HANDOVER_RANGE := 2.2           # 마녀가 이 안에 오면 들고 있던 자원을 넘긴다
## 용병 동행(docs/merc-escort-v01.md, 사용자 확정 2026-10-22): 낮에 마녀가 산장을 벗어나면 전투직이 따라나와 함께 싸운다.
const ESCORT_LEAVE_RADIUS := 14.0     # 마녀가 산장 중심에서 이보다 멀어지면 전투직이 따라나선다(18 → 14, 2026-10-22 더 빨리 따라나오도록)
const ESCORT_RETURN_RADIUS := 11.0    # 마녀가 이 안으로 돌아오면 정찰로 복귀(히스테리시스)
const ESCORT_FOLLOW_DIST := {"warrior": 2.2, "hunter": 3.0}   # 마녀와 이 거리 안이면 멈춰 선다
const ESCORT_FOLLOW_CARRY := 1.8      # 짐을 든 채 따라올 때는 더 붙어 바로 건넨다(HANDOVER_RANGE 안)
## 거리 비례 달리기(2026-10-22): 마녀와의 거리가 ESCORT_SPEED_NEAR 이면 걷기(1배), ESCORT_SPEED_FAR 이상이면 ESCORT_SPEED_MAX_MULT 배.
## 그 사이는 선형. 출발할 때든 필드에서 벌어졌을 때든 똑같이 적용된다(멀수록 더 빨리 합류).
const ESCORT_SPEED_NEAR := 3.0
const ESCORT_SPEED_FAR := 18.0
const ESCORT_SPEED_MAX_MULT := 2.4    # 2.6 × 2.4 ≈ 6.2m/s(마녀 3.5의 약 1.8배). 6m 에서 1.47배(3.8m/s)로 이미 마녀보다 빠르다
const ESCORT_WARP_DIST := 30.0        # 이보다 멀리 떨어진 채 ESCORT_WARP_TIME 이 지나면 마녀 곁으로 순간이동(끼임 안전장치)
const ESCORT_WARP_TIME := 4.0
const ESCORT_ENGAGE_RADIUS := 10.0    # 동행 중 마녀 기준 적 발견 반경(enemies 그룹: 맹독 곤충 포함)
const ESCORT_DISENGAGE_RADIUS := 14.0 # 대상이 마녀에게서 이보다 멀어지면 놓아준다
const ESCORT_HUNT_RADIUS := 10.0      # 마녀가 서 있을 때 사냥꾼이 찾는 사냥감 반경(마녀 기준)
const ESCORT_STILL_TIME := 0.6        # 마녀가 이만큼 제자리면 "서 있음"으로 본다
const TREE_YIELD_PER_M := 1.0         # 목재량 = clamp(round(높이 × 이 값), TREE_YIELD_MIN, TREE_YIELD_MAX). 1장=1개 전환으로 한 그루 2~6장
const TREE_YIELD_MIN := 2
const TREE_YIELD_MAX := 6
const TREE_ACCESS_NAV := 1.2          # 밑동에서 이 거리 안에 이동 가능 지면이 있어야 벌목 가능
const TREE_CROWD_RADIUS := 2.4        # 이 반경 안에 다른 나무가 TREE_CROWD_MAX그루 이상이면 둘러싸임
const TREE_CROWD_MAX := 3
## 장애물 충돌 최소 높이(m). 내비메시 굽기 높이(y 1.0)보다 높아야 윗면이 고립 섬으로 구워지지 않는다(world.gd).
const OBSTACLE_MIN_HEIGHT := 1.2

# 감시탑(docs/watchtower-v01.md, 2026-10-18): 공터에 목재 카드를 적립해 준비한 뒤 골드를 내고 짓는다.
## 단계별: 적립 목재·골드·최대 체력·올라갈 사냥꾼 수·시야 반경. 2단계는 1단계 위에 다시 목재를 적립해 업그레이드한다.
const TOWER_LEVELS := [
	{"timber": 3, "gold": 50, "hp": 180.0, "slots": 1, "sight": 8.0},
	{"timber": 5, "gold": 100, "hp": 300.0, "slots": 3, "sight": 10.0},
]
const TOWER_RANGE := 10.5             # 탑 위 사냥꾼 사거리(지상 HUNTER_RANGE 7.0보다 길다)
const TOWER_DAMAGE_MULT := 1.5        # 탑 위 사냥꾼 화살 피해 배율(6 → 9)
const TOWER_INTERVAL := 1.1           # 탑 위 사냥꾼 사격 간격(지상 1.2)
const TOWER_REPAIR_AMOUNT := 60.0     # 목재 1장으로 수리하는 양(산장 수리 효율 하향과 무관)
const TOWER_FOE_RADIUS := 1.2         # 괴물이 탑을 칠 때 중심에서 뺄 반경(탑 발치에서 공격)
const TOWER_CLIMB_RADIUS := 0.6       # 사다리 아래 이 거리 안에 오면 올라간다
# 야생 동물
const RABBIT_HP := 8.0
const RABBIT_SPEED := 2.2
const DEER_HP := 20.0
const DEER_SPEED := 2.6
const ANIMAL_FLEE_RADIUS := 4.0
const ANIMAL_LIFETIME := 90.0
const ANIMAL_SPAWN_INTERVAL := [20.0, 40.0]
const ANIMAL_SPAWN_RING := [9.0, 26.0]
const RABBIT_MAX := 3
const DEER_MAX := 2
const HUNT_SEARCH_RADIUS := 25.0      # 사냥꾼이 사냥감을 찾는 반경(자기 위치 기준)
const DEER_MEAT := 1                  # 1장=1개 전환으로 사슴도 생고기 1장(늑대 송곳니면 +1)
# 채집가
const GATHER_MIN_PREP := 30.0         # 카드 사용에 필요한 남은 준비 시간
const GATHER_RETURN_MARGIN := 20.0    # 준비 시간 끝나기 이만큼 전에 산장 도착
const GATHER_STOPS := 3
const GATHER_PICK_TIME := 3.0
# 줍기 표(합 1.0, 시험값). 주머니 v1에서 독버섯·오래된 마법서적을 추가: 목재 40→36, 생고기 20→18, 가죽 15→13, 빈손 15→12
const GATHER_TABLE := [["timber", 0.36, 1, 1], ["raw_meat", 0.18, 1, 1], ["rabbit_pelt", 0.13, 1, 1], ["treasure_chest", 0.10, 1, 1], ["poison_mushroom", 0.08, 1, 1], ["old_spellbook", 0.03, 1, 1], ["ore", 0.06, 1, 2], ["", 0.06, 0, 0]]  # ore: 광석(docs/legend-cards-v01.md)
const GATHER_CHEST_PER_DAY := 1
const GATHER_BOOK_PER_DAY := 1        # 오래된 마법서적은 하루 1권까지(넘치면 독버섯으로 대체)
# 새 자원
const MEAT_PRICE := 8                 # 1장=1개 전환으로 1장 가치 상향(5→8)
const PELT_PRICE := 10                # (7→10)
const MEAT_HEAL := 30.0               # (25→30)
const SALE_PRICES := {"wool": WOOL_PRICE, "raw_meat": MEAT_PRICE, "rabbit_pelt": PELT_PRICE, "scrap": 4, "ore": 12}  # scrap: 잡동사니 자루의 쇠붙이(고블린 카드 v1) · ore: 드워프 광석(전설 카드 v1)
# 앞마당 모닥불(docs/resource-uses-expansion-v01.md v0.3, 사용자 확정 2026-10-18): 목재를 태우고, 켜져 있을 때만 조리·낮 회복.
const CAMPFIRE_FUEL_PER_TIMBER := 60.0  # 목재 1개가 타는 시간(초)
const CAMPFIRE_MAX_TIMBER := 3          # 한 번에 채울 수 있는 목재 수(최대 180초)
const CAMPFIRE_START_FUEL := 60.0       # 새 판 시작 시 남은 연료(목재 1개분, 켜진 상태)
const CAMPFIRE_GAUGE_RANGE := 5.0       # 마녀가 이 안에 오면 모닥불 위에 남은 시간 링이 뜬다
const CAMPFIRE_DROP_RANGE := 1.6        # 카드를 놓은 지면이 모닥불 중심에서 이 안이면 모닥불에 놓은 것
const CAMPFIRE_HEAL_RADIUS := 3.4       # 낮 회복 반경(모닥불 둘레 대기 자리 두 겹을 덮는다)
const CAMPFIRE_HEAL_PER_SEC := 0.3      # 낮에 켜진 모닥불 곁 용병의 초당 회복(매우 느림)
const STEW_HEAL_RATIO := 0.8            # 고기 스튜: 끌어 놓은 용병 한 명이 최대 체력의 이 비율만큼 회복
# 유물(영구 패시브)
const RELICS := ["moonlit_charm", "hearth_ember", "old_tree_heart", "wolf_fang_pendant", "frost_queen_tear"]
const RELIC_NAMES := {"moonlit_charm": "달빛 부적", "hearth_ember": "화로의 온기석", "old_tree_heart": "고목의 심장",
	"wolf_fang_pendant": "늑대 송곳니 목걸이", "frost_queen_tear": "서리 여왕의 눈물"}
const RELIC_DESC := {
	"moonlit_charm": "마녀의 마법탄 피해 +50%, 사거리 +1m",
	"hearth_ember": "밤에도 산장 8m 안의 아군이 초당 1 회복. 매일 낮 시작에 산장 체력 +8",
	"old_tree_heart": "벌목 시간 15초 → 10초 (나무꾼이 목재를 더 빨리 모음)",
	"wolf_fang_pendant": "사냥꾼·전투용병 피해 +40%, 사냥 드롭 +1",
	"frost_queen_tear": "모든 적 이동 속도 85%. 매일 낮 시작에 서리 룬 카드 1장"}
const CHEST_CHOICES := 3
const CHEST_FALLBACK_TIMBER := 2      # 유물을 다 모았을 때 상자가 주는 목재(1장=1개 전환으로 10→2)
const RELIC_BOLT_MULT := 1.5
const RELIC_BOLT_RANGE := 1.0
const RELIC_EMBER_RADIUS := 8.0
const RELIC_EMBER_REGEN := 1.0
const RELIC_EMBER_LODGE := 40.0 * LODGE_REPAIR_EFFICIENCY
const RELIC_CHOP_TIME := 10.0         # 고목의 심장: 벌목 15초 → 10초
const RELIC_FANG_MULT := 1.4
const RELIC_FANG_DROP := 1
const RELIC_FROST_SLOW := 0.85

# 장착 장비 v0(2026-10-19, docs/equipment-and-party-frames-v01.md). 카드 컨셉 확정 전의 시험 장비 5종.
# 장비 카드를 마녀·용병(월드 또는 용병 초상)에 끌어 놓으면 그 칸에 끼운다. 같은 칸에 있던 장비는 손패로 돌아온다.
# who: witch | merc | any. stats: max_hp(+), damage(피해 배율 +), armor(받는 피해 감소율), speed(이동 배율 +), regen(초당 회복)
const EQUIP_SLOTS := ["weapon", "armor", "trinket"]
const EQUIP_SLOT_NAMES := {"weapon": "무기", "armor": "방어구", "trinket": "장신구"}
const EQUIPMENT := {
	"rusty_longsword": {"slot": "weapon", "who": "merc", "stats": {"damage": 0.3}},
	"oak_staff": {"slot": "weapon", "who": "witch", "stats": {"damage": 0.25}},
	"quilted_gambeson": {"slot": "armor", "who": "any", "stats": {"max_hp": 15.0, "armor": 0.15}},
	"traveler_boots": {"slot": "trinket", "who": "any", "stats": {"speed": 0.15}},
	"rowan_charm": {"slot": "trinket", "who": "any", "stats": {"regen": 0.4}},
	# 고블린 카드 v1(docs/goblin-cards-v01.md): 수치 효과는 scripts/game/goblin_cards.gd·kill_gold.gd 가 착용 여부로 처리한다
	"graz_whistle": {"slot": "trinket", "who": "merc", "stats": {}, "text": "고블린이 끼면 밤에 20초마다 졸개 1마리(최대 3)"},
	"pot_helmet": {"slot": "armor", "who": "merc", "stats": {}, "text": "피해 5회를 100→80→60→40→20% 막음 · 6회째 파괴(고블린은 10%로 버팀, 새벽 수리)"},
	"mala_coin_scale": {"slot": "trinket", "who": "merc", "stats": {}, "text": "처치 골드 +1"},
	"mala_monocle": {"slot": "trinket", "who": "merc", "stats": {}, "text": "처치 시 재화 드랍 확률 ×1.5"},
	# 종족·언데드·화합 카드 v1(docs/race-cards-v01.md): 특수 효과는 scripts/game/race_cards.gd·undead_cards.gd 가 착용 여부로 처리한다
	"dream_journal": {"slot": "trinket", "who": "witch", "stats": {}, "text": "아침 드로우 때 주머니에서 2장을 보고 1장을 고름"},
	"thistle_oath": {"slot": "trinket", "who": "merc", "stats": {}, "text": "공격이 적을 2.5초 둔화(이동 −40%)"},
	"rune_hammer": {"slot": "weapon", "who": "merc", "stats": {}, "text": "새벽마다 목재 1로 가장 상한 곳을 체력 40 수리(드워프 80)"},
	"ancestor_shield": {"slot": "armor", "who": "merc", "stats": {"armor": 0.3}, "text": "받는 피해 −30% · 드워프면 4m 안 아군도 −15%"},
	"ash_sigil": {"slot": "trinket", "who": "merc", "stats": {}, "text": "쓰러질 때(밤마다 한 번) 반경 5m 적이 4초 겁먹어 달아남"},
	"pack_scent": {"slot": "trinket", "who": "merc", "stats": {}, "text": "수인이 끼면 8m 안 다른 수인 1명마다 이동·공격 속도 +10%(최대 +40%)"},
	"porter_pack": {"slot": "armor", "who": "merc", "stats": {}, "text": "채집가·사냥꾼이 줍는 양 2배 · 짐을 들면 이동 +25%"},
	"interpreter_pen": {"slot": "trinket", "who": "witch", "stats": {}, "text": "용병 이벤트에서 공용 이벤트 확률 30% → 55%"},
	"ledger_of_dead": {"slot": "trinket", "who": "witch", "stats": {}, "text": "바친 용병 5명마다 언데드 카드 3장 중 1장"},
}
const EQUIP_ARMOR_CAP := 0.6           # 받는 피해 감소율 합의 상한

# 물리 레이어 비트
const L_GROUND := 1
const L_OBSTACLE := 2   # 산장·나무 줄기·큰 바위: 이동 차단 + 시야 차단
const L_BOUNDARY := 4   # 울타리·숲 경계: 이동만 차단
const L_ACTOR := 8

# 마녀의 주머니 — 창고를 덱으로(기획: docs/region-season-pocket-design.md §6, 시험값). 우선순위·진행: docs/region-season-pocket-priorities.md
const STARTER_DRAW := 3               # 시작 손패: 주머니에서 무작위 3장을 펼쳐 보여 준다(사용자 결정 2026-10-16)
const MULLIGAN_SWAPS := 1             # 시작 손패에서 교체할 수 있는 장수. 교체한 카드는 주머니로 돌아가고 다른 카드를 뽑는다
const DRAW_REVEAL_SCALE := 1.25       # 아침·효과 드로우 카드를 화면 가운데에 잠깐 보여 줄 때의 크기(손패 카드 대비)
const DRAW_REVEAL_HOLD := 1.0         # 주머니에서 꺼낸 카드가 나오기 시작해 손패로 내려가기까지(초). 날아오는 시간 포함
const DRAW_REVEAL_STEP := 0.3         # 여러 장을 뽑을 때 주머니에서 한 장씩 꺼내는 간격(초). 손패로 내려가는 간격도 같다
const MORNING_DRAW := 1               # 아침마다 주머니에서 뽑는 장수
const SPELLBOOK_CHOICES := 3          # 오래된 마법서적이 펼치는 후보 수(부족하면 있는 만큼)
const MUSHROOM_HP_COST := 10.0        # 독버섯의 체력 비용(미정 → 시험값). 체력이 이보다 많아야 사용할 수 있다(치명적 비용 불허)
const DRAW_ONLY_CARDS := ["poison_mushroom", "old_spellbook"]  # 본래 효과 없이 드로우만 하는 카드: 주머니가 비면 사용 불가·비용 없음

# 손패 흐름 v1(사용자 확정 2026-10-18, 기획: docs/hand-draw-flow-design-v01.md §7)
# 카드의 시간대: 낮 손패에는 낮 카드만, 밤 손패에는 밤 카드만 둔다. "both"는 양쪽에 남고 "none"(침식)은 어느 쪽도 아니지만 손패에 남아 칸을 막는다.
# 손패로 들어오는 카드가 지금 시간대에 못 쓰는 카드면 주머니로 간다. 낮↔밤 전환 때 반대 시간대 카드는 모두 주머니로 가고, 손패가 찰 때까지 새 시간대 카드를 무작위로 뽑는다(2026-10-23, 부족하면 있는 만큼).
const CARD_PHASE := {
	"lumberjack": "day", "hunter": "day", "warrior": "day", "gatherer": "day",
	"lamb": "day", "black_sheep": "day", "sleeping_thorn_seed": "day", "ward_lantern": "day", "guest_invitation": "day",
	"timber": "day", "wool": "day", "rabbit_pelt": "day", "treasure_chest": "day",
	"shroud_cloth": "day", "red_chalice": "day", "hibernation_pelt": "day",
	"frost_rune": "night", "resin_torch": "night", "vine_snare": "night", "thorn_bind": "night",
	"forest_monster": "night", "firefly_swarm": "night", "winter_firewood": "night", "dragon_scale": "night",
	"raw_meat": "both", "meat_stew": "both", "black_wool": "both", "moss_bandage": "both", "poison_mushroom": "both", "old_spellbook": "both",
	"corrupt_prayer": "none", "poison_spore": "none", "cursed_whisper": "none",
	"wolf_blood": "both", "crescent_moon": "night", "half_moon": "night", "full_moon": "night",
	"rusty_longsword": "both", "oak_staff": "both", "quilted_gambeson": "both", "traveler_boots": "both", "rowan_charm": "both",
	# 고블린 카드 v1
	"goblin_gang": "night", "goblin_firecracker": "night", "dud_bomb": "night", "goblin_rush": "night", "shiny_lure": "night",
	"junk_barricade": "both", "pikl_traps": "both", "junk_sack": "day", "scrap": "day",
	"graz_whistle": "both", "pot_helmet": "both", "mala_coin_scale": "both", "mala_monocle": "both",
	# 종족·언데드·화합 카드 v1(docs/race-cards-v01.md). 사건 카드는 대화 이벤트라 손패에 들어오지 않는다
	"fae_swap": "both", "dream_journal": "both", "thistle_oath": "both",
	"rune_hammer": "both", "dark_ale": "both", "stone_wall": "both", "ancestor_shield": "both", "mine_prop": "both", "stone_song": "night",
	"war_drum": "both", "feast_table": "both", "blood_oath": "both", "victory_roar": "night", "ash_sigil": "both", "spit_roast": "both",
	"pack_scent": "both", "porter_pack": "both",
	"guild_writ": "day", "village_militia": "night", "pilgrim_blessing": "both", "battle_ration": "both",
	"sacrifice_dagger": "both", "corpse": "both", "rise_up": "night", "bone_barricade": "both", "soul_jar": "both", "ghoul_feast": "both",
	"death_march": "night", "bone_hounds": "night", "black_rumor": "none", "ledger_of_dead": "both",
	"crest_banner": "both", "interpreter_pen": "both",
	# 술 주정뱅이 에린·주점 카드 v1(docs/tavern-cards-v01.md). 꿀술은 손님이 묵는 낮에만
	"drunken_erin": "both", "fire_ale": "both", "golden_mead": "day", "wisp_spirit": "both", "dew_of_forgetting": "both", "drunk_rant": "both",
	# 전설 카드 5장 + 광석 v1(docs/legend-cards-v01.md). 광석은 낮(판매·보강·벼리기), 마법서·종은 밤 전투
	"ore": "day", "frost_crown": "both", "lich_crown": "both", "wild_grimoire": "night", "fire_brazier": "both", "winter_bell": "night",
	# 용병 고유 키트 v04(docs/mercenary-unique-kit-v04.md): 고유 카드·생성 카드는 밤 전투
	"merc_war_horn": "night", "merc_hunt_mark": "night", "merc_rolling_log": "night", "merc_big_cauldron": "night",
	"gen_rally": "night", "gen_log_wall": "night", "gen_herb_water": "night",
	"merc_hold_line": "night", "merc_all_in": "night", "merc_timber_wall": "night", "merc_bitter": "night", "merc_thistle_hedge": "night",
	"merc_moth_dust": "night", "merc_pruning": "night", "merc_pollen": "night", "merc_junk_bomb": "night", "merc_snare": "night",
	"merc_saw_wheel": "night", "merc_lure": "night", "merc_blood_scent": "night", "merc_ambush": "night", "merc_bear_hug": "night",
	"merc_run": "night", "merc_oath_shield": "night", "merc_bone_spear": "night", "merc_axe_whirl": "night", "merc_ash_blessing": "night",
	"gen_bolt": "night", "gen_salve": "night", "gen_root": "night", "gen_junk_wall": "night", "gen_marble": "night",
	"gen_shadow_arrow": "night", "gen_honey": "night", "gen_herb_handful": "night", "gen_trophy": "night", "gen_forgive": "night",
	"gen_ash_charm": "night",
}
const DRAW_STACK_SIZE := 3            # 카드를 이만큼 쓰면(주머니 버튼 옆 동그란 스택이 다 차면) 주머니에서 1장 뽑는다
const BURN_DRAW_PER_DAY := 2          # 켜진 모닥불에 손패 카드를 태워 1장 뽑기: 하루 한도
const BURN_CORRUPTION_HP := 5.0       # 침식 카드를 태울 때 연기로 잃는 마녀 체력(드로우 없음)

# 볼륨 확장 E1 — 적 종류·보스·밤 규칙(시험값). 기획: docs/game-volume-expansion-plan.md §2.3~2.5
# hp_mult는 그 밤의 기본 체력에 곱한다. reach = 공격 거리. lodge_mult = 산장에 주는 피해 배율.
# ignore_units = 마녀·용병·방책을 무시하고 산장으로 간다. scale = 모형 크기. tint = 표시용 빛 색.
const ENEMY_KINDS := {
	# 기본 적(2026-10-17): 서리 거미. 수치는 숲의 괴물과 같고 이동은 '달리다 멈칫'(평균 속도 동일, monster.gd _scuttle)
	"spider": {"name": "서리 거미", "hp_mult": 1.0, "speed": 1.7, "damage": 5.0, "interval": 2.0, "reach": 1.2, "lodge_mult": 1.0, "scale": 1.0},
	"forest": {"name": "숲의 괴물", "hp_mult": 1.0, "speed": 1.7, "damage": 5.0, "interval": 2.0, "reach": 1.2, "lodge_mult": 1.0, "scale": 1.0},
	"cultist": {"name": "침식된 자", "hp_mult": 0.8, "speed": 1.5, "damage": 4.0, "interval": 2.2, "reach": 4.5, "lodge_mult": 1.0, "scale": 0.92, "tint": Color(0.75, 0.35, 1.0)},
	"insect": {"name": "맹독 곤충", "hp_mult": 0.5, "speed": 3.0, "damage": 3.0, "interval": 1.0, "reach": 1.1, "lodge_mult": 1.0, "scale": 0.7, "tint": Color(0.7, 1.0, 0.25)},
	"brute": {"name": "공성 괴물", "hp_mult": 3.0, "speed": 1.0, "damage": 6.0, "interval": 2.6, "reach": 1.5, "lodge_mult": 3.0, "scale": 1.5, "ignore_units": true, "big": true, "tint": Color(1.0, 0.55, 0.3)},
	"boss": {"name": "빈 굴의 주인", "hp": 1400.0, "speed": 1.1, "damage": 16.0, "interval": 2.4, "reach": 1.9, "lodge_mult": 1.5, "scale": 2.3, "big": true, "tint": Color(0.6, 0.85, 1.0)},
}
const BOSS_HIT_CAP := 150.0           # 보스가 한 번에 받는 피해 상한(용 불덩이 200이 보스를 녹이지 않도록)
const BOSS_ROAR_INTERVAL := 14.0      # 보스의 부름: 이 간격마다 숲의 괴물을 불러낸다
const BOSS_ROAR_SPAWN := 2
const BOSS_TROPHY := "hibernation_pelt"
const FOG_NIGHT_SIGHT := 0.6          # 안개의 밤 시야 배율

# 볼륨 확장 E2 — 마녀의 제단과 의식(시험값). 제단은 달빛 돌 제단 랜드마크에 있다.
const ALTAR_UNLOCK_DAY := 4
const ALTAR_RESTORE_TIMBER := 3       # 1장=1개 전환으로 10→3
const ALTAR_USE_RANGE := 3.2          # 마녀가 이 안에 있어야 제단을 쓸 수 있다
# id -> 공물(손패 자원 id·수량 또는 양), 첫 완성 권능 카드, 반복 시 그날 밤 축복
const RITUALS := {
	"shroud": {"name": "수의의 의식", "cost": {"wool": 2}, "power": "shroud_cloth", "blessing": "shroud",
		"desc": "양털 2 · 권능: 수의 카드 · 축복: 오늘 밤 마녀·아군이 치명타를 한 번 버팀"},
	"thorn": {"name": "가시의 봉헌", "cost": {"forest_monster": 1}, "power": "thorn_bind", "blessing": "thorn",
		"desc": "숲의 괴물 카드 1 · 권능: 가시 속박 카드 · 축복: 오늘 밤 가시 방책 공격력 +50%"},
	"red_feast": {"name": "붉은 만찬", "cost": {"sheep": 1}, "power": "red_chalice", "blessing": "red_feast",
		"desc": "어른 양 1마리 · 권능: 붉은 잔 카드 · 축복: 오늘 밤 마녀의 마법탄이 피해의 30% 회복"},
}
const BLESS_THORN_MULT := 1.5
const BLESS_LIFESTEAL := 0.3
const PELT_LODGE_MULT := 0.5          # 겨울잠 털가죽: 그날 밤 산장이 받는 피해 배율

# 볼륨 확장 E3 — 숲 카드·침식 카드(시험값)
const MOSS_HEAL := 20.0
const RESIN_RADIUS := 2.4
const RESIN_DPS := 6.0
const RESIN_TIME := 5.0
const FIREFLY_SIGHT := 8.0
const VINE_RADIUS := 2.0
const VINE_DAMAGE := 6.0
const VINE_SLOW := 0.15
const VINE_TIME := 4.0
const THORN_BIND_RADIUS := 3.0
const THORN_BIND_DAMAGE := 12.0
const THORN_BIND_SLOW := 0.1
const THORN_BIND_TIME := 4.0
const FIREWOOD_REPAIR := 60.0 * LODGE_REPAIR_EFFICIENCY
const CORRUPTION_CARDS := ["corrupt_prayer", "poison_spore", "cursed_whisper", "black_rumor"]  # black_rumor: 검은 소문(평판, docs/race-cards-v01.md)
const CORRUPTION_PER_NIGHT := 2       # 한 밤에 주머니로 들어오는 침식 카드 상한
const SPORE_DAWN_HP := 8.0            # 독 포자: 손패에 있으면 새벽마다 마녀 체력 -8(치명적이지 않음)

# 늑대의 피(docs/wolf-blood-event-design.md, 사용자 확정 2026-10-18): 파르그가 검은 양 한 마리를 얻어먹고 주는 카드.
# 마녀에게 쓰면 잠시 괴로워한 뒤 달 카드 3종이 주머니로 들어온다. 달 카드는 밤에만, 한 밤에 한 장, 1회용(버림패).
const MOON_CARDS := ["crescent_moon", "half_moon", "full_moon"]
const MOON_KIND := {"crescent_moon": "crescent", "half_moon": "half", "full_moon": "full"}
const MOON_NAMES := {"crescent": "초승달", "half": "상현달", "full": "보름달"}
const WOLF_SUFFER_TIME := 1.6         # 늑대의 피를 쓴 뒤 괴로워하는 시간(이동·공격 불가)
const WOLF_SUFFER_CARDS_AT := 1.0     # 괴로워하기 시작한 뒤 달 카드가 솟아 주머니로 가는 시점
const MOON_CRESCENT_ATTACK := 0.65    # 초승달: 마법탄 간격 배율
const MOON_HALF_ATTACK := 0.65        # 상현달: 마법탄 간격 배율
const MOON_HALF_MOVE := 1.3           # 상현달: 이동 속도 배율
# 보름달 — 늑대(체력은 마녀와 같은 풀). 근접 물기 평타 + Q 할퀴기 + E 덮치기. 손패는 잠긴다(사용자 확정).
const WOLF_MOVE_MULT := 1.6
const WOLF_BITE_RANGE := 1.5
const WOLF_BITE_DAMAGE := 14.0
const WOLF_BITE_INTERVAL := 0.55
const WOLF_BITE_WINDUP := 0.12
const WOLF_CLAW_ANGLE := 110.0        # 전방 부채꼴 각도(도)
const WOLF_CLAW_RADIUS := 2.4
const WOLF_CLAW_HITS := 4
const WOLF_CLAW_DAMAGE := 9.0         # 1회 할퀴기 피해(4번이면 36)
const WOLF_CLAW_TIME := 0.45          # 4번 할퀴는 데 걸리는 시간(이동 불가)
const WOLF_CLAW_CD := 7.0
const WOLF_POUNCE_RANGE := 7.0        # 이 안의 적 하나에게 덮친다
const WOLF_POUNCE_TIME := 0.25        # 도약 시간
const WOLF_POUNCE_DAMAGE := 32.0
const WOLF_POUNCE_SLOW := 0.6         # 물린 적 이동 속도 배율
const WOLF_POUNCE_SLOW_TIME := 1.5
const WOLF_POUNCE_CD := 10.0
