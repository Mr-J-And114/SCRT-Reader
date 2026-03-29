# modder/ — Mod 系统 (Mod System)

> 上级文档：[/CLAUDE.md](/CLAUDE.md)
> 修改 ModAPI 接口后请同步更新本文件。

沙盒化的 Mod API，提供 16 类功能访问接口、完整生命周期钩子和跨 Mod 通信。
Mod 以 `.scp` ZIP 包格式分发，包含 `mod_manifest.json` 和 GDScript 脚本。
由 `package_manager.gd`（817 行，位于 scripts/）管理安装/卸载/运行时生命周期。

## 文件列表

| 文件 | 行数 | 用途 |
|---|---|---|
| mod_api.gd | 1075 | 沙盒 API：16 类功能（输出/文件/命令/音频/效果/通讯/环境/摄像头/无线电/邮件等） |
| mod_base.gd | 92 | Mod 基类：生命周期钩子 + 事件钩子，Mod 脚本继承此类 |

## ModBase 生命周期（Mod 需覆写的方法）

```
_on_install() → _on_enable() → _register_commands() → [运行时 _process] → _on_disable() → _on_uninstall()
```

- `_on_install()`：首次安装时调用，用于初始化持久数据
- `_on_enable()`：每次启用时调用
- `_register_commands()`：注册自定义命令
- `_process(delta)`：每帧调用（如果 Mod 需要持续逻辑）
- `_on_disable()`：禁用时清理
- `_on_uninstall()`：卸载时清理所有数据

## ModBase 事件钩子

| 钩子 | 返回值 | 说明 |
|---|---|---|
| `_on_before_command(cmd, args)` | `bool` | 命令执行前拦截（返回 true 阻止执行） |
| `_on_after_command(cmd, args)` | void | 命令执行后回调 |
| `_on_directory_changed(old, new)` | void | 目录切换时触发 |
| `_on_before_file_open(path)` | `bool` | 文件打开前拦截（返回 true 阻止） |
| `_on_after_file_open(path)` | void | 文件打开后回调 |
| `_on_disc_loaded(story_id, manifest)` | void | 故事盘加载完成 |
| `_on_disc_ejected()` | void | 故事盘弹出 |
| `_on_mode_changed(is_desktop)` | void | 桌面/故事盘模式切换 |
| `_on_mod_message(from_id, data)` | void | 接收其他 Mod 的消息 |
| `_on_user_login(username)` | void | 用户登录 |
| `_on_user_logout(username)` | void | 用户登出 |

## ModAPI 功能分类（16 类）

| 类别 | 说明 |
|---|---|
| output | 终端输出（append_output, clear 等） |
| commands | 注册/注销自定义命令 |
| fs | 文件系统访问（受限于 Mod 目录 + vdisc/） |
| ui | UI 节点访问 |
| effects | CRT 效果触发（glitch/shake/tear 等） |
| comm | 通讯系统（触发对话、注册角色） |
| env | 环境监测（读取传感器、注入事件、添加任务） |
| camera | 摄像头控制（解锁/上线/触发异常） |
| radio | 无线电信号管理 |
| mail | 邮件投递 |
| triggers | 触发器系统 |
| settings | 设置读写 |
| audio | 音频播放（环境音/音效/媒体） |
| save | 存档数据读写 |
| theme | 主题颜色查询 |
| utils | 工具函数（定时器/Tween/日志） |

## 重要陷阱

- ModAPI 限制文件访问范围：仅允许 Mod 自身目录 + vdisc/
- 包格式：`.zip` 文件，根目录含 `mod_manifest.json`
- `mod_api.gd` 有 1075 行——修改时注意影响所有已安装 Mod
- 实际的 Mod 生命周期管理在 `scripts/package_manager.gd`（817 行）中
