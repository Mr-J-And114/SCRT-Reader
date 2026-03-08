> **DEPRECATED**: This document has been split into structured Claude Code project files.
> See `CLAUDE.md` (root), `docs/architecture.md`, `docs/data-formats.md`, `docs/extension-guide.md`,
> and local `CLAUDE.md` files in `SCRT/scripts/`, `SCRT/comm_system/`, `SCRT/camera_system/`, `SCRT/radio/`.

# SCRT-Reader AI Handoff Document
<!-- VERSION:1.3 | ENGINE:Godot4.6 | RENDERER:GL_Compatibility | LAST_UPDATE:2026-03-04 -->
<!-- FORMAT: Compressed for AI consumption. Minimize whitespace. Section headers are anchors. -->

## §1 PROJECT OVERVIEW
**Name:** SCRT-Reader (SCP CRT Terminal Reader)
**Type:** SCP-themed retro CRT terminal simulator / interactive fiction reader
**Single Scene:** `res://scenes/main.tscn` (root: Control, script: `res://scripts/main.gd`)
**Window:** 1152×648, stretch_mode=canvas_items
**No autoloads.** All systems instantiated in main.gd `_ready()`.
**Physics:** Jolt3D (unused; project is pure 2D UI).
**Content:** Stories are loaded from `.scp` files (ZIP archives).
- Located in `res://vdisc/` (editor) or exe root `./vdisc/` (exported build)
- Downloaded .scp files also saved to the same `vdisc/` directory via modem dial

## §2 ARCHITECTURE
All logic lives in `res://scripts/` + `res://comm_system/` + `res://settings/` + `res://modder/` + `res://templates/` + `res://camera_system/`.
**Pattern:** Main.gd (Control node) owns RefCounted manager instances. No singletons. Managers reference each other via constructor injection in `_ready()`.

### Core Dependency Graph
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
├─ comm_mgr: CommManager — dialogue/comm system (characters, choices)
│  ├─ dial_mgr: DialManager — DTMF dialing, voice call routing, modem download state machine
│  ├─ tone_gen: DialToneGenerator — procedural DTMF/ringback/busy/modem/hangup audio synthesis (owned by dial_mgr)
├─ trigger_sys: TriggerSystem — event-driven triggers (enter dir, open file, etc.)
├─ mail_sys: MailSystem — in-game mail inbox with delayed delivery
├─ effect_sys: EffectSystem — timeline-based multi-step effect sequences
├─ effect_settings: EffectSettings — photosensitive/intensity levels
├─ boot_sequence: BootSequence — keyframe-driven boot/shutdown animations
├─ loading_screen: LoadingScreen — disc loading animation
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

## §3 SCENE TREE (main.tscn)
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

````

## §4 SCRIPT REFERENCE (key classes, lines, purpose)

### §4.1 Core Scripts (`res://scripts/`)
| File | Class | Lines | Purpose |
|---|---|---|---|
| main.gd | — | 1939 | God object: init, input routing, mode management, UI updates, media, effects |
| file_system.gd | FileSystem | 473 | Virtual FS tree (FSNode), permissions, clearance, ambient sounds, path utils |
| command_handler.gd | CommandHandler | 1638 | CLI command registry (desktop/disc/global), history, tab-complete, all `_cmd_*` handlers |
| story_loader.gd | StoryLoader | 709 | Parse .scp ZIP files, detect encoding (UTF-8/GBK), build manifest+filesystem |
| disc_manager.gd | DiscManager | 597 | Scan vdisc/, load/eject stories, mod support, auto-save |
| crtml_parser.gd | CrtmlParser | 1266 | Markdown→BBCode: headings, bold, italic, spoilers, tables, media tags, effect tags, page breaks |
| typewriter.gd | Typewriter | 521 | Queued text output with char-by-char typing, inline FX triggers, progress bars |
| save_manager.gd | SaveManager | 229 | Per-user per-story JSON save/load, auto-save |
| user_manager.gd | UserManager | 725 | Multi-user accounts, login/register/passwd, profiles, stats, story progress |
| audio_manager.gd | AudioManager | 587 | Ambient(crossfade)/SFX/Media players, ducking, spectrum analyzer, load from bytes (MP3/OGG/WAV) |
| crt_shader.gd | — | 417 | CRT post-process: glitch, shake, tear, boot/shutdown, noise burst, blackout |
| theme_manager.gd | ThemeManager | 495 | 4 themes, color palette (ThemeColors), CRT/background/logo shader refresh |
| boot_sequence.gd | BootSequence | 807 | JSON-driven keyframe boot/shutdown: screen_off/on, text, glitch, progress, audio |
| loading_screen.gd | LoadingScreen | 519 | Disc loading keyframe animation |
| trigger_system.gd | TriggerSystem | 614 | Event triggers: enter_dir, open_file, command, idle, level_change → actions (mail, glitch, lock, etc.) |
| mail_system.gd | MailSystem | 831 | Mail inbox, delayed delivery, global+per-story mail, blink notification |
| effect_system.gd | EffectSystem | 452 | Timeline effect sequences (glitch, shake, sound, text, reboot, brightness, etc.) |
| effect_settings.gd | EffectSettings | 154 | Effect intensity levels (full/mild/off), photosensitive mode |
| settings/settings_manager.gd | SettingsManager | 904 | Registry-based settings system with categories, TUI interface, import/export |
| settings/settings_registry.gd | — | — | Setting definitions registration |
| settings/settings_storage.gd | — | — | JSON storage backend for settings |
| header_parser.gd | HeaderParser | 248 | Parse file headers (metadata block between markers) |
| cipher_decoder.gd | CipherDecoder | 585 | Caesar, Vigenere, substitution, base64, morse, ROT13, atbash, reverse |
| morse_engine.gd | MorseEngine | 348 | Morse encode/decode, playback events, numbers station mode |
| radio_audio_generator.gd | RadioAudioGenerator | 312 | Procedural noise/tone/SSTV audio generation |
| radio_config_parser.gd | RadioConfigParser | 303 | Parse radio signal definitions from config/manifest; RadioSignal class with hidden, content_audio, proximity_range |
| radio_signal_manager.gd | RadioSignalManager | 297 | Signal database, quality calc (progressive proximity), discovery, bookmarks, scan |
| sstv_decoder.gd | SSTVDecoder | 311 | SSTV image receive simulation with scanline noise |
| package_manager.gd | PackageManager | 818 | Mod system: install/uninstall .scp mods, hook dispatch, mod lifecycle |
| ui_manager.gd | UIManager | 467 | Procedural UI style: cursors, scrollbar, panel themes, font setup |
| ui_sound.gd | UiSound | 201 | Procedural SFX: keystroke, enter, backspace, HDD read, click |
| profile_builder.gd | ProfileBuilder | 219 | Build 3-page profile card for doc_viewer |
| video_player.gd | VideoPlayerViewer | 737 | Video overlay with controls, ffmpeg fallback support |
| env_monitor.gd | EnvMonitor | ~550 | Environmental simulation: sensors, weather, events, anomalies, daily seed |
| env_task_manager.gd | EnvTaskManager | ~450 | Daily task checklist: inspection, recording, calibration, reporting |
| camera_feed.gd | CameraFeed | ~273 | Single camera data model: base/depth/light/anomaly images, lens params |
| camera_manager.gd | CameraManager | ~290 | Camera registry, unlock/lock, anomaly triggers, save/load, image loading |

### §4.2 Viewer/Overlay Scripts
| File | Class | Lines | Purpose |
|---|---|---|---|
| document_viewer.gd | DocumentViewer | 669 | 2-page overlay (left/right RTL), pagination, typing animation |
| explore_viewer.gd | ExploreViewer | 478 | File tree panel, story progress display |
| image_viewer.gd | ImageViewer | 634 | Zoomable image viewer, pan, scan effect, _ImageCanvas inner class |
| oscilloscope.gd | Oscilloscope | 820 | Spectrum analyzer + Lissajous, _ScopeCanvas inner class |
| radio_receiver.gd | RadioReceiver | ~1700 | Full radio UI: tuning, bands, morse decode, SSTV, audio station, hidden signals, waterfall, _RadioCanvas inner class |
| decode_viewer.gd | DecodeViewer | 1457 | Cipher decode animation viewer, _DecodeCanvas inner class |
| env_viewer.gd | EnvViewer | ~350 | Environmental data panel overlay, 6 pages, _EnvCanvas inner class |
| camera_viewer.gd | CameraViewer | ~480 | CCTV fullscreen overlay, shader-rendered surveillance feed, pan/switch controls |

### §4.3 Comm System (`res://comm_system/`)
| File | Class | Purpose |
|---|---|---|
| comm_manager.gd | CommManager | Dialogue orchestration, character management, tutorial flow, disc dialogues |
| comm_dialogue_player.gd | CommDialoguePlayer | Dialogue playback engine (line-by-line, choices, conditions, silent stop for seamless transitions) |
| comm_character.gd | — | Character data (portrait, expressions, voice config) |
| comm_sprite_renderer.gd | — | Character sprite rendering |
| comm_ui.gd | — | Comm overlay UI (text display, portrait, choices) |
| comm_voice.gd | — | Procedural voice synthesis (sine/square/saw tones) |
| dial_manager.gd | DialManager | DTMF dial state machine, voice call routing, modem handshake/download, phonebook |
| dial_tone_generator.gd | DialToneGenerator | Procedural audio: DTMF keys, ringback, busy tone, modem handshake, data noise, hangup |

### §4.4 Mod System (`res://modder/`)
| File | Class | Purpose |
|---|---|---|
| mod_api.gd | ModAPI | 997-line API surface for mods: output, FS access, commands, audio, effects, UI, comm, etc. |
| mod_base.gd | ModBase | Base class for mods: lifecycle hooks (_on_install, _on_enable, _process, event callbacks) |

### §4.5 Templates (`res://templates/`)
| File | Purpose |
|---|---|
| article_viewer.gd | Article-style document template |
| chat_viewer.gd | Chat log template |
| email_viewer.gd | Email template |
| two_page_reader.gd | Two-page book template |

## §5 DATA & CONTENT FORMAT

### §5.1 Story Disc (.scp)
ZIP archive containing:
- `manifest.json` or `manifest.cfg` — story metadata, filesystem definition, permissions, triggers, effects, radio signals, mail, dialogues
- Text files (CRTML format), images (PNG/JPG), audio (MP3/OGG/WAV), video (OGV/MP4)

### §5.2 Radio Signal Config (manifest radio_signals)
Supports array format with per-signal properties:
- `type`: "morse" | "sstv" | "audio" — signal content type
- `hidden`: bool — hidden signals don't appear on radar/ruler/waterfall markers
- `proximity_range`: float (MHz) — progressive perception range (0 = use tolerance_freq)
- `content_audio`: PackedByteArray — loaded audio data for "audio" type signals
- Audio stations play automatically when tuned near, volume scales with signal quality
- All signal types support progressive perception (sound heard before full lock)

### §5.3 CRTML Markup (CrtmlParser)
Markdown-like syntax → BBCode:
- `# H1`, `## H2`, `### H3` headings
- `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``
- `||spoiler||`, `[CLASSIFIED]`/`[REDACTED]` SCP markers
- `███` black blocks
- `---` separator, `===` page break
- `> quote`
- `![alt](path)` images, `!audio[label](path)` audio, `!video[label](path)` video
- `{tw:speed=N}` typewriter speed tags
- `{fx:glitch}`, `{fx:shake}`, `{fx:sound=path}` inline effect tags
- Tables via `|col1|col2|` syntax

### §5.4 Boot/Shutdown Config (`res://boot_config.json`)
JSON keyframe timeline: `{time, action, params}`. Actions: screen_off, screen_on, audio_play, text, beep, glitch, scanlines, progress_bar, clear, fade_in, background, logo, screen_collapse, shutdown_sound, quit.

### §5.5 Save System
- Saves: `res://saves/{username}/save_{story_id}.json`
- Profile: `res://saves/{username}/profile.json`
- Settings: `res://saves/{username}/settings.json` + `res://saves/_settings_global.json`
- Mail: `res://saves/{username}/mail/`

### §5.6 Dial Directory Config
Phone numbers are loaded from multiple sources (priority: story > system > preset):
- **Preset:** `res://data/dial_directory.json` — built-in download numbers, loaded at startup
- **Story:** `manifest.json` → `dial_directory` section, injected by DiscManager on load
- **System:** registered programmatically via `register_system_voice()`/`register_system_modem()`

Format:
```json
{
  "voice": {
    "1001-0001": { "character": "ava", "label": "AVA - Liaison Officer" }
  },
  "modem": {
    "9900-0001": {
      "label": "SCP Archive Server",
      "speed_display": "9600 bps",
      "filename": "story.scp",
      "url": "https://example.com/story.scp"
    }
  }
}
````

**Call types:**

| Type    | Flow                                                                                                 | Outcome                         |
| ------- | ---------------------------------------------------------------------------------------------------- | ------------------------------- |
| VOICE   | DTMF → 1s pause → ringback → connect → CommManager dialogue                                          | Hangup tone after dialogue ends |
| MODEM   | DTMF → 1s pause → ringback → AT commands → carrier detect → handshake audio → download with progress | File saved to vdisc/            |
| INVALID | DTMF → 1s pause → busy tone                                                                          | "NUMBER NOT IN SERVICE"         |

## §6 KEY FLOW & STATE

### §6.1 App Lifecycle

1. `_ready()` → instantiate all managers → setup UI styles
2. Load boot_config.json → play boot sequence (BootSequence)
3. Login flow (login/register prompt)
4. Enter desktop mode → load settings, mail, check for stories
5. User types commands → CommandHandler dispatches
6. `load` command → DiscManager.load_story() → StoryLoader parses ZIP → populate FS
7. `cd`/`open` → navigate virtual FS, display files via CrtmlParser
8. `eject` → auto-save, clear FS
   8b. `dial <number>` → DialManager.dial() → DTMF sequence → voice call (CommManager dialogue) or modem download
   8c. `comm` → show comm status / `comm phonebook` → show phone directory / `comm answer` → accept incoming call
9. `exit`/`shutdown` → shutdown sequence → quit

### §6.2 Mode Flags (main.gd)

* `_desktop_mode`: true=normal CLI, false=story loaded
* `_password_mode`/`_file_password_mode`: password input capture
* `_login_mode`/`_register_mode`/`_passwd_mode`: auth flows
* `_oscilloscope_mode`/`_image_viewer_mode`/`_video_player_mode`/`_radio_mode`/`_decode_mode`: overlay active flags
* `_command_running`: async command lock
* `dial_mgr.state`: DialState enum (IDLE→DTMF_PLAYING→RINGING→VOICE_ACTIVE/MODEM_*→CALL_ENDED→IDLE)
* `dial_mgr.call_type`: NONE/VOICE/MODEM/INVALID

### §6.3 Commands (CommandHandler)

**Desktop:** help, clear, status, whoami, settings, theme, volume, reboot, exit, logout, passwd, birthday, users, deluser, profile, comm, mail, scan, load, vdisc, explore, dial, phonebook, env, camera
**Disc (story loaded):** ls, cd, back, open, unlock, eject, save, clearsave, radio, fx, sound, decode, install, uninstall, packages
**Global (env subcommands):** env status, env view, env tasks, env check, env read, env calibrate, env anomaly, env report, env repair, env advance, env sensor, env weather, env events
**Global (camera subcommands):** camera list, camera view [id/num], camera status (aliases: cam, cctv)

## §7 SHADERS

| File                                 | Purpose                                                                                        |
| ------------------------------------ | ---------------------------------------------------------------------------------------------- |
| shaders/crt_effect.gdshader          | CRT post-process (scanlines, curvature, chromatic aberration, noise, brightness, shake offset) |
| shaders/background_vignette.gdshader | Background vignette effect                                                                     |
| shaders/background_logo.gdshader     | SCP logo background effect                                                                     |
| camera_system/camera_effect.gdshader | CCTV surveillance shader: depth parallax, 3 light modes (spotlight/nightvision/infrared), noise, scanlines, signal interference, anomaly blend |

## §8 MODDING INTERFACE

* Mods are `.scp` ZIP files with `package.json` manifest (type="package")
* Mod scripts extend `ModBase`, get `ModAPI` instance
* ModAPI provides: output, FS, commands, audio, effects, UI nodes, comm system, mail, settings, timers, tweens, inter-mod messaging
* Lifecycle: install → enable → _register_commands → _process (per frame) → hooks → disable → uninstall
* Hook events: before/after_command, directory_changed, file_open, disc_loaded/ejected, mode_changed, user_login/logout, mod_message

## §9 EXTENSION GUIDE

To add a new feature:

1. Create class in `res://scripts/` extending RefCounted (or Node if needs _process)
2. Instantiate in main.gd `_ready()`, inject dependencies
3. If needs commands: register in CommandHandler._register_commands()
4. If needs overlay: follow pattern of ImageViewer/Oscilloscope (overlay Panel + custom Control._draw)
5. If needs manifest data: parse in disc_manager.load_story() or trigger_system.load_from_manifest()
6. If needs save data: add to save_manager.auto_save()/load_save()
7. If needs settings: register in settings_manager via register_category()/register_setting()

## §10 FILE INDEX (non-asset)

```
scripts/main.gd|1939  scripts/command_handler.gd|1638  scripts/crtml_parser.gd|1266
scripts/radio_receiver.gd|~1700  scripts/decode_viewer.gd|1457  scripts/oscilloscope.gd|820
scripts/boot_sequence.gd|807  scripts/mail_system.gd|831  scripts/package_manager.gd|818
scripts/image_viewer.gd|634  scripts/video_player.gd|737  scripts/user_manager.gd|725
scripts/story_loader.gd|709  scripts/document_viewer.gd|669  scripts/trigger_system.gd|614
scripts/disc_manager.gd|597  scripts/audio_manager.gd|587  scripts/cipher_decoder.gd|585
scripts/typewriter.gd|521  scripts/loading_screen.gd|519  scripts/theme_manager.gd|495
scripts/explore_viewer.gd|478  scripts/file_system.gd|473  scripts/ui_manager.gd|467
scripts/effect_system.gd|452  scripts/crt_shader.gd|417  scripts/radio_signal_manager.gd|297
scripts/radio_audio_generator.gd|312  scripts/radio_config_parser.gd|303  scripts/sstv_decoder.gd|311
scripts/morse_engine.gd|348  scripts/header_parser.gd|248  scripts/save_manager.gd|229
scripts/profile_builder.gd|219  scripts/ui_sound.gd|201  scripts/effect_settings.gd|154
camera_system/camera_feed.gd|273  camera_system/camera_manager.gd|290  camera_system/camera_viewer.gd|480
camera_system/camera_effect.gdshader|~200
comm_system/comm_manager.gd|~600  comm_system/comm_dialogue_player.gd|~280
comm_system/comm_character.gd|?  comm_system/comm_sprite_renderer.gd|?
comm_system/comm_ui.gd|?  comm_system/comm_voice.gd|?
scripts/dial_manager.gd|~550  scripts/dial_tone_generator.gd|?
settings/settings_manager.gd|904  settings/settings_registry.gd|?  settings/settings_storage.gd|?
modder/mod_api.gd|997  modder/mod_base.gd|93
templates/article_viewer.gd|?  templates/chat_viewer.gd|?  templates/email_viewer.gd|?  templates/two_page_reader.gd|?
```

## §11 KNOWN PATTERNS & CONVENTIONS

* All viewers use overlay pattern: Panel on OutputArea, hide input/prompt, restore on close
* Theme colors accessed via `T.c_primary()`, `T.c_error()` etc. (return hex string)
* Output via `main.append_output(bbcode)` or `tw.append(text)` for typed output
* CRT effects via `crt_shader.play_glitch()`, `crt_shader.play_shake()`, etc.
* `_process(delta)` in main.gd drives: boot_sequence, typewriter, effect_system, mail_system, comm_mgr, radio, oscilloscope, image_viewer, video_player, decode_viewer, camera_mgr, camera_viewer, scroll, status bar, inline audio/video
* Input handled in `_input(event)` with mode-priority: boot_sequence > comm > viewers (env/camera/decode/radio/...) > password > login > normal
* Dial system driven by `dial_mgr.process(delta)` in main._process; does NOT block terminal input (runs in background)
* CommDialoguePlayer.stop_dialogue(silent=true) used for dialogue transitions; silent=false (default) for natural completion — prevents premature UI hide and hangup during multi-segment dialogues
* Voice calls: CommManager._on_dialogue_finished() delays 1.0s before calling dial_mgr.on_voice_call_ended() to let UI close animation complete
* Downloaded .scp files saved to OS.get_executable_path().get_base_dir()/vdisc/ (exported) or ProjectSettings.globalize_path("res://")/vdisc/ (editor)

## §12 RADIO SYSTEM DETAILS (Phase 2)

### §12.1 Signal Types

| Type  | Description                                | Lock Required          | Progressive Audio                          |
| ----- | ------------------------------------------ | ---------------------- | ------------------------------------------ |
| morse | Morse code text (standard/numbers station) | Yes (for decode)       | Tone audible before lock, volume ∝ quality |
| sstv  | Slow-scan TV image                         | Yes (Space to receive) | SSTV tone audible before lock              |
| audio | Audio broadcast (MP3/OGG/WAV)              | No                     | Auto-play, volume ∝ quality                |

### §12.2 Progressive Perception

* All signals: entering proximity_range begins audio feedback
* Signal quality = f(freq_diff, azimuth_diff, elevation_diff) → 0.0~1.0
* Noise volume inversely proportional to max signal quality
* Morse tone volume scales with quality (audible at quality > 0.02)
* Audio stations: volume = quality × master_volume × 0.8
* Full lock (quality ≥ threshold for ≥ 3s) still required for morse decode / SSTV receive

### §12.3 Hidden Signals

* `hidden: true` in config → signal omitted from radar dots, frequency ruler markers, waterfall markers
* Still discoverable via manual tuning, audible via progressive perception
* Discovered when quality reaches lock threshold

### §12.4 Audio Manager Extensions

* `load_audio_from_bytes(file_path: String, data: PackedByteArray) -> AudioStream` — loads MP3/OGG/WAV from raw bytes
* Signature: first arg is path (for extension detection), second is byte data
* MP3: `AudioStreamMP3.new()` with `.data = bytes`
* OGG: `AudioStreamOggVorbis.load_from_buffer(bytes)`
* WAV: manual PCM parsing (RIFF chunk traversal)

## §13 MODULE STATUS TEMPLATE

<!-- AI: Update this section as development progresses -->

| Module        | Status     | Notes                                                                                                          |
| ------------- | ---------- | -------------------------------------------------------------------------------------------------------------- |
| Core Terminal | ✅ Complete | CLI, themes, CRT effects                                                                                       |
| File System   | ✅ Complete | Virtual FS, permissions, clearance                                                                             |
| Story Loading | ✅ Complete | ZIP parsing, GBK support                                                                                       |
| User System   | ✅ Complete | Multi-user, profiles, stats                                                                                    |
| Save System   | ✅ Complete | Per-user per-story                                                                                             |
| Comm System   | ✅ Complete | Dialogues, characters, tutorial, dial-initiated voice calls, silent stop for seamless transitions              |
| Mail System   | ✅ Complete | Inbox, delayed delivery                                                                                        |
| Radio System  | ✅ Complete | Tuning, morse, SSTV, audio stations, hidden signals, waterfall, progressive perception                         |
| Mod System    | ✅ Complete | Install, lifecycle, API                                                                                        |
| Settings      | ✅ Complete | Registry, TUI, import/export                                                                                   |
| Triggers      | ✅ Complete | Event-driven actions                                                                                           |
| Effects       | ✅ Complete | Timeline sequences, presets                                                                                    |
| Viewers       | ✅ Complete | Image, audio, video, decode, explore                                                                           |
| CRTML         | ✅ Complete | Full markup parser                                                                                             |
| Dial System   | ✅ Complete | DTMF dialing, voice call routing, modem handshake + HTTP download, phonebook, preset + story directory loading |
| Env Monitor   | ✅ Complete | Environmental simulation, daily seed, Sakhalin baselines, weather, anomalies, daily tasks, viewer overlay      |
| Camera System | ✅ Complete | CCTV surveillance: base/depth/light/anomaly images, shader pipeline, 3 light modes, anomaly system, trigger integration |

## §14 ENVIRONMENT MONITORING SYSTEM

### §14.1 Overview
Environmental monitoring simulation for the observation station. Generates realistic weather/ocean/geophysics data based on Sakhalin Island climate, driven by daily random seeds. Players perform routine inspection tasks to advance days.

### §14.2 Architecture
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

### §14.3 Sensors (21 parameters)
| Category     | Sensors                                                                |
|-------------|------------------------------------------------------------------------|
| Atmosphere  | air_temp, humidity, pressure, wind_speed, wind_dir, precipitation, visibility, cloud_cover, light_level, uv_index |
| Ocean       | sea_temp, tide_level, wave_height, salinity                            |
| Geophysics  | mag_field, mag_declination, radiation, seismic, soil_temp              |
| Composition | o2_concentration, co2_concentration                                    |

### §14.4 Commands
| Command | Description |
|---------|-------------|
| `env status` | Show all current readings |
| `env view` | Open monitoring panel overlay |
| `env tasks` | Show daily task checklist |
| `env check` | Equipment status inspection |
| `env read <category>` | Record sensor data (atmosphere/ocean/geophysics/composition) |
| `env calibrate` | Calibrate instruments |
| `env anomaly` | Check and confirm anomalies |
| `env report` | Submit daily report |
| `env repair <sensor>` | Repair offline sensor |
| `env advance` | Advance to next day (requires all tasks) |
| `env sensor <id>` | Detailed sensor info |
| `env weather` | Current weather details |
| `env events` | View active events/anomalies |

### §14.5 Data Generation
- Master seed per playthrough + day number → deterministic daily data
- Monthly baselines interpolated with seasonal transitions
- Diurnal curves (temperature peaks at 14h, humidity inverse)
- Weather modifiers (8 patterns with seasonal restrictions)
- Event modifiers (stackable, with duration)
- Calibration drift simulation + sensor failure rates
- Semi-diurnal tidal model (12.42h period)
- Solar angle-based light/UV calculation

### §14.6 Story Pack Integration
Manifest key: `"env_config"` — supports overriding:
- `location`: station name, coordinates
- `sensors`: add/override sensor definitions
- `baselines`: override monthly averages
- `weather_patterns`: add custom weather types
- `anomaly_types`: add SCP-specific anomaly definitions
- `events`: add special events
- `tasks`: add/override daily tasks
- `master_seed`: force specific seed

### §14.7 ModAPI Extensions
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

### §14.8 Save Data
Stored in `extra["env_data"]` and `extra["env_task_data"]` within story save files.

## §15 CAMERA SYSTEM (CCTV Surveillance)

### §15.1 Overview
CCTV monitoring system allowing players to view surveillance camera feeds. Each camera has a base image, optional depth map (pseudo-3D parallax), optional lighting map (spotlight/nightvision/infrared), and optional anomaly overlays. All rendering through a custom shader pipeline.

### §15.2 Architecture
```
camera_system/camera_feed.gd (CameraFeed) — Single camera data model
├─ Base/depth/light/anomaly image paths + cached textures
├─ Lens parameters (viewport_size, viewport_pos, pan_speed, pan_bounds)
├─ Effect parameters (noise, scanlines, vignette, signal_quality, snow)
├─ Anomaly system (array of anomalies with trigger/duration/cooldown)
└─ Runtime state (_active_anomaly, _anomaly_blend, _anomaly_cooldowns)

camera_system/camera_manager.gd (CameraManager) — Registry & lifecycle
├─ Camera registration from manifest "camera_system.cameras"
├─ Unlock/lock, online/offline, signal quality control
├─ Anomaly triggering with effect_settings safety check
├─ Random anomaly auto-trigger in process()
├─ Save/load state (unlocked, online, signal_quality per camera)
└─ Image loading via FileSystem (supports ZIP .scp content)

camera_system/camera_viewer.gd (CameraViewer) — Fullscreen overlay
├─ ColorRect with camera_effect.gdshader for rendering
├─ UI overlay (camera name, location, timestamp, signal bar, status)
├─ Keyboard: arrows=pan, 1-9=switch, TAB=next, F=light mode, Q/ESC=close
├─ Shader uniforms updated per-frame from CameraFeed state
└─ Anomaly blend driven by CameraFeed._anomaly_blend

camera_system/camera_effect.gdshader — Shader pipeline
├─ Depth-based parallax offset (base + anomaly layers)
├─ 3 lighting modes: spotlight (circle mask), nightvision (green tint), infrared (pseudocolor heatmap)
├─ Noise/scanlines/vignette/signal interference/snow
├─ Color compression (desaturation + green shift for CRT feel)
└─ Anomaly smooth blend transition
```

### §15.3 Manifest Config
Key: `"camera_system"` in manifest.json. Contains `"cameras"` dict keyed by camera ID.
Each camera: `name`, `location`, `unlocked`, `online`, `base_image` (required), `depth_map`, `light_mode` ("none"|"spotlight"|"nightvision"|"infrared"), `light_image`, `light_radius`, `light_falloff`, `viewport_size` [w,h], `viewport_pos` [x,y], `pan_speed`, `pan_bounds` [x1,y1,x2,y2], `noise_intensity`, `scanline_intensity`, `vignette`, `signal_quality`, `snow_intensity`, `timestamp_visible`, `anomalies` array.
Each anomaly: `id`, `image`, `depth_map`, `light_image`, `trigger` ("random"|"trigger"|"timed"), `probability`, `duration`, `min_interval`, `effects`, `action`.

### §15.4 Commands
| Command | Description |
|---------|-------------|
| `camera list` | List unlocked cameras |
| `camera view [num/id]` | Open camera viewer |
| `camera status` | Show all cameras status |

### §15.5 Trigger Actions
| Action | Description |
|--------|-------------|
| `camera_unlock:cam_id` | Unlock camera |
| `camera_lock:cam_id` | Lock camera |
| `camera_online:cam_id` | Set camera online |
| `camera_offline:cam_id` | Set camera offline |
| `camera_anomaly:cam_id[:anom_id]` | Trigger anomaly |
| `camera_signal:cam_id:quality` | Set signal quality (0-1) |

### §15.6 Save Data
Stored in `extra["camera_data"]` within story save files. Saves per-camera: `unlocked`, `online`, `signal_quality`.

### §15.7 Safety
Anomaly visual effects blocked when `effect_settings.is_effect_allowed("jumpscare")` returns false (OFF mode). Trigger actions (mail delivery, file unlock, etc.) always execute regardless of effect level.

<!-- END OF HANDOFF DOCUMENT -->

```
```
