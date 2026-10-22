# SCRT-Reader Core

**CRT 终端模拟器 · 内容包阅读器 · 可扩展叙事框架**

SCRT-Reader 是 SCRT Studio 在开发终端交互式叙事游戏《SCRT》过程中构建的软件框架，使用 Godot 4.7.1 与 GDScript。它以模拟计算机终端为交互入口，将档案阅读、虚拟文件系统、通讯、无线电和环境观测等功能组织在同一个界面中。

本仓库当前公开的是 **SCRT-Reader Core 无剧情源码版**，供开发者学习、修改，以及制作自己的终端阅读与交互内容。面向玩家的、包含剧情与配套素材的版本通过 **Releases 发行附件**提供。

[下载含剧情的试玩版本](https://github.com/Mr-J-And114/SCRT-Reader/releases/latest) · [查看全部发行版本](https://github.com/Mr-J-And114/SCRT-Reader/releases) · [反馈问题](https://github.com/Mr-J-And114/SCRT-Reader/issues) · [支持开发](#支持开发)

## 公开源码与游戏发行版

| 项目 | 当前 `main` 分支：Core 源码版 | Releases：游戏发行包 |
| --- | --- | --- |
| 主要用途 | 阅读源码、二次开发、制作和加载内容包 | 下载并体验作者发布的游戏内容 |
| 内容范围 | 通用框架、场景、界面、字体、中立配置及开发文档 | 对应版本的游戏程序、剧情与配套素材，以各版本说明为准 |
| 原创剧情与角色素材 | 不包含正式剧情、人物数据、立绘、语音或正式故事盘 | 随具体发行包提供 |
| 使用方式 | 通过 Godot 编辑器导入工程运行 | 下载作者上传的发行附件，解压后按说明启动 |
| 授权范围 | 框架代码采用 MIT，第三方依赖另见许可说明 | 游戏内容及素材按对应版本的署名、许可和发行说明使用 |

**想体验游戏，请前往 Releases 下载发行附件。** GitHub 自动生成的 `Source code (zip)` 和 `Source code (tar.gz)` 只是对应标签的源码快照，不等同于含剧情的游戏包。

当前已发布 [Demo-V1.0.1](https://github.com/Mr-J-And114/SCRT-Reader/releases/tag/Demo-V1.0.1)，发行附件为 `SCRT-DEMO-V1.0.1.rar`，包含 Day0 至 Day3 的剧情。该 Demo 提供这一版本的完整游玩内容，项目仍处于开发与优化阶段，不代表整部游戏已经完成。后续内容范围与运行要求请以各次 Release 的说明为准。

> 当前 `main` 的无剧情范围适用于 Core 替换后的文件树。仓库保留了旧提交历史与旧标签，其中仍可能访问历史内容；保留历史不意味着这些内容获得了新的授权。详见[发布说明](docs/PUBLISHING.md)。

## Core 提供什么

| 功能 | 说明 |
| --- | --- |
| CRT 终端界面 | 终端命令交互、CRT 显示效果、主题与基础运行设置 |
| 虚拟磁盘与阅读器 | 扫描和加载 ZIP 格式的 `.scp` 内容包，浏览虚拟文件与文档 |
| 文本与媒体 | CRTML 文本标记、通用文档模板、图片、音频及 OGV 视频展示 |
| 本地账号与进度 | 本地账号、用户档案与按账号保存的运行数据 |
| 通讯与邮件 | 拨号、DTMF、通讯与邮件的通用代码，具体对象和内容由内容包提供 |
| 无线电与环境观测 | RADIO、环境观测和任务相关的通用接口，按内容包配置运行 |
| 扩展接口 | Mod API 与内容包扩展入口，便于接入自己的数据和交互逻辑 |

Core 保留通用实现，正式游戏使用的剧情、人物和任务数据已作中立适配。因此，首次打开时没有主线故事、摄像头对象或来电内容属于正常状态；这些功能需要相应内容包提供数据。

## 运行公开源码版

1. 安装 **Godot 4.7.1**，克隆或下载本仓库当前 `main` 分支。
2. 在 Godot 项目管理器中导入 `SCRT/project.godot`，等待资源导入完成。
3. 运行工程主场景，按终端提示创建自己的本地账号并登录。Core 没有预置管理员密码。
4. 输入 `help` 查看当前可用命令；未加载内容包时，可以先了解终端、账号和阅读器入口。

账号、进度与运行设置写入工程或可执行文件所在目录的 `saves/`，应作为个人数据保留，不要提交到源码仓库，也不要随内容包分发。

### 加载自己的内容包

将有权使用的 ZIP 格式 `.scp` 文件放入 `SCRT/vdisc/`，目录不存在时自行创建。登录后输入：

```text
scan
load <编号>
```

把 `<编号>` 替换为扫描结果中的磁盘编号，再按终端提示浏览文件。包内可定义文本、媒体及各系统所需的数据；结构和最小示例见[内容包说明](docs/content-pack.md)。

### 兼容性与可选依赖

- **文件名编码：**推荐使用 UTF-8 ZIP。本仓库没有分发来源未核实的完整 GBK 映射表；内置回退只覆盖标点、全角字母和数字，无法保证旧 GBK 汉字文件名正确读取。遇到乱码时，请先将压缩包转换为 UTF-8 文件名。
- **媒体扩展：**OGV 使用 Godot 内置支持。FFmpeg 原生扩展和录制语音库未随 Core 分发；其他格式或相关功能需要自行安装合法且兼容当前引擎的依赖。
- **模组权限：**Mod 脚本具有宿主权限，只有信任其来源时才加载。

## 开发与反馈

欢迎通过 [Issues](https://github.com/Mr-J-And114/SCRT-Reader/issues) 提交问题或建议。报告时请注明使用的是 Core 源码版还是具体 Release，并附版本号、复现步骤及预期行为；分享日志或截图前请移除账号、存档和个人信息。

| 文档 | 内容 |
| --- | --- |
| [内容包说明](docs/content-pack.md) | 内容包结构、编码建议与最小示例 |
| [维护说明](public-sync/README.md) | 逐文件白名单、增量同步、适配冲突与失败恢复 |
| [验证记录](docs/VALIDATION.md) | 已执行的检查及验证范围 |
| [发布说明](docs/PUBLISHING.md) | 仓库历史边界与人工审阅、提交和推送流程 |
| [第三方许可](THIRD_PARTY_NOTICES.md) | 字体来源及可选依赖的授权说明 |

公开版通过确定性的本地同步工具维护。日常通用代码更新按 SHA-256 增量同步；公开适配的来源发生变化时，工具会报告受影响文件与冲突位置，交由维护者审阅。普通同步无需联网或 AI 服务，操作入口见维护说明。

## 许可证与内容边界

Core 框架代码采用 [MIT License](LICENSE)。随仓库分发的 Sarasa Mono SC 字体采用 SIL Open Font License 1.1，完整许可见 [`SCRT/fonts/OFL.txt`](SCRT/fonts/OFL.txt) 和[第三方说明](THIRD_PARTY_NOTICES.md)。

正式游戏的剧情、人物、图像、音频以及用户提供的内容包，不因框架开源而自动获得 MIT 授权。使用或再分发这些内容时，请查阅对应作品、依赖和发行版本的许可及署名要求。

## 支持开发

《SCRT》由 **SCRT Studio** 持续设计、开发与维护。我们希望继续完善终端交互与阅读体验，推进剧情创作、素材制作和后续版本迭代，同时维护这里公开的 Core 框架。

如果你喜欢这个项目，欢迎通过以下平台支持开发，也可以在对应主页了解项目动态与赞助说明。各平台的方案、权益及更新安排以主页公告为准。

<p>
  <a href="https://afdian.com/a/scrtstudio?tab=home"><img src="https://pic1.afdiancdn.com/static/img/welcome/button-sponsorme.png" width="200" alt="在爱发电支持 SCRT Studio"></a>
</p>

<p>
  <a href="https://ko-fi.com/scrtstudio"><img src="docs/assets/support-kofi.svg" width="200" alt="在 Ko-fi 支持 SCRT Studio"></a>
  <a href="https://www.patreon.com/SCRTStudio"><img src="docs/assets/support-patreon.svg" width="200" alt="在 Patreon 支持 SCRT Studio"></a>
</p>

[爱发电：SCRT Studio](https://afdian.com/a/scrtstudio?tab=home) · [Ko-fi：scrtstudio](https://ko-fi.com/scrtstudio) · [Patreon：SCRTStudio](https://www.patreon.com/SCRTStudio)

感谢每一位试玩、反馈、分享和支持项目的朋友。
