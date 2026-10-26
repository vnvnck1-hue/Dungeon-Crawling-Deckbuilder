shader_type spatial;
// 캐릭터 분리용 카툰 림라이트(TF2식을 툰 띠로): 실루엣 가장자리 중 위쪽을 향한 면에만 경계가 또렷한 앰버 띠를 가산으로 얹는다.
// 부드러운 프레넬 그라데이션 대신 문턱값으로 잘라 셀 셰이딩처럼 한 단으로 보이게 한다(2026-10-21 사용자 요청).
// material_overlay(외곽선)의 next_pass 로 붙어 스킨·묶음 애니메이션을 그대로 따라간다. 표시 전용.
render_mode unshaded, blend_add, cull_back, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 rim_color : source_color = vec4(1.0, 0.68, 0.32, 1.0);
uniform float strength = 0.6;
uniform float rim_width = 0.42;   // 클수록 띠가 두껍다(1 - 프레넬 문턱)
uniform float top_cut = 0.15;     // 위쪽을 향한 정도가 이 값을 넘는 면에만 띠를 둔다
uniform float edge = 0.015;       // 띠 경계 안티에일리어싱 폭(작을수록 딱딱하다)

void fragment() {
	float fres = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	vec3 up_view = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	float up = dot(NORMAL, up_view);
	float band = smoothstep(1.0 - rim_width - edge, 1.0 - rim_width + edge, fres)
		* smoothstep(top_cut - edge * 4.0, top_cut + edge * 4.0, up);
	ALBEDO = rim_color.rgb * band * strength;
}
