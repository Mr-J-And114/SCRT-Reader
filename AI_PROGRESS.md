# AI Session Progress

> **给 AI 的第一条指令**：每次接手任务前先通读本文件，了解当前会话上下文、未完成工作和关键决策。
> 每次完成任务后更新相关章节。
> 本文件最后更新：2026-07-15

---

## 一、项目总览

**SCRT-Reader** — SCP 主题复古 CRT 终端模拟器 / 互动小说阅读器
- 引擎：Godot 4.7.1（GL Compatibility）
- 语言：GDScript，全类型标注，约 44,000 行
- 架构：纯 2D UI，单场景 (`main.tscn`)，无 Autoload

**当前主要工作方向**：LaTeX 公式渲染系统已完成并集成，引擎已升级至 4.7.1
**展示目标**：用于向老师演示"底图+深度图→伪3D"技术（3D视频/AI/IoT方向）

---

## 二、LaTeX 公式渲染系统（2026-07-15 完成）

### 成果概述
在 SCRT 和 demo PPT 项目中实现了完整的 LaTeX 公式渲染能力，支持在 CRTML 文本和 PPT slide 中使用 `[math]...[/math]` 标记嵌入数学公式。

### 新增文件
- `SCRT/scripts/latex_renderer.gd`（1720 行）— LaTeX 渲染引擎，`class_name LatexRenderer extends RefCounted`
- `demo/scripts/latex_renderer.gd` — 开发原型（与 SCRT 同步）

### 架构
```
_Tokenizer (词法) → _Parser (递归下降 AST) → _Layout (测量+定位) → _LatexCanvas (SubViewport 绘制) → ImageTexture
```

### 支持的 LaTeX 命令
- 分数 `\frac`、根号 `\sqrt[n]`（自绘 V 形）、上下标 `^_`、大运算符 `\sum\int\prod\oint`（含 `\limits`）
- 可缩放定界符 `\left(\right)`（曲线/折线自绘）、环境 `matrix/pmatrix/bmatrix/cases/aligned`
- 100+ 希腊字母/数学符号/箭头、装饰命令 `\hat\vec\overline\dot\tilde`
- 字体切换 `\mathbf\mathit\mathbb`、颜色 `\color`、间距 `\quad\,`
- 静态缓存 `latex|size|color → ImageTexture`

### 集成点
- **SCRT CRTML**：`crtml_parser.gd._process_inline()` 第 12 步 `_parse_math()`，复用 `_inline_image_cache` 占位符机制
- **Demo PPT**：`demo_camera.gd` 异步预渲染所有公式 → `_set_body_text_with_math()` 替换 `_body_text.text`
- **初始化**：`main.gd._ready()` 中创建 LatexRenderer，注入 4 个 Sarasa 字体

### 修复记录
- √ 根号符号超出画布裁剪 → 改为自绘 draw_line V 形，高度自适应
- `\sqrt[n]{}` 可选参数解析失败 → `_parse_optional_arg` 用专用循环替代 `_parse_row`
- `\vec{}` 箭头头超出画布 → deco_h 从 5.0 改为 7.0
- `_await_frame` 健壮性 → 支持 SceneTree 模式和 host 未入树情况

---

## 三、Godot 4.7.1 引擎升级（2026-07-15 完成）

### 修改
- `main.gd._insert_inline_image()`: `add_image()` 签名变更 — `width_in_percent: bool` → `width_unit: int`，修复 `false` → `0`
- `SCRT/project.godot`: `config/features` 从 "4.6" 改为 "4.7"
- 全部 `.claude/skills/*.md` 和文档中的引擎版本号已同步

### 验证通过（无影响）
`tap_back_pos`、`UPDATE_WIDTH_IN_PERCENT`、device ID、font hinting、draw_line antialiasing、method override return types、packed array setters

---

## 四、摄像头系统现状

### 已完成（改进前）

- [x] `camera_feed.gd`（320 行）— 数据模型/纹理缓存/异常状态机/镜头控制
- [x] `camera_manager.gd`（435 行）— 注册中心/manifest 加载/随机异常/存档
- [x] `camera_viewer.gd`（656 行）— 全屏覆盖层/键盘控制/UI 叠加/shader 参数路由
- [x] `camera_effect.gdshader`（247 行）— POM 视差/3 照明/噪点/扫描线/暗角/色彩压缩

### 已知缺陷

| 问题 | 严重程度 | 说明 |
|---|---|---|
| 空间结构错位 | **高** | 全局逐像素深度图仅 255 级灰度，不同物体灰度相近时视差偏移相同 |
| 边缘锯齿撕裂 | 中 | 物体边缘深度梯度不连续 → POM UV 跳变 |
| 照明不准确 | 中 | 灯光衰减用近似公式，不感知物体实际远近 |

---

## 三、改进方案：Region-Based Depth

### 状态：方案已定稿，等待实现

方案文档：`docs/upgrade-plans/camera-region-depth-plan.md`

### 核心思路

三种互补的深度定义方式，运行时合成 `region_depth_map`：

| 方式 | 定义 | 适用场景 |
|---|---|---|
| **Polygon** | JSON 顶点列表 | 简单规则形状（天花板、地板、墙面） |
| **PNG Mask** | 透明/黑白 PNG 图片(数量不限) | 任意复杂形状（树冠、云朵、人形） |
| **Multi-Layer** | 独立底图+独立深度图+z_offset | 独立物体（飞鸟、路灯、前景装饰） |

三者按固定优先级链叠层（layer > mask > polygon > raw depth fallback > default），可同时使用也可任选 1~2 种。

### 关键设计决策

| 决策 | 选择 | 理由 |
|---|---|---|
| 数据存储 | camera manifest 中 `region_config` JSON 字段 | 随故事包分发，一次制作 |
| 运行时合成 | `CameraFeed.build_region_depth_map()` 在 `load_textures()` 后自动调用 | 无需额外管线 |
| 可扩展性 | polygons/masks/layers 均为变长数组 | 支持 N 张 mask PNG、N 个 layer |
| 兼容性 | 无 region config 时行为完全不变 | 向后兼容 |
| Fallback | 未覆盖像素 → raw depth map → global_default | 零遗漏 |
| 对比演示 | R 键切换 region / per-pixel 模式 | PPT 展示 |
| 照明增强 | absorption map 同步生成 | 模拟灯光 + 区域吸光 |
| Mask 边缘过渡 | 用 PNG alpha 通道做渐变，支持画笔绘制的半透明边缘 | 远超算法模拟的平滑效果 |

### 实现顺序

1. ✅ `camera_feed.gd` — 字段 + `load_from_dict` 解析（三种数据源）— 已完成 (2026-07-14)
2. ✅ `camera_feed.gd` — polygon 光栅化 + 平滑 + fallback — 已完成 (2026-07-14)
3. ✅ `camera_feed.gd` — mask PNG 加载 + 写入 — 已完成 (2026-07-14)
4. ✅ `camera_feed.gd` — layer 加载 + 底图合成 + 深度偏移 — 已完成 (2026-07-14)
5. ✅ `camera_effect.gdshader` — uniforms + `get_depth()` 包装 — 已完成 (2026-07-14)
6. ✅ `camera_viewer.gd` — R 键 + UI + shader 透传 — 已完成 (2026-07-14)
7. ✅ `camera_manager.gd` — 加载后触发生成 + 存档 — 已完成 (2026-07-14)
8. ✅ 文档更新 — 已完成 (2026-07-14)

### 涉及文件

| 文件 | 修改量 | 优先级 |
|---|---|---|
| `SCRT/camera_system/camera_feed.gd` | ✅ 已完成（787 行，字节数组优化 + 覆盖掩码） | ★★★★★ |
| `SCRT/camera_system/camera_effect.gdshader` | ✅ 已完成（248 行，移除阈值回退） | ★★★★☆ |
| `SCRT/camera_system/camera_viewer.gd` | ✅ 已完成（689 行，未改动） | ★★★☆☆ |
| `SCRT/camera_system/camera_manager.gd` | ✅ 已完成（444 行，移除冗余调用） | ★★☆☆☆ |
| `docs/camera-asset-guide.txt` | ✅ 已完成（新增 §7.2 Region Config 章节 + 目录示例 + 设计建议） | ★★☆☆☆ |
| `SCRT/camera_system/CLAUDE.md` | 同步更新 | ★★☆☆☆ |

### 代码审阅修复（2026-07-14）

| 修复 | 严重程度 | 说明 |
|---|---|---|
| Bug 1: unload_textures 清空配置 | 高 | `unload_textures()` 不再清除 polygon/mask/layer 配置元数据，只清纹理缓存 |
| Bug 2: shader 阈值回退 | 高 | `get_depth()` 移除 `< 0.001` 判断，天空/远景 ref_distance=0.0 不再误回退 |
| Bug 3: 平滑/fallback 顺序 | 高 | 引入覆盖掩码，fallback 先于平滑执行，region 与 raw depth 自然过渡 |
| Perf 1: 字节数组优化 | 高 | 全部像素循环改用 `PackedByteArray` 直接操作，预计提速 10-50 倍 |
| Perf 2: 冗余合成调用 | 中 | 删除 `camera_manager` 中重复的 `build_composite_base_image()` 调用 |
| 代码质量 | 低 | 删除死代码 `_get_polygon_bounds`、修复重复注释、冒泡排序改 `sort_custom` |

---

## 四、后续规划

### Phase A：实现 Region Depth（✅ 已完成）

摄像头系统具备 R 键实时对比、区域语义深度、字节数组优化管线。

### Phase B：演示专用入口（✅ PPT 框架已完成，等待素材替换）

独立 Godot 项目位于 `D:\Godot\Projects\demo\`（SCRT 同级目录）。
- 14 页幻灯片：技术原理 + POM 数学模型 + 代码片段 + 2 个 live camera demo
- 代码高亮 + 彩色渐变图表（优先级链/管线流程/POM步进）
- 占位素材系统：缺失图片显示虚线框 + 描述
- 清理：删除 `demo/` 文件夹即可，SCRT 零影响（详见 `demo/CLEANUP.md`）
- 详见 `docs/upgrade-plans/demo-camera-plan.md`

### Phase C：PPT 素材制作

- 准备 3~5 组底图+深度图+region config 的测试场景
- 录制对比视频（per-pixel vs region depth）

---

## 五、关键索引

| 资源 | 路径 |
|---|---|
| 项目入口文档 | `CLAUDE.md` |
| 开发进度总结 | `DEVELOPMENT_STATUS.md` |
| 摄像头系统 AI 文档 | `SCRT/camera_system/CLAUDE.md` |
| 摄像头素材指南 | `docs/camera-asset-guide.txt` |
| Region Depth 方案 | `docs/upgrade-plans/camera-region-depth-plan.md` |
| 架构文档 | `docs/architecture.md` |
| 扩展指南 | `docs/extension-guide.md` |

### 摄像头系统文件

| 文件 | 行数 | 用途 |
|---|---|---|
| `SCRT/camera_system/camera_feed.gd` | 787 | 数据模型（含 Region Depth 完整管线：字节数组 + 覆盖掩码 + 解析 + 合成 + 底图合成） |
| `SCRT/camera_system/camera_manager.gd` | 444 | 注册/生命周期 |
| `SCRT/camera_system/camera_viewer.gd` | 689 | 查看器覆盖层 |
| `SCRT/camera_system/camera_effect.gdshader` | 248 | Shader 渲染管线 |

