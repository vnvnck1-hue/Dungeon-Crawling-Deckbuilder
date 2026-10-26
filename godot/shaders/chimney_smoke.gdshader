shader_type spatial;
// 굴뚝 연기: Stable Fluids 밀도장(chimney_smoke.gd)을 세로 판에 그린다.
// 시뮬레이션은 30Hz 라 직전/현재 두 밀도장을 시간 보간하고, 격자보다 작은 결은
// 위로 흘러가는 노이즈로 밀도를 조금 비틀어 더한다. 빛은 위쪽에서 오는 것으로 보고
// 그 방향의 밀도를 몇 번 더 읽어 자기 그림자를 흉내 낸다.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D dens_prev : filter_linear, repeat_disable;
uniform sampler2D dens_cur : filter_linear, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform float blend = 1.0;
uniform vec2 cells = vec2(40.0, 56.0);   // 내부 칸 수(가장자리 경계 칸 제외)
uniform float opacity = 2.2;
uniform float max_alpha = 0.9;
uniform float detail_strength = 0.5;
uniform float time_offset = 0.0;
uniform vec4 warm : source_color = vec4(1.0, 0.80, 0.60, 1.0);
uniform vec4 mid : source_color = vec4(0.97, 0.92, 0.92, 1.0);
uniform vec4 cool : source_color = vec4(0.84, 0.82, 0.95, 1.0);
uniform vec4 shade : source_color = vec4(0.50, 0.47, 0.64, 1.0);
uniform float fade = 1.0;

// 판 UV(0..1, 위쪽 0) → 밀도 텍스처 좌표(가장자리 경계 칸 포함, 바닥 줄이 0행)
vec2 grid_uv(vec2 p) {
	vec2 g = vec2(p.x, 1.0 - p.y) * cells + 1.0;
	return g / (cells + 2.0);
}

float density_at(vec2 p) {
	vec2 g = grid_uv(p);
	return mix(texture(dens_prev, g).r, texture(dens_cur, g).r, blend);
}

void fragment() {
	vec2 p = UV;
	float h = 1.0 - p.y;   // 0 = 굴뚝 입구, 1 = 판 꼭대기
	float t = TIME + time_offset;
	// 격자보다 작은 결: 위로 흐르는 두 겹 노이즈로 좌표를 살짝 비틀고 밀도에 곱한다.
	vec2 q = vec2(p.x * 2.2, p.y * 3.0 + t * 0.12);
	vec2 n1 = texture(detail, q).rg - 0.5;
	float n2 = texture(detail, q * 2.3 + vec2(0.37, t * 0.17)).b;
	vec2 warp = n1 * (0.010 + 0.030 * h);
	float d = density_at(p + warp);
	d *= mix(1.0, 0.45 + 1.1 * n2, detail_strength * smoothstep(0.0, 0.5, h));

	// 자기 그림자: 위쪽(빛 방향)으로 쌓인 밀도만큼 어둡게.
	vec2 step_up = vec2(-0.25, -1.0) / cells * 2.5;
	float above = density_at(p + step_up) + density_at(p + step_up * 2.0) * 0.7 + density_at(p + step_up * 3.5) * 0.5;
	float lit = exp(-above * 0.6);

	vec3 base = mix(warm.rgb, mid.rgb, smoothstep(0.0, 0.35, h));
	base = mix(base, cool.rgb, smoothstep(0.3, 0.95, h));
	vec3 col = mix(shade.rgb, base, 0.3 + 0.7 * lit);
	// 굴뚝 바로 위는 불빛을 머금어 살짝 밝게
	col += warm.rgb * 0.18 * (1.0 - smoothstep(0.0, 0.12, h));

	float a = (1.0 - exp(-pow(max(d, 0.0), 0.75) * opacity)) * max_alpha;
	// 판 가장자리에서 잘린 티가 나지 않게
	a *= smoothstep(0.0, 0.16, p.x) * smoothstep(0.0, 0.16, 1.0 - p.x);
	a *= smoothstep(0.0, 0.22, p.y);
	a *= smoothstep(0.0, 0.015, h);
	ALBEDO = col;
	ALPHA = clamp(a * fade, 0.0, 1.0);
}
