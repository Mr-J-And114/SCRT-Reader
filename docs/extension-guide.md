# 扩展开发指南 / Extension Guide

> 最后更新：2026-04-01
<!-- Extracted from SCRT/AI_HANDOFF.md §6, §8, §9 -->

## 添加新功能的 7 步流程 / Adding a New Feature

1. **创建类**：在 `res://scripts/` 中创建脚本，继承 `RefCounted`（如需 `_process` 则继承 `Node`）
2. **实例化**：在 `main.gd._ready()` 中实例化，通过构造函数注入依赖
3. **注册命令**（如需要）：在 `CommandHandler._register_commands()` 中添加 `_cmd_<name>` 方法
4. **创建覆盖层**（如需要）：参照 `ImageViewer` / `Oscilloscope` 的模式——用 Panel 覆盖 OutputArea，隐藏 input/prompt，关闭时恢复，自定义绘制用 `_draw()`
5. **解析 manifest 数据**（如需要）：在 `disc_manager.load_story()` 或 `trigger_system.load_from_manifest()` 中添加解析逻辑
6. **存档集成**（如需要）：接入 `save_manager.auto_save()` / `load_save()`
7. **注册设置**（如需要）：使用 `settings_manager.register_category()` / `register_setting()`

## 应用生命周期 / App Lifecycle

1. `_ready()` → 实例化所有管理器 → 初始化 UI 样式
2. 加载 `boot_config.json` → 播放开机动画（`BootSequence`）
3. 登录流程（登录/注册提示）
4. 进入桌面模式 → 加载设置、邮件，检查故事盘
5. 用户输入命令 → `CommandHandler` 分发处理
6. `load` 命令 → `DiscManager.load_story()` → `StoryLoader` 解析 ZIP → 提取 `loading_screen.json` → 填充虚拟文件系统 → 播放加载画面（自定义或默认）→ 等待完成
7. `cd`/`open` → 浏览虚拟文件系统，通过 `CrtmlParser` 显示文件
8. `eject` → 自动存档，清空文件系统
   - `dial <number>` → `DialManager.dial()` → DTMF → 语音通话或调制解调器下载
   - `comm` → 显示状态 / `comm phonebook` / `comm answer`
9. `exit`/`shutdown` → 关机动画 → 退出程序

## 模式标志变量 / Mode Flags (`main.gd`)

以下是 `main.gd` 中声明的实际模式标志变量：

**桌面/故事模式：**
- `_desktop_mode`：`true` = 普通桌面 CLI，`false` = 故事盘已加载

**密码输入模式：**
- `_password_mode`：密码输入捕获（故事盘密码）
- `_file_password_mode`：文件密码输入捕获

**用户认证流程：**
- `_login_mode`：登录流程
- `_register_mode`：注册流程
- `_passwd_mode`：修改密码流程
- `_delete_user_mode`：删除用户确认

**全屏覆盖层模式：**
- `_oscilloscope_mode`：示波器覆盖层
- `_image_viewer_mode`：图片查看器覆盖层
- `_video_player_mode`：视频播放器覆盖层
- `_radio_mode`：无线电接收器覆盖层
- `_decode_mode`：密码解码器覆盖层
- `_env_viewer_mode`：环境监测仪表盘覆盖层
- `_camera_viewer_mode`：CCTV 监控查看器覆盖层

**其他状态：**
- `_theme_confirm_mode`：主题切换确认
- `_command_running`：异步命令执行锁
- `dial_mgr.state`：拨号状态机（DialState 枚举，完整 13 个状态见 `comm_system/CLAUDE.md`）
- `dial_mgr.call_type`：通话类型（NONE / VOICE / MODEM / INVALID）

## 命令列表 / Commands

**桌面命令（全局可用）：**
`help`（帮助）、`clear`/`cls`（清屏）、`status`（状态）、`whoami`（当前用户）、`settings`/`set`（设置）、`theme`（主题）、`volume`/`vol`（音量）、`reboot`（重启）、`exit`/`quit`（退出）、`logout`（登出）、`passwd`（改密码）、`birthday`（设置生日）、`nickname`（设置昵称）、`gender`（设置性别）、`users`（用户列表）、`deluser`（删除用户）、`profile`（查看资料）、`comm`（通讯）、`mail`（邮件）、`scan`（扫描故事盘）、`load`（加载故事盘）、`vdisc`（列出故事盘）、`explore`（文件树浏览）、`dial`（拨号）、`phonebook`/`pb`（电话簿）、`env`/`monitor`（环境监测）、`camera`/`cam`/`cctv`（CCTV 监控）、`decode`（密码解码）、`sound`（音效）、`save`（存档）、`packages`/`pkg`（Mod 管理）、`install`（安装 Mod）、`uninstall`（卸载 Mod）、`radio`（无线电）、`perf`/`performance`（绩效查看）

**通讯子命令：**
`comm`（状态）、`comm answer`（接听）、`comm reject`（拒接）、`comm video`（视频频道列表）、`comm video <num>`（拨打视频）、`comm phonebook`（电话簿）、`comm history`/`comm log`（通讯记录）

**故事盘命令（加载故事后可用）：**
`ls`/`dir`（列出文件）、`cd`（切换目录）、`back`（返回上级）、`open`/`read`/`cat`（打开文件）、`unlock`（解锁文件）、`eject`（弹出故事盘）、`save`（存档）、`clearsave`（清除存档）、`radio`（无线电）、`fx`/`sfx`/`sound`（音效）、`decode`（解码）、`install`（安装）、`uninstall`（卸载）、`packages`/`pkg`（Mod 管理）、`explore`（浏览）

**环境监测子命令：**
`env status`（总览）、`env view`（打开仪表盘）、`env tasks`（任务列表）、`env check`（检查传感器）、`env read`（读取传感器值）、`env calibrate`（校准传感器）、`env anomaly`（异常报告）、`env report`（生成报告）、`env repair`（修复传感器）、`env advance`（推进天数）、`env sensor`（传感器详情）、`env weather`（天气信息）、`env events`（事件日志）

**绩效子命令：**
`perf`/`perf status`（当日绩效状态）、`perf detail`（分类明细）、`perf history`（历史记录表）、`perf help`（帮助）

**摄像头子命令：**
`camera list`（列出摄像头）、`camera view [id/num]`（查看摄像头画面）、`camera status`（状态）（别名：`cam`、`cctv`）

## Mod 开发接口 / Modding Interface

- Mod 以 `.scp` ZIP 文件发布，包含 `package.json` 清单（`type="package"`）
- Mod 脚本继承 `ModBase` 基类，获得 `ModAPI` 沙盒实例
- **ModAPI 提供 16 类 API**：输出（output）、文件系统（fs）、命令（commands）、音频（audio）、效果（effects）、UI 节点（ui）、通讯系统（comm）、邮件（mail）、设置（settings）、定时器（timers）、补间动画（tweens）、跨 Mod 通信（messaging）、存档（save）、触发器（triggers）、摄像头（camera）、环境（env）
- **生命周期**：安装 → 启用 → `_register_commands`（注册命令） → `_process`（每帧） → 钩子回调 → 禁用 → 卸载
- **钩子事件**：`before/after_command`（命令前后）、`directory_changed`（目录切换）、`file_open`（文件打开）、`disc_loaded/ejected`（故事盘加载/弹出）、`mode_changed`（模式切换）、`user_login/logout`（用户登入/登出）、`mod_message`（Mod 间消息）

### Mod 安全约束

- Mod 脚本运行在受限沙盒中，无法直接访问宿主节点
- 文件系统操作限制在虚拟文件系统内
- 所有 API 调用经过权限检查
- 详见 `SCRT/modder/CLAUDE.md`
