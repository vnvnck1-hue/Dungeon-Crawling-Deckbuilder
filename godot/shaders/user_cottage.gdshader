shader_type spatial;
render_mode specular_disabled, cull_disabled;
#include "res://shaders/card_style.gdshaderinc"
uniform sampler2D cottage_paint : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
instance uniform float hit_flash = 0.0;
varying vec3 world_pos;
void vertex() { world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	if (!FRONT_FACING) NORMAL=-NORMAL;
	vec3 paint=texture(cottage_paint,UV).rgb;
	ALBEDO=mix(paint,vec3(1.0,.89,.93),hit_flash*.55);
	float window=smoothstep(.60,.87,paint.r)*smoothstep(.40,.70,paint.g)*(1.0-smoothstep(.23,.45,paint.b));
	EMISSION=paint*.035+paint*window*.55+vec3(.8,.1,.2)*hit_flash*.4;
	ROUGHNESS=.95; SPECULAR=0.0;
	FOG=colored_air(world_pos,VERTEX,INV_VIEW_MATRIX[3].xyz);
}
void light() {
	float d=smoothstep(.06,.94,(dot(NORMAL,LIGHT)+.32)/1.32);
	d=card_diffuse(dot(NORMAL,LIGHT),d,1.0,LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT+=LIGHT_COLOR/PI*ATTENUATION*d;
}
