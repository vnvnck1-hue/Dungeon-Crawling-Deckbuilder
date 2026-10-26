// 프랍·캐릭터 공용 스타일 셰이더.
// 넓게 감싸는 확산광(wrap) + 부드러운 밴드로 큰 명암 덩어리를 만들고,
// 그림자 쪽은 환경광(보라)이 채우도록 한다. 표면 무늬 대신 저주파 색 변화만 넣는다.
shader_type spatial;
render_mode specular_disabled;
#include "res://shaders/card_style.gdshaderinc"

uniform vec4 albedo : source_color = vec4(1.0);
uniform float warm_absorb = 0.9;
uniform float wrap : hint_range(0.0, 1.0) = 0.45;
uniform float band_lo = 0.22;
uniform float band_hi = 0.72;
uniform vec4 emission_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform float rim_strength = 0.22;
// 하늘(위쪽) 보조광: 지붕·눈 덮개처럼 위를 향한 면을 바닥보다 한 톤 밝게 띄운다.
uniform float sky_fill = 0.32;
uniform vec4 sky_color : source_color = vec4(1.0, 0.9, 0.86, 1.0);
uniform vec4 rim_color : source_color = vec4(0.80, 0.76, 1.0, 1.0);
uniform float noise_amount = 0.06;
uniform float noise_scale = 0.55;
uniform float style_band_scale = 1.0;
// 윗면 눈 덮기: 법선 y가 이 값보다 크면 눈 색으로 바뀐다(1 이상이면 꺼짐).
uniform float top_snow = 2.0;
uniform vec4 snow_color : source_color = vec4(0.87, 0.85, 1.0, 1.0);

instance uniform float hit_flash = 0.0;

varying vec3 v_wpos;
varying vec3 v_wnrm;

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

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 col = albedo.rgb;
	float n = vnoise(v_wpos.xz * noise_scale + vec2(v_wpos.y * 0.7, -v_wpos.y * 0.4));
	col *= 1.0 + (n - 0.5) * 2.0 * noise_amount;
	if (top_snow < 1.0) {
		float up = smoothstep(top_snow, top_snow + 0.12, normalize(v_wnrm).y + (n - 0.5) * 0.25);
		col = mix(col, snow_color.rgb, up);
	}
	col = mix(col, vec3(1.0, 0.9, 0.95), hit_flash * 0.55);
	col = card_surface_color(col,NORMAL,VIEW,1.0);
	ALBEDO = col;
	ROUGHNESS = 1.0;
	METALLIC = 0.0;
	SPECULAR = 0.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = emission_color.rgb * emission_energy
			+ rim_color.rgb * rim * rim_strength * col * card_style_surface.z
			+ vec3(1.0, 0.35, 0.45) * hit_flash * 0.6
			+ col * sky_color.rgb * max(normalize(v_wnrm).y, 0.0) * sky_fill * card_style_surface.z;
	FOG = colored_air(v_wpos,VERTEX,INV_VIEW_MATRIX[3].xyz);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float w = clamp((ndl + wrap) / (1.0 + wrap), 0.0, 1.0);
	float d = smoothstep(band_lo, band_hi, w);
	d = card_diffuse(ndl,d,style_band_scale,LIGHT_IS_DIRECTIONAL);
	vec3 lc = LIGHT_COLOR / PI;
	DIFFUSE_LIGHT += lc * ATTENUATION * d;
	// 따뜻한 광원(앰버·불덩이)은 보라 환경광을 일부 밀어내 원화처럼 주황 빛 웅덩이를 만든다.
	float warm = max(lc.r - lc.b * 1.6, 0.0);
	float k = clamp(warm * ATTENUATION * d * warm_absorb, 0.0, 1.0);
	DIFFUSE_LIGHT -= vec3(0.0, 0.0, 0.55) * k;
}
