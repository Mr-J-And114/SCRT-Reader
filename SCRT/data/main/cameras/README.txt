════════════════════════════════════════════════════════════════
  摄像头系统完全指南 - 从零开始设置你的第一个摄像头
════════════════════════════════════════════════════════════════

本指南面向完全不懂代码的作者，手把手教你如何设置一个监控摄像头。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  第一步：准备图片素材
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### 必需的图片（至少需要这个）

1. **基础图（base_image）** - 必需
   - 这是摄像头看到的正常画面
   - 文件名示例：my_camera_base.jpg
   - 推荐尺寸：1920x1080 或更高
   - 格式：JPG 或 PNG

### 可选的图片（让摄像头更真实）

2. **深度图（depth_map）** - 强烈推荐
   - 用于模拟 3D 空间感
   - 白色 = 近景（前面的物体）
   - 黑色 = 远景（后面的墙壁）
   - 灰色 = 中景
   - 文件名示例：my_camera_depth.jpg
   - 制作方法：用 PS/GIMP 把基础图转成黑白，手动调整深浅

3. **聚光灯图（spotlight_image）** - 可选
   - 打开聚光灯时显示的画面
   - 中间亮，四周暗
   - 文件名示例：my_camera_light.jpg
   - 制作方法：复制基础图，用渐变工具从中心向外变暗

4. **夜视图（nightvision_image）** - 可选
   - 打开夜视仪时显示的画面
   - 绿色调，有噪点
   - 文件名示例：my_camera_nvg.jpg
   - 制作方法：基础图 → 去色 → 调成绿色 → 加噪点

5. **红外图（infrared_image）** - 可选
   - 打开红外热成像时显示的画面
   - 彩色热力图效果（蓝→紫→红→黄）
   - 文件名示例：my_camera_heat.jpg
   - 制作方法：基础图 → 应用渐变映射（冷色到暖色）

### 图片放在哪里？

把所有图片放到这个文件夹：
```
data/main/cameras/
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  第二步：编辑配置文件
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

打开文件：data/main/manifest.json

找到 "cameras" 这一段，添加你的摄像头：

### 最简单的配置（只有基础图）

```json
"cam_my_camera": {
  "name": "我的摄像头",
  "location": "某个地方",
  "unlocked": true,
  "base_image": "my_camera_base.jpg"
}
```

就这么简单！保存后进游戏输入 `camera view 1` 就能看到。

### 完整配置（所有功能）

```json
"cam_my_camera": {
  "name": "我的摄像头",
  "location": "某个地方",
  "unlocked": true,

  // ── 图片文件 ──
  "base_image": "my_camera_base.jpg",
  "depth_map": "my_camera_depth.jpg",
  "spotlight_image": "my_camera_light.jpg",
  "nightvision_image": "my_camera_nvg.jpg",
  "infrared_image": "my_camera_heat.jpg",

  // ── 使用预制图片（推荐新手设为 true）──
  "use_prerendered": true,

  // ── 3D 视差效果（需要深度图）──
  "use_parallax": true,
  "parallax_scale": 0.05,
  "parallax_layers": 8,

  // ── 摄像头转动方式 ──
  "rotation_enabled": true,
  "rotation_center": [0.5, 0.5],
  "rotation_radius": 0.15,
  "rotation_angle_range": 45.0,

  // ── 初始照明模式 ──
  "light_mode": "none"
}
```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  第三步：理解每个参数
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### 基础信息

**name**（必需）
- 摄像头的显示名称
- 例如："走廊监控"、"大门摄像头"

**location**（可选）
- 摄像头的位置描述
- 例如："1F 东翼"、"地下室入口"

**unlocked**（必需）
- true = 游戏开始就能看
- false = 需要通过剧情解锁

### 图片文件

**base_image**（必需）
- 正常画面的图片文件名
- 必须放在 data/main/cameras/ 文件夹里

**depth_map**（强烈推荐）
- 深度图文件名
- 用于 3D 效果和聚光灯
- 没有的话某些功能会不可用

**spotlight_image**（可选）
- 聚光灯模式的预制图
- 没有的话会用 shader 自动生成（需要深度图）

**nightvision_image**（可选）
- 夜视模式的预制图
- 没有的话会用 shader 自动生成（需要深度图）

**infrared_image**（可选）
- 红外模式的预制图
- ⚠️ 这个必须提供，系统不会自动生成

### 预制图片开关

**use_prerendered**
- true = 使用你准备的图片（推荐新手）
- false = 使用 shader 自动生成（需要深度图）

**什么时候用 true？**
- 你不懂技术，只会 PS
- 你想要精确控制效果
- 你有现成的图片

**什么时候用 false？**
- 你懂 shader 编程
- 你想要动态效果
- 你只有深度图，没时间做其他图

### 3D 视差效果

**use_parallax**
- true = 启用 3D 视差效果
- false = 关闭（画面是平的）
- ⚠️ 需要深度图才能工作

**parallax_scale**
- 视差强度，数值越大效果越明显
- 推荐值：0.03 - 0.08
- 太大会失真，太小看不出效果

**parallax_layers**
- 视差采样层数，越多越精细但越卡
- 推荐值：8 - 16
- 低端电脑用 4，高端电脑用 16

### 摄像头转动方式

**rotation_enabled**
- true = 摄像头围绕中心旋转（真实）
- false = 摄像头直接平移（不真实）

**rotation_center**
- 旋转中心点，格式：[X, Y]
- [0.5, 0.5] = 画面正中心
- [0.3, 0.4] = 偏左上

**rotation_radius**
- 旋转半径，数值越大转动范围越大
- 推荐值：0.1 - 0.2
- 模拟摄像头臂的长度

**rotation_angle_range**
- 左右转动的最大角度（度数）
- 推荐值：30 - 60
- 真实摄像头一般是 45 度

### 照明模式

**light_mode**
- "none" = 无照明（默认）
- "spotlight" = 聚光灯
- "nightvision" = 夜视仪
- "infrared" = 红外热成像

游戏中按 F 键可以切换模式。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  第四步：常见问题解答
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### Q: 我只有一张图片，能用吗？
A: 能！只需要 base_image 就够了。其他功能会被禁用。

### Q: 深度图怎么做？
A:
1. 用 PS/GIMP 打开基础图
2. 去色（变成黑白）
3. 用画笔/橡皮擦调整：
   - 前景物体涂白
   - 背景墙壁涂黑
   - 中间物体涂灰
4. 保存为 JPG

### Q: 我不会做夜视图/红外图怎么办？
A:
- 设置 use_prerendered: false
- 提供深度图
- 系统会自动生成（除了红外）

### Q: 为什么红外模式不能自动生成？
A: 因为热力图需要知道哪里热哪里冷，深度图无法提供这个信息。
   你必须手动制作红外图。

### Q: 视差效果不明显怎么办？
A:
1. 检查深度图对比度是否足够
2. 增大 parallax_scale（试试 0.08）
3. 增加 parallax_layers（试试 12）

### Q: 摄像头转动太快/太慢？
A: 这个在代码里控制，不在配置文件里。
   如果需要调整，找 pan_speed 参数。

### Q: 可以添加多个摄像头吗？
A: 可以！在 "cameras" 里继续添加：

```json
"cameras": {
  "cam_1": { ... },
  "cam_2": { ... },
  "cam_3": { ... }
}
```

### Q: 摄像头 ID（cam_1）有什么要求？
A:
- 必须唯一
- 只能用英文、数字、下划线
- 不能有空格或特殊符号
- 推荐格式：cam_location_number

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  第五步：推荐配置方案
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### 方案 A：极简配置（新手友好）

只需要一张图片！

```json
"cam_simple": {
  "name": "简单摄像头",
  "unlocked": true,
  "base_image": "my_image.jpg"
}
```

**优点：** 超级简单，5 分钟搞定
**缺点：** 没有特殊效果

---

### 方案 B：标准配置（推荐）

需要：基础图 + 深度图

```json
"cam_standard": {
  "name": "标准摄像头",
  "unlocked": true,
  "base_image": "base.jpg",
  "depth_map": "depth.jpg",
  "use_prerendered": false,
  "use_parallax": true,
  "rotation_enabled": true
}
```

**优点：** 有 3D 效果，真实感强
**缺点：** 需要制作深度图

---

### 方案 C：完美配置（最佳效果）

需要：所有图片

```json
"cam_perfect": {
  "name": "完美摄像头",
  "unlocked": true,
  "base_image": "base.jpg",
  "depth_map": "depth.jpg",
  "spotlight_image": "light.jpg",
  "nightvision_image": "nvg.jpg",
  "infrared_image": "heat.jpg",
  "use_prerendered": true,
  "use_parallax": true,
  "parallax_scale": 0.06,
  "rotation_enabled": true,
  "rotation_angle_range": 50.0
}
```

**优点：** 所有功能，效果最好
**缺点：** 需要准备很多图片

---

### 方案 D：混合配置（灵活）

部分用预制图，部分用自动生成

```json
"cam_hybrid": {
  "name": "混合摄像头",
  "unlocked": true,
  "base_image": "base.jpg",
  "depth_map": "depth.jpg",
  "infrared_image": "heat.jpg",
  "use_prerendered": true,
  "use_parallax": true
}
```

**说明：**
- Spotlight/Nightvision 用 shader 自动生成
- Infrared 用预制图
- 兼顾效率和效果

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  第六步：测试你的摄像头
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. **保存配置文件**
   - 确保 manifest.json 没有语法错误
   - 注意逗号、引号、括号要配对

2. **启动游戏**
   - 登录账号

3. **查看摄像头列表**
   ```
   camera list
   ```
   应该能看到你的摄像头

4. **打开摄像头**
   ```
   camera view 1
   ```
   或者
   ```
   camera view cam_my_camera
   ```

5. **测试功能**
   - ←→↑↓ 键：转动摄像头
   - F 键：切换照明模式
   - TAB 键：切换到下一个摄像头
   - Q/ESC 键：退出

6. **检查效果**
   - 转动时有没有 3D 感？（需要深度图 + 视差）
   - 转动是旋转还是平移？（rotation_enabled）
   - 照明模式能切换吗？（需要对应图片）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  第七步：进阶技巧
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

### 制作高质量深度图

1. **使用 AI 工具**
   - 用 Depth Anything 等 AI 工具自动生成
   - 比手动制作更精确

2. **手动调整**
   - AI 生成后用 PS 微调
   - 重点调整前景和背景的对比度

3. **测试迭代**
   - 在游戏里看效果
   - 不满意就回去调整深度图
   - 多试几次就能掌握

### 优化性能

如果游戏卡顿：

1. **降低视差层数**
   ```json
   "parallax_layers": 4
   ```

2. **使用预制图**
   ```json
   "use_prerendered": true
   ```

3. **降低图片分辨率**
   - 1920x1080 → 1280x720

### 创意应用

1. **损坏的摄像头**
   ```json
   "signal_quality": 0.3,
   "snow_intensity": 0.8
   ```

2. **老旧摄像头**
   ```json
   "noise_intensity": 0.3,
   "scanline_intensity": 0.5
   ```

3. **高清摄像头**
   ```json
   "noise_intensity": 0.05,
   "signal_quality": 1.0
   ```

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  附录：完整参数列表
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

```json
{
  // ── 基础信息 ──
  "name": "摄像头名称",
  "location": "位置描述",
  "unlocked": true,
  "online": true,

  // ── 图片文件 ──
  "base_image": "文件名.jpg",
  "depth_map": "文件名.jpg",
  "spotlight_image": "文件名.jpg",
  "nightvision_image": "文件名.jpg",
  "infrared_image": "文件名.jpg",

  // ── 预制图片开关 ──
  "use_prerendered": true,

  // ── 视差效果 ──
  "use_parallax": true,
  "parallax_scale": 0.05,
  "parallax_layers": 8,

  // ── 摄像头转动 ──
  "rotation_enabled": true,
  "rotation_center": [0.5, 0.5],
  "rotation_radius": 0.15,
  "rotation_angle_range": 45.0,

  // ── 镜头参数 ──
  "viewport_size": [0.3, 0.3],
  "viewport_pos": [0.5, 0.5],
  "pan_speed": 0.008,
  "pan_bounds": [0.0, 0.0, 1.0, 1.0],

  // ── 照明 ──
  "light_mode": "none",
  "light_radius": 0.35,
  "light_falloff": 2.0,

  // ── 画面效果 ──
  "noise_intensity": 0.15,
  "scanline_intensity": 0.3,
  "vignette": 0.4,
  "signal_quality": 1.0,
  "snow_intensity": 0.0,
  "timestamp_visible": true
}
```

════════════════════════════════════════════════════════════════
  需要帮助？
════════════════════════════════════════════════════════════════

如果遇到问题：
1. 检查图片文件名是否正确
2. 检查 JSON 语法是否有错
3. 查看游戏控制台的错误信息
4. 参考 data/main/cameras/ 里的示例配置

祝你创作顺利！🎥
════════════════════════════════════════════════════════════════
