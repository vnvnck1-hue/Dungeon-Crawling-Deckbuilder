// 카드 3D 변형(마법 카드 연출): 카드 그림을 격자 메시(card_surface.gd)로 그리면 정점마다 3D 로 옮겨
// 휘기(bend)·말기(roll)·비틀기(twist)·물결(flutter)·Y/X 축 회전(yaw/pitch, 360° 가능)을 한 뒤 원근으로 투영한다.
// 정점마다 이웃 두 점을 같이 옮겨 화면상 앞/뒷면과 조명(v_warp)을 구한다.
// 모든 값이 0 이면 원래 평평한 카드와 같다(연출을 쓰지 않는 카드는 그대로 보인다).
// card_burn.gdshader(카드 그림)와 card_burn_glow.gdshader(소모 글로우 층)가 같이 쓴다. card_size·pad 는 포함하는 셰이더가 선언한다.

group_uniforms Warp;
uniform float warp_yaw = 0.0;        // Y축 회전(라디안). π 면 뒷면이 보인다
uniform float warp_pitch = 0.0;      // X축 회전(라디안)
uniform vec2 warp_bend = vec2(0.0);  // x: 폭 방향 휨(+ 양옆이 뒤로, − 양옆이 앞으로 오목), y: 높이 방향 휨
uniform float warp_roll = 0.0;       // 0..1 아래 끝부터 두루마리처럼 뒤로 말린 정도
uniform float warp_twist = 0.0;      // 위·아래가 서로 반대로 도는 비틀림(라디안, 카드 높이 전체)
uniform float warp_flutter = 0.0;    // 흐르는 물결(종이가 바람에 날리는 떨림)
uniform float warp_magic = 0.0;      // 0..1 표면을 흐르는 마법 광택
uniform sampler2D card_back : filter_linear_mipmap, hint_default_transparent;
group_uniforms;

// x: > 0 앞면, < 0 뒷면 · y: 휨에 따른 명암 배율(평평하면 1) · z: 휜 면의 반사광(평평하면 0)
// 바리잉은 vertex() 안에서만 쓸 수 있어 포함하는 셰이더가 'v_warp = ...' 로 받아 넣는다
varying vec3 v_warp;

vec3 warp_point(vec2 n, float t) {
	vec2 sz = card_size;
	vec3 p = vec3(n * sz, 0.0);
	// 1) 두루마리: 아래 끝에서 위로 감기며 뒤로 말린다. 안쪽 바퀴일수록 반지름이 줄어 겹이 생긴다
	if (warp_roll > 0.0) {
		float L = warp_roll * sz.y * 1.05;
		float y0 = sz.y * 0.5 - L;
		if (p.y > y0) {
			float s = p.y - y0;
			float R = sz.y * 0.1;
			float r = R * (1.0 - 0.1 * clamp(s / (6.2831853 * R), 0.0, 4.0));
			float a = s / r;
			p.y = y0 + r * sin(a);
			p.z -= r - r * cos(a);
		}
	}
	// 2) 폭 방향 휨(원통에 감긴 것처럼). 양옆 끝이 이루는 각 = bend.x × 2.6 rad
	if (abs(warp_bend.x) > 0.0005) {
		float th = warp_bend.x * 2.6;
		float rb = sz.x / th;
		float a = p.x / rb;
		float zz = p.z;
		p.x = (rb + zz) * sin(a);
		p.z = (rb + zz) * cos(a) - rb;
	}
	// 3) 높이 방향 휨
	if (abs(warp_bend.y) > 0.0005) {
		float th = warp_bend.y * 2.2;
		float rb = sz.y / th;
		float a = p.y / rb;
		float zz = p.z;
		p.y = (rb + zz) * sin(a);
		p.z = (rb + zz) * cos(a) - rb;
	}
	// 4) 물결: 대각선으로 흐르는 파동, 가장자리일수록 크게 펄럭인다
	if (warp_flutter > 0.0005) {
		float edge = 0.35 + abs(n.x) + abs(n.y) * 0.6;
		p.z += warp_flutter * sz.x * 0.09 * edge * sin(n.x * 5.5 + n.y * 3.2 - t * 9.0);
	}
	// 5) 비틀림 + Y축 회전: 위쪽이 더 돈다
	float yaw = warp_yaw - warp_twist * n.y;
	float cy = cos(yaw);
	float sy = sin(yaw);
	p = vec3(p.x * cy + p.z * sy, p.y, -p.x * sy + p.z * cy);
	// 6) X축 회전
	float cp = cos(warp_pitch);
	float sp = sin(warp_pitch);
	p = vec3(p.x, p.y * cp - p.z * sp, p.y * sp + p.z * cp);
	return p;
}

// 원근 투영(카드 가운데 기준, 앞으로 나온 쪽이 커진다)
vec2 warp_project(vec3 p) {
	float f = card_size.y * 3.2;
	return p.xy * f / max(f - p.z, f * 0.3);
}

bool warp_active() {
	return abs(warp_yaw) + abs(warp_pitch) + abs(warp_bend.x) + abs(warp_bend.y) + warp_roll + abs(warp_twist) + warp_flutter > 0.0005;
}

// vertex() 에서 부른다: 변형된 위치를 돌려주고 info 에 앞뒷면·명암·반사광을 넣는다.
//   vec3 wi; VERTEX = warp_vertex(VERTEX, TIME, wi); v_warp = wi;
vec2 warp_vertex(vec2 vtx, float t, out vec3 info) {
	info = vec3(1.0, 1.0, 0.0);
	if (!warp_active()) {
		return vtx;
	}
	vec2 c = pad + card_size * 0.5;
	vec2 n = (vtx - c) / card_size;
	float e = 0.02;
	vec3 p0 = warp_point(n, t);
	vec3 px = warp_point(n + vec2(e, 0.0), t);
	vec3 py = warp_point(n + vec2(0.0, e), t);
	vec2 s0 = warp_project(p0);
	vec2 sx = warp_project(px);
	vec2 sy = warp_project(py);
	vec2 dx = sx - s0;
	vec2 dy = sy - s0;
	float face = dx.x * dy.y - dx.y * dy.x;
	vec3 nrm = normalize(cross(px - p0, py - p0));
	if (face < 0.0) {
		nrm = -nrm;
	}
	// 왼쪽 위 앞에서 오는 빛. 평평한 카드(nrm = +Z)의 값을 기준으로 상대 명암만 준다
	vec3 L = normalize(vec3(-0.45, -0.6, 0.66));
	vec3 H = normalize(L + vec3(0.0, 0.0, 1.0));
	float shade = clamp(1.0 + (dot(nrm, L) - L.z) * 0.85, 0.45, 1.25);
	float glint = max(0.0, dot(nrm, H) - H.z) * 2.2;
	info = vec3(sign(face), shade, glint);
	return c + s0;
}

// fragment() 에서 부른다: 뒷면이면 뒷면 그림(좌우 반전), 명암·반사광·마법 광택을 입힌다.
// front = 앞면 색(알파 포함), c = 카드 UV(0..1)
vec4 warp_shade(vec4 front, vec2 c, float t) {
	vec4 col = front;
	if (v_warp.x < 0.0) {
		vec2 b = vec2(1.0 - c.x, c.y);
		float inside = step(0.0, b.x) * step(b.x, 1.0) * step(0.0, b.y) * step(b.y, 1.0);
		col = texture(card_back, clamp(b, 0.0, 1.0));
		col.a *= inside;
	}
	col.rgb *= v_warp.y;
	col.rgb += vec3(1.0, 0.95, 0.85) * clamp(v_warp.z, 0.0, 0.6) * 0.55;
	if (warp_magic > 0.001) {
		// 대각선으로 흐르는 보랏빛·금빛 무지개 띠(마법 포일)
		float d = c.x * 0.8 + c.y * 0.55 - t * 0.9 + warp_yaw * 0.25;
		float band = pow(0.5 + 0.5 * sin(d * 9.0), 6.0);
		vec3 iri = 0.5 + 0.5 * cos(6.2831853 * (vec3(0.0, 0.33, 0.67) + d * 0.7 + 0.15));
		iri = mix(iri, vec3(0.8, 0.6, 1.0), 0.35);
		col.rgb += iri * band * warp_magic * 0.42;
	}
	return col;
}
