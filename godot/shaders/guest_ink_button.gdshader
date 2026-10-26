shader_type canvas_item;
// 대화창 '마녀의 대답'·'다음' 버튼용 잉크 패널. 뒤 대화 패널(guest_ink_panel.tres)과 같은 천 일렁임 위에,
// 흐름이 흐름을 비트는 노이즈로 몸통이 액체처럼 제멋대로 휘며 일렁인다(두께는 거의 그대로, 속은 단색). 색·테두리는 버튼 상태(ReplyRow)가 정한다.

uniform float motion_time = 0.0;      // 패널과 같은 시계(presenter.clock)
uniform vec2 rect_size = vec2(430.0, 150.0);   // 이 ColorRect 의 픽셀 크기(버튼 + pad 양쪽)
uniform float pad_px = 18.0;          // 버튼 윤곽 바깥 여유(일렁임이 잘리지 않게)
uniform vec2 panel_origin = vec2(0.0); // 이 ColorRect 왼쪽 위의 패널 좌표(px, 패널 왼쪽 위 = 0)
uniform vec2 panel_size = vec2(1550.0, 500.0);
uniform float wobble = 0.9;           // 패널 일렁임 대비 윤곽 흔들림 비율
uniform vec4 fill_color : source_color = vec4(0.141, 0.086, 0.243, 0.82);
uniform vec4 border_color : source_color = vec4(0.655, 0.588, 0.804, 0.22);
uniform float border_px = 1.0;

uniform float radius_px = 14.0;       // 네모 모서리 둥글기
uniform float bump_px = 4.5;          // 액체 윤곽이 부풀었다 빠지는 크기
uniform float seed = 1.0;             // 버튼마다 다른 흐름(서로 따로 울렁이게)

// 둥근 네모까지의 거리(px)
float rounded_box(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

// sin 없는 해시(GPU 정밀도 때문에 생기는 줄무늬·계단이 없다)
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// 5차 보간 값 노이즈(0~1): 격자 경계에서 꺾임 없이 매끈하다
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 큰 덩어리 위주 두 겹(잔 옥타브가 섞이면 액체가 아니라 찢긴 종이처럼 보인다)
float liquid_noise(vec2 p) {
	return 0.72 * vnoise(p) + 0.28 * vnoise(mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6)) * p + vec2(3.1, 7.7));
}

void fragment() {
	vec2 px = UV * rect_size;
	vec2 puv = (panel_origin + px) / panel_size;
	float clock = motion_time;
	// guest_ink_panel 'Slow cloth / 2 waves' 와 같은 식(패널 uv 기준) → 픽셀 변위
	vec2 shift;
	shift.y = (0.018 * sin(puv.x * 12.0 + clock * 0.48) + 0.009 * sin(puv.x * 23.0 - clock * 0.31)) * panel_size.y;
	shift.x = 0.007 * sin(puv.y * 9.0 + clock * 0.37) * panel_size.x;
	vec2 warped = px + shift * wobble;
	vec2 half_size = rect_size * 0.5 - vec2(pad_px);
	vec2 c = warped - rect_size * 0.5;
	// 액체 윤곽: 덩어리를 부풀리는 대신 '휘게' 한다. 위아래 변은 x 를 따라, 좌우 변은 y 를 따라 같은 양만큼
	// 함께 밀려서 버튼 두께(위↔아래 폭)는 거의 그대로이고 몸통만 제멋대로 구불거린다.
	// 휨 곡선은 흐름이 흐름을 비트는 노이즈라 같은 모양이 반복되지 않는다. seed 로 버튼마다 흐름·박자가 다르다.
	float t = clock + seed * 11.0;
	vec2 sp = c * 0.0065 + vec2(seed * 3.7, seed * 1.9);
	float drift_x = liquid_noise(vec2(sp.x * 0.8, t * 0.09 + seed));
	float drift_y = liquid_noise(vec2(t * 0.08 - seed, sp.y * 0.8 + 4.1));
	float bend_y = liquid_noise(vec2(sp.x + drift_x * 1.6, t * 0.12)) * 2.0 - 1.0;
	float bend_x = liquid_noise(vec2(t * 0.1 + 7.3, sp.y + drift_y * 1.6)) * 2.0 - 1.0;
	c -= vec2(bend_x * 0.6, bend_y) * bump_px * 2.4;
	float d = rounded_box(c, half_size, radius_px);
	// 두께 차이는 아주 조금만(굵은 곳과 얇은 곳이 거의 같게)
	float swell = liquid_noise(sp * 1.2 + vec2(t * 0.05, -t * 0.04)) * 2.0 - 1.0;
	d -= swell * bump_px * 0.35;
	float aa = max(fwidth(d), 0.75);
	float inside = 1.0 - smoothstep(-aa, aa, d);
	// 테두리: 윤곽 안쪽 border_px 띠
	float band = smoothstep(-border_px - aa, -border_px + aa, d);
	vec3 fill = fill_color.rgb;  // 속은 단색(외형만 일렁인다)
	// 바탕 위에 테두리를 겹친다(source-over)
	float edge_a = band * border_color.a;
	float a = fill_color.a + (1.0 - fill_color.a) * edge_a;
	vec3 rgb = (fill * fill_color.a * (1.0 - edge_a) + border_color.rgb * edge_a) / max(a, 0.001);
	COLOR = vec4(rgb, a * inside);
}
