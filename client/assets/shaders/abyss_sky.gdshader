shader_type canvas_item;
// 深渊天光：竖直渐变 + 右上角冷光渗下，给整个场景定基调。
// 屏幕空间绘制（挂在 CanvasLayer 的 ColorRect 上），不随相机移动。

uniform vec4 top_color : source_color = vec4(0.048, 0.078, 0.098, 1.0);
uniform vec4 mid_color : source_color = vec4(0.088, 0.146, 0.166, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.020, 0.030, 0.038, 1.0);
uniform vec4 shaft_color : source_color = vec4(0.150, 0.260, 0.270, 1.0);
uniform float shaft_strength = 0.22;

void fragment() {
	vec3 col = mix(top_color.rgb, mid_color.rgb, smoothstep(0.0, 0.55, UV.y));
	col = mix(col, bottom_color.rgb, smoothstep(0.45, 1.0, UV.y));
	// 光柱从右上方斜下来，用一条拉长的椭圆近似
	vec2 p = (UV - vec2(0.74, 0.10)) * vec2(1.0, 2.2);
	float d = length(p);
	col += shaft_color.rgb * exp(-d * 3.4) * shaft_strength;
	COLOR = vec4(col, 1.0);
}
