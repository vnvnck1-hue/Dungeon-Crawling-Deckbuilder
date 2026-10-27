# 숲길 원정대 (카드 던전 크롤러 프로토타입)

마녀산장(`../마녀산장/witchs-lodge`)의 눈 덮인 숲 프랍·툰 화면·카드 연출을 그대로 가져온 **그리드 이동 기반 던전 크롤러 카드 게임**.
궁수·전사·마법사 셋이 숲속 방(공터)을 하나씩 정리하며 좁은 숲길을 뛰어 다음 방으로 나아간다. 세 무리마다 중간 보스, 8번째 방이 끝.

- **실행**: [ForestExpedition.exe](ForestExpedition.exe) 더블클릭(데이터 내장 단일 파일)
- **카드·규칙 컨셉**: [docs/card-concept-v01.md](docs/card-concept-v01.md)
- **직업 시너지(현재 카드 50장·상태이상·연계)**: [docs/card-synergy-design-v01.md](docs/card-synergy-design-v01.md)
- 엔진: Godot 4.7.2 (마녀산장의 `.tools/Godot-4.7.2.exe` 를 같이 쓴다), 프로젝트는 [godot/](godot/)

## 조작

| 동작 | 방법 |
|---|---|
| 카드 쓰기 | 카드를 위로 끌어 적·칸에 놓기 **또는** 카드를 눌러 고른 뒤 적·칸 누르기(집으면 주인과 대상 적만 밝아진다) |
| 즉시 카드(불굴의 포효·철벽 등) | 한 번 더 누르거나 전장 위에 놓기 |
| 취소 | 오른쪽 클릭 · Esc |
| 턴 종료 | [턴 종료] 버튼 · Space(모든 행동력을 쓰면 자동) |
| 레벨업 카드 고르기 | 떠오른 세 장 중 하나 누르기 |
| 전체 화면 | 처음 실행하면 테두리 없는 전체 화면. **F11** 로 창 모드 전환(`--windowed` 로 실행하면 이번만 창 모드) |

적 머리 위 글자는 다음 적 턴에 할 행동(공격 n · 포효 · 빙결)이다. 적은 이동하지 않고 어디서든 바로 친다. 적을 마우스로 가리키면 아래에 정보가 뜬다.

## 규칙 요약 (2026-10-27)

- 모든 캐릭터는 **매 아군 턴 행동력 3**으로 시작한다. 카드 비용은 1·2·3.
- **손패 5장.** 방에 들어서면 살아 있는 캐릭터의 덱을 모두 섞어 5장 뽑고, 턴마다 5장이 될 때까지 다시 뽑는다. 쓴 카드는 버림패로, 뽑을 패가 비면 버림패를 섞는다.
- 아군·적 모두 **이동 없음.** 근접은 대상 앞까지 돌진해 치고 돌아온다.
- **경험치·레벨.** 적이 쓰러지면 살아 있는 아군 모두 그 적의 경험치를 얻고, 직접 처치한 캐릭터는 +3. 레벨업하면 그 캐릭터의 새 카드 셋 중 하나를 골라 덱에 섞어 넣는다(바로 뽑을 패에도 들어간다).
- 피격: 움찔·넉백·하얗게 번쩍·납작 스쿼시 + 히트스탑 + 화면 흔들림(피해가 클수록 세게).
- **직업 시너지.** 전사 투지(맞을수록 피해 +) · 궁수 표식 중첩(모두의 피해 +, 표식 적 처치 시 행동력 +1) · 마법사 냉기/화상(냉기 3 = 빙결, 둘이 겹치면 증기 폭발).
  빙결 + 밀치기 충돌 = 파쇄, 연쇄 번개는 상태를 옮긴다(전도). **연계**: 직전에 낸 카드의 주인에 따라 추가 효과(손패에서 주황으로 맥동).
  지속 카드는 그 방이 끝날 때까지 켜진다(캐릭터 패널 위에 이름). 레벨업 때 새 카드 셋 + 덱의 카드 하나 강화 중 고른다.
- 상태이상은 머리 위 칩(숫자)과 몸·발밑 연출로 보인다: 표식 = 붉은 조준 고리(쌓인 수만큼 화살촉), 화상 = 몸에 타오르는 불꽃, 냉기 = 서리 + 도는 얼음 조각, 빙결 = 얼음 덩어리, 투지 = 붉은 기운.
- 자세한 수치는 [docs/card-synergy-design-v01.md](docs/card-synergy-design-v01.md), 바꾸려면 `godot/dungeon/data/defs.gd`.

## 구조

```text
godot/
  dungeon/                 ← 이 게임 코드
    data/defs.gd           캐릭터·카드·적·방 수치(밸런스는 여기만)
    core/battle.gd         전투 판정(화면과 무관, 사건 목록을 돌려줌)
    view/forest_world.gd   환경·달빛·카메라·지면·숲·방(격자·모닥불)·좁은 길·가리는 나무 비침·공기 원근·날씨·입김·딤드 강조
                           식생: 덩어리진 숲·절벽 바위·윗가장자리 덤불·늘어진 뿌리·달빛 꽃(발광)
    view/terrain.gd        지형 높낮이: 공터·길은 y=0 평지, 바깥은 계단식 단·절벽(뒤는 솟고 카메라 쪽은 꺼져 물웅덩이)
    view/unit_view.gd      3D 유닛(마녀산장 캐릭터 모델 + RigAnim + 소품)
    view/status_fx.gd      상태이상 3D 표시(몸 껍질 셰이더·발밑 고리·얼음 덩어리·불씨 입자)
    view/status_chip.gd    머리 위 상태 칩(그림 + 쌓인 수)
    view/hand.gd           손패(마녀산장 card_view 연출 + CardFace 글자 굽기)
    view/card_vfx.gd       카드·적 행동 연출(Fx·번개 창·서리 룬·리본 꼬리·효과음)
    view/hud.gd            체력 막대·적 의도·캐릭터 패널(레벨·경험치)·배너·원정대 선택·레벨업 카드 고르기·승패
    shaders/               던전 지면(마녀산장 지면 셰이더 파생, 절벽 바위·물가 포함) · 밤 물웅덩이 · 격자 오버레이
    main.gd                흐름(선택 → 행군 → 전투 → 자동 이동 → 승패)·입력
    tools/verify_*.gd      헤드리스 검증 · capture.gd 렌더 캡처
  scripts/ shaders/ scenes/ assets/   ← 마녀산장에서 복사(그대로 재사용, 고치지 않음)
```

마녀산장에서 가져온 파일은 고치지 않고 `res://` 경로 그대로 둔다. 바꿔야 하면 `dungeon/` 쪽에 파생본을 만든다(지면 셰이더처럼).

## 검증(헤드리스 우선)

`godot/` 폴더에서(`G` = `../../마녀산장/.tools/Godot-4.7.2.exe`). 새로 받은 저장소라면 먼저 `$G --headless --path . --import` 로 에셋을 임포트한다.

```text
$G --headless --path . --script res://dungeon/tools/verify_battle.gd   # 전투 규칙 84항목(덱·손패·경험치·레벨업·상태 중첩·반응·연계·지속·강화) + 8방 자동 진행
$G --headless --path . --script res://dungeon/tools/verify_flow.gd     # 메인 장면 흐름: 행군→전투→뛰어 이동→중간 보스→승리, 레벨업 고르기·줌·히트스탑
$G --headless --path . --script res://dungeon/tools/verify_input.gd    # 마우스 입력(끌기·누르기·딤드 강조·돌진·취소·넉백·턴 종료·한 부채꼴)
$G --path . --script res://dungeon/tools/capture.gd                    # 렌더 캡처(셰이더·배치 확인용) → screenshots/capture/
$G --path . --script res://dungeon/tools/capture_terrain.gd            # 지형(단·절벽·물·식생) 넓은 구도 캡처 → screenshots/capture/terrain_*.png
$G --path . --script res://dungeon/tools/capture_status.gd             # 상태이상·반응·연계·레벨업 강화 캡처 → screenshots/capture/status_*.png
```

## 실행 파일 다시 만들기

```text
$G --headless --path . --export-release "Windows Desktop" ../ForestExpedition.exe
```

게임을 고친 뒤에는 위 명령으로 실행 파일을 다시 내보낸다(약 15초).
