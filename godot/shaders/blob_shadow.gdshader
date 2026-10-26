shader_type spatial;
// 캐릭터 발밑 둥근 그림자: 실제 그림자 대신 몸보다 한 단계 밝고 푸른 원으로 실루엣과 바닥을 떼어 놓는다. 표시 전용.
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 shadow_color : source_color = vec4(0.10, 0.12, 0.32, 0.50);
uniform float softness = 0.55;
// 디딤돌·눈 굴곡처럼 높이가 제각각인 바닥에 묻히지 않도록 카메라 쪽으로 이만큼(m) 당겨 그린다.
uniform float lift = 0.35;

void vertex() {
	vec4 v = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	v.xyz += normalize(-v.xyz) * lift;
	POSITION = PROJECTION_MATRIX * v;
}

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	ALBEDO = shadow_color.rgb;
	ALPHA = shadow_color.a * (1.0 - smoothstep(1.0 - softness, 1.0, d));
}
