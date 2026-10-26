shader_type canvas_item;
// Keep the actual transparent cutout silhouette; gently soften only the cropped clothing base.
void fragment() {
	COLOR.a *= 1.0 - smoothstep(0.975, 1.0, UV.y);
}
