shader_type spatial;
// 카메라를 향하는 카툰 VFX 입자(MultiMesh 한 장으로 수백 개를 그린다).
// INSTANCE_CUSTOM = (가로 크기, 세로 크기, 화면 회전, 도형번호 + 0.5×가산여부)
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

#include "res://shaders/vfx/vfx_shapes.gdshaderinc"

varying vec4 v_custom;
varying vec4 v_color;
varying float v_seed;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR;
	v_seed = fract(MODEL_MATRIX[3].x * 0.137 + MODEL_MATRIX[3].z * 0.291 + float(INSTANCE_ID) * 0.618);
	float c = cos(INSTANCE_CUSTOM.z);
	float s = sin(INSTANCE_CUSTOM.z);
	vec2 q = VERTEX.xy * INSTANCE_CUSTOM.xy;
	q = vec2(q.x * c - q.y * s, q.x * s + q.y * c);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	VERTEX = vec3(q, 0.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	int shape = int(floor(v_custom.w + 0.01));
	float additive = step(0.25, fract(v_custom.w + 0.01));
	vec4 c = vfx_shape(shape, p, v_color, v_seed);
	if (c.a < 0.003) {
		discard;
	}
	ALBEDO = c.rgb * c.a;
	ALPHA = c.a * (1.0 - additive);
}
