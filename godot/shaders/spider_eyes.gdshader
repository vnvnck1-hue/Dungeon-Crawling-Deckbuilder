shader_type spatial;
// 서리 거미 머리: painted_prop과 같은 페인터리 셰이딩 + 텍스처에 그려진 눈 4개 위로 눈꺼풀이 위→아래로 덮이는 깜빡임.
// 눈 위치는 GLB 모델 좌표(정면 투영 실측, tools/inspect_spider_eyes.gd)이며 머리 메시가 모델 좌표로 구워져 있어 그대로 쓴다.
render_mode specular_disabled, cull_disabled;
#include "res://shaders/card_style.gdshaderinc"
uniform sampler2D paint_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform float paint_gain = 1.0;
uniform float painted_fill = .11;
uniform float texture_mix = 1.0;
uniform vec4 base_color : source_color = vec4(1.0);
uniform vec4 lid_color : source_color = vec4(.20,.18,.34,1.0);
uniform vec4 eye_glow : source_color = vec4(.35,.85,1.0,1.0);
uniform float glow_strength = .55;
// xy 중심, zw 반지름(가로·세로). 0·1 = 위쪽 작은 눈 L·R, 2·3 = 아래쪽 큰 눈 L·R
uniform vec4 eye0 = vec4(-.0300,.3245,.0170,.0135);
uniform vec4 eye1 = vec4(.0294,.3245,.0170,.0135);
uniform vec4 eye2 = vec4(-.0383,.2845,.0285,.0290);
uniform vec4 eye3 = vec4(.0367,.2850,.0310,.0285);
instance uniform float hit_flash = 0.0;
instance uniform float blink_top = 0.0;   // 0 뜸 → 1 감음
instance uniform float blink_big = 0.0;
varying vec3 world_pos;
varying vec3 world_normal;
varying vec3 obj_pos;

void vertex() {
	obj_pos = VERTEX;
	world_pos = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL,0.0)).xyz);
}

// 눈 타원 안이면 1, 눈꺼풀이 내려온 부분이면 lid에 1을 쓴다. 가장자리에 어두운 속눈썹 선.
void eye_lid(vec4 e, float blink, inout float lid, inout float line_k, inout float inside) {
	vec2 d = (obj_pos.xy - e.xy) / (e.zw * 1.18);
	float r = length(d);
	if (r > 1.0 || obj_pos.z < .30) return;
	inside = max(inside, 1.0 - smoothstep(.85,1.0,r));
	// 눈꺼풀 아래 끝 높이: 1(위 가장자리) → -1(아래 가장자리)
	float edge = 1.0 - 2.0 * blink;
	float cover = smoothstep(edge - .08, edge + .02, d.y) * step(.02, blink);
	lid = max(lid, cover);
	line_k = max(line_k, (1.0 - smoothstep(0.0,.16,abs(d.y - edge))) * step(.02, blink) * step(blink,.98));
}

void fragment() {
	if (!FRONT_FACING) NORMAL = -NORMAL;
	vec3 tex = texture(paint_texture,UV).rgb;
	vec3 c = base_color.rgb;
	c = mix(c,c * tex * paint_gain,texture_mix*card_style_ink.y);
	// 텍스처의 밝은 청록 = 눈동자
	float eye_mask = smoothstep(.55,.75,tex.b) * smoothstep(.45,.65,tex.g) * (1.0 - smoothstep(.45,.6,tex.r));
	float lid = 0.0, line_k = 0.0, inside = 0.0;
	eye_lid(eye0, blink_top, lid, line_k, inside);
	eye_lid(eye1, blink_top, lid, line_k, inside);
	eye_lid(eye2, blink_big, lid, line_k, inside);
	eye_lid(eye3, blink_big, lid, line_k, inside);
	lid *= inside;
	float open_eye = eye_mask * (1.0 - lid);
	float dist = length((world_pos.xz - vec2(1.0,1.3)) / vec2(1.1,1.0));
	float edge = smoothstep(8.0,21.0,dist);
	vec3 cool = mix(vec3(.40,.37,.66),vec3(.30,.55,.64),smoothstep(-10.0,14.0,world_pos.x-world_pos.z));
	c *= mix(vec3(1.0),cool,edge*.75);
	c *= 1.0-edge*.28;
	// 눈꺼풀: 갑각 색 + 가장자리 어두운 선
	c = mix(c, lid_color.rgb, lid);
	c = mix(c, lid_color.rgb * .35, line_k * inside * .8);
	c = card_surface_color(c,NORMAL,VIEW,1.0);
	ALBEDO = mix(c,vec3(1.0,.87,.93),hit_flash*.55);
	ROUGHNESS = 1.0; SPECULAR = 0.0;
	EMISSION = (c*painted_fill + c*max(world_normal.y,0.0)*.035)*card_style_surface.z + vec3(.8,.1,.2)*hit_flash*.4
		+ eye_glow.rgb * open_eye * glow_strength;
	FOG = colored_air(world_pos,VERTEX,INV_VIEW_MATRIX[3].xyz);
}

void light() {
	float d = smoothstep(.06,.94,(dot(NORMAL,LIGHT)+.32)/1.32);
	d = card_diffuse(dot(NORMAL,LIGHT),d,1.0,LIGHT_IS_DIRECTIONAL);
	vec3 lc = LIGHT_COLOR/PI;
	DIFFUSE_LIGHT += lc * ATTENUATION * d;
	float warm = max(lc.r-lc.b*1.55,0.0);
	DIFFUSE_LIGHT -= vec3(0.0,0.0,.12)*clamp(warm*ATTENUATION*d,0.0,1.0);
}
