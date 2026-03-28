# comm_system/ — Dialogue, Dial & Character System

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 数据格式：[/docs/data-formats.md](/docs/data-formats.md)
> 修改通讯/角色/拨号逻辑后请同步更新本文件。

Communication subsystem handling character dialogues, voice calls, modem downloads,
and modular character management with layered sprite system.

## Critical Gotchas

### silent stop (最常见的坑)
`CommDialoguePlayer.stop_dialogue(silent=true)` for dialogue transitions between segments.
`silent=false` (default) for natural completion — triggers UI hide and hangup.
**Wrong usage causes premature UI close during multi-segment dialogues.**

### Voice call timing
`CommManager._on_dialogue_finished()` delays **1.0 seconds** before calling
`dial_mgr.on_voice_call_ended()`. This lets the UI close animation complete.
Do not reduce this delay or the hangup tone overlaps with dialogue.

## Character System Architecture

```
CharacterRegistry          — Central registry: create, lookup, lifecycle
  ├─ CharacterAssetLibrary — Asset profiles, texture loading (res:// + virtual FS)
  │    ├─ AssetProfile     — Per-character asset config (layers, eyes, mouth, costumes, actions)
  │    └─ CharacterTextures— Loaded texture cache per character
  ├─ CommCharacter         — Lightweight data model (identity + voice + state)
  │    └─ CharacterAnimator— Animation engine (mouth, blink, action, layer overrides)
  └─ Sources: BUILTIN / DISC / MOD
```

### Adding a New Character
1. Create an `AssetProfile` (see `CharacterAssetLibrary.create_ava_profile()` for reference)
2. Register profile: `asset_library.register_profile("char_id", profile)`
3. Register character config: `registry.register_character("char_id", config)`
4. Character auto-loads assets via `init_from_asset_library()`

### Dialogue JSON Character Tags
```json
{
  "character": "ava",
  "text": "Hello!",
  "expression": "neutral",
  "action": "nod",
  "costume": "lab_coat",
  "layer_override": { "eye_L": "eye_L_close", "eye_R": "eye_R_open" },
  "layer_override_duration": 5.0,
  "clear_overrides": true,
  "anim_effect": "wink_left:2.0"
}
```

Available `anim_effect` values: `wink_left`, `wink_right`, `eyes_closed`, `surprised`
(all accept optional `:duration` suffix, default 2.0s)

## Call Modes (CallHandler)

CallHandler manages three incoming call modes, extracted from CommManager:

| Mode | Behavior |
|---|---|
| SILENT | Direct dialogue start, no ring. Default for `comm:dialogue_id` triggers |
| FORCED | Ring sound → auto-answer after N rings. Player cannot refuse |
| ANSWERABLE | Ring sound → prompt. Player types `comm answer` / `comm reject` |

State machine: `IDLE → RINGING → WAITING_ANSWER → IDLE`

### JSON format (dialogue-level)
```json
{
  "dialogue_id": {
    "trigger": "incoming_call",
    "call_mode": "forced",
    "reject_consequence": "some_action",
    "lines": [...]
  }
}
```

### Trigger action format
`comm:dialogue_id:forced` or `comm:dialogue_id:answerable`

## Presentation Mode

Presentation mode shows a PPT/slide image alongside a character in meeting mode.

### Dialogue line fields
```json
{
  "character": "ava",
  "text": "Let me show you the data...",
  "display_mode": "presentation",
  "meeting_slot": "left",
  "slide_image": "images/slide1.png",
  "slide_position": [0.55, 0.1],
  "slide_size": [0.4, 0.5],
  "slide_area": [0.5, 0.05, 0.45, 0.6],
  "slide_fit": "contain",
  "slide_align": "center",
  "slide_transition": "fade"
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| slide_image | String | — | Image path (res:// or story pack path) |
| slide_position | [x, y] | [0.55, 0.1] | Normalized position (0.0~1.0) |
| slide_size | [w, h] | [0.4, 0.5] | Normalized size (0.0~1.0) |
| slide_area | [x, y, w, h] | — | Display area (overrides position+size) |
| slide_fit | String | "contain" | Image fitting: contain/cover/stretch/actual |
| slide_align | String | "center" | Alignment within area: center/top_left/top_center/top_right/center_left/center_right/bottom_left/bottom_center/bottom_right |
| slide_transition | String | "fade" | Transition: fade/instant/slide_left/slide_right |

To hide a slide: `"slide_hide": true` or `"slide_hide": "slide_left"`

Transitions: `fade`, `instant`, `slide_left`, `slide_right`

## Display Modes (CommUI)

| Mode | Description |
|---|---|
| `"card"` | Small portrait cards beside dialogue bar (default) |
| `"meeting"` | Galgame-style large character sprites, per-slot z-ordering |
| `"presentation"` | Meeting mode + slide overlay with configurable fit/align/area |

Set via `"display_mode"` field in dialogue line JSON. Card/meeting chars share the same
`ensure_meeting_char()` infrastructure. Presentation mode adds `PresentationOverlay` for slides.

## Comm Commands

| Command | Description |
|---|---|
| `comm` | Show comm status |
| `comm answer` | Answer incoming call |
| `comm reject` | Reject incoming call |
| `comm video` | List video channels |
| `comm video <num>` | Call video channel by number |
| `comm phonebook` | Show phonebook |
| `comm history` / `comm log` | View communication history |

## Dial State Machine

```
IDLE → DTMF_PLAYING → RINGING → VOICE_ACTIVE / MODEM_* → CALL_ENDED → IDLE
```

- `dial_mgr.state`: DialState enum tracks current state
- `dial_mgr.call_type`: NONE / VOICE / MODEM / INVALID
- Dial system runs in background via `dial_mgr.process(delta)` in `main._process()`
- Does NOT block terminal input

## Call Types

| Type | Flow | Outcome |
|---|---|---|
| VOICE | DTMF → 1s → ringback → connect → CommManager dialogue | Hangup tone |
| MODEM | DTMF → 1s → ringback → AT → carrier → handshake → download | File saved to vdisc/ |
| INVALID | DTMF → 1s → busy tone | "NUMBER NOT IN SERVICE" |

## Phone Number Sources (priority order)

1. **Story:** `manifest.json` → `dial_directory` section (injected by DiscManager on load)
2. **System:** registered via `register_system_voice()` / `register_system_modem()`
3. **Preset:** `res://data/dial_directory.json` (built-in, loaded at startup)

## Files

| File | Purpose |
|---|---|
| comm_manager.gd | Dialogue orchestration, tutorial flow, call routing, delegates to registry |
| comm_dialogue_player.gd | Dialogue playback (line-by-line, choices, conditions, character tags, slides) |
| comm_character.gd | Lightweight character data model (delegates to animator) |
| call_handler.gd | Call mode handler: SILENT/FORCED/ANSWERABLE ring + answer flow |
| presentation_overlay.gd | Presentation mode slide overlay (fit/align/area config + transitions) |
| character_registry.gd | Character lifecycle, registration (builtin/disc/mod) |
| character_asset_library.gd | Asset profiles, modular texture loading |
| character_animator.gd | Animation engine (mouth, blink, action, layer overrides, costumes) |
| comm_sprite_renderer.gd | Character sprite rendering (card mode) |
| comm_ui.gd | Comm overlay UI (text, portrait, choices, meeting/presentation mode) |
| comm_voice.gd | Procedural voice synthesis (sine/square/saw tones) |
| dial_manager.gd | DTMF dial state machine, call routing, modem download |
| dial_tone_generator.gd | Procedural DTMF/ringback/busy/modem/hangup/ring audio |
