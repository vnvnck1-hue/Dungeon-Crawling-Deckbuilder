shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
// 방 격자 오버레이: 칸 테두리, 아군/적 지역 색, 가운데 경계선, 칸마다 강조(cell_state 텍스처).
// UV: x = 열(0..cols), y = 행(0..rows)로 메시가 넘겨준다. 표시 전용.

uniform sampler2D cell_state : filter_nearest, repeat_disable;  // RGB 색, A 세기(0 = 강조 없음)
uniform vec2 grid = vec2(8.0,4.0);
uniform float ally_cols = 4.0;
uniform vec4 ally_tint : source_color = vec4(.35,.75,1.0,1.0);
uniform vec4 enemy_tint : source_color = vec4(1.0,.32,.42,1.0);
uniform float base_alpha = .10;
uniform float line_alpha = .24;
uniform float reveal = 1.0;   // 0..1 방 입장 때 격자가 번져 나타남

void fragment() {
	vec2 g = UV*grid;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	bool enemy = cell.x >= ally_cols;
	vec3 tint = enemy ? enemy_tint.rgb : ally_tint.rgb;
	// 둥근 칸 테두리(안쪽이 비고 가장자리만 옅게 빛남)
	vec2 q = abs(f-.5)*2.0;
	float r = .22;
	vec2 e = max(q-(1.0-r),vec2(0.0));
	float box = length(e)/r;
	float border = smoothstep(.74,.92,max(max(q.x,q.y),box));
	float inner = 1.0-smoothstep(.0,.9,max(q.x,q.y));
	float a = border*line_alpha+base_alpha*.35+inner*.04;
	vec3 col = tint;
	// 아군·적 지역 경계선
	float edge_d = abs(g.x-ally_cols);
	float seam = 1.0-smoothstep(.0,.07,edge_d);
	float seam_glow = (1.0-smoothstep(.0,.45,edge_d))*.35;
	col = mix(col,vec3(1.0,.93,.78),seam);
	a = max(a,seam*.85+seam_glow);
	// 칸 강조
	vec4 s = texture(cell_state,(cell+.5)/grid);
	if (s.a > .001) {
		float pulse = .82+.18*sin(TIME*5.0);
		float fill = (.30+.25*(1.0-max(q.x,q.y)))*s.a*pulse;
		float ring = border*s.a;
		col = mix(col,s.rgb,clamp(fill*2.2+ring,0.0,1.0));
		a = max(a,fill+ring*.9);
	}
	// 바깥 테두리를 부드럽게
	vec2 outer = min(UV,1.0-UV)*grid;
	float fade = smoothstep(.0,.12,min(outer.x,outer.y));
	// 방 입장 연출: 경계선에서 바깥으로 번져 나타남
	float spread = 1.0-smoothstep(reveal*grid.x*.6-.6,reveal*grid.x*.6+.01,abs(g.x-ally_cols));
	ALBEDO = col;
	EMISSION = col*.35;
	ALPHA = clamp(a,0.0,1.0)*fade*spread;
}
