extends RefCounted
## 손님 이야기 연작(docs/pentiment-dialogue-research-v01.md §3.1~3.2, 2026-10-25 인간 7명 시범).
## 1편은 guest_dialogues.gd STORIES 그대로이고, 다시 찾아올 때마다 2편·3편이 이어진다.
## 선택의 remember 는 손님 기억 장부(guest_events.memory)에 남아 다음 편·재방문 인사가 그 대답을 꺼낸다.
##
## 박자(beat) 형식 — opening·choices[].reply·closing 은 문자열 하나 또는 박자 목록이다.
##   "문자열"                        이야기하는 손님의 한 마디(3줄 안)
##   {"text": …}                     같음. "if" 를 붙일 수 있다
##   {"who": "<손님 id>", "text": …}  산장에 묵고 있는 다른 손님이 끼어든다(그 손님이 없으면 건너뜀)
##   {"who": "witch", "text": …}     마녀의 생각(괄호 글, 연보라)
##   {"who": "scene", "text": …}     장면 묘사(괄호 글, 옅은 청록)
## 조건 "if": 문자열 하나 또는 목록(모두 참이어야 함). 앞에 "!" 를 붙이면 반대.
##   mem:<표시>  기억 장부   present:<id>  묵고 있는 다른 손님   day>=N / day<=N
##   merchant_day  오늘 브로크가 왔다   black_sheep  목장에 검은 양이 있다
## 선택지는 2개 이상 적을 수 있고, 조건을 통과한 앞의 2개를 쓴다.

## 1편(STORIES)의 두 선택지가 남기는 기억. 순서는 choices 와 같다.
const PART1_MEMORY := {
	"bram": ["bram_fair", "bram_grandpa"],
	"mira": ["mira_weed", "mira_book"],
	"olaf": ["olaf_deer", "olaf_fear"],
	"torbin": ["torbin_road", "torbin_mark"],
	"neri": ["neri_read", "neri_bring"],
	"oswin": ["oswin_hush", "oswin_hearth"],
	"sera": ["sera_plain", "sera_share"],
}

## 손님 id → [2편, 3편]
const ARCS := {
	"bram": [
		{"prompt": "주인, 잠깐이면 되오.", "title": "문 옆의 검",
			"opening": [
				{"who": "scene", "text": "브람이 문 옆 벽에 검을 세워 두었다.\n칼끝이 바깥을 향해 있다."},
				{"if": "mem:bram_fair", "text": "값을 깎지 않는 집이라 또 왔소.\n빚진 기분 없이 자는 곳은\n드물거든."},
				{"if": "mem:bram_grandpa", "text": "지난번 할아버지 얘기 말이오.\n털어놓고 나니… 이상하게\n잠이 잘 왔소."},
				"그런데 마을에선 날 두고\n'마녀 집 문지기'라 부르더군.\n…비웃는 거요.",
				{"who": "thistle", "if": "present:thistle", "text": "인간이 문지기라니, 숲이 웃겠군요.\n…하지만 문을 지키는 손은\n횃불을 든 손보다 낫습니다."},
				{"if": "present:thistle", "text": "…요정 나리, 귀가 밝으시군.\n그 말은 칭찬으로 듣겠소."},
				{"who": "witch", "text": "비웃음보다, 그 별명이 싫지 않은 게\n더 곤란한 얼굴이다."}],
			"choices": [
				{"text": "문지기 품삯은 안 줘.", "remember": "bram_wage",
					"reply": ["하! 품삯 받으면 진짜 문지기 되지.\n공짜라야 내 마음대로\n서 있다 갈 수 있소."]},
				{"text": "그 사람들한테 뭐라고 했어?", "remember": "bram_answer",
					"reply": ["'문지기면 어떻소, 안에 수프가 있는데.'\n…그 뒤로 아무도 안 웃더군.", "몇은 길을 물었소.\n이 집 가는 길을."]}],
			"closing": ["오늘 밤도 칼끝은 바깥이오.\n…안쪽은 볼 일이 없으니."]},
		{"prompt": "보여 줄 게 있소.", "title": "할아버지의 등불",
			"opening": [
				{"who": "scene", "text": "브람이 낡은 등불 하나를 탁자에 올린다.\n그을음이 두껍다."},
				"할아버지 유품이오.\n횃불을 내려놓은 뒤로\n평생 이 등불만 들고 다녔다지.",
				{"if": "mem:bram_grandpa", "text": "'불빛을 따라가면 마녀 집이 나온다.'\n…그 말, 당신한테 처음 했소.\n이제야 뜻을 알 것 같군."},
				{"if": "!mem:bram_grandpa", "text": "죽기 전에 이상한 말을 했소.\n'불빛을 따라가면 마녀 집이 나온다.'\n…이제야 뜻을 알 것 같군."},
				"이 등불, 이 집 창가에 두고 가겠소.\n길 잃은 놈이 따라오게.",
				{"who": "witch", "text": "마녀사냥꾼의 등불이\n마녀 집 창가에서 길을 비춘다.\n…받아도 될까."}],
			"choices": [
				{"text": "창가에 둬. 기름은 네가 채우고.", "remember": "bram_lamp",
					"reply": ["…그러지. 사흘에 한 번은 들르겠소.\n기름 핑계로.", {"who": "witch", "text": "빚을 안 남기는 사람이\n처음으로 핑계를 만들었다."}]},
				{"text": "할아버지 등불은 네가 들어.", "remember": "bram_keeps",
					"reply": ["…그렇군. 이건 내 짐이지.\n당신 집 창가가 아니라.", "그럼 길에서 이 불빛을 보는 놈은\n이 집 쪽으로 데려오겠소.\n그건 되지?"]}],
			"closing": ["할아버지는 불을 들고 마녀를 쫓았고\n나는 불을 들고 마녀 집을 찾았소.", "…집안 내력이 꽤 바뀌었군."]},
	],
	"mira": [
		{"prompt": "책 얘기, 기억하세요?", "title": "찢긴 첫 장",
			"opening": [
				{"who": "scene", "text": "미라가 약초 바구니를 내려놓는다.\n맨 위에 서리 맞은 달맞이풀이 있다."},
				{"if": "mem:mira_weed", "text": "그냥 잡초라고 하셨죠?\n잡초가 상처를 이렇게 빨리\n아물게 하던데요. 이것 보세요."},
				{"if": "mem:mira_book", "text": "그 책이요, 다시 봤어요.\n찢긴 첫 장 뒷면에\n눈송이 같은 표식이 남아 있었어요."},
				"할머니는 그 책을 '빌린 책'이라고만\n했어요. 누구한테서인지는\n끝까지 말 안 해 주셨고요.",
				{"who": "durga", "if": "present:durga", "text": "얘, 빌린 책은 돌려줘야 하는 거다.\n백 년이 지나도."},
				{"if": "present:durga", "text": "…백 년이요? 할머니, 그 책 아세요?"},
				{"who": "durga", "if": "present:durga", "text": "모른다. 드워프는 책보다\n빌려 간 놈 얼굴을 기억하지.\n…밥이나 먹어라."},
				{"who": "witch", "text": "눈송이 표식. 북쪽 마녀의 표식이다.\n…할머니의 할머니가 쓰던."}],
			"choices": [
				{"text": "그 책, 나한테 보여 줄 수 있어?", "remember": "mira_shows",
					"reply": ["…가져오면 돌려 달라고 하실 거죠?", "아, 아니에요. 원래 주인이면\n돌려드리는 게 맞죠.\n다음에 꼭 가져올게요."]},
				{"text": "할머니 말대로 빌린 책으로 둬.", "remember": "mira_keeps",
					"reply": ["빌린 책으로요?\n…그럼 제가 계속 빌리고 있는 거네요.\n갚을 게 늘었어요. 약초로 갚을게요."]}],
			"closing": ["오늘 밤엔 첫 장을 다시 붙여 볼게요.\n밥풀로요. 마녀님 밥으로."]},
		{"prompt": "가져온 게 있어요.", "title": "겨울에 피는 까닭",
			"opening": [
				{"if": "mem:mira_shows", "text": "가져왔어요. 약속대로요.\n…손이 떨리네요. 왜 떨리지."},
				{"who": "scene", "if": "mem:mira_shows", "text": "책장을 넘기던 마녀의 손이 멈춘다.\n여백마다 낯익은 글씨다."},
				{"if": "!mem:mira_shows", "text": "책은 안 가져왔어요.\n대신 겨울 약초 장만 베껴 왔어요.\n제 글씨라 엉망이에요."},
				"책에 이런 구절이 있어요.\n'겨울에 피는 풀은\n누군가 아직 이 집에 산다는 뜻.'",
				{"who": "witch", "text": "그래서 겨울에도 핀다.\n내가 여기 사니까."}],
			"choices": [
				{"text": "그 풀, 너도 키워 봐.", "remember": "mira_grows",
					"reply": ["제가요? 마녀도 아닌데요?", "…'누군가 산다는 뜻'이면\n제 집에도 사람은 사니까요.\n해 볼게요!"]},
				{"text": "그 구절은 다른 데 말하지 마.", "remember": "mira_secret",
					"reply": ["…네. 약초꾼은 입이 무거워요.\n독초가 어디 나는지도\n아무한테나 안 알려 주거든요."]}],
			"closing": ["할머니가 왜 이 책을 아꼈는지 알겠어요.", "…빌린 사람이 아니라\n맡은 사람이었나 봐요."]},
	],
	"olaf": [
		{"prompt": "수프 얘기는 아니오.", "title": "사라진 호위 대장",
			"opening": [
				{"if": "mem:olaf_deer", "text": "사슴을 잡아 왔소. 약속대로.\n…추가 요금은 없는 거요."},
				{"who": "scene", "if": "mem:olaf_deer", "text": "문밖에 사슴 한 마리가\n눈을 덮고 누워 있다. 꽤 크다."},
				{"if": "!mem:olaf_deer", "text": "오늘은 토끼 두 마리요.\n사슴은 눈치가 빨라서.\n…수프에 넣어 주시오."},
				"호위하던 상단이 흩어졌소.\n대장이 돈 궤를 들고 사라졌지.\n…석 달 치 품삯이오.",
				{"who": "sera", "if": "present:sera", "text": "혹시 '회색 말' 상단이에요?\n장터에 소문 났어요.\n대장이 남쪽 항구로 갔대요."},
				{"if": "present:sera", "text": "…남쪽이라. 고맙소, 장사꾼.\n소문은 장터가 제일 빠르군."},
				{"who": "witch", "text": "무뚝뚝한 얼굴인데\n숟가락 쥔 손에 힘이 들어가 있다."}],
			"choices": [
				{"text": "쫓아갈 거야?", "remember": "olaf_chase",
					"reply": ["…쫓아가면 석 달을 더 쓰지.\n그 돈 받자고. 셈이 안 맞소.", "…그래도 화는 나는군."]},
				{"text": "이 겨울엔 여기서 사냥해.", "remember": "olaf_stays",
					"reply": ["…품삯은 못 주는 집이잖소.\n수프로 받으라는 거요?", "…나쁘지 않군.\n고기 있는 수프면."]}],
			"closing": ["오늘은 한 그릇만.\n…아니, 두 그릇.\n화가 나면 배가 고프오."]},
		{"prompt": "물어볼 게 있소.", "title": "역참 네 곳의 수프",
			"opening": [
				"새 일을 구했소. 북쪽 국경 역참 호위.\n이 집에서 반나절 거리요.",
				{"if": "mem:olaf_stays", "text": "겨울 내내 여기서 사냥한 덕에\n활 솜씨가 늘었소.\n새 대장이 그걸 보고 뽑더군."},
				{"if": "mem:olaf_chase", "text": "결국 안 쫓아갔소.\n대신 새 대장 얼굴을 오래 봤지.\n이번 대장은 돈 냄새가 안 나오."},
				"그래서 묻는 거요.\n역참 사람들한테 이 집 수프를\n…소문내도 되겠소?"],
			"choices": [
				{"text": "'안 잡아먹음'만 빼고.", "remember": "olaf_rumor",
					"reply": ["하. 고블린 행상 광고 말이오?\n그건 이미 국경까지 퍼졌소.", "…나는 '고기는 추가 요금'만\n말하겠소."]},
				{"text": "조용한 게 좋아.", "remember": "olaf_quiet",
					"reply": ["…알겠소. 역참 넷 중\n여기가 제일 낫다는 건\n나 혼자 알고 있겠소."]}],
			"closing": ["역참 셋을 돌았다고 했던가.\n…이제 넷이오. 여기까지 쳐서."]},
	],
	"torbin": [
		{"prompt": "길 얘기요.", "title": "길을 묻는 사람들",
			"opening": [
				"옛 산길 말이오.\n요즘 그 길로 사람이 오오.\n나 말고도.",
				{"if": "mem:torbin_road", "text": "길이 아직 쓸 만하다고 했지.\n…그 말을 술집에서 했더니\n이렇게 됐소. 내 탓이오."},
				{"if": "mem:torbin_mark", "text": "문양을 안 지웠소.\n그랬더니 문양을 따라온 사람들이\n생겼소. 길잡이도 없이."},
				"피난민이오. 남쪽 마을이\n'뭔가'에 쫓겨 비었다더군.\n…다들 이 집을 찾고 있소.",
				{"who": "luka", "if": "present:luka", "text": "길잡이 밥줄 끊겼네요, 토르빈 씨.\n우리 여우들은 그 길 안 써요.\n문양이 꼭 눈 같아서요."},
				{"who": "witch", "text": "남쪽. 남쪽 자매의 땅이다.\n…그쪽 봉인석은 무사할까."}],
			"choices": [
				{"text": "오는 사람은 받아.", "remember": "torbin_open",
					"reply": ["…방이 모자랄 거요.\n그럼 나는 마구간에서 자지.", "원래 창문에서 먼 방이 좋았소.\n마구간은 창문이 없지."]},
				{"text": "길 입구에 표시를 해 둬.", "remember": "torbin_sign",
					"reply": ["표시라. 문양 옆에 하나 더?\n…'방 없음'이라 새길까.", "농담이오.\n등불 하나 더 새기지."]}],
			"closing": ["길잡이가 길을 안 숨기니\n먹고살 게 줄겠군.\n…이상하게 서운하지 않소."]},
		{"prompt": "하나만 묻겠소.", "title": "새 이정표",
			"opening": [
				{"who": "scene", "text": "토르빈의 손이 돌가루투성이다."},
				"이정표를 하나 새로 세웠소.\n옛 것 옆에.",
				{"if": "mem:torbin_sign", "text": "등불 문양도 하나 더 새겼소.\n…내 솜씨라 비뚤어졌지만."},
				"물어볼 게 있소.\n옛 이정표를 세운 건 누구요?\n…마녀였소? 아니면 다른 누구?",
				{"who": "witch", "if": "mem:heard:oswin", "text": "돌에 새긴 손이 둘이었다고\n오스윈이 말했었다.\n마녀의 손과… 다른 손."}],
			"choices": [
				{"text": "마녀와… 그 친구.", "remember": "torbin_truth",
					"reply": ["친구라. 마녀사냥 전엔\n마녀에게도 친구가 있었군.", "…당연한 얘긴데\n처음 생각해 보오."]},
				{"text": "모르는 게 나아.", "remember": "torbin_hush",
					"reply": ["…그렇군. 길잡이는\n길 끝만 알면 되오.\n누가 닦았는지는 돌이 알겠지."]}],
			"closing": ["내 이정표엔 이름을 안 새겼소.\n…그건 그 사람들한테 배운 거요."]},
	],
	"neri": [
		{"prompt": "크, 큰일 났어요!", "title": "잃어버린 한 통",
			"opening": [
				"'숲의 마녀' 앞 편지,\n하나를 잃어버렸어요!\n배달부 인생 최대 사고예요!",
				{"if": "mem:neri_bring", "text": "가져오라고 하셔서 챙겼는데\n…가방 구멍으로 하나가.\n나머지 아홉 통은 여기 있어요!"},
				{"if": "mem:neri_read", "text": "안 읽었어요! 정말로!\n…근데 잃어버린 건 봉투가 찢어져서\n조금 보였어요. 조금만."},
				{"if": "mem:neri_read", "text": "'숲의 마녀님, 그 겨울에\n제 아이를 살려 주셔서…'\n거기까지요! 진짜 거기까지!"},
				{"who": "oswin", "if": "present:oswin", "text": "편지 한 통이면 숲길 어딘가에서\n누가 주워 읽겠지.\n…기록은 원래 그렇게 퍼지는 거요."},
				{"who": "witch", "text": "그 겨울.\n어느 겨울인지 기억한다."}],
			"choices": [
				{"text": "잃어버린 건 괜찮아.", "remember": "neri_forgiven",
					"reply": ["괜찮다고요? 배달부한테\n그건 제일 무서운 말인데…", "…그래도 고마워요.\n울 뻔했어요. 아니, 조금 울었어요."]},
				{"text": "같이 찾으러 가자.", "remember": "neri_search",
					"reply": ["진짜요? 마녀님이 숲길에?", "…그럼 편지가 무서워서\n알아서 튀어나오겠네요!"]}],
			"closing": ["다음엔 가방부터 꿰맬게요.\n…실은 어디 뒀더라."]},
		{"prompt": "이번엔 반대예요!", "title": "답장",
			"opening": [
				"마녀님이 답장을 쓰시면\n제가 배달할게요.\n이번엔 안 잃어버려요!",
				{"if": "mem:neri_search", "text": "그날 같이 찾은 편지,\n개울가 바위 밑에 있었잖아요.\n…거기 주소가 있었어요."},
				"받을 사람들이 다 마을에 있어요.\n'고맙습니다' 열 통의 주인들이요.",
				{"who": "witch", "text": "답장을 하면, 마녀가 여기 산다는 걸\n열 집이 확실히 알게 된다."}],
			"choices": [
				{"text": "한 줄씩만 쓸게. '잘 지내.'", "remember": "neri_reply",
					"reply": ["'잘 지내.' 열 번이요?", "…좋아요. 짧은 편지가\n제일 오래 남아요.\n배달부 경험이에요."]},
				{"text": "답장은 안 해.", "remember": "neri_silent",
					"reply": ["…그럼 제가 말로 전할게요.\n'편지 잘 받았대요.'\n그 정도는 배달부 재량이에요."]}],
			"closing": ["오늘은 가방이 가벼워요.\n…그래서 더 무거운 것 같아요."]},
	],
	"oswin": [
		{"prompt": "문양을 더 베꼈소.", "title": "왼손잡이 석공",
			"opening": [
				"두 번째 손은 왼손잡이였소.\n획이 반대로 기울었지.",
				{"if": "mem:oswin_hush", "text": "모르는 척하라고 했지.\n…그래서 책엔 안 적고\n머릿속에만 적었소. 더 무겁더군."},
				{"if": "mem:oswin_hearth", "text": "말한 대로 기록은 난로 곁에 두었소.\n…주인 몰래 반 장은 탔소.\n불이 너무 좋아서."},
				"왼손잡이 석공은 드물지.\n그런데 이 집 들보 이음새도\n왼쪽으로 기울었소.",
				{"who": "thorgrim", "if": "present:thorgrim", "text": "맞소. 들보 짠 손은 왼손이오.\n쐐기 없이.\n…드워프도 못 하는 솜씨지."},
				{"who": "witch", "text": "할머니의 할머니는 오른손잡이였다.\n그럼 이 집을 지은 건…"}],
			"choices": [
				{"text": "이 집을 같이 지었겠지.", "remember": "oswin_built",
					"reply": ["…같이라. 마녀와 워록이\n한 지붕을 올렸다면.", "마녀사냥은 대체\n무엇을 끊은 거요."]},
				{"text": "들보 얘기는 그만해.", "remember": "oswin_stop",
					"reply": ["알겠소. 하지만 나는 기록가요.\n멈추라면 멈추지만\n잊으라는 말은 못 듣소."]}],
			"closing": ["오늘 밤 잉크는 아끼겠소.\n…쓸 수 없는 것이 늘어서."]},
		{"prompt": "떠나기 전에.", "title": "쓰지 않은 기록",
			"opening": [
				"보여 줄 게 있소.",
				{"who": "scene", "text": "오스윈이 가죽 장부 하나를 내민다.\n첫 장부터 끝까지 비어 있다."},
				"이 집에 대한 기록이오.\n…아무것도 안 적었소.\n적으면 누군가 읽을 테니.",
				{"if": "mem:oswin_built", "text": "마녀와 그 '다른 손'이\n함께 지은 집이라는 것.\n그건 책보다 돌에 맡기겠소."},
				{"who": "witch", "text": "빈 장부.\n그가 쓸 수 있는 가장 긴 기록이다."}],
			"choices": [
				{"text": "한 줄만 적어. '따뜻했다.'", "remember": "oswin_line",
					"reply": ["…'따뜻했다.'", "그건 누가 읽어도 괜찮겠군.\n마녀사냥꾼이 읽어도."]},
				{"text": "빈 채로 둬. 내가 보관할게.", "remember": "oswin_keep",
					"reply": ["주인이 빈 장부를 맡는다.\n…기록가로서 이보다 나은\n결말은 못 썼을 거요."]}],
			"closing": ["다음 유적은 동쪽이오.\n거기에도 두 손이 있다면\n또 오겠소. 잉크를 사서."]},
	],
	"sera": [
		{"prompt": "장터 소식이에요!", "title": "양털 감독관",
			"opening": [
				"마녀네 양털 소문, 결국\n누가 '확인'하러 온대요.",
				{"if": "mem:sera_share", "text": "셋으로 나누자고 했잖아요.\n그 말 하고 다녔더니\n값이 진짜 두 배가 됐어요."},
				{"if": "mem:sera_plain", "text": "그냥 양털이라고 하셨죠.\n그 말 했더니 아무도 안 믿어요.\n'마녀가 숨긴다'고요."},
				"오는 사람은 남쪽 모직 조합\n감독관이에요.\n…돈 냄새 맡는 코가 길어요.",
				{"who": "brock", "if": "present:brock", "text": "그 감독관 말이오?\n지난달 내 좌판에서 깎다가\n동전 하나 떨어뜨리고 갔지."},
				{"if": "present:brock", "text": "그 동전 돌려줬어요, 브로크 씨?"},
				{"who": "brock", "if": "present:brock", "text": "…좌판에 떨어진 건 좌판 거요."},
				{"if": "black_sheep", "text": "그리고… 그 검은 양이요.\n그건 소문 내지 마세요.\n검은 양털은 값을 매길 수가 없어요."},
				{"who": "witch", "text": "양털이 비에 안 젖는 건 사실이다.\n양이 아니라, 울타리에 건\n서리 결계 덕이지만."}],
			"choices": [
				{"text": "감독관한테 젖은 양털을 보여 줘.", "remember": "sera_trick",
					"reply": ["하! 물통에 담갔다 꺼낸 걸로요?", "…좋아요, 연기는 제가 할게요.\n장사꾼은 원래 반은 배우예요."]},
				{"text": "직접 와서 보라고 해.", "remember": "sera_invite",
					"reply": ["여기로요? 감독관이 마녀 집에?", "…오면 숙박비 두 배 받으세요.\n제 몫은 안 받을게요. 이번만."]}],
			"closing": ["양한테 오늘 저녁은 좋은 풀 주세요.\n…모르는 척 연기해야 하니까."]},
		{"prompt": "감독관 얘기예요.", "title": "감독관의 할머니",
			"opening": [
				{"if": "mem:sera_trick", "text": "감독관 다녀갔어요.\n젖은 양털 보고 코웃음 치더니\n'소문은 소문'이래요. 성공!"},
				{"if": "mem:sera_invite", "text": "감독관이 진짜 왔다 갔어요.\n하룻밤 묵고 아무 말 없이\n양털 한 묶음을 비싸게 사 갔어요."},
				"근데 이상해요.\n떠나면서 저한테 그러더라고요.",
				"'그 집 주인, 우리 할머니가\n말하던 사람 같다'고요.",
				{"who": "witch", "text": "감독관의 할머니.\n누군가 이 집을 또 기억하고 있다."}],
			"choices": [
				{"text": "누구 할머니였는지 알아 와.", "remember": "sera_trace",
					"reply": ["오, 장사 말고 탐문이요?", "…알아 올게요. 대신 정보비는\n양털로요. 젖은 거 말고."]},
				{"text": "장사나 잘해.", "remember": "sera_trade",
					"reply": ["넵, 장사나 잘할게요.", "…근데 마녀님, 지금\n살짝 웃으셨어요. 봤어요."]}],
			"closing": ["다음엔 모직 조합 도장 찍힌\n주문서 들고 올게요.\n'안 젖는 양털, 세 묶음'."]},
	],
}

## 다시 찾아온 손님의 첫인사가 지난 대답을 꺼낸다. 위에서부터 조건이 맞는 첫 줄을 쓴다(없으면 평소 인사).
const MEMORY_GREETINGS := {
	"bram": [
		{"if": "mem:bram_lamp", "text": "창가 등불이 보이더군.\n…기름 채울 차례라 왔소."},
		{"if": "mem:bram_keeps", "text": "등불 들고 왔소.\n길에서 둘을 이리 보냈지.\n…방 있소?"},
		{"if": "mem:bram_fair", "text": "값 안 깎는 집이라 또 왔소.\n…수프 값은 똑같지?"}],
	"mira": [
		{"if": "mem:mira_grows", "text": "우리 집 앞에도 한 송이 폈어요!\n겨울인데요! 보여 드리고 싶어서요."},
		{"if": "mem:mira_shows", "text": "책 얘기, 아직 기억하시죠?\n오늘은 빈손 아니에요."},
		{"if": "mem:mira_book", "text": "찢긴 첫 장이 계속 생각나서요.\n…오늘 밤도 신세 질게요."}],
	"olaf": [
		{"if": "mem:olaf_quiet", "text": "…조용히 왔소.\n아무한테도 말 안 했소."},
		{"if": "mem:olaf_stays", "text": "또 겨울 사냥철이오.\n수프 냄새 따라왔소."},
		{"if": "mem:olaf_deer", "text": "사슴 약속은 지켰소.\n오늘은 수프만 주시오. 돈 내고."}],
	"torbin": [
		{"if": "mem:torbin_open", "text": "오늘도 길에 사람이 있었소.\n…다 이 집 쪽이더군."},
		{"if": "mem:torbin_road", "text": "옛 산길로 왔소.\n…문양이 오늘도 이 집을 가리키더군."}],
	"neri": [
		{"if": "mem:neri_reply", "text": "답장 다 배달했어요!\n열 집 다 울었어요. 저도요."},
		{"if": "mem:neri_forgiven", "text": "이번엔 가방 꿰맸어요!\n…한쪽만요."}],
	"oswin": [
		{"if": "mem:oswin_keep", "text": "빈 장부는 잘 있소?\n…가끔 생각나더군."},
		{"if": "mem:oswin_built", "text": "들보부터 보러 왔소.\n…인사는 그다음이오."}],
	"sera": [
		{"if": "mem:sera_invite", "text": "감독관 다녀간 뒤로\n장터에서 제 값이 올랐어요!\n오늘은 제가 차 살게요."},
		{"if": "mem:sera_share", "text": "셋으로 나눈 몫 가져왔어요.\n…양 몫은 풀로요."}],
}

## 종족별 연작 파일(같은 세 상수 PART1_MEMORY · ARCS · MEMORY_GREETINGS). 위 인간 7명과 합쳐 쓴다.
const RACE_FILES := [
	"res://scripts/game/arcs/arcs_dwarf.gd",
	"res://scripts/game/arcs/arcs_fairy.gd",
	"res://scripts/game/arcs/arcs_goblin.gd",
	"res://scripts/game/arcs/arcs_beastfolk.gd",
	"res://scripts/game/arcs/arcs_orc.gd",
]
static var _merged: Dictionary = {}

## 인간 + 종족 파일을 합친 {"part1", "arcs", "greetings"}. 처음 한 번만 읽는다.
static func merged() -> Dictionary:
	if not _merged.is_empty(): return _merged
	var out := {"part1": PART1_MEMORY.duplicate(true), "arcs": ARCS.duplicate(true), "greetings": MEMORY_GREETINGS.duplicate(true)}
	for path in RACE_FILES:
		if not ResourceLoader.exists(path): continue
		var script: GDScript = load(path)
		var consts: Dictionary = script.get_script_constant_map()
		out.part1.merge(consts.get("PART1_MEMORY", {}))
		out.arcs.merge(consts.get("ARCS", {}))
		out.greetings.merge(consts.get("MEMORY_GREETINGS", {}))
	_merged = out
	return _merged

static func all_part1() -> Dictionary: return merged().part1
static func all_arcs() -> Dictionary: return merged().arcs
static func all_greetings() -> Dictionary: return merged().greetings

## 이 손님의 n편(0 = 1편). 없으면 빈 사전. 1편에는 PART1_MEMORY 의 기억 표시를 붙여 준다.
static func part(id: String, index: int, first: Dictionary) -> Dictionary:
	if index <= 0:
		var story := first.duplicate(true)
		var flags: Array = all_part1().get(id, [])
		for i in mini(flags.size(), story.get("choices", []).size()):
			story["choices"][i]["remember"] = flags[i]
		return story
	var parts: Array = all_arcs().get(id, [])
	if index - 1 >= parts.size(): return {}
	return parts[index - 1].duplicate(true)

static func part_count(id: String) -> int:
	return 1 + all_arcs().get(id, []).size()
