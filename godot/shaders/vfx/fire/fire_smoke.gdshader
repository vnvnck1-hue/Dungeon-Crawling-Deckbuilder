shader_type spatial;
// 화염 연기(반투명 혼합). 불 바로 위에서는 불빛을 머금은 tint 색, 오르면서 smoke 색으로 식고 크게 퍼지며 사라진다.
// 지면·물체와 맞닿는 곳은 깊이로 부드럽게 지우고(소프트 입자), 카메라 바로 앞에서도 흐려진다.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

#include "res://shaders/vfx/fire/fire_common.gdshaderinc"

uniform vec4 smoke_color : source_color = vec4(0.12, 0.13, 0.24, 1.0);
uniform vec4 tint_color : source_color = vec4(0.55, 0.12, 0.08, 1.0);
uniform float tint_glow = 1.4;         // 불 근처 연기가 불빛을 받는 정도
uniform float puffiness : hint_range(0.0, 1.0) = 0.7;
uniform float opacity : hint_range(0.0, 1.0) = 0.55;
uniform float noise_scale = 2.1;
uniform float scroll_speed = 0.35;
uniform float soft_distance = 0.6;
uniform float camera_fade = 1.2;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

void vertex() {
	fire_billboard(MODELVIEW_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX, INSTANCE_CUSTOM);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_age = INSTANCE_CUSTOM.y;
	v_seed = INSTANCE_CUSTOM.z;
}

void fragment() {
	float t = TIME * scroll_speed;
	float m = fire_puff(UV, v_seed, t, puffiness, noise_scale);
	// 덩어리 안쪽 결: 진한 곳과 엷은 곳이 섞여 2톤 연기로 읽힌다
	float inner = fire_fbm(UV * noise_scale * 1.7 + vec2(v_seed * 9.0, -t * 1.4));
	float fade = smoothstep(0.0, 0.18, v_age) * (1.0 - smoothstep(0.45, 1.0, v_age));
	float warm = 1.0 - smoothstep(0.0, 0.35, v_age);
	vec3 col = mix(smoke_color.rgb, tint_color.rgb * tint_glow, warm);
	col *= 0.7 + inner * 0.65;

	float soft = fire_soft_depth(textureLod(depth_tex, SCREEN_UV, 0.0).r, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z, soft_distance);
	float near = smoothstep(0.2, camera_fade, -VERTEX.z);

	ALBEDO = col;
	ALPHA = clamp(m * fade * opacity * (0.6 + inner * 0.8) * soft * near, 0.0, 1.0);
}
