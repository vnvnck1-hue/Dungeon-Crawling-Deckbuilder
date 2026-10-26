shader_type spatial;
// 굴뚝 연도 안쪽(user_cottage.gd 가 뚫은 구멍의 벽·바닥). 정점색 = 그을린 돌 색, 정점색 알파 = 아래 화덕 불빛 정도.
// 산장 본체와 같은 빛 계단·색 공기(안개)를 써서 겉과 따로 놀지 않게 한다.
render_mode specular_disabled, cull_disabled;
#include "res://shaders/card_style.gdshaderinc"
uniform vec3 ember : source_color = vec3(1.0, 0.42, 0.16);
uniform float glow = 0.55;
varying vec3 world_pos;
void vertex() { world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	if (!FRONT_FACING) NORMAL = -NORMAL;
	ALBEDO = COLOR.rgb;
	EMISSION = ember * glow * COLOR.a;
	ROUGHNESS = 1.0; SPECULAR = 0.0;
	FOG = colored_air(world_pos, VERTEX, INV_VIEW_MATRIX[3].xyz);
}
void light() {
	float d = smoothstep(.06, .94, (dot(NORMAL, LIGHT) + .32) / 1.32);
	d = card_diffuse(dot(NORMAL, LIGHT), d, 1.0, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * ATTENUATION * d * 0.6;
}
