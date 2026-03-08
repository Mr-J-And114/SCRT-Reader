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
