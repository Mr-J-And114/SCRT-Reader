# camera_system/ — CCTV 监控系统 (CCTV Surveillance)

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 素材指南：[/docs/camera-asset-guide.txt](/docs/camera-asset-guide.txt)
> 修改摄像头系统后请同步更新本文件。

CCTV 监控摄像头系统，支持 shader 渲染的监控画面、深度视差、多种照明模式和异常事件。
玩家通过 `camera` / `cam` / `cctv` 命令查看摄像头。

## 文件列表

| 文件 | 行数 | 用途 |
|---|---|---|
| camera_feed.gd | 928 | 单摄像头数据模型：底图/深度图/照明图/异常图路径 + 缓存纹理、镜头参数、Region-Based Depth 完整管线（浮点深度 + 局部变化 + 两遍 mask 算法 + mask 羽化 + 软 coverage + 软 fallback + 合成 + 底图合成） |
| camera_manager.gd | 444 | 摄像头注册中心：从 manifest 加载、解锁/锁定、上下线、异常触发、存档、图像加载、Region Depth 存档状态 |
| camera_viewer.gd | 689 | 全屏查看覆盖层 + `camera_effect.gdshader` 渲染、UI 覆盖层、R 键 Region Depth 切换、shader 透传 |
| camera_effect.gdshader | 263 | 监控画面着色器：深度视差（POM clamp [0,1]）+ 3 种照明 + 噪声/扫描线/信号干扰/雪花点 + Region-Based Depth 统一采样（FORMAT_RF 浮点纹理） |

## 架构

```
CameraFeed（数据模型）→ CameraManager（注册/生命周期）→ CameraViewer（覆盖层 + shader 渲染）
```

- **CameraFeed**：底图/深度图/照明图/异常图路径 + 缓存纹理，镜头参数（视口/平移速度/平移范围），效果参数，异常系统（触发/持续时间/冷却），Region-Based Depth 三路数据（polygons/masks/layers）
- **CameraManager**：从 manifest 注册摄像头，解锁/锁定，上线/下线，异常触发（含安全检查），`process()` 中自动触发异常，存档/读档，通过 FileSystem 加载图像
- **CameraViewer**：全屏覆盖层，键盘控制（方向键=平移, [/]=缩放, 1-9=切换, TAB/Shift+TAB=前后切换, F=照明模式, Q/ESC=关闭）

## Shader 渲染管线 (camera_effect.gdshader)

1. **深度视差偏移**（底图 + 异常图层），支持陡峭视差映射 (POM) + 插值优化
2. **3 种照明模式**：聚光灯（圆形遮罩，支持预渲染图叠加）、夜视（绿色调）、红外（伪彩热图）
3. **噪声 / 扫描线 / 暗角 / 信号干扰 / 雪花点**（信号质量 < 0.5 时出现横条纹）
4. **色彩压缩**（去饱和 + 绿色偏移营造 CRT 质感）
5. **异常平滑混合过渡**（支持 overlay/replace 两种混合模式）
6. **FOV 缩放**（`[`/`]` 键控制，`fov_min`~`fov_max` 范围限制）
7. **摄像头切换故障效果**（切换时短暂降低信号质量 + 视觉抖动）

## 异常安全（重要）

当 `effect_settings.is_effect_allowed("jumpscare")` 返回 `false`（OFF 模式）时，视觉异常效果被阻止。
**但触发器动作（邮件投递、文件解锁等）始终执行，不受效果等级影响。**

## Manifest 配置

键名：`"camera_system"`，包含 `"cameras"` 字典（以摄像头 ID 为键）。

每个摄像头支持的字段：

| 字段 | 类型 | 说明 |
|---|---|---|
| `name` | String | 摄像头名称 |
| `location` | String | 位置描述 |
| `unlocked` | bool | 是否已解锁 |
| `online` | bool | 是否在线 |
| `base_image` | String | **必填** 底图路径 |
| `depth_map` | String | 深度图路径（灰度） |
| `light_mode` | String | 默认照明模式 |
| `light_image` | String | 照明图路径 |
| `viewport_size` | Array | 视口尺寸 [w, h] |
| `viewport_pos` | Array | 初始视口位置 [x, y] |
| `pan_speed` | float | 平移速度 |
| `pan_bounds` | Array | 平移范围限制 |
| `noise_intensity` | float | 噪声强度 |
| `scanline_intensity` | float | 扫描线强度 |
| `vignette` | float | 暗角强度 |
| `signal_quality` | float | 信号质量 (0-1) |
| `snow_intensity` | float | 雪花点强度 |
| `anomalies` | Array | 异常定义数组 |
| `region_config` | Dictionary | Region-Based Depth 配置（polygons/masks/layers + 全局参数 + variation_scale + mask_feather_radius） |

## 触发器动作

| 动作 | 说明 |
|---|---|
| `camera_unlock:cam_id` | 解锁摄像头 |
| `camera_lock:cam_id` | 锁定摄像头 |
| `camera_online:cam_id` | 设置摄像头在线 |
| `camera_offline:cam_id` | 设置摄像头离线 |
| `camera_anomaly:cam_id[:anom_id]` | 触发摄像头异常 |
| `camera_signal:cam_id:quality` | 设置信号质量 (0-1) |

## 存档数据

存储在故事存档的 `extra["camera_data"]` 中。
每个摄像头保存：`unlocked`（是否解锁）、`online`（是否在线）、`signal_quality`（信号质量）、`viewport_pos`（视口位置）、异常冷却状态。

## Region-Based Depth（已完成）

三路混合深度定义方式，运行时合成 `region_depth_map`，解决逐像素深度图的空间结构错位问题。

| 方式 | 定义 | 适用场景 |
|---|---|---|
| **Polygon** | JSON 顶点列表 | 简单规则形状（天花板、地板、墙面） |
| **PNG Mask** | 透明/黑白 PNG（数量不限） | 任意复杂形状（树冠、云朵、人形） |
| **Multi-Layer** | 独立底图+独立深度图+z_offset | 独立物体（飞鸟、路灯、前景装饰） |

优先级链：layer (z_offset) > mask (priority) > polygon > raw depth fallback > global_default

### Mask 局部变化算法（v2）

mask 不再写入平坦的 `ref_distance`，而是保留原深度图在 mask 区域内的局部 3D 结构变化：

```
final_depth = ref_distance + (raw_depth - mask_mean_raw) * variation_scale
```

- `ref_distance`：mask 指定的绝对距离基准
- `raw_depth`：原深度图在该像素的值
- `mask_mean_raw`：该 mask 覆盖区域内原深度图的**加权均值**（Pass 1 计算，用羽化后的权重）
- `variation_scale`：局部变化强度系数（全局可配，默认 0.3，设为 0 退化为平坦模式）

三遍算法：Pass 0 预计算 mask 浮点权重 + 高斯羽化 → Pass 1 计算加权均值 → Pass 2 写入 `ref_distance + 局部变化`。

### Mask 边界羽化（v3 新增）

解决人工绘制 mask 边界不精确（gap/overlap）导致的深度硬跳变问题：

- **`mask_feather_radius`**（默认 3.0px）：mask 边缘羽化宽度
- Pass 0 将 mask 的 `alpha × red` 组合权重预计算为 `PackedFloat32Array`，然后做 box blur 产生 0→1 渐变
- 羽化后的权重用于 Pass 1 均值计算和 Pass 2 软合成，使相邻 mask 区域之间平滑过渡
- 设为 0 关闭羽化（退化为二值 mask，但仍有软 coverage + 软 fallback）

### 软 Coverage + 软 Fallback

- **Coverage** 从二值 (0/255) 改为**权重累积** (0~255)：mask 边缘像素的 coverage 按权重比例标记，不再被 fallback 整块覆盖
- **Fallback** 从硬切 (`if coverage == 0`) 改为**lerp 软过渡**：`depth = lerp(raw, region, coverage_weight)`
  - coverage=0 → 全用 raw depth（未覆盖区域）
  - coverage=128 → 50% 混合（mask 边缘羽化区）
  - coverage=255 → 全用 region depth（mask 内部）

### 浮点深度管线

深度数组从 `PackedByteArray` (L8, 0-255) 升级为 `PackedFloat32Array` (32 位浮点)，突破 0-255 限制：
- 最终图像格式：`Image.FORMAT_RF`（32-bit float per pixel）
- 值域：[0.0, 2.0]（clamp）
- Shader 端 `sampler2D` 自动返回 float，无需修改采样代码
- POM 视差映射内部 clamp 到 [0,1]，防止 depth > 1.0 导致插值外推
- 照明/激光等效果不 clamp，depth > 1.0 表示更远物体，光照衰减更强

合成管线顺序：
1. 填充 `global_default_distance` → 2. 预处理原深度图为浮点数组 → 3. 应用 polygon/mask/layer（mask 三遍算法：Pass 0 羽化权重 + Pass 1 加权均值 + Pass 2 软合成）→ 4. raw depth fallback（软过渡 lerp，用 coverage 权重混合）→ 5. 边缘平滑（float 版 box blur）→ 6. 创建 FORMAT_RF 图像

性能优化：深度数组使用 `PackedFloat32Array` 直接操作浮点，吸光仍用 `PackedByteArray`。覆盖掩码（L8）从二值改为权重累积，跟踪每个像素被 region 覆盖的程度（0~255）。

详细方案见 `docs/upgrade-plans/camera-region-depth-plan.md`。

