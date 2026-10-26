shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 mist_color : source_color = vec4(.20,.69,.22,.18);
uniform float phase=0.0;
varying vec3 wp;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p); f=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);
}
void vertex() { wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p=UV*2.0-1.0;
	float edge=1.0-smoothstep(.38,1.0,length(p));
	float n=noise(wp.xz*.62+vec2(TIME*.09+phase,-TIME*.05));
	n=.67*n+.33*noise(wp.xz*1.7-vec2(TIME*.06,phase));
	ALBEDO=mix(mist_color.rgb*.55,mist_color.rgb*1.3,n);
	ALPHA=edge*smoothstep(.19,.75,n)*mist_color.a;
}
