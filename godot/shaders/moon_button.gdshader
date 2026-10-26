shader_type canvas_item;
// 달빛 UI 버튼 상태(명세 §5): 외형 크기는 그대로 두고 경계만 청록/크림으로 약하게 강조,
// 비활성은 저채도, 활성 임시 착색(tint). 원본 그림 픽셀은 바꾸지 않고 표시만 조정한다.

uniform vec4 outline_color : source_color = vec4(0.22, 0.74, 0.76, 1.0);
uniform float outline : hint_range(0.0, 1.0) = 0.0;
uniform float outline_px = 2.0;
uniform float saturation = 1.0;
uniform float brightness = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 0.0);

varying vec4 v_modulate;

void vertex() {
	v_modulate = COLOR;  // fragment의 COLOR에는 이미 텍스처가 곱해져 있으므로 정점 색만 따로 보관
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(vec3(l), c.rgb, saturation) * brightness;
	c.rgb = mix(c.rgb, tint.rgb * (0.3 + l * 1.5), tint.a);
	if (outline > 0.001) {
		vec2 px = TEXTURE_PIXEL_SIZE * outline_px;
		float amax = 0.0;
		float amin = 1.0;
		for (int i = 0; i < 12; i++) {
			float a = float(i) * 0.5235988;
			float s = texture(TEXTURE, UV + vec2(cos(a), sin(a)) * px).a;
			amax = max(amax, s);
			amin = min(amin, s);
		}
		float outer = amax * (1.0 - c.a);
		float inner = c.a * (1.0 - amin);
		float g = clamp(outer + inner * 0.7, 0.0, 1.0) * outline * outline_color.a;
		c.rgb = mix(c.rgb, outline_color.rgb, g);
		c.a = max(c.a, g);
	}
	COLOR = c * v_modulate;
}
