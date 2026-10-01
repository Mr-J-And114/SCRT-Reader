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

// --- 屏幕撕裂 ---
uniform float tear_strength : hint_range(0.0, 0.2) = 0.0;
uniform float tear_speed : hint_range(0.0, 10.0) = 3.0;
uniform float tear_count : hint_range(1.0, 10.0) = 3.0;

// --- 磷光/辉光 ---
uniform float glow_intensity : hint_range(0.0, 1.0) = 0.9;
uniform float bloom_spread : hint_range(0.0, 10.0) = 0.8;
uniform float bloom_intensity : hint_range(0.0, 2.0) = 0.4;
uniform vec3 phosphor_color : source_color = vec3(0.1, 1.0, 0.2);
uniform float phosphor_boost : hint_range(0.0, 2.0) = 0.2;

// --- 亮度/对比度 ---
uniform float brightness : hint_range(0.0, 2.0) = 1.2;
uniform float contrast : hint_range(0.5, 2.0) = 1.1;

// --- 过曝控制 ---
uniform float max_brightness : hint_range(0.5, 2.0) = 1.0;
uniform float tonemap_compensation : hint_range(1.0, 3.0) = 1.6;

// ══════════════════════════════════════════════════════════
//  第五阶段新增：Glitch / Shake / Boot-Shutdown 参数
// ══════════════════════════════════════════════════════════

// --- Glitch 故障效果 ---
uniform float glitch_intensity : hint_range(0.0, 1.0) = 0.0;
uniform float glitch_line_speed : hint_range(0.0, 20.0) = 8.0;
uniform float glitch_line_density : hint_range(1.0, 50.0) = 10.0;
uniform float glitch_color_drift : hint_range(0.0, 0.05) = 0.0;

// --- 噪点爆发 ---
uniform float noise_burst : hint_range(0.0, 1.0) = 0.0;

// --- 屏幕震动 ---
uniform vec2 shake_offset = vec2(0.0, 0.0);

// --- 开关机动画 ---
uniform float screen_height_ratio : hint_range(0.0, 1.0) = 1.0;
uniform float boot_glow : hint_range(0.0, 3.0) = 0.0;

// ══════════════════════════════════════════════════════════
//  辅助函数
// ══════════════════════════════════════════════════════════

float random(vec2 co) {
    return fract(sin(dot(co, vec2(12.9898, 78.233))) * 43758.5453);
}

float hash_step(float x) {
    return fract(sin(x * 127.1) * 43758.5453);
}

vec2 curve_uv(vec2 uv) {
    vec2 centered = uv * 2.0 - 1.0;
    float dist = dot(centered, centered);
    centered *= 1.0 + dist * curvature * 0.02;
    return centered * 0.5 + 0.5;
}

// ══════════════════════════════════════════════════════════
//  主片段函数
// ══════════════════════════════════════════════════════════
void fragment() {
    // ---- 0. 屏幕震动偏移 ----
    vec2 base_uv = SCREEN_UV + shake_offset;

    // ---- 0b. 开关机：判断是否在收缩区域外 ----
    bool is_outside_screen = false;
    float shutdown_line_glow = 0.0;

    if (screen_height_ratio < 0.999) {
        float center_y = 0.5;
        float dist_y = abs(base_uv.y - center_y);
        float half_h = screen_height_ratio * 0.5;

        if (dist_y > half_h) {
            // 收缩区域之外
            is_outside_screen = true;
            if (screen_height_ratio < 0.02) {
                float line_dist = abs(base_uv.y - center_y);
                shutdown_line_glow = exp(-line_dist * 80.0) * boot_glow;
            }
        } else {
            // 收缩区域内：重映射 UV.y 到 0~1
            float local_y = (base_uv.y - center_y + half_h) / (half_h * 2.0);
            base_uv.y = local_y;
        }
    }

    // ---- 根据是否在屏幕外分支处理 ----
    if (is_outside_screen) {
        // 屏幕关闭区域：黑色 + 可选中心亮线
        vec3 off_color = phosphor_color * shutdown_line_glow;
        COLOR = vec4(off_color, 1.0);
    } else {
        vec2 uv = curve_uv(base_uv);

        // ---- 0c. Glitch UV 扰动 ----
        if (glitch_intensity > 0.001) {
            float line_seed = floor(uv.y * glitch_line_density + TIME * glitch_line_speed);
            float line_rand = hash_step(line_seed);
            float line_active = step(1.0 - glitch_intensity * 0.6, line_rand);
            float offset_amount = (hash_step(line_seed + 42.0) - 0.5) * 2.0 * glitch_intensity * 0.08;
            uv.x += offset_amount * line_active;

            if (tear_strength > 0.001) {
                float tear_y = uv.y * tear_count + TIME * tear_speed;
                float t1 = step(0.98, fract(sin(tear_y * 12.9898) * 43758.5453));
                float t2 = step(0.97, fract(sin(tear_y * 7.233 + 1.5) * 23421.631));
                float tear_m = max(t1, t2);
                uv.x += tear_m * tear_strength * (random(vec2(floor(uv.y * 50.0), TIME)) * 2.0 - 1.0);
            }
        }

        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            COLOR = vec4(0.0, 0.0, 0.0, 1.0);
        } else {
            // --- 1. 色差 + Glitch 色漂移 ---
            float total_aberration = chromatic_aberration * 0.001 + glitch_color_drift;
            float r = texture(SCREEN_TEXTURE, vec2(uv.x + total_aberration, uv.y)).r;
            float g = texture(SCREEN_TEXTURE, uv).g;
            float b = texture(SCREEN_TEXTURE, vec2(uv.x - total_aberration, uv.y)).b;
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

            // --- 3.5 屏幕撕裂色差增强 ---
            if (tear_strength > 0.001) {
                float tear_render_y = uv.y * tear_count + TIME * tear_speed;
                float tr1 = step(0.98, fract(sin(tear_render_y * 12.9898) * 43758.5453));
                float tr2 = step(0.97, fract(sin(tear_render_y * 7.233 + 1.5) * 23421.631));
                float tr3 = step(0.985, fract(sin(tear_render_y * 17.45 + 3.7) * 65432.123));
                float tear_vis = max(tr1, max(tr2, tr3));
                if (tear_vis > 0.5) {
                    float t_off = tear_strength * (random(vec2(floor(uv.y * 50.0), TIME)) * 2.0 - 1.0);
                    float tr = texture(SCREEN_TEXTURE, vec2(uv.x + t_off + total_aberration, uv.y)).r;
                    float tb = texture(SCREEN_TEXTURE, vec2(uv.x + t_off - total_aberration, uv.y)).b;
                    col.r = tr;
                    col.b = tb;
                    col *= 1.0 + tear_strength * 2.0;
                }
            }

            // --- 4. 噪点 + 噪点爆发 ---
            float noise = random(uv * TIME) * noise_intensity;
            col += noise;
            if (noise_burst > 0.001) {
                float burst = random(uv * (TIME + 1.7)) * noise_burst;
                col = mix(col, vec3(burst), noise_burst * 0.7);
            }

            // --- 5. 闪烁 ---
            float flicker = 1.0 + sin(TIME * flicker_speed) * flicker_intensity;
            col *= flicker;

            // --- 5b. Glitch 闪烁 ---
            if (glitch_intensity > 0.3) {
                float glitch_flash = hash_step(floor(TIME * 15.0));
                if (glitch_flash > (1.0 - glitch_intensity * 0.3)) {
                    col *= 1.0 + (glitch_flash - 0.5) * glitch_intensity * 0.8;
                }
            }

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
            float col_luma = dot(col, vec3(0.299, 0.587, 0.114));
            float bloom_mask = 1.0 - smoothstep(0.3, 0.7, col_luma);
            col += bloom * bloom_intensity * bloom_mask;

            // --- 8. 磷光色调 ---
            float luma = dot(col, vec3(0.299, 0.587, 0.114));
            float soft_luma = sqrt(clamp(luma, 0.0, 1.0));
            col += phosphor_color * soft_luma * phosphor_boost;
            col += col * soft_luma * glow_intensity * 0.5;

            // --- 9. 亮度和对比度 ---
            col = (col - 0.5) * contrast + 0.5;
            col *= brightness;

            // --- 9b. 开机辉光 ---
            if (boot_glow > 0.01) {
                col += phosphor_color * boot_glow * 0.3;
            }

            // --- 10. Tone mapping ---
            col = min(col, vec3(max_brightness * 2.0));
            col = col / (col + vec3(1.0));
            col *= tonemap_compensation;

            // --- 11. 最终钳制 ---
            col = clamp(col, 0.0, 1.0);

            COLOR = vec4(col, 1.0);
        }
    }
}