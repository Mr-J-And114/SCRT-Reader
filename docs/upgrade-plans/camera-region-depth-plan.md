# Camera System 改进方案：Region-Based Depth

> 技术规格书 — 面向 AI 开发者
> 目标：用人工区域划分 + 基准距离替代/增强全局逐像素深度图，解决 POM 视差中的空间结构错位
> 创建：2026-07-13 | 最后更新：2026-07-13 | 状态：待实现

---

## 目录

1. [问题回顾](#一问题回顾)
2. [解决方案总览](#二解决方案总览)
3. [三种深度来源对比](#三三种深度来源对比)
4. [文件变更清单](#四文件变更清单)
5. [数据格式设计](#五数据格式设计)
6. [CameraFeed 修改细节](#六camerafeed-修改细节)
7. [Shader 修改细节](#七shader-修改细节)
8. [CameraViewer 修改细节](#八cameraviewer-修改细节)
9. [CameraManager 修改细节](#九cameramanager-修改细节)
10. [测试与验证](#十测试与验证)
11. [实现顺序](#十一实现顺序推荐)
12. [备选/扩展方向](#十二备选扩展方向)

---

## 一、问题回顾

### 1.1 当前架构

```
depth_map.png (逐像素灰度 0~255)
    → POM: 采样 depth 值 → 计算 UV 偏移量
    → 照明: depth 值影响 light_falloff 衰减半径
```

### 1.2 三个本质问题

| 问题 | 表现 | 根因 |
|---|---|---|
| **空间结构错位** | 不同物体但灰度相近 → 视差偏移相同 → "柱子粘在墙上" | 灰度是标量，不包含语义归属 |
| **边缘锯齿撕裂** | 物体边缘深度梯度不连续 → UV 跳变 → 画面撕裂 | POM 对梯度敏感，per-pixel depth 在边缘处无法平滑 |
| **照明不准确** | 灯光衰减仅依赖距离中心远近，不感知物体实际远近 | `effective_dist = uv_dist * (1 + depth² × weight)` 是近似，非物理 |

---

## 二、解决方案总览

### 2.1 核心思路

引入三种互补的深度定义方式，运行时合成一张 `region_depth_map`：

1. **Polygon Regions** — 用 JSON 顶点定义简单几何区域，适合矩形/三角形等规则形状
2. **PNG Mask Regions** — 用透明/黑白图片定义任意复杂形状，适合不规则物体
3. **Multi-Layer** — 独立底图分层，支持独立深度图和 z_offset

```
┌──────────────────────────────────────────────────────────────────────┐
│  Region Config JSON  (人工定义，一次性制作)                           │
│                                                                      │
│  ┌─────────────┐  ┌──────────────────┐  ┌──────────────────────┐    │
│  │ polygons[]  │  │ masks[]          │  │ layers[]             │    │
│  │ (顶点坐标)  │  │ (PNG 区域掩码)   │  │ (独立底图+深度+偏移) │    │
│  └──────┬──────┘  └────────┬─────────┘  └──────────┬───────────┘    │
│         │                  │                       │                 │
└─────────┼──────────────────┼───────────────────────┼─────────────────┘
          │                  │                       │
          ▼                  ▼                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Depth Compositor   (CameraFeed.build_region_depth_map)              │
│                                                                      │
│  优先级链 (每个像素独立计算):                                         │
│    ① layers[n].z_offset        (z_offset 最大者优先)                │
│    ② masks[n] 非透明像素       (数组顺序优先: 越靠后越近)           │
│    ③ polygons[n] 内部像素      (数组顺序优先: 越靠后越近)           │
│    ④ raw depth_map fallback    (如果 use_raw_depth_fallback=true)   │
│    ⑤ global_default_distance   (兜底值)                             │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│  Image Compositor  (如果有 layers，合成最终底图)                     │
│                                                                      │
│  从远到近 (按 z_offset 排序):                                         │
│  - 上层像素透明 → 透到下层                                           │
│  - 上层像素不透明 → 取上层颜色 + 上层深度                            │
│  - 输出: 合成底图 + 合成深度图                                        │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                           ▼
              region_depth_texture  →  shader POM
```

### 2.2 优先级链（每个像素独立计算）

```
最高优先级 ┌─────────────────────────────────────┐
           │  Layer z_offset (绝对值最近)         │  ← 独立物体覆盖场景
           ├─────────────────────────────────────┤
           │  PNG mask 非透明区域 (靠后优先)      │  ← 复杂不规则形状
           ├─────────────────────────────────────┤
           │  Polygon 内部区域 (靠后优先)          │  ← 简单规则形状
           ├─────────────────────────────────────┤
           │  Raw depth map (fallback)            │  ← 原有逐像素深度
           ├─────────────────────────────────────┤
           │  global_default_distance             │  ← 啥都没有时的默认值
最低优先级 └─────────────────────────────────────┘
```

### 2.3 可扩展性说明

- `polygons[]`、`masks[]`、`layers[]` 都是**变长数组**，数量不限
- 三者可同时使用，也可只用其中 1~2 种
- 一个场景可以只有 1 张 mask PNG，也可以有 10 张
- 单个独立物体（如一只鸟）可以是一个 layer，有自己的 base + depth，无需和其他区域纠缠

### 2.4 设计原则

1. **向后兼容** — 不提供 region config 时行为完全不变
2. **按需覆盖** — 只定义需要修正的区域，其余 fallback
3. **可插拔** — shader 端 `use_region_depth` uniform 切换，R 键运行时对比
4. **三路互补** — polygon 管简单形状、mask 管复杂形状、layer 管独立物体

---

## 三、三种深度来源对比

| 维度 | Polygon Regions | PNG Mask Regions | Multi-Layer |
|---|---|---|---|
| **定义方式** | JSON 顶点数组 | PNG 图片（透明/黑白） | 独立底图 + 独立深度图 |
| **适用形状** | 矩形、三角形、简单多边形 | 任意复杂不规则形状 | 独立物体（可脱离场景移动） |
| **制作门槛** | 配 JSON 数值即可 | 需要绘画工具（PS/GIMP） | 需要抠图+绘制深度 |
| **边缘过渡** | 算法平滑（均值滤波） | 直接在 PNG 中画渐变 | 依赖独立深度图 |
| **典型场景** | 天花板、地板、墙面 | 树冠、云层、人形轮廓 | 飞鸟、移动物体、前景饰品 |
| **重叠处理** | 后定义覆盖前定义 | 后定义覆盖前定义 | z_offset 排序 |
| **图片数量** | 0 张 | N 张（每区域 1 张） | N 组（每组 1 底图+1深度图） |

---

## 四、文件变更清单

| 文件 | 操作 | 说明 |
|---|---|---|
| `SCRT/camera_system/camera_feed.gd` | **修改** | 新增三种 region 数据类型、`build_region_depth_map()` 核心合成方法、layer 合图方法、loader 函数扩展 |
| `SCRT/camera_system/camera_effect.gdshader` | **修改** | 新增 region depth uniform、`get_depth()` 统一采样函数 |
| `SCRT/camera_system/camera_viewer.gd` | **修改** | 新增 R 键切换对比、UI 指示、操作提示 |
| `SCRT/camera_system/camera_manager.gd` | **修改** | manifest 解析、加载后触发生成、存档扩展 |
| `docs/camera-asset-guide.txt` | **修改** | 新增 Region Config 素材制作章节 |
| `SCRT/camera_system/CLAUDE.md` | **修改** | 同步更新 |
| _(可选)_ `tools/region_editor.gd` | **新增** | 可视化区域绘制 + 预览工具 |

---

## 五、数据格式设计

### 5.1 Region Config JSON Schema

```json
{
  "camera_system": {
    "cameras": {
      "cam_outdoor_01": {
        "base_image": "cameras/outdoor/base.png",
        "depth_map": "cameras/outdoor/depth.png",
        "region_config": {

          "polygons": [
            {
              "id": "ceiling_arch",
              "label": "天花板拱门",
              "ref_distance": 0.88,
              "points": [[0.0,0.0], [0.4,0.0], [0.35,0.18], [0.0,0.22]],
              "light_absorption": 0.2
            }
          ],

          "masks": [
            {
              "id": "sky",
              "label": "天空",
              "image": "cameras/outdoor/regions/sky.png",
              "ref_distance": 0.0,
              "real_distance": -999.0,
              "priority": 0
            },
            {
              "id": "mountain_far",
              "label": "远山",
              "image": "cameras/outdoor/regions/mountains.png",
              "ref_distance": 0.12,
              "real_distance": 500.0,
              "priority": 1
            },
            {
              "id": "building_mid",
              "label": "建筑群",
              "image": "cameras/outdoor/regions/buildings.png",
              "ref_distance": 0.35,
              "real_distance": 80.0,
              "priority": 2
            },
            {
              "id": "fence_near",
              "label": "近处围栏",
              "image": "cameras/outdoor/regions/fence.png",
              "ref_distance": 0.78,
              "real_distance": 3.0,
              "priority": 3
            }
          ],

          "layers": [
            {
              "id": "bird",
              "label": "飞鸟",
              "base_image": "cameras/outdoor/layers/bird.png",
              "depth_map": "cameras/outdoor/layers/bird_depth.png",
              "z_offset": 0.0,
              "real_distance": 12.0
            },
            {
              "id": "lamp_post",
              "label": "路灯(前景)",
              "base_image": "cameras/outdoor/layers/lamp.png",
              "depth_map": "cameras/outdoor/layers/lamp_depth.png",
              "z_offset": 2.5,
              "real_distance": 1.5
            }
          ],

          "global_default_distance": 0.3,
          "smooth_radius": 0.02,
          "use_raw_depth_fallback": true
        }
      }
    }
  }
}
```

### 5.2 字段说明

#### 顶层

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `polygons` | Array | 否 | `[]` | 多边形区域定义 |
| `masks` | Array | 否 | `[]` | PNG 掩码区域定义 |
| `layers` | Array | 否 | `[]` | 独立图层定义 |
| `global_default_distance` | float | 否 | `0.3` | 未被任何方式覆盖的像素的默认距离 |
| `smooth_radius` | float | 否 | `0.02` | 区域间插值平滑半径(归一化) |
| `use_raw_depth_fallback` | bool | 否 | `true` | 是否回退到原始 depth map |

#### Polygon

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `id` | String | 是 | — | 区域唯一标识 |
| `label` | String | 否 | `""` | 人类可读标签 |
| `ref_distance` | float | 是 | — | 基准距离 0.0(最远)~1.0(最近) |
| `points` | Array[[x,y]] | 是 | — | 多边形顶点(归一化坐标 0.0~1.0) |
| `light_absorption` | float | 否 | `0.5` | 吸光系数 0.0~1.0 |

#### Mask

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `id` | String | 是 | — | 区域唯一标识 |
| `label` | String | 否 | `""` | 人类可读标签 |
| `image` | String | 是 | — | PNG 掩码图片路径 |
| `ref_distance` | float | 是 | — | 基准距离 0.0(最远)~1.0(最近) |
| `real_distance` | float | 否 | `null` | 真实距离(米)，负数=无限远(天空) |
| `priority` | int | 否 | `0` | 优先级(大=近，重叠时优先) |

**Mask PNG 制作规范**：
- 非透明/非黑色像素 = 该区域覆盖范围
- 透明/黑色像素 = 穿透（留给更低优先级）
- 可在边缘画渐变透明度 → 等效深度过渡
- 白色区域纯度高，值更稳定过渡更准确

#### Layer

| 字段 | 类型 | 必填 | 默认值 | 说明 |
|---|---|---|---|---|
| `id` | String | 是 | — | 图层唯一标识 |
| `label` | String | 否 | `""` | 人类可读标签 |
| `base_image` | String | 是 | — | 独立底图 (含透明通道) |
| `depth_map` | String | 是 | — | 独立深度图 |
| `z_offset` | float | 否 | `0.0` | 深度偏移量(越大越靠近镜头，覆盖底层) |
| `real_distance` | float | 否 | `null` | 真实距离(米) |

### 5.3 `ref_distance` 取值规范

| 范围 | 语义 | 典型物体 |
|---|---|---|
| 0.0~0.2 | 极远（背景） | 天空、远方山脉、走廊尽头、窗外景色 |
| 0.2~0.4 | 远景 | 远处墙壁、远处家具、窗 |
| 0.4~0.6 | 中景 | 桌子、椅子、仪器台、门 |
| 0.6~0.8 | 近景 | 操作台、近处设备、靠近镜头的门框 |
| 0.8~1.0 | 极近（前景） | 镜头前的柱子、左上角的天花板、最近处的物体边缘 |

---

## 六、CameraFeed 修改细节

### 6.1 新增成员变量

```gdscript
# ── Region Config 原始数据 ──
var region_config: Dictionary = {}

# ── 三种深度来源（解析后）──
var polygon_regions: Array[Dictionary] = []    # polygons[]
var mask_regions: Array[Dictionary] = []       # masks[] (含 image 路径)
var layers: Array[Dictionary] = []             # layers[] (含 base/depth 路径)

# ── 全局参数 ──
var global_default_distance: float = 0.3
var smooth_radius: float = 0.02
var use_raw_depth_fallback: bool = true

# ── Region Depth 运行时纹理 ──
var region_depth_image: Image = null
var region_depth_texture: ImageTexture = null
var use_region_depth: bool = false

# ── Absorption map ──
var absorption_image: Image = null
var absorption_texture: ImageTexture = null

# ── 合成底图（当有 layers 时使用）──
var composite_base_image: Image = null
var composite_base_texture: ImageTexture = null

# ── 脏标记 ──
var _region_dirty: bool = false

# ── Mask 纹理缓存 ──
var _mask_textures: Dictionary = {}           # mask_id → Image
var _layer_base_images: Dictionary = {}       # layer_id → Image
var _layer_depth_images: Dictionary = {}      # layer_id → Image
```

### 6.2 `load_from_dict()` 新增解析

在异常图解析之后添加：

```gdscript
# ── Region Depth Config ──
polygon_regions.clear()
mask_regions.clear()
layers.clear()
_region_dirty = false

region_config = data.get("region_config", {})
if not region_config.is_empty():
    use_region_depth = true
    global_default_distance = region_config.get("global_default_distance", 0.3)
    smooth_radius = region_config.get("smooth_radius", 0.02)
    use_raw_depth_fallback = region_config.get("use_raw_depth_fallback", true)

    # 解析 polygons
    for r_data in region_config.get("polygons", []):
        var r: Dictionary = {}
        r["id"] = r_data.get("id", "poly_%d" % polygon_regions.size())
        r["label"] = r_data.get("label", "")
        r["ref_distance"] = r_data.get("ref_distance", 0.5)
        r["points"] = r_data.get("points", [])
        r["light_absorption"] = r_data.get("light_absorption", 0.5)
        polygon_regions.append(r)

    # 解析 masks
    for m_data in region_config.get("masks", []):
        var m: Dictionary = {}
        m["id"] = m_data.get("id", "mask_%d" % mask_regions.size())
        m["label"] = m_data.get("label", "")
        m["image"] = _resolve_path(m_data.get("image", ""), base_path)
        m["ref_distance"] = m_data.get("ref_distance", 0.5)
        m["real_distance"] = m_data.get("real_distance", null)
        m["priority"] = m_data.get("priority", 0)
        m["light_absorption"] = m_data.get("light_absorption", 0.5)
        mask_regions.append(m)

    # 解析 layers
    for l_data in region_config.get("layers", []):
        var l: Dictionary = {}
        l["id"] = l_data.get("id", "layer_%d" % layers.size())
        l["label"] = l_data.get("label", "")
        l["base_image"] = _resolve_path(l_data.get("base_image", ""), base_path)
        l["depth_map"] = _resolve_path(l_data.get("depth_map", ""), base_path)
        l["z_offset"] = l_data.get("z_offset", 0.0)
        l["real_distance"] = l_data.get("real_distance", null)
        layers.append(l)

    # 按 z_offset 排序（从远到近）
    layers.sort_custom(func(a, b): return a["z_offset"] < b["z_offset"])

    _region_dirty = true
```

### 6.3 `load_textures()` 扩展

在现有纹理加载完成后，追加 region 相关加载：

```gdscript
func load_textures(loader_func: Callable) -> void:
    # ... 原有 base/depth/light/prerendered 加载不变 ...

    # 加载 mask 图片
    if _region_dirty and use_region_depth:
        _mask_textures.clear()
        for m in mask_regions:
            var path: String = m.get("image", "")
            if not path.is_empty():
                var img: Image = loader_func.call(path)
                if img:
                    _mask_textures[m["id"]] = img

        # 加载 layer 图片
        _layer_base_images.clear()
        _layer_depth_images.clear()
        for l in layers:
            var base_path: String = l.get("base_image", "")
            var depth_path: String = l.get("depth_map", "")
            if not base_path.is_empty():
                var img: Image = loader_func.call(base_path)
                if img:
                    _layer_base_images[l["id"]] = img
            if not depth_path.is_empty():
                var img: Image = loader_func.call(depth_path)
                if img:
                    _layer_depth_images[l["id"]] = img

        build_region_depth_map()
```

### 6.4 `build_region_depth_map()` — 核心合成方法

```gdscript
func build_region_depth_map() -> void:
    if not use_region_depth:
        _clear_region_data()
        return

    var img_w: int = 0
    var img_h: int = 0
    if composite_base_image:
        img_w = composite_base_image.get_width()
        img_h = composite_base_image.get_height()
    elif base_image:
        img_w = base_image.get_width()
        img_h = base_image.get_height()
    elif depth_map:
        img_w = depth_map.get_width()
        img_h = depth_map.get_height()
    else:
        return

    # 创建 depth 和 absorption 画布
    var depth_img := Image.create(img_w, img_h, false, Image.FORMAT_L8)
    var abs_img := Image.create(img_w, img_h, false, Image.FORMAT_L8)
    var default_val: int = int(global_default_distance * 255.0)
    depth_img.fill(Color8(default_val, default_val, default_val))
    abs_img.fill(Color8(128, 128, 128))

    # Step 1: 写入 polygon regions (最低优先级)
    _apply_polygon_regions(depth_img, abs_img, img_w, img_h)

    # Step 2: 写入 PNG mask regions (覆盖 polygon)
    _apply_mask_regions(depth_img, abs_img, img_w, img_h)

    # Step 3: 写入 layer z_offset (最高优先级，覆盖 mask)
    _apply_layer_depths(depth_img, img_w, img_h)

    # Step 4: 边缘平滑
    if smooth_radius > 0.0:
        var px_radius: int = maxi(1, int(smooth_radius * float(mini(img_w, img_h))))
        depth_img = _smooth_region_boundaries(depth_img, px_radius)
        abs_img = _smooth_region_boundaries(abs_img, px_radius)

    # Step 5: Fallback 到原始 depth map
    if use_raw_depth_fallback and depth_map:
        var raw: Image = depth_map
        if raw.get_size() != Vector2i(img_w, img_h):
            raw = raw.duplicate()
            raw.resize(img_w, img_h, Image.INTERPOLATE_LANCZOS)
        _apply_raw_depth_fallback(depth_img, raw, default_val)

    region_depth_image = depth_img
    region_depth_texture = ImageTexture.create_from_image(depth_img)
    absorption_image = abs_img
    absorption_texture = ImageTexture.create_from_image(abs_img)
    _region_dirty = false
```

### 6.5 `_apply_polygon_regions()`

```gdscript
func _apply_polygon_regions(depth_img: Image, abs_img: Image, w: int, h: int) -> void:
    for region in polygon_regions:
        var pts: Array = region.get("points", [])
        if pts.size() < 3:
            continue
        var dist_val: int = int(clampf(region.get("ref_distance", 0.5), 0.0, 1.0) * 255.0)
        var abs_val: int = int(clampf(region.get("light_absorption", 0.5), 0.0, 1.0) * 255.0)
        _rasterize_polygon(depth_img, pts, dist_val)
        _rasterize_polygon(abs_img, pts, abs_val)
```

### 6.6 `_apply_mask_regions()`

```gdscript
func _apply_mask_regions(depth_img: Image, abs_img: Image, w: int, h: int) -> void:
    # 按 priority 排序（低→高，高优先级覆盖低优先级）
    var sorted: Array[Dictionary] = mask_regions.duplicate()
    sorted.sort_custom(func(a, b): return a.get("priority", 0) < b.get("priority", 0))

    for m in sorted:
        var mask_img: Image = _mask_textures.get(m["id"])
        if mask_img == null:
            continue
        # 缩放到目标尺寸
        if mask_img.get_size() != Vector2i(w, h):
            mask_img = mask_img.duplicate()
            mask_img.resize(w, h, Image.INTERPOLATE_BILINEAR)

        var dist_val: int = int(clampf(m.get("ref_distance", 0.5), 0.0, 1.0) * 255.0)
        var abs_val: int = int(clampf(m.get("light_absorption", 0.5), 0.0, 1.0) * 255.0)

        for y in range(h):
            for x in range(w):
                var px: Color = mask_img.get_pixel(x, y)
                # 非透明且非黑色 = 有效区域
                if px.a > 0.1 and px.r > 0.01:
                    # 使用 alpha 做距离插值（支持边缘渐变过渡）
                    var blend: float = px.a
                    if px.r < 1.0:
                        # 灰度值也可作为辅助权重
                        blend *= px.r
                    var new_d: float = lerpf(
                        depth_img.get_pixel(x, y).r,
                        float(dist_val) / 255.0,
                        blend)
                    depth_img.set_pixel(x, y, Color(new_d, new_d, new_d))
                    var new_a: float = lerpf(
                        abs_img.get_pixel(x, y).r,
                        float(abs_val) / 255.0,
                        blend)
                    abs_img.set_pixel(x, y, Color(new_a, new_a, new_a))
```

### 6.7 `_apply_layer_depths()`

```gdscript
func _apply_layer_depths(depth_img: Image, w: int, h: int) -> void:
    # layers 已按 z_offset 从远到近排序，从近到远写入（近的覆盖远的）
    for i in range(layers.size() - 1, -1, -1):
        var l: Dictionary = layers[i]
        var layer_depth: Image = _layer_depth_images.get(l["id"])
        var layer_base: Image = _layer_base_images.get(l["id"])
        if layer_depth == null or layer_base == null:
            continue
        if layer_depth.get_size() != Vector2i(w, h):
            layer_depth = layer_depth.duplicate()
            layer_depth.resize(w, h, Image.INTERPOLATE_LANCZOS)
        if layer_base.get_size() != Vector2i(w, h):
            layer_base = layer_base.duplicate()
            layer_base.resize(w, h, Image.INTERPOLATE_LANCZOS)

        var z_base: float = l.get("z_offset", 0.0)
        # 将 z_offset 映射到 0~1 深度修正值
        # z_offset 越大(越靠近镜头)，深度值越大
        var z_depth_bias: float = clampf(z_base * 0.15, 0.0, 1.0)

        for y in range(h):
            for x in range(w):
                var base_px: Color = layer_base.get_pixel(x, y)
                if base_px.a < 0.05:
                    continue  # 透明像素穿透
                var raw_d: float = layer_depth.get_pixel(x, y).r
                var adjusted_d: float = clampf(raw_d + z_depth_bias, 0.0, 1.0)
                depth_img.set_pixel(x, y, Color(adjusted_d, adjusted_d, adjusted_d))
```

### 6.8 合成底图生成（在有 layers 时）

当存在 layers 时，需要合成一张新的底图。在 `build_region_depth_map()` 之前调用：

```gdscript
func build_composite_base_image() -> void:
    if layers.is_empty():
        composite_base_image = null
        composite_base_texture = null
        return

    var img_w: int = base_image.get_width() if base_image else 0
    var img_h: int = base_image.get_height() if base_image else 0
    if img_w == 0 or img_h == 0:
        return

    # 从底层(base_image)开始，逐层向上合成
    var result: Image
    if base_image:
        result = base_image.duplicate()
    else:
        result = Image.create(img_w, img_h, false, Image.FORMAT_RGBA8)
        result.fill(Color(0, 0, 0, 0))

    for l in layers:
        var layer_img: Image = _layer_base_images.get(l["id"])
        if layer_img == null:
            continue
        if layer_img.get_size() != Vector2i(img_w, img_h):
            layer_img = layer_img.duplicate()
            layer_img.resize(img_w, img_h, Image.INTERPOLATE_LANCZOS)

        # 逐像素合成：上层不透明 → 覆盖；透明 → 保留下层
        for y in range(img_h):
            for x in range(img_w):
                var upper: Color = layer_img.get_pixel(x, y)
                if upper.a > 0.05:
                    var lower: Color = result.get_pixel(x, y)
                    # alpha 混合
                    var out_a: float = upper.a + lower.a * (1.0 - upper.a)
                    if out_a > 0.0:
                        var out_r: float = (upper.r * upper.a + lower.r * lower.a * (1.0 - upper.a)) / out_a
                        var out_g: float = (upper.g * upper.a + lower.g * lower.a * (1.0 - upper.a)) / out_a
                        var out_b: float = (upper.b * upper.a + lower.b * lower.a * (1.0 - upper.a)) / out_a
                        result.set_pixel(x, y, Color(out_r, out_g, out_b, out_a))

    composite_base_image = result
    composite_base_texture = ImageTexture.create_from_image(result)
```

### 6.9 `_smooth_region_boundaries()` / `_apply_raw_depth_fallback()` / `_rasterize_polygon()` / `_get_polygon_bounds()`

同上版方案，保持不变。这些辅助方法处理 polygon 光栅化、均值平滑滤波和 fallback 逻辑。

### 6.10 `unload_textures()` 清理

```gdscript
func unload_textures() -> void:
    # ... 原有清理 ...
    region_depth_image = null
    region_depth_texture = null
    absorption_image = null
    absorption_texture = null
    composite_base_image = null
    composite_base_texture = null
    _mask_textures.clear()
    _layer_base_images.clear()
    _layer_depth_images.clear()
    _region_dirty = true
    polygon_regions.clear()
    mask_regions.clear()
    layers.clear()
    region_config = {}
```

---

## 七、Shader 修改细节

### 7.1 新增 Uniform

```glsl
uniform bool use_region_depth = false;
uniform sampler2D region_depth_texture : filter_linear, repeat_disable;
```

### 7.2 统一深度采样函数

```glsl
float get_depth(vec2 uv) {
    if (use_region_depth) {
        float region_d = texture(region_depth_texture, uv).r;
        if (region_d < 0.001) {
            return texture(depth_texture, uv).r;
        }
        return region_d;
    }
    return texture(depth_texture, uv).r;
}
```

### 7.3 替换 POM / 照明中的深度采样

所有 `texture(depth_texture, uv).r` 替换为 `get_depth(uv)`。

---

## 八、CameraViewer 修改细节

### 8.1 R 键切换

```gdscript
KEY_R:
    _toggle_region_depth()
    return true
```

### 8.2 `_toggle_region_depth()`

```gdscript
func _toggle_region_depth() -> void:
    var cam: SecurityCameraFeed = _get_current_camera()
    if cam == null or not cam.use_region_depth:
        return
    cam.use_region_depth = not cam.use_region_depth
    var status: String = "REGION DEPTH" if cam.use_region_depth else "PER-PIXEL DEPTH"
    if main:
        main.append_output("[color=" + main.T.info_hex + "]深度模式切换: " + status + "[/color]\n", false)
    if main.path_label:
        main.path_label.text = "深度模式: " + status
```

### 8.3 `_update_shader_params()` 透传

```gdscript
# ★ Region Depth
mat.set_shader_parameter("use_region_depth", cam.use_region_depth)
if cam.use_region_depth and cam.region_depth_texture:
    mat.set_shader_parameter("region_depth_texture", cam.region_depth_texture)

# 如果有合成底图，替换 base_texture
if cam.composite_base_texture:
    mat.set_shader_parameter("base_texture", cam.composite_base_texture)
```

### 8.4 UI 指示 + 操作提示

```gdscript
# 深度模式指示
if cam.use_region_depth:
    canvas_node.draw_string(font, Vector2(margin, bottom_y - 14), "DEPTH: REGION",
        HORIZONTAL_ALIGNMENT_LEFT, -1, small_size, Color(0.3, 0.8, 1.0, 0.8))

# 操作提示
if cam and cam.use_region_depth:
    help_text = "←→↑↓ 平移  [/] 缩放  TAB 切换  F 照明  R 深度  Q 退出"
```

---

## 九、CameraManager 修改细节

### 9.1 `load_camera_textures()` 扩展

```gdscript
func load_camera_textures(camera_id: String) -> void:
    var cam: SecurityCameraFeed = get_camera(camera_id)
    if cam:
        cam.load_textures(_load_image_func())
        # 如果有 layers，触发底图合成
        if not cam.layers.is_empty():
            cam.build_composite_base_image()
```

### 9.2 存档扩展

同原方案，保存 `region_depth_enabled` 状态。

---

## 十、测试与验证

### 10.1 验证清单

| # | 测试项 | 预期结果 |
|---|---|---|
| 1 | 无 region config | 行为完全不变 |
| 2 | 只有 polygons | Polygon 光栅化 + 平滑正确 |
| 3 | 只有 masks | Mask PNG 加载 + alpha 混合正确 |
| 4 | masks + polygons | Mask 覆盖 polygon（高优先级） |
| 5 | layers | 独立底图合成 + 独立深度偏移正确 |
| 6 | 三者同时使用 | 优先级链正确（layer > mask > polygon > fallback） |
| 7 | R 键切换 | region depth ↔ per-pixel depth 运行时切换 |
| 8 | Mask 渐变过渡 | 透明度边缘过渡自然，无硬边 |
| 9 | Layer 透明穿透 | 透明像素正确透到底层 |
| 10 | 照明 + region depth | 灯光衰减随 ref_distance 偏移 |
| 11 | 存档/读档 | 切换状态保存恢复 |

### 10.2 测试场景建议

| 场景 | polygons | masks | layers | 说明 |
|---|---|---|---|---|
| 简单走廊 | 3~5 个 | 0 | 0 | 验证 polygon 基本功能 |
| 户外风景 | 0 | 4~5 张 | 0 | 验证 mask PNG 复杂形状 |
| 有独立物体 | 2~3 个 | 0 | 1~2 个 | 验证 layer 合成 |
| 全功能 | 2 个 | 3 张 | 1 个 | 验证优先级链 |

---

## 十一、实现顺序（推荐）

| 步骤 | 文件 | 工作量 | 依赖 |
|---|---|---|---|
| 1. 定义 region config 字段 + `load_from_dict` 解析 | `camera_feed.gd` | 小 | 无 |
| 2. 实现 polygon 光栅化 + 平滑 + fallback | `camera_feed.gd` | 中 | Step 1 |
| 3. 实现 mask PNG 加载 + 写入 | `camera_feed.gd` | 中 | Step 2 |
| 4. 实现 layer 加载 + 底图合成 + 深度偏移 | `camera_feed.gd` | 中 | Step 3 |
| 5. Shader: 新增 uniforms + `get_depth()` | `camera_effect.gdshader` | 小 | 无 |
| 6. CameraViewer: R 键 + UI + shader 透传 | `camera_viewer.gd` | 小 | Step 2~5 |
| 7. CameraManager: 触发合成 + 存档 | `camera_manager.gd` | 小 | Step 4 |
| 8. 文档更新 | 2 个文档 | 小 | 全部 |

**总估算**：中等，核心逻辑集中在 `camera_feed.gd`（约 +350 行）

---

## 十二、备选/扩展方向

| 方向 | 说明 | 何时需要 |
|---|---|---|
| **AI 自动区域分割** | SAM/MaskFormer 自动生成 mask PNG | 大量场景批量处理 |
| **动态层** | Layer 位置/深度随时间变化 | 动画/剧情需要 |
| **独立层 POM** | 每层在 GPU 独立做 POM 再合成 | 追求最高视差真实感 |
| **可视化编辑器** | Canvas 上绘制 polygon + 导入 mask 预览 | 内容制作效率需求 |
