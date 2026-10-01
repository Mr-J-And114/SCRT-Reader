# Vdisc 解密任务系统 — 实施计划

> 2026-09-29 实施注记：系统代码和联调样例已接入，等待玩家在 Godot 中按 `docs/debug-mode-guide.md` 验收。原计划的 D1–D6 保留；实体副本及归档改为 `saves/<用户名>/vdisc/` 下的玩家专属目录，任务状态和工作副本修改记录保存在玩家 `profile.json` 的 `vdisc_task_data` 字段。蒙混标记采用简易规则：上交时只要工作副本有文件修改，记录 `fake_pass`。现有 `explore` 已有百分比，实施时与任务统计统一。Day0 限时选项另行处理。

> 本文档为交接文档：由规划会话（2026-09-29）产出，交给实施 AI 执行。
> 实施前请先通读本文件，并按「〇、给实施 AI 的说明」完成必读文档。
> 规划时未改动任何游戏逻辑代码，全部为新增设计。

---

## 〇、给实施 AI 的说明

### 项目背景
- SCRT-Reader：SCP 主题复古 CRT 终端模拟器 / 互动小说阅读器
- 引擎：Godot 4.7.1（GL Compatibility），GDScript 全类型标注，纯 2D UI，单场景 `main.tscn`，无 Autoload
- 工作目录：`D:\Godot\Projects\SCRT`
- 无头回归命令：`& "D:\Godot\Godot\Godot_v4.7.1-stable_win64_console.exe" --headless --path "D:\Godot\Projects\SCRT" --quit-after 10`
  （正常输出末尾只有 RID/resource leak 提示，这是 `--quit-after` 强退的预期现象）

### 必读文档（避免重复调研）
1. `CLAUDE.md`（根，架构总览 + 文档维护规范）
2. `SCRT/scripts/CLAUDE.md`（核心脚本索引与行数）
3. `docs/architecture.md`（脚本表 + 行数）
4. `docs/data-formats.md`（数据格式）
5. `docs/story-authoring-guide.txt`（剧情数据格式，第 15 章有模板）
6. `SCRT/comm_system/CLAUDE.md`（拨号/通讯系统）
7. 本文档第二节（现状调研索引）

### 项目代码约定（必须遵守）
- **不要加多余注释**（项目风格：只在关键逻辑加 `# ★` 注释）
- 管理器继承 `RefCounted`（需要 `_process` 时除外）；没有 Autoload，全部在 `main.gd._ready()` 构造注入
- 命令写在 `command_handler.gd` 的 `_cmd_*`，注册在 `global_commands` / `desktop_commands` / `disc_commands`
- 查看器遵循覆盖层模式：`is_active` 标志 + Panel 覆盖 + ESC/Q 关闭
- 修改后必须同步更新文档行数（`docs/architecture.md`、`SCRT/scripts/CLAUDE.md`、相关子系统 CLAUDE.md）
- 有隐藏调试系统：`debug 114514 <子命令>`（详见 `docs/debug-mode-guide.md`），新功能建议补调试子命令
- 项目有剧情版本门控：manifest `story.version` 变化会重置存档（本系统改动若影响存档结构，考虑版本号是否提升，与用户确认）

### 已知历史 bug 点（改动时留意）
- 信号重复连接（CommManager 曾出现）
- URL 拼接错误（modem 下载）
- JSON 数字解析为 float 的陷阱（`requires_flag` 曾因 `1.0` vs `1` 比较失败）
- `visible: false` vs `hidden: true` 语义差异（无线电系统）
- GDScript 单行 `if x: a else b` 不合法（match case 中注意）

---

## 一、需求（用户原文 + 拆解）

### 1.1 用户原文

> 1. 游戏角色会通过邮件等方式给玩家发布解密 vdisc 的任务，此时玩家通过邮件触发器或者手动"下载"的功能将 vdisc 放到本地，准备解密。
> 2. 玩家探索/解密 vdisc 的时候会记录其探索进度（百分比），大部分情况下玩家无需全部探索完成，上交时达到任务要求的解密比例、任务要求重要文件是否获取、数据包完整性等即可上交。（玩家可以选择拷贝某些文件或者截留某些文件，然后往里面塞一些垃圾/重复文件以达到任务要求蒙混过关，这涉及到不同结局的要求）
> 3. 在界面里面通过特定命令+指定角色的通讯号码，将这份文件上交给任务发布者，通过任务要求的判定即可完成任务，否则则会要求继续解密直到达标；在完成任务并上交之后会移除已解密的 vdisc 到另一个文件夹内存着以防备用。（如果玩家发错了角色会被退回，或者触发一些特殊后果：比如将其它角色委托的 vdisc 发给 ava 就会被没收，导致玩家需要重新下载重新解密，但可以获得额外绩效）

### 1.2 需求拆解

| # | 需求点 | 验收标准 |
|---|---|---|
| R1 | 任务发布 | 角色邮件可发布 vdisc 解密任务，含下载途径（modem 号码 / 邮件附件 / 外部 URL） |
| R2 | 下载 | 三种方式均可把 vdisc（.scp）放到本地 `vdisc/`，并自动登记任务 |
| R3 | 探索进度 | 记录并显示"已读文件百分比" |
| R4 | 上交判定 | `submit <号码>` 命令；判定 = 解密比例 + 关键文件存在 + 数据包数量/大小 |
| R5 | 蒙混 | 玩家可用 cp/rm/mv/mkfile 截留文件、塞垃圾/重复文件；数量+存在性判定可通过；痕迹供结局区分 |
| R6 | 失败反馈 | 未达标要求继续解密，任务保留 |
| R7 | 归档 | 上交后 .scp 移入 `vdisc/submitted/`，仅记录（不支持重新加载查看） |
| R8 | 发错角色 | 一般角色退回；发给 ava 没收 + 需重新下载 + 获得额外绩效 |

---

## 二、现状调研结论（关键实现索引）

> 规划会话已完成的调研，实施时直接引用即可，无需重复探索。

### 2.1 Modem 下载（已有，需扩展联动）
文件：`SCRT/comm_system/dial_manager.gd`（831 行）

| 位置 | 内容 |
|---|---|
| `:113` | `register_system_modem(number, info)` — 注册 modem 号码，`info` 含 `{label, speed_display, filename, url}` |
| `:152` | `resolve_number(number)` — 解析号码返回 `{type: CallType, character, label, modem_info}` |
| `:189` | `dial(number)` — 拨号入口 |
| `:532` | `_process_modem_phase()` — 进入 MODEM_DOWNLOADING，读取 `_modem_info` 的 filename/speed/url |
| `:555-560` | url 非空 → `_start_http_download(url)`（真实 HTTP）；为空 → 模拟下载 |
| `:601-628` | `_process_download(delta)` — 模拟进度（按字节），每 10% 显示进度条 |
| `:648-668` | `_enter_modem_complete()` — 下载完成，调 `_save_downloaded_file`，提示 `load <NUM>` |
| `:676-705` | `_save_downloaded_file(data, filename)` — 保存到 `vdisc/`（编辑器 `res://vdisc/`，导出版 exe 目录/vdisc/），返回 `"vdisc/<filename>"` |

现有 modem 号码来源：`_load_preset_dial_directory()`（`:274`）读 `res://data/dial_directory.json`（当前文件**已归档移除**）；
归档版本在 `SCRT/data/_story_archive_20260819/dial_directory.json`（含示例号码 9900-0001）。
Day0 剧情中拨号号码改为代码注册（`main.gd:200-202`，见 `comm_system/CLAUDE.md`）。

**扩展点**：下载完成时（`_enter_modem_complete`）回调任务管理器登记任务。

### 2.2 虚拟文件系统（需扩展文件操作）
文件：`SCRT/scripts/file_system.gd`（472 行）

| 位置 | 内容 |
|---|---|
| `:11-16` | `class FSNode: var type: String; var content: String` — 只有类型+内容两个字段 |
| `:22` | `file_system: Dictionary` — 树状结构（嵌套 Dictionary） |
| `:88` | `get_node_at_path(path) -> FSNode` |
| `:99` | `get_children_at_path(path) -> Array[String]` |
| `:117` | `get_file_data(path) -> Dictionary` |
| `:419` | `get_binary_data(path) -> PackedByteArray` |
| `:460` | `read_text(path) -> String` |

**缺口**：无 copy/move/delete/create；无文件计数/大小统计；无文件来源标记。

### 2.3 探索进度（仅列表，无百分比）
- `main.gd:58-59`：`read_files: Array[String]`、`visited_paths: Array[String]`
- 写入点：`command_handler.gd:1332-1454`（各 `_cmd_open` 分支读文件时 append）、`:1178-1194`（cd 时 append 目录）、`disc_manager.gd:430`（加载时预写）、`trigger_system.gd:376-377`（触发器）
- 显示：`SCRT/scripts/explore_viewer.gd` `_render_story_progress()`（`:425-472`）— 仅列已读/已访问清单
- 存档：`save_manager.auto_save(story_id, clearance, read_files, unlocked_passwords, unlocked_file_passwords, current_path, extra_data)`（`save_manager.gd:75`）

### 2.4 解密系统（与文件无关联，本期不强制改）
- `SCRT/scripts/cipher_decoder.gd`（584 行）：8 种算法（CAESAR/VIGENERE/ROT13/ATBASH/SUBSTITUTION/BASE64/MORSE/REVERSE），`decode(type, text, key) -> DecodeResult`（`:80`）
- `SCRT/scripts/decode_viewer.gd`（1456 行）：UI 选择算法 → 手动输入密文 → 密钥 → 动画 → 结果
- 需求确认：**本期"解密比例"= 已读文件比例**，不要求密文与文件绑定（后续版本可迭代）

### 2.5 磁盘/命令（现有入口）
- `disc_manager.gd`：`scan_stories()`（`:165` 扫描 vdisc/*.scp）、`load_story(args)`（`:271`）、`eject_story()`（`:566`）、`show_story_info()`（`:663`）
- `command_handler.gd`：`_cmd_scan`（`:930`）、`_cmd_load`（`:933`）、`_cmd_vdisc`（`:936`）、`_cmd_explore`（`:939`）、`_cmd_eject`、`_cmd_clearsave`
- 故事盘加载后 FS 树来源：`story_loader.gd`（ZIP 解析，`manifest.json` + 文件树）

### 2.6 .scp 包结构（真实样例）
```
test_story/
├── manifest.json
├── readme.txt / welcome.txt / notice.txt ...
├── audio/ (party.mp3, party.txt)
├── classified/ (overseer_memo.txt, project_origin.txt)
├── comms/ (email_archive.txt, radio_log.txt, stransmission_log.txt)
├── personnel/ (agent_k.txt, dr_bright.txt, dr_zhang.txt, roster.txt)
└── reports/ (final_report.txt, incident_0117.txt, scp_173.txt, scp_682.txt)
```

### 2.7 邮件系统扩展点
- `mail_system.gd`：`deliver_mail(mail_id, ...)`（`:240`）、`deliver_inline_mail(mail_id, title, from, body, persistent)`（`:310`）
- 邮件触发器：`daily_dialogues` 的 `mail_deliveries`（内嵌邮件定义，见 `main/manifest.json` Day0 的 M00-01/M00-02）
- 触发器动作：`new_mail:<id>`（`trigger_system.gd`）
- 邮件头支持 `template` 字段切换显示模板（email/article/chat/two-page，见 `SCRT/templates/CLAUDE.md`）

### 2.8 存档结构
- 玩家存档路径：`saves/<username>/<story_id>.json`（`user_mgr.save_story_progress`）
- 字段：`story_id / player_clearance / read_files / unlocked_passwords / unlocked_file_passwords / current_path` + `extra_data`（邮件、触发器、无线电、绩效等模块各自扩展）
- 剧情进度另有：`saves/<username>/story_progress.json`（`daily_dialogue_manager`）
- 密码存档：`comm_progress.cfg` / `env_progress.json` / `performance.json` 等（见 `saves/<user>/`）

---

## 三、设计决策（用户已确认，不可更改）

| # | 决策点 | 结论 |
|---|---|---|
| D1 | 下载方式 | **三种都要**：① 现有命令从外部网站下载（meta 要素）② 邮件给定 modem 号码拨号下载 ③ 邮件内附件（点击即可下载） |
| D2 | 任务要求定义位置 | **`main/manifest.json` 新增 `vdisc_tasks` 段**（与 `comm_dialogues` 并列） |
| D3 | 解密比例 | **已读文件比例** = 已读文件数 / 可见文件总数 |
| D4 | 蒙混判定 | **数量+存在性**（垃圾/重复文件凑数有效，不做内容指纹拦截） |
| D5 | 文件操作方式 | **终端命令**（cp/mv/rm/mkfile 等） |
| D6 | 归档后用途 | **仅记录**（不支持重新加载查看内容） |

---

## 四、详细设计

### 4.1 数据格式：`main/manifest.json` 新增 `vdisc_tasks` 段

```json
{
  "story": { "version": "0.3.0" },
  "vdisc_tasks": {
    "task_ava_01": {
      "_comment": "测试任务：Ava 委托的音频日志解密",
      "title": "Vdisc 解密：音频日志",
      "giver": "ava",
      "giver_number": "1001-0001",
      "download": {
        "number": "9900-0002",
        "filename": "audio_log_V0.1.scp",
        "url": "",
        "mail_attachment": "M00-03"
      },
      "requirements": {
        "min_read_percent": 60,
        "required_files": ["/classified/report.txt"],
        "min_total_files": 5,
        "min_size_kb": 80
      },
      "on_success": {
        "score": "main:1",
        "flags": { "task_ava_01_done": 1 },
        "dialogue": ""
      },
      "on_fail": {
        "dialogue": "",
        "message": "任务未达标，请继续解密。"
      },
      "wrong_recipient": {
        "default": { "action": "return", "message": "这不是交给我的任务。" },
        "ava": { "action": "confiscate", "score": "main:1", "message": "数据已没收。需要重新获取原始副本。" }
      }
    }
  }
}
```

字段说明：

| 字段 | 必填 | 说明 |
|---|---|---|
| `title` | 是 | 任务名（任务箱显示） |
| `giver` | 是 | 发布者角色 id（ava/kanda/nanami） |
| `giver_number` | 是 | 上交号码（通常 = 角色拨号号，如 ava=1001-0001） |
| `download.number` | 否 | modem 拨号号码（空则无此途径） |
| `download.filename` | 否 | 下载文件名（.scp，须与 modem 注册的 filename 一致） |
| `download.url` | 否 | 外部 URL（走现有 HTTP 下载） |
| `download.mail_attachment` | 否 | 邮件 id，标记该邮件携带此 vdisc 附件 |
| `requirements.min_read_percent` | 否 | 0-100，缺少视为 0 |
| `requirements.required_files` | 否 | 数组，须存在的文件路径（存在性检查） |
| `requirements.min_total_files` | 否 | 可见文件数下限 |
| `requirements.min_size_kb` | 否 | 文件总大小下限（KB） |
| `on_success.score` | 否 | 绩效格式 `"类型:数量"`（main/daily/side） |
| `on_success.flags` | 否 | 成功后写入的剧情标记 |
| `on_success.dialogue` | 否 | 成功后触发对话 id（可空） |
| `on_fail.message` | 否 | 未达标提示文本 |
| `wrong_recipient.<role>.action` | 是 | `"return"`（退回）或 `"confiscate"`（没收） |
| `wrong_recipient.<role>.score` | 否 | 后果附带绩效（没收时） |

### 4.2 模块架构

```
scripts/vdisc_task_manager.gd（新建，~400 行，RefCounted）
class_name VdiscTaskManager
├─ setup(p_main, p_save_mgr)                    # 构造注入
├─ load_tasks_from_manifest(manifest)           # 解析 vdisc_tasks
├─ on_modem_downloaded(filename) -> String      # 下载完成登记（返回 task_id 或 ""）
├─ on_mail_attachment_downloaded(mail_id)       # 邮件附件登记
├─ get_task_for_story(story_id) -> String       # 当前加载的 vdisc → 任务
├─ get_task(task_id) -> Dictionary
├─ get_task_status(task_id) -> String           # not_started/downloaded/submitted/confiscated
├─ submit(number: String) -> Dictionary         # ★ 上交判定核心（见 4.3）
├─ get_progress_percent(story_id) -> float      # 已读/总数
├─ get_progress_detail(story_id) -> Dictionary  # {read, total, percent, size_kb, files_ok}
├─ get_task_list() -> Array[Dictionary]         # 任务箱（vdisc 命令显示）
├─ archive_story(story_id) -> bool              # 移动 .scp 到 vdisc/submitted/
├─ get_save_data() / load_save_data(data)       # 持久化（任务状态 + 归档记录）
└─ _check_requirements(task) -> Dictionary      # {passed: bool, missing: Array[String]}
```

### 4.3 核心机制

#### 4.3.1 判定引擎（数量+存在性）

```gdscript
func _check_requirements(task: Dictionary) -> Dictionary:
    # 输入：当前加载的 vdisc（main.fs 的 FS 树 + main.read_files）
    # 输出：{passed: bool, missing: [], detail: {...}}
    # 1. min_read_percent：read_files.size() / 可见文件总数
    # 2. required_files：逐个 get_node_at_path() 存在性检查
    # 3. min_total_files：遍历 FS 树统计可见文件数（排除 hidden_dirs）
    # 4. min_size_kb：所有文件 content.length() 之和 / 1024
    # 全部通过 → passed=true；否则 missing 列出未达标项（用于提示）
```

#### 4.3.2 蒙混痕迹（供结局区分）

在 `file_system.gd` 的 FSNode 增加来源标记：
```gdscript
class FSNode:
    var type: String
    var content: String
    var origin: String = "original"   # original / copied / created（玩家操作产生）
```

- `copy_node` 产生的新节点：`origin = "copied"`
- `create_file` 产生的新节点：`origin = "created"`
- 判定通过时，若 `required_files` 中任一文件 `origin != "original"`：
  - 任务记录 `fake_pass = true`
  - 写入剧情标记 `<task_id>_fake_pass = 1`（供后续剧情/结局使用）
- **注意**：判定本身**不拦截**（数量+存在性通过即通过，符合 D4）

#### 4.3.3 上交流程（`submit <号码>`，磁盘模式）

```
submit <number>
├─ 前置检查：必须已 load 一个 vdisc（否则提示"未加载虚拟磁盘"）
├─ 找当前 story_id 对应任务（get_task_for_story）
│   ├─ 无任务 → "此磁盘不是任何任务的交付物"
│   └─ 任务已上交/没收 → "任务已结束"
├─ 号码分支：
│   ├─ number == task.giver_number
│   │   ├─ _check_requirements 通过
│   │   │   ├─ 写 fake_pass 痕迹（如有）
│   │   │   ├─ on_success：绩效 + flags +（可选对话）
│   │   │   ├─ 归档：vdisc/<file>.scp → vdisc/submitted/
│   │   │   ├─ 任务状态 = submitted，记录 {time, result, fake_pass}
│   │   │   └─ 输出成功提示
│   │   └─ 不通过
│   │       ├─ 输出 on_fail.message + missing 明细
│   │       └─ 任务保留（状态不变，可继续解密后重试）
│   ├─ number != giver_number 且匹配其他已注册角色号码
│   │   ├─ 查 wrong_recipient.<role>（默认 default）
│   │   ├─ action == "return" → 文件保留，输出退回提示
│   │   └─ action == "confiscate" → 文件移入 vdisc/confiscated/ + 绩效 + 任务状态=confiscated
│   └─ 号码无匹配 → "未知的接收方号码"
```

#### 4.3.4 归档

- 归档目录：`vdisc/submitted/`（成功）与 `vdisc/confiscated/`（没收）
- 用文件移动（`DirAccess.rename_absolute` 或手动 copy+delete）
- 同时从 `disc_mgr.available_stories` 移除（重新 scan）
- 归档记录存玩家存档：`vdisc_archive: [{task_id, filename, result: "submitted"/"confiscated", fake_pass: bool, day: int, time: unix}]`

#### 4.3.5 工作副本持久化（关键难点）

玩家对 FS 树的修改（cp/rm/mv/mkfile）必须跨 load/存档保留：
- 方案：**修改 patch 存玩家存档**
  ```json
  "vdisc_modifications": {
    "<story_id>": {
      "added":   { "/reports/fake.txt": "内容" },
      "deleted": [ "/classified/real.txt" ],
      "renamed": { "/old.txt": "/new.txt" }
    }
  }
  ```
- 加载 .scp 后应用 patch（`story_loader` → 内存树 → 应用 patch）
- 应用位置：`disc_manager.load_story()` 完成 FS 构建后，调用 `vdisc_task_mgr.apply_modifications(story_id)`
- 每次 cp/rm/mv/mkfile 后由命令处理器通知任务管理器更新 patch 并保存

> 简化替代：若实施成本过高，可先做"内存内修改 + 每次操作即存 patch"，暂不处理重命名链式覆盖。

### 4.4 命令设计

#### 磁盘模式新命令（`disc_commands`）
| 命令 | 用法 | 说明 |
|---|---|---|
| `cp` | `cp <源文件> <目标路径>` | 拷贝文件（origin=copied） |
| `mv` | `mv <源> <目标>` | 移动/改名 |
| `rm` | `rm <文件>` | 删除文件（记录 deleted patch） |
| `mkfile` | `mkfile <路径> [内容]` | 新建文件（origin=created，塞垃圾用） |
| `submit` | `submit <号码>` | 上交 vdisc |

> 命名顾虑：`cp/mv/rm` 是 Unix 风格，与现有 `ls/cd/open` 一致。若担心与未来命令冲突，可用 `copy/move/delete`，实施时与用户确认（默认用短名）。

#### 桌面模式扩展
| 命令 | 用法 | 说明 |
|---|---|---|
| `vdisc`（扩展） | `vdisc` | 显示：任务箱（进行中/已上交）+ 当前磁盘解密进度百分比 |
| `download` | `download <号码>`（可选） | meta 要素直连下载（走 modem 的 url 机制）；若用户希望仅走 dial，则不加 |

### 4.5 存档结构（玩家存档新增字段）

```json
{
  "vdisc_tasks": {
    "task_ava_01": { "status": "submitted", "fake_pass": false, "submitted_at": 1759000000, "result": "success" }
  },
  "vdisc_modifications": { "<story_id>": { "added": {}, "deleted": [], "renamed": {} } },
  "vdisc_archive": [ { "task_id": "task_ava_01", "filename": "audio_log_V0.1.scp", "result": "submitted", "fake_pass": false, "day": 3 } ]
}
```

---

## 五、实施阶段（按顺序，每阶段可独立验证）

### P1 — 文件操作基础
**改动**：
1. `scripts/file_system.gd`：
   - FSNode 增加 `origin: String = "original"`
   - 新方法：`copy_node(src, dst) -> bool`、`move_node(src, dst) -> bool`、`delete_node(path) -> bool`、`create_file(path, content) -> bool`
   - 统计：`count_files(exclude_hidden := true) -> int`、`count_total_size() -> int`
2. `scripts/command_handler.gd`：`disc_commands` 注册 `cp/mv/rm/mkfile`，实现 `_cmd_cp/_cmd_mv/_cmd_rm/_cmd_mkfile`
3. `scripts/vdisc_task_manager.gd`：先只做 modification patch 的记录与应用（`record_add/delete/rename` + `apply_modifications`）
4. `scripts/disc_manager.gd`：`load_story()` 完成后应用 modifications
5. `main.gd`：`auto_save` 的 extra_data 增加 `vdisc_modifications`

**验证**：
- 手动：load 一个测试盘 → `mkfile /test.txt hello` → `rm /readme.txt` → `cp /reports/scp_173.txt /reports/copy.txt` → eject → 重新 load → 文件变化保留
- headless 回归无脚本错误

### P2 — 任务核心
**改动**：
1. 新建 `scripts/vdisc_task_manager.gd` 完整实现（4.2 节 API）
2. `main/manifest.json`：新增 `vdisc_tasks` 段（含 1-2 个测试任务）
3. `scripts/daily_dialogue_manager.gd`（或 main.gd 加载流程）：把 manifest 的 `vdisc_tasks` 传给任务管理器
4. `main.gd`：实例化 `vdisc_task_mgr`，注入依赖；注册到 `command_handler` 上下文
5. `command_handler.gd`：`disc_commands` 注册 `submit`，实现 `_cmd_submit`
6. 归档逻辑 + 存档持久化（`get_save_data/load_save_data`）

**验证**：
- 全流程：手动放测试 .scp 到 vdisc/ → load → submit 正确号码（不达标 → 提示；达标 → 成功+归档）
- 发错号码（return / confiscate）各测一遍
- 归档后 vdisc/submitted/ 有文件，vdisc/ 原文件消失，`scan` 不再列出

### P3 — 下载途径
**改动**：
1. `dial_manager.gd`：`_enter_modem_complete()` 下载成功后回调 `main.vdisc_task_mgr.on_modem_downloaded(filename)`
2. modem 号码注册：任务定义的 `download.number/filename/url` 在任务加载时调用 `dial_mgr.register_system_modem()`
3. `mail_system.gd`：邮件定义支持 `attachment` 字段（`{ "filename": "xxx.scp", "url": "" , "content": "" }`）
   - 阅读邮件时：若邮件有 attachment → 提示命令（如 `mail download <序号>` 或读邮件时自动）
   - 下载实现：url 走 HTTP，content 直接写字节到 vdisc/；随后登记任务
4. 邮件模板渲染：邮件正文显示附件信息（可复用 email 模板）
5. `main/manifest.json`：测试任务 M00-03 邮件带附件

**验证**：三种下载途径各跑一遍，任务状态变为 downloaded

### P4 — 进度显示与联动
**改动**：
1. `explore_viewer.gd`：`_render_story_progress()` 增加百分比 + 文本进度条（▓░ 风格，参考 dial_manager.gd:644）
2. `command_handler.gd` `_cmd_vdisc`：扩展显示任务箱 + 当前进度
3. 绩效联动：`on_success.score` → `main.perf_mgr.add_score(n, type)`（注意 Day0 屏蔽规则，参考 `env_task_manager.complete_task` 的写法）
4. flags 联动：`daily_dialogue_mgr.set_flag()`
5. 调试命令：`debug 114514 vdisc`（list/complete/reset/give 等子命令，参考 `_debug_radio` 的实现风格）
6. 文档同步：`docs/data-formats.md`（vdisc_tasks 格式）、`docs/story-authoring-guide.txt`（新章节）、`comm_system/CLAUDE.md`、`scripts/CLAUDE.md`、`docs/architecture.md` 行数

**验证**：完整剧情链路（模拟邮件发布 → 下载 → 探索 → 蒙混 → 上交 → 结局 flag 检查）

---

## 六、验收清单（全部通过才算完成）

- [ ] R1 任务发布：邮件可含 modem 号码/附件/URL 三种下载信息
- [ ] R2 下载：三种途径均落地 `vdisc/` 且自动登记任务
- [ ] R3 进度：`explore` 与 `vdisc` 显示正确百分比
- [ ] R4 上交：`submit <giver_number>` 判定（比例/关键文件/数量/大小），未达标提示继续
- [ ] R5 蒙混：cp/rm/mv/mkfile 可用；垃圾凑数可通过；`fake_pass` 标记正确
- [ ] R6 失败反馈：不达标任务保留可重试
- [ ] R7 归档：`vdisc/submitted/` 归档 + 记录
- [ ] R8 发错：一般角色退回；ava 没收 + 绩效 + 需重新下载
- [ ] 存档：修改 patch + 任务状态跨存档/重启保留
- [ ] 回归：headless 无脚本错误；无头测试 `--quit-after 10` 通过
- [ ] 文档：所有相关 CLAUDE.md / architecture.md / data-formats.md 已同步
- [ ] debug：`debug 114514 vdisc` 子命令可用

---

## 七、遗留决策点（实施时与用户确认）

1. **命令短名 vs 长名**：`cp/mv/rm/mkfile`（Unix 风格，默认）还是 `copy/move/delete/makefile`？
2. **submit 模式**：仅磁盘模式（默认，需内容判定）还是也支持桌面模式？
3. **归档文件夹名**：`vdisc/submitted/`（默认）还是 `vdisc/archive/`？
4. **邮件附件交互**：读邮件时自动下载（简单）还是提示命令手动下载（可控）？建议提示手动
5. **`min_size_kb` 是否参与判定**：默认为是（"数据包完整性"的量化实现），若嫌复杂可先不做
6. **work copy 持久化范围**：是否包含 mv 的链式重命名覆盖（复杂场景）？建议先支持单层
7. **剧情版本门控**：本系统改动若影响旧存档（新增字段），是否需要提升 `story.version`？建议不提升（新增字段向后兼容）

---

## 八、测试数据建议

P2 联调时可创建一个测试 vdisc 包（.scp = ZIP）：
```
test_task_disc/
├── manifest.json          # {"story": {"id": "test_task_disc", "title": "测试任务盘"}}
├── reports/
│   ├── summary.txt        # 关键文件（required_files 用）
│   ├── log_01.txt / log_02.txt / log_03.txt
├── classified/
│   ├── memo.txt
│   └── data.bin           # 大文件（测试 min_size_kb）
```
放入 `vdisc/` 后用 debug 命令（P4）或手动 `scan` + `load` 测试。

现有测试包可直接复制改造：`vdisc/test_story_V0.3.2_1.scp`（结构见 2.6 节）。

---

## 附录 A：相关文件速查

| 文件 | 用途 | 本系统改动 |
|---|---|---|
| `scripts/file_system.gd` | 虚拟文件系统 | ★ 扩展文件操作 API |
| `scripts/vdisc_task_manager.gd` | 任务系统（新建） | ★ 全新 |
| `scripts/command_handler.gd` | 命令 | ★ 新命令 cp/mv/rm/mkfile/submit + vdisc 扩展 + debug |
| `comm_system/dial_manager.gd` | 拨号/modem 下载 | ★ 下载完成回调 |
| `scripts/disc_manager.gd` | 磁盘加载 | ★ 应用 modifications + 归档联动 |
| `scripts/mail_system.gd` | 邮件 | ★ 附件字段 + 下载 |
| `scripts/explore_viewer.gd` | 探索进度 UI | ★ 百分比显示 |
| `scripts/save_manager.gd` | 存档 | 复用（extra_data） |
| `scripts/main.gd` | 上帝对象 | ★ 实例化任务管理器 + 注入 |
| `data/main/manifest.json` | 剧情数据 | ★ vdisc_tasks 段 |
| `scripts/daily_dialogue_manager.gd` | 剧情/flag | 复用（set_flag） |
| `scripts/performance_manager.gd` | 绩效 | 复用（add_score） |

## 2026-09-30：邮件附件与上交提示补充

- 阅读关联邮件时自动追加可点击的 Vdisc 附件链接，使用 `vdisc://mail/<URI 编码邮件 ID>`；不关闭邮件查看器。
- `download_task()` 的命令与邮件入口共用下载窗口。下载中禁止重复领取和关闭窗口，完成或失败后允许关闭；联网请求最多等待 30 秒。
- 本地源盘使用约 1.2 秒的模拟传输；HTTP 使用实际已收字节，未知总大小时使用等待动画。100% 仅在 ZIP、story.id 校验和个人副本保存成功后显示。
- 当前任务的 `vdisc` 信息显示完整上交命令及未达标条件。联调任务达标后使用 `submit 1001-0002`。
- 对外接口增加 `is_download_open()`、`close_download()`；主界面在窗口打开时暂停输入路由与其他子系统的逐帧交互。
- 仅做源文件检查，未运行 Godot。手动验收流程见 `docs/debug-mode-guide.md`。

## 附录 B：实施前行数基线（2026-09-29，保留供比对）

| 文件 | 当前行数 |
|---|---|
| command_handler.gd | 3335 |
| main.gd | 2284 |
| file_system.gd | 472 |
| disc_manager.gd | 700 |
| mail_system.gd | 937 |
| dial_manager.gd | 831 |
| explore_viewer.gd | 477 |
| save_manager.gd | 228 |
| daily_dialogue_manager.gd | 534 |
| performance_manager.gd | 413 |

## 2026-09-30：下载弹窗风格修复与重复领取

- 弹窗 CanvasLayer 层级取 CRTEffect.layer - 1（当前为 9），进入 CRT 后处理；字体取终端正文，配色/边框/按钮/进度条取当前 ThemeColors。
- 检测个人 inbox 实际文件，重复领取须确认。取消保留原磁盘；确认后重新下载并重置这张盘的任务状态、文件修改、探索及解锁进度。已上交任务仍不能重复领取。
- store_download(task_id, bytes, replace_existing=false) 先写临时包校验 ZIP 与 story.id，再备份旧磁盘/旧进度并替换；失败尝试回滚。旧盘与旧进度存于个人 vdisc/replaced/<编号>/。
- 重置时写空白个人存档，防止 SaveManager 回退迁移旧的全局存档。正在使用的同故事盘先弹出，成功后通过 load 重新加载。
- 确认窗口支持鼠标/键盘焦点，Esc 等同保留。仍由玩家进行 Godot 内测试。


2026-09-30 再补充：下载窗口使用 FileSystem.build_box() 字符边框与 Typewriter.format_progress_bar() 字符进度条，取消独立 ProgressBar/按钮描边。窗口键盘操作：Y 确认重下载，N/Esc/Enter 保留；结束后 Enter/Esc 返回。main 统一隐藏全屏界面下的终端输出、暂存普通提示，退出后回放。scan 新增个人任务盘标记，任务编辑仅允许加载的个人副本。完整验收见 docs/upgrade-plans/vdisc-manual-test-plan.md，未运行游戏。


2026-09-30 白线修复：下载框已禁用 RichTextLabel 焦点，并用空 StyleBox 显式覆盖焦点样式；PanelContainer 的边框宽度、阴影尺寸均明确为零。字符框是唯一外框。未启动 Godot，待玩家目视验收。

