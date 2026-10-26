shader_type canvas_item;
// 대사 한 줄을 펜으로 적듯 드러낸다(docs/dialogue-handwriting.md).
// 펜 끝(reveal_x)보다 왼쪽만 보이고, 위쪽이 조금 먼저 적히는 비스듬한 경계라 획을 긋는 느낌이 난다.
// 막 적힌 자리는 젖은 잉크 색(wet_color)으로 반짝이다 wet_len 픽셀 뒤로 갈수록 원래 글자색으로 마른다.

uniform float reveal_x = 100000.0;  // 펜 끝 x(Label 로컬 픽셀)
uniform float soft = 6.0;           // 경계 번짐 폭
uniform float slant = 0.25;         // 세로 1px 당 경계가 물러나는 양(위가 먼저)
uniform float center_y = 22.0;      // 기울기 기준 줄 가운데
uniform vec4 wet_color : source_color = vec4(1.0, 0.82, 0.52, 1.0);
uniform float wet_len = 48.0;
uniform float wet_amount = 0.85;    // 0 이면 젖은 색 없이 드러나기만

varying vec2 local;

void vertex() {
	local = VERTEX;
}

void fragment() {
	float edge = reveal_x - (local.y - center_y) * slant;
	float shown = 1.0 - smoothstep(edge - soft, edge, local.x);
	float wet = (1.0 - smoothstep(0.0, wet_len, edge - local.x)) * wet_amount;
	vec4 c = COLOR;
	c.rgb = mix(c.rgb, wet_color.rgb, wet * wet_color.a);
	COLOR = vec4(c.rgb, c.a * shown);
}
