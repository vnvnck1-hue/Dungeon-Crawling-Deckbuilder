shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
uniform vec4 haze_color : source_color = vec4(1.0,.08,.52,1.0);
uniform float opacity = 0.0;

void fragment() {
	vec2 p = (UV-.5)*2.0;
	float falloff = 1.0-smoothstep(.12,1.0,dot(p,p));
	float wisps = .65+.20*sin(UV.x*15.0+UV.y*9.0)+.15*sin(UV.y*23.0-UV.x*8.0);
	ALBEDO = haze_color.rgb;
	ALPHA = falloff*wisps*opacity;
}
