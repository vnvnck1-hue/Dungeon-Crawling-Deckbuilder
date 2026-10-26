shader_type spatial;
render_mode specular_disabled, cull_disabled;
#include "res://shaders/card_style.gdshaderinc"
// User Tripo props (rocks, vines): keep the painted texture, optional light frost on upward faces
// so green moss can sit in the snowy forest without repainting the source art.
uniform sampler2D rock_paint : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform float frost_amount : hint_range(0.0, 1.0) = 0.45;
uniform vec3 frost_color : source_color = vec3(0.86, 0.90, 0.98);
uniform float moss_saturation : hint_range(0.0, 1.5) = 0.78;
uniform float paint_brightness : hint_range(0.5, 2.0) = 1.15;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
	if (!FRONT_FACING) NORMAL = -NORMAL;
	vec3 paint = texture(rock_paint, UV).rgb;
	float luma = dot(paint, vec3(.299, .587, .114));
	paint = mix(vec3(luma), paint, moss_saturation) * paint_brightness;
	float up = clamp(world_normal.y * (FRONT_FACING ? 1.0 : -1.0), 0.0, 1.0);
	float frost = smoothstep(.55, .92, up) * frost_amount;
	vec3 c = mix(paint, frost_color * (.82 + luma * .3), frost);
	ALBEDO = c;
	EMISSION = c * (.05 + up * .03) * card_style_surface.z;
	ROUGHNESS = .95; SPECULAR = 0.0;
	FOG = colored_air(world_pos, VERTEX, INV_VIEW_MATRIX[3].xyz);
}
void light() {
	float d = smoothstep(.06, .94, (dot(NORMAL, LIGHT) + .32) / 1.32);
	d = card_diffuse(dot(NORMAL, LIGHT), d, 1.0, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * ATTENUATION * d;
}
