shader_type canvas_item;
// 로비 인물 아이들링(사용자 요청 2026-10-24). docs/lobby.md
// 일곱 인물이 한 장으로 붙은 레이어(assets/ui/lobby/lobby_characters.png)를 구역별로 UV 비틀기 한다.
// 구역마다 목·허리 피벗을 중심으로 아주 작게 기울고(두 주기를 섞어 기계적이지 않게), 숨에 맞춰 위쪽이 살짝 떠오른다.
// 부위(모자·귀·날개·더듬이)는 부모 인물의 움직임을 이어받고 제 움직임을 더한다.
// 구역 경계는 부드러운 가중치 텍스처(tools/build_lobby_weights.gd)로 섞여 찢어지지 않는다. 모든 좌표는 원화 픽셀(1920×1080).
const int REGIONS = 12;

uniform float motion_time = 0.0;                         // 로비 시계(초). 스크립트가 매 프레임 올린다
uniform float idle_amount : hint_range(0.0, 2.0) = 1.0;  // 0 이면 원화 그대로 정지
uniform vec2 canvas_px = vec2(1920.0, 1080.0);
uniform sampler2D weights_0 : filter_linear, repeat_disable;  // 구역 0~3 가중치(RGBA)
uniform sampler2D weights_1 : filter_linear, repeat_disable;  // 구역 4~7
uniform sampler2D weights_2 : filter_linear, repeat_disable;  // 구역 8~11
// 구역별 값(scripts/ui/lobby_rig.gd). pivot: 피벗 x·y(px), 기울기 진폭(rad), 기울기 각속도(rad/s)
uniform vec4 rig_pivot[REGIONS];
// breath: 위상(초), 숨에 떠오르는 높이(px), 숨 각속도(rad/s), 숨에 부푸는 비율
uniform vec4 rig_breath[REGIONS];
// extra: 씰룩임 문(0 = 계속 흔들림, 1 = 몇 초에 한 번 짧게), 부모 구역(-1 이면 없음), 문 각속도(rad/s), 미사용
uniform vec4 rig_extra[REGIONS];

// 구역 i 가 화면 픽셀 p 에서 만드는 변위(px). 원화의 p - d 자리를 읽는다.
vec2 motion(int i, vec2 p) {
	vec4 pv = rig_pivot[i];
	vec4 br = rig_breath[i];
	vec4 ex = rig_extra[i];
	float t = motion_time + br.x;
	vec2 c = pv.xy;
	// 기울기: 느린 주기 + 더 느린 엇박 주기
	float gate = mix(1.0, pow(max(sin(t * ex.z + 1.3), 0.0), 18.0), ex.x);
	float a = pv.z * (0.72 * sin(t * pv.w) + 0.28 * sin(t * pv.w * 1.61 + 1.1)) * gate;
	vec2 q = p - c;
	float ca = cos(a);
	float sa = sin(a);
	vec2 src = c + vec2(ca * q.x + sa * q.y, -sa * q.x + ca * q.y);   // 역회전으로 원화 자리를 찾는다
	// 숨: 피벗보다 위쪽만 세로로 살짝 부풀고(어깨가 오르는 느낌) 전체가 조금 떠오른다
	float b = sin(t * br.z);
	float above = smoothstep(0.0, 120.0, c.y - src.y);
	src.y = mix(src.y, c.y + (src.y - c.y) / (1.0 + br.w * b), above);
	src.y += br.y * (0.5 + 0.5 * b) * smoothstep(-80.0, 160.0, c.y - p.y);
	return p - src;
}

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;  // fragment 의 COLOR 는 이미 텍스처가 곱해져 있어 modulate 만 따로 넘긴다
}

void fragment() {
	vec2 uv = UV;
	vec2 p = uv * canvas_px;
	vec2 d = vec2(0.0);
	// 가중치를 한 번에 펼친다(벡터 성분을 변수 인덱스로 읽지 않는다 — 일부 백엔드 미지원)
	vec4 w0 = texture(weights_0, uv);
	vec4 w1 = texture(weights_1, uv);
	vec4 w2 = texture(weights_2, uv);
	float ws[REGIONS] = float[REGIONS](w0.r, w0.g, w0.b, w0.a, w1.r, w1.g, w1.b, w1.a, w2.r, w2.g, w2.b, w2.a);
	for (int i = 0; i < REGIONS; i++) {
		float w = ws[i];
		if (w < 0.002) continue;
		vec2 di = motion(i, p);
		int parent = int(rig_extra[i].y);
		if (parent >= 0) di += motion(parent, p);
		d += w * di;
	}
	vec2 suv = clamp((p - d * idle_amount) / canvas_px, vec2(0.0), vec2(1.0));
	COLOR = texture(TEXTURE, suv) * v_modulate;
}
