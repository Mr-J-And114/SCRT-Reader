# Architecture Reference

<!-- Extracted from SCRT/AI_HANDOFF.md §2-4, §7, §10, §13-15 -->

## Core Dependency Graph

```
main.gd (extends Control) — the god object
├─ fs: FileSystem — virtual filesystem tree
├─ save_mgr: SaveManager — per-user per-story save/load
├─ tw: Typewriter (extends Node) — queued typewriter output + inline FX
├─ T: ThemeManager — 4 color themes (green/amber/blue/white)
├─ story_loader: StoryLoader — parse .scp ZIP → populate fs
├─ cmd_handler: CommandHandler — CLI command registry + dispatch
├─ disc_mgr: DiscManager — scan/load/eject story discs
├─ user_mgr: UserManager — multi-user accounts, profiles, stats
├─ crtml: CrtmlParser — Markdown-like markup → BBCode for RichTextLabel
├─ pkg_mgr: PackageManager — mod .scp install/uninstall/runtime
├─ settings_mgr: SettingsManager — registry-based settings with TUI
├─ comm_mgr: CommManager — dialogue/comm system (characters, calls, presentation)
│  ├─ call_handler: CallHandler — SILENT/FORCED/ANSWERABLE incoming call flow
│  ├─ comm_ui: CommUI — dialogue bar, card/meeting/presentation modes, history
│  │  └─ presentation: PresentationOverlay — slide display with fit/align/transitions
│  ├─ character_registry: CharacterRegistry — character lifecycle (builtin/disc/mod)
│  │  └─ asset_library: CharacterAssetLibrary — asset profiles, texture loading
│  ├─ dial_mgr: DialManager — DTMF dialing, voice call routing, modem download state machine
│  ├─ tone_gen: DialToneGenerator — procedural DTMF/ringback/busy/modem/hangup audio synthesis (owned by dial_mgr)
├─ trigger_sys: TriggerSystem — event-driven triggers (enter dir, open file, etc.)
├─ mail_sys: MailSystem — in-game mail inbox with delayed delivery
├─ effect_sys: EffectSystem — timeline-based multi-step effect sequences
├─ effect_settings: EffectSettings — photosensitive/intensity levels
├─ boot_sequence: BootSequence — keyframe-driven boot/shutdown animations
├─ loading_screen: LoadingScreen — disc loading animation (custom or default, exclusive mode)
├─ doc_viewer: DocumentViewer — paginated document overlay
├─ profile_builder: ProfileBuilder — user profile card pages
├─ explore_viewer: ExploreViewer — file tree explorer panel
├─ image_viewer: ImageViewer — zoomable image viewer with scanline
├─ oscilloscope: Oscilloscope — audio spectrum/lissajous visualizer
├─ video_player_viewer: VideoPlayerViewer — video playback overlay
├─ radio_receiver: RadioReceiver — radio tuning/morse/SSTV/audio station/hidden signals decoder
├─ decode_viewer: DecodeViewer — cipher decode visualization
├─ ui_sound: UiSound — procedural keystroke/click SFX
├─ camera_mgr: CameraManager — CCTV camera management (register/unlock/anomaly/save)
├─ camera_viewer: CameraViewer — fullscreen camera overlay with shader rendering
├─ ui_manager(static calls): UIManager — theme-aware style builder
├─ audio_manager: AudioManager (extends Node) — ambient/sfx/media players, load from bytes (MP3/OGG/WAV)
└─ crt_shader: CRTShader (extends ColorRect) — CRT post-process on CanvasLayer(10)
```

## Scene Tree (main.tscn)

```
Main (Control, fullrect) [main.gd]
├─ Background (ColorRect, black)
│  ├─ Backgrund (TextureRect, background_vignette shader)
│  └─ CenterContainer
│     └─ BackgroundLogo (TextureRect, background_logo shader, 600×600)
├─ MainContent (VBoxContainer, fullrect)
│  ├─ StatusFrame (PanelContainer)
│  │  └─ StatusBar (HBoxContainer, h=30)
│  │     ├─ PathLabel (Label) — shows "[/root]" etc.
│  │     └─ MailIcon (Label, right-aligned) — "[Mail]"
│  ├─ OutputArea (ScrollContainer, expand)
│  │  └─ OutputText (RichTextLabel, bbcode=true, fit_content=true)
│  └─ InputFrame (PanelContainer)
│     └─ InputArea (HBoxContainer, h=30)
│        ├─ Prompt (Label) — ">"
│        └─ InputField (LineEdit, expand)
├─ AudioManager (Node) [audio_manager.gd]
└─ CRTEffect (CanvasLayer, layer=10)
   └─ CRTShader (ColorRect) [crt_shader.gd] — crt_effect.gdshader
```

## Script Reference

### Core Scripts (`res://scripts/`)

| File | Class | Lines | Purpose |
|---|---|---|---|
| main.gd | — | 2209 | God object: init, input routing, mode management, UI updates, media, effects |
| file_system.gd | FileSystem | 472 | Virtual FS tree (FSNode), permissions, clearance, ambient sounds, path utils |
| command_handler.gd | CommandHandler | 2346 | CLI command registry (desktop/disc/global), history, tab-complete, all `_cmd_*` handlers |
| story_loader.gd | StoryLoader | 708 | Parse .scp ZIP files, detect encoding (UTF-8/GBK), build manifest+filesystem |
| disc_manager.gd | DiscManager | 698 | Scan vdisc/, load/eject stories, mod support, auto-save |
| crtml_parser.gd | CrtmlParser | 1263 | Markdown→BBCode: headings, bold, italic, spoilers, tables, media tags, effect tags, page breaks |
| typewriter.gd | Typewriter | 520 | Queued text output with char-by-char typing, inline FX triggers, progress bars |
| save_manager.gd | SaveManager | 228 | Per-user per-story JSON save/load, auto-save |
| user_manager.gd | UserManager | 856 | Multi-user accounts, login/register/passwd, profiles, stats, story progress |
| audio_manager.gd | AudioManager | 586 | Ambient(crossfade)/SFX/Media players, ducking, spectrum analyzer, load from bytes (MP3/OGG/WAV) |
| crt_shader.gd | — | 416 | CRT post-process: glitch, shake, tear, boot/shutdown, noise burst, blackout |
| theme_manager.gd | ThemeManager | 518 | 4 themes, color palette (ThemeColors), CRT/background/logo shader refresh |
| boot_sequence.gd | BootSequence | 813 | JSON-driven keyframe boot/shutdown: screen_off/on, text, glitch, progress, audio |
| loading_screen.gd | LoadingScreen | 543 | Disc loading keyframe animation (custom via loading_screen.json or built-in default) |
| trigger_system.gd | TriggerSystem | 726 | Event triggers: enter_dir, open_file, command, idle, level_change → actions (mail, glitch, lock, etc.) |
| mail_system.gd | MailSystem | 891 | Mail inbox, delayed delivery, global+per-story mail, blink notification |
| effect_system.gd | EffectSystem | 451 | Timeline effect sequences (glitch, shake, sound, text, reboot, brightness, etc.) |
| effect_settings.gd | EffectSettings | 175 | Effect intensity levels (full/mild/off), photosensitive mode |
| settings/settings_manager.gd | SettingsManager | 903 | Registry-based settings system with categories, TUI interface, import/export |
| settings/settings_registry.gd | — | — | Setting definitions registration |
| settings/settings_storage.gd | — | — | JSON storage backend for settings |
| header_parser.gd | HeaderParser | 247 | Parse file headers (metadata block between markers) |
| cipher_decoder.gd | CipherDecoder | 584 | Caesar, Vigenere, substitution, base64, morse, ROT13, atbash, reverse |
| morse_engine.gd | MorseEngine | 347 | Morse encode/decode, playback events, numbers station mode |
| radio_audio_generator.gd | RadioAudioGenerator | 311 | Procedural noise/tone/SSTV audio generation |
| radio_config_parser.gd | RadioConfigParser | 319 | Parse radio signal definitions from config/manifest; RadioSignal class with hidden, content_audio, proximity_range |
| radio_signal_manager.gd | RadioSignalManager | 344 | Signal database, quality calc (progressive proximity), discovery, bookmarks, scan |
| sstv_decoder.gd | SSTVDecoder | 310 | SSTV image receive simulation with scanline noise |
| package_manager.gd | PackageManager | 817 | Mod system: install/uninstall .scp mods, hook dispatch, mod lifecycle |
| ui_manager.gd | UIManager | 466 | Procedural UI style: cursors, scrollbar, panel themes, font setup |
| ui_sound.gd | UiSound | 200 | Procedural SFX: keystroke, enter, backspace, HDD read, click |
| profile_builder.gd | ProfileBuilder | 242 | Build 3-page profile card for doc_viewer |
| video_player.gd | VideoPlayerViewer | 748 | Video overlay with controls, ffmpeg fallback support |
| daily_dialogue_manager.gd | DailyDialogueManager | 414 | Per-day dialogue/mail triggers, main storyline loading |
| env_monitor.gd | EnvMonitor | 919 | Environmental simulation: sensors, weather, events, anomalies, daily seed |
| env_task_manager.gd | EnvTaskManager | 697 | Daily task checklist: inspection, recording, calibration, reporting |
| camera_feed.gd | CameraFeed | 320 | Single camera data model: base/depth/light/anomaly images, lens params |
| camera_manager.gd | CameraManager | 435 | Camera registry, unlock/lock, anomaly triggers, save/load, image loading |

### Viewer/Overlay Scripts

| File | Class | Lines | Purpose |
|---|---|---|---|
| document_viewer.gd | DocumentViewer | 668 | 2-page overlay (left/right RTL), pagination, typing animation |
| explore_viewer.gd | ExploreViewer | 477 | File tree panel, story progress display |
| image_viewer.gd | ImageViewer | 634 | Zoomable image viewer, pan, scan effect, _ImageCanvas inner class |
| oscilloscope.gd | Oscilloscope | 820 | Spectrum analyzer + Lissajous, _ScopeCanvas inner class |
| radio_receiver.gd | RadioReceiver | 1804 | Full radio UI: tuning, bands, morse decode, SSTV, audio station, hidden signals, waterfall, _RadioCanvas inner class |
| decode_viewer.gd | DecodeViewer | 1456 | Cipher decode animation viewer, _DecodeCanvas inner class |
| env_viewer.gd | EnvViewer | 557 | Environmental data panel overlay, 6 pages, _EnvCanvas inner class |
| camera_viewer.gd | CameraViewer | 656 | CCTV fullscreen overlay, shader-rendered surveillance feed, pan/switch controls |

### Comm System (`res://comm_system/`)

| File | Class | Lines | Purpose |
|---|---|---|---|
| comm_manager.gd | CommManager | 1259 | Dialogue orchestration, call routing, tutorial flow, `comm` command handler |
| comm_dialogue_player.gd | CommDialoguePlayer | 377 | Dialogue playback engine (line-by-line, choices, conditions, slides, silent stop) |
| comm_character.gd | CommCharacter | 426 | Lightweight character data model (identity, voice, state, delegates to animator) |
| character_registry.gd | CharacterRegistry | 297 | Character lifecycle, registration (builtin/disc/mod sources) |
| character_asset_library.gd | CharacterAssetLibrary | 420 | Asset profiles, modular texture loading (res:// + virtual FS) |
| character_animator.gd | CharacterAnimator | 387 | Animation engine (mouth, blink, action, layer overrides, costumes) |
| call_handler.gd | CallHandler | 285 | Call mode handler: SILENT/FORCED/ANSWERABLE ring + answer flow |
| presentation_overlay.gd | PresentationOverlay | 295 | Presentation mode slide overlay (image display, fit/align, transitions) |
| comm_sprite_renderer.gd | — | 181 | Character sprite rendering (card mode) |
| comm_ui.gd | CommUI | 1289 | Comm overlay UI (dialogue bar, card/meeting/presentation mode, history) |
| comm_voice.gd | — | 188 | Procedural voice synthesis (sine/square/saw tones) |
| dial_manager.gd | DialManager | 831 | DTMF dial state machine, voice call routing, modem handshake/download, phonebook |
| dial_tone_generator.gd | DialToneGenerator | 376 | Procedural audio: DTMF keys, ringback, busy tone, modem handshake, data noise, hangup, ring |

### Mod System (`res://modder/`)

| File | Class | Purpose |
|---|---|---|
| mod_api.gd | ModAPI | 1075-line API surface for mods: output, FS access, commands, audio, effects, UI, comm, etc. |
| mod_base.gd | ModBase | Base class for mods: lifecycle hooks (_on_install, _on_enable, _process, event callbacks) |

### Templates (`res://templates/`)

| File | Lines | Purpose |
|---|---|---|
| article_viewer.gd | 466 | Article-style document template |
| chat_viewer.gd | 823 | Chat log template |
| email_viewer.gd | 788 | Email template |
| two_page_reader.gd | 571 | Two-page book template |

## Shaders

| File | Purpose |
|---|---|
| shaders/crt_effect.gdshader | CRT post-process (scanlines, curvature, chromatic aberration, noise, brightness, shake offset) |
| shaders/background_vignette.gdshader | Background vignette effect |
| shaders/background_logo.gdshader | SCP logo background effect |
| camera_system/camera_effect.gdshader | CCTV surveillance shader: depth parallax, 3 light modes (spotlight/nightvision/infrared), noise, scanlines, signal interference, anomaly blend |

## Environment Monitoring System

### Architecture
```
env_monitor.gd (EnvMonitor) — Core simulation + data generation
├─ 20+ sensors with Sakhalin baselines (monthly averages)
├─ Weather pattern system (8 patterns, seasonal weighting)
├─ Special event system (storms, magnetic anomalies, SCP events)
├─ Anomaly detection engine (threshold + deviation checks)
├─ Diurnal cycles, tidal model, wind direction simulation
└─ Story pack overrides via manifest "env_config" section

env_task_manager.gd (EnvTaskManager) — Daily task checklist
├─ 8 required daily tasks (check → read → calibrate → report)
├─ Task dependency system (report requires all readings)
├─ Dynamic special tasks (injected by events/mods)
├─ Formatted output generators for each task type
└─ Day advancement gating (all tasks + report required)

env_viewer.gd (EnvViewer) — CRT overlay panel
├─ 6 pages: Overview, Atmosphere, Ocean, Geophysics, Composition, Events
├─ Real-time sensor readings with trend indicators
├─ Mini sparkline graphs from reading history
├─ Anomaly blink indicators
└─ Keyboard: ←/→ pages, TAB next, Q/ESC close
```

### Sensors (21 parameters)

| Category | Sensors |
|---|---|
| Atmosphere | air_temp, humidity, pressure, wind_speed, wind_dir, precipitation, visibility, cloud_cover, light_level, uv_index |
| Ocean | sea_temp, tide_level, wave_height, salinity |
| Geophysics | mag_field, mag_declination, radiation, seismic, soil_temp |
| Composition | o2_concentration, co2_concentration |

### Data Generation
- Master seed per playthrough + day number → deterministic daily data
- Monthly baselines interpolated with seasonal transitions
- Diurnal curves (temperature peaks at 14h, humidity inverse)
- Weather modifiers (8 patterns with seasonal restrictions)
- Event modifiers (stackable, with duration)
- Calibration drift simulation + sensor failure rates
- Semi-diurnal tidal model (12.42h period)
- Solar angle-based light/UV calculation

### Story Pack Integration
Manifest key: `"env_config"` — supports overriding: `location`, `sensors`, `baselines`, `weather_patterns`, `anomaly_types`, `events`, `tasks`, `master_seed`.

### ModAPI Extensions
```gdscript
api.env_get_reading(sensor_id)       # Float reading
api.env_get_all_readings()           # Dict of all readings
api.env_get_weather()                # Weather name
api.env_get_day()                    # Current day number
api.env_get_hour()                   # Current game hour
api.env_get_sensor_status(sensor_id) # "online"/"degraded"/"offline"
api.env_get_active_events()          # Active events dict
api.env_inject_event(id, config)     # Add event definition
api.env_force_event(id)              # Force-start event
api.env_add_task(id, data)           # Add special task
api.env_get_progress()               # Task progress dict
api.env_can_advance()                # Can advance day?
api.env_get_anomalies()              # Pending anomalies
```

## File Index (by size)

```
scripts/command_handler.gd|2346  scripts/main.gd|2209  radio/radio_receiver.gd|1804
scripts/decode_viewer.gd|1456  scripts/crtml_parser.gd|1263  comm_system/comm_manager.gd|1259
comm_system/comm_ui.gd|1289  modder/mod_api.gd|1075  env_system/env_monitor.gd|919
settings/settings_manager.gd|903  scripts/mail_system.gd|891  scripts/user_manager.gd|856
comm_system/dial_manager.gd|831  scripts/oscilloscope.gd|820  scripts/package_manager.gd|817
scripts/boot_sequence.gd|813  templates/chat_viewer.gd|823  templates/email_viewer.gd|788
scripts/video_player.gd|748  scripts/trigger_system.gd|726  scripts/story_loader.gd|708
env_system/env_task_manager.gd|697  scripts/disc_manager.gd|698  camera_system/camera_viewer.gd|656
scripts/document_viewer.gd|668  scripts/image_viewer.gd|634  scripts/audio_manager.gd|586
scripts/cipher_decoder.gd|584  templates/two_page_reader.gd|571  env_system/env_viewer.gd|557
scripts/loading_screen.gd|543  scripts/typewriter.gd|520  scripts/theme_manager.gd|518
scripts/explore_viewer.gd|477  scripts/file_system.gd|472  scripts/ui_manager.gd|466
templates/article_viewer.gd|466  scripts/effect_system.gd|451  camera_system/camera_manager.gd|435
comm_system/character_asset_library.gd|420  comm_system/comm_character.gd|426
scripts/crt_shader.gd|416  scripts/daily_dialogue_manager.gd|414
comm_system/character_animator.gd|387  comm_system/comm_dialogue_player.gd|377
comm_system/dial_tone_generator.gd|376  radio/radio_signal_manager.gd|344
scripts/morse_engine.gd|347  radio/radio_config_parser.gd|319  camera_system/camera_feed.gd|320
radio/radio_audio_generator.gd|311  scripts/sstv_decoder.gd|310  radio/radio_data_manager.gd|302
comm_system/character_registry.gd|297  comm_system/presentation_overlay.gd|295
comm_system/call_handler.gd|285  scripts/header_parser.gd|247  scripts/profile_builder.gd|242
scripts/save_manager.gd|228  scripts/ui_sound.gd|200  comm_system/comm_voice.gd|188
comm_system/comm_sprite_renderer.gd|181  scripts/effect_settings.gd|175
modder/mod_base.gd|92
```

## Module Status

| Module | Status | Notes |
|---|---|---|
| Core Terminal | ✅ Complete | CLI, themes, CRT effects |
| File System | ✅ Complete | Virtual FS, permissions, clearance |
| Story Loading | ✅ Complete | ZIP parsing, GBK support |
| User System | ✅ Complete | Multi-user, profiles, stats |
| Save System | ✅ Complete | Per-user per-story |
| Comm System | ✅ Complete | Dialogues, characters, call modes (silent/forced/answerable), card/meeting/presentation display, layered sprites, history, video calls |
| Mail System | ✅ Complete | Inbox, delayed delivery |
| Radio System | ✅ Complete | Tuning, morse, SSTV, audio stations, hidden signals, waterfall, progressive perception |
| Mod System | ✅ Complete | Install, lifecycle, API |
| Settings | ✅ Complete | Registry, TUI, import/export |
| Triggers | ✅ Complete | Event-driven actions |
| Effects | ✅ Complete | Timeline sequences, presets |
| Viewers | ✅ Complete | Image, audio, video, decode, explore |
| CRTML | ✅ Complete | Full markup parser |
| Dial System | ✅ Complete | DTMF dialing, voice call routing, modem handshake + HTTP download, phonebook, preset + story directory loading |
| Env Monitor | ✅ Complete | Environmental simulation, daily seed, Sakhalin baselines, weather, anomalies, daily tasks, viewer overlay |
| Camera System | ✅ Complete | CCTV surveillance: base/depth/light/anomaly images, shader pipeline, 3 light modes, anomaly system, trigger integration |
