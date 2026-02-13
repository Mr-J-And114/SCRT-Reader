shader_type canvas_item;

// Godot 4.x 需要显式声明屏幕纹理
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// ============================================================
// CRT 效果参数 - 可在检查器中实时调节
// ============================================================

// --- 扫描线 ---
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.08;
uniform float scanline_frequency : hint_range(100.0, 800.0) = 300.0;
uniform float scanline_speed : hint_range(0.0, 5.0) = 1.0;

// --- 屏幕弯曲 ---
uniform float curvature : hint_range(0.0, 10.0) = 2.5;

// --- 色差/色散 ---
uniform float chromatic_aberration : hint_range(0.0, 5.0) = 0.8;

// --- 暗角 ---
uniform float vignette_intensity : hint_range(0.0, 2.0) = 0.25;
uniform float vignette_size : hint_range(0.0, 1.0) = 0.75;

// --- 闪烁 ---
uniform float flicker_intensity : hint_range(0.0, 0.2) = 0.03;
uniform float flicker_speed : hint_range(0.0, 20.0) = 8.0;

// --- 噪点 ---
uniform float noise_intensity : hint_range(0.0, 0.5) = 0.04;

// --- 磷光/辉光 ---
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.6;
uniform float bloom_spread : hint_range(0.0, 10.0) = 3.0;
uniform float bloom_intensity : hint_range(0.0, 2.0) = 0.5;
uniform vec3 phosphor_color : source_color = vec3(0.1, 1.0, 0.3);
uniform float phosphor_boost : hint_range(0.0, 2.0) = 0.35;

// --- 亮度 ---
uniform float brightness : hint_range(0.5, 2.0) = 1.4;
uniform float contrast : hint_range(0.5, 2.0) = 1.15;

// ============================================================
// 工具函数
// ============================================================

// 伪随机数生成
float random(vec2 co) {
	return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

// 屏幕弯曲变形 UV
vec2 curve_uv(vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	float dist = dot(centered, centered);
	centered *= 1.0 + dist * curvature * 0.02;
	return centered * 0.5 + 0.5;
}

// ============================================================
// 主片段着色器
// ============================================================
void fragment() {
	// --- 1. 屏幕弯曲 ---
	vec2 uv = curve_uv(SCREEN_UV);

	// 超出屏幕范围的部分显示为黑色（弯曲后的边角）
		// 超出屏幕范围的部分显示为黑色（弯曲后的边角）
	if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		// --- 2. 色差（RGB通道微小偏移）---
		float aberration = chromatic_aberration * 0.001;
		float r = texture(SCREEN_TEXTURE, vec2(uv.x + aberration, uv.y)).r;
		float g = texture(SCREEN_TEXTURE, uv).g;
		float b = texture(SCREEN_TEXTURE, vec2(uv.x - aberration, uv.y)).b;
		vec3 col = vec3(r, g, b);

		// --- 3. 扫描线 ---
		float scanline_y = uv.y * scanline_frequency + TIME * scanline_speed;
		float scanline = sin(scanline_y * 3.14159) * 0.5 + 0.5;
		scanline = pow(scanline, 1.5);
		col *= 1.0 - scanline_intensity * (1.0 - scanline);

		// --- 4. 移动扫描线（模拟CRT刷新）---
		float rolling_line = sin(uv.y * 3.0 + TIME * 0.5) * 0.5 + 0.5;
		rolling_line = pow(rolling_line, 20.0);
		col += col * rolling_line * 0.02;

		// --- 5. 噪点 ---
		float noise = random(uv * TIME) * noise_intensity;
		col += noise;

		// --- 6. 闪烁 ---
		float flicker = 1.0 + sin(TIME * flicker_speed) * flicker_intensity;
		col *= flicker;

		// --- 7. 暗角 ---
		vec2 vig_uv = uv * (1.0 - uv);
		float vig = vig_uv.x * vig_uv.y * 15.0;
		vig = pow(vig, vignette_intensity);
		vig = mix(vignette_size, 1.0, vig);
		col *= vig;

		// --- 8. 模拟Bloom（多次采样模糊发光）---
		vec3 bloom = vec3(0.0);
		float pixel_size_x = bloom_spread / float(textureSize(SCREEN_TEXTURE, 0).x);
		float pixel_size_y = bloom_spread / float(textureSize(SCREEN_TEXTURE, 0).y);
		for (int x = -2; x <= 2; x++) {
			for (int y = -2; y <= 2; y++) {
				vec2 offset = vec2(float(x) * pixel_size_x, float(y) * pixel_size_y);
				bloom += texture(SCREEN_TEXTURE, uv + offset).rgb;
			}
		}
		bloom /= 25.0;
		col += bloom * bloom_intensity;

		// --- 9. 磷光色调叠加 ---
		float luma = dot(col, vec3(0.299, 0.587, 0.114));
		col += phosphor_color * luma * phosphor_boost;
		col += col * luma * glow_intensity;

		// --- 10. 亮度和对比度 ---
		col = (col - 0.5) * contrast + 0.5;
		col *= brightness;

		// --- 11. 钳制颜色范围 ---
		col = clamp(col, 0.0, 1.0);

		COLOR = vec4(col, 1.0);
	}
}
