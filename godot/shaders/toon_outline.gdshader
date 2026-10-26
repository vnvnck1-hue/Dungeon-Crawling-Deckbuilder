shader_type spatial;
// Depth/normal outlines, drawn before the CanvasLayer HUD.
// Forward+ reads the normal-roughness buffer; Compatibility (web/WebGL 2) has none,
// so normals are rebuilt from neighbouring depth samples there.
render_mode unshaded, fog_disabled, depth_test_disabled, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
#if CURRENT_RENDERER != RENDERER_COMPATIBILITY
uniform sampler2D normal_texture : hint_normal_roughness_texture, repeat_disable, filter_nearest;
#endif
uniform vec4 ink_color : source_color = vec4(.065,.025,.105,1.0);
uniform float width_pixels = 3.0;
uniform float depth_threshold = .32;
uniform float normal_threshold = .75;
uniform vec4 air_fog_params = vec4(0.0,1.0,1.0,0.0); // begin, end, curve, max fog

void vertex() {
	POSITION = vec4(VERTEX.xy,1.0,1.0); // Godot 4.3+ reverse Z near plane.
}

vec3 view_position(vec2 uv, mat4 inv_projection) {
	float depth = textureLod(depth_texture,uv,0.0).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	depth = depth*2.0-1.0; // OpenGL NDC z is -1..1.
#endif
	vec4 pos = inv_projection*vec4(uv*2.0-1.0,depth,1.0);
	return pos.xyz/pos.w;
}

vec3 view_normal(vec2 uv, vec2 pixel, mat4 inv_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	// Use the flatter side on each axis so silhouettes don't smear the normal.
	vec3 c = view_position(uv,inv_projection);
	vec3 r = view_position(uv+vec2(pixel.x,0.0),inv_projection)-c;
	vec3 l = c-view_position(uv-vec2(pixel.x,0.0),inv_projection);
	vec3 u = view_position(uv+vec2(0.0,pixel.y),inv_projection)-c;
	vec3 d = c-view_position(uv-vec2(0.0,pixel.y),inv_projection);
	vec3 dx = abs(r.z)<abs(l.z) ? r : l;
	vec3 dy = abs(u.z)<abs(d.z) ? u : d;
	vec3 n = normalize(cross(dy,dx));
	return n.z<0.0 ? -n : n;
#else
	return normalize(textureLod(normal_texture,uv,0.0).rgb*2.0-1.0);
#endif
}

void fragment() {
	vec2 pixel = 1.0/VIEWPORT_SIZE;
	vec3 center = view_position(SCREEN_UV,INV_PROJECTION_MATRIX);
	vec3 normal = view_normal(SCREEN_UV,pixel,INV_PROJECTION_MATRIX);
	// Remove the expected depth change across a flat sloping surface.
	// This keeps the snow field and broad roof faces clear of false contour lines.
	float edge = 0.0;
	for (int i=0;i<8;i++) {
		float a = float(i)*.785398163;
		vec2 offset = vec2(cos(a),sin(a))*width_pixels;
		vec2 uv = clamp(SCREEN_UV+offset*pixel,pixel*.5,vec2(1.0)-pixel*.5);
		vec3 neighbor = view_position(uv,INV_PROJECTION_MATRIX);
		float delta = abs(dot(normal,neighbor-center));
		float depth_edge = smoothstep(depth_threshold,depth_threshold*1.6,delta);
		float normal_delta = 1.0-dot(normal,view_normal(uv,pixel,INV_PROJECTION_MATRIX));
		float crease = smoothstep(normal_threshold,normal_threshold+.22,normal_delta);
		edge = max(edge,max(depth_edge,crease*.85));
	}
	ALBEDO = ink_color.rgb;
	float air = pow(smoothstep(air_fog_params.x,air_fog_params.y,length(center)),air_fog_params.z)*air_fog_params.w;
	ALPHA = edge*ink_color.a*(1.0-air);
}
