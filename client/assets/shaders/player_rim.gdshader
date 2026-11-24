shader_type canvas_item;

// 主角轮廓光（P0 美术打磨）：沿贴图 alpha 边缘补一圈冷色亮边，
// 让"近黑的骑士"在同样是深色的背景/石壁上还能读出剪影。
// 只给实心部件用，眼睛/发光层不要挂这个材质。

uniform vec4 rim_color : source_color = vec4(0.60, 0.76, 0.92, 1.0);
uniform float rim_width = 3.5;      // 采样距离（贴图像素）
uniform float rim_strength = 0.62;
uniform float top_bias = 1.0;       // 顶面受光最强
uniform float side_bias = 0.50;     // 两侧弱一些
uniform float bottom_bias = 0.10;   // 底部几乎不打光

void fragment() {
	vec4 base = texture(TEXTURE, UV) * COLOR;
	vec2 step_px = TEXTURE_PIXEL_SIZE * rim_width;
	float a_up = texture(TEXTURE, UV + vec2(0.0, -step_px.y)).a;
	float a_down = texture(TEXTURE, UV + vec2(0.0, step_px.y)).a;
	float a_left = texture(TEXTURE, UV + vec2(-step_px.x, 0.0)).a;
	float a_right = texture(TEXTURE, UV + vec2(step_px.x, 0.0)).a;
	float edge_up = (1.0 - a_up) * base.a;
	float edge_down = (1.0 - a_down) * base.a;
	float edge_side = max(1.0 - a_left, 1.0 - a_right) * base.a;
	float edge = clamp(max(edge_up * top_bias, max(edge_side * side_bias, edge_down * bottom_bias)), 0.0, 1.0);
	vec3 lit = mix(base.rgb, rim_color.rgb * 1.15, edge * rim_strength);
	COLOR = vec4(lit, base.a);
}
