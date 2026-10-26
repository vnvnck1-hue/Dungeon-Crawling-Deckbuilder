// 카드 소모 연출 공용: 노이즈와 연소선 계산. card_burn(카드 표면)과 card_burn_glow(에디티브 글로우)가
// 같은 연소선을 쓰도록 한 곳에 둔다. 매개변수는 각 셰이더의 uniform 을 그대로 넘긴다.

// 정수 해시: 실수 해시는 GPU 반올림 오차로 격자 경계에서 값이 어긋나 세로 단차가 생긴다
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(p)) * uvec2(1597334673u, 3812015801u);
	uint n = (q.x ^ q.y) * 1597334673u;
	return float(n) * (1.0 / 4294967295.0);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p, float gain) {
	float v = 0.0;
	float amp = 1.0;
	float total = 0.0;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		total += amp;
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= gain;
	}
	return v / total;
}

// 연소선이 카드 밖에서 시작해 밖에서 끝나도록 더하는 여유(카드 높이 대비)
float burn_margin(float k_thickness, float k_wobble, float k_jag) {
	return k_thickness + k_wobble * 0.15 + k_jag * 0.3 + 0.02;
}

// 연소선 기준 부호 거리. e < 0 : 탄 부분, e > 0 : 남은 카드. x = 카드 UV x * 종횡비, h = 연소 진행 축(0=시작 가장자리)
// (매개변수 이름은 셰이더 uniform 과 겹치면 안 되므로 k_ 접두사)
float burn_edge(float x, float h, float t, float k_progress, float k_thickness, float k_wobble, float k_jag, float k_noise_scale, float k_roughness) {
	// 연소선 왜곡: 큰 물결(wobble) + 2D 노이즈 톱니(jaggedness)
	float wob = (vnoise(vec2(x * k_noise_scale * 0.25, t * 0.15)) - 0.5) * k_wobble * 0.3;
	float gain = mix(0.05, 0.6, k_roughness);
	float jag = (fbm(vec2(x * k_noise_scale, h * k_noise_scale * 0.45 + t * 0.2), gain) - 0.5) * k_jag * 0.6;
	float margin = burn_margin(k_thickness, k_wobble, k_jag);
	float line = mix(-margin, 1.0 + margin, k_progress);
	return h - line + wob + jag;
}
