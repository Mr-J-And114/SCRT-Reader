# scripts/ — 核心脚本 (Core Scripts)

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 详细索引：[/docs/architecture.md](/docs/architecture.md)
> 修改脚本后请同步更新本文件中的行数和文件列表。

本目录包含所有核心逻辑脚本。`main.gd` 是中央控制器（2355 行），拥有所有管理器实例。
共 36 个 `.gd` 脚本文件，总计约 24,000 行。

## 按行数排列的文件索引（行数大 = 复杂度高）

| 文件 | 行数 | 用途 |
|---|---|---|
| command_handler.gd | 3365 | CLI 命令注册中心，含 Vdisc 下载、文件操作、上交与调试入口 |
| main.gd | 2381 | 初始化、输入路由、模式管理、Vdisc 任务管理器及各子系统集成 |
| latex_renderer.gd | 1720 | LaTeX 公式渲染器：Tokenizer → Parser(AST) → Layout → Image，支持分数/根号(自绘)/矩阵/上下标/希腊字母/定界符/cases 环境 |
| decode_viewer.gd | 1456 | 密码解码 UI 覆盖层，内含 _DecodeCanvas 内部类 |
| crtml_parser.gd | 1325 | Markdown 风格标记 → BBCode 转换（含内联效果标记解析 + LaTeX [math] 公式） |
| mail_system.gd | 958 | 收件箱系统，含 `mail download` 附件领取入口 |
| user_manager.gd | 853 | 多用户账户系统：登录/注册/改密、个人资料、统计信息 |
| oscilloscope.gd | 820 | 音频可视化器（频谱分析/李萨如图形），内含 _ScopeCanvas |
| package_manager.gd | 817 | Mod 安装/卸载/运行时生命周期管理 |
| boot_sequence.gd | 809 | JSON 关键帧驱动的开机/关机动画 |
| video_player.gd | 750 | 视频播放覆盖层，含控件和 ffmpeg 回退支持 |
| trigger_system.gd | 754 | 事件触发器：条件（进目录/开文件/执行命令/空闲/等级变化）→ 30 种动作（含 score/perf_warning） |
| story_loader.gd | 708 | ZIP 解析器，UTF-8/GBK 编码检测 |
| disc_manager.gd | 751 | 虚拟磁盘：扫描共用原盘与玩家副本、加载/挂载、工作副本恢复 |
| document_viewer.gd | 668 | 双页覆盖层，分页，打字动画 |
| image_viewer.gd | 634 | 全屏 CRT 图像查看器，支持缩放/平移，内含 _ImageCanvas |
| audio_manager.gd | 586 | 环境音/音效/媒体播放器，ducking、频谱分析、字节加载（MP3/OGG/WAV） |
| cipher_decoder.gd | 584 | 密码解码算法：凯撒、维吉尼亚、Base64、摩斯、ROT13、Atbash、替换、反转 |
| loading_screen.gd | 543 | 关键帧驱动的磁盘加载动画（支持自定义 + 默认两种） |
| typewriter.gd | 540 | 逐字符输出队列，内联效果触发器，进度条 |
| theme_manager.gd | 517 | 4 种配色方案（绿/琥珀/蓝/白），shader 参数刷新 |
| explore_viewer.gd | 481 | 文件树浏览面板，任务磁盘进度与判定口径一致 |
| file_system.gd | 535 | 虚拟文件系统：路径/权限/密码/环境音、工作副本文件操作 |
| vdisc_task_manager.gd | 624 | Vdisc 任务定义、邮件链接下载/进度弹窗、玩家副本、判定、上交、归档和存档 |
| ui_manager.gd | 466 | UI 初始化：背景/字体/光标/滚动条主题化 |
| effect_system.gd | 451 | 时间轴驱动的效果编排（glitch/shake/sound/text/reboot/brightness 等） |
| crt_shader.gd | 416 | CRT 后处理效果控制器（glitch/shake/tear/noise/blackout） |
| daily_dialogue_manager.gd | 556 | 每日对话/邮件触发管理，钩子触发（先过滤条件后标记）、场景邮件投递、requires_tasks 条件、requires_flag 数值兼容（JSON 数字解析为 float，与 int 型 flag 比较时按数值比较）、剧情版本门控、故事标记/选择持久化，绩效配额配置 |
| performance_manager.gd | 413 | 绩效评分系统：三类绩效(main/daily/side)、配额、加班缺口、4日报告、警告升级、剧情版本门控 |
| morse_engine.gd | 327 | 摩斯码编解码，播放事件回调，数字站模式 |
| sstv_decoder.gd | 294 | SSTV 图像接收模拟，带扫描线噪声效果 |
| header_parser.gd | 247 | 文件头部解析（模板类型/标题/密码/元数据） |
| profile_builder.gd | 253 | 用户资料显示（3 页卡片） |
| save_manager.gd | 228 | 存档路径管理、目录创建 |
| ui_sound.gd | 200 | 终端音效：按键声/回车/退格/硬盘读取/点击 |
| effect_settings.gd | 175 | 效果强度等级 (FULL/MILD/OFF) + 光敏模式 |

## 输入优先级链（main.gd `_input` + `_on_input_submitted` 中的实际路由顺序）

```
_input() 中的拦截顺序：
0. comm_mgr.is_voice_tuner_open() ← 编辑器调音面板；让 GUI 接收输入，Esc 关闭
0. F12 during boot              ← 编辑器开机序列强制跳过
1. pkg_mgr.handle_input()        ← Mod 输入捕获最优先
2. comm_mgr.is_call_ringing()    ← 来电铃声期间吞掉所有按键
3. comm_mgr.is_active            ← 通讯对话（等命令时放行，否则拦截）
4. _oscilloscope_mode            ← 示波器
5. _image_viewer_mode            ← 图片查看器
6. _video_player_mode            ← 视频播放器
7. _radio_mode                   ← 无线电接收器
8. _env_viewer_mode              ← 环境仪表盘
9. _camera_viewer_mode           ← CCTV 监控
10. _decode_mode                 ← 密码解码器
11. article/chat/email/two_page  ← 文档模板查看器（通过 .is_active 检查）
12. doc_viewer/explore_viewer    ← 文档/探索查看器
13. [鼠标滚轮/右键等]

_on_input_submitted() 中的拦截顺序：
1. loading_screen.is_active()    ← 加载画面独占
2. 各查看器 .is_active           ← 全屏覆盖层阻断终端输入
3. comm_mgr.is_active            ← 通讯对话
4. _login_mode / _register_mode / _passwd_mode / _delete_user_mode
5. _theme_confirm_mode / _password_mode / _file_password_mode
6. [普通命令分发]
```

实际模式标志变量（main.gd 中声明的 `var _*_mode`）：
`_desktop_mode` `_password_mode` `_file_password_mode` `_theme_confirm_mode`
`_login_mode` `_register_mode` `_passwd_mode` `_delete_user_mode`
`_oscilloscope_mode` `_image_viewer_mode` `_video_player_mode`
`_radio_mode` `_decode_mode` `_env_viewer_mode` `_camera_viewer_mode`

## 架构模式

- **管理器**继承 RefCounted，除非需要 `_process`（则继承 Node）
- **查看器**使用覆盖层模式：Panel 覆盖 OutputArea，隐藏 input/prompt，关闭时恢复
  - 参考 `image_viewer.gd`、`oscilloscope.gd` 作为标准实现
  - 自定义绘制通过内部 `_*Canvas` 类的 `_draw()` 实现
- **命令**定义为 `command_handler.gd` 中的 `_cmd_<name>` 方法
  - 三个字典：`global_commands`、`desktop_commands`、`disc_commands`
- **内联效果**在 CRTML 文本中使用：`{glitch}`、`{screen_shake}`、`{tear}`、`{noise}`、`{sound=path}`、`{effect=id}`、`{speed=N}`、`{delay=N}` 等（注意：不是 `{fx:}` 前缀）
- **无 Autoload**——所有管理器在 `main.gd._ready()` 中创建，通过构造注入依赖
- **加载画面**使用 BBCode 缓冲区（`_bbcode_buffer`）确保可靠的就地渲染。
  所有输出通过缓冲区，通过 `output_text.text = _bbcode_buffer` 渲染。
  进度条保存缓冲区快照，每帧覆写最后一行。
  播放期间 `main._process()` 进入独占模式（提前返回），阻止打字机/触发器/邮件/效果系统写入 `output_text`。

## 添加新脚本

1. 在此目录创建类，继承 RefCounted
2. 在 `main.gd._ready()` 中实例化，通过构造函数传递依赖
3. 如需每帧更新，在 `main._process()` 中调用其 `process()`
4. 如需输入处理，在 `main._input()` 中添加处理器（遵循模式优先级链）
5. 如需命令，在 `CommandHandler._register_commands()` 中注册
6. 更新本文件的文件列表和行数

Vdisc 下载弹窗接口：is_download_open() 查询覆盖层；close_download() 仅在下载结束后关闭。主界面优先拦截弹窗输入，暂停其他子系统逐帧交互；邮件通过 vdisc://mail/ 链接调用 download_mail_attachment()。


全屏输出协议：is_terminal_covered() 统一判定当前覆盖界面；append_output() 在覆盖期间暂存终端结果；_sync_terminal_visibility() 隐藏底层输出并在所有覆盖界面关闭后回放。查看器关闭须使用 _refocus_input.call_deferred()，禁止直接抢终端焦点。Typewriter.format_progress_bar() 与 Vdisc 字符弹窗共享 30 格 █ 规则，弹窗边框复用 FileSystem.build_box()。debug 114514 vdisc notice 提供 5 秒延迟的后台输出探针。


## 2026-10-01 Environment 衔接

main.env_observation 负责短采集和手动日报，EnvViewer 负责覆盖界面；daily_dialogue_manager.process_pending 每帧检查界面／通讯／拨号再按次播放剧情队列，队列随 story_progress 保存。profile_builder 第二页新增当日／累计绩效和日报来源。旧env扫描流程移除，命令与隔离debug见 docs/upgrade-plans/environment-manual-test-plan.md。
