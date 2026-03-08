// ============================================================
// camera_effect.gdshader - 监控摄像头画面后处理
// 效果管线：深度采样 → 照明投影 → 噪点 → 扫描线 → 雪花 → 暗角
// ============================================================
shader_type canvas_item;

// ── 基础画面 ──
uniform sampler2D base_texture : filter_linear, repeat_disable;
uniform sampler2D depth_texture : filter_linear, repeat_disable;
uniform sampler2D light_texture : filter_linear, repeat_disable;

// ── 异常叠加 ──
uniform sampler2D anomaly_texture : filter_linear, repeat_disable;
uniform sampler2D anomaly_depth : filter_linear, repeat_disable;
uniform sampler2D anomaly_light : filter_linear, repeat_disable;
uniform float anomaly_blend : hint_range(0.0, 1.0) = 0.0;

// ── 镜头裁剪（归一化坐标）──
uniform vec4 viewport_rect = vec4(0.35, 0.35, 0.3, 0.3); // x, y, w, h

// ── 照明参数 ──
uniform int light_mode = 0;           // 0=none, 1=spotlight, 2=nightvision, 3=infrared
uniform vec2 light_center = vec2(0.5, 0.5);
uniform float light_radius = 0.35;
uniform float light_falloff = 2.0;
uniform float light_intensity = 1.0;
uniform float depth_weight = 0.3;     // 深度对照明衰减的影响权重（降低以减少过度影响）

// ── 视差贴图参数 ──
uniform bool use_parallax = false;
uniform float parallax_scale = 0.05;  // 视差强度
uniform int parallax_layers = 8;      // 采样层数
uniform vec2 parallax_view_offset = vec2(0.0, 0.0); // 镜头朝向偏移（viewport_pos - 0.5），消除中央畸变

// ── 噪点 & 效果 ──
uniform float noise_intensity = 0.15;
uniform float scanline_intensity = 0.3;
uniform float snow_intensity = 0.0;
uniform float signal_quality = 1.0;
uniform float vignette_strength = 0.4;
uniform float time_val = 0.0;

// ── 照明叠加（Spotlight 预渲染叠加模式）──
uniform sampler2D spotlight_overlay : filter_linear, repeat_disable;
uniform bool use_spotlight_overlay = false;

// ── 异常叠加模式 ──
uniform bool anomaly_overlay_mode = false; // false=图像替换, true=透明叠加（使用 anomaly_texture.a）

// ── 色调参数 ──
uniform vec3 tint_color = vec3(0.7, 0.8, 0.7);  // 监控画面微绿色调

// ============================================================
// 工具函数
// ============================================================

// 伪随机哈希
float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(443.897, 441.423, 437.195));
	p3 += dot(p3, p3.yzx + 19.19);
	return fract((p3.x + p3.y) * p3.z);
}

// 值噪声
float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);

	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));

	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// ============================================================
// 视差遮蔽映射（Parallax Occlusion Mapping）
// ============================================================
vec2 parallax_mapping(vec2 uv, vec2 view_dir) {
	if (!use_parallax) {
		return uv;
	}

	// 采样深度
	float height = texture(depth_texture, uv).r;

	// 计算偏移
	float layer_depth = 1.0 / float(parallax_layers);
	float current_layer_depth = 0.0;
	vec2 delta_uv = view_dir * parallax_scale / float(parallax_layers);
	vec2 current_uv = uv;
	float current_depth = texture(depth_texture, current_uv).r;

	// 陡峭视差映射
	for (int i = 0; i < parallax_layers; i++) {
		if (current_layer_depth >= current_depth) {
			break;
		}
		current_uv -= delta_uv;
		current_depth = texture(depth_texture, current_uv).r;
		current_layer_depth += layer_depth;
	}

	// 视差遮蔽映射（插值优化）
	vec2 prev_uv = current_uv + delta_uv;
	float after_depth = current_depth - current_layer_depth;
	float before_depth = texture(depth_texture, prev_uv).r - current_layer_depth + layer_depth;
	float weight = after_depth / (after_depth - before_depth);

	return mix(current_uv, prev_uv, weight);
}

// ============================================================
// 主片段着色器
// ============================================================
void fragment() {
	// ── 1. 将屏幕 UV 映射到底图 UV ──
	vec2 base_uv = viewport_rect.xy + UV * viewport_rect.zw;

	// ── 2. 视差贴图（模拟 3D 深度）──
	if (use_parallax) {
		// 使用镜头朝向偏移作为视角方向，避免以屏幕像素为基准导致的中央畸变
		base_uv = parallax_mapping(base_uv, parallax_view_offset);
	}

	// ── 3. 信号干扰（水平偏移）──
	float distortion = (1.0 - signal_quality) * 0.02;
	float h_offset = sin(base_uv.y * 50.0 + time_val * 3.0) * distortion;
	h_offset += sin(base_uv.y * 130.0 + time_val * 7.0) * distortion * 0.5;
	base_uv.x += h_offset;

	// 限制 UV 在有效范围内
	base_uv = clamp(base_uv, vec2(0.0), vec2(1.0));

	// ── 4. 采样底图和深度 ──
	vec4 base_col = texture(base_texture, base_uv);
	float depth = texture(depth_texture, base_uv).r;

	// ── 5. 异常混合 ──
	if (anomaly_blend > 0.01) {
		vec4 anom_col = texture(anomaly_texture, base_uv);
		if (anomaly_overlay_mode) {
			// 透明叠加：使用异常图的 alpha 通道作为蒙版叠加在正常画面之上
			base_col.rgb = mix(base_col.rgb, anom_col.rgb, anom_col.a * anomaly_blend);
		} else {
			// 图像替换：渐变替换整张底图（原有行为）
			float anom_depth = texture(anomaly_depth, base_uv).r;
			base_col = mix(base_col, anom_col, anomaly_blend);
			depth = mix(depth, anom_depth, anomaly_blend);
		}
	}

	// ── 6. 照明计算 ──
	vec4 final_color = base_col;

	if (light_mode > 0) {
		// 计算到照明中心的距离（考虑深度）
		float uv_dist = distance(UV, light_center);

		// ★ 改进深度影响：深度值越大（越远），照明衰减越快
		// 使用非线性映射让深度影响更自然
		float depth_factor = 1.0 + (depth * depth) * depth_weight * 2.0;
		float effective_dist = uv_dist * depth_factor;

		// 照明蒙版（平滑衰减）
		float mask = 1.0 - smoothstep(light_radius * 0.3, light_radius, effective_dist);
		mask = pow(mask, light_falloff) * light_intensity;

		if (light_mode == 1) {
			// ── Spotlight：灯光照亮圆形区域，圈外极暗 ──
			if (use_spotlight_overlay) {
				// 预渲染叠加模式：范围内以原图亮度直接替换，仅在边缘做窄过渡
				vec3 overlay_col = texture(spotlight_overlay, base_uv).rgb;
				// range_mask：范围内保持 1.0（不降低亮度），仅最外 15% 做软边过渡
				float range_mask = 1.0 - smoothstep(light_radius * 0.85, light_radius, effective_dist);
				final_color.rgb = mix(base_col.rgb * 0.08, overlay_col, range_mask);
			} else {
				// shader 计算模式：按亮度蒙版调整原底图
				float brightness = mix(0.08, 1.2, mask);
				final_color.rgb = base_col.rgb * brightness;
			}
		} else if (light_mode == 2) {
			// ── Nightvision：全图绿色 + 增强亮度 ──
			float luma = dot(base_col.rgb, vec3(0.299, 0.587, 0.114));

			// 距离衰减：远处可见度降低
			float visibility = 1.0 - smoothstep(light_radius * 0.8, light_radius * 1.5, effective_dist);
			luma *= (0.3 + 0.7 * visibility);

			// 增强亮度 + 噪点
			luma = pow(luma, 0.6) * 1.5;
			float nv_noise = hash(UV * 500.0 + time_val * 10.0) * 0.08;
			luma += nv_noise;

			final_color.rgb = vec3(luma * 0.2, luma * 1.0, luma * 0.15);
		} else if (light_mode == 3) {
			// ── Infrared：禁用自动生成，必须使用预渲染图 ──
			// 如果到这里说明没有预渲染图，显示错误提示
			final_color.rgb = vec3(1.0, 0.0, 1.0); // 洋红色错误提示
		}
	} else {
		// 无照明模式：底图变暗模拟黑暗环境
		final_color.rgb = base_col.rgb * 0.6;
	}

	// ── 6. 色调调整（轻微绿色监控感）──
	final_color.rgb *= tint_color;

	// ── 7. 噪点 ──
	float noise = hash(UV * 1000.0 + time_val * 5.0) * 2.0 - 1.0;
	float effective_noise = noise_intensity + (1.0 - signal_quality) * 0.3;
	final_color.rgb += vec3(noise * effective_noise);

	// ── 8. 扫描线 ──
	float scanline = sin(UV.y * 800.0 + time_val * 2.0) * 0.5 + 0.5;
	scanline = pow(scanline, 2.0) * scanline_intensity;
	final_color.rgb -= vec3(scanline * 0.15);

	// ── 9. 雪花点（大块随机）──
	if (snow_intensity > 0.01) {
		float snow_block = hash(floor(UV * vec2(80.0, 60.0)) + floor(time_val * 8.0));
		float snow_mask = step(1.0 - snow_intensity, snow_block);
		float snow_val = hash(floor(UV * vec2(160.0, 120.0)) + floor(time_val * 15.0));
		final_color.rgb = mix(final_color.rgb, vec3(snow_val), snow_mask * snow_intensity);
	}

	// ── 10. 信号质量很差时的色带效果 ──
	if (signal_quality < 0.5) {
		float band = step(0.98, sin(UV.y * 3.0 + time_val * 0.5));
		float band_strength = (0.5 - signal_quality) * 2.0;
		final_color.rgb = mix(final_color.rgb, vec3(0.0), band * band_strength * 0.5);
	}

	// ── 11. 暗角 ──
	float vig = distance(UV, vec2(0.5));
	vig = smoothstep(0.3, 0.85, vig);
	final_color.rgb *= 1.0 - vig * vignette_strength;

	// ── 12. 色彩压缩（模拟低质量摄像头）──
	final_color.rgb = floor(final_color.rgb * 32.0) / 32.0;

	// ── 13. 最终输出 ──
	final_color.a = 1.0;
	COLOR = final_color;
}
