extends RefCounted
## 고블린 카드 v1 수치(시험값). 기획: docs/deck-archetypes-v01.md §4.1(1차 검수 2026-10-19), 적용 기록 docs/goblin-cards-v01.md.
## 공용 config.gd 를 덜 건드리도록 고블린 전용 수치는 여기에 둔다(장비 칸·시간대처럼 공용 표가 읽는 값만 config.gd).

const RACE := "goblin"

# ── 고블린 졸개(밤 동안만 있는 약한 고블린) ──
const MINION_HP := 14.0
const MINION_DAMAGE := 3.0
const MINION_INTERVAL := 1.0
const MINION_REACH := 1.0
const MINION_SPEED := 3.0
const MINION_AGGRO := 14.0          # 이 안의 적을 쫓는다(자기 자리 기준)
const MINION_CAP := 12              # 동시에 있을 수 있는 졸개 수(모든 출처 합)
const MINION_SCALE := 0.5           # 니브 모델(1.3m)을 줄여 쓴다 → 약 0.65m

# ── 사촌 패거리 ──
const GANG_COUNT := 3
const GANG_COUNT_BONUS := 4          # 고블린 용병 GANG_BONUS_AT 명 이상
const GANG_BONUS_AT := 2

# ── 그라즈의 호루라기 ──
const WHISTLE_INTERVAL := 20.0
const WHISTLE_MAX := 3               # 호루라기 하나가 거느리는 졸개 상한

# ── 고블린 폭죽 · 불발탄 ──
const FIRECRACKER_RADIUS := 3.0
const FIRECRACKER_DAMAGE := 14.0
const FIRECRACKER_FEAR := 2.5        # 겁먹어 물러나는 시간(이동 느림 + 공격 멈춤)
const FIRECRACKER_PUSH := 1.6        # 물러나는 거리
const FIRECRACKER_BACKFIRE := 0.15   # 아군도 맞을 확률
const FIRECRACKER_BACKFIRE_DAMAGE := 5.0
const FIRECRACKER_DUD_AT := 4        # 고블린 용병이 이만큼이면 불발탄 2장
const FIRECRACKER_DUDS := 2
const DUD_RADIUS := 1.4
const DUD_DAMAGE := 4.0
const DUD_STUN := 2.0

# ── 떼거리 돌격 ──
const RUSH_RADIUS := 2.5
const RUSH_DAMAGE_PER := 4.0         # 졸개 한 마리당 범위 피해

# ── 반짝이 미끼(2판) ──
const LURE_TIME := 8.0
const LURE_PULL := 7.0               # 이 안의 적이 미끼로 몰린다
const LURE_BLIND_RADIUS := 3.0
const LURE_BLIND := 2.0
const LURE_MINION_BONUS := 1.5       # 미끼 반경 안의 적에게 졸개 피해 +50%

# ── 고물 방책 ──
const BARRICADE_HP := 40.0           # 가시 방책 90의 절반 이하, 산장 300
const BARRICADE_DAYS := 2            # 2일 뒤 새벽에 무너진다
const BARRICADE_TIMBER := 1

# ── 피클의 덫 꾸러미 ──
const TRAP_COUNT := 3
const TRAP_SPREAD := 1.5
const TRAP_TRIGGER := 0.8
const TRAP_DAMAGE := 4.0
const TRAP_STUN := 2.5

# ── 잡동사니 자루 ──
const SACK_MIN := 2
const SACK_MAX := 4
const SACK_SCRAP_CHANCE := 0.25      # 한 개마다 쇠붙이일 확률
const SACK_POOL := ["timber", "timber", "raw_meat", "rabbit_pelt", "wool"]
const SCRAP_PRICE := 4

# ── 찌그러진 냄비 투구: 피격 회차별 막는 비율(1회차부터). 6회차에 파괴, 고블린은 10%로 남음 ──
const HELMET_BLOCK := [1.0, 0.8, 0.6, 0.4, 0.2]
const HELMET_GOBLIN_FLOOR := 0.1

# ── 처치 골드 ──
const COIN_SCALE_BONUS := 1          # 말라의 동전 저울: 장착 용병이 처치하면 +1
const MONOCLE_LOOT_BONUS := 0.5      # 말라의 외알 안경: 재화 드랍 확률 ×1.5(재화 드랍 시스템이 읽는다)

# ── 용병 이벤트(고블린) ──
const EVENT_CHANCE := 0.4            # 고블린 용병이 있을 때 새벽마다 이벤트가 일어날 확률(하루 최대 1건)
const COUSIN_DECLINE_GOLD := 10
const COUSIN_FOOD := ["meat_stew", "raw_meat"]   # 사촌을 받으면 그날 먹일 음식(있으면 1개 소비)
const COUSIN_NO_FOOD_GOLD := 5        # 음식이 없으면 대신 내는 골드
const DEBT_DAYS := 3
const DEBT_AMOUNT := 45              # 계약료 30 + 이자 15
