shader_type canvas_item;
// 손님 초상 아이들링 + 등장 가슴 모핑(사용자 요청 2026-10-22, 에린 대화 창). docs/erin-portrait-motion.md
// 뼈 없는 한 장 일러스트를 UV 비틀기(화면 픽셀이 원화의 조금 다른 자리를 읽음)로 숨·몸 흔들림·고개·가슴 흔들림처럼 움직인다.
// 발끝은 고정이고 위로 갈수록 크게 움직여 본(bone) 아이들링처럼 보인다. 모든 변위는 부드러운 마스크로 이어져 찢어지지 않는다.
uniform float motion_time = 0.0;                           // 대화 창 시계(초). 스크립트가 매 프레임 올린다
uniform float appear = -1.0;                               // 초상이 등장한 뒤 지난 시간(초). 음수면 등장 흔들림 없음
uniform float idle_amount : hint_range(0.0, 2.0) = 0.0;    // 0 이면 완전히 정지. 프로필에 portrait_motion 이 있을 때만 켠다
uniform float breath_rate = 1.8;                           // 숨 주기(rad/s) ≈ 3.5초에 한 번
uniform vec2 head_center = vec2(0.55, 0.16);               // 머리 중심(UV)
uniform float head_radius = 0.17;
uniform float chest_amount : hint_range(0.0, 2.0) = 0.0;   // 가슴 모핑 세기. 0 이면 없음
uniform vec2 chest_center = vec2(0.40, 0.36);              // 가슴 영역 중심(UV)
uniform vec2 chest_radius = vec2(0.15, 0.11);              // 가슴 영역 반지름(UV, 가로·세로)
uniform float chest_freq = 9.5;                            // 등장 흔들림 진동수(rad/s)
uniform float chest_decay = 2.4;                           // 감쇠(1/s): 약 1.5초 뒤 거의 멈춘다
uniform float chest_swing = 0.018;                         // 등장 흔들림 최대 세로 변위(UV, 600px 초상에서 약 11px)
uniform bool rounded_hem = false;                         // 직선으로 잘린 에린 치마 밑단만 알파 마스킹. 원본 RGB는 보존.
// 인물별 성격(2026-10-23, 전 손님 적용. docs/portrait-motion-all.md). 기본값이면 에린 원래 모습과 같다.
uniform float motion_phase = 0.0;                          // 시계 위상(초). 손님마다 달라 둘이 같은 박자로 숨쉬지 않는다
uniform float breath_amount = 1.0;                         // 숨 크기 배율(오크는 크게, 요정은 작게)
uniform float sway_amount = 1.0;                           // 몸 좌우 흔들림 배율(드워프는 묵직하게 작게)
uniform float sway_rate = 1.0;                             // 몸 흔들림 빠르기 배율(고블린은 부산하게)
uniform float head_amount = 1.0;                           // 고개 움직임 배율
// 보조 움직임: 타원 안을 accent_center 기준으로 accent_axis 방향으로 늘였다 줄인다(요정 날개 파닥임·고블린/수인 귀 쫑긋).
uniform float accent_amount = 0.0;                         // 0 이면 없음
uniform vec2 accent_center = vec2(0.5, 0.3);
uniform vec2 accent_radius = vec2(0.4, 0.25);
uniform vec2 accent_axis = vec2(1.0, 0.0);                 // 늘이는 방향 가중(x 가로·y 세로)
uniform float accent_rate = 5.0;                           // 진동(rad/s)
uniform float accent_inner = 0.0;                          // 데드존 폭(UV). 날개·옆 귀는 가운데 얼굴을 빼고 양옆만, 머리 위 귀는 얼굴 위쪽만 움직인다
uniform float accent_burst = 0.0;                          // 0 = 계속 진동(날개), 1 = 몇 초에 한 번 짧게 씰룩(귀)

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;  // TextureRect 의 modulate(등장 알파·종족색)를 그대로 넘긴다
}

// 타원 안쪽 1 → 가장자리 0 으로 부드럽게 꺼지는 마스크(smootherstep)
float soft_mask(vec2 uv, vec2 c, vec2 r) {
	float d = length((uv - c) / r);
	float m = 1.0 - smoothstep(0.0, 1.0, d);
	return m * m * (3.0 - 2.0 * m);
}

void fragment() {
	vec2 uv = UV;
	float t = motion_time + motion_phase;
	float h = clamp(1.0 - uv.y, 0.0, 1.0);                 // 발끝 0 → 머리 꼭대기 1
	vec2 d = vec2(0.0);

	// 1) 숨쉬기: 상체가 아주 조금 떠올랐다 내려앉고, 가슴 높이에서 몸통 폭이 살짝 넓어진다
	float breath = sin(t * breath_rate);
	float torso = smoothstep(0.25, 0.6, h) * (1.0 - smoothstep(0.75, 0.95, h));
	d.y += 0.0045 * breath * breath_amount * smoothstep(0.1, 0.7, h);
	d.x += (uv.x - 0.45) * 0.010 * breath * breath_amount * torso;

	// 2) 몸 흔들림: 발끝 고정, 위로 갈수록 좌우로 천천히(두 주기를 섞어 기계적으로 보이지 않게)
	float st = t * sway_rate;
	d.x += (0.0055 * sin(st * 0.53) + 0.0025 * sin(st * 0.91 + 1.3)) * h * h * sway_amount;

	// 3) 고개: 숨에 맞춰 살짝 끄덕이고 느리게 기운다
	float head = soft_mask(uv, head_center, vec2(head_radius, head_radius * 1.15));
	d.x += 0.0035 * sin(st * 0.77 + 0.6) * head * head_amount;
	d.y += 0.0025 * sin(t * breath_rate + 0.4) * head * head_amount;

	// 4) 보조: 날개는 계속 천천히 파닥이고, 귀는 몇 초에 한 번 짧게 씰룩인다(burst 가 문 역할)
	float gate = mix(1.0, pow(max(sin(t * 0.61 + 1.7), 0.0), 24.0), accent_burst);
	float wave = sin(t * accent_rate) * gate;
	// 데드존: 가로 축이면 중심에서 좌우로 떨어진 곳만(날개·옆 귀), 세로 축이면 중심보다 위쪽만(머리 위 귀)
	float along = accent_axis.x >= accent_axis.y ? abs(uv.x - accent_center.x) : accent_center.y - uv.y;
	float side_gate = accent_inner > 0.0 ? smoothstep(accent_inner * 0.6, accent_inner * 1.6, along) : 1.0;
	d -= (uv - accent_center) * accent_axis * (accent_amount * wave) * soft_mask(uv, accent_center, accent_radius) * side_gate;
	d *= idle_amount;

	// 5) 가슴: 숨에 따른 작은 부풀기 + 등장 순간의 감쇠 진동(모핑처럼 중심에서 바깥으로 퍼졌다 돌아온다)
	float chest = soft_mask(uv, chest_center, chest_radius);
	float on = step(0.0, appear);
	float env = exp(-chest_decay * max(appear, 0.0)) * on;
	float jiggle = env * sin(chest_freq * max(appear, 0.0));
	vec2 cd = vec2(0.0);
	cd.y += chest_swing * jiggle;
	cd.x += 0.25 * chest_swing * env * sin(chest_freq * 0.5 * max(appear, 0.0) + 0.8);
	cd.y += 0.003 * breath;
	cd -= (uv - chest_center) * (0.06 * jiggle + 0.015 * breath);
	d += cd * chest * chest_amount;

	vec2 suv = clamp(uv - d, vec2(0.0), vec2(1.0));
	COLOR = texture(TEXTURE, suv) * v_modulate;
	if (rounded_hem) {
		// 상반신·손·술병은 그대로 두고 마지막 치마 구간만 둥근 초상 외곽으로 마감한다.
		float side = abs((suv.x - 0.55) / 0.36);
		float hem = 0.969 - 0.075 * pow(side, 1.7);
		// 작은 비대칭 요철로 곧은 절단선을 없앤다. 넓은 페이드 없이 경계 1px만 안티앨리어싱.
		hem += 0.003 * sin(suv.x * 83.0) + 0.0015 * sin(suv.x * 193.0 + 0.8);
		float edge = max(fwidth(suv.y), TEXTURE_PIXEL_SIZE.y) * 0.5;
		COLOR.a *= 1.0 - smoothstep(hem - edge, hem + edge, suv.y);
	}
}
