# camera_system/ — CCTV Surveillance

CCTV monitoring system with shader-rendered surveillance camera feeds.

## Architecture

```
CameraFeed (data model) → CameraManager (registry/lifecycle) → CameraViewer (overlay+shader)
```

- **CameraFeed**: base/depth/light/anomaly image paths + cached textures, lens parameters (viewport, pan_speed, pan_bounds), effect parameters, anomaly system (trigger/duration/cooldown)
- **CameraManager**: camera registration from manifest, unlock/lock, online/offline, anomaly triggering with safety check, auto-trigger in `process()`, save/load, image loading via FileSystem
- **CameraViewer**: fullscreen overlay with `camera_effect.gdshader`, UI overlay (name, location, timestamp, signal bar), keyboard controls (arrows=pan, 1-9=switch, TAB=next, F=light mode, Q/ESC=close)

## Shader Pipeline (camera_effect.gdshader)

1. Depth-based parallax offset (base + anomaly layers)
2. 3 lighting modes: spotlight (circle mask), nightvision (green tint), infrared (pseudocolor heatmap)
3. Noise / scanlines / vignette / signal interference / snow
4. Color compression (desaturation + green shift for CRT feel)
5. Anomaly smooth blend transition

## Anomaly Safety (重要)

Visual effects blocked when `effect_settings.is_effect_allowed("jumpscare")` returns `false` (OFF mode).
**Trigger actions (mail delivery, file unlock, etc.) always execute regardless of effect level.**

## Manifest Config

Key: `"camera_system"` in manifest.json. Contains `"cameras"` dict keyed by camera ID.
Each camera: `name`, `location`, `unlocked`, `online`, `base_image` (required), `depth_map`, `light_mode`, `light_image`, `viewport_size`, `viewport_pos`, `pan_speed`, `pan_bounds`, `noise_intensity`, `scanline_intensity`, `vignette`, `signal_quality`, `snow_intensity`, `anomalies` array.

## Trigger Actions

| Action | Description |
|---|---|
| `camera_unlock:cam_id` | Unlock camera |
| `camera_lock:cam_id` | Lock camera |
| `camera_online:cam_id` | Set camera online |
| `camera_offline:cam_id` | Set camera offline |
| `camera_anomaly:cam_id[:anom_id]` | Trigger anomaly |
| `camera_signal:cam_id:quality` | Set signal quality (0-1) |

## Save Data

Stored in `extra["camera_data"]` within story save files. Per-camera: `unlocked`, `online`, `signal_quality`.
