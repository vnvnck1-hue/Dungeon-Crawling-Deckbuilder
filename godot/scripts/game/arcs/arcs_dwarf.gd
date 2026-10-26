extends RefCounted
## 드워프 7명(하랄·브륀힐드·토르그림·두르가·오르무·케틸·시그뉘)의 이야기 연작 2·3편(2026-10-25).
## 형식·조건은 guest_story_arcs.gd 머리말을 따른다. 1편은 guest_dialogues.gd STORIES 그대로다.

## 1편(STORIES)의 두 선택지가 남기는 기억. 순서는 choices 와 같다.
const PART1_MEMORY := {
	"harald": ["harald_wise", "harald_open"],
	"brynhild": ["brynhild_sweep", "brynhild_night"],
	"thorgrim": ["thorgrim_hands", "thorgrim_old"],
	"durga": ["durga_busy", "durga_rest"],
	"ormu": ["ormu_stone", "ormu_wait"],
	"ketil": ["ketil_ask", "ketil_thanks"],
	"signy": ["signy_potato", "signy_potion"],
}

## 손님 id → [2편, 3편]
const ARCS := {
	"harald": [
		{"prompt": "주인, 할 말이 있소.", "title": "세 번 두드린 문",
			"opening": [
				{"who": "scene", "text": "하랄이 문 옆 벽을 두드린다.\n세 번. 대답을 기다리듯."},
				{"if": "mem:harald_wise", "text": "현명했다고 했지.\n그 말을 사흘 씹었소.\n…돌에도 맛이 있더군. 썼소."},
				{"if": "mem:harald_open", "text": "문은 내가 지킨다 했지.\n그래서 말해 둘 게 있소.\n늦은 값이 얼마인지."},
				"산문이 닫히던 밤,\n문 앞을 지킨 게 나였소.\n갓 수염 난 경비였지.",
				"누가 문을 두드렸소. 세 번.\n여자 목소리였지.\n…빗장은 내 손에 있었소.",
				{"who": "garok", "if": "present:garok", "text": "우리 법엔 문 앞 손님을\n돌려보내는 말이 없다.\n…드워프 법은 다른가."},
				{"if": "present:garok", "text": "…다르지 않소, 오크.\n법은 같았는데\n손이 굳었던 거요."},
				{"who": "witch", "text": "세 번 두드리는 버릇.\n그는 아직도\n대답을 기다린다."}],
			"choices": [
				{"text": "닫으라 한 건 장로들이야.", "remember": "harald_elders",
					"reply": ["장로는 명을 내렸고\n나는 빗장을 걸었소.\n돌은 누가 깎든 무게가 같소.", "…그래도 고맙소.\n그 말을 해 준 건\n당신이 처음이오."]},
				{"text": "그 목소리, 아직 들려?", "remember": "harald_voice",
					"reply": ["…매일 밤은 아니오.\n눈 오는 밤에만.\n그래서 겨울엔 문 옆에 서지.", {"who": "witch", "text": "문 옆 자리를 고집한 까닭이\n거기 있었다."}]}],
			"closing": ["오늘 밤 누가 세 번 두드리면\n내가 열겠소.\n…대답부터 하고."]},
		{"prompt": "이걸 보시오.", "title": "청동 열쇠",
			"opening": [
				{"who": "scene", "text": "탁자 위에 청동 열쇠 하나.\n망치 문장이 닳아 있다."},
				"산문 열쇠요. 경비가\n물러날 때 받는 거지.\n…광산에서 편지가 왔소.",
				"젊은 경비들을 가르치라더군.\n이 무릎으로 말이오.",
				{"if": "mem:harald_elders", "text": "장로 얘기 했었지.\n편지 끝에 그 장로 손자\n이름이 있더군. 우습지."},
				{"if": "mem:harald_voice", "text": "그 목소리 말이오.\n지난겨울엔 안 들렸소.\n…이 집 문 옆에선."},
				{"who": "durga", "if": "present:durga", "text": "무릎 시리면 이끼 찜질해라.\n고집만 센 늙은 경비야.\n…가르치러 가거라."},
				{"if": "present:durga", "text": "…두르가 할멈한텐\n못 당하겠군."},
				{"who": "witch", "text": "열쇠를 놓은 손이\n탁자에서 쉬 떨어지지 않는다."}],
			"choices": [
				{"text": "가서 여는 법을 가르쳐.", "remember": "harald_teach",
					"reply": ["여는 법이라.\n경비는 닫는 법만 배우오.\n…그걸 바꾸라는 거군.", "좋소. 첫 수업은\n'세 번 두드리면 대답한다'요."]},
				{"text": "열쇠는 여기 걸어 둬.", "remember": "harald_key",
					"reply": ["이 집 문에 산문 열쇠라.\n맞는 구멍도 없는데.", "…맞는 구멍이 없어서\n좋은 거요. 다시는\n아무도 못 잠그니."]}],
			"closing": ["닫은 문은 오래 기억되고\n연 문은 금방 잊히지.\n…그래도 열겠소."]},
	],
	"brynhild": [
		{"prompt": "새 내기요!", "title": "드워프 대 오크",
			"opening": [
				{"if": "mem:brynhild_sweep", "text": "마당은 내가 쓸었지?\n빗자루 빚은 갚았소.\n이제 새 내기요!"},
				{"if": "mem:brynhild_night", "text": "그날 밤 하늘만 봤소.\n…안 날더군. 두 배는…\n농담이오. 내가 먼저 잤지."},
				"오크 사냥꾼하고 걸었소.\n사흘 동안 누가 더 잡나.\n은화 세 닢.",
				{"who": "kranya", "if": "present:kranya", "text": "하! 드워프 다리로?\n난 아침 먹기 전에 다섯이야.\n은화 닦아 둬."},
				{"if": "present:kranya", "text": "다리가 짧으면 화살이 길지.\n…석궁이지만."},
				{"who": "witch", "text": "은화 세 닢이면\n저 석궁 줄값이다.\n지면 줄 없이 쏘겠군."},
				"그래서 말인데, 심판 좀 하시오.\n마녀는 거짓말을 안 한다더군."],
			"choices": [
				{"text": "심판값은 따로 받아.", "remember": "brynhild_judge",
					"reply": ["하! 역시 드워프 같은 마녀요.\n이기면 반을 주지.\n…지면 마당을 또 쓸고."]},
				{"text": "둘이 같이 사냥해.", "remember": "brynhild_together",
					"reply": ["같이? 오크랑?\n…그럼 누가 이긴 거요?", "둘 다 이기면\n둘 다 술을 사는 건가.\n…그거 좋은 내기군."]}],
			"closing": ["오늘 밤 내기는\n누가 먼저 코를 고나.\n…이번엔 안 지오."]},
		{"prompt": "…동전 하나.", "title": "걸려 있는 내기",
			"opening": [
				{"who": "scene", "text": "브륀힐드가 구멍 난 동전을\n굴린다. 웃지 않는다."},
				{"if": "mem:brynhild_judge", "text": "심판값 가져왔소.\n…졌소. 오크가 하나 더 잡았지.\n세 닢의 반이오."},
				{"if": "mem:brynhild_together", "text": "같이 사냥했소.\n멧돼지 한 마리, 둘이 나눴지.\n내기는 비긴 걸로 칩시다."},
				"이 동전은 오라비랑 건 거요.\n'누가 먼저 장가가나.'\n…갱도가 무너지기 전날.",
				"누가 이겼는지 아직 모르오.\n그러니 이건\n아직 걸려 있는 내기지.",
				{"who": "witch", "text": "그래서 늘 내기를 건다.\n진 쪽은\n다시 와야 하니까."}],
			"choices": [
				{"text": "봄에 또 오기, 내기해.", "remember": "brynhild_spring",
					"reply": ["하! 마녀가 내기를?\n좋소. 은화 한 닢.", "…가만, 지는 쪽이 오는 거요?\n이기는 쪽이 오는 거요?\n…둘 다 와야겠군."]},
				{"text": "그 동전, 내가 맡아 둘게.", "remember": "brynhild_coin",
					"reply": ["…맡는다고?\n이건 오라비 빚인데.", "그럼 됐소. 동전이 여기 있으면\n나도 여기로 오겠지.\n드워프는 빚을 안 남기니."]}],
			"closing": ["오늘은 내기 없소.\n…아니, 하나만.\n내일 아침 눈이 오나 안 오나."]},
	],
	"thorgrim": [
		{"prompt": "나무 얘기요.", "title": "결이 꼬인 갱목",
			"opening": [
				{"if": "mem:thorgrim_hands", "text": "할머니의 할머니 말이오.\n쐐기 없이 짠 들보.\n…밤새 그 생각만 했소."},
				{"if": "mem:thorgrim_old", "text": "늙을수록 단단하다 했지.\n사람은 반대라고.\n…나는 무르게 늙었소."},
				"갱목을 짜던 시절 얘기요.\n결이 꼬인 참나무를\n버팀목으로 쓴 적이 있소.",
				"무너지진 않았소.\n대신 견습 하나가\n다리를 절게 됐지.",
				"그 뒤로 짜는 일은 안 하오.\n베기만 하지.\n베는 건 나무 탓이니까.",
				{"who": "moga", "if": "present:moga", "text": "하하! 베기 전에 미안하다 해.\n그럼 도끼가 가벼워져.\n…짜기 전에도 해 봐."},
				{"if": "present:moga", "text": "나무는 대답 안 하오, 오크.\n대답은 결이 하지."},
				{"who": "witch", "text": "나무 탓이라면서\n매일 나무에 귀를 댄다."}],
			"choices": [
				{"text": "양 우리 문을 짜 줘.", "remember": "thorgrim_build",
					"reply": ["…짜라고? 나더러?\n양이 다치면 어쩌려고.", "…알겠소. 결부터 읽지.\n양 우리 문은\n천 번 열리고 닫히니까."]},
				{"text": "베는 일만 해도 돼.", "remember": "thorgrim_cut",
					"reply": ["…그렇지. 그게 맞소.", {"who": "witch", "text": "맞다고 하면서\n어깨가 내려갔다."}]}],
			"closing": ["내일은 결 바른 참나무 하나.\n…쓸 데는 아직 모르오."]},
		{"prompt": "허락을 받으러 왔소.", "title": "쐐기 하나",
			"opening": [
				{"who": "scene", "text": "토르그림 손에 참나무 쐐기.\n칼자국이 고르다."},
				{"if": "mem:thorgrim_build", "text": "양 우리 문, 짰소.\n양이 들이받아도 멀쩡하더군."},
				{"if": ["mem:thorgrim_build", "black_sheep"], "text": "검은 놈이 제일 세게 받더군.\n…그놈이 대장이오?"},
				{"if": "mem:thorgrim_cut", "text": "벤 것 중에 결 바른 놈이 있어서\n버리기 아까웠소.\n…그래서 이걸 깎았지."},
				"그 들보에 박을 쐐기요.\n삼백 년 버틴 들보에\n백 년을 더 얹는 거지.",
				{"who": "ketil", "if": "present:ketil", "text": "…쇠로 하지."},
				{"if": "present:ketil", "text": "나무로 하오. 쇠는 녹슬어.\n…그리고 이건 내 일이오."},
				{"who": "ketil", "if": "present:ketil", "text": "…알았소."},
				"다만 남의 집 들보요.\n주인이 허락해야지.",
				{"who": "witch", "text": "견습 얘기 뒤로 처음\n무언가를 짜려는 손이다."}],
			"choices": [
				{"text": "박아. 네 이름도 새기고.", "remember": "thorgrim_mark",
					"reply": ["이름? 들보에?\n…쐐기 끝에만 작게 새기지.\n삼백 년 뒤에 누가 웃게."]},
				{"text": "박아. 표시는 없이.", "remember": "thorgrim_plain",
					"reply": ["좋소. 그 손도 표시를 안 했으니.\n좋은 일은\n결 속에 숨기는 거요."]}],
			"closing": ["쾅. 한 번이면 되오.", "…견습한테도\n편지 한 장 써야겠군."]},
	],
	"durga": [
		{"prompt": "얘, 이리 앉아.", "title": "이끼 사러 오던 처자",
			"opening": [
				{"who": "scene", "text": "두르가가 창턱 이끼를 긁어\n천에 싼다. 손이 빠르다."},
				{"if": "mem:durga_busy", "text": "할 일 많다던 그 얼굴,\n오늘도 그대로구나.\n쯧, 이리 와. 찜질해 주마."},
				{"if": "mem:durga_rest", "text": "할미더러 쉬라더니\n너는 안 쉬지?\n…말 안 들을 줄 알았다."},
				"옛날 광산에 이끼를 사러\n오던 처자가 있었지.\n손이 눈처럼 찼어.",
				{"who": "mira", "if": "present:mira", "text": "할머니, 그 이끼 이름이 뭐예요?\n제 책엔 안 나와요."},
				{"if": "present:mira", "text": "책에 없는 게 약이다.\n…다 먹으면 가르쳐 주마."},
				"산문이 닫히고는 안 왔어.\n이끼는 그대로 자라는데.",
				{"who": "witch", "text": "할미는 나를 보면서\n다른 얼굴을 보고 있다."}],
			"choices": [
				{"text": "그 사람 이름 기억나?", "remember": "durga_name",
					"reply": ["…이름은 안 물었다.\n물었으면 찾으러 갔겠지.\n그럼 나도 사라졌을 거고.", "드워프는 얼굴을 기억해.\n…네 얼굴이 좀 닮았다."]},
				{"text": "이끼 긁는 법 가르쳐 줘.", "remember": "durga_teach",
					"reply": ["쯧, 이제야 묻는구나.\n위에서 아래로. 뿌리는 두고.\n…그 처자도 그렇게 긁었다."]}],
			"closing": ["찜질 식었다. 또.\n…됐다, 내가 데우마."]},
		{"prompt": "얘야, 할 말 있다.", "title": "데워 줄 사람",
			"opening": [
				"앉아라. 아니, 이번엔\n네가 앉으라는 게 아니다.\n…내가 앉을 거다.",
				{"who": "scene", "text": "두르가가 찻잔을 두 손으로\n쥔다. 잔이 조금 떨린다."},
				{"if": "mem:durga_name", "text": "이름 얘기 하고 나서\n그 처자 꿈을 꿨다.\n…너처럼 차를 식히더구나."},
				{"if": "mem:durga_teach", "text": "이끼 긁은 거 봤다.\n위에서 아래로. 잘했어.\n…이제 내가 없어도 되겠다."},
				"손녀가 광산으로 오래.\n눈이 흐려서 이끼랑 녹을\n못 가린다고. 맞는 말이지.",
				{"who": "harald", "if": "present:harald", "text": "할멈이 떠나면\n이 집 차는 누가 데우오."},
				{"if": "present:harald", "text": "넌 무릎이나 데워라.\n…차는 얘가 데울 거다."},
				{"who": "witch", "text": "차를 데우는 건\n늘 더 앉아 있을 핑계였다."}],
			"choices": [
				{"text": "오늘은 내가 데울게.", "remember": "durga_tea",
					"reply": ["…그래. 데워 봐라.", {"who": "scene", "text": "마녀가 손을 대자\n잔에서 김이 오른다."}, "쯧. 마녀는 반칙이다.\n…그래도 따뜻하구나."]},
				{"text": "가지 마. 방은 있어.", "remember": "durga_stay",
					"reply": ["방이야 있겠지. 할미가 모르냐.\n…겨울만 나고 가마.", "손녀한텐 네가 편지 써라.\n할미 글씨는 아무도 못 읽어."]}],
			"closing": ["차 식기 전에 마셔라.\n…이번엔 정말로."]},
	],
	"ormu": [
		{"prompt": "유적 얘기요.", "title": "팔려 간 문설주",
			"opening": [
				{"if": "mem:ormu_stone", "text": "숨 쉬는 돌이 있다 했지.\n그 말 듣고 잠을 못 잤소.\n…돌 생각에."},
				{"if": "mem:ormu_wait", "text": "기다리겠다고 했지.\n돌은 기다렸소.\n나는 조금 못 기다렸소."},
				"우리 유적 말이오.\n무너진 게 아니오.\n…숙부가 팔았소. 돌 하나씩.",
				"빚 때문이었지.\n조상의 문설주가\n영주 성벽이 됐소.",
				{"who": "oswin", "if": "present:oswin", "text": "돌을 믿는 쪽이라면 나도요.\n다만 나는 그걸\n종이에 옮기지."},
				{"if": "present:oswin", "text": "그래서 기록가는\n늘 잉크가 모자란 거요."},
				{"who": "witch", "text": "돌을 믿는다면서\n숙부 얘기를 할 땐\n돌을 안 본다."}],
			"choices": [
				{"text": "지하 돌은 못 보여 줘.", "remember": "ormu_refused",
					"reply": ["…알고 있소. 묻지도 않았소.\n돌을 지키는 집이\n돌을 보여 주면 안 되지.", "…숙부도 그 말을\n들었어야 했는데."]},
				{"text": "숙부를 용서했어?", "remember": "ormu_uncle",
					"reply": ["숙부는 돌을 판 은화로\n마을을 먹였소. 흉년이었지.", "용서는 돌한테 물으시오.\n나는 아직 못 했소."]}],
			"closing": ["종이에 적지 않겠소.\n…숙부 이름은 특히."]},
		{"prompt": "찾았소.", "title": "방앗간 맷돌",
			"opening": [
				{"who": "scene", "text": "오르무 손바닥에 밀가루가\n묻어 있다. 털지 않는다."},
				"우리 문설주 하나를 찾았소.\n골짜기 방앗간에서\n맷돌이 되어 돌고 있더군.",
				{"if": "mem:ormu_refused", "text": "돌을 지키는 집 얘기 했지.\n방앗간 주인도\n그 돌을 잘 지키더군."},
				{"if": "mem:ormu_uncle", "text": "숙부 얘기를 했더니\n방앗간 주인이 그러더군.\n'흉년에 그 돌이 마을을 살렸다.'"},
				{"who": "brock", "if": "present:brock", "text": "방앗간 맷돌이라면\n값은 내가 알지요.\n드워프 돌이면… 비싸오."},
				{"if": "present:brock", "text": "값은 안 물었소, 오소리.\n…물으면 살 것 같아서."},
				{"who": "witch", "text": "밀가루를 털지 않는다.\n조상의 돌에서 나온 거라서."}],
			"choices": [
				{"text": "맷돌로 두는 게 낫겠어.", "remember": "ormu_mill",
					"reply": ["…그렇소. 문설주였을 땐\n아무도 안 먹였지.\n지금은 마을을 먹이오.", "돌은 거짓말을 안 하오.\n…그 돌, 잘 돌더군."]},
				{"text": "한 조각만 얻어 와.", "remember": "ormu_piece",
					"reply": ["모서리 한 조각이라.\n주춧돌 곁에 두면\n따뜻한 돌 곁이 되겠군.", "방앗간 주인한텐\n맷돌 정을 쪼아 주고\n바꾸겠소. 드워프식으로."]}],
			"closing": ["오늘 빵은 그 가루로 구웠소.\n조상 맛은 안 나더군.\n…그냥 빵 맛이오. 좋은."]},
	],
	"ketil": [
		{"prompt": "…주인.", "title": "아버지의 모루",
			"opening": [
				{"if": "mem:ketil_ask", "text": "…이번엔 묻소.\n양 우리 걸쇠. 헐겁소.\n…고쳐도 되오?"},
				{"if": "mem:ketil_thanks", "text": "…또 고쳤소.\n양 우리 걸쇠.\n…값 없소."},
				{"who": "scene", "text": "케틸이 모루를 내려놓는다.\n바닥이 한 번 운다."},
				"…아버지 거요.\n대장간은 없어졌소.\n모루만 남았지.",
				{"who": "signy", "if": "present:signy", "text": "케틸 아저씨는 말 대신 망치예요!\n제가 통역해 드릴까요?"},
				{"if": "present:signy", "text": "…필요 없소."},
				{"who": "signy", "if": "present:signy", "text": "'고맙다'래요!"},
				"…아버지가 그랬소.\n'말은 녹슨다. 쇠는 안 녹슨다.'\n…쇠도 녹소. 거짓말이었지.",
				{"who": "witch", "text": "모루는 사람만큼 무겁다.\n지고 다니는 건\n대장간 하나다."}],
			"choices": [
				{"text": "모루 내려놓고 쉬어.", "remember": "ketil_rest",
					"reply": ["…하룻밤만.", {"who": "witch", "text": "등이 펴지는 데\n한참 걸렸다."}]},
				{"text": "대장간은 왜 없어졌어?", "remember": "ketil_forge",
					"reply": ["…아버지가\n마녀사냥꾼 칼을\n안 벼렸소.", "…손님이 끊겼지.\n후회 안 했소. 아버지는."]}],
			"closing": ["…내일 아침. 망치 소리.\n일찍이오. …미안하오."]},
		{"prompt": "…할 말 있소.", "title": "긴 말",
			"opening": [
				{"who": "scene", "text": "케틸이 무쇠 고리 하나를\n내민다. 아직 따뜻하다."},
				"…등불 고리.\n창가에 거는 거.",
				{"if": "mem:ketil_rest", "text": "…모루 내려놓고 잤소.\n아버지 꿈을 꿨소.\n…웃었소. 아버지가."},
				{"if": "mem:ketil_forge", "text": "…칼 안 벼린 얘기.\n누구한테 한 건 처음이오.\n…가벼워졌소."},
				{"who": "fargh", "if": "present:fargh", "text": "…조용한 손이군."},
				{"if": "present:fargh", "text": "…응."},
				{"who": "witch", "if": "present:fargh", "text": "방금 이 집에서\n가장 긴 대화가 끝났다."},
				"…할 말이 있소.\n긴 거.",
				{"who": "witch", "text": "그가 숨을 두 번 고른다.\n망치를 들기 전처럼."}],
			"choices": [
				{"text": "천천히 해. 기다릴게.", "remember": "ketil_wait",
					"reply": ["…이 집에 오면\n잠이 오오.\n아버지 대장간 같아서.", "…끝이오. 길었소."]},
				{"text": "말 안 해도 알아.", "remember": "ketil_known",
					"reply": ["…알면 됐소.", "…그래도 하나만.\n고맙소. …끝."]}],
			"closing": ["…고리. 기울면 말하시오.\n…아니. 내가 보겠소."]},
	],
	"signy": [
		{"prompt": "맛 좀 봐 줄래요?", "title": "축제의 술통",
			"opening": [
				{"if": "mem:signy_potato", "text": "감자로 담갔어요! 진짜로!\n노래가 거짓말이면\n제가 참말로 만들면 되죠."},
				{"if": "mem:signy_potion", "text": "비약보다 센 술 가져왔어요.\n마시면 어떻게 되냐고요?\n…노래가 나와요."},
				{"who": "scene", "text": "작은 술통에서 거품이 넘친다.\n냄새가 조금 시큼하다."},
				"산 아래 겨울 축제에\n양조 겨루기가 있어요.\n어르신들은 저를 애 취급하고요.",
				"엄마 레시피로 나가면\n이길 수 있는데…\n그럼 제 술이 아니잖아요.",
				{"who": "erin", "if": "present:erin", "text": "딸꾹! 술 냄새!\n품평은 내가 해 줄게.\n한 잔… 아니 세 잔."},
				{"if": "present:erin", "text": "품평은 맨정신일 때\n해 주세요, 언니!"},
				{"who": "witch", "text": "엄마 얘기를 할 때만\n잔을 내려다본다."}],
			"choices": [
				{"text": "첫 잔은 내가 맛볼게.", "remember": "signy_taste",
					"reply": ["진짜요? 마녀님이?\n…어때요? 얼굴 보니 시죠?", "괜찮아요! 신 건 고쳐요.\n아무도 안 마셔 주는 게\n못 고치는 거죠."]},
				{"text": "엄마 술로 나가.", "remember": "signy_mother",
					"reply": ["…역시 그게 낫죠?\n다들 그렇게 말해요.", "…알았어요.\n근데 거품은 제 식으로 낼래요.\n그건 아무도 모를 거예요."]}],
			"closing": ["오늘 밤 통은 창가에 둘게요.\n추워야 맛이 들어요.\n…저처럼요. 농담!"]},
		{"prompt": "노래 하나 들을래요?", "title": "내려가는 음",
			"opening": [
				{"if": "mem:signy_taste", "text": "시다고 하신 거 고쳤어요.\n…이등 했어요! 이등!\n어르신들 입이 떡 벌어졌죠."},
				{"if": "mem:signy_mother", "text": "엄마 술로 나갔어요.\n일등 했어요.\n…근데 하나도 안 기뻤어요."},
				{"who": "brynhild", "if": "present:brynhild", "text": "시그뉘 술에 은화 한 닢 걸었지.\n결과는 비밀이오.\n이 애한테 물으시오."},
				{"if": "present:brynhild", "text": "언니는 아무 데나 걸잖아요!"},
				"엄마는 그 솥 노래를\n낮은 음으로 불렀어요.\n저는 올라가는 음으로요.",
				"근데 오는 길에 숲에서\n누가 낮은 음으로 부르더라고요.\n…꼭 엄마처럼요.",
				{"who": "witch", "text": "숲이 부르는 노래는\n따라가면 안 된다.\n…이번 건 모르겠다."}],
			"choices": [
				{"text": "낮은 음으로 불러 봐.", "remember": "signy_low",
					"reply": ["…엄마 음으로요?", {"who": "scene", "text": "노래가 낮게 깔린다.\n난로 불이 조금 흔들린다."}, "…이상하다.\n안 울 줄 알았는데."]},
				{"text": "네 음으로 불러.", "remember": "signy_high",
					"reply": ["올라가는 음으로요?\n좋아요! 숲이 따라 부르면\n그땐 제가 이긴 거예요!"]}],
			"closing": ["다음 통 이름 정했어요.\n'마녀의 솥'.\n…감자 들어가요. 당연히."]},
	],
}

## 다시 찾아온 손님의 첫인사가 지난 대답을 꺼낸다. 위에서부터 조건이 맞는 첫 줄을 쓴다(없으면 평소 인사).
const MEMORY_GREETINGS := {
	"harald": [
		{"if": "mem:harald_key", "text": "열쇠 잘 걸려 있군.\n…녹은 안 슬었소?"},
		{"if": "mem:harald_teach", "text": "애송이들한테 가르쳤소.\n세 번 두드리면 대답한다.\n…다들 웃더군."},
		{"if": "mem:harald_voice", "text": "눈 오는 밤이군.\n문 옆 자리, 비어 있소?"}],
	"brynhild": [
		{"if": "mem:brynhild_spring", "text": "봄이오! 내가 먼저 왔지?\n…내기는 내가 이겼소."},
		{"if": "mem:brynhild_coin", "text": "동전 잘 있소?\n…그럼 나도 잘 있는 거요."},
		{"if": "mem:brynhild_sweep", "text": "빗자루 어딨소?\n마당부터 쓸고 자지."}],
	"thorgrim": [
		{"if": "mem:thorgrim_mark", "text": "쐐기 끝 이름 봤소?\n…아직 안 웃었소?"},
		{"if": "mem:thorgrim_build", "text": "양 우리 문부터 봤소.\n결이 잘 버티더군."},
		{"if": "mem:thorgrim_hands", "text": "들보는 오늘도 곧군.\n…그 손 덕이오."}],
	"durga": [
		{"if": "mem:durga_tea", "text": "그 반칙 말이다.\n오늘도 차 데워 봐라."},
		{"if": "mem:durga_stay", "text": "또 겨울이다.\n…방 있다며. 할미 왔다."},
		{"if": "mem:durga_teach", "text": "창턱 이끼 긁었니?\n위에서 아래로."}],
	"ormu": [
		{"if": "mem:ormu_mill", "text": "방앗간 빵 가져왔소.\n조상 맛은 안 나오. 좋은 맛이지."},
		{"if": "mem:ormu_refused", "text": "지하는 안 묻겠소.\n…주춧돌만 만져 보지."},
		{"if": "mem:ormu_stone", "text": "돌이 또 따뜻해졌군.\n…숨이 고르오."}],
	"ketil": [
		{"if": "mem:ketil_wait", "text": "…왔소.\n…잠 자러."},
		{"if": "mem:ketil_rest", "text": "…모루. 내려놔도 되오?"},
		{"if": "mem:ketil_thanks", "text": "…문고리. 봤소.\n괜찮군."}],
	"signy": [
		{"if": "mem:signy_low", "text": "낮은 음 연습했어요!\n…이제 숲보다 잘해요."},
		{"if": "mem:signy_taste", "text": "새 통이에요!\n첫 잔은 또 마녀님 거예요."},
		{"if": "mem:signy_potato", "text": "감자 술 새로 담갔어요!\n…노래 가사도 고쳤고요."}],
}
