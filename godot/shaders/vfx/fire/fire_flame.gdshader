shader_type spatial;
// 화염 불꽃(premultiplied: additive 만큼만 더하고 나머지는 덮는다 → 겹쳐도 하얗게 타지 않고 색이 산다). 태어날 때 흰 심지 → core → mid → edge 로 식으며 노이즈로 깎여 몽글하게 흩어진다.
// 색은 입자 수명 비율(INSTANCE_CUSTOM.y)로 고르므로 프리셋마다 uniform 세 개만 바꾸면 된다.
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/vfx/fire/fire_common.gdshaderinc"

uniform vec4 core_color : source_color = vec4(1.0, 0.93, 0.62, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.45, 0.12, 1.0);
uniform vec4 edge_color : source_color = vec4(0.75, 0.08, 0.04, 1.0);
uniform float energy = 1.7;            // HDR 밝기. 1 이상은 환경 글로우에 걸린다
uniform float puffiness : hint_range(0.0, 1.0) = 0.6;
uniform float opacity : hint_range(0.0, 2.0) = 0.9;
uniform float noise_scale = 2.2;
uniform float scroll_speed = 1.6;
uniform float additive : hint_range(0.0, 1.0) = 0.45;  // 1 = 순수 가산
uniform float soft_distance = 0.35;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear;

void vertex() {
	fire_billboard(MODELVIEW_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX, INSTANCE_CUSTOM);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_age = INSTANCE_CUSTOM.y;
	v_seed = INSTANCE_CUSTOM.z;
}

vec3 heat_ramp(float h) {
	// h: 1 = 가장 뜨거움(흰 심지), 0 = 식은 끝
	vec3 c = mix(edge_color.rgb, mid_color.rgb, smoothstep(0.0, 0.45, h));
	c = mix(c, core_color.rgb, smoothstep(0.45, 0.85, h));
	return mix(c, vec3(1.0), smoothstep(0.88, 1.0, h) * 0.6);
}

void fragment() {
	float t = TIME * scroll_speed;
	// 나이 들수록 더 깊게 깎인다 → 위로 갈수록 덩어리가 나뉜다
	float m = fire_puff_soft(UV, v_seed, t, puffiness * (0.25 + v_age), noise_scale, 0.05);
	float core = smoothstep(0.3, 0.95, m);
	// 뜨거운 구간은 수명 앞쪽 1/3 정도, 덩어리 안쪽일수록 오래 뜨겁다
	float heat = clamp((1.0 - v_age * 1.45) * (0.5 + core * 0.7), 0.0, 1.0);
	float fade = smoothstep(0.0, 0.08, v_age) * (1.0 - smoothstep(0.5, 1.0, v_age));
	float soft = fire_soft_depth(textureLod(depth_tex, SCREEN_UV, 0.0).r, SCREEN_UV, INV_PROJECTION_MATRIX, VERTEX.z, soft_distance);
	float a = clamp(m * fade * opacity * soft, 0.0, 1.0);
	ALBEDO = heat_ramp(heat) * energy * (0.55 + heat * 0.9) * a;
	ALPHA = a * (1.0 - additive);
}
