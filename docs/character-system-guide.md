# 角色系统指南 (Character System Guide)

本文档说明如何在 SCRT-Reader 中添加、修改角色，以及如何在对话 JSON 中制作角色动画效果。

---

## 目录

1. [架构概览](#1-架构概览)
2. [添加新角色](#2-添加新角色)
3. [素材规范](#3-素材规范)
4. [修改已有角色](#4-修改已有角色)
5. [对话 JSON 中的角色控制标记](#5-对话-json-中的角色控制标记)
6. [服装系统](#6-服装系统)
7. [动画效果](#7-动画效果)
8. [模组兼容](#8-模组兼容)
9. [API 参考](#9-api-参考)

---

## 1. 架构概览

角色系统由以下模块组成：

```
CharacterRegistry           — 角色注册中心（创建、查询、生命周期）
  ├─ CharacterAssetLibrary  — 素材库（AssetProfile 配置 + 纹理加载）
  │    ├─ AssetProfile      — 每个角色的素材定义（图层、眼睛、嘴型、服装、动作）
  │    └─ CharacterTextures — 已加载的纹理缓存
  ├─ CommCharacter          — 角色数据模型（身份信息 + 语音配置）
  │    └─ CharacterAnimator — 动画控制器（嘴型、眨眼、动作帧、图层覆盖）
  └─ 来源标识: BUILTIN / DISC / MOD
```

### 数据流

```
AssetProfile (素材配置)
    ↓ register_profile()
CharacterAssetLibrary (加载纹理)
    ↓ load_character_assets()
CharacterTextures (纹理缓存)
    ↓ bind_assets()
CharacterAnimator (驱动动画)
    ↓ get_render_state()
CommUI (渲染到屏幕)
```

---

## 2. 添加新角色

### 方法 A：通过代码添加内置角色

**步骤 1：准备素材文件**

将角色素材放入 `SCRT/images/character/<角色名>/` 目录。

**步骤 2：创建 AssetProfile**

在 `character_asset_library.gd` 中添加工厂方法：

```gdscript
static func create_my_char_profile() -> AssetProfile:
    var p := AssetProfile.new()
    p.base_dir = "res://images/character/my_char/"
    p.mode = "layered"  # 或 "static" / "minimal"
    p.layer_order = ["body", "head", "eye_L", "eye_R", "mouth", "hair", "accessory"]
    p.layer_files = {
        "body": "body.png",
        "head": "head.png",
        "hair": "hair.png",
        "accessory": "hat.png",
    }
    p.eye_files = {
        "eye_L_open": "eye-L-open.png",
        "eye_L_half": "eye-L-half.png",
        "eye_L_close": "eye-L-close.png",
        "eye_R_open": "eye-R-open.png",
        "eye_R_half": "eye-R-half.png",
        "eye_R_close": "eye-R-close.png",
    }
    p.mouth_files = {
        "MBP": "mouth-1-MBP.png",
        "slight": "mouth-2-slight.png",
        "A": "mouth-3-A.png",
        "EI": "mouth-4-EI.png",
        "O": "mouth-5-O.png",
        "UW": "mouth-6-UW.png",
        "FV": "mouth-7-FV.png",
        "LNTS": "mouth-8-LNTS.png",
    }
    return p
```

**步骤 3：在 CharacterRegistry 中注册**

在 `character_registry.gd` 中添加 setup 方法：

```gdscript
func setup_my_char() -> void:
    var profile := CharacterAssetLibrary.create_my_char_profile()
    _asset_library.register_profile("my_char", profile)
    if _characters.has("my_char"):
        _characters["my_char"].init_from_asset_library(_asset_library)
```

**步骤 4：在 CommManager 初始化时调用**

在 `comm_manager.gd` 的 `_load_tutorial_json()` 末尾添加：

```gdscript
_registry.setup_my_char()
```

**步骤 5：在教程/对话 JSON 中定义角色信息**

```json
{
  "comm_characters": {
    "my_char": {
      "name": "Dr. Smith",
      "title": "Research Lead",
      "sprite_mode": "layered",
      "portrait_position": "right",
      "name_color": "#00aaff",
      "voice": {
        "tone": "sine",
        "base_pitch": 0.8,
        "pitch_variance": 0.1,
        "speed": "normal"
      }
    }
  }
}
```

### 方法 B：通过故事包 (.scp) 添加角色

在故事包的 `manifest.json` 中定义：

```json
{
  "comm_characters": {
    "agent_x": {
      "name": "AGENT-X",
      "title": "Field Operative",
      "sprite_mode": "static",
      "portrait": "characters/agent_x/portrait.png",
      "portrait_position": "left",
      "voice": {
        "tone": "square",
        "base_pitch": 1.2
      }
    }
  }
}
```

对于分层角色，可以在故事包中提供 `asset_profile`：

```json
{
  "comm_characters": {
    "agent_x": {
      "name": "AGENT-X",
      "asset_profile": {
        "base_dir": "characters/agent_x/",
        "mode": "layered",
        "layer_order": ["body", "head", "eye_L", "eye_R", "mouth", "hair"],
        "layer_files": {
          "body": "body.png",
          "head": "head.png",
          "hair": "hair.png"
        },
        "eye_files": {
          "eye_L_open": "eye-L-open.png",
          "eye_L_half": "eye-L-half.png",
          "eye_L_close": "eye-L-close.png",
          "eye_R_open": "eye-R-open.png",
          "eye_R_half": "eye-R-half.png",
          "eye_R_close": "eye-R-close.png"
        },
        "mouth_files": {
          "MBP": "mouth-closed.png",
          "slight": "mouth-slight.png",
          "A": "mouth-A.png",
          "EI": "mouth-EI.png",
          "O": "mouth-O.png",
          "UW": "mouth-UW.png",
          "FV": "mouth-FV.png",
          "LNTS": "mouth-LNTS.png"
        }
      }
    }
  }
}
```

### 方法 C：三种素材模式选择

| 模式 | 说明 | 所需素材 |
|------|------|----------|
| `layered` | 完整分层合成 | 多张图层 + 眼睛状态 + 嘴型音素 |
| `static` | 单张静态头像 | 1张头像 + 可选4张嘴型帧 |
| `minimal` | 纯文字无图 | 无需任何图片 |

---

## 3. 素材规范

### 分层模式图层说明

所有图层尺寸必须一致（推荐 1216×1803 px，即 AVA 的原始尺寸）。
图层从底到顶按 `layer_order` 数组顺序叠加渲染。

```
layer_order 示例:
["body", "head", "nose", "eye_L", "eye_R", "mouth", "hair", "glasses"]
 ↑底层                                                        ↑顶层
```

### 眼睛状态命名

每只眼睛需要 3 个状态：
- `open` — 正常睁眼
- `half` — 半闭（用于眨眼过渡）
- `close` — 完全闭眼

文件命名格式：`eye_{L|R}_{open|half|close}`

### 嘴型音素系统（8种）

| Key | 说明 | 典型口型 |
|-----|------|----------|
| `MBP` | 闭嘴 (M/B/P) | 双唇闭合 |
| `slight` | 微张 | 轻微张开 |
| `A` | 大开 (A/啊) | 嘴巴大张 |
| `EI` | 前展 (E/I/诶) | 嘴角横向拉伸 |
| `O` | 圆唇 (O/噢) | 嘴唇圆形 |
| `UW` | 窄圆 (U/W/呜) | 嘴唇小圆 |
| `FV` | 齿唇 (F/V) | 上齿咬下唇 |
| `LNTS` | 舌齿 (L/N/T/S) | 舌头顶上齿 |

### 静态模式嘴型（4帧简易版）

| Key | 说明 |
|-----|------|
| `closed` | 闭嘴 |
| `half` | 半张 |
| `open` | 张开 |
| `wide` | 大张 |

---

## 4. 修改已有角色

### 添加新图层

1. 在 AssetProfile 的 `layer_order` 中插入新图层名
2. 在 `layer_files` 中添加对应文件映射
3. 准备图片文件（尺寸与其他图层一致）

示例：给 AVA 添加帽子图层
```gdscript
# 在 create_ava_profile() 中:
p.layer_order.append("hat")  # 加到最顶层
p.layer_files["hat"] = "ava-hat.png"
```

### 添加新动作帧

1. 在 AssetProfile 的 `action_files` 中添加动作定义
2. 准备动作帧图片序列

```gdscript
p.action_files = {
    "nod": ["nod-1.png", "nod-2.png", "nod-3.png", "nod-2.png", "nod-1.png"],
    "wave": ["wave-1.png", "wave-2.png", "wave-3.png"],
}
```

### 添加服装变体

```gdscript
p.costumes = {
    "lab_coat": {
        "body": "body-labcoat.png",     # 替换 body 图层
        "glasses": null,                  # 隐藏 glasses 图层
    },
    "casual": {
        "body": "body-casual.png",
        "hair": "hair-down.png",
    },
}
```

---

## 5. 对话 JSON 中的角色控制标记

### 基础标记

```json
{
  "character": "ava",          // 切换当前说话角色
  "text": "Hello there!",     // 对话文本
  "expression": "happy",      // 设置表情状态（预留）
  "action": "nod"             // 播放动作帧序列
}
```

### 图层覆盖（临时修改角色外观）

```json
{
  "character": "ava",
  "text": "*winks*",
  "layer_override": {
    "eye_L": "eye_L_close",    // 左眼闭合
    "eye_R": "eye_R_open"      // 右眼保持睁开
  },
  "layer_override_duration": 3.0   // 3秒后自动恢复（省略则永久）
}
```

隐藏图层：
```json
{
  "layer_override": {
    "glasses": "hide"         // 隐藏眼镜图层
  }
}
```

### 清除覆盖

```json
{
  "text": "Back to normal.",
  "clear_overrides": true      // 清除所有临时覆盖
}
```

### 服装切换

```json
{
  "text": "Let me change into something more comfortable.",
  "costume": "casual"          // 切换到 casual 服装
}
```

恢复默认服装：
```json
{
  "costume": ""                // 空字符串 = 恢复默认
}
```

### 预设动画效果

```json
{
  "text": "*winks playfully*",
  "anim_effect": "wink_left:2.0"    // 左眼眨眼，持续2秒
}
```

可用的预设效果：

| 效果名 | 说明 | 示例 |
|--------|------|------|
| `wink_left` | 左眼眨眼 | `"wink_left:2.0"` |
| `wink_right` | 右眼眨眼 | `"wink_right:3.0"` |
| `eyes_closed` | 双眼闭合 | `"eyes_closed:1.5"` |
| `surprised` | 惊讶（双眼大睁） | `"surprised:2.0"` |

格式：`"效果名:持续秒数"`，持续时间可省略（默认 2.0 秒）。

### 完整示例

```json
{
  "comm_dialogues": {
    "demo_expressions": {
      "description": "表情演示",
      "callable": true,
      "repeatable": true,
      "lines": [
        {
          "character": "ava",
          "text": "Let me show you some expressions!",
          "display_mode": "meeting",
          "meeting_slot": "center"
        },
        {
          "character": "ava",
          "text": "*winks*",
          "anim_effect": "wink_left:2.0"
        },
        {
          "character": "ava",
          "text": "Surprised!",
          "anim_effect": "surprised:1.5"
        },
        {
          "character": "ava",
          "text": "Let me put on my lab coat...",
          "costume": "lab_coat"
        },
        {
          "character": "ava",
          "text": "Custom eye control:",
          "layer_override": {
            "eye_L": "eye_L_close",
            "eye_R": "eye_R_open"
          },
          "layer_override_duration": 5.0
        },
        {
          "character": "ava",
          "text": "And back to normal.",
          "clear_overrides": true,
          "costume": ""
        }
      ]
    }
  }
}
```

---

## 6. 服装系统

服装（Costume）允许批量替换角色的多个图层纹理。

### 定义

在 AssetProfile 中定义：
```gdscript
p.costumes = {
    "winter": {
        "body": "body-winter-coat.png",
        "hair": "hair-with-hat.png",
        "accessory": "scarf.png",
    },
}
```

或在故事包 manifest 的 `asset_profile.costumes` 中定义。

### 优先级

纹理查找优先级（从高到低）：
1. **图层覆盖 (Layer Override)** — 临时效果，最高优先级
2. **服装变体 (Costume)** — 批量替换
3. **默认图层** — AssetProfile 中的基础纹理

### 注意事项

- 服装中 `null` 值表示隐藏该图层
- 服装只影响 `layer_files` 中定义的静态图层
- 眼睛和嘴型不受服装影响（由动画系统控制）
- 切换服装为空字符串 `""` 恢复默认外观

---

## 7. 动画效果

### 自动动画（无需配置）

- **嘴型动画**：说话时自动在嘴型序列中循环
  - 分层模式：8 音素序列 `[MBP, slight, A, EI, O, UW, slight, MBP]`
  - 静态模式：4 帧序列 `[closed, half, open, half]`
  - 切换间隔：0.08 秒，20% 概率跳帧增加自然感

- **眨眼动画**：自动随机眨眼
  - 平均间隔：3.5 秒（随机 2.0-5.0 秒）
  - 4 阶段过渡：open → half → close → half → open
  - 如果有眼睛相关的图层覆盖，自动暂停眨眼

### 自定义临时动画

通过 `layer_override` + `layer_override_duration` 组合实现：

```json
{
  "text": "单独睁一只眼闭一只眼",
  "layer_override": {
    "eye_L": "eye_L_close",
    "eye_R": "eye_R_open"
  },
  "layer_override_duration": 5.0
}
```

### 通过代码添加自定义动画

在 `CharacterAnimator` 中添加新的预设方法：

```gdscript
func play_my_custom_anim(duration: float = 2.0) -> String:
    return add_layer_override({
        "eye_L": "eye_L_half",
        "eye_R": "eye_R_half",
    }, duration)
```

然后在 `CommManager._play_anim_effect()` 中注册：

```gdscript
"my_custom":
    _active_character.animator.play_my_custom_anim(duration)
```

---

## 8. 模组兼容

### 模组注册新角色

```gdscript
# 在 ModBase 的 _on_enable() 中:
var config = {
    "name": "Agent Zero",
    "title": "Infiltration Specialist",
    "sprite_mode": "layered",
    "voice": {"tone": "noise", "base_pitch": 0.7},
    "asset_profile": {
        "base_dir": "res://mods/my_mod/characters/zero/",
        "mode": "layered",
        "layer_order": ["body", "head", "eye_L", "eye_R", "mouth"],
        "layer_files": {"body": "body.png", "head": "head.png"},
        "eye_files": {
            "eye_L_open": "eye-L-open.png",
            "eye_L_half": "eye-L-half.png",
            "eye_L_close": "eye-L-close.png",
            "eye_R_open": "eye-R-open.png",
            "eye_R_half": "eye-R-half.png",
            "eye_R_close": "eye-R-close.png",
        },
        "mouth_files": {
            "MBP": "m-closed.png",
            "slight": "m-slight.png",
            "A": "m-A.png",
            "EI": "m-EI.png",
            "O": "m-O.png",
            "UW": "m-UW.png",
            "FV": "m-FV.png",
            "LNTS": "m-LNTS.png",
        },
    }
}
api.comm_register_character("zero", config)
```

### 模组为内置角色添加服装

```gdscript
var profile_data = {
    "costumes": {
        "mod_outfit": {
            "body": "res://mods/my_mod/ava-body-alt.png",
            "glasses": null,
        }
    }
}
# 通过 registry 注册额外素材
var registry = main.comm_mgr.get_registry()
registry.register_mod_asset_profile("ava", profile_data)
```

### 模组注销

```gdscript
# 在 ModBase 的 _on_disable() 中:
api.comm_unregister_character("zero")
```

---

## 9. API 参考

### CharacterAssetLibrary

| 方法 | 说明 |
|------|------|
| `register_profile(id, profile)` | 注册素材配置 |
| `register_profile_from_dict(id, data)` | 从 Dictionary 注册 |
| `load_character_assets(id) → CharacterTextures` | 加载所有纹理 |
| `get_textures(id) → CharacterTextures` | 获取已加载纹理 |
| `get_costume_names(id) → Array[String]` | 获取服装列表 |
| `get_action_names(id) → Array[String]` | 获取动作列表 |
| `get_layer_order(id) → Array[String]` | 获取图层顺序 |
| `create_ava_profile() → AssetProfile` | 内置 AVA profile |
| `create_researcher_profile() → AssetProfile` | 内置 Researcher profile |

### CharacterAnimator

| 方法 | 说明 |
|------|------|
| `bind_assets(profile, textures)` | 绑定素材 |
| `start_speaking()` / `stop_speaking()` | 控制说话状态 |
| `set_expression(id)` | 设置表情 |
| `play_action(id, callback?)` | 播放动作帧 |
| `set_costume(name)` | 切换服装（空=默认） |
| `add_layer_override(changes, duration?, callback?)` | 添加图层覆盖 |
| `remove_layer_override(id)` | 移除图层覆盖 |
| `clear_all_overrides()` | 清除所有覆盖 |
| `play_wink(side, duration?)` | 眨一只眼 |
| `play_eyes_closed(duration?)` | 双眼闭合 |
| `play_surprised(duration?)` | 惊讶表情 |
| `get_effective_layer_texture(layer)` | 获取有效纹理（含覆盖） |
| `get_render_state() → Dictionary` | 获取渲染状态 |

### CharacterRegistry

| 方法 | 说明 |
|------|------|
| `register_character(id, config, source)` | 注册角色 |
| `unregister_character(id)` | 注销角色 |
| `get_character(id) → CommCharacter` | 获取角色 |
| `has_character(id) → bool` | 检查是否存在 |
| `get_character_ids() → Array[String]` | 获取所有 ID |
| `load_disc_characters(data)` | 加载磁盘角色 |
| `unload_by_source(source)` | 按来源卸载 |
| `register_mod_character(id, config)` | 模组注册 |
| `register_mod_asset_profile(id, data)` | 模组素材扩展 |
| `setup_ava()` / `setup_researcher()` | 内置角色初始化 |

### CommCharacter (代理方法)

| 方法 | 说明 |
|------|------|
| `set_expression(id)` | → animator |
| `start_speaking()` / `stop_speaking()` | → animator |
| `play_action(id, callback?)` | → animator |
| `set_costume(name)` | → animator |
| `add_layer_override(changes, duration?, callback?)` | → animator |
| `play_wink(side, duration?)` | → animator |
| `get_render_state() → Dictionary` | 合并 animator + 本地缓存 |
