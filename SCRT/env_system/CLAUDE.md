# env_system/ — 环境观测台与详细传感器数据

更新：2026-10-01。上级入口：CLAUDE.md。当前 demo 不含无人机；未运行 Godot，等待玩家验收。

## 当前实现

| 文件 | 用途 |
|---|---|
| env_monitor.gd | 既有 21 传感器、天气、派生参数、异常、设备和玩家环境存档 |
| env_task_manager.gd | 旧任务 ID 与剧情门控兼容、首次日报计分、每日快照和历史存档 |
| env_observation.gd | 短采集、固定快照、可选复测／关注／设备校准、提交、迁移与隔离 debug |
| env_map_canvas.gd | 圆形监视盘、方形底图占位、网格与比例尺、设备来源、操作区和历史页 |
| env_viewer.gd | CRT CanvasLayer 覆盖层与输入，2 张地图、6 页原详细数据、1 页日报历史 |

## 生命周期与存档

main 创建 EnvObservation 并注入 main / EnvMonitor / EnvTaskManager，在 `_process` 驱动采集。采集约 2.4 秒，不自动校准或提交。底图留空，用正方形占位；数据来源和设施坐标明确标为示意。

`env_task_progress.json` 新增 `observation_data` 和 `observation_history`，同样经既有 `get_save_data()` 进入磁盘 extra.env_task_data。日报最多 30 份，每日 reset 保留历史；新账号／无有效进度采用 `reset_for_new_day(false)` 清除前一账号历史。旧版已提交日报在跨日前补成归档，不再次计分。不修改 story.version。

首次提交沿用单次 +1 daily（Day0 自动计分禁用），基础采集不逐项计分、无自动全勤奖励。特殊任务仍单独 +1。任务完成及检查均防重复。`requires_tasks`、日报提交门控及登录跨日保持兼容。profile 第二页展示绩效概览与最近日报来源。

`on_scan_complete` 为兼容旧剧情在日报提交后触发；不是采集结束即触发。完成与异常通讯通过 DailyDialogueManager 的持久化队列，在覆盖界面、拨号与通讯结束后按次播放，避免 timer 到时穿透。EnvObservation 的 notify_pending 也随进度保存。

## 命令与操作

- `env` / `env view` / `env map`：打开观测台。
- `env scan` / `env collect`：打开并开始短采集。
- `env report`：提交；`env retest` / `env mark` / `env calibrate`：当前疑点操作。
- `env history`：日报；`env details`：原详细仪表盘。
- 旧 read/anomaly/check/status/weather/events 入口进入观测台；repair/sensor 保留维护／详情命令。
- 观测台为命令操作：help/scan/status/issues/select/retest/mark/next/calibrate/report/map/details/history/clear/exit；取消操作快捷键与点击按钮。左侧小字号日志和输入在各页保留，右侧简报；details evidence 集中快照、来源和疑点证据。上下键仅调出命令历史。
- register_command_extension(name, Callable) / unregister_command_extension(name) 预留无人机等独立模块接口，handler(Array[String]) 返回 String。demo 不含无人机实现。
- `debug 114514 env normal/device/mystery/sea/clear`：隔离预览，不保存、计分或触发剧情；clear 返回玩家数据。

## 配置与扩展

`data/env_observation.json`：采集时间、map_texture、地图半径／网格、regions 来源和 normalized position、contacts。正常 contacts 为空；sea debug 的航迹和雷区是示意。底图由用户绘制冷战风格 SVG 矢量地形；map_texture 可直接指定导入后的 SVG 资源路径，空值继续显示方形占位。Godot 将 SVG 导入为纹理，清晰度按导入分辨率管理。地形先绘制，网格、扫描线和动态标记独立叠加。

EnvObservation 公开 begin_capture/process/state/submit/retest/mark_issue/calibrate_issue/migrate_legacy/set_preview/contacts。旧 EnvMonitor 的 manifest.env_config 覆盖、异常等级、扫描模式和任务仪式 API 保留作为底层能力，不意味着旧文档列出的所有命令都已启用。

正式内容应按区域 ID、证据来源和事件 ID 接入 camera/radio/文件；无人机、3D 拍照和飞行约束是后续规划，不在本版实现。

手动验收：docs/upgrade-plans/environment-manual-test-plan.md。完整规划：docs/upgrade-plans/env-observation-improvement-plan.md。

### 2026-10-01 第二轮界面反馈（覆盖此前交互说明）

复用桌面底部输入框，通过 main 的 env 分流执行指令，不重复连接提交信号。左侧反馈无标题、外框和滚动条，按当前尺寸折行保留最新内容；右侧仅保留环境简报。恢复地图图标点击，使用 [ ] 表示选中设施／目标，本站及无目标不加框，圆盘空白点击取消。Tab 切换近海／远海并保留输入内容；manual/help/guide 打开操作说明页面，将图例整合进说明页。详情与历史继续可使用底部命令。无人机注册接口保持，尚未实现无人机。未运行 Godot，等待用户测试。
