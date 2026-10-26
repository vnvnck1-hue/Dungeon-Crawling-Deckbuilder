shader_type spatial;
// 화염 불티(가산). 작고 또렷한 심지 + 엷은 번짐, 깜빡이며 식는다.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://shaders/vfx/fire/fire_common.gdshaderinc"

uniform vec4 cinder_color : source_color = vec4(1.0, 0.55, 0.18, 1.0);
uniform vec4 cinder_hot : source_color = vec4(1.0, 0.92, 0.7, 1.0);
uniform float energy = 4.0;

void vertex() {
	fire_billboard(MODELVIEW_MATRIX, VIEW_MATRIX, INV_VIEW_MATRIX, MODEL_MATRIX, INSTANCE_CUSTOM);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_age = INSTANCE_CUSTOM.y;
	v_seed = INSTANCE_CUSTOM.z;
}

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float dot_core = smoothstep(0.32, 0.0, d);
	float halo = smoothstep(1.0, 0.0, d);
	halo *= halo;
	float flicker = 0.65 + 0.35 * sin(TIME * (9.0 + v_seed * 14.0) + v_seed * 40.0);
	float fade = smoothstep(0.0, 0.05, v_age) * (1.0 - smoothstep(0.6, 1.0, v_age));
	vec3 col = mix(cinder_color.rgb, cinder_hot.rgb, dot_core * (1.0 - v_age));
	float a = (dot_core + halo * 0.35) * fade * flicker;
	ALBEDO = col * energy * a;
	ALPHA = clamp(a, 0.0, 1.0);
}
