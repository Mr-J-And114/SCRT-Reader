# Radio System Refactoring Plan

## 概述
将 radio 从 vdisc 专属功能重构为桌面模式独立功能，使用 `data/radio/` 文件夹管理信号定义和资源，支持触发器动态修改。

---

## 第一步：创建 RadioDataManager（新文件）

**新文件**: `SCRT/radio/radio_data_manager.gd`

负责管理 `data/radio/` 文件夹下的所有 radio JSON 定义文件和资源文件。

```gdscript
class_name RadioDataManager extends RefCounted
```

核心职责：
- `scan_radio_folder()` — 扫描 `data/radio/` 下所有 `.json` 文件，解析为 RadioSignal
- `save_signal_definition(id, data)` — 写入/更新单个信号的 JSON 文件
- `delete_signal_definition(id)` — 删除信号 JSON 文件
- `import_from_vdisc(fs, signal_ids)` — 从 vdisc 虚拟文件系统复制信号定义和资源到 `data/radio/`
- `set_signal_visible(id, visible)` — 修改信号 JSON 的 `visible` 字段
- `update_signal_field(id, field, value)` — 修改信号 JSON 的任意字段
- `get_radio_data_path()` — 返回 `data/radio/` 的实际路径（编辑器 vs 导出）

### JSON 信号定义格式
每个信号一个 JSON 文件，如 `data/radio/weather_broadcast.json`：
```json
{
  "id": "weather_broadcast",
  "type": "audio",
  "frequency": 162.55,
  "band": "VHF",
  "azimuth": 180,
  "elevation": 10,
  "tolerance_freq": 0.1,
  "tolerance_dir": 30,
  "content_file": "weather_day1.ogg",
  "label": "天气广播",
  "visible": true,
  "loop": true
}
```

- `visible` 字段（新增）：`false` 时信号不会被加载到 radio_signal_manager
- `content_file` 相对于 `data/radio/` 文件夹
- 音频/图片等资源文件直接放在 `data/radio/` 或其子文件夹

---

## 第二步：修改 RadioConfigParser

在 `radio_config_parser.gd` 中新增：
- `static func parse_signal_from_json_file(path: String) -> RadioSignal` — 从单个 JSON 文件解析信号
- `static func parse_local_signals(radio_dir: String) -> Array[RadioSignal]` — 扫描目录解析所有可见信号
- 资源文件加载：从本地文件系统（而非 vdisc 虚拟 fs）加载 content_file

---

## 第三步：修改 RadioSignalManager

在 `radio_signal_manager.gd` 中新增：
- `load_local_signals(radio_dir: String)` — 调用 parser 加载本地信号，替代/补充 vdisc 信号
- `reload_signals()` — 重新扫描并加载（触发器修改后调用）
- `add_signal(sig: RadioSignal)` — 动态添加单个信号
- `remove_signal(id: String)` — 动态移除单个信号

---

## 第四步：修改 RadioReceiver

在 `radio_receiver.gd` 中：
- 新增 `load_local_signals()` — 从 `data/radio/` 加载信号
- 修改 `open()` — 无论是否有 vdisc，都从本地文件夹加载信号
- 新增 `reload_signals()` — 供触发器调用，热重载信号列表

---

## 第五步：修改 CommandHandler — 将 radio 从 disc 命令移到 desktop 命令

在 `command_handler.gd` 中：
- 将 `"radio": _cmd_radio` 从 `disc_commands` 移到 `desktop_commands`
- 从 `disc_commands` 中移除 `"radio"`
- 修改 `_cmd_radio()` — 不再检查 vdisc 信号，改为检查本地信号
  ```gdscript
  func _cmd_radio(_args: Array = []) -> void:
      if main.radio_receiver == null:
          main.append_output("[color=" + T.error_hex + "]无线电模块未初始化。[/color]\n", false)
          return
      main.radio_receiver.load_local_signals()
      if not main.radio_receiver.has_signals():
          main.append_output("[color=" + T.muted_hex + "]未检测到可用无线电信号。[/color]\n", false)
          return
      main.append_output("[color=" + T.muted_hex + "]正在启动无线电接收器...[/color]\n", false)
      main.open_radio_receiver()
  ```

---

## 第六步：新增触发器动作 — TriggerSystem

在 `trigger_system.gd` 的 `_exec_single()` 中新增以下动作：

### 6a: `radio_import` — 从 vdisc 导入信号定义和资源
```
"radio_import": _act_radio_import(param)
```
参数格式：`radio_import:signal_id` 或 `radio_import:*`（全部）
- 从当前 vdisc 的 manifest/fs 中提取 radio 信号定义
- 将 JSON 定义写入 `data/radio/signal_id.json`
- 将关联资源文件（音频、图片等）复制到 `data/radio/`

### 6b: `radio_visible` — 设置信号可见性
```
"radio_visible": _act_radio_visible(param)
```
参数格式：`radio_visible:signal_id:true` 或 `radio_visible:signal_id:false`
- 修改 `data/radio/signal_id.json` 的 `visible` 字段

### 6c: `radio_update` — 修改信号字段
```
"radio_update": _act_radio_update(param)
```
参数格式：`radio_update:signal_id:field=value`
例如：`radio_update:weather:content_file=weather_day2.ogg`
- 修改指定信号 JSON 的字段值
- 适用于天气广播等动态内容更新

### 6d: `radio_reload` — 热重载信号
```
"radio_reload": _act_radio_reload()
```
- 触发 radio_receiver 重新扫描 `data/radio/` 并重载信号列表
- 如果 radio 当前打开，立即刷新

---

## 第七步：修改 DiscManager

在 `disc_manager.gd` 中：
- `load_story()` — 不再自动加载 radio 信号到 radio_receiver
- 保留 vdisc 中的 radio_signals 数据供 `radio_import` 触发器使用
- `unload_story()` — 不再关闭 radio（radio 现在独立于 vdisc）
- Save/Load 仍保存 radio 发现状态，但改为保存到独立文件而非 vdisc save

---

## 第八步：初始化流程修改

在 `main.gd` 中：
- `_ready()` 创建 RadioDataManager，注入到 radio_receiver
- radio_receiver 在 setup 时自动扫描 `data/radio/` 加载初始信号
- 不再依赖 disc_manager 提供 radio 数据

---

## 第九步：创建 data/radio/ 目录结构

```
SCRT/data/radio/           ← 新建目录
  README.txt               ← 简要说明格式（可选）
```

运行时自动创建（如不存在）。

---

## 文件变更清单

| 文件 | 操作 |
|---|---|
| `SCRT/radio/radio_data_manager.gd` | **新建** — 本地文件管理 |
| `SCRT/radio/radio_config_parser.gd` | **修改** — 新增本地 JSON 解析 |
| `SCRT/radio/radio_signal_manager.gd` | **修改** — 新增本地信号加载/热重载 |
| `SCRT/radio/radio_receiver.gd` | **修改** — 本地信号加载、reload 支持 |
| `SCRT/scripts/command_handler.gd` | **修改** — radio 命令移至 desktop |
| `SCRT/scripts/trigger_system.gd` | **修改** — 新增 4 个 radio 触发器动作 |
| `SCRT/scripts/disc_manager.gd` | **修改** — 解耦 radio 加载 |
| `SCRT/scripts/main.gd` | **修改** — RadioDataManager 初始化 |
| `SCRT/radio/CLAUDE.md` | **修改** — 更新文档 |
| `SCRT/data/radio/` | **新建** — 目录 |

---

## 向后兼容

- 现有 vdisc 中的 `radio_signals` 仍可工作，但需要通过 `radio_import` 触发器显式导入到 `data/radio/`
- 故事包作者可以在 manifest 的 triggers 中配置 `radio_import:*` 来在加载时自动导入
- 旧版 `signals.cfg` 格式同样支持导入
