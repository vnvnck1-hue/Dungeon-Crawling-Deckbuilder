shader_type spatial;
// 선택한 나무의 외곽선: 뒷면만 그리는 두꺼운 껍질(인버티드 헐). 표시 전용.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;
uniform vec4 line_color : source_color = vec4(1.0, 0.85, 0.35, 1.0);
uniform float width = 0.045;
uniform float pulse = 1.0;

void vertex() {
	float w = width * (0.85 + 0.15 * sin(TIME * 5.0) * pulse);
	VERTEX += NORMAL * w;
}

void fragment() {
	ALBEDO = line_color.rgb;
	ALPHA = line_color.a;
}
