shader_type spatial;
// 지면에 눕는 카툰 VFX(발자국·충격 고리·그을음·마법진). PlaneMesh(XZ) 한 장을 MultiMesh로 그린다.
// INSTANCE_CUSTOM = (가로 크기, 세로 크기, Y축 회전, 도형번호 + 0.5×가산여부)
render_mode blend_premul_alpha, unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

#include "res://shaders/vfx/vfx_shapes.gdshaderinc"

varying vec4 v_custom;
varying vec4 v_color;
varying float v_seed;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_color = COLOR;
	v_seed = fract(MODEL_MATRIX[3].x * 0.137 + MODEL_MATRIX[3].z * 0.291);
	float c = cos(INSTANCE_CUSTOM.z);
	float s = sin(INSTANCE_CUSTOM.z);
	vec2 q = VERTEX.xz * INSTANCE_CUSTOM.xy;
	q = vec2(q.x * c + q.y * s, -q.x * s + q.y * c);
	VERTEX = vec3(q.x, 0.0, q.y);
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
