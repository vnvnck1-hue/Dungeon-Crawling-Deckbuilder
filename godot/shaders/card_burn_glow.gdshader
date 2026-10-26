shader_type canvas_item;
render_mode blend_add;
// 카드 소모 연출의 에디티브 글로우 층: card_burn 과 같은 연소선을 따라 보랏빛 잔광을 더한다.
// 카드 위에 겹쳐 그리는 별도 사각형(card_burn 보다 넓은 pad)에 쓰며, 카드 밖으로 살짝 번진다.
//   (1) 연소선 잔광 — 선 바로 아래(탄 쪽)는 짧게, 위(남은 카드 쪽)는 길게 번지는 보라 띠. 노이즈로 일렁인다.
//   (2) 열기 — 아직 타지 않은 카드 전체에 아주 옅은 보라 덧빛. 진행에 따라 조금 강해진다.
// 두 값 모두 카드 알파를 넓힌(dilate) 마스크로 잘라 카드 윤곽 밖으로 부드럽게 흘러나온다.
#include "res://shaders/card_burn_noise.gdshaderinc"

uniform vec2 card_size = vec2(100.0, 120.0);
uniform vec2 pad = vec2(0.0, 0.0);    // 그림 사각형을 카드 밖으로 넓힌 양(px, 한쪽)
uniform vec2 tilt = vec2(0.0, 0.0);   // card_burn 과 같은 원근 기울기
uniform float progress : hint_range(0.0, 1.0) = 0.0;
#include "res://shaders/card_warp.gdshaderinc"

group_uniforms Glow;
uniform vec4 glow_color : source_color = vec4(0.62, 0.40, 1.0, 1.0);
/** 연소선 잔광 세기(에디티브, 살짝) */
uniform float glow_strength : hint_range(0.0, 2.0, 0.01) = 0.42;
/** 남은 카드 쪽으로 번지는 폭(카드 높이 대비) */
uniform float glow_width : hint_range(0.01, 0.6, 0.005) = 0.17;
/** 탄 쪽으로 남는 잔광 폭(카드 높이 대비) */
uniform float ember_width : hint_range(0.01, 0.4, 0.005) = 0.07;
/** 타지 않은 카드 전체의 옅은 열기 덧빛 */
uniform float heat_tint : hint_range(0.0, 0.5, 0.005) = 0.09;
/** 카드 윤곽 밖으로 번지는 거리(pad 대비 0..1) */
uniform float bleed : hint_range(0.0, 1.0, 0.01) = 1.0;

group_uniforms Burn;
uniform bool burn_from_top = false;
uniform float fire_thickness : hint_range(0.0, 0.4, 0.001) = 0.14;
uniform float speed : hint_range(0.0, 20.0, 0.01) = 11.4;
uniform float burn_noise_scale : hint_range(0.5, 40.0, 0.01) = 15.12;
uniform float edge_wobble : hint_range(0.0, 1.0, 0.001) = 0.865;
uniform float edge_jaggedness : hint_range(0.0, 1.0, 0.001) = 0.164;
uniform float roughness : hint_range(0.0, 1.0, 0.01) = 0.15;

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;
	vec2 c = pad + card_size * 0.5;
	vec2 n = (VERTEX - c) / card_size;
	vec3 wi;
	VERTEX = warp_vertex(VERTEX, TIME, wi);   // 카드 그림과 같은 휨·회전을 따른다
	v_warp = wi;
	float sy = 1.0 + tilt.x * n.x * 2.0;
	float sx = 1.0 + tilt.y * n.y * 2.0;
	VERTEX = c + vec2((VERTEX.x - c.x) * sx, (VERTEX.y - c.y) * sy);
	VERTEX.x = c.x + (VERTEX.x - c.x) * (1.0 - abs(tilt.x) * 0.25);
	VERTEX.y = c.y + (VERTEX.y - c.y) * (1.0 - abs(tilt.y) * 0.25);
}

float card_alpha(sampler2D tex, vec2 c) {
	float inside = step(0.0, c.x) * step(c.x, 1.0) * step(0.0, c.y) * step(c.y, 1.0);
	return texture(tex, clamp(c, 0.0, 1.0)).a * inside;
}

void fragment() {
	vec2 quad = card_size + pad * 2.0;
	vec2 c = (UV - 0.5) * quad / card_size + 0.5;
	float intensity = 0.0;
	if (progress > 0.0) {
		float a = card_alpha(TEXTURE, c);
		float aspect = card_size.x / card_size.y;
		float t = TIME * speed * 0.1;
		float h = burn_from_top ? c.y : 1.0 - c.y;
		float x = c.x * aspect;
		float e = burn_edge(x, h, t, progress, fire_thickness, edge_wobble, edge_jaggedness, burn_noise_scale, roughness);

		// 카드 윤곽을 네 단계 반지름으로 넓혀 바깥으로 갈수록 옅어지는 마스크(단계 사이는 노이즈로 흐린다)
		vec2 spill = pad / card_size * bleed;
		float dil = a * 1.4;
		float total = 1.4;
		for (int r = 1; r <= 4; r++) {
			float ring = 0.0;
			float rad = (float(r) - 0.5 + 0.5 * vnoise(vec2(x * 14.0, h * 14.0))) / 4.0;
			for (int i = 0; i < 8; i++) {
				float ang = float(i) * 0.7853982 + rad * 0.5;
				ring = max(ring, card_alpha(TEXTURE, c + vec2(cos(ang), sin(ang)) * spill * rad));
			}
			float wgt = 1.0 - float(r) / 4.0 * 0.85;
			dil += ring * wgt;
			total += wgt;
		}
		float mask = clamp(dil / total * 1.6, 0.0, 1.0);

		// (1) 연소선 잔광: 위(남은 카드)는 넓게, 아래(탄 쪽)는 좁게
		float w = e >= 0.0 ? glow_width : ember_width;
		float line_glow = exp(-abs(e) / max(w, 1e-4));
		float flicker = 0.82 + 0.18 * vnoise(vec2(x * 9.0, TIME * 7.0));
		// 탄 쪽 끝부분이 여리게 남는 숯불 느낌
		float ember = e < 0.0 ? 0.35 * exp(-abs(e) / (ember_width * 2.2)) * (0.5 + 0.5 * vnoise(vec2(x * 22.0, h * 22.0 + TIME * 2.0))) : 0.0;

		// (2) 열기: 아직 남은 카드에 옅은 보라 덧빛(연소가 진행될수록 조금 강해짐)
		float unburnt = smoothstep(0.0, 0.03, e);
		float heat = heat_tint * (0.5 + 0.5 * progress) * unburnt * a;

		// 끝나갈 때 전체를 거둔다
		float fade = 1.0 - smoothstep(0.86, 1.0, progress);
		intensity = ((line_glow * flicker + ember) * glow_strength * mask + heat) * fade;
	}
	COLOR = vec4(glow_color.rgb * v_modulate.rgb, intensity * glow_color.a * v_modulate.a);
}
