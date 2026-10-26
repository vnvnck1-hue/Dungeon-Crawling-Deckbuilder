// 화염 VFX 공용: 입자 빌보드(입자 회전·크기 유지)와 텍스처 없는 값 노이즈.
// GPUParticles3D + ParticleProcessMaterial 기준 INSTANCE_CUSTOM: x = 회전(rad), y = 수명 비율(0→1), z = 입자별 무작위(anim_offset 0~1).

varying float v_age;
varying float v_seed;

void fire_billboard(inout mat4 modelview, mat4 view, mat4 inv_view, mat4 model, vec4 custom) {
	mat4 w = mat4(normalize(inv_view[0]), normalize(inv_view[1]), normalize(inv_view[2]), model[3]);
	float c = cos(custom.x), s = sin(custom.x);
	w = w * mat4(vec4(c, -s, 0.0, 0.0), vec4(s, c, 0.0, 0.0), vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	modelview = view * w * mat4(
		vec4(length(model[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(model[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(model[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

float fire_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float fire_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = fire_hash(i);
	float b = fire_hash(i + vec2(1.0, 0.0));
	float c = fire_hash(i + vec2(0.0, 1.0));
	float d = fire_hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fire_fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * fire_vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		amp *= 0.5;
	}
	return v;
}

// 몽글한 덩어리 마스크. puff(0~1)가 클수록 노이즈로 깊게 깎여 덩어리가 나뉜다.
// inner: 가장자리 그라디언트 안쪽 끝(작을수록 무른 가장자리)
float fire_puff_soft(vec2 uv, float seed, float t, float puff, float scale, float inner) {
	vec2 p = uv * 2.0 - 1.0;
	float d = length(p);
	vec2 q = uv * scale + vec2(seed * 17.0, seed * 31.0 - t);
	float n = fire_fbm(q + fire_fbm(q * 0.7 + t * 0.3) * 0.8);
	float edge = d + (n - 0.5) * (0.35 + puff * 0.9);
	return smoothstep(1.0, inner, edge);
}

float fire_puff(vec2 uv, float seed, float t, float puff, float scale) {
	return fire_puff_soft(uv, seed, t, puff, scale, 0.25);
}

// 소프트 입자: 지면·물체와 맞닿는 곳을 깊이 차이로 지운다. depth = 깊이 텍스처 값
// (깊이 샘플러는 함수 인자로 넘기면 컴파일러가 거부하므로 fragment 에서 읽어 값만 넘긴다)
float fire_soft_depth(float depth, vec2 screen_uv, mat4 inv_proj, float frag_z, float dist) {
	vec4 v = inv_proj * vec4(screen_uv * 2.0 - 1.0, depth, 1.0);
	float scene_z = -v.z / v.w;
	return clamp((scene_z + frag_z) / dist, 0.0, 1.0);
}
