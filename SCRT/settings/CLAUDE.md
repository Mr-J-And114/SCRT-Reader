# settings/ — 设置系统 (Settings System)

> 上级文档：[/CLAUDE.md](/CLAUDE.md)
> 新增设置类别或修改 API 后请同步更新本文件。

注册式设置系统，支持自动 TUI 渲染界面、JSON 持久化和设置变更回调。
玩家通过 `settings` 或 `set` 命令打开设置界面。

## 文件列表

| 文件 | 行数 | 用途 |
|---|---|---|
| settings_manager.gd | 903 | 核心管理器：注册/读写/通知/TUI 渲染/导入导出 |
| settings_registry.gd | 225 | 内置设置定义：所有默认分类和设置项的静态注册 |
| settings_storage.gd | 165 | JSON 持久化后端：全局 + 用户级存储，版本迁移 |

## 架构

```
SettingsRegistry（静态默认值定义）
    ↓ 启动时注册
SettingsManager（运行时管理）
    ├─ 读写设置值
    ├─ 变更通知（信号 + 回调）
    └─ TUI 界面渲染
    ↓ 持久化
SettingsStorage（磁盘存储）
    ├─ _settings_global.json（全局共享）
    └─ saves/{user}/settings.json（用户独立）
```

## 内置设置分类

| ID | 显示名称 | 排序 | 包含的设置项示例 |
|---|---|---|---|
| display | 显示设置 | 10 | CRT 效果强度、扫描线、弯曲度 |
| audio | 音频设置 | 20 | 主音量、环境音、音效音量 |
| effect | 效果设置 | 30 | 效果等级 (FULL/MILD/OFF)、光敏模式 |
| terminal | 终端设置 | 40 | 打字速度、进度条速度 |
| comm | 通讯设置 | 50 | 对话前清屏 (clear_before_dialogue) |

## 关键 API

| 方法 | 说明 |
|---|---|
| `register_category(cat_def)` | 注册分类：`{id, display_name, icon, order}` |
| `register_setting(def)` | 注册设置项定义（含默认值、类型、范围等） |
| `get_value(key)` | 获取设置值 |
| `set_value(key, value)` | 设置值并触发回调 |
| `register_apply(key, callback)` | 注册值变更时的回调函数 |

**信号**：`setting_changed(key: String, old_value: Variant, new_value: Variant)`

## 重要陷阱

- 设置键格式为 `"category.key"`（点分隔），如 `"audio.master_volume"`
- `settings_registry` 定义所有内置默认值；故事包**不能**添加新设置
- 存储路径：`_settings_global.json`（共享）+ 每用户 `settings.json`
- 向后兼容迁移：自动转换旧版 `theme.cfg`、`audio.cfg`、`effect_settings.cfg`
