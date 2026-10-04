# Vdisc 解密系统 — 架构与接口（As-Built）

> 核查日期：2026-10-02。基于当前代码实际核查（非设计稿）。
> 范围：Vdisc 任务系统（下载→探索/编辑→判定→上交/归档）+ 关联的探索进度、Radio 无线电、Decode 密码解码。
> 上级文档：[/CLAUDE.md](/CLAUDE.md) ｜ 计划背景：[/docs/upgrade-plans/vdisc-task-system-plan.md](upgrade-plans/vdisc-task-system-plan.md) ｜ 手动测试：[/docs/upgrade-plans/vdisc-manual-test-plan.md](upgrade-plans/vdisc-manual-test-plan.md)
> 本文档描述现状；修改相关代码后请同步更新。

---

## 1. 系统定位

Vdisc 解密系统是"任务磁盘"玩法闭环：

```
角色邮件/号码发布任务
      │
      ▼
下载 .scp 磁盘到玩家个人任务箱（3 种途径）
      │
      ▼
load 加载为可编辑的工作副本（虚拟文件系统）
      │
      ▼
探索文件（已读进度）+ cp/mv/rm/mkfile 编辑（截留/塞垃圾）
      │
      ▼
submit <号码> 上交 → 判定（探索比例/必需文件/数量/体积）
      │   ├─ 达标 → 归档 submitted/ + 绩效 + flags（如有修改记 fake_pass）
      │   ├─ 不达标 → 保留磁盘，提示缺口
      │   └─ 发错角色 → 退回（保留）或没收 confiscated/（可重新下载，可能带绩效）
      ▼
scan 不再显示已归档盘；任务状态与归档记录永久保存在玩家账户
```

核心设计决策（已确认并实施）：
- 任务定义在 `data/main/manifest.json` 的 `vdisc_tasks` 段（与 `comm_dialogues` 并列）
- "解密比例" = 已读文件比例（不要求密文与文件绑定）
- 蒙混判定 = 数量 + 存在性（垃圾/重复文件凑数有效）
- 文件操作 = 终端命令（cp/mv/rm/mkfile），仅限个人任务副本
- 归档 = 仅记录（不支持重新加载查看），实体移动 + 玩家存档记录

---

## 2. 总体架构

### 2.1 模块图

```
                      ┌──────────────────────────────┐
                      │ command_handler.gd（命令层）  │
                      │ download / submit / cp/mv/rm  │
                      │ mkfile / vdisc / debug vdisc  │
                      └───────┬──────────────────────┘
                              │
     ┌────────────────────────┼───────────────────────────────┐
     ▼                        ▼                               ▼
┌─────────────┐      ┌─────────────────┐            ┌────────────────┐
│ mail_system │      │ dial_manager    │            │ VdiscTaskManager│
│ 附件链接     │      │ modem 下载       │            │  ★ 系统核心     │
│ mail download│─────▶│ on_modem_complete│──────────▶│ 任务状态/下载   │
└─────────────┘      └─────────────────┘            │ 弹窗/判定/上交  │
                                                     │ 修改记录/归档   │
                                                     └───┬──────┬─────┘
                                                         │      │
                              ┌──────────────────────────┘      └──────────┐
                              ▼                                            ▼
                    ┌──────────────────┐                         ┌─────────────────┐
                    │ DiscManager       │                         │ FileSystem       │
                    │ inbox 扫描/加载    │                         │ 工作副本(file_system)│
                    │ 个人任务盘标记     │                         │ origin/文件操作   │
                    └────────┬─────────┘                         └─────────────────┘
                             │
              ┌──────────────┼───────────────┬──────────────┐
              ▼              ▼               ▼              ▼
        ExploreViewer   user_manager    save_manager   performance/dialogue
        （进度口径一致）  (profile.json)  (saves/目录)    (绩效/flags)
```

### 2.2 关键数据流

| 阶段 | 数据路径 |
|---|---|
| 下载 | 邮件链接/modme URL/本地源 → `store_download()` 校验 → `saves/<user>/vdisc/inbox/<filename>.scp` |
| 登记 | `task_states[task_id] = {status:"downloaded", story_id, filename}` → profile.json |
| 加载 | `scan_stories()` 扫描 inbox → `load_story()` 解包 ZIP → 应用 `apply_modifications()` |
| 编辑 | `cp/mv/rm/mkfile` → FileSystem 内存树 + `record_path_change()` 写 patch |
| 上交 | `submit(number)` → `check_requirements()` → `_finish_task()` 移动实体 + 记录 → `scan_stories(true)` |
| 归档 | `saves/<user>/vdisc/submitted|confiscated/<filename>` + `archive[]` 记录 |

---

## 3. 磁盘获取（三条途径）

### 3.1 命令下载（meta 要素 / 本地联调）

```
download <任务ID>          # 桌面模式；任务 ID 如 demo_site19
```

实现 `command_handler.gd:950 _cmd_download` → `VdiscTaskManager.download_task()`（vdisc_task_manager.gd:267）。

- `download.url` 非空 → 真实 `HTTPRequest`（30 秒超时，≤95% 真实进度）
- `url` 为空 → 读共用源盘 `vdisc_dir/<filename>` 模拟分块传输（本地联调包）
- 下载弹窗实时显示；已存在同名副本时先弹"重新下载/保留"确认（Y/N）

### 3.2 邮件附件

两种入口，共用同一流程 `download_mail_attachment(mail_id)`（vdisc_task_manager.gd:334）：

| 入口 | 说明 |
|---|---|
| 邮件正文链接 | 渲染于 `mail_system.gd:664-665`，格式 `[下载 Vdisc 附件](vdisc://mail/<id>)` |
| 命令 | `mail download <邮件编号或ID>`（mail_system.gd:452-477 解析编号→ID） |

链接由 `main.gd:1835 _on_meta_clicked` 处理（`vdisc://mail/` 前缀 → `download_mail_attachment`）。下载弹窗覆盖在邮件上方，邮件不被关闭。

### 3.3 Modem 拨号

```
dial 9900-0002            # 号码来自任务定义的 download.number
```

- 任务加载时 `register_modem_numbers()`（vdisc_task_manager.gd:195）把 `download.number/filename/url/title` 注册进 `DialManager.register_system_modem()`
- 拨号下载完成 → `dial_manager.gd:658-659` 回调 `vdisc_task_mgr.on_modem_complete(filename, bytes)`（:353）
- 该入口保留拨号系统原有下载界面（无字符弹窗确认；重复拨号提示已有副本）

### 3.4 下载校验与原子性（`store_download`，:368）

1. 文件名安全检查（`_safe_filename`：非空、纯文件名、`.scp` 后缀、无 `..`）
2. 字节校验：≥4 字节且 `PK` 头（80/75）→ 是 ZIP
3. 解包读 `manifest.json` 提取 `story.id`；与任务 `story_id`（如配置）比对
4. 先写 `.download` 暂存文件，全部校验通过后才替换正式文件
5. 重下载/没收重领（`replace_existing` 或原状态 `confiscated`）：
   - 备份旧磁盘与旧存档到 `vdisc/replaced/<ticks>/`
   - 写空白 `fresh_progress.json`（防 `load_save` 回退迁移旧进度）
   - 若同故事盘正在加载则先 `eject_story()`
   - 清除该故事的 `modifications[story_id]`
6. 失败时逐步回滚（旧磁盘/旧存档恢复）

---

## 4. 存储布局

```
<游戏根>/saves/<用户名>/vdisc/          ← 玩家专属（_user_disc_dir）
├── inbox/            # 个人任务箱（领取的 .scp；scan 显示 [个人任务盘]）
├── submitted/        # 成功上交归档（仅记录用）
├── confiscated/      # 被没收归档
└── replaced/<ticks>/ # 重下载备份（旧 .scp + progress.json + fresh_progress.json）

<编辑器> res://vdisc/                   ← 共用源盘（开发用）
<导出版> <exe目录>/vdisc/               ← 共用源盘
```

- 玩家状态存于 `profile.json` 的 `vdisc_task_data` 字段（`_save_state()`，:222）：
  ```json
  "vdisc_task_data": {
    "tasks": { "<task_id>": {"status":"downloaded|submitted|confiscated", "story_id":"", "filename":"", "fake_pass":false, "finished_at":0} },
    "modifications": { "<story_id>": { "changed": { "/path": {"content":"", "origin":"", "binary_base64":""} }, "deleted": ["/path"] } },
    "archive": [ {"task_id":"", "filename":"", "result":"submitted|confiscated", "fake_pass":false, "day":0} ]
  }
  ```
- 同名归档防撞：已存在时加 `<unix时间戳>_` 前缀（`_finish_task`，:589）
- 共用源盘中的任务盘在 `scan_stories()` 中被跳过（vdisc_task_mgr 已知该 filename，:178-180），只有玩家副本可加载/上交

---

## 5. 任务定义（`data/main/manifest.json` → `vdisc_tasks`）

```json
"vdisc_tasks": {
  "demo_site19": {
    "title": "Vdisc 联调：Site-19 调查盘",
    "story_id": "site19_incident_0117_2",
    "giver": "kanda",
    "giver_number": "1001-0002",
    "download": {
      "number": "9900-0002",
      "filename": "test_story_V0.3.2_1.scp",
      "url": "",
      "mail_attachment": "MTEST-VDISC"
    },
    "requirements": {
      "min_read_percent": 20,
      "required_files": ["/reports/summary.txt"],
      "min_total_files": 8,
      "min_size_kb": 1
    },
    "on_success": {"score": "side:1", "flags": {"demo_site19_done": 1}},
    "on_fail": {"message": "调查盘仍缺少必要内容。"},
    "wrong_recipient": {
      "default": {"action": "return", "message": "收件人不符，磁盘已退回。"},
      "ava": {"action": "confiscate", "score": "main:1", "message": "磁盘已被 Ava 没收；可重新下载。"}
    }
  }
}
```

| 字段 | 说明 |
|---|---|
| `title` | 任务标题（弹窗/列表/vdisc 显示） |
| `story_id` | 磁盘 story.id 校验（store_download 比对；`get_task_for_story` 匹配） |
| `giver` / `giver_number` | 发布者与上交号码（号码须与 dial_manager 可解析） |
| `download.number/filename/url/mail_attachment` | 三种领取途径信息（均可选，filename 必填） |
| `requirements.min_read_percent` | 已读文件百分比下限（缺省 0） |
| `requirements.required_files` | 必需文件路径数组（存在性） |
| `requirements.min_total_files` | 可见且有权限文件数下限 |
| `requirements.min_size_kb` | 数据包总大小（KB）下限 |
| `on_success.score` | 绩效 `"类型:数量"`（main/daily/side） |
| `on_success.flags` | 成功后写入的剧情标记 |
| `on_success.dialogue` | 成功后触发的对话 ID（可空） |
| `on_fail.message` | 未达标提示文本（缺省"任务未达标，请继续探索。"） |
| `wrong_recipient.<role>` | `action: "return"/"confiscate"`、`score`、`message`；缺省 default |

任务定义来源：`main.gd:282-283 setup()` 时从 `res://data/main/manifest.json` 读取；`disc_manager.load_story()`（:342-343）加载磁盘时也会用该磁盘 manifest 的（空）段再调一次 `load_tasks_from_manifest`（幂等，不会清除已有定义）。

---

## 6. VdiscTaskManager 接口（scripts/vdisc_task_manager.gd，624 行）

### 6.1 生命周期与状态

```gdscript
class_name VdiscTaskManager
extends RefCounted

setup(p_main, p_fs, p_save_mgr, p_disc_mgr)   # main.gd:283 注入
load_tasks_from_manifest(manifest)            # 解析 vdisc_tasks + register_modem_numbers
load_player_state()                           # main.gd:561 登录后；从 profile.json 恢复三项状态
```

任务状态机（`task_states[task_id].status`）：

| 状态 | 含义 | 可领取 | 可编辑/上交 |
|---|---|---|---|
| `not_started` | 未领取 | ✅ | ❌ |
| `downloaded` | 已领取 | ✅（触发重下载确认） | ✅（仅个人副本） |
| `submitted` | 已上交 | ❌（拒绝，防重复奖励） | ❌ |
| `confiscated` | 已没收 | ✅（重置进度重新开始） | ❌ |

### 6.2 公开方法

| 方法 | 位置 | 说明 |
|---|---|---|
| `is_download_open() -> bool` | :25 | 下载弹窗是否打开（输入路由/全屏隔离判定） |
| `close_download() -> void` | :28 | 关闭弹窗（下载中/确认中无效；确认中视为"保留"） |
| `handle_download_input(event) -> void` | :38 | 弹窗按键：Y=重下载、N/Esc/Enter=保留、完成后 Enter/Esc=关闭 |
| `get_inbox_dir() -> String` | :240 | `saves/<user>/vdisc/inbox` |
| `get_task_for_filename(filename) -> String` | :247 | 按磁盘文件名反查任务 |
| `get_task_for_story(story_id) -> String` | :254 | 按 story.id / 已登记状态反查任务 |
| `get_task_status(task_id) -> String` | :264 | 读取状态 |
| `download_task(task_id) -> Dictionary` | :267 | **async**；三种确认/校验/存储全流程；返回 `{ok, message}` |
| `download_mail_attachment(mail_id) -> Dictionary` | :334 | **async**；邮件附件入口 |
| `has_mail_attachment(mail_id) -> bool` | :346 | 邮件是否有附件（邮件渲染用） |
| `on_modem_complete(filename, bytes) -> Dictionary` | :353 | 拨号下载完成回调；`{handled, ok, message}` |
| `store_download(task_id, bytes, replace_existing=false) -> Dictionary` | :368 | 校验+原子落盘+状态登记 |
| `apply_modifications(story_id) -> void` | :478 | 加载磁盘后应用玩家修改 patch |
| `record_path_change(story_id, path) -> void` | :490 | 编辑后记录变更（changed/deleted）；非任务盘忽略 |
| `get_progress_detail(story_id) -> Dictionary` | :513 | `{read, total, percent, size_kb}`（口径见 §8） |
| `check_requirements(task_id) -> Dictionary` | :526 | `{passed, missing[], detail}` |
| `submit(number) -> Dictionary` | :546 | 上交判定全流程（见 §9） |
| `get_task_list() -> Array[Dictionary]` | :619 | `[{id, title, status}]`（桌面 vdisc / debug list） |

### 6.3 下载弹窗（UI）

- 实现：`_open_download()`（:57）用 `CanvasLayer`（layer = CRTEffect 层 - 1）+ `RichTextLabel`
- 外框复用 `FileSystem.build_box()` 的 `╔═╗` 字符；进度条复用 `Typewriter.format_progress_bar()`（30 格 `█` 规则）
- 宽度 54 单元格自动换行（`_wrap_download_text`）；同帧渲染去重（`_last_download_render`）
- 状态文案：准备下载 → 下载中（真实 %/本地模拟步进）→ 校验保存 → 完成/失败/取消/已保留
- 重下载确认：`_confirm_redownload()`（:164）显示"是否重新下载 + 重置说明"，等待 Y/N 选择
- 输入拦截优先级：`main._input` 最前（main.gd:1254）；`is_terminal_covered()` 第一项（main.gd:1225）
- 后台输出隔离：`append_output()` 在覆盖期间暂存 `_deferred_terminal_output`，退出全部覆盖层后回放（main.gd:1244-1249、1507-1511）

---

## 7. 工作副本（FileSystem 扩展）

### 7.1 FSNode 扩展（scripts/file_system.gd）

```gdscript
class FSNode:
    var type: String      # "file" / "folder"
    var content: String
    var origin: String    # ★ original / copied / created（玩家操作来源标记）
```

### 7.2 文件操作 API（仅用于个人任务盘）

| 方法 | 位置 | 行为 |
|---|---|---|
| `create_file(path, content) -> bool` | :101 | 新建（origin=created）；父目录须存在且可写 |
| `copy_node(source, target) -> bool` | :108 | 复制文件（origin=copied）；目标不得已存在 |
| `move_node(source, target) -> bool` | :121 | 移动/改名；目标不得已存在 |
| `delete_node(path) -> bool` | :132 | 删除文件 |
| `count_files(exclude_hidden=true) -> int` | :143 | 可见文件计数（判定用） |
| `count_total_size(exclude_hidden=true) -> int` | :150 | 总字节数（binary 优先，文本按 UTF-8） |
| `_writable_parent(path) -> bool` | :139 | 父目录校验 |

### 7.3 修改持久化（modifications patch）

- 编辑命令执行后调用 `record_path_change(story_id, path)`：
  - 文件存在 → `changed[path] = {content, origin[, binary_base64]}`
  - 文件不存在 → `deleted[]` 追加
- 每次记录即 `_save_state()` 写 profile.json（不需要手动 save）
- 加载磁盘时 `disc_manager.gd:483-484` 在存档恢复后调 `apply_modifications(story_id)`：先擦除 `deleted`，再重建 `changed`（含二进制 base64 解码）
- 守卫 `_vdisc_edit_allowed(paths)`（command_handler.gd:964）：任务必须是 `downloaded` + 当前加载路径必须是个人任务箱副本 + 路径非隐藏且有权限；**共用源盘不可编辑**

### 7.4 编辑命令

| 命令 | 实现 | 附加行为 |
|---|---|---|
| `cp <源> <目标>` | :978 | origin=copied；记录目标 |
| `mv <源> <目标>` | :991 | 已读标记跟随移动；记录源+目标 |
| `rm <文件>` | :1008 | 已读标记移除；记录删除 |
| `mkfile <路径> [内容]` | :1021 | origin=created；不支持覆盖已有文件 |

路径参数相对当前目录（`_vdisc_path`，:961）；错误提示为统一笼统文案（已知待改进项）。

---

## 8. 判定引擎

### 8.1 进度口径（`get_progress_detail`，:513）

```
total   = file_system 中所有 → 可见（非 hidden_dirs）且当前权限可读 的 file 数
read    = main.read_files 中命中上述路径的数量
percent = read / total × 100（整数）
size_kb = count_total_size() / 1024（已验证：含玩家新增文件）
```

> ExploreViewer 的统计在任务盘场景下直接采用同一 `get_progress_detail()`（explore_viewer.gd:267-270），保证"界面显示 = 判定口径"。

### 8.2 四项要求（`check_requirements`，:526）

| 检查 | 数据源 | 缺口文案 |
|---|---|---|
| `min_read_percent` | detail.percent | `探索进度不足：X% / Y%` |
| `required_files[]` | `fs.get_node_at_path(path)` 存在且 type=file | `缺少必需文件：/path` |
| `min_total_files` | detail.total | `文件数量不足` |
| `min_size_kb` | detail.size_kb | `数据包体积不足` |

- 垃圾/重复文件计入 total 与 size（数量+存在性设计）
- 返回 `{passed, missing[], detail}`；`missing` 用于 `on_fail` 提示和盘内 `vdisc` 缺口列表

### 8.3 蒙混痕迹（fake_pass）

- 简易规则（当前实现）：上交时只要 `modifications[story_id]` 的 `changed` 或 `deleted` 非空 → `fake_pass = true`（vdisc_task_manager.gd:596）
- 成功上交且 `fake_pass` → 写入剧情标记 `<task_id>_fake_pass = 1`（:605），供后续剧情/结局区分
- **注意**：不拦截上交（数量+存在性通过即通过）；标记的是"工作副本有修改"而非"关键文件被替换"
- 已知待讨论项（见测试计划 §5）：是否改为只标记关键文件修改

---

## 9. 上交流程（`submit(number)`，:546）

```
submit <号码>
├─ story_id 空 → "请先加载任务磁盘。"
├─ get_task_for_story 无 → "这张磁盘没有关联的上交任务。"
├─ 状态非 downloaded → "任务尚未下载，或已经结束。"
├─ 当前加载路径 ≠ inbox/<filename> → "请加载个人任务箱中的磁盘副本再上交。"
├─ number == giver_number
│   ├─ check_requirements 未过 → on_fail.message + 缺口明细（磁盘保留可重试）
│   └─ 通过 → _finish_task(task_id, "submitted", on_success)
└─ number != giver_number
    ├─ dial_mgr.resolve_number(number)；character 空 → "未知的接收方号码。"
    ├─ wrong_recipient[character] ?? default（默认 return）
    ├─ action == "confiscate" → _finish_task(task_id, "confiscated", rule)
    └─ action == "return" → rule.message（默认"这不是交给我的任务，磁盘已退回。"），磁盘保留
```

### `_finish_task(task_id, result, effects)`（:578）

1. 定位 inbox 副本；不存在 → 报错不结算
2. `disc_mgr.eject_story()`（先弹出，防止旧内存回写进度）
3. `rename_absolute` 移动到 `vdisc/<result>/`（同名加时间戳）
4. 计算 `fake_pass`（见 §8.3）
5. 状态更新 `status/fake_pass/finished_at`；`archive[]` 追加 `{task_id, filename, result, fake_pass, day}`
6. `_save_state()` + `disc_mgr.scan_stories(true)`（列表刷新，归档盘消失）
7. effects 结算：
   - `score: "类型:n"` → `perf_mgr.add_score(n, 类型)` + `save_progress()`
   - `flags: {...}` → `daily_dialogue_mgr.set_flag()`
   - `dialogue: "id"` → `comm_mgr.trigger_dialogue(id)`
   - `submitted + fake_pass` → `set_flag("<task_id>_fake_pass", 1)`

### 没收后的重领

状态 `confiscated` → `download_task()` 走重下载路径（`reset_progress = true`）：备份 → 弹旧盘 → 清修改记录 → 写空白存档 → 新副本从零开始；归档记录保留。

---

## 10. 命令与界面汇总

### 玩家命令

| 模式 | 命令 | 作用 |
|---|---|---|
| 桌面 | `download <任务ID>` | 领取/重领（弹窗） |
| 桌面 | `vdisc` | 任务列表（标题/状态/ID）+ 归档数量 |
| 桌面 | `scan` / `load <编号>` | 扫描（个人盘带 `[个人任务盘]`）/ 加载 |
| 桌面 | `explore <磁盘编号>` | 查看指定盘的探索进度 |
| 邮件 | `mail download <编号或ID>` | 附件领取（与点击链接等价） |
| 邮件 | 点击 `vdisc://mail/<id>` | 附件领取（弹窗覆盖在邮件上） |
| 拨号 | `dial <modem号码>` | 走拨号系统下载流程 |
| 磁盘 | `vdisc` | 当前盘进度（read/total/%）、任务要求、缺口、`submit <号码>` 提示 |
| 磁盘 | `cp/mv/rm/mkfile` | 工作副本编辑（仅个人任务盘） |
| 磁盘 | `submit <号码>` | 上交 |
| 磁盘 | `save` / `eject` | 存盘 / 弹出（自动保存） |
| 任意 | `decode` | 密码解码器（见 §13） |
| 桌面 | `radio` | 无线电接收器（见 §12） |

### Debug 子命令（`debug 114514 vdisc ...`，command_handler.gd:1043-1081）

| 子命令 | 作用 |
|---|---|
| `list` | 任务状态原始列表 |
| `mail` | 投递/刷新联调邮件（MTEST-VDISC） |
| `give <任务ID>` | 直接走下载流程 |
| `check` | 当前盘达标检查 + 缺口 |
| `notice` | 5 秒延迟后台输出探针（全屏隔离测试） |

### 相关界面

| 界面 | 位置 | 说明 |
|---|---|---|
| 下载弹窗 | vdisc_task_manager.gd `_open_download/_render_download` | 字符框 + 进度条 + URL 动作 |
| 磁盘扫描列表 | disc_manager.gd:227-266 | 个人盘标记、存档标记、包类型标记 |
| 盘内信息 | disc_manager.gd:695-751 | 进度/任务要求/上交命令/缺口；外部模组激活提示 |
| 探索面板 | explore_viewer.gd | 文件树 + 百分比 + 30 格进度条（任务盘口径一致） |

---

## 11. 外部集成点

| 系统 | 集成方式 | 代码位置 |
|---|---|---|
| Main 输入路由 | 弹窗最优先拦截；`is_terminal_covered` 第一项 | main.gd:1224、1254 |
| 全屏输出隔离 | `append_output` 暂存/回放 | main.gd:1244、1507 |
| 超链接 | `vdisc://mail/` → 附件下载 | main.gd:1835 |
| 登录 | `load_player_state()` 恢复任务状态 | main.gd:560-561 |
| 存档 | 状态在 `profile.json`（`user_manager._save_current_profile`） | vdisc_task_manager.gd:222-230 |
| 磁盘扫描 | 跳过共用源盘任务包；追加 inbox 扫描 | disc_manager.gd:178、195-212 |
| 磁盘加载 | 应用修改 patch | disc_manager.gd:483-484 |
| 验收判定 | `requires_flag` 数值兼容（JSON float 陷阱） | daily_dialogue_manager.gd |
| 绩效 | `perf_mgr.add_score(n, type)` | vdisc_task_manager.gd:606-610 |
| 剧情 | `set_flag` / `trigger_dialogue` | vdisc_task_manager.gd:605、611-616 |
| 环境天数 | 归档记录 `day: env_monitor.current_day` | vdisc_task_manager.gd:601 |

---

## 12. Radio 无线电系统（解码相关）

### 12.1 与 Vdisc 的关联

| 关联点 | 说明 |
|---|---|
| 信号导入 | 触发器 `radio_import:<id>` 或 `radio_import:*` → `TriggerSystem._act_radio_import`（trigger_system.gd:563-576）→ `RadioDataManager.import_from_vdisc(manifest, fs, ids)`（radio_data_manager.gd:197） |
| 信号来源 | ① 磁盘 manifest 的 `radio_signals`（格式 1：`{signals:{id:{...}}}`；格式 2：`[{id,...}]`）；② 磁盘内 `/radio/signals.cfg` 或 `/signals.cfg` |
| 资源导出 | morse 文本/sstv 图片/audio 音频从虚拟 FS 复制到 `data/radio/`，并写 `<id>.json` 定义（`visible=true`） |
| 加密标记 | `RadioSignal.cipher_type`（""/caesar/vigenere/otp）与 `cipher_key_file` 在接收界面显示 `CIPHER: CAESAR` / `KEY FILE: xxx`（radio_receiver.gd:1499-1505） |
| 磁盘弹出 | 无线电**独立于 vdisc**（reset_all 不关闭 radio；信号持久在 `data/radio/`） |

### 12.2 Radio 信号系统接口

| 模块 | 关键接口 |
|---|---|
| `RadioDataManager`（302 行） | `scan_signals()`、`set_signal_visible()`、`update_signal_field()`、`delete_signal()`、`import_from_vdisc()` |
| `RadioConfigParser`（319 行） | `parse_signals(fs)`（signals.cfg）、`parse_signals_from_manifest(manifest, fs)`、`RadioSignal` 数据类 |
| `RadioSignalManager`（324 行） | `load_local_signals()` / `reload_local_signals()`、`add_signal()` / `remove_signal()`、`calculate_signal_quality()`、`discover_signal()`、`log_beacon()`、书签、`get_save_data()/load_save_data()` |
| `RadioReceiver`（1804 行） | `open()/close()/handle_input()/process()`、`load_local_signals()` / `reload_signals()` |
| `MorseEngine`（327 行） | `load_text(text, wpm, loop)`、`load_numbers_text(...)`、`process(delta, quality) -> Dictionary`、`get_decoded_text()` / `get_morse_display()` / `get_progress()` |
| `SSTVDecoder`（294 行） | `start_receive(image_data, mode, duration)`、`process(delta, quality)`、`get_image_as_png()`、`get_received_texture()` |
| `RadioAudioGenerator`（304 行） | 程序化噪声/音调/SSTV 音频流 |

### 12.3 解码机制（无线电侧）

- 锁定条件：质量 ≥ 0.5 持续 ≥ 3 秒（渐进感知：质量 = f(频率差, 方位差, 仰角差)）
- 摩斯：`MorseEngine.process()` 按质量决定解码完整度；数字电台模式（`character_set="numbers"`）
- SSTV：锁定后空格键 `start_receive()`，进度按时间；`P` 保存 PNG
- 加密信号：仅显示 CIPHER 标记，**不会自动解码**——玩家需手动用 `decode` 命令处理密文
- 存档：发现状态/信标日志/书签存 `radio_data`（磁盘 auto_save 的 extra 字段）

---

## 13. Decode 密码解码系统

### 13.1 引擎（scripts/cipher_decoder.gd，584 行）

```gdscript
enum CipherType { CAESAR, VIGENERE, SUBSTITUTION, BASE64, MORSE, ROT13, ATBASH, REVERSE }

decode(cipher_type, input_text, key="") -> DecodeResult     # :80 统一入口
# 分算法：decode_caesar / decode_vigenere / decode_substitution
#         decode_base64 / decode_morse / decode_rot13 / decode_atbash / decode_reverse

static get_type_name(t) -> String      # 中文名
static get_type_key(t) -> String       # 命令参数 key（如 "caesar"）
static get_type_from_key(key) -> CipherType
```

`DecodeResult`（:39）：`cipher_type / input_text / output_text / key / steps:Array[DecodeStep] / success / error_message / metadata`
- `DecodeStep`：`source_char / result_char / description / highlight_row / highlight_col / shift_value / key_char / extra`（驱动逐字符动画）
- 凯撒支持空密钥频率分析自动检测（`metadata` 记最佳偏移）；维吉尼亚/替换需密钥

### 13.2 界面（scripts/decode_viewer.gd，1456 行）

| 接口 | 位置 | 说明 |
|---|---|---|
| `setup(p_main)` | :77 | 构建 8 算法菜单（needs_key/optional_key/key_hint） |
| `open(args)` | :186 | `args[0]`=方法 key、`args[1]`=密钥；无参进入选择菜单 |
| `handle_input(event)` | :262 | 菜单导航/密文输入/密钥输入/动画控制 |
| `process(delta)` | :527 | 解码动画步进 |
| `close()` | :238 | 恢复终端缓存 |

命令入口：`decode` / `decode <方法> [密钥]` / `decode help`（command_handler.gd:1993 `_cmd_decode` → `main.open_decode_viewer(args)` main.gd:1669）。密文为**手动键盘输入**。

### 13.3 与 Vdisc 的现状关系

- 本期决策："解密比例 = 已读文件比例"，**文件打开与 decode 无自动联动**
- 磁盘内文件里的密文（如 SCP 文本内容）需要玩家自行输入 `decode` 处理
- 无线电加密信号同理：`cipher_type` 只是提示标记
- 扩展空间（未实现）：文件声明密文类型一键送解码器、无线电密文自动填入、按解密结果写剧情 flag

---

## 14. 关键文件索引

| 文件 | 行数 | 角色 |
|---|---|---|
| scripts/vdisc_task_manager.gd | 624 | ★ 任务系统核心（下载弹窗/判定/上交/归档/存档） |
| scripts/file_system.gd | 535 | 虚拟 FS（origin 标记 + 文件操作 + 统计） |
| scripts/disc_manager.gd | 751 | 磁盘扫描/加载/归档后刷新；inbox 扫描；盘内信息 |
| scripts/explore_viewer.gd | 481 | 探索面板（任务盘统一判定口径） |
| scripts/command_handler.gd | 3365 | download/submit/cp/mv/rm/mkfile/vdisc/debug vdisc |
| scripts/main.gd | 2381 | 集成与输入路由（弹窗优先 + 全屏隔离） |
| scripts/mail_system.gd | 958 | 邮件附件渲染与 `mail download` |
| scripts/cipher_decoder.gd | 584 | 8 算法解码引擎 |
| scripts/decode_viewer.gd | 1456 | 解码器 UI |
| comm_system/dial_manager.gd | 831 | modem 注册与下载完成回调 |
| radio/radio_receiver.gd | 1804 | 无线电 UI（调谐/摩斯/SSTV/瀑布图） |
| radio/radio_data_manager.gd | 302 | data/radio 管理 + `import_from_vdisc` |
| radio/radio_config_parser.gd | 319 | 信号解析（signals.cfg / manifest） |
| radio/radio_signal_manager.gd | 324 | 信号库/质量/发现/信标/书签/存档 |
| scripts/morse_engine.gd | 327 | 摩斯编解码引擎 |
| scripts/sstv_decoder.gd | 294 | SSTV 接收模拟 |
| data/main/manifest.json | — | `vdisc_tasks` 任务定义（当前含 demo_site19 联调任务） |

> 行数为 2026-10-02 核查值；注意 `radio/CLAUDE.md` 中 radio_receiver（1735）等行数已过时。

---

## 15. 已知限制与扩展点

| # | 限制 | 现状 | 可能的扩展 |
|---|---|---|---|
| 1 | fake_pass 粒度粗 | 任一文件修改即标记 | 只标记关键文件被替换（origin != original） |
| 2 | 编辑错误提示笼统 | 统一"请检查任务状态、权限、路径" | 区分权限不足/源不存在/目标已存在/父目录缺失 |
| 3 | 桌面任务状态显示英文 | `get_task_list()` 返回原始状态值 | 统一中文 + 直接展示领取命令 |
| 4 | 盘内需 debug 看达标 | `vdisc` 已显示缺口，仍需 debug check 看原始判定 | 提供玩家侧 `vdisc check` |
| 5 | 归档无详情 UI | 仅显示记录条数 | 展示标题/接收方/日期/正常或修改上交/结算分数 |
| 6 | 三入口重复领取体验不一 | 邮件/download 有确认弹窗，modem 无 | 统一确认与提示 |
| 7 | decode 与文件/信号不联动 | 手动输入密文 | 密文一键送解、解密状态写 flag |
| 8 | 探索百分比按"可见且有权限"文件 | 锁定文件不计入分母 | 按任务需要调整口径 |
| 9 | 多任务并存支持 | 一次 load 一个盘；状态按 task_id 独立保存 | 任务箱 UI 多开（未实现） |

---

## 附录 A：验收测试与计划文档

- `docs/upgrade-plans/vdisc-task-system-plan.md` — 原实施计划（含实施注记与需求原文）
- `docs/upgrade-plans/vdisc-manual-test-plan.md` — 14 项手动测试方案（T01–T14）
- `docs/debug-mode-guide.md` — 调试命令总览（含 `debug 114514 vdisc ...`）
