shader_type spatial;
render_mode specular_disabled;
#include "res://shaders/card_style.gdshaderinc"
// Col is painted on real geometry in Blender and exported as glTF COLOR_0.
// Wind idle: only foliage materials set wind_strength > 0; rocks/logs keep the static default.
uniform float wind_strength = 0.0; // tip sway (m) at wind_height above the prop's ground pivot
uniform float wind_height = 5.0; // world-space height the sway curve is normalized to
uniform float wind_speed = 1.0;
uniform float wind_flutter = 0.0; // small per-branch shiver (m) on top of the trunk sway
uniform vec2 wind_direction = vec2(0.93, 0.37); // follows the snowfall drift
varying vec3 world_normal;
varying vec3 air_world_pos;

vec3 wind_offset(vec3 world_pos, vec3 origin) {
	float h = max(world_pos.y - origin.y, 0.0);
	float bend = pow(h / wind_height, 1.6); // rooted base, freer tip
	float t = TIME * wind_speed;
	float phase = dot(origin.xz, vec2(.37, .23));
	// Slow gusts roll across the forest so neighbours move together but not in lockstep.
	float gust = .6 + .4 * sin(t * .29 - dot(origin.xz, wind_direction) * .045) * sin(t * .17 + 1.3);
	vec2 dir = normalize(wind_direction);
	vec2 side = vec2(-dir.y, dir.x);
	float along = .45 + sin(t * 1.05 + phase) * .55 + sin(t * 1.83 + phase * 1.7) * .22;
	float across = sin(t * .79 + phase * 2.1) * .32;
	vec2 sway = (dir * along + side * across) * gust * wind_strength * bend;
	float shiver = sin(t * 4.6 + dot(world_pos, vec3(1.9, 1.3, 1.7))) * sin(t * 2.3 + phase);
	vec3 flutter = vec3(dir.x, .45, dir.y) * shiver * wind_flutter * gust * clamp(h / wind_height, 0.0, 1.0);
	// Drop the tip slightly as it leans so branches arc instead of shearing sideways.
	float sag = dot(sway, sway) / max(2.0 * h, .2);
	return vec3(sway.x, -sag, sway.y) + flutter;
}

void vertex() {
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	if (wind_strength > 0.0 || wind_flutter > 0.0) {
		vec3 world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * wind_offset(world_pos, NODE_POSITION_WORLD);
	}
	air_world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	vec3 c = card_surface_color(COLOR.rgb, NORMAL, VIEW, .60);
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = c * (.07 + max(world_normal.y, 0.0) * .035) * card_style_surface.z;
	FOG = colored_air(air_world_pos,VERTEX,INV_VIEW_MATRIX[3].xyz);
}
void light() {
	float ndl = dot(NORMAL, LIGHT);
	float diffuse = smoothstep(.06, .94, (ndl + .32) / 1.32);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * ATTENUATION * card_diffuse(ndl, diffuse, 1.0, LIGHT_IS_DIRECTIONAL);
}
