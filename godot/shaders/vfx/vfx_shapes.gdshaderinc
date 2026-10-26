// 카툰 VFX 도형 모음. 텍스처 없이 SDF로 또렷한 가장자리와 2톤 명암을 그린다.
// p: -1..1 (위쪽 +y). 반환: 직선(premultiply 전) rgb + alpha.
// 도형 번호는 scripts/visual/vfx/vfx_pool.gd 의 상수와 같아야 한다.

const int SH_GLOW = 0;
const int SH_PUFF = 1;
const int SH_STAR = 2;
const int SH_SPARKLE = 3;
const int SH_RING = 4;
const int SH_LEAF = 5;
const int SH_FOOT = 6;
const int SH_FLAKE = 7;
const int SH_STREAK = 8;
const int SH_SLASH = 9;
const int SH_SHOCK = 10;
const int SH_PLUS = 11;
const int SH_CLOUD = 12;
const int SH_CLAW = 13;
const int SH_SCORCH = 14;

float vfx_fill(float d) {
	float w = max(fwidth(d), 1e-4);
	return clamp(0.5 - d / w, 0.0, 1.0);
}

float vfx_star5(vec2 p, float r, float rf) {
	const vec2 k1 = vec2(0.809016994375, -0.587785252292);
	const vec2 k2 = vec2(-0.809016994375, -0.587785252292);
	p.x = abs(p.x);
	p -= 2.0 * max(dot(k1, p), 0.0) * k1;
	p -= 2.0 * max(dot(k2, p), 0.0) * k2;
	p.x = abs(p.x);
	p.y -= r;
	vec2 ba = rf * vec2(-k1.y, k1.x) - vec2(0.0, 1.0);
	float h = clamp(dot(p, ba) / dot(ba, ba), 0.0, r);
	return length(p - ba * h) * sign(p.y * ba.x - p.x * ba.y);
}

float vfx_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

// 구름 몽글 명암: 왼쪽 위에서 빛을 받은 쪽은 밝게, 나머지는 라벤더 그림자.
vec3 vfx_two_tone(vec3 base, vec2 p, vec2 light_c, float light_r) {
	float lit = vfx_fill(length(p - light_c) - light_r);
	vec3 shade = base * vec3(0.70, 0.72, 0.90);
	return mix(shade, base, lit);
}

vec4 vfx_shape(int shape, vec2 p, vec4 col, float seed) {
	float r = length(p);
	vec3 rgb = col.rgb;
	float a = 0.0;
	if (shape == SH_GLOW) {
		float k = clamp(1.0 - r, 0.0, 1.0);
		a = pow(k, 1.7);
		rgb = mix(col.rgb, vec3(1.0), smoothstep(0.55, 0.95, k) * 0.85);
	} else if (shape == SH_PUFF) {
		float d = r - 0.9;
		a = vfx_fill(d);
		rgb = vfx_two_tone(col.rgb, p, vec2(-0.28, 0.3), 0.78);
	} else if (shape == SH_CLOUD) {
		float d1 = length(p - vec2(-0.42, -0.2)) - 0.46;
		float d2 = length(p - vec2(0.4, -0.18)) - 0.5;
		float d3 = length(p - vec2(-0.02, 0.2)) - 0.6;
		float d = min(min(d1, d2), d3);
		a = vfx_fill(d);
		float l = min(length(p - vec2(-0.15, 0.38)) - 0.5, length(p - vec2(-0.55, 0.0)) - 0.3);
		rgb = mix(col.rgb * vec3(0.70, 0.72, 0.90), col.rgb, vfx_fill(l));
	} else if (shape == SH_STAR) {
		float d = vfx_star5(p, 0.95, 0.45);
		a = vfx_fill(d);
		rgb = mix(col.rgb, vec3(1.0, 1.0, 0.92), vfx_fill(d + 0.16));
	} else if (shape == SH_SPARKLE) {
		vec2 q = abs(p);
		float d = pow(q.x, 0.55) + pow(q.y, 0.55) - 1.0;
		a = max(vfx_fill(d * 0.6), pow(clamp(1.0 - r, 0.0, 1.0), 3.0) * 0.6);
		rgb = mix(col.rgb, vec3(1.0), vfx_fill(d + 0.45) * 0.9);
	} else if (shape == SH_RING) {
		float d = abs(r - 0.82) - 0.1;
		a = vfx_fill(d);
		rgb = mix(col.rgb, vec3(1.0), vfx_fill(abs(r - 0.82) - 0.03) * 0.7);
	} else if (shape == SH_LEAF) {
		float d = max(length(p - vec2(0.55, 0.0)) - 1.0, length(p + vec2(0.55, 0.0)) - 1.0);
		a = vfx_fill(d);
		rgb = p.x > 0.0 ? col.rgb * 0.72 : col.rgb;
		rgb = mix(rgb, col.rgb * 0.5, vfx_fill(abs(p.x) - 0.035) * step(abs(p.y), 0.7));
	} else if (shape == SH_FOOT) {
		float sole = length((p - vec2(0.0, 0.3)) / vec2(0.62, 0.66)) - 1.0;
		float heel = length((p - vec2(0.0, -0.6)) / vec2(0.5, 0.38)) - 1.0;
		float d = min(sole * 0.62, heel * 0.42);
		a = vfx_fill(d);
		// 눈이 눌린 자국: 가장자리는 조금 밝은 테두리
		rgb = mix(col.rgb + vec3(0.12, 0.12, 0.18), col.rgb, vfx_fill(d + 0.05));
	} else if (shape == SH_FLAKE) {
		a = max(vfx_fill(r - 0.55), pow(clamp(1.0 - r, 0.0, 1.0), 2.0) * 0.5);
	} else if (shape == SH_STREAK) {
		float x = p.x;
		float half_w = 0.85 * sqrt(max(1.0 - x * x, 0.0)) * (0.35 + 0.65 * (x * 0.5 + 0.5));
		float d = abs(p.y) - half_w;
		a = vfx_fill(d * 0.25) * smoothstep(-1.0, 0.1, x);
		rgb = mix(col.rgb, vec3(1.0), vfx_fill(abs(p.y) - half_w * 0.4) * 0.8);
	} else if (shape == SH_SLASH) {
		float outer = r - 0.95;
		float inner = length(p - vec2(0.0, -0.38)) - 0.92;
		float d = max(outer, -inner);
		float ang = atan(p.x, p.y);
		a = vfx_fill(d) * smoothstep(1.55, 0.4, abs(ang + 0.15));
		rgb = mix(col.rgb, vec3(1.0), vfx_fill(max(r - 0.9, -(length(p - vec2(0.0, -0.3)) - 0.92))));
	} else if (shape == SH_CLAW) {
		float d = 1e3;
		for (int i = -1; i <= 1; i++) {
			vec2 q = p - vec2(float(i) * 0.42, 0.0);
			q = vec2(q.x + q.y * 0.35, q.y);
			float w = 0.11 * sqrt(max(1.0 - q.y * q.y / 0.81, 0.0));
			d = min(d, max(abs(q.x) - w, abs(q.y) - 0.9));
		}
		a = vfx_fill(d);
		rgb = mix(col.rgb, vec3(1.0, 0.92, 1.0), vfx_fill(d + 0.04) * 0.6);
	} else if (shape == SH_SHOCK) {
		float ang = atan(p.y, p.x);
		float spikes = pow(0.5 + 0.5 * cos(ang * 9.0 + seed * 6.28), 2.5);
		float wob = 0.06 * sin(ang * 4.0 + seed * 11.0);
		float d = r - (0.55 + 0.4 * spikes + wob);
		a = vfx_fill(d * 0.6);
		vec3 hot = mix(col.rgb, vec3(1.0, 0.98, 0.85), 0.75);
		rgb = mix(col.rgb, hot, vfx_fill(r - (0.38 + 0.2 * spikes)));
		rgb = mix(rgb, vec3(1.0), vfx_fill(r - 0.22));
	} else if (shape == SH_PLUS) {
		float d = min(vfx_box(p, vec2(0.24, 0.78)), vfx_box(p, vec2(0.78, 0.24))) - 0.08;
		a = vfx_fill(d);
		rgb = mix(col.rgb * 0.75, col.rgb, vfx_fill(min(vfx_box(p - vec2(-0.05, 0.05), vec2(0.15, 0.68)), vfx_box(p - vec2(-0.05, 0.05), vec2(0.68, 0.15)))));
	} else if (shape == SH_SCORCH) {
		float ang = atan(p.y, p.x);
		float edge = 0.78 + 0.12 * sin(ang * 7.0 + seed * 9.0) + 0.06 * sin(ang * 13.0 + seed * 3.0);
		a = vfx_fill(r - edge) * (0.55 + 0.45 * smoothstep(edge, 0.0, r));
	}
	return vec4(rgb, a * col.a);
}
