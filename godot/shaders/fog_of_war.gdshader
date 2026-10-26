shader_type spatial;
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D sight_mask : repeat_disable, filter_linear;
uniform vec4 map_bounds = vec4(-52.0,-52.0,104.0,104.0);
uniform vec3 mist_color : source_color = vec3(.69,.76,.86);
uniform vec3 ambient_tint : source_color = vec3(.5,.5,.7);
uniform float unknown_opacity = .25;
uniform float memory_opacity = .09;
uniform float feather_meters = 7.5;
uniform float drift_strength = .07;
void vertex() { POSITION = vec4(VERTEX.xy,1.0,1.0); }
void fragment() {
	float depth = textureLod(depth_texture, SCREEN_UV, 0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth*2.0-1.0; // OpenGL NDC z is -1..1 (web/WebGL 2).
#endif
	vec4 view_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV*2.0-1.0,depth,1.0);
	vec3 world_pos = (INV_VIEW_MATRIX * vec4(view_pos.xyz/view_pos.w,1.0)).xyz;
	vec2 uv = (world_pos.xz-map_bounds.xy)/map_bounds.zw;
	// Broad world-space feathering is separate from the precise gameplay sight mask.
	// Two weighted rings soften obstacle cuts as well as the circular range boundary.
	vec2 sight = texture(sight_mask,uv).rg*.20;
	for (int i=0; i<8; i++) {
		float angle = float(i)*.785398163;
		vec2 direction = vec2(cos(angle),sin(angle));
		sight += texture(sight_mask,uv+direction*feather_meters*.45/map_bounds.zw).rg*.06;
		sight += texture(sight_mask,uv+direction*feather_meters/map_bounds.zw).rg*.04;
	}
	float visible = smoothstep(.0,.8,sight.r);
	float explored = smoothstep(.0,.9,sight.g);
	float clouds = sin(world_pos.x*.17+world_pos.z*.08+TIME*.06)
		*sin(world_pos.z*.14-world_pos.x*.06-TIME*.04);
	ALBEDO = mix(mist_color,ambient_tint,.22);
	// Terrain remains readable through a colored veil. Unseen actors are hidden separately.
	// Blend over the rendered scene so visible spells and aerial perspective are preserved.
	ALPHA = (1.0-visible)*mix(unknown_opacity,memory_opacity,explored)
		*(1.0+clouds*drift_strength);
}
