# Extension Guide

<!-- Extracted from SCRT/AI_HANDOFF.md §6, §8, §9 -->

## Adding a New Feature (7-Step Process)

1. **Create class** in `res://scripts/` extending RefCounted (or Node if needs `_process`)
2. **Instantiate** in `main.gd` `_ready()`, inject dependencies via constructor
3. **Register commands** (if needed): add `_cmd_<name>` methods in `CommandHandler._register_commands()`
4. **Create overlay** (if needed): follow pattern of ImageViewer/Oscilloscope — overlay Panel on OutputArea, hide input/prompt, restore on close, use `_draw()` for custom rendering
5. **Parse manifest data** (if needed): add parsing in `disc_manager.load_story()` or `trigger_system.load_from_manifest()`
6. **Add save data** (if needed): integrate with `save_manager.auto_save()` / `load_save()`
7. **Register settings** (if needed): use `settings_manager.register_category()` / `register_setting()`

## App Lifecycle

1. `_ready()` → instantiate all managers → setup UI styles
2. Load boot_config.json → play boot sequence (BootSequence)
3. Login flow (login/register prompt)
4. Enter desktop mode → load settings, mail, check for stories
5. User types commands → CommandHandler dispatches
6. `load` command → DiscManager.load_story() → StoryLoader parses ZIP → populate FS
7. `cd`/`open` → navigate virtual FS, display files via CrtmlParser
8. `eject` → auto-save, clear FS
   - `dial <number>` → DialManager.dial() → DTMF → voice call or modem download
   - `comm` → show status / `comm phonebook` / `comm answer`
9. `exit`/`shutdown` → shutdown sequence → quit

## Mode Flags (main.gd)

* `_desktop_mode`: true=normal CLI, false=story loaded
* `_password_mode` / `_file_password_mode`: password input capture
* `_login_mode` / `_register_mode` / `_passwd_mode`: auth flows
* `_oscilloscope_mode` / `_image_viewer_mode` / `_video_player_mode` / `_radio_mode` / `_decode_mode`: overlay active flags
* `_command_running`: async command lock
* `dial_mgr.state`: DialState enum (IDLE → DTMF_PLAYING → RINGING → VOICE_ACTIVE/MODEM_* → CALL_ENDED → IDLE)
* `dial_mgr.call_type`: NONE / VOICE / MODEM / INVALID

## Commands

**Desktop:** help, clear, status, whoami, settings, theme, volume, reboot, exit, logout, passwd, birthday, users, deluser, profile, comm, mail, scan, load, vdisc, explore, dial, phonebook, env, camera

**Disc (story loaded):** ls, cd, back, open, unlock, eject, save, clearsave, radio, fx, sound, decode, install, uninstall, packages

**Env subcommands:** env status, env view, env tasks, env check, env read, env calibrate, env anomaly, env report, env repair, env advance, env sensor, env weather, env events

**Camera subcommands:** camera list, camera view [id/num], camera status (aliases: cam, cctv)

## Modding Interface

* Mods are `.scp` ZIP files with `package.json` manifest (`type="package"`)
* Mod scripts extend `ModBase`, get `ModAPI` instance
* ModAPI provides: output, FS, commands, audio, effects, UI nodes, comm system, mail, settings, timers, tweens, inter-mod messaging
* Lifecycle: install → enable → `_register_commands` → `_process` (per frame) → hooks → disable → uninstall
* Hook events: `before/after_command`, `directory_changed`, `file_open`, `disc_loaded/ejected`, `mode_changed`, `user_login/logout`, `mod_message`
