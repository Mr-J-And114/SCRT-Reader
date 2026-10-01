# Demo 清理指南

> 演示完成后，按以下步骤清理。SCRT 主项目完全不受影响。

## 快速清理（一步）

删除整个 `demo/` 文件夹：

```powershell
Remove-Item -Recurse -Force "D:\Godot\Projects\demo"
```

## 文件清单（全部在 demo/ 内）

| 文件/目录 | 说明 |
|---|---|
| `demo/project.godot` | 独立 Godot 项目配置 |
| `demo/demo_camera.tscn` | Demo 场景 |
| `demo/demo_camera.gd` | 主控制器（CRT 后处理 + 背景图 + 字体 + 幻灯片渲染 + 摄像头集成） |
| `demo/demo_slides.gd` | 幻灯片数据 + 占位注册表 + 摄像头配置 |
| `demo/shaders/crt_effect.gdshader` | 从 SCRT 复制的 CRT 后处理 shader |
| `demo/shaders/background_vignette.gdshader` | 从 SCRT 复制的背景暗角 shader |
| `demo/shaders/background_logo.gdshader` | 从 SCRT 复制的背景 logo shader |
| `demo/fonts/` | 从 SCRT 复制的 SarasaMonoSC 字体（Regular/SemiBold/Italic/SemiBoldItalic） |
| `demo/images/backround.png` | 从 SCRT 复制的背景纹理图 |
| `demo/images/矢量SCP.png` | 从 SCRT 复制的 SCP logo（备用） |
| `demo/camera_system/` | 从 SCRT 复制的摄像头系统（4 文件） |
| `demo/theme/theme_manager.gd` | ThemeManager 桩（仅提供绿色主题色） |
| `demo/data/cameras/` | 演示用摄像头素材（占位/真实） |
| `demo/assets/` | PPT 配图素材 |
| `demo/CLEANUP.md` | 本文件 |

## SCRT 主项目可能残留

如果在 SCRT 主项目中也测试过 demo 摄像头配置：
- `SCRT/data/main/manifest.json` → 搜索 `cam_demo`，删除相关条目
- `SCRT/data/main/demo_cameras/` → 删除此目录（如果创建过）

## 素材替换记录

### PPT 配图（demo/assets/）
| ID | 路径 | 状态 | 说明 |
|---|---|---|---|
| system_overview | demo/assets/system_overview.png | 已用代码绘制替代 | 幻灯片 Slide 2 |
| pom_principle | demo/assets/pom_principle.png | 已用代码绘制替代 | 幻灯片 Slide 3 |
| problem_comparison | demo/assets/problem_comparison.png | 已用代码绘制替代 | 幻灯片 Slide 5 |
| three_sources | demo/assets/three_sources.png | 已用代码绘制替代 | 幻灯片 Slide 7 |
| room_preview | demo/assets/room_preview.jpg | ✅ 已替换 | Test 1 底图 (test1-base.jpg) |
| pool_preview | demo/assets/pool_preview.png | ✅ 已替换 | Test 2 底图 (test-2-base.png) |
| compare_result | demo/assets/compare_result.png | 已用代码绘制替代 | 幻灯片 Slide 13 |

### 摄像头素材（demo/data/cameras/）
| 路径 | 状态 | 说明 |
|---|---|---|
| room/base.jpg | ✅ 已替换 | Test 1 彩色底图 |
| room/depth.png | ✅ 已替换 | Test 1 深度图 (Depth Anything V2 生成) |
| room/spotlight.jpg | ✅ 已替换 | Test 1 夜间模式 (test1-dark.jpg) |
| room/regions/mask_0~10.png | ✅ 已替换 | Test 1 的 11 张区域掩码 |
| pool/base.png | ✅ 已替换 | Test 2 彩色底图 (test-2-base.png, 1600×672) |
| pool/depth.png | ✅ 已替换 | Test 2 深度图 (test-2-depth.png, Depth Anything V2) |
| pool/spotlight.png | ✅ 已替换 | Test 2 夜间模式 (test2-dark.png) |
| pool/regions/mask_0~6.png | ✅ 已替换 | Test 2 的 7 张区域掩码 |

### 摄像头配置（demo_slides.gd DEMO_CAMERAS）
- cam_demo_room: ✅ 已配置 11 张 mask（ref_distance 按真实距离线性映射）
- cam_demo_pool: ✅ 已配置 7 张 mask（∞/25m/20m/15m/11m/9m/2m，max_distance=30m）
