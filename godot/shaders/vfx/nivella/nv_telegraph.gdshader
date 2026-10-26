// 니벨라 공격 예고 장판(바닥 평면). shape 0 = 원, 1 = 줄(UV.y 가 보스 → 끝). fill 0→1 로 안쪽이 차오르고,
// 다 차면 그 순간 공격이 떨어진다. 가장자리 테두리는 처음부터 또렷해 피할 범위를 바로 읽을 수 있다.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform int shape = 0;
uniform float fill : hint_range(0.0, 1.0) = 0.0;
uniform float alpha = 1.0;
uniform vec4 edge_color : source_color = vec4(0.62, 0.86, 1.0, 1.0);
uniform vec4 fill_color : source_color = vec4(0.30, 0.55, 1.0, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.42, 0.55, 1.0);

void fragment() {
	float d;          // 0 = 시작(가운데/보스 쪽), 1 = 가장자리/끝
	float border;
	if (shape == 0) {
		vec2 p = UV * 2.0 - 1.0;
		d = length(p);
		border = smoothstep(0.90, 0.95, d) * (1.0 - smoothstep(0.98, 1.0, d));
		if (d > 1.0) discard;
	} else {
		d = UV.y;
		float side = abs(UV.x * 2.0 - 1.0);
		border = smoothstep(0.82, 0.9, side) * (1.0 - smoothstep(0.97, 1.0, side));
	}
	// 안쪽 줄무늬(빙결 결): 가장자리 쪽으로 흐른다
	float stripes = 0.5 + 0.5 * sin(d * 34.0 - TIME * 6.0);
	float inside = step(d, fill);
	float front = exp(-pow((d - fill) / 0.035, 2.0)) * step(0.01, fill);
	// 다 차 갈수록 붉은 위험색으로 기운다
	vec3 body = mix(fill_color.rgb, hot_color.rgb, smoothstep(0.55, 1.0, fill));
	vec3 col = body * (0.75 + stripes * 0.25);
	col = mix(col, edge_color.rgb, border);
	col += vec3(1.0) * front * 0.8;
	float a = 0.10 + border * 0.75 + inside * (0.26 + stripes * 0.08) + front * 0.6;
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0) * alpha;
}
