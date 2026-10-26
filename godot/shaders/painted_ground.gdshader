shader_type spatial;
render_mode specular_disabled;
#include "res://shaders/colored_air.gdshaderinc"
uniform sampler2D cleanplate : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D painted_snow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D painted_trail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D painted_forest : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D toxic_ground : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 toxic_sites[3];
uniform sampler2D prop_blend_mask : filter_linear_mipmap, repeat_disable;
uniform vec4 mask_bounds = vec4(-60.0,-60.0,120.0,120.0);
uniform float painted_ground_enabled = 1.0;
uniform float texture_world_size = 2.9;
uniform vec3 reference_center = vec3(1.0,0.0,1.3);
uniform vec3 reference_right = vec3(.7071,0.0,-.7071);
uniform vec3 reference_up = vec3(-.586,.559,-.586);
uniform vec2 reference_size = vec2(44.0,22.0);
uniform float warm_enabled = 1.0;
uniform float ground_emission = .44;
uniform float ground_albedo = .62;
uniform float ground_neutral = 0.0;
uniform vec4 ground_tint : source_color = vec4(1.0);
uniform vec4 trail_segments[64];
uniform int trail_count = 0;
uniform vec2 clearings[4];
varying vec3 world_pos;
// Randomly rotated overlapping interior patches preserve brush shapes without
// hard tile borders or the bilateral motifs produced by mirrored tiling.
vec2 patch_hash(vec2 p) {
	return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}
vec3 paint_patch(sampler2D tex, vec2 p, vec2 cell) {
	vec2 random = patch_hash(cell);
	float angle = random.x*6.2831853;
	mat2 turn = mat2(vec2(cos(angle),-sin(angle)),vec2(sin(angle),cos(angle)));
	vec2 uv = vec2(.5)+turn*(p-cell)*.29+(random-.5)*.10;
	return textureGrad(tex,uv,turn*dFdx(p)*.29,turn*dFdy(p)*.29).rgb;
}
vec3 ground_paint(sampler2D tex, vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec4 w = vec4((1.0-f.x)*(1.0-f.y),f.x*(1.0-f.y),(1.0-f.x)*f.y,f.x*f.y);
	w = pow(w,vec4(5.0));
	w /= dot(w,vec4(1.0));
	return paint_patch(tex,p,cell)*w.x + paint_patch(tex,p,cell+vec2(1.0,0.0))*w.y
		+ paint_patch(tex,p,cell+vec2(0.0,1.0))*w.z + paint_patch(tex,p,cell+vec2(1.0,1.0))*w.w;
}
float trail_distance(vec2 p) {
	float d = 1000.0;
	for (int i=0;i<trail_count;i++) {
		vec2 a=trail_segments[i].xy;
		vec2 ab=trail_segments[i].zw-a;
		float t=clamp(dot(p-a,ab)/max(dot(ab,ab),.001),0.0,1.0);
		d=min(d,length(p-a-ab*t));
	}
	return d;
}
void vertex() { world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec3 p = world_pos-reference_center;
	vec2 uv = vec2(.5+dot(p,reference_right)/reference_size.x,.5-dot(p,reference_up)/reference_size.y);
	vec3 c = texture(cleanplate,clamp(uv,vec2(.001),vec2(.999))).rgb;
	// Perspective can see beyond the original orthographic cleanplate.
	// Fade outside its bounds into world-space forest snow instead of stretching edge pixels.
	float outside = max(abs(uv.x-.5)-.5,abs(uv.y-.5)-.5);
	vec2 paint_uv = world_pos.xz / texture_world_size;
	vec3 snow_paint = ground_paint(painted_snow,paint_uv);
	vec3 trail_paint = ground_paint(painted_trail,paint_uv*1.11+vec2(4.7,-2.3));
	vec3 forest_paint = ground_paint(painted_forest,paint_uv*.93+vec2(-3.1,8.2));
	vec2 mask_uv = (world_pos.xz-mask_bounds.xy)/mask_bounds.zw;
	vec2 contact = texture(prop_blend_mask,mask_uv).rg;
	float brush_edge = (snow_paint.r-.47)*.65;
	float trail = 1.0-smoothstep(1.0,3.4,trail_distance(world_pos.xz)+brush_edge);
	float clearing = 0.0;
	for (int i=0;i<4;i++) clearing=max(clearing,1.0-smoothstep(4.0,7.0,length(world_pos.xz-clearings[i])));
	float path_weight = max(trail*.84,clearing*.54);
	path_weight = max(path_weight,contact.g*.56);
	vec3 terrain = mix(snow_paint,trail_paint,path_weight);
	float forest_weight = contact.r*.90*(1.0-trail*.65);
	terrain = mix(terrain,forest_paint,forest_weight);
	// Keep the lodge's approved painted composition and warm door approach;
	// world-space art covers every exterior route, clearing and forest bed.
	float home_keep = (1.0-smoothstep(6.0,12.0,length(p.xz/vec2(1.2,1.0))))*.84;
	home_keep *= 1.0-smoothstep(-.04,.03,outside);
	c = mix(c,terrain,(1.0-home_keep)*painted_ground_enabled);
	c = mix(c,vec3(dot(c,vec3(.2126,.7152,.0722))),.22);
	c *= vec3(1.05,1.01,.91);
	// Regional colored mist keeps the dark forest's plum/teal hue visible.
	float outer = smoothstep(7.5,19.0,length((world_pos.xz-vec2(1.0,1.3))/vec2(1.1,1.0)));
	float pocket = .5+.5*sin(world_pos.x*.22-world_pos.z*.19);
	vec3 forest_tint = mix(vec3(.25,.16,.40),vec3(.11,.32,.36),pocket);
	c = mix(c,c*.82+forest_tint*.15,outer*.42);
	float rim = smoothstep(.34,.70,length((uv-vec2(.5,.49))*vec2(1.0,1.7)));
	c *= mix(vec3(1.0),mix(vec3(.80,.74,.89),vec3(.76,.89,.91),pocket),rim*.40);
	vec2 lamp_delta = (world_pos.xz-vec2(.25,3.55))/vec2(2.8,2.1);
	float warm = exp(-dot(lamp_delta,lamp_delta)*.5)*warm_enabled;
	vec2 pen_delta = (world_pos.xz-vec2(3.8,1.0))/vec2(1.7,2.0);
	warm = max(warm,exp(-dot(pen_delta,pen_delta)*.5)*.72*warm_enabled);
	c = mix(c,vec3(1.0,.53,.23),warm*.83);
	// Reduce baked color/fill for reference lighting so real local lights shape the snow.
	c = mix(c,vec3(dot(c,vec3(.2126,.7152,.0722))),ground_neutral)*ground_tint.rgb;
	float venom=0.0;
	for(int i=0;i<3;i++) {
		vec2 q=(world_pos.xz-toxic_sites[i].xy)/max(toxic_sites[i].zw,vec2(.001));
		float a=atan(q.y,q.x);
		float edge=length(q)+.055*sin(a*7.0)+.03*sin(world_pos.x*2.5+world_pos.z*1.7);
		venom=max(venom,1.0-smoothstep(.82,1.17,edge));
	}
	vec3 venom_paint=ground_paint(toxic_ground,world_pos.xz/6.5)*vec3(.95,1.12,1.03);
	c=mix(c,venom_paint,venom);
	ALBEDO = c*ground_albedo;
	EMISSION = c*mix(ground_emission,.27,venom);
	ROUGHNESS=1.0; SPECULAR=0.0;
	FOG = colored_air(world_pos,VERTEX,INV_VIEW_MATRIX[3].xyz);
}
void light() {
	float d = smoothstep(.06,.94,(dot(NORMAL,LIGHT)+.32)/1.32);
	vec3 lc = LIGHT_COLOR/PI;
	DIFFUSE_LIGHT += lc * ATTENUATION * d;
	float warm = max(lc.r-lc.b*1.55,0.0);
	DIFFUSE_LIGHT -= vec3(0.0,0.0,.15)*clamp(warm*ATTENUATION*d,0.0,1.0);
}
