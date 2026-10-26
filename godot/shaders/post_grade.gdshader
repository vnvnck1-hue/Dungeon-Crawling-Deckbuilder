// 화면 후처리: 가장자리의 짙은 인디고 비네트 + 어두운 영역을 보라로 들어 올리는 색보정.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform vec4 vignette_color : source_color = vec4(0.17, 0.2, 0.36, 1.0);
uniform float vignette_strength = 0.10;
uniform float vignette_start = 0.45;
uniform float vignette_end = 1.15;
uniform vec4 lift_color : source_color = vec4(0.12, 0.07, 0.26, 1.0);
uniform float lift_amount = 0.0;
uniform float saturation = 1.0;
uniform float toxic_amount = 0.0;
// 보스룸: 차가운 남청 색조·채도 저하·짙은 비네트(boss_amount), 포효 순간 하얀 서리 섬광 + 화면 가장자리 색수차(boss_flash),
// 버티는 동안 비네트가 심장처럼 조여 오는 박동(boss_beat 0~1).
uniform float boss_amount = 0.0;
uniform float boss_flash = 0.0;
uniform float boss_beat = 0.0;

void fragment() {
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec2 uv = SCREEN_UV - 0.5;
	if (boss_flash > 0.001) {
		vec2 shift = (SCREEN_UV - 0.5) * 0.012 * boss_flash;
		c.r = texture(screen_tex, SCREEN_UV + shift).r;
		c.b = texture(screen_tex, SCREEN_UV - shift).b;
	}
	uv.x *= (SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x) * 0.62;
	float v = smoothstep(vignette_start, vignette_end, length(uv) * 1.6);
	c = mix(c, c * vignette_color.rgb * 2.2, v * vignette_strength);
	float lum = dot(c, vec3(0.299, 0.587, 0.114));
	c += lift_color.rgb * (1.0 - smoothstep(0.0, 0.55, lum)) * lift_amount;
	c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
	// Location-driven grade leaves the HUD above this layer fully readable.
	vec3 poisoned = c * vec3(.61, .85, .79);
	float shadow = 1.0-smoothstep(.04,.55,lum);
	poisoned += vec3(.009,.025,.031)*shadow;
	poisoned = mix(poisoned, poisoned*vec3(.32,.47,.58),v*.72);
	c = mix(c,poisoned,toxic_amount*.86);
	// 보스룸 긴장감: 밝은 곳은 차가운 청록 얼음빛만 남기고 나머지는 남청으로 가라앉힌다.
	float bl = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 cold = mix(vec3(bl), c, .72) * vec3(.82, .94, 1.10);
	cold = mix(cold * vec3(.70, .70, .95), cold, smoothstep(.12, .62, bl));
	float edge = smoothstep(.30 - boss_beat * .06, 1.05, length(uv) * 1.6);
	cold = mix(cold, cold * vec3(.10, .10, .24), edge * (.62 + boss_beat * .25));
	c = mix(c, cold, boss_amount);
	c += vec3(.75, .88, 1.0) * boss_flash * .32 * (1.0 - edge * .6);
	COLOR = vec4(c, 1.0);
}
