shader_type spatial;
// 투사체 꼬리 리본: 흰 심지 + 색 테두리, 꼬리로 갈수록 가늘고 투명해진다(UV.x = 머리 0 → 꼬리 1).
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 edge_color : source_color = vec4(0.75, 0.45, 1.0, 1.0);
uniform vec4 core_color : source_color = vec4(1.0, 0.95, 1.0, 1.0);
uniform float intensity = 1.6;

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float along = UV.x;
	float body = 1.0 - smoothstep(0.55, 1.0, across);
	float core = 1.0 - smoothstep(0.15, 0.4, across + along * 0.35);
	vec3 col = mix(edge_color.rgb, core_color.rgb, core);
	float fade = COLOR.a * (1.0 - along);
	ALBEDO = col * body * fade * intensity;
}
