shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;

// --- 扫描线 ---
uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.15;
uniform float scanline_frequency : hint_range(100.0, 800.0) = 300.0;
uniform float scanline_speed : hint_range(0.0, 5.0) = 1.0;

// --- 屏幕弯曲 ---
uniform float curvature : hint_range(0.0, 10.0) = 1.0;

// --- 色差 ---
uniform float chromatic_aberration : hint_range(0.0, 5.0) = 0.3;

// --- 暗角 ---
uniform float vignette_intensity : hint_range(0.0, 2.0) = 0.4;
uniform float vignette_size : hint_range(0.0, 1.0) = 0.6;

// --- 闪烁 ---
uniform float flicker_intensity : hint_range(0.0, 0.2) = 0.03;
uniform float flicker_speed : hint_range(0.0, 20.0) = 8.0;

// --- 噪点 ---
uniform float noise_intensity : hint_range(0.0, 0.5) = 0.04;

// --- 磷光/辉光 ---
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.9;
uniform float bloom_spread : hint_range(0.0, 10.0) = 0.8;
uniform float bloom_intensity : hint_range(0.0, 2.0) = 0.4;
uniform vec3 phosphor_color : source_color = vec3(0.1, 1.0, 0.2);
uniform float phosphor_boost : hint_range(0.0, 2.0) = 0.2;

// --- 亮度/对比度 ---
uniform float brightness : hint_range(0.5, 2.0) = 1.2;
uniform float contrast : hint_range(0.5, 2.0) = 1.1;

// --- ★ 新增：过曝控制 ---
uniform float max_brightness : hint_range(0.5, 2.0) = 1;
uniform float tonemap_compensation : hint_range(1.0, 3.0) = 1.6;

float random(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 curve_uv(vec2 uv) {
    vec2 centered = uv * 2.0 - 1.0;
    float dist = dot(centered, centered);
    centered *= 1.0 + dist * curvature * 0.02;
    return centered * 0.5 + 0.5;
}

void fragment() {
    vec2 uv = curve_uv(SCREEN_UV);

    if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
        COLOR = vec4(0.0, 0.0, 0.0, 1.0);
    } else {
        // --- 1. 色差 ---
        float aberration = chromatic_aberration * 0.001;
        float r = texture(SCREEN_TEXTURE, vec2(uv.x + aberration, uv.y)).r;
        float g = texture(SCREEN_TEXTURE, uv).g;
        float b = texture(SCREEN_TEXTURE, vec2(uv.x - aberration, uv.y)).b;
        vec3 col = vec3(r, g, b);

        // --- 2. 扫描线 ---
        float scanline_y = uv.y * scanline_frequency + TIME * scanline_speed;
        float scanline = sin(scanline_y * 3.14159) * 0.5 + 0.5;
        scanline = pow(scanline, 1.5);
        col *= 1.0 - scanline_intensity * (1.0 - scanline);

        // --- 3. 移动扫描线 ---
        float rolling_line = sin(uv.y * 3.0 + TIME * 0.5) * 0.5 + 0.5;
        rolling_line = pow(rolling_line, 20.0);
        col += col * rolling_line * 0.02;

        // --- 4. 噪点 ---
        float noise = random(uv * TIME) * noise_intensity;
        col += noise;

        // --- 5. 闪烁 ---
        float flicker = 1.0 + sin(TIME * flicker_speed) * flicker_intensity;
        col *= flicker;

        // --- 6. 暗角 ---
        vec2 vig_uv = uv * (1.0 - uv);
        float vig = vig_uv.x * vig_uv.y * 15.0;
        vig = pow(vig, vignette_intensity);
        vig = mix(vignette_size, 1.0, vig);
        col *= vig;

        // --- 7. Bloom ---
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

        // ★ 关键改动1：bloom 只对暗部区域有效果，亮部不再叠加
        // 原来：col += bloom * bloom_intensity;（亮部也叠加，导致过曝）
        float col_luma = dot(col, vec3(0.299, 0.587, 0.114));
        float bloom_mask = 1.0 - smoothstep(0.3, 0.7, col_luma);
        col += bloom * bloom_intensity * bloom_mask;

        // --- 8. 磷光色调 ---
        float luma = dot(col, vec3(0.299, 0.587, 0.114));

        // ★ 关键改动2：phosphor 和 glow 使用 sqrt(luma) 而非 luma
        // 这样亮部的增量被大幅压缩（sqrt 曲线在高值处增长很慢）
        float soft_luma = sqrt(clamp(luma, 0.0, 1.0));
        col += phosphor_color * soft_luma * phosphor_boost;
        col += col * soft_luma * glow_intensity * 0.5;

        // --- 9. 亮度和对比度 ---
        col = (col - 0.5) * contrast + 0.5;
        col *= brightness;

        // --- 10. ★ 改进的 tone mapping ---
        // 先限制最大亮度，然后做 Reinhard，再用较低的补偿系数
        col = min(col, vec3(max_brightness * 2.0));
        col = col / (col + vec3(1.0));
        col *= tonemap_compensation;

        // --- 11. 最终钳制 ---
        col = clamp(col, 0.0, 1.0);

        COLOR = vec4(col, 1.0);
    }
}