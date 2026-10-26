shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform vec4 venom_color : source_color = vec4(.48,1.0,.035,1.0);
uniform float phase = 0.0;
uniform float energy = 2.6;
varying vec3 wp;
void vertex() { wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	float breath=pow(max(0.0,sin(TIME*1.12+phase)),12.0);
	float ripple=.78+.22*sin(UV.x*2.1-TIME*1.1+phase);
	float core=pow(clamp(1.0-abs(UV.y*2.0-1.0),0.0,1.0),.65);
	vec3 c=mix(vec3(.12,.42,.055),venom_color.rgb,core);
	ALBEDO=c;
	EMISSION=c*(.6+core*energy)*(1.0+breath*.8)*ripple;
}
