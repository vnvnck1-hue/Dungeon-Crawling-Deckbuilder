shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform vec4 membrane : source_color = vec4(.17,.53,.30,.86);
void fragment() {
	vec2 uv=UV;
	float ribs=1.0-smoothstep(.025,.065,abs(sin((uv.x*5.5+uv.y*1.8)*3.14159)));
	float cells=1.0-smoothstep(.035,.11,abs(sin((uv.y*6.0-uv.x*.8)*3.14159)));
	float edge=1.0-smoothstep(.025,.09,min(uv.y,1.0-uv.y));
	float vein=max(ribs*.8,cells*.55);
	ALBEDO=mix(membrane.rgb,vec3(.028,.095,.09),max(vein,edge));
	EMISSION=membrane.rgb*(1.0-vein)*.24;
	ROUGHNESS=.78; SPECULAR=0.0;
}
