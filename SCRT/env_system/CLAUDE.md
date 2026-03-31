# env_system/ — 环境监测系统 (Environmental Monitoring)

> 上级文档：[/CLAUDE.md](/CLAUDE.md)
> 修改环境监测系统后请同步更新本文件。

观测站环境传感器系统，包含每日任务、天气模拟和异常检测。
玩家通过 `env scan` 执行每日例行扫描，通过 `env view` 查看仪表盘详情。

## 文件列表

| 文件 | 行数 | 用途 |
|---|---|---|
| env_monitor.gd | 1173 | 核心模拟引擎：21 传感器 + 6 派生参数、系统时钟同步、传感器间物理关联、天气模式、异常检测、事件系统 |
| env_task_manager.gd | 703 | 每日任务清单：检查→读数→校准→报告，任务依赖链，天数推进门控，绩效加分钩子 |
| env_viewer.gd | 578 | 6 页仪表盘覆盖层（总览含派生参数/大气/海洋/地球物理/大气成分/事件异常），含迷你趋势图 |

## 架构

```
EnvMonitor（核心模拟）
├─ 21 传感器，基于萨哈林岛基准月均值
├─ 6 派生参数：露点、风寒、热指数、体感温度、蒲福风级、气压趋势
├─ 传感器间物理关联（气压→风速→降水→能见度→浪高）
├─ 系统时钟同步（真实时间驱动昼夜节律，虚构日期显示）
├─ 天气模式系统（8 种模式，气压趋势驱动切换）
├─ 特殊事件系统（风暴/磁异常/SCP 事件）
├─ 异常检测引擎（阈值 + 偏差检查）
├─ 潮汐模型（真实时间计算相位）、风向模拟
└─ 故事包覆盖：通过 manifest "env_config" 节配置

EnvTaskManager（每日任务）
├─ 8 项必做日常任务（检查→读数→校准→报告）
├─ 任务依赖系统（报告需要所有读数完成）
├─ 动态特殊任务（由事件/Mod 注入）
└─ 天数推进门控（所有任务 + 报告完成才能进入下一天）

EnvViewer（仪表盘覆盖层）
├─ 6 页：总览、大气、海洋、地球物理、大气成分、事件异常
├─ 实时传感器读数 + 趋势指示器
├─ 迷你火花线图（基于历史读数）
└─ 异常闪烁指示 | 键盘：←/→ 翻页, TAB 下一页, Q/ESC 关闭
```

## 关键信号 (env_monitor)

| 信号 | 参数 | 触发时机 |
|---|---|---|
| `day_changed` | `day_number: int` | 天数推进 |
| `anomaly_detected` | `anomaly_id: String, data: Dictionary` | 检测到异常（触发 daily_dialogue 的 `on_anomaly`） |
| `sensor_failure` | `sensor_id: String` | 传感器故障 |
| `weather_changed` | `old_pattern: String, new_pattern: String` | 天气变化 |
| `event_started` | `event_id: String, event_data: Dictionary` | 特殊事件开始 |
| `event_ended` | `event_id: String` | 特殊事件结束 |

## 关键信号 (env_task_manager)

| 信号 | 触发时机 |
|---|---|
| `task_completed(task_id)` | 单项任务完成 |
| `task_failed(task_id, reason)` | 任务失败 |
| `all_tasks_completed()` | 所有任务完成 |
| `day_can_advance()` | 可以推进到下一天 |

## 传感器列表（21 个参数）

| 类别 | 传感器 ID |
|---|---|
| 大气 (atmosphere, 10) | air_temp, humidity, pressure, wind_speed, wind_dir, precipitation, visibility, cloud_cover, light_level, uv_index |
| 海洋 (ocean, 4) | sea_temp, tide_level, wave_height, salinity |
| 地球物理 (geophysics, 5) | mag_field, mag_declination, radiation, seismic, soil_temp |
| 大气成分 (composition, 2) | o2_concentration, co2_concentration |

## 派生参数（6 个，由传感器读数交叉计算）

| 参数 | 公式 | 依赖传感器 |
|---|---|---|
| 露点温度 (dew_point) | Magnus 公式 | air_temp, humidity |
| 风寒指数 (wind_chill) | 加拿大标准 (T<10°C, V>4.8km/h) | air_temp, wind_speed |
| 热指数 (heat_index) | Rothfusz 回归 (T>27°C, RH>40%) | air_temp, humidity |
| 体感温度 (feels_like) | 低温=风寒，高温=热指数，中间=实际 | air_temp, humidity, wind_speed |
| 蒲福风级 (beaufort) | 标准 0-12 级分级 | wind_speed |
| 气压趋势 (pressure_tendency) | 3h 滑动窗口: ±3.5hPa=急变 | pressure (历史) |

## 传感器间物理关联

- 气压下降 → 风速增大 (+10%~30%)
- 高湿度 + 低温 → 能见度降低（雾效应）
- 降水增加 → 能见度进一步降低
- 强风 (>10m/s) → 浪高增加

## 时间系统

- **系统时钟同步**：`current_hour` 每帧从 `Time.get_time_dict_from_system()` 读取
- **虚构日期**：`fictional_year/start_month/start_day` 配置起始日期，`current_day` 递增偏移
- **天数推进**：仅在所有每日任务完成 + 游戏重启/重新登录时推进
- **潮汐相位**：由当前真实小时直接计算 `fmod(hour / 12.42, 1.0) * TAU`
- **天气切换**：真实秒数计时（默认 45 分钟切换一次），由气压趋势影响方向

## 数据生成机制

- **主种子**：每次游戏 + 天数 → 确定性每日数据
- **月均基准线**：基于萨哈林岛实际数据，按月插值平滑过渡
- **昼夜曲线**：sin/cos 插值（温度 14:00 峰值，湿度反向），由系统时钟驱动
- **天气修正**：8 种天气模式叠加传感器基准线
- **事件修正**：可叠加、有持续时间
- **传感器退化**：校准漂移模拟 + 故障率
- **潮汐模型**：半日潮（12.42 小时周期），由真实时间驱动
- **光照/UV**：基于太阳角度计算
- **交叉关联**：读数生成后应用物理约束（气压→风速→降水→能见度）

## Manifest 配置

键名：`"env_config"`，支持以下子键覆盖默认值：

| 子键 | 说明 |
|---|---|
| `location` | 位置参数覆盖 |
| `sensors` | 传感器定义覆盖/新增（自动初始化读数/状态/校准） |
| `baselines` | 月均基准线覆盖 |
| `weather_patterns` | 天气模式新增 |
| `anomaly_types` | 异常类型新增 |
| `events` | 事件定义新增 |
| `tasks` | 任务定义覆盖/新增 |
| `master_seed` | 随机种子覆盖 |

## 存档数据

存储在故事存档的 `extra["env_data"]` 和 `extra["env_task_data"]` 中。

## 重要陷阱

- 昼夜曲线使用 sin/cos 插值——温度 14:00 达到峰值，湿度与之反向
- 潮汐模型为半日潮（12.42 小时周期），非简单正弦波
- 天气模式修正可叠加（8 种模式各自影响传感器基准线）
- `current_readings` 字典以 sensor_id → float 为键值对
- env CLAUDE.md 中 `"env_config"` 是正确的 manifest 键名（非 `"env_monitor"`）
