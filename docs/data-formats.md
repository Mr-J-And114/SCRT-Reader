# Data & Content Formats

<!-- Extracted from SCRT/AI_HANDOFF.md §5 -->

## Story Disc (.scp)

ZIP archive containing:
- `manifest.json` or `manifest.cfg` — story metadata, filesystem definition, permissions, triggers, effects, radio signals, mail, dialogues
- Text files (CRTML format), images (PNG/JPG), audio (MP3/OGG/WAV), video (OGV/MP4)

Encoding detection: UTF-8 preferred, GBK fallback (handled by StoryLoader).

Located in `res://vdisc/` (editor) or exe root `./vdisc/` (exported build).
Downloaded .scp files also saved to the same `vdisc/` directory via modem dial.

## Radio Signal Config (manifest `radio_signals`)

Supports array format with per-signal properties:
- `type`: `"morse"` | `"sstv"` | `"audio"` — signal content type
- `hidden`: bool — hidden signals don't appear on radar dots, frequency ruler markers, waterfall markers
- `proximity_range`: float (MHz) — progressive perception range (0 = use `tolerance_freq`)
- `content_audio`: PackedByteArray — loaded audio data for `"audio"` type signals
- Audio stations play automatically when tuned near, volume scales with signal quality
- All signal types support progressive perception (sound heard before full lock)

## CRTML Markup (CrtmlParser)

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

## Loading Screen Config (`loading_screen.json` in vdisc root)

Optional standalone JSON file placed at the root of a `.scp` story pack. If present,
completely replaces the built-in default loading animation when the disc is loaded.
Extracted by `disc_manager._extract_loading_screen()` before populating the virtual FS
(hidden from players). Uses the same keyframe timeline engine as `boot_sequence.gd`.

During playback, `main._process()` enters exclusive mode — only the loading screen
processes; all other systems (typewriter, triggers, mail, effects) are suspended.

### Top-level Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `skippable` | bool | `true` | Allow player to skip by pressing any key |
| `total_duration` | float | `8.0` | Total animation length in seconds |
| `audio` | string | `""` | Virtual FS path to background music |
| `audio_volume` | float | `0.6` | Music volume (linear 0.0~1.0) |
| `keyframes` | array | `[]` | Array of `{time, action, params}` objects |

### Keyframe Actions

**Text output:**
| Action | Params | Description |
|---|---|---|
| `text` | `content`, `color` | Terminal text line |
| `text_center` | `content`, `color` | Centered text line |
| `disc_title` | `color` (optional) | Display disc title box (uses `fs.build_box`) |
| `disc_info` | `color` (optional) | Display Author/Version/ID |
| `separator` | `char` (default `═`), `width` (default 50), `color` | Separator line |
| `ascii_art` | `content`, `color` | ASCII art block |

**Visual effects:**
| Action | Params | Description |
|---|---|---|
| `glitch` | `intensity`, `duration` | CRT glitch effect |
| `scanlines` | `intensity` | Scanline intensity |
| `screen_flash` | `duration` | Screen flash |

**Audio:**
| Action | Params | Description |
|---|---|---|
| `beep` | — | Terminal beep sound |
| `sound` | `path` | Play sound from virtual FS |
| `audio_play` | `path` (optional, falls back to top-level `audio`) | Start background music |

**Flow control:**
| Action | Params | Description |
|---|---|---|
| `clear` | — | Clear screen |
| `wait` | — | No-op placeholder |
| `progress_bar` | `duration`, `label` | Animated progress bar (in-place update) |
| `complete` | — | End loading screen |

### Variable Substitution in `text`/`text_center` content

| Variable | Replaced with |
|---|---|
| `{disc_title}` | Story title from manifest |
| `{disc_author}` | Author name |
| `{disc_version}` | Version string |
| `{disc_id}` | Story ID |
| `{username}` | Current logged-in username |

### Color Names

`primary`, `success`, `warning`, `error`, `muted` — resolved via ThemeManager.

### Example

```json
{
  "skippable": true,
  "total_duration": 8.0,
  "keyframes": [
    { "time": 0.0, "action": "clear" },
    { "time": 0.0, "action": "text", "params": {
        "content": "INSERTING VIRTUAL DISC...", "color": "muted" } },
    { "time": 0.5, "action": "glitch", "params": {
        "intensity": 0.2, "duration": 0.3 } },
    { "time": 1.0, "action": "disc_title" },
    { "time": 1.5, "action": "disc_info" },
    { "time": 2.0, "action": "separator" },
    { "time": 2.5, "action": "progress_bar", "params": {
        "duration": 4.0 } },
    { "time": 7.0, "action": "text", "params": {
        "content": "READY.", "color": "success" } },
    { "time": 8.0, "action": "complete" }
  ]
}
```

## Boot/Shutdown Config (`res://boot_config.json`)

JSON keyframe timeline: `{time, action, params}`.

Actions: `screen_off`, `screen_on`, `audio_play`, `text`, `beep`, `glitch`, `scanlines`, `progress_bar`, `clear`, `fade_in`, `background`, `logo`, `screen_collapse`, `shutdown_sound`, `quit`.

## Save System

| Path | Purpose |
|---|---|
| `res://saves/{username}/save_{story_id}.json` | Per-story save data |
| `res://saves/{username}/profile.json` | User profile |
| `res://saves/{username}/settings.json` | Per-user settings |
| `res://saves/_settings_global.json` | Global settings |
| `res://saves/{username}/mail/` | Mail storage |

Extra data keys in save files:
- `extra["env_data"]` / `extra["env_task_data"]` — Environment monitoring state
- `extra["camera_data"]` — Camera system state (per-camera: unlocked, online, signal_quality)

## Dial Directory Config

Phone numbers are loaded from multiple sources (priority: story > system > preset):
- **Preset:** `res://data/dial_directory.json` — built-in download numbers, loaded at startup
- **Story:** `manifest.json` → `dial_directory` section, injected by DiscManager on load
- **System:** registered programmatically via `register_system_voice()` / `register_system_modem()`

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
```

### Call Types

| Type | Flow | Outcome |
|---|---|---|
| VOICE | DTMF → 1s pause → ringback → connect → CommManager dialogue | Hangup tone after dialogue ends |
| MODEM | DTMF → 1s pause → ringback → AT commands → carrier detect → handshake audio → download with progress | File saved to vdisc/ |
| INVALID | DTMF → 1s pause → busy tone | "NUMBER NOT IN SERVICE" |

## Comm Dialogue Format (`dialogues` in manifest or standalone JSON)

Each dialogue object in the `dialogues` array/dictionary supports:

### Basic Fields

| Field | Type | Required | Description |
|---|---|---|---|
| `id` | string | Yes | Unique dialogue identifier |
| `character` | string | Yes | Character ID (must match a defined character) |
| `trigger` | string | No | Auto-trigger condition (e.g. `"incoming_call"`, `"story_start"`) |
| `lines` | array | Yes | Array of dialogue line objects |

### Call Mode Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `call_mode` | string | `"silent"` | `"silent"` — direct start, no ring; `"forced"` — rings then auto-answers after timeout; `"answerable"` — rings, player must `comm answer` or `comm reject` |
| `reject_consequence` | string | `""` | Text shown if player rejects an answerable call |
| `caller_name` | string | character label | Display name shown during ringing |

Trigger format in manifest: `comm:dialogue_id:forced` or `comm:dialogue_id:answerable`.

### Video / Meeting Mode Fields

| Field | Type | Default | Description |
|---|---|---|---|
| `video_call` | bool | `false` | Mark as video call (appears in `comm video` channel list) |
| `video_number` | string | `""` | Dial number for this video channel (e.g. `"1002-0001"`) |
| `display_mode` | string | `"normal"` | `"normal"` (text only), `"video"` (single char), `"meeting"` (multi-char), `"presentation"` (meeting + slides) |

### Meeting Mode Character Setup (per-line)

| Field | Type | Description |
|---|---|---|
| `meeting_slot` | string | `"left"` or `"right"` — character position in meeting layout |
| `char_anim` | string | Character animation: `"talk"`, `"idle"`, `"think"`, etc. |

Multiple characters share the screen with overlap offset (40px). Active speaker brought to front with full brightness; inactive dimmed to 70%.

### Presentation Mode (per-line)

| Field | Type | Default | Description |
|---|---|---|---|
| `slide_image` | string | — | Path to slide image (relative to story pack or `res://`) |
| `slide_position` | array | `[0.55, 0.1]` | `[x, y]` normalized position (0.0~1.0) |
| `slide_size` | array | `[0.4, 0.5]` | `[w, h]` normalized size (0.0~1.0) |
| `slide_area` | array | — | `[x, y, w, h]` display area (overrides position+size) |
| `slide_fit` | string | `"contain"` | Image fitting: `"contain"` / `"cover"` / `"stretch"` / `"actual"` |
| `slide_align` | string | `"center"` | Image alignment within area: `"center"` / `"top_left"` / `"top_center"` / `"top_right"` / `"center_left"` / `"center_right"` / `"bottom_left"` / `"bottom_center"` / `"bottom_right"` |
| `slide_transition` | string | `"fade"` | Transition: `"fade"` / `"instant"` / `"slide_left"` / `"slide_right"` |
| `slide_hide` | bool/string | — | Hide current slide with transition (e.g. `true` or `"slide_left"`) |

### Clear-Before-Dialogue Setting

Registered in settings as `comm.clear_before_dialogue` (bool, default `false`). When enabled, terminal output is cleared before each new dialogue starts.

### Example: Answerable Call with Video Meeting

```json
{
  "id": "team_briefing",
  "character": "ava",
  "call_mode": "answerable",
  "reject_consequence": "未接来电已记录。",
  "video_call": true,
  "video_number": "1000-9999",
  "display_mode": "meeting",
  "lines": [
    {
      "character": "ava",
      "meeting_slot": "left",
      "text": "各位，会议开始。"
    },
    {
      "character": "researcher",
      "meeting_slot": "right",
      "char_anim": "talk",
      "text": "收到，请继续。"
    },
    {
      "character": "ava",
      "meeting_slot": "left",
      "slide_image": "slides/plan.png",
      "slide_area": [0.5, 0.05, 0.45, 0.6],
      "slide_fit": "contain",
      "slide_align": "center",
      "slide_transition": "fade",
      "text": "请看这份计划。"
    }
  ]
}
```
