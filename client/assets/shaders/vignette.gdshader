shader_type canvas_item;
// 暗角：压住四角，把视线收到画面中间。挂在 CanvasLayer 的全屏 ColorRect 上。

uniform float strength = 0.92;
uniform float inner = 0.30;
uniform float outer = 0.80;
uniform vec4 tint : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 uv = UV - 0.5;
	float d = length(uv * vec2(1.0, 0.86));
	float a = smoothstep(inner, outer, d) * strength;
	COLOR = vec4(tint.rgb, a);
}
