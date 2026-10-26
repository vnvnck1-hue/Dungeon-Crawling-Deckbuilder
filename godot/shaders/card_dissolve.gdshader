shader_type canvas_item;
// 카드 표면: (1) 원근 기울기 — 드래그 방향·마우스 위치에 따라 카드가 3D로 기운 듯 사다리꼴로 보인다.
// (2) 소모 연출 — 흰 섬광 → 노이즈 경계를 따라 청록·금빛으로 타들어가며 사라진다.

uniform vec2 card_size = vec2(100.0, 120.0);
uniform vec2 tilt = vec2(0.0, 0.0);   // x: 좌우로 기울기(Y축 회전), y: 앞뒤로 기울기(X축 회전). -0.35..0.35
uniform float shine = 0.0;            // 기울기 쪽 가장자리 하이라이트
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
uniform float edge_width = 0.09;
uniform vec4 edge_color : source_color = vec4(1.0, 0.82, 0.42, 1.0);
uniform vec4 edge_color_hot : source_color = vec4(0.45, 0.95, 0.95, 1.0);
uniform sampler2D noise : repeat_enable;

varying vec4 v_modulate;
varying vec2 v_n;

void vertex() {
	v_modulate = COLOR;
	vec2 c = card_size * 0.5;
	vec2 n = (VERTEX - c) / card_size;   // -0.5..0.5
	v_n = n;
	// 멀어지는 쪽 가장자리는 짧아지고 가까운 쪽은 길어진다
	float sy = 1.0 + tilt.x * n.x * 2.0;
	float sx = 1.0 + tilt.y * n.y * 2.0;
	VERTEX = c + vec2((VERTEX.x - c.x) * sx, (VERTEX.y - c.y) * sy);
	// 원근 시 살짝 좁아지는 폭
	VERTEX.x = c.x + (VERTEX.x - c.x) * (1.0 - abs(tilt.x) * 0.25);
	VERTEX.y = c.y + (VERTEX.y - c.y) * (1.0 - abs(tilt.y) * 0.25);
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float lit = clamp(dot(v_n, -normalize(tilt + vec2(0.0001))) + 0.2, 0.0, 1.0);
	c.rgb += vec3(1.0, 0.96, 0.88) * shine * lit * lit * 0.35 * length(tilt) * 3.0;
	if (progress > 0.0 || flash > 0.0) {
		c.rgb = mix(c.rgb, vec3(1.0, 0.97, 0.9), flash);
		float nz = texture(noise, UV * 1.3).r * 0.75 + (1.0 - UV.y) * 0.25;
		float cut = progress * (1.0 + edge_width * 2.0) - edge_width;
		float d = nz - cut;
		if (d < 0.0) {
			c.a = 0.0;
		} else if (d < edge_width) {
			float k = d / edge_width;
			vec3 e = mix(edge_color_hot.rgb, edge_color.rgb, k);
			c.rgb = mix(e * 1.6, c.rgb, k * k);
			c.a *= smoothstep(0.0, 0.25, k) + 0.6 * (1.0 - k);
		}
	}
	COLOR = c * v_modulate;
}
