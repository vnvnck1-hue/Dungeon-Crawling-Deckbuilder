shader_type spatial;
// 상태이상 껍질: 유닛 몸 파츠를 살짝 부풀린 복제 메시에 덮어 상태를 몸 색으로 보여 준다(view/status_fx.gd).
// 화상 = 발밑에서 타오르는 주황 불꽃 띠, 냉기 = 푸른 서리 테두리와 얼음 반점, 빙결 = 전신 얼음 막, 투지 = 붉게 맥동하는 테두리.
// 각 세기는 0..1. 원본 캐릭터 셰이더는 마녀산장 것이라 고치지 않고, 이 껍질만 따로 그린다.
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform float burn : hint_range(0.0, 1.0) = 0.0;
uniform float chill : hint_range(0.0, 1.0) = 0.0;
uniform float freeze : hint_range(0.0, 1.0) = 0.0;
uniform float fury : hint_range(0.0, 1.0) = 0.0;
uniform float pulse = 0.0;          // 상태가 막 걸린 순간 번쩍(1 → 0)
uniform float base_y = 0.0;         // 유닛 발 높이(세계 y)
uniform float height = 1.8;         // 유닛 키(m)
uniform float grow = 0.012;         // 법선 방향으로 부풀리는 양(m, 모델 공간 배율 보정 전)
instance uniform float hit_flash = 0.0;   // Fx.flash 가 모든 칠한 메시에 거는 값(여기서는 쓰지 않음)

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	VERTEX += NORMAL * (grow + freeze * 0.025);
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	float h = clamp((wpos.y - base_y) / max(height, 0.1), 0.0, 1.0);
	vec3 col = vec3(0.0);
	float a = 0.0;

	// 화상: 아래에서 위로 일렁이는 불꽃 띠(세기만큼 높이 올라온다)
	if (burn > 0.001) {
		vec2 q = vec2(wpos.x * 2.6 + wpos.z * 1.7, wpos.y * 2.2 - TIME * 2.4);
		float n = vnoise(q) * 0.65 + vnoise(q * 2.3 + 7.1) * 0.35;
		float reach = 0.25 + 0.6 * burn;
		float flame = smoothstep(reach + 0.15, reach - 0.25, h + (n - 0.5) * 0.45);
		vec3 fc = mix(vec3(1.0, 0.32, 0.05), vec3(1.0, 0.85, 0.3), clamp(n * 1.3 - h, 0.0, 1.0));
		float fa = flame * (0.55 + 0.35 * n) * (0.55 + 0.45 * burn) + fres * 0.35 * burn;
		col += fc * fa;
		a = max(a, fa);
	}
	// 냉기: 푸른 서리 테두리 + 얼음 반점(세기만큼 늘어난다)
	if (chill > 0.001) {
		float spots = step(1.0 - chill * 0.55, vnoise(wpos.xz * 9.0 + wpos.y * 6.0));
		float ca = (fres * 0.8 + spots * 0.45) * (0.35 + 0.65 * chill);
		col += vec3(0.62, 0.88, 1.0) * ca;
		a = max(a, ca);
	}
	// 빙결: 전신을 덮는 연푸른 얼음 막 + 흰 테두리
	if (freeze > 0.001) {
		float crack = smoothstep(0.47, 0.5, abs(vnoise(wpos.xy * 5.0 + wpos.z * 3.0) - 0.5) * 2.0 - 0.45);
		vec3 ic = mix(vec3(0.55, 0.82, 1.0), vec3(0.95, 1.0, 1.0), fres + crack * 0.6);
		float ia = freeze * (0.5 + 0.45 * fres + crack * 0.2);
		col = mix(col, ic, freeze);
		a = max(a, ia);
	}
	// 투지: 붉게 맥동하는 테두리
	if (fury > 0.001) {
		float beat = 0.65 + 0.35 * sin(TIME * 6.0);
		float ra = fres * fury * beat * 0.9;
		col += vec3(1.0, 0.18, 0.08) * ra;
		a = max(a, ra);
	}
	col += vec3(1.0) * pulse * 0.6;
	a = max(a, pulse * 0.5 * (0.4 + fres));
	ALBEDO = col / max(a, 0.001);
	ALPHA = clamp(a, 0.0, 0.92);
}
