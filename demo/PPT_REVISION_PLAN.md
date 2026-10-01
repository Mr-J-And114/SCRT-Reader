# PPT 修订规划大纲

> 生成日期：2026/7/15
> 用途：指导 demo 项目 14 页 PPT 的内容修改 + 演讲稿撰写参考

## 主题变更

- **旧主题**：Region-Based Depth（区域划分为核心）
- **新主题**：深度图驱动的伪 3D 视差渲染（深度图技术为核心，区域划分为优化手段）

## 成员信息

- 贾铭扬、金文辉
- 展示日期：2026/7/15

---

## 逐页修改方案（14 页，页数不变）

### Slide 1 — 标题页
- **旧**：标题 "Region-Based Depth" + 副标题 "基于区域划分的伪 3D 深度增强"
- **新**：
  - 标题："深度图驱动的伪 3D 视差渲染"
  - 副标题："从逐像素映射到区域优化"
  - 成员行："贾铭扬  金文辉    2026/7/15"
  - footer："SCRT-Reader 摄像头系统技术展示"
- **技术**：`_render_title_slide()` 新增成员 Label 渲染

### Slide 2 — 深度图技术概述
- **旧**：摄像头系统概述（偏向系统功能介绍）
- **新**：深度图技术概述
  - 什么是深度图（灰度图 = 距离值，0=远 1=近）
  - AI 单目深度估计：Depth Anything V2
  - 深度图→伪 3D 的核心应用：视差映射
  - 技术栈：Godot 4.6 + GLSL Shader
- **图表**：`_draw_system_overview()` 重绘为"深度图→伪3D管线"概念图

### Slide 3 — POM 视差映射原理（不改）
- 视差遮蔽映射核心原理
- 深度图存距离值 → 视角偏移 UV → 近物偏移大、远物偏移小
- **图表**：`_draw_pom_principle()` 保持不变

### Slide 4 — POM 数学模型（不改）
- 步进采样公式
- 逐层比较逻辑
- 遮蔽插值修正
- **图表**：`_draw_pom_stepping()` 保持不变

### Slide 5 — 逐像素深度图的局限
- **旧**：三大缺陷（批判语气）
- **新**：客观分析纯逐像素方法的自然局限
  - ① 空间结构错位：灰度相近→视差相同，"柱子粘在墙上"
  - ② 边缘撕裂：深度梯度不连续→UV 跳变
  - ③ 绝对距离不可知：AI 深度图只有相对深度，无真实距离
- **图表**：`_draw_problem_comparison()` 保持不变

### Slide 6 — 优化思路：区域划分
- **旧**：三路混合深度方案
- **新**：区域划分作为优化手段（非唯一方案）
  - 核心思想：人工标注关键区域的绝对距离，弥补 AI 深度图的局限
  - Mask PNG：灰度/透明图定义复杂轮廓
  - 优先级链：layer > mask > polygon > raw fallback
- **图表**：`_draw_priority_chain()` 保留或微调

### Slide 7 — Mask 局部变化算法（新算法）
- **旧**：三种深度源详解
- **新**：Mask 局部变化算法
  - 公式：`final_depth = ref_distance + (raw_depth - mask_mean_raw) × variation_scale`
  - 两遍算法：Pass 1 计算 mask 区域原深度均值，Pass 2 写入 ref + 局部变化
  - 效果：mask 提供绝对距离基准，保留原深度图的局部 3D 结构变化
  - 退化兼容：variation_scale=0 → 平坦模式
- **图表**：`_draw_three_sources()` → 重绘为算法公式/流程图

### Slide 8 — 浮点深度管线
- **旧**：CPU 合成管线（字节数组）
- **新**：浮点深度管线
  - PackedByteArray (L8, 0-255) → PackedFloat32Array (32-bit float)
  - 图像格式：Image.FORMAT_RF（32-bit float per pixel）
  - 值域突破 [0,1] → [0, 2.0]
  - Shader 端 sampler2D 自动返回 float，无需改采样代码
  - POM 内部 clamp [0,1]，照明/激光不 clamp（depth > 1 = 更远）
- **图表**：`_draw_pipeline()` 重绘为浮点管线流程
- **代码**：更新为浮点版本

### Slide 9 — 性能优化
- **旧**：字节数组优化
- **新**：性能优化
  - 从 PackedByteArray 到 PackedFloat32Array
  - 对比 get_pixel/set_pixel vs 直接数组操作
  - 吸光/覆盖掩码仍用 PackedByteArray（L8 足够）
- **代码**：更新为浮点版本对比

### Slide 10 — Shader 实现
- **旧**：POM + 统一深度采样
- **新**：Shader 实现
  - get_depth() 统一采样入口，R 键运行时切换
  - parallax_mapping() 内 clamp [0,1]（防止 depth > 1 插值外推）
  - 照明/激光不 clamp（depth > 1 正确表示更远）
- **代码**：更新加入 clamp

### Slide 11 — Demo Test 1（不改）
- 简单几何房间，11 张 mask，鼠标拖动/手电/深度/激光

### Slide 12 — Demo Test 2（不改）
- 复杂场景，7 张 mask，相同管线

### Slide 13 — 总结与展望
- **旧**：成果 + 未来方向
- **新**：
  - 成果：深度图伪 3D 视差技术 + 区域优化 + 浮点管线
  - **区域划分的现存缺陷**：
    - mask 需要人工绘制，耗时且主观
    - 复杂场景边界难以精确标注
    - variation_scale 为全局参数，不同区域可能需要不同强度
    - mean 计算依赖 mask 覆盖区域内有有效深度数据
  - 未来方向：AI 自动区域分割、动态层、可视化编辑器、per-region variation_scale
- **图表**：`_draw_compare_result()` 保留或微调

### Slide 14 — 谢谢（不改）

---

## 需要修改的文件

| 文件 | 改动 |
|---|---|
| `demo_slides.gd` | 所有 14 页的 slide data（title/subtitle/footer/members/body/diagram/code） |
| `demo_camera.gd` | `_render_title_slide()` 新增成员渲染；`_draw_system_overview()` 重绘；`_draw_three_sources()` 重绘为算法图；`_draw_pipeline()` 重绘；`_draw_compare_result()` 微调 |

## 不改动的图表函数

- `_draw_pom_principle()` — POM 原理图
- `_draw_pom_stepping()` — POM 步进图
- `_draw_problem_comparison()` — 局限性图
- `_draw_priority_chain()` — 优先级链（可能微调文字）
- `_draw_placeholder()` — 占位图
