shader_type spatial;
// Clumped ground plants for GrassField (MultiMesh). No image textures: colour comes from the
// root->tip gradient + per-instance variation, and the hand-painted look (midrib, side veins, darker rims,
// brush streaks along the leaf) is drawn from the leaf UVs. All motion is computed here on the GPU.
// world_vertex_coords: VERTEX/NORMAL arrive in world space, so the wind offset needs no inverse matrix.
render_mode cull_disabled, world_vertex_coords, specular_disabled;
#include "res://shaders/card_style.gdshaderinc"

group_uniforms colors;
uniform vec4 color_root : source_color = vec4(.06, .17, .10, 1.0);
uniform vec4 color_tip : source_color = vec4(.38, .62, .26, 1.0);
uniform vec4 color_dry : source_color = vec4(.66, .66, .30, 1.0); // per-clump variation target
uniform vec4 color_sheen : source_color = vec4(.78, .92, .55, 1.0); // wave crest tint — keep near color_tip, not white
uniform vec4 flower_a : source_color = vec4(.95, .82, .35, 1.0);
uniform vec4 flower_b : source_color = vec4(.80, .55, .95, 1.0);
uniform float variation = .35;
uniform float sheen_amount = .45;
uniform float trough_shade = .2; // darken blades between gusts so waves read through value, not glare
uniform float toon_mix = .5; // 1 = game toon bands, lower = softer wrap light on grass
uniform float translucency = .25; // light passing through thin leaf tips (adds tip colour, scaled by light)
uniform float normal_flatten = .35; // 1 = every leaf shades as straight up; lower keeps the midrib fold readable

group_uniforms leaf_paint;
uniform float midrib_light = .5; // pale stripe down the leaf centre, fading towards the tip
uniform float vein_shade = .38; // thin darker side veins slanting out from the midrib
uniform float vein_count = 5.0; // veins per side along the leaf
uniform float edge_shade = .3; // darker rim along the leaf edge
uniform float half_tone = .25; // one half of each leaf painted lighter, like a lit fold
uniform float brush_amount = .45; // streaky value variation running along the leaf
uniform float tip_glow = 1.0; // tips lighten and warm a little, like sunlit leaf ends
uniform float root_shade = .6; // leaves darken into the heart of the plant, as if shaded by the leaves above

group_uniforms wind;
uniform sampler2D wind_noise : repeat_enable, filter_linear;
uniform vec2 wind_direction = vec2(1.0, .35);
uniform float wave_speed = 3.2; // m/s the gust pattern travels across the field
uniform float wind_strength = .55; // tip lean per metre of blade height at a full gust
uniform float base_lean = .12; // constant lean even between gusts
uniform float gust_scale = .045; // 1/m — size of the big gust patches
uniform float wave_length = 6.5; // m between rolling crests
uniform float wave_amount = .55; // 0 = pure noise gusts, 1 = strong regular rolling bands
uniform float flutter = .05;

group_uniforms interaction;
uniform vec4 push_sphere = vec4(0.0, -100.0, 0.0, 0.0); // xyz, radius (set by GrassField)
uniform float push_strength = .9;

group_uniforms lod;
uniform vec2 fade_distance = vec2(32.0, 44.0); // blades sink into the ground between these camera distances

varying float v_wind;
varying float v_gust;
varying float v_var;
varying vec3 v_world;
varying vec3 v_normal;

float wind_field(vec2 p, float t, vec2 dir) {
	// Large travelling gust patches (noise scrolls downwind) ...
	vec2 uv = (p - dir * wave_speed * t) * gust_scale;
	float g = textureLod(wind_noise, uv, 0.0).r * .75
		+ textureLod(wind_noise, uv * 2.7 + vec2(.37, .11) - dir * t * .02, 0.0).r * .25;
	g = smoothstep(.25, .80, g);
	// ... plus rolling bands so the field reads as waves; bands are stronger where gusts are.
	float phase = (dot(p, dir) - wave_speed * t) / wave_length * TAU;
	float band = pow(.5 + .5 * sin(phase + g * 2.2), 3.0);
	return clamp(mix(g, band * (.35 + g), wave_amount), 0.0, 1.0);
}

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float along = UV.y; // 0 root .. 1 tip along each blade
	// Distance LOD: shrink to the ground instead of popping at the visibility range.
	float fade = 1.0 - smoothstep(fade_distance.x, fade_distance.y, distance(root, CAMERA_POSITION_WORLD));
	VERTEX.y = root.y + (VERTEX.y - root.y) * fade;
	float h = max(VERTEX.y - root.y, 0.0);

	vec2 dir = normalize(wind_direction);
	vec2 side = vec2(-dir.y, dir.x);
	float rnd = INSTANCE_CUSTOM.g;
	float stiffness = max(INSTANCE_CUSTOM.b, .2);
	float w = wind_field(root.xz, TIME, dir);
	float flut = sin(TIME * (5.0 + rnd * 3.0) + rnd * 40.0 + UV2.x * 9.0) * flutter * (.35 + w);

	vec2 off = (dir * (base_lean + w * wind_strength) + side * flut) / stiffness * h * along;
	vec3 pd = root - push_sphere.xyz;
	float push = (1.0 - smoothstep(push_sphere.w * .35, push_sphere.w, length(pd.xz))) * step(.001, push_sphere.w);
	off += normalize(pd.xz + vec2(.0001)) * push * push_strength * h * along;

	// Keep blade length: bending lowers the tip so it arcs instead of shearing.
	float d = min(length(off), h * .92);
	off = normalize(off + vec2(1e-5)) * d;
	VERTEX.xz += off;
	VERTEX.y = root.y + sqrt(max(h * h - d * d, 0.0));

	// Mostly-up normals: tufts shade as one soft mass instead of noisy individual cards.
	v_normal = normalize(mix(NORMAL, vec3(0.0, 1.0, 0.0), normal_flatten));
	v_gust = max(w, push * .6);
	v_wind = v_gust * along;
	v_var = INSTANCE_CUSTOM.r;
	v_world = VERTEX;
}

void fragment() {
	float along = UV.y;
	float patch = textureLod(wind_noise, v_world.xz * .021 + vec2(.5, .2), 0.0).r; // broad tone patches
	vec3 tip = mix(color_tip.rgb, color_dry.rgb, clamp(v_var * variation + (patch - .5) * .5, 0.0, 1.0));
	vec3 c = mix(color_root.rgb, tip, smoothstep(0.0, 1.0, along));
	float crest = smoothstep(.3, 1.0, v_gust) * along;
	c = mix(c, color_sheen.rgb, crest * sheen_amount);
	c *= 1.0 - trough_shade * (1.0 - v_gust) * along;
	// Hand-painted leaf: everything below is in leaf space (UV.x across, .5 = midrib; UV.y root..tip).
	float x = UV.x - .5;
	float ax = abs(x) * 2.0; // 0 midrib .. 1 edge
	float rnd = UV2.x;
	// Brush streaks: noise stretched along the leaf, different per leaf, so no two leaves are flat copies.
	float brush = textureLod(wind_noise, vec2(ax * .22 + rnd * 3.7 + v_var * 1.9, along * .07 + rnd * 1.3), 0.0).r;
	c *= 1.0 + (brush - .5) * brush_amount * 2.0;
	c *= 1.0 + sign(x) * half_tone * (rnd > .5 ? 1.0 : -1.0);
	c = mix(c, c * 1.35 + color_dry.rgb * .08, smoothstep(.55, 1.0, along) * tip_glow);
	// Side veins slant from the midrib towards the tip; thinned by screen-space width so they fade, not shimmer, far away.
	float vp = along * vein_count - ax * .9 + step(0.0, x) * .5;
	float aa = fwidth(vp);
	float vd = abs(fract(vp) - .5) * 2.0; // 1 on a vein
	float vein = smoothstep(1.0 - max(.26, aa * 1.5), 1.0, vd) * (1.0 - smoothstep(.25, .6, aa));
	vein *= smoothstep(.1, .25, ax) * (1.0 - smoothstep(.75, .95, ax)) * smoothstep(.05, .2, along) * (1.0 - smoothstep(.85, 1.0, along));
	c *= 1.0 - vein_shade * vein;
	float rib = (1.0 - smoothstep(.03, .1 + aa * .3, ax)) * (1.0 - smoothstep(.4, 1.0, along) * .7);
	c = mix(c, c * 1.5 + tip * .12, rib * midrib_light);
	c *= 1.0 - edge_shade * smoothstep(.7, 1.0, ax);
	c *= mix(1.0 - root_shade, 1.0, smoothstep(.0, .5, along));
	if (COLOR.a > .5) c = mix(flower_a.rgb, flower_b.rgb, step(.5, fract(v_var * 7.31)));
	c = card_surface_color(c, NORMAL, VIEW, .25);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	// Override the back-face flip of cull_disabled so both sides light identically.
	NORMAL = normalize((VIEW_MATRIX * vec4(v_normal, 0.0)).xyz);
	FOG = colored_air(v_world, VERTEX, CAMERA_POSITION_WORLD);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diffuse = smoothstep(.06, .94, (ndl + .32) / 1.32);
	float lit = mix(diffuse, card_diffuse(ndl, diffuse, 1.0, LIGHT_IS_DIRECTIONAL), toon_mix);
	// Thin leaves let some light through, strongest towards the tip: reads as leaf, not painted plastic.
	float through = translucency * UV.y * (.6 + .4 * (1.0 - abs(ndl)));
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * ATTENUATION * (lit + through);
}
