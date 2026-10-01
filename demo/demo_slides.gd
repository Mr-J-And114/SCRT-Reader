# ============================================================
# demo_slides.gd - 幻灯片数据 + 占位注册表 + 演示摄像头配置
# ============================================================
class_name DemoSlides
extends RefCounted

# ══════════════════════════════════════════
#  占位素材注册表
# ══════════════════════════════════════════
# 所有 PPT 配图占位。素材就绪后替换 demo/assets/ 下的文件。
const PLACEHOLDER_ASSETS: Dictionary = {
	"system_overview": {
		"path": "res://assets/system_overview.png",
		"description": "摄像头系统功能总览图",
		"slide": 2
	},
	"pom_principle": {
		"path": "res://assets/pom_principle.png",
		"description": "POM 视差映射原理示意图",
		"slide": 3
	},
	"problem_comparison": {
		"path": "res://assets/problem_comparison.png",
		"description": "逐像素深度图三大缺陷对比",
		"slide": 5
	},
	"three_sources": {
		"path": "res://assets/three_sources.png",
		"description": "三种深度来源示意图",
		"slide": 7
	},
	"room_preview": {
		"path": "res://assets/room_preview.jpg",
		"description": "规则几何房间场景预览",
		"slide": 11
	},
	"pool_preview": {
		"path": "res://assets/pool_preview.png",
		"description": "复杂泳池场景预览",
		"slide": 12
	},
	"compare_result": {
		"path": "res://assets/compare_result.png",
		"description": "Region vs Per-Pixel 深度对比",
		"slide": 13
	},
}

# ══════════════════════════════════════════
#  演示用摄像头配置
# ══════════════════════════════════════════
# cam_demo_room: test1 简单几何房间
#   深度图由 Depth Anything V2 生成
#   11 张 Mask PNG 按由远及近排列
#   ref_distance = 1.0 - (real_distance / 15.0)  线性映射
#   priority = mask 索引（越高越近，覆盖远处）
# cam_demo_pool: test2 复杂场景
#   深度图由 Depth Anything V2 生成
#   7 张 Mask PNG，max_distance = 30m
#   无限远 → ref_distance = 0.0
const DEMO_CAMERAS: Dictionary = {
	"camera_system": {
		"base_path": "res://data/cameras",
		"defaults": {
			"unlocked": true,
			"online": true,
			"viewport_size": [0.9, 0.7],
			"viewport_pos": [0.5, 0.5],
			"pan_speed": 0.02,
			"pan_bounds": [0.0, 0.0, 1.0, 1.0],
			"noise_intensity": 0.12,
			"scanline_intensity": 0.25,
			"vignette": 0.35,
			"signal_quality": 1.0,
			"timestamp_visible": false,
			"snow_intensity": 0.0,
			"light_mode": "none",
			"light_radius": 0.5,
			"light_falloff": 2.0,
			"use_parallax": true,
			"parallax_scale": 0.04,
			"parallax_layers": 8,
		},
		"cameras": {
			"cam_demo_room": {
				"name": "Demo: 简单几何房间",
				"location": "Test 1 — Mask 方式",
				"base_image": "room/base.jpg",
				"depth_map": "room/depth.png",
				"spotlight_image": "room/spotlight.jpg",
				"use_prerendered": true,
				"region_config": {
					"masks": [
						# 11 张 mask，由远及近
						# ref_distance = 1.0 - (real_distance / 15.0)
						{"id": "m0", "label": "15m", "image": "room/regions/mask_0.png", "ref_distance": 0.00, "real_distance": 15.0, "priority": 0},
						{"id": "m1", "label": "12m", "image": "room/regions/mask_1.png", "ref_distance": 0.20, "real_distance": 12.0, "priority": 1},
						{"id": "m2", "label": "9m",  "image": "room/regions/mask_2.png", "ref_distance": 0.40, "real_distance": 9.0,  "priority": 2},
						{"id": "m3", "label": "10m", "image": "room/regions/mask_3.png", "ref_distance": 0.33, "real_distance": 10.0, "priority": 3},
						{"id": "m4", "label": "5m",  "image": "room/regions/mask_4.png", "ref_distance": 0.67, "real_distance": 5.0,  "priority": 4},
						{"id": "m5", "label": "14m", "image": "room/regions/mask_5.png", "ref_distance": 0.07, "real_distance": 14.0, "priority": 5},
						{"id": "m6", "label": "10m", "image": "room/regions/mask_6.png", "ref_distance": 0.33, "real_distance": 10.0, "priority": 6},
						{"id": "m7", "label": "9m",  "image": "room/regions/mask_7.png", "ref_distance": 0.40, "real_distance": 9.0,  "priority": 7},
						{"id": "m8", "label": "3m",  "image": "room/regions/mask_8.png", "ref_distance": 0.80, "real_distance": 3.0,  "priority": 8},
						{"id": "m9", "label": "4m",  "image": "room/regions/mask_9.png", "ref_distance": 0.73, "real_distance": 4.0,  "priority": 9},
						{"id": "m10", "label": "2m", "image": "room/regions/mask_10.png", "ref_distance": 0.87, "real_distance": 2.0,  "priority": 10},
					],
					"global_default_distance": 0.3,
					"smooth_radius": 0.02,
					"use_raw_depth_fallback": true,
					"variation_scale": 0.3,
					"mask_feather_radius": 3.0,
				},
			},
		"cam_demo_pool": {
			"name": "Demo: 复杂场景 (Test 2)",
			"location": "Test 2 — Mask 方式",
			"base_image": "pool/base.png",
			"depth_map": "pool/depth.png",
			"spotlight_image": "pool/spotlight.png",
			"use_prerendered": true,
			"region_config": {
				"masks": [
					# 7 张 mask，由远及近
					# ref_distance = 1.0 - (real_distance / 30.0)
					# 无限远 → ref_distance = 0.0
					{"id": "p0", "label": "∞",   "image": "pool/regions/mask_0.png", "ref_distance": 0.00, "real_distance": -1.0,  "priority": 0},
					{"id": "p1", "label": "25m", "image": "pool/regions/mask_1.png", "ref_distance": 0.17, "real_distance": 25.0, "priority": 1},
					{"id": "p2", "label": "20m", "image": "pool/regions/mask_2.png", "ref_distance": 0.33, "real_distance": 20.0, "priority": 2},
					{"id": "p3", "label": "15m", "image": "pool/regions/mask_3.png", "ref_distance": 0.50, "real_distance": 15.0, "priority": 3},
					{"id": "p4", "label": "11m", "image": "pool/regions/mask_4.png", "ref_distance": 0.63, "real_distance": 11.0, "priority": 4},
					{"id": "p5", "label": "9m",  "image": "pool/regions/mask_5.png", "ref_distance": 0.70, "real_distance": 9.0,  "priority": 5},
					{"id": "p6", "label": "2m",  "image": "pool/regions/mask_6.png", "ref_distance": 0.93, "real_distance": 2.0,  "priority": 6},
				],
				"global_default_distance": 0.3,
				"smooth_radius": 0.02,
				"use_raw_depth_fallback": true,
				"variation_scale": 0.3,
				"mask_feather_radius": 3.0,
			},
		},
		},
	},
}

# ══════════════════════════════════════════
#  幻灯片数据（14 页）
# ══════════════════════════════════════════
static func get_slides() -> Array[Dictionary]:
	return [
		# ── Slide 1: 标题页 ──
		{
			"type": "title",
			"title": "深度图驱动的伪 3D 视差渲染",
			"subtitle": "从逐像素映射到区域优化",
			"members": "贾铭扬  金文辉        2026/7/15",
			"footer": "SCRT-Reader 摄像头系统技术展示",
		},
		# ── Slide 2: 深度图技术概述 ──
		{
			"type": "diagram",
			"title": "深度图与伪 3D 渲染",
			"body": "[b]什么是深度图[/b]\n" +
					"灰度图像，每像素存距离值\n" +
					"0 = 远, 1 = 近\n\n" +
					"[b]AI 单目深度估计[/b]\n" +
					"[color=#66CCFF]Depth Anything V2[/color]\n" +
					"从单张 2D 图推断深度\n\n" +
					"[b]核心应用[/b]\n" +
					"视差映射 (POM)\n" +
					"2D 底图 → 伪 3D 空间感\n\n" +
					"[b]技术栈[/b]\n" +
					"Godot 4.6 | GLSL Shader",
			"diagram": "system_overview",
		},
		# ── Slide 3: POM 原理 ──
		{
			"type": "diagram",
			"title": "POM 视差映射原理",
			"body": "[b]视差遮蔽映射[/b]\n\n" +
					"• 深度图存\"距离\"值\n" +
					"  (0=远, 1=近)\n" +
					"• 视角方向偏移 UV\n" +
					"• 近物偏移大, 远物偏移小\n\n" +
					"[color=#66CCFF]2D→伪3D空间感[/color]",
			"diagram": "pom_principle",
		},
		# ── Slide 4: POM 数学模型 ──
		{
			"type": "diagram",
			"title": "POM 数学模型",
			"body": "[b]步进采样公式[/b]\n" +
					"[math]layer_{depth} = 1.0 / N[/math] 每层深度间隔\n" +
					"[math]\\Delta_{uv} = view_{dir} \\times scale / N[/math] 每步UV偏移\n\n" +
					"[b]逐层比较[/b]\n" +
					"沿 view_dir 反向步进\n" +
					"每步: [math]current_{layer\\_depth} \\geq current_{depth}?[/math]\n" +
					"  是 → 可见表面，停止\n" +
					"  否 → 继续步进\n\n" +
					"[b]遮蔽插值修正[/b]\n" +
					"交点前后两 UV 间线性插值\n" +
					"[math]weight = \\frac{after_{depth}}{after_{depth} - before_{depth}}[/math]\n" +
					"[math]result = mix(current_{uv},\\ prev_{uv},\\ weight)[/math]",
			"diagram": "pom_stepping",
		},
		# ── Slide 5: 逐像素深度图的局限 ──
		{
			"type": "diagram",
			"title": "逐像素深度图的局限",
			"body": "[color=#FFAA66][b]① 空间结构错位[/b][/color]\n" +
					"灰度相近 → 视差相同\n" +
					"\"柱子粘在墙上\"\n\n" +
					"[color=#FFAA66][b]② 边缘撕裂[/b][/color]\n" +
					"深度梯度不连续\n" +
					"→ UV 跳变 → 撕裂\n\n" +
					"[color=#FFAA66][b]③ 绝对距离不可知[/b][/color]\n" +
					"AI 深度图仅有相对深度\n" +
					"无法区分 5m 与 15m",
			"diagram": "problem_comparison",
		},
		# ── Slide 6: 优化思路 ──
		{
			"type": "diagram",
			"title": "优化思路：区域划分",
			"body": "[b]核心思想[/b]\n" +
					"人工标注关键区域绝对距离\n" +
					"弥补 AI 深度图的局限\n\n" +
					"• [color=#66CCFF]PNG Mask[/color] — 灰度图定义轮廓\n" +
					"• 每个区域指定 ref_distance\n" +
					"• 优先级链叠层覆盖\n\n" +
					"[color=#99FF99]区域 = 绝对距离基准[/color]\n" +
					"[color=#99FF99]+ 原深度图局部变化[/color]",
			"diagram": "priority_chain",
		},
		# ── Slide 7: Mask 局部变化算法 ──
		{
			"type": "diagram",
			"title": "Mask 局部变化算法",
			"body": "[b]核心公式[/b]\n" +
					"[math]final = ref_{distance} + (raw - \\mu) \\times scale[/math]\n\n" +
					"[b]两遍算法[/b]\n" +
					"Pass 1: 计算 mask 区域\n" +
					"  原深度图均值 [math]\\mu[/math]\n" +
					"Pass 2: 写入 ref + 局部变化\n\n" +
					"[color=#66CCFF]mask 提供绝对距离[/color]\n" +
					"[color=#66CCFF]原深度图提供 3D 细节[/color]\n\n" +
					"[math]scale = 0[/math] → 退化为平坦模式",
			"diagram": "local_variation",
		},
		# ── Slide 8: 浮点深度管线 ──
		{
			"type": "diagram",
			"title": "浮点深度管线",
			"body": "[b]突破 0-255 限制[/b]\n" +
					"PackedByteArray (L8)\n" +
					"→ PackedFloat32Array (32-bit)\n\n" +
					"[b]图像格式[/b]\n" +
					"FORMAT_L8 → [color=#66CCFF]FORMAT_RF[/color]\n" +
					"值域 [math][0,1] \\to [0, 2.0][/math]\n\n" +
					"[b]Shader 适配[/b]\n" +
					"sampler2D 自动返回 float\n" +
					"POM 内部 [math]clamp [0,1][/math]\n" +
					"照明/激光不 clamp",
			"diagram": "float_pipeline",
			"code": "var depth_floats := PackedFloat32Array()\ndepth_floats.resize(total)\ndepth_floats.fill(default_val)\n# ... mask 两遍算法写入 ...\n# FORMAT_RF: 32-bit float per pixel\nregion_depth_image = Image.create_from_data(\n    img_w, img_h, false,\n    Image.FORMAT_RF,\n    depth_floats.to_byte_array())",
			"code_lang": "gdscript",
		},
		# ── Slide 9: 性能优化 ──
		{
			"type": "code",
			"title": "性能优化：浮点数组",
			"body": "[b]PackedFloat32Array 直接操作[/b]\n" +
					"深度用浮点数组，吸光/覆盖用字节数组\n" +
					"[color=#99FF99]避免 get_pixel/set_pixel 开销[/color]",
			"code": "# 旧方案：每像素 2 次函数调用\nfor y in range(h):\n    for x in range(w):\n        var px = mask_img.get_pixel(x, y)\n        if px.a > 0.1:\n            depth_img.set_pixel(x, y, color)\n\n# 新方案：直接操作浮点数组\nvar mask_bytes = mask_img.get_data()\nvar depth := PackedFloat32Array()\nfor y in range(h):\n    for x in range(w):\n        var idx = (y * w + x) * 4\n        if mask_bytes[idx + 3] > 25:\n            var variation = (raw[idx] - mean) * scale\n            depth[idx] = ref_dist + variation",
			"code_lang": "gdscript",
		},
		# ── Slide 10: Shader 实现 ──
		{
			"type": "code",
			"title": "Shader 实现：POM + 统一采样",
			"body": "[b]get_depth()[/b] — 统一采样，R 键切换\n" +
					"[b]parallax_mapping()[/b] — clamp [0,1] 防外推\n" +
					"照明/激光不 clamp，depth > 1 = 更远",
			"code": "float get_depth(vec2 uv) {\n    if (use_region_depth)\n        return texture(region_depth_texture, uv).r;\n    return texture(depth_texture, uv).r;\n}\n\nvec2 parallax_mapping(vec2 uv, vec2 view_dir) {\n    // POM 内部 clamp 防止 depth > 1 插值外推\n    float current_depth =\n        clamp(get_depth(current_uv), 0.0, 1.0);\n    for (int i = 0; i < parallax_layers; i++) {\n        if (current_layer_depth >= current_depth)\n            break;\n        current_uv -= delta_uv;\n        current_depth =\n            clamp(get_depth(current_uv), 0.0, 1.0);\n    }\n    // 照明: depth 不 clamp, > 1 = 更远\n    float depth = get_depth(base_uv);\n}",
			"code_lang": "glsl",
		},
		# ── Slide 11: 演示房间 ──
		{
			"type": "camera_link",
			"title": "演示：简单几何房间 (Test 1)",
			"body": "[b]Mask 方式 — 11 张区域掩码[/b]\n" +
					"深度图: [color=#66CCFF]Depth Anything V2[/color] 生成\n\n" +
					"由远及近: 15m → 2m\n" +
					"每个 mask 区域独立估算深度\n\n" +
					"[color=#66CCFF]点击下方按钮查看效果[/color]\n" +
					"鼠标拖动平移 | F 手电照明\n" +
					"R 切换深度 | L 激光",
			"image": "room_preview",
			"image_x": 680, "image_y": 200, "image_w": 320, "image_h": 280,
			"camera": "cam_demo_room",
		},
		# ── Slide 12: 演示场景2 ──
		{
			"type": "camera_link",
			"title": "演示：复杂场景 (Test 2)",
			"body": "[b]Mask 方式 — 7 张区域掩码[/b]\n" +
					"深度图: [color=#66CCFF]Depth Anything V2[/color] 生成\n\n" +
					"复杂场景深度估算验证\n\n" +
					"[color=#66CCFF]点击下方按钮查看效果[/color]\n" +
					"鼠标拖动平移 | F 手电照明\n" +
					"R 切换深度 | L 激光",
			"image": "pool_preview",
			"image_x": 400, "image_y": 200, "image_w": 450, "image_h": 300,
			"camera": "cam_demo_pool",
		},
		# ── Slide 13: 总结与展望 ──
		{
			"type": "diagram",
			"title": "总结与展望",
			"body": "[b]成果[/b]\n" +
					"• 深度图伪 3D 视差渲染\n" +
					"• Mask 局部变化算法\n" +
					"• 浮点深度管线 (FORMAT_RF)\n" +
					"• Mask 边界羽化 + 软过渡\n\n" +
					"[color=#FFAA66][b]区域划分的局限[/b][/color]\n" +
					"• mask 需人工绘制，耗时主观\n" +
					"• 复杂场景边界难精确标注\n" +
					"• scale 为全局参数，非自适应\n\n" +
					"[b]未来方向[/b]\n" +
					"• AI 自动区域分割\n" +
					"• per-region variation_scale\n" +
					"• 可视化编辑器",
			"diagram": "compare_result",
		},
		# ── Slide 14: 谢谢 ──
		{
			"type": "title",
			"title": "谢谢",
			"subtitle": "Q & A",
			"footer": "",
		},
	]

# ══════════════════════════════════════════
#  占位素材加载
# ══════════════════════════════════════════
static func load_placeholder(asset_id: String) -> Texture2D:
	if not PLACEHOLDER_ASSETS.has(asset_id):
		return null
	var info: Dictionary = PLACEHOLDER_ASSETS[asset_id]
	var path: String = info["path"]
	if ResourceLoader.exists(path):
		var tex = ResourceLoader.load(path)
		if tex is Texture2D:
			return tex
	# 占位缺失
	print("[Demo] 占位素材缺失: %s (slide %d) — %s" % [asset_id, info.get("slide", 0), info.get("description", "")])
	return null

static func get_placeholder_description(asset_id: String) -> String:
	if PLACEHOLDER_ASSETS.has(asset_id):
		return PLACEHOLDER_ASSETS[asset_id].get("description", "")
	return ""
