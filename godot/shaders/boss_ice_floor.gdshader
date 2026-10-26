// 니벨라 보스룸 얼음 바닥판. 원화(05-arena-floor-and-rim) 기준: 청록 얼음 판석 + 짙은 남색 줄눈 + 흰 서리 결,
// 가장자리로 갈수록 눈이 덮인다. UV = 타원 정규 좌표(중심 0, 가장자리 길이 1). pulse 는 포효 때 금이 번쩍이는 값.
shader_type spatial;
render_mode specular_disabled, cull_disabled;
#include "res://shaders/card_style.gdshaderinc"

uniform vec4 ice_a : source_color = vec4(0.30, 0.84, 0.86, 1.0);
uniform vec4 ice_b : source_color = vec4(0.14, 0.52, 0.66, 1.0);
uniform vec4 grout : source_color = vec4(0.12, 0.13, 0.30, 1.0);
uniform vec4 vein : source_color = vec4(0.86, 0.96, 1.0, 1.0);
uniform vec4 snow : source_color = vec4(0.87, 0.86, 1.0, 1.0);
uniform vec4 glow_color : source_color = vec4(0.42, 0.80, 1.0, 1.0);
uniform float cell_scale = 0.62;
uniform float pulse = 0.0;
uniform float wrap : hint_range(0.0, 1.0) = 0.5;

varying vec3 v_wpos;

vec2 hash22(vec2 p) {
	// sin 기반 해시는 GPU 정밀도에 따라 사각 얼룩이 생겨 fract 기반(Hoskins)을 쓴다
	vec3 a = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	a += dot(a, a.yzx + 33.33);
	return fract((a.xx + a.yz) * a.zy);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash22(i).x, b = hash22(i + vec2(1, 0)).x, c = hash22(i + vec2(0, 1)).x, d = hash22(i + vec2(1, 1)).x;
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 보로노이 판석: x = 가장 가까운 칸까지, y = 두 번째와의 차(줄눈), zw = 칸 id
vec4 voronoi(vec2 p) {
	vec2 g = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0, d2 = 8.0;
	vec2 id = vec2(0.0);
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec2 r = o + 0.15 + hash22(g + o) * 0.7 - f;
			float d = dot(r, r);
			if (d < d1) { d2 = d1; d1 = d; id = g + o; }
			else if (d < d2) { d2 = d; }
		}
	}
	return vec4(sqrt(d1), sqrt(d2) - sqrt(d1), id);
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_wpos.xz * cell_scale;
	vec2 warp = vec2(vnoise(p * 1.7), vnoise(p * 1.7 + 7.3)) - 0.5;
	vec4 v = voronoi(p + warp * 0.35);
	float cell = hash22(v.zw).x;
	// 판석 안쪽: 칸마다 다른 청록, 가운데가 밝다
	vec3 col = mix(ice_b.rgb, ice_a.rgb, 0.35 + cell * 0.65);
	col = mix(col * 1.18, col, smoothstep(0.0, 0.6, v.x));
	// 얼음 속 흰 서리 결(굽은 실금)
	vec2 q = p * 2.3 + v.zw * 3.7;
	float n = vnoise(q) * 0.65 + vnoise(q * 2.1 + 5.2) * 0.35;
	float veins = (1.0 - smoothstep(0.0, 0.035, abs(n - 0.5))) * smoothstep(0.08, 0.3, v.y + 0.1);
	col = mix(col, vein.rgb, veins * 0.55);
	// 줄눈: 짙은 남색 + 가장자리 살짝 눈
	float joint = 1.0 - smoothstep(0.035, 0.085, v.y);
	col = mix(col, grout.rgb, joint);
	// 바깥으로 갈수록 눈이 판석을 덮는다
	float r = length(UV);
	float drift = smoothstep(0.78, 1.0, r + (vnoise(v_wpos.xz * 1.3) - 0.5) * 0.22);
	col = mix(col, snow.rgb, drift);
	col = card_surface_color(col, NORMAL, VIEW, 1.0);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	float crack_glow = veins * (1.0 - joint) * (1.0 - drift);
	// 밤에도 얼음이 스스로 희미하게 빛나 청록이 남는다(원화의 빛나는 바닥)
	EMISSION = glow_color.rgb * crack_glow * (0.18 + pulse * 1.6) + col * (1.0 - joint) * (1.0 - drift) * 0.16;
	FOG = colored_air(v_wpos, VERTEX, INV_VIEW_MATRIX[3].xyz);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float d = smoothstep(0.2, 0.75, w);
	d = card_diffuse(ndl, d, 1.0, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += LIGHT_COLOR / PI * ATTENUATION * d;
}
