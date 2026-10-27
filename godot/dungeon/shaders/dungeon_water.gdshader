shader_type spatial;
render_mode specular_disabled, cull_disabled;
// 꺼진 낭떠러지 아래 밤 물웅덩이. 깊은 남청 바탕에 달빛 물결 줄무늬와 물가 반짝임.
#include "res://shaders/colored_air.gdshaderinc"
uniform vec4 deep : source_color = vec4(.05,.08,.20,1.0);
uniform vec4 shallow : source_color = vec4(.14,.24,.46,1.0);
uniform vec4 glint : source_color = vec4(.62,.72,1.0,1.0);
uniform float emission = .55;
varying vec3 world_pos;

// 세계 좌표가 수백 m 라 sin 해시는 정밀도가 깨져 네모 무늬가 생긴다 — fract 해시를 쓴다
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx)*.1031);
	p3 += dot(p3,p3.yzx+33.33);
	return fract((p3.x+p3.y)*p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
	vec2 p = world_pos.xz;
	float n = vnoise(p*.18+vec2(TIME*.03,0.0))*.6+vnoise(p*.5-vec2(0.0,TIME*.05))*.4;
	vec3 c = mix(deep.rgb,shallow.rgb,smoothstep(.25,.85,n));
	// 달빛 물결: 가늘게 끊긴 가로 줄무늬가 천천히 흐른다
	float band = sin(p.y*2.3+p.x*.35+n*5.0+TIME*.6);
	float streak = smoothstep(.93,1.0,band)*smoothstep(.45,.75,vnoise(p*vec2(.35,1.4)+TIME*.08));
	c += glint.rgb*streak*.55;
	float spark = step(.985,hash(floor(p*3.0)+floor(TIME*2.0)))*smoothstep(.6,.9,n);
	c += glint.rgb*spark*.8;
	ALBEDO = c*.4;
	EMISSION = c*emission;
	ROUGHNESS = 1.0; SPECULAR = 0.0;
	FOG = colored_air(world_pos,VERTEX,INV_VIEW_MATRIX[3].xyz);
}
