shader_type canvas_item;
render_mode blend_add;
// 카드 획득·공개·소모 순간의 에디티브 글로우. 원이 아니라 카드 윤곽(둥근 사각형) 모양을 따라 퍼진다.
// 카드 중심에 둔 사각형(card_size + pad*2)에 그리며, 모든 모양은 둥근 사각형 부호 거리(SDF)로 만든다.
//   (1) 섬광 — 카드 안쪽을 가득 채운 뒤 빠르게 걷히는 흰빛(코어색). 카드 밖으로는 짧게 번진다.
//   (2) 충격파 — 카드 윤곽에서 출발해 밖으로 퍼지는 띠. 퍼질수록 얇고 옅어지고, 각도 노이즈로 일렁인다.
//       두 번째 겹(시간차)은 card_fx.card_glow 가 노드를 하나 더 만들어 올린다.
//   (3) 광선 — 윤곽에서 바깥으로 뻗는 가는 줄기(각도 노이즈). 초반에만 잠깐.
//   색은 안쪽 코어색 → 가운데 금색 → 바깥 가장자리색으로 거리에 따라 흐른다.
#include "res://shaders/card_burn_noise.gdshaderinc"

uniform vec2 card_size = vec2(100.0, 150.0);
uniform vec2 pad = vec2(80.0, 80.0);          // 사각형을 카드 밖으로 넓힌 양(px, 한쪽)
uniform float corner : hint_range(0.0, 0.5, 0.005) = 0.08; // 카드 모서리 반지름(카드 폭 대비)
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;

group_uniforms Colors;
uniform vec4 color_core : source_color = vec4(1.0, 0.97, 0.88, 1.0);
uniform vec4 color_mid : source_color = vec4(1.0, 0.76, 0.32, 1.0);
uniform vec4 color_edge : source_color = vec4(0.40, 0.80, 1.0, 1.0);

group_uniforms Shape;
/** 충격파가 퍼지는 최대 거리(카드 폭 대비) */
uniform float spread : hint_range(0.1, 2.0, 0.01) = 0.42;
/** 충격파 시작 두께(카드 폭 대비) */
uniform float ring_width : hint_range(0.01, 0.4, 0.005) = 0.09;
/** 섬광 세기 */
uniform float flash_strength : hint_range(0.0, 3.0, 0.01) = 0.9;
/** 충격파 세기 */
uniform float ring_strength : hint_range(0.0, 3.0, 0.01) = 0.85;
/** 광선 세기 */
uniform float ray_strength : hint_range(0.0, 3.0, 0.01) = 0.9;

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
}

// 둥근 사각형 부호 거리(px). 안쪽은 음수
float rbox(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// 텐션 있는 이징: 빠르게 튀어나와 길게 여운
float ease_out_expo(float t) {
	return 1.0 - pow(2.0, -9.0 * t);
}

float ease_out_quart(float t) {
	float u = 1.0 - t;
	return 1.0 - u * u * u * u;
}

void fragment() {
	vec2 quad = card_size + pad * 2.0;
	vec2 p = (UV - 0.5) * quad;                   // 카드 중심 기준 px
	float w = card_size.x;
	float d = rbox(p, card_size * 0.5, corner * w) / w;  // 카드 윤곽 기준 거리(카드 폭 단위)
	float ang = atan(p.y, p.x);
	float t = clamp(progress, 0.0, 1.0);

	// (1) 섬광: 안쪽 가득 → 걷힘. 가장자리부터 걷혀 안쪽이 마지막까지 남는다
	float flash_t = 1.0 - ease_out_quart(t);          // 1 → 0
	float inside = smoothstep(0.015, -0.06, d);
	float core_hold = smoothstep(0.0, -0.35, d);       // 카드 깊숙한 안쪽
	float flash = inside * flash_t * flash_t * (0.55 + 0.45 * core_hold);
	float bleed = exp(-max(d, 0.0) / (0.06 + 0.10 * flash_t)) * flash_t * 0.55;
	flash += bleed * (1.0 - inside);

	// (2) 충격파: 윤곽에서 spread 까지. 두께는 퍼질수록 얇아지고, 각도 노이즈로 일렁인다
	float wave = ease_out_expo(t);
	float linger = pow(1.0 - t, 0.8);                    // 여운: 끝까지 서서히
	float r1 = wave * spread;
	float shimmer = 0.65 + 0.35 * vnoise(vec2(ang * 2.6 + seed * 7.0, t * 5.0 + seed));
	float width1 = ring_width * (1.0 - 0.55 * wave) * shimmer;
	float ring1 = exp(-pow((d - r1) / max(width1, 1e-3), 2.0));
	ring1 *= linger * (1.0 - 0.45 * wave) * shimmer;
	float outside = smoothstep(-0.04, 0.0, d);
	float ring = ring1 * outside;                       // 안쪽으로는 번지지 않게
	// 충격파 뒤에 남는 넓고 부드러운 후광(카드 윤곽을 감싸는 블룸)
	float halo = exp(-max(d, 0.0) / (0.1 + 0.18 * wave)) * pow(1.0 - t, 1.6) * 0.3 * outside;

	// (3) 광선: 각도 노이즈를 날카롭게 깎아 가는 줄기. 윤곽 바깥에서 멀어질수록 사라진다
	float ray_n = vnoise(vec2(ang * 4.0 + seed * 3.0, seed * 11.0));
	ray_n = max(ray_n, vnoise(vec2(ang * 9.0 + seed * 5.0 + 3.1, seed * 2.0)) * 0.85);
	float rays = pow(max(ray_n - 0.38, 0.0) * 1.9, 2.2);
	float ray_reach = exp(-max(d, 0.0) / (0.12 + 0.4 * wave));
	float ray_t = pow(1.0 - t, 1.3);
	rays *= ray_reach * ray_t * outside * smoothstep(0.0, 0.04, d);

	// 색: 거리·시간으로 코어 → 금색 → 가장자리색
	float k = clamp(d / max(spread, 1e-3) * 0.9 + 0.3 * t, 0.0, 1.0);
	vec3 grad = mix(color_mid.rgb, color_edge.rgb, smoothstep(0.15, 0.95, k));
	vec3 ring_col = mix(color_core.rgb, grad, smoothstep(0.0, 0.5, k + 0.2));   // 띠 안쪽 가장자리만 살짝 희게
	vec3 flash_col = mix(color_core.rgb, color_mid.rgb, 0.3 + 0.7 * smoothstep(-0.08, 0.1, d));
	vec3 col = flash * flash_strength * flash_col
	         + ring * ring_strength * ring_col
	         + halo * ring_strength * grad
	         + rays * ray_strength * mix(color_mid.rgb, color_edge.rgb, 0.4 + 0.6 * wave);

	// 사각형 가장자리에서 0 으로: 후광·광선의 꼬리가 사각형 경계로 드러나지 않게
	vec2 edge = min(UV, 1.0 - UV);
	col *= smoothstep(0.0, 0.2, min(edge.x, edge.y));

	// 에디티브: 색에 세기를 곱해 두고 알파는 modulate(퇴장 페이드)만 쓴다 → 밝은 곳이 희게 뭉개지지 않는다
	COLOR = vec4(col * v_modulate.rgb * v_modulate.a, 1.0);
}
