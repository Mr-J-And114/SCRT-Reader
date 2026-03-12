# comm_system/ — Dialogue, Dial & Character System

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
| comm_manager.gd | Dialogue orchestration, tutorial flow, delegates to registry |
| comm_dialogue_player.gd | Dialogue playback (line-by-line, choices, conditions, character tags) |
| comm_character.gd | Lightweight character data model (delegates to animator) |
| character_registry.gd | **NEW** Character lifecycle, registration (builtin/disc/mod) |
| character_asset_library.gd | **NEW** Asset profiles, modular texture loading |
| character_animator.gd | **NEW** Animation engine (mouth, blink, action, layer overrides, costumes) |
| comm_sprite_renderer.gd | Character sprite rendering (card mode) |
| comm_ui.gd | Comm overlay UI (text, portrait, choices, meeting mode) |
| comm_voice.gd | Procedural voice synthesis (sine/square/saw tones) |
| dial_manager.gd | DTMF dial state machine, call routing, modem download |
| dial_tone_generator.gd | Procedural DTMF/ringback/busy/modem/hangup audio |
