# 숲길 원정대 (카드 던전 크롤러 프로토타입)

마녀산장(`../마녀산장/witchs-lodge`)의 눈 덮인 숲 프랍·툰 화면·카드 연출을 그대로 가져온 **그리드 이동 기반 던전 크롤러 카드 게임**.
궁수·전사·마법사 셋이 숲속 방(공터)을 하나씩 정리하며 좁은 숲길을 뛰어 다음 방으로 나아간다. 세 무리마다 중간 보스, 8번째 방이 끝.

- **실행**: [ForestExpedition.exe](ForestExpedition.exe) 더블클릭(데이터 내장 단일 파일)
- **카드·규칙 컨셉**: [docs/card-concept-v01.md](docs/card-concept-v01.md)
- 엔진: Godot 4.7.2 (마녀산장의 `.tools/Godot-4.7.2.exe` 를 같이 쓴다), 프로젝트는 [godot/](godot/)

## 조작

| 동작 | 방법 |
|---|---|
| 카드 쓰기 | 카드를 위로 끌어 적·칸에 놓기 **또는** 카드를 눌러 고른 뒤 적·칸 누르기(집으면 주인과 대상 적만 밝아진다) |
| 즉시 카드(불굴의 포효) | 한 번 더 누르거나 전장 위에 놓기 |
| 취소 | 오른쪽 클릭 · Esc |
| 턴 종료 | [턴 종료] 버튼 · Space(모든 행동력을 쓰면 자동) |

적 머리 위 글자는 다음 적 턴에 할 행동(공격 n · 전진 · 포효 · 빙결)이다. 적을 마우스로 가리키면 아래에 정보가 뜬다.

## 구조

```text
godot/
  dungeon/                 ← 이 게임 코드
    data/defs.gd           캐릭터·카드·적·방 수치(밸런스는 여기만)
    core/battle.gd         전투 판정(화면과 무관, 사건 목록을 돌려줌)
    view/forest_world.gd   환경·달빛·카메라·지면·숲·방(격자·모닥불)·좁은 길·가리는 나무 비침·공기 원근·날씨·입김·딤드 강조
    view/unit_view.gd      3D 유닛(마녀산장 캐릭터 모델 + RigAnim + 소품)
    view/hand.gd           손패(마녀산장 card_view 연출 + CardFace 글자 굽기)
    view/card_vfx.gd       카드·적 행동 연출(Fx·번개 창·서리 룬·리본 꼬리·효과음)
    view/hud.gd            체력 막대·적 의도·캐릭터 패널·배너·원정대 선택·승패
    shaders/               던전 지면(마녀산장 지면 셰이더 파생) · 격자 오버레이
    main.gd                흐름(선택 → 행군 → 전투 → 자동 이동 → 승패)·입력
    tools/verify_*.gd      헤드리스 검증 · capture.gd 렌더 캡처
  scripts/ shaders/ scenes/ assets/   ← 마녀산장에서 복사(그대로 재사용, 고치지 않음)
```

마녀산장에서 가져온 파일은 고치지 않고 `res://` 경로 그대로 둔다. 바꿔야 하면 `dungeon/` 쪽에 파생본을 만든다(지면 셰이더처럼).

## 검증(헤드리스 우선)

`godot/` 폴더에서(`G` = `../../마녀산장/witchs-lodge/.tools/Godot-4.7.2.exe`):

```text
$G --headless --path . --script res://dungeon/tools/verify_battle.gd   # 전투 규칙 34항목 + 8방 자동 진행
$G --headless --path . --script res://dungeon/tools/verify_flow.gd     # 메인 장면 흐름: 행군→전투→뛰어 이동(시간 측정)→중간 보스→승리
$G --headless --path . --script res://dungeon/tools/verify_input.gd    # 마우스 입력(끌기·누르기·딤드 강조·돌진·취소·자동 턴·한 부채꼴)
$G --path . --script res://dungeon/tools/capture.gd                    # 렌더 캡처(셰이더·배치 확인용) → screenshots/capture/
```

## 실행 파일 다시 만들기

```text
$G --headless --path . --export-release "Windows Desktop" ../ForestExpedition.exe
```

게임을 고친 뒤에는 위 명령으로 실행 파일을 다시 내보낸다(약 15초).
