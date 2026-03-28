# env_system/ — Environmental Monitoring

> 上级文档：[/CLAUDE.md](/CLAUDE.md)
> 修改环境监测系统后请同步更新本文件。

Station environmental sensor system with daily tasks, weather simulation, and anomaly detection.

## Files

| File | Lines | Purpose |
|---|---|---|
| env_monitor.gd | ~800 | Sensor data, weather patterns, diurnal curves, anomaly detection |
| env_task_manager.gd | ~400 | Daily station tasks: checklist, completion tracking, day advance |
| env_viewer.gd | ~600 | 6-page overlay dashboard (总览/大气/海洋/地球物理/大气成分/事件异常) |

## Key Signals (env_monitor)

- `day_changed(day_number: int)` — new day started
- `anomaly_detected(anomaly_id: String, data: Dictionary)` — triggers `on_anomaly` daily_dialogue
- `weather_changed(old_pattern: String, new_pattern: String)`
- `event_started(event_id: String, event_data: Dictionary)` / `event_ended(event_id: String)`

## Key Signals (env_task_manager)

- `task_completed(task_id: String)` / `task_failed(task_id: String, reason: String)`
- `all_tasks_completed()` / `day_can_advance()`

## Sensors (21 total, grouped)

- **Atmospheric**: air_temp, humidity, barometric, wind_speed, wind_direction, visibility, rainfall
- **Ocean**: sea_temp, wave_height, salinity, tide_level, current_speed
- **Seismic**: seismic_activity, ground_temp
- **Biological**: radiation, uv_index, dissolved_oxygen, ph_level
- **Electromagnetic**: em_field, signal_noise, magnetic_declination

## Critical Gotchas

- Diurnal curves use sin/cos interpolation — temperature peaks at ~14:00, humidity inverse
- Tidal model is semi-diurnal (12.42h period), not simple sin wave
- Weather patterns stack modifiers (8 pattern types affect sensor baselines)
- `current_readings` dict keyed by sensor_id → float; access via command output formatting

## Save Data

Stored in `extra["env_data"]` and `extra["env_task_data"]` within story save files.

## Manifest Config

Key: `"env_config"` or `"env_monitor"` in manifest.json. Overrides default sensor baselines, weather sequences, and anomaly thresholds per story.
