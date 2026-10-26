shader_type spatial;
// 적 대상 지정 외곽선(롤식): 뒷면만 그리는 껍질을 화면 공간에서 일정한 픽셀 두께로 밀어낸다.
// material_overlay 로 붙이므로 스킨·IK·애니메이션을 그대로 따라간다. 표시 전용.
render_mode unshaded, cull_front, depth_draw_opaque, shadows_disabled, fog_disabled;
uniform vec4 line_color : source_color = vec4(1.0, 0.18, 0.12, 1.0);
uniform float width_px = 3.0;
uniform float pulse = 0.0;

void vertex() {
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	vec3 vn = (MODELVIEW_MATRIX * vec4(NORMAL, 0.0)).xyz;
	vec2 dir = (PROJECTION_MATRIX * vec4(vn, 0.0)).xy;
	float len = length(dir);
	if (len > 1e-5) {
		float w = width_px * (1.0 + 0.18 * sin(TIME * 7.0) * pulse);
		clip.xy += dir / len * w * 2.0 / VIEWPORT_SIZE * clip.w;
	}
	POSITION = clip;
}

void fragment() {
	ALBEDO = line_color.rgb;
}
