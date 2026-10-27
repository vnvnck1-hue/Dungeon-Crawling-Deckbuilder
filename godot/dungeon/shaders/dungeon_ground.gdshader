shader_type spatial;
render_mode specular_disabled;
// 숲길 원정대 지면. 마녀산장 painted_ground.gdshader 의 붓터치 텍스처(눈·숲길·숲바닥)와
// 무작위 회전 패치 기법, 조명 함수를 그대로 쓰고, 산장 고정 구도(cleanplate·문 앞 따뜻한 빛)만 뺐다.
// 방(공터)은 회전된 사각형, 길은 선분 목록으로 받아 그 자리에 숲길 흙을 칠한다.
#include "res://shaders/colored_air.gdshaderinc"
uniform sampler2D painted_snow : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D painted_trail : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D painted_forest : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float texture_world_size = 2.9;
uniform float warm_enabled = 1.0;
uniform float ground_emission = .44;
uniform float ground_albedo = .62;
uniform float ground_neutral = 0.0;
uniform vec4 ground_tint : source_color = vec4(1.0);
uniform vec4 trail_segments[64];
uniform int trail_count = 0;
uniform float trail_width = 1.6;
// 방: xy = 중심(xz), zw = 반 크기(가로축 = 진행 방향)
uniform vec4 rooms[8];
uniform int room_count = 0;
uniform vec2 room_axis = vec2(.866,-.5);
// 횃불 자리: 방마다 따뜻한 빛 웅덩이(xy 위치, z 반경, w 세기)
uniform vec4 warm_spots[16];
uniform int warm_count = 0;
// 지형 단·절벽(view/terrain.gd): 가파른 면은 바위, 낮은 땅은 푸르게 가라앉고 물가는 젖는다
uniform float water_y = -3.4;
uniform vec4 cliff_dark : source_color = vec4(.09,.08,.19,1.0);
uniform vec4 cliff_light : source_color = vec4(.31,.29,.5,1.0);
varying vec3 world_pos;
varying vec3 world_nrm;

vec2 patch_hash(vec2 p) {
	return fract(sin(vec2(dot(p,vec2(127.1,311.7)),dot(p,vec2(269.5,183.3))))*43758.5453);
}
vec3 paint_patch(sampler2D tex, vec2 p, vec2 cell) {
	vec2 random = patch_hash(cell);
	float angle = random.x*6.2831853;
	mat2 turn = mat2(vec2(cos(angle),-sin(angle)),vec2(sin(angle),cos(angle)));
	vec2 uv = vec2(.5)+turn*(p-cell)*.29+(random-.5)*.10;
	return textureGrad(tex,uv,turn*dFdx(p)*.29,turn*dFdy(p)*.29).rgb;
}
vec3 ground_paint(sampler2D tex, vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	vec4 w = vec4((1.0-f.x)*(1.0-f.y),f.x*(1.0-f.y),(1.0-f.x)*f.y,f.x*f.y);
	w = pow(w,vec4(5.0));
	w /= dot(w,vec4(1.0));
	return paint_patch(tex,p,cell)*w.x + paint_patch(tex,p,cell+vec2(1.0,0.0))*w.y
		+ paint_patch(tex,p,cell+vec2(0.0,1.0))*w.z + paint_patch(tex,p,cell+vec2(1.0,1.0))*w.w;
}
float trail_distance(vec2 p) {
	float d = 1000.0;
	for (int i=0;i<trail_count;i++) {
		vec2 a=trail_segments[i].xy;
		vec2 ab=trail_segments[i].zw-a;
		float t=clamp(dot(p-a,ab)/max(dot(ab,ab),.001),0.0,1.0);
		d=min(d,length(p-a-ab*t));
	}
	return d;
}
// 방 사각형 바깥까지의 거리(안쪽이면 음수)
float room_distance(vec2 p) {
	float d = 1000.0;
	vec2 perp = vec2(-room_axis.y,room_axis.x);
	for (int i=0;i<room_count;i++) {
		vec2 q = p-rooms[i].xy;
		vec2 local = vec2(dot(q,room_axis),dot(q,perp));
		vec2 e = abs(local)-rooms[i].zw;
		float outside = length(max(e,vec2(0.0)));
		float inside = min(max(e.x,e.y),0.0);
		d = min(d,outside+inside);
	}
	return d;
}
void vertex() {
	world_pos = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX*vec4(NORMAL,0.0)).xyz);
}
void fragment() {
	vec2 paint_uv = world_pos.xz / texture_world_size;
	vec3 snow_paint = ground_paint(painted_snow,paint_uv);
	vec3 trail_paint = ground_paint(painted_trail,paint_uv*1.11+vec2(4.7,-2.3));
	vec3 forest_paint = ground_paint(painted_forest,paint_uv*.93+vec2(-3.1,8.2));
	float brush_edge = (snow_paint.r-.47)*.65;
	float trail = 1.0-smoothstep(trail_width*.55,trail_width*1.6,trail_distance(world_pos.xz)+brush_edge);
	float rd = room_distance(world_pos.xz)+brush_edge*1.4;
	float clearing = 1.0-smoothstep(-.6,2.2,rd);
	float path_weight = max(trail*.9,clearing*.55);
	// 밟혀 다져진 길은 눈보다 한 톤 어둡고 따뜻하게(길이 읽히도록)
	vec3 trodden = trail_paint*mix(vec3(1.0),vec3(.78,.72,.74),trail);
	vec3 terrain = mix(snow_paint,trodden,path_weight);
	// 공터·길 둘레는 숲바닥(나무 밑 그늘진 흙과 낙엽)으로 번진다
	float edge = smoothstep(1.5,4.5,rd)*(1.0-smoothstep(5.0,11.0,rd));
	float trail_edge = smoothstep(trail_width*1.2,trail_width*2.6,trail_distance(world_pos.xz))*(1.0-smoothstep(trail_width*2.8,trail_width*5.5,trail_distance(world_pos.xz)));
	float forest_weight = max(edge,trail_edge*.8)*.75*(1.0-trail*.65);
	terrain = mix(terrain,forest_paint,forest_weight);
	vec3 c = terrain;
	c = mix(c,vec3(dot(c,vec3(.2126,.7152,.0722))),.22);
	c *= vec3(1.05,1.01,.91);
	// 깊은 숲은 자두빛·청록빛 안개로
	float outer = smoothstep(4.0,16.0,min(rd,trail_distance(world_pos.xz)));
	float pocket = .5+.5*sin(world_pos.x*.22-world_pos.z*.19);
	vec3 forest_tint = mix(vec3(.25,.16,.40),vec3(.11,.32,.36),pocket);
	c = mix(c,c*.72+forest_tint*.18,outer*.55);
	// 절벽 면: 붓터치를 세로로 펴 바르고 지층 띠를 넣는다. 위 가장자리는 눈 언저리로 밝게 남는다
	vec3 n = normalize(world_nrm);
	float cliff = 1.0-smoothstep(.5,.8,n.y);
	vec2 hd = normalize(n.xz+vec2(.0001));
	vec2 cuv = vec2(dot(world_pos.xz,vec2(-hd.y,hd.x)),world_pos.y*1.6)/texture_world_size;
	vec3 rock_paint = ground_paint(painted_trail,cuv*1.3+vec2(9.1,3.7));
	float rl = dot(rock_paint,vec3(.333));
	float strata = .78+.22*smoothstep(-.3,.6,sin(world_pos.y*3.1+rl*6.0+world_pos.x*.13));
	vec3 rock = mix(cliff_dark.rgb,cliff_light.rgb,clamp(rl*1.15-.1,0.0,1.0))*strata;
	// 절벽이 화면을 향하면(카메라 쪽) 조금 더 밝게 — 단의 앞면이 읽히도록
	rock *= .9+.45*clamp(n.z,0.0,1.0);
	c = mix(c,rock,cliff);
	// 낮은 땅은 푸르게 가라앉고, 높은 단은 달빛에 조금 더 밝다
	float low = smoothstep(-.4,water_y,world_pos.y);
	c = mix(c,c*vec3(.58,.66,.95),low*.65);
	c *= 1.0+smoothstep(1.0,9.0,world_pos.y)*.12;
	// 물가: 젖은 짙은 띠 + 물에 닿는 하얀 결
	float wet = 1.0-smoothstep(.0,.7,world_pos.y-water_y);
	c = mix(c,c*vec3(.45,.5,.7),wet);
	float foam = (1.0-smoothstep(.0,.14,abs(world_pos.y-water_y-.06)))*(.6+.4*sin(world_pos.x*3.0+world_pos.z*2.1));
	c = mix(c,vec3(.7,.78,1.0),foam*.45);
	float warm = 0.0;
	for (int i=0;i<warm_count;i++) {
		vec2 dl = (world_pos.xz-warm_spots[i].xy)/max(warm_spots[i].z,.01);
		warm = max(warm,exp(-dot(dl,dl)*.5)*warm_spots[i].w);
	}
	c = mix(c,vec3(1.0,.53,.23),warm*.6*warm_enabled);
	c = mix(c,vec3(dot(c,vec3(.2126,.7152,.0722))),ground_neutral)*ground_tint.rgb;
	ALBEDO = c*ground_albedo;
	// 달빛을 등진 절벽 앞면도 형태가 읽히게 스스로 조금 더 빛난다
	EMISSION = c*ground_emission*(1.0+cliff*.7);
	ROUGHNESS=1.0; SPECULAR=0.0;
	FOG = colored_air(world_pos,VERTEX,INV_VIEW_MATRIX[3].xyz);
}
void light() {
	float d = smoothstep(.06,.94,(dot(NORMAL,LIGHT)+.32)/1.32);
	vec3 lc = LIGHT_COLOR/PI;
	DIFFUSE_LIGHT += lc * ATTENUATION * d;
	float warm = max(lc.r-lc.b*1.55,0.0);
	DIFFUSE_LIGHT -= vec3(0.0,0.0,.15)*clamp(warm*ATTENUATION*d,0.0,1.0);
}
