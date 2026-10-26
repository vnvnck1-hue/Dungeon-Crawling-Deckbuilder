shader_type spatial;
// Preserve the GLB's two-sided surface display when replacing its material.
render_mode specular_disabled, cull_disabled, shadows_disabled;
#include "res://shaders/card_style.gdshaderinc"
uniform sampler2D paint_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_texture = false;
uniform float paint_gain = 1.0;
uniform float painted_fill = .11;
uniform float texture_mix = 1.0;
uniform vec4 base_color : source_color = vec4(1.0);
instance uniform float hit_flash = 0.0;
varying vec3 world_pos;
varying vec3 world_normal;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL,0.0)).xyz);
}
void fragment() {
	if (!FRONT_FACING) NORMAL = -NORMAL;
	vec3 c = base_color.rgb;
	if (use_texture) c = mix(c,c * texture(paint_texture,UV).rgb * paint_gain,texture_mix*card_style_ink.y);
	float dist = length((world_pos.xz - vec2(1.0,1.3)) / vec2(1.1,1.0));
	float edge = smoothstep(8.0,21.0,dist);
	vec3 cool = mix(vec3(.40,.37,.66),vec3(.30,.55,.64),smoothstep(-10.0,14.0,world_pos.x-world_pos.z));
	c *= mix(vec3(1.0),cool,edge*.75);
	c *= 1.0-edge*.55;
	vec3 neutral = vec3(dot(c,vec3(.2126,.7152,.0722)))*vec3(1.02,1.0,1.04);
	c = mix(c,neutral,card_style_palette.w);
	c = card_surface_color(c,NORMAL,VIEW,.35);
	ALBEDO = mix(c,vec3(1.0,.87,.93),hit_flash*.55);
	ROUGHNESS = 1.0; SPECULAR = 0.0;
	// Small painted fill preserves hue in shadow without flattening actual geometry.
	EMISSION = (c*painted_fill + c*max(world_normal.y,0.0)*.035)*card_style_surface.z + vec3(.8,.1,.2)*hit_flash*.4;
	FOG = colored_air(world_pos,VERTEX,INV_VIEW_MATRIX[3].xyz);
}
void light() {
	float d = smoothstep(.06,.94,(dot(NORMAL,LIGHT)+.32)/1.32);
	d = card_diffuse(dot(NORMAL,LIGHT),d,card_style_surface.x,LIGHT_IS_DIRECTIONAL);
	vec3 lc = LIGHT_COLOR/PI;
	DIFFUSE_LIGHT += lc * ATTENUATION * d;
	float warm = max(lc.r-lc.b*1.55,0.0);
	DIFFUSE_LIGHT -= vec3(0.0,0.0,.12)*clamp(warm*ATTENUATION*d,0.0,1.0);
}

