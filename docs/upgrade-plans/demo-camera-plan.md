# Camera Demo 独立演示程序规划

> 状态：PPT 代码框架已完成，等待素材就绪后替换占位
> 创建：2026-07-14 | 最后更新：2026-07-14
> 清理指南：`demo/CLEANUP.md`（删除 demo/ 文件夹即可，SCRT 零影响）

---

## 一、需求

- 点开 EXE 直接进 PPT，**无开机动画、无登录、无终端 UI**
- **鼠标点击**推进幻灯片（不能用键盘命令）
- 摄像头查看器内保留键盘操作（R 切换深度、方向键平移、Q 退出）
- 退出摄像头回到幻灯片，继续播放
- 可导出为独立 EXE，搬到演示电脑直接运行

---

## 二、架构

```
现有项目（不动）                  新建 Demo（完全独立）
┌─────────────────────┐          ┌──────────────────────────────┐
│ main.tscn           │          │ demo/demo_camera.tscn        │
│   main.gd (2240行)  │          │   DemoCameraHost.gd (~300行) │
│   ├─ 开机动画       │          │   ├─ 幻灯片渲染器            │
│   ├─ 登录系统       │          │   ├─ CameraManager (复用)    │
│   ├─ 故事加载       │          │   ├─ CameraViewer (复用)     │
│   └─ 终端 UI       │          │   └─ 鼠标输入路由            │
└─────────────────────┘          └──────────────────────────────┘
```

不修改任何现有文件，Demo 全部在 `SCRT/demo/` 目录下自包含。

---

## 三、两模式循环

```
    ┌──────────────────────────────────────────────────┐
    │                                                  │
    ▼                                                  │
┌────────┐   点击"打开摄像头"    ┌──────────┐ 按 Q/ESC │
│ 幻灯片 │ ──────────────────→ │ 摄像头    │ ────────→┘
│ 模式   │                     │ 查看器    │
│        │ ←────────────────── │          │
│ 左侧点击：上一页              │ 键盘操作：│
│ 右侧点击：下一页              │ R=深度切换│
│ 中部点击：打开摄像头           │ ←→↑↓=平移 │
│ (仅 camera_link 页)          │ [/]=缩放  │
└────────┘                     └──────────┘
```

---

## 四、幻灯片数据

每张幻灯片是内存中的 Dictionary，不需要外部文件：

```gdscript
var _slides: Array[Dictionary] = [
    {
        "title": "Region-Based Depth",
        "subtitle": "基于区域划分的伪 3D 深度增强",
        "bg": Color(0.05, 0.08, 0.05),
        "type": "title"
    },
    {
        "title": "问题：逐像素深度图",
        "body": "现有方案将深度存储为每个像素的灰度值...\n\n" +
                "[b]问题一：空间结构错位[/b]\n不同物体灰度相近→视差相同\n\n" +
                "[b]问题二：边缘锯齿撕裂[/b]\n深度梯度不连续→UV跳变",
        "image": "res://data/main/demo_cameras/pool/pool_compare.png",
        "type": "content"
    },
    {
        "title": "方案：三路混合深度",
        "body": "① Polygon 区域 - JSON顶点定义规则形状\n" +
                "② PNG Mask 区域 - 灰度图定义复杂轮廓\n" +
                "③ Multi-Layer 层 - 独立底图+深度+偏移\n\n" +
                "优先级链：layer > mask > polygon > raw depth fallback > 默认值",
        "type": "content"
    },
    {
        "title": "演示：规则几何房间",
        "body": "4个Polygon → 16个顶点坐标\n后方墙壁→地板→门框→前景\n\n点击下方按钮打开摄像头查看效果",
        "image": "res://data/main/demo_cameras/room/room_preview.png",
        "camera": "cam_demo_room",
        "type": "camera_link"
    },
    {
        "title": "演示：复杂泳池场景",
        "body": "5张Mask PNG → 立柱+水面+池边\n灰度软笔刷绘制，alpha自然过渡\n\n点击下方按钮打开摄像头查看效果",
        "image": "res://data/main/demo_cameras/pool/pool_preview.png",
        "camera": "cam_demo_pool",
        "type": "camera_link"
    },
    {
        "title": "谢谢",
        "subtitle": "Q & A",
        "type": "title"
    }
]
```

### Slide 类型

| type | 说明 |
|---|---|
| `title` | 标题页，大字居中 |
| `content` | 内容页，标题 + 正文 + 可选图片 |
| `camera_link` | 内容页 + 底部"打开摄像头"按钮，`camera` 字段指定 camera_id |

---

## 五、鼠标交互

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│                 幻灯片内容区域                         │
│                                                      │
│     [点击左侧 40%]           [点击右侧 60%]            │
│      上一页                   下一页                  │
│                                                      │
│        ┌──────────────────────────┐                  │
│        │  [ 打开摄像头查看 ]       │                  │
│        │    (仅 camera_link 页)    │                  │
│        └──────────────────────────┘                  │
└──────────────────────────────────────────────────────┘
```

- 左侧 40% 点击 → 上一页（第一页无效）
- 右侧 60% 点击 → 下一页（最后一页无效）
- `camera_link` 页底部居中按钮 → 打开摄像头
- 摄像头模式中点击不响应（交给键盘）

---

## 六、CameraManager/CameraViewer 适配

`CameraManager` 和 `CameraViewer` 原本依赖 `main` 对象，提供 stub：

| main 属性 | 原用途 | Demo 处理 |
|---|---|---|
| `input_field` | 隐藏终端输入框 | 创建空 LineEdit（不显示） |
| `prompt_label` | 隐藏终端提示 | 创建空 Label（不显示） |
| `output_text` | 缓存终端输出 | 创建空 RichTextLabel（不显示） |
| `path_label` | 状态栏文字 | 创建底部状态栏 Label |
| `scroll_container` | 覆盖层定位参考 | 全屏 ScrollContainer |
| `T` | 主题颜色 | `ThemeManager.current` |
| `fs` | 虚拟文件系统 | `null`（直接从本地加载） |
| `effect_settings` | 效果安全检查 | `null`（demo 不需要） |
| `append_output()` | 日志输出 | print 到控制台 |
| `has_method()` | 方法存在性检查 | 返回 false |

---

## 七、演示流程

1. 启动 → 标题页
2. 点击右侧 → 问题说明页（含对比截图）
3. 点击右侧 → 方案说明页
4. 点击右侧 → 房间场景介绍页
5. 点击"打开摄像头" → 进入摄像头查看器
6. 演示操作：方向键平移、[/] 缩放、R 切换深度模式
7. 按 Q → 回到幻灯片（当前页或下一页）
8. 点击右侧 → 泳池场景介绍页
9. 点击"打开摄像头" → 泳池查看器
10. 演示操作：R 切换对比、平移观察立柱分离
11. 按 Q → 回到幻灯片（总结页）
12. 结束

---

## 八、实施状态（已完成）

Demo 作为独立 Godot 项目，位于 `D:\Godot\Projects\demo\`（SCRT 同级目录）。

### 文件结构

```
demo/                         独立 Godot 项目（删除此文件夹即可清理）
├── project.godot             独立项目配置（GL Compatibility）
├── CLEANUP.md                清理指南 + 占位素材替换记录
├── demo_camera.tscn          Demo 场景（Control 根节点）
├── demo_camera.gd            主控制器：CRT后处理 + 背景图 + 字体 + 幻灯片渲染 + 代码高亮 + 彩色渐变图 + 鼠标导航 + stub 适配
├── demo_slides.gd            14 页幻灯片数据 + 占位注册表 + 演示摄像头配置
├── shaders/
│   ├── crt_effect.gdshader   CRT 后处理 shader（扫描线/弯曲/色差/暗角/磷光/bloom）
│   ├── background_vignette.gdshader  背景暗角 shader
│   └── background_logo.gdshader      背景 logo shader（备用）
├── fonts/                    SarasaMonoSC 等宽字体（Regular/SemiBold/Italic/SemiBoldItalic）
├── images/
│   ├── backround.png         背景纹理图
│   └── 矢量SCP.png           SCP logo（备用）
├── camera_system/            从 SCRT 复制的摄像头系统（4 文件，代码已审阅修复）
│   ├── camera_feed.gd        Region Depth 完整管线
│   ├── camera_manager.gd     注册/生命周期
│   ├── camera_viewer.gd      查看器覆盖层 + R 键切换
│   └── camera_effect.gdshader 渲染 shader
├── theme/
│   └── theme_manager.gd      ThemeManager 桩（仅绿色 CRT 主题色）
├── data/cameras/             演示摄像头素材
│   ├── room/base.jpg         [占位] → 替换为真实房间底图
│   ├── room/depth.jpg        [占位] → 替换为真实房间深度图
│   ├── pool/base.jpg         [占位] → 替换为真实泳池底图
│   └── pool/depth.jpg        [占位] → 替换为真实泳池深度图
└── assets/                   PPT 配图占位目录
    └── .gdignore
```

### 验证状态

- Godot 4.6 headless 模式：零 parse error、零 script error
- CameraManager 成功加载 2 个演示摄像头
- 14 页幻灯片数据完整
- 代码高亮 + 彩色渐变图绘制就绪
- 占位素材系统：缺失图片显示虚线框 + 描述文字

### 幻灯片列表（14 页）

| # | 类型 | 标题 |
|---|---|---|
| 1 | title | Region-Based Depth |
| 2 | content | 摄像头系统与深度图技术 |
| 3 | content | POM 视差映射原理 |
| 4 | content | POM 数学模型 |
| 5 | content | 逐像素深度图的三大缺陷 |
| 6 | diagram | 方案：三路混合深度 |
| 7 | content | 三种深度源详解 |
| 8 | diagram | CPU 合成管线 |
| 9 | code | 性能优化：字节数组 |
| 10 | code | Shader 实现：POM + 统一深度采样 |
| 11 | camera_link | 演示：规则几何房间 |
| 12 | camera_link | 演示：复杂泳池场景 |
| 13 | content | 总结与展望 |
| 14 | title | 谢谢 |

---

## 九、素材准备清单（待替换占位）

详细占位替换记录见 `demo/CLEANUP.md`。

### PPT 配图（demo/assets/）

| 占位 ID | 路径 | 说明 |
|---|---|---|
| system_overview | demo/assets/system_overview.png | 摄像头系统功能总览 |
| pom_principle | demo/assets/pom_principle.png | POM 视差映射原理 |
| problem_comparison | demo/assets/problem_comparison.png | 三大缺陷对比 |
| three_sources | demo/assets/three_sources.png | 三种深度源示意 |
| room_preview | demo/assets/room_preview.png | 房间场景预览 |
| pool_preview | demo/assets/pool_preview.png | 泳池场景预览 |
| compare_result | demo/assets/compare_result.png | Region vs Per-Pixel 对比 |

### 摄像头素材（demo/data/cameras/）

| 占位 | 当前 | 替换为 |
|---|---|---|
| room/base.jpg | camera_test_main.jpg | 真实房间底图 |
| room/depth.jpg | camera_test_depth.jpg | 真实房间深度图 |
| pool/base.jpg | camera_test_main.jpg | 真实泳池底图 |
| pool/depth.jpg | camera_test_depth.jpg | 真实泳池深度图 |
| pool/mask_*.png | 无 | 泳池各区域灰度 mask |

### 摄像头配置占位（demo_slides.gd DEMO_CAMERAS）

- cam_demo_room 的 region_config polygons → 替换为真实房间顶点坐标
- cam_demo_pool 的 region_config masks → 替换为真实泳池 mask 配置

### 待实现功能

- **LaTeX 公式支持**：在幻灯片 body 中支持 `$...$` 行内公式和 `$$...$$` 块公式，渲染为数学符号图片嵌入 RichTextLabel。需要在 demo 中集成公式渲染（可用 MathJax 预渲染为 PNG 或 Godot 插件）。优先级：低，当前问题解决后实施。
