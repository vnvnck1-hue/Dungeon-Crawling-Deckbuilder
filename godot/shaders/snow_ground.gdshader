// 눈밭 바닥. 큰 색면(저주파 노이즈) + 두 숲길 + 숲 가장자리의 짙은 보라.
// 잔무늬·작은 색조각은 넣지 않는다.
shader_type spatial;
render_mode specular_disabled;

uniform vec4 snow_a : source_color = vec4(0.905, 0.905, 0.98, 1.0);
uniform vec4 snow_b : source_color = vec4(0.86, 0.86, 0.97, 1.0);
uniform vec4 path_color : source_color = vec4(0.66, 0.69, 0.9, 1.0);
uniform vec4 path_edge_color : source_color = vec4(0.95, 0.95, 1.0, 1.0);
uniform vec4 forest_color : source_color = vec4(0.72, 0.74, 0.92, 1.0);
uniform vec2 path_a[8];
uniform int path_a_count = 0;
uniform vec2 path_b[8];
uniform int path_b_count = 0;
uniform float path_half_width = 1.5;
uniform vec2 clearing_center = vec2(0.5, 0.5);
uniform float clearing_radius = 14.0;
uniform float forest_falloff = 16.0;
uniform float forest_amount = 0.22;
uniform float warm_absorb = 0.9;
uniform float wrap = 0.5;
uniform float band_lo = 0.2;
uniform float band_hi = 0.75;

varying vec3 v_wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.55;
	for (int i = 0; i < 3; i++) {
		v += vnoise(p) * a;
		p = p * 2.03 + vec2(17.1, 9.4);
		a *= 0.5;
	}
	return v / 0.9625;
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 pa = p - a;
	vec2 ba = b - a;
	float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
	return length(pa - ba * h);
}

float path_dist(vec2 p) {
	float d = 1e5;
	for (int i = 0; i < 7; i++) {
		if (i + 1 < path_a_count) {
			d = min(d, seg_dist(p, path_a[i], path_a[i + 1]));
		}
		if (i + 1 < path_b_count) {
			d = min(d, seg_dist(p, path_b[i], path_b[i + 1]));
		}
	}
	return d;
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_wpos.xz;
	float n1 = fbm(p * 0.055);
	float n2 = vnoise(p * 0.21);
	vec3 col = mix(snow_a.rgb, snow_b.rgb, smoothstep(0.35, 0.78, n1));
	col *= 0.975 + n2 * 0.05;

	float d = path_dist(p) + (n2 - 0.5) * 0.7;
	float core = 1.0 - smoothstep(path_half_width * 0.45, path_half_width, d);
	float bank = smoothstep(path_half_width * 0.85, path_half_width * 1.1, d)
			* (1.0 - smoothstep(path_half_width * 1.1, path_half_width * 1.7, d));
	col = mix(col, path_color.rgb, core * 0.75);
	col = mix(col, path_edge_color.rgb, bank * 0.45);

	float r = length(p - clearing_center);
	float f = smoothstep(clearing_radius, clearing_radius + forest_falloff, r + (n1 - 0.5) * 5.0);
	col = mix(col, forest_color.rgb, f * forest_amount);

	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float d = smoothstep(band_lo, band_hi, w);
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += lc * ATTENUATION * d;
	// 따뜻한 광원(앰버·불덩이)은 보라 환경광을 일부 밀어내 원화처럼 주황 빛 웅덩이를 만든다.
	float warm = max(lc.r - lc.b * 1.6, 0.0);
	float k = clamp(warm * ATTENUATION * d * warm_absorb, 0.0, 1.0);
	DIFFUSE_LIGHT -= vec3(0.0, 0.0, 0.55) * k;
}
