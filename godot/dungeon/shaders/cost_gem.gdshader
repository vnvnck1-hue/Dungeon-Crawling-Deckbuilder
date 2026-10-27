shader_type canvas_item;
// 손패 행동력 배지의 보석 링(assets/ui/cost_badge/badge_gem.png, 무채색 패싯 명암).
// 명암을 영웅색으로 물들이고, 패싯마다 엇박으로 천천히 반짝이며 옅은 광택 띠가 링을 따라 돈다.
// active = 0 이면(행동력 부족) 연기 낀 회색으로 가라앉고 반짝임이 멎는다. 표시 전용.

uniform vec4 hero : source_color = vec4(0.7, 0.5, 1.0, 1.0);
uniform float active : hint_range(0.0, 1.0) = 1.0;
uniform float seed = 0.0;          // 카드마다 다른 박자
uniform float facets = 14.0;       // 링을 도는 패싯 수
uniform float twinkle_speed = 0.55;
uniform float sweep_speed = 0.35;  // 광택 띠가 한 바퀴 도는 속도(rad/s)
uniform float sparkle = 0.38;      // 반짝임 최대 밝기

float hash(float n) {
	return fract(sin(n * 127.1 + seed * 311.7) * 43758.5453);
}

void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float l = dot(t.rgb, vec3(0.299, 0.587, 0.114));
	// 어두운 면은 영웅색의 그늘, 밝은 면은 영웅색, 가장 밝은 면은 흰빛으로
	vec3 col = hero.rgb * mix(0.35, 1.25, l);
	col = mix(col, vec3(1.0), smoothstep(0.82, 1.0, l) * 0.55);

	vec2 d = UV - vec2(0.5);
	float ang = atan(d.y, d.x);
	float idx = floor((ang / TAU + 0.5) * facets);
	float ph = hash(idx) * TAU;
	// 패싯 반짝임: 대부분은 잠잠하고 가끔 한 면씩 은은하게 켜진다
	float tw = pow(max(sin(TIME * twinkle_speed * (0.7 + hash(idx + 7.0) * 0.6) + ph), 0.0), 10.0);
	// 링을 따라 천천히 도는 광택 띠
	float sw = pow(max(cos(ang - TIME * sweep_speed - seed * 2.3), 0.0), 18.0);
	float glint = (tw * 0.8 + sw * 0.6) * smoothstep(0.35, 0.8, l);
	col += (hero.rgb * 0.5 + vec3(0.5)) * glint * sparkle * active;

	vec3 off = vec3(l * 0.42 + 0.08);
	COLOR = vec4(mix(off, col, active), t.a);
}
