# camera_system/ — CCTV 监控系统 (CCTV Surveillance)

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 素材指南：[/docs/camera-asset-guide.txt](/docs/camera-asset-guide.txt)
> 修改摄像头系统后请同步更新本文件。

CCTV 监控摄像头系统，支持 shader 渲染的监控画面、深度视差、多种照明模式和异常事件。
玩家通过 `camera` / `cam` / `cctv` 命令查看摄像头。

## 文件列表

| 文件 | 行数 | 用途 |
|---|---|---|
| camera_feed.gd | 320 | 单摄像头数据模型：底图/深度图/照明图/异常图路径 + 缓存纹理、镜头参数 |
| camera_manager.gd | 435 | 摄像头注册中心：从 manifest 加载、解锁/锁定、上下线、异常触发、存档、图像加载 |
| camera_viewer.gd | 656 | 全屏查看覆盖层 + `camera_effect.gdshader` 渲染、UI 覆盖层（名称/位置/时间戳/信号条） |
| camera_effect.gdshader | — | 监控画面着色器：深度视差 + 3 种照明 + 噪声/扫描线/信号干扰/雪花点 |

## 架构

```
CameraFeed（数据模型）→ CameraManager（注册/生命周期）→ CameraViewer（覆盖层 + shader 渲染）
```

- **CameraFeed**：底图/深度图/照明图/异常图路径 + 缓存纹理，镜头参数（视口/平移速度/平移范围），效果参数，异常系统（触发/持续时间/冷却）
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
