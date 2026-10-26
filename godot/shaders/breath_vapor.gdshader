shader_type spatial;
// 입김: Stable Fluids 로 구운 날숨 밀도 플립북(breath_vapor.gd)을 세로 판에 그린다.
// 아틀라스 가로 = 시간(FRAMES 장), 세로 = 날숨 변형. 나이에 맞는 이웃한 두 장을 보간하고
// 위로 흐르는 노이즈로 좌표를 비틀어 격자보다 작은 결을 더한다. 윤곽선 없이 옅게 비치는 기체로 그린다.
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D atlas : filter_linear, repeat_disable;
uniform sampler2D detail : filter_linear_mipmap, repeat_enable;
uniform vec2 cells = vec2(28.0, 28.0);    // 내부 칸 수(경계 칸 제외)
uniform vec2 grid = vec2(27.0, 3.0);      // 아틀라스 칸 수(장 수, 변형 수)
uniform float opacity = 9.0;
uniform float max_alpha = 0.85;
uniform float detail_strength = 0.6;
uniform vec4 shade : source_color = vec4(0.70, 0.70, 0.86, 1.0);
uniform float soft_distance = 0.3;        // 몸·지면과 겹치는 곳을 녹이는 거리(m). 판이 물체를 뚫는 직선을 없앤다
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;

instance uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.6);   // sRGB 색(셰이더에서 선형으로 바꾼다)
instance uniform float age = 0.0;          // 0..1 (수명 비율)
instance uniform float variant = 0.0;
instance uniform float seed = 0.0;

float frame_density(vec2 p, float frame) {
	vec2 tile = cells + 2.0;
	vec2 g = vec2(p.x, 1.0 - p.y) * cells + 1.0;
	g = clamp(g, vec2(0.5), tile - 0.5);
	vec2 uv = (vec2(frame, variant) * tile + g) / (grid * tile);
	return texture(atlas, uv).r;
}

float density_at(vec2 p) {
	float f = clamp(age, 0.0, 1.0) * (grid.x - 1.0);
	float f0 = floor(f);
	float f1 = min(f0 + 1.0, grid.x - 1.0);
	return mix(frame_density(p, f0), frame_density(p, f1), f - f0);
}

// 퍼진 기체는 가장자리가 무르다: 나이에 따라 넓어지는 반경으로 9곳을 가중 평균한다.
float soft_density(vec2 p, float radius_cells) {
	vec2 r = vec2(radius_cells) / cells;
	float d = density_at(p) * 0.2;
	d += (density_at(p + vec2(r.x, 0.0)) + density_at(p - vec2(r.x, 0.0))
		+ density_at(p + vec2(0.0, r.y)) + density_at(p - vec2(0.0, r.y))) * 0.12;
	d += (density_at(p + r * 0.7) + density_at(p - r * 0.7)
		+ density_at(p + vec2(r.x, -r.y) * 0.7) + density_at(p + vec2(-r.x, r.y) * 0.7)) * 0.08;
	return d;
}

void fragment() {
	vec2 p = UV;
	float t = TIME * 0.6 + seed;
	// 결 비틀기: 나이가 들수록(흩어질수록) 더 크게 일렁인다.
	vec2 q = vec2(p.x * 1.6 + seed * 0.37, p.y * 1.3 + t * 0.35);
	vec2 n1 = texture(detail, q).rg - 0.5;
	float n2 = texture(detail, q * 2.1 + vec2(seed, -t * 0.4)).r;
	vec2 warp = n1 * (0.03 + 0.09 * age);
	float d = soft_density(p + warp, 1.2 + 2.5 * age);
	// 흩어질수록 성긴 구멍이 생기도록 노이즈를 곱한다.
	d *= mix(1.0, 0.35 + 1.3 * n2, detail_strength * smoothstep(0.05, 0.6, age));

	// 위쪽(빛)으로 쌓인 밀도만큼 라벤더빛으로 살짝 그늘지게.
	vec2 up = vec2(0.0, -2.0) / cells;
	float above = density_at(p + up) + density_at(p + up * 2.0) * 0.6;
	float lit = exp(-above * 0.8);
	vec3 tc = pow(tint.rgb, vec3(2.2));
	vec3 col = mix(shade.rgb * tc, tc, 0.45 + 0.55 * lit);

	float a = 1.0 - exp(-pow(max(d, 0.0), 0.6) * opacity);
	// 막 내쉴 때 톡 튀어나오지 않게, 끝은 서서히 사라지게.
	a *= smoothstep(0.0, 0.06, age) * (1.0 - smoothstep(0.55, 1.0, age));
	// 판 가장자리에서 잘린 티가 나지 않게
	a *= smoothstep(0.0, 0.1, p.x) * smoothstep(0.0, 0.12, 1.0 - p.x);
	a *= smoothstep(0.0, 0.12, p.y) * smoothstep(0.0, 0.1, 1.0 - p.y);
	// 기체가 물체에 닿는 곳은 깊이 차이만큼 옅게(BaseMaterial 의 proximity fade 와 같은 식)
	float scene_depth = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 scene_pos = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, scene_depth, 1.0);
	scene_pos.xyz /= scene_pos.w;
	a *= clamp(1.0 - smoothstep(scene_pos.z + soft_distance, scene_pos.z, VERTEX.z), 0.0, 1.0);
	ALBEDO = col;
	ALPHA = clamp(a * max_alpha * tint.a / 0.6, 0.0, 1.0);
}
