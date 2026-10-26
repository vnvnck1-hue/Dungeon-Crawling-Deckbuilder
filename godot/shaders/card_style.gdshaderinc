// Shared preset values are defined in project.godot and changed by ScreenStyle.
#include "res://shaders/colored_air.gdshaderinc"
global uniform vec4 card_style_shading; // blend, transition width, wrap, two-tone
global uniform vec4 card_style_surface; // snow/foliage multipliers, fill, contour
global uniform vec4 card_style_palette; // RGB multiplier, snow neutralization
global uniform vec4 card_style_ink; // two-tone shadow level, texture retention, reserved

float card_diffuse(float ndl, float original, float strength, bool directional) {
	if (!directional) return original; // Keep local lamp/fire falloff continuous.
	float w = clamp((ndl + card_style_shading.z) / (1.0 + card_style_shading.z),0.0,1.0);
	float s = max(card_style_shading.y,.005);
	float bands = .20 + .55*smoothstep(.40-s,.40+s,w) + .25*smoothstep(.74-s,.74+s,w);
	float toon = card_style_ink.x + (1.0-card_style_ink.x)*smoothstep(.46-s,.46+s,w);
	bands = mix(bands,toon,card_style_shading.w);
	return mix(original,bands,clamp(card_style_shading.x*strength,0.0,1.0));
}

vec3 card_surface_color(vec3 color, vec3 normal, vec3 view, float contour_scale) {
	float edge = pow(1.0-clamp(abs(dot(normalize(normal),normalize(view))),0.0,1.0),5.0);
	vec3 tinted = color*card_style_palette.rgb;
	return mix(tinted,tinted*vec3(.36,.28,.47),edge*card_style_surface.w*contour_scale);
}
