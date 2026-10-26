// Local-light tint for the existing distance fog. RGB values are already linear.
global uniform vec4 air_depth_params;
global uniform vec4 air_base_color;
global uniform mat4 air_positions_a;
global uniform mat4 air_positions_b;
global uniform mat4 air_positions_c;
global uniform mat4 air_colors_a;
global uniform mat4 air_colors_b;
global uniform mat4 air_colors_c;

void air_source(vec3 p,vec4 source,vec4 tint,inout vec3 sum,inout float weight) {
	float distance_ratio = length(p-source.xyz)/max(source.w,.01);
	float falloff = 1.0-smoothstep(.0,1.0,distance_ratio);
	float w = falloff*falloff*tint.w;
	sum += tint.rgb*w;
	weight += w;
}

vec4 colored_air(vec3 world_pos,vec3 view_pos,vec3 camera_pos) {
	float distance = length(view_pos);
	float amount = pow(smoothstep(air_depth_params.x,air_depth_params.y,distance),air_depth_params.z)*air_depth_params.w;
	if (amount <= .00001 || air_base_color.a == 0.0) return vec4(air_base_color.rgb,amount);
	vec3 sum = vec3(0.0);
	float weight = 0.0;
	// Sample the end and midpoint of the fogged ray segment, not only the surface.
	float segment = clamp(distance-air_depth_params.x,0.0,16.0);
	vec3 towards_camera = normalize(camera_pos-world_pos);
	for (int j=0;j<2;j++) {
		vec3 p = world_pos+towards_camera*segment*float(j)*.5;
		for (int i=0;i<4;i++) {
			air_source(p,air_positions_a[i],air_colors_a[i],sum,weight);
			air_source(p,air_positions_b[i],air_colors_b[i],sum,weight);
			air_source(p,air_positions_c[i],air_colors_c[i],sum,weight);
		}
	}
	vec3 color = mix(air_base_color.rgb,sum/max(weight,.001),(1.0-exp(-weight*.75))*.80*air_base_color.a);
	return vec4(color,amount);
}
