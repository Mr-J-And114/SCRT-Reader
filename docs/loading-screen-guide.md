# 自定义加载画面指南 (Loading Screen Guide)

故事包（.scp）可在根目录放置 `loading_screen.json` 文件来完全替换默认的磁盘加载动画。
该系统使用关键帧时间轴引擎，与开机动画（`boot_sequence.gd`）采用相同的设计模式。

## 快速开始

在 .scp 包的根目录创建 `loading_screen.json`：

```json
{
  "skippable": true,
  "total_duration": 6.0,
  "keyframes": [
    { "time": 0.0, "action": "clear" },
    { "time": 0.0, "action": "text", "params": {
        "content": "LOADING DISC...", "color": "muted" } },
    { "time": 0.5, "action": "beep" },
    { "time": 1.0, "action": "disc_title" },
    { "time": 1.5, "action": "disc_info" },
    { "time": 2.0, "action": "separator" },
    { "time": 2.5, "action": "progress_bar", "params": { "duration": 3.0 } },
    { "time": 5.5, "action": "text", "params": {
        "content": "READY.", "color": "success" } },
    { "time": 6.0, "action": "complete" }
  ]
}
```

放入 .scp 包后，`load` 该磁盘时就会使用自定义动画替代默认动画。

## 配置字段

### 顶层字段

| 字段 | 类型 | 默认值 | 说明 |
|---|---|---|---|
| `skippable` | bool | `true` | 是否允许玩家按任意键跳过 |
| `total_duration` | float | `8.0` | 动画总时长（秒） |
| `audio` | string | `""` | 背景音乐路径（虚拟文件系统路径） |
| `audio_volume` | float | `0.6` | 音乐音量（线性 0.0~1.0） |
| `keyframes` | array | `[]` | 关键帧数组 `{time, action, params}` |

### 关键帧格式

每个关键帧是一个字典：
```json
{ "time": 1.5, "action": "text", "params": { "content": "Hello", "color": "primary" } }
```

- **time**: 触发时间（秒），从 0.0 开始
- **action**: 动作名称（见下表）
- **params**: 动作参数（可选，部分动作不需要参数）

同一时间点可以有多个关键帧，会按顺序依次执行。

## 关键帧动作一览

### 文字输出

| 动作 | 参数 | 说明 |
|---|---|---|
| `text` | `content`, `color` | 输出一行文字 |
| `text_center` | `content`, `color` | 输出居中文字 |
| `disc_title` | `color`（可选） | 显示磁盘标题框（调用 `fs.build_box`） |
| `disc_info` | `color`（可选，默认 muted） | 显示 Author / Version / ID 信息 |
| `separator` | `char`（默认 `═`）, `width`（默认 50）, `color` | 输出分隔线 |
| `ascii_art` | `content`, `color` | 输出 ASCII 艺术文本 |

### 视觉效果

| 动作 | 参数 | 说明 |
|---|---|---|
| `glitch` | `intensity`（0.0~1.0）, `duration`（秒） | CRT 故障效果 |
| `scanlines` | `intensity`（0.0~1.0） | 设置扫描线强度 |
| `screen_flash` | `duration`（秒） | 屏幕闪白效果 |

### 音频

| 动作 | 参数 | 说明 |
|---|---|---|
| `beep` | — | 播放终端蜂鸣音 |
| `sound` | `path` | 播放虚拟文件系统中的音效文件 |
| `audio_play` | `path`（可选，回退到顶层 `audio` 字段） | 开始播放背景音乐 |

### 流程控制

| 动作 | 参数 | 说明 |
|---|---|---|
| `clear` | — | 清屏（清空所有已输出的内容） |
| `wait` | — | 纯占位，不执行任何操作 |
| `progress_bar` | `duration`（秒）, `label`（文字标签） | 显示进度条（原地更新，不清除之前的内容） |
| `complete` | — | **结束加载画面**（必须包含） |

## 颜色名称

`color` 参数支持以下主题色名称，会自动适配当前终端主题：

| 名称 | 说明 |
|---|---|
| `primary` | 主色调（默认绿色） |
| `success` | 成功色（默认亮绿） |
| `warning` | 警告色（默认橙色） |
| `error` | 错误色（默认红色） |
| `muted` | 次要色（默认灰色） |

## 变量替换

`text` 和 `text_center` 的 `content` 中可使用以下变量，会在运行时自动替换：

| 变量 | 替换为 |
|---|---|
| `{disc_title}` | manifest 中的故事标题 |
| `{disc_author}` | 作者名 |
| `{disc_version}` | 版本号 |
| `{disc_id}` | 故事 ID |
| `{username}` | 当前登录的用户名 |

## 完整示例：CLASSIFIED 主题

```json
{
  "skippable": true,
  "total_duration": 10.0,
  "keyframes": [
    { "time": 0.0, "action": "clear" },
    { "time": 0.0, "action": "screen_flash", "params": { "duration": 0.1 } },
    { "time": 0.2, "action": "glitch", "params": { "intensity": 0.5, "duration": 0.4 } },

    { "time": 0.3, "action": "text_center", "params": {
        "content": "══════════════════════════════════════", "color": "warning" } },
    { "time": 0.5, "action": "text_center", "params": {
        "content": "██  CLASSIFIED MEDIA DETECTED  ██", "color": "error" } },
    { "time": 0.7, "action": "text_center", "params": {
        "content": "══════════════════════════════════════", "color": "warning" } },

    { "time": 1.0, "action": "beep" },
    { "time": 1.2, "action": "text", "params": { "content": "" } },
    { "time": 1.5, "action": "text", "params": {
        "content": "SECURITY CLEARANCE ... VERIFIED", "color": "success" } },
    { "time": 2.0, "action": "text", "params": {
        "content": "OPERATOR ID ......... {username}", "color": "primary" } },
    { "time": 2.5, "action": "text", "params": {
        "content": "DISC SERIAL ......... {disc_id}", "color": "primary" } },

    { "time": 3.0, "action": "glitch", "params": { "intensity": 0.2, "duration": 0.2 } },
    { "time": 3.0, "action": "text", "params": { "content": "" } },
    { "time": 3.2, "action": "separator", "params": {
        "char": "─", "width": 50, "color": "muted" } },
    { "time": 3.5, "action": "disc_title" },
    { "time": 4.0, "action": "disc_info" },
    { "time": 4.5, "action": "separator", "params": {
        "char": "─", "width": 50, "color": "muted" } },

    { "time": 4.8, "action": "text", "params": { "content": "" } },
    { "time": 5.0, "action": "beep" },
    { "time": 5.0, "action": "text", "params": {
        "content": "DECRYPTING FILESYSTEM ...", "color": "warning" } },
    { "time": 5.5, "action": "progress_bar", "params": {
        "duration": 3.5, "label": "DECRYPT" } },

    { "time": 9.0, "action": "screen_flash", "params": { "duration": 0.08 } },
    { "time": 9.0, "action": "beep" },
    { "time": 9.2, "action": "text", "params": {
        "content": "DECRYPTION COMPLETE. DISC MOUNTED.", "color": "success" } },
    { "time": 9.5, "action": "glitch", "params": { "intensity": 0.15, "duration": 0.3 } },
    { "time": 10.0, "action": "complete" }
  ]
}
```

此示例展示了一个机密主题的加载画面：
1. 开场闪屏 + 故障效果（0~0.2s）
2. 居中的 CLASSIFIED 警告横幅（0.3~0.7s）
3. 安全验证信息，含变量替换（1.2~2.5s）
4. 磁盘标题和信息（3.5~4.5s）
5. "DECRYPTING" 进度条（5.5~9.0s）
6. 完成提示 + 效果收尾（9.0~10.0s）

## 设计建议

### 时间节奏

- **开头（0~1s）**：吸引注意力 — 闪屏、故障效果、醒目标题
- **中段（1~5s）**：信息展示 — 验证状态、磁盘信息、分隔线
- **后段（5~9s）**：等待感 — 进度条、处理状态文字
- **结尾（最后1s）**：收束 — 完成提示、final glitch、complete

### 进度条使用技巧

- `progress_bar` 不会清除之前的输出内容，而是追加在最后一行并原地更新
- 在进度条之前输出的磁盘信息会保持可见
- `duration` 控制进度条从 0% 到 100% 的时间
- 进度条结束后可以继续添加其他关键帧

### 自定义标题外观

`disc_title` 动作会渲染和默认加载动画一样的标题框。如果想要不同的外观，
可以用 `text` 或 `text_center` 自己拼装：

```json
{ "time": 1.0, "action": "text_center", "params": {
    "content": "╔═══════════════════════════╗", "color": "warning" } },
{ "time": 1.0, "action": "text_center", "params": {
    "content": "║    {disc_title}    ║", "color": "warning" } },
{ "time": 1.0, "action": "text_center", "params": {
    "content": "╚═══════════════════════════╝", "color": "warning" } }
```

### 空行

输出空行用空 content 的 text 动作：
```json
{ "time": 1.0, "action": "text", "params": { "content": "" } }
```

## 注意事项

- `loading_screen.json` 必须放在 .scp 包的**根目录**（如果有顶层文件夹包裹，放在那个文件夹内）
- 文件会在加载时被自动提取并从虚拟文件系统中移除，玩家不可见
- **`complete` 动作是必须的**，否则动画需要等到 `total_duration + 1` 秒后超时结束
- `manifest.json` 中的 `loading_screen` 字段已弃用，会被静默忽略
- 加载画面播放期间：
  - 终端输入被禁用
  - 打字机、触发器、邮件等系统被暂停（独占模式）
  - CRT 视觉效果（glitch/scanlines/flash）正常工作
- 视觉效果受 `effect_settings` 控制 — 如果玩家关闭了效果，glitch/flash 不会显示
