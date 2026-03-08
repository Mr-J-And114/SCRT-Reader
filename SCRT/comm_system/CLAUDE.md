# comm_system/ — Dialogue & Dial System

Communication subsystem handling character dialogues, voice calls, and modem downloads.

## Critical Gotchas

### silent stop (最常见的坑)
`CommDialoguePlayer.stop_dialogue(silent=true)` for dialogue transitions between segments.
`silent=false` (default) for natural completion — triggers UI hide and hangup.
**Wrong usage causes premature UI close during multi-segment dialogues.**

### Voice call timing
`CommManager._on_dialogue_finished()` delays **1.0 seconds** before calling
`dial_mgr.on_voice_call_ended()`. This lets the UI close animation complete.
Do not reduce this delay or the hangup tone overlaps with dialogue.

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
| comm_manager.gd | Dialogue orchestration, character management, tutorial flow |
| comm_dialogue_player.gd | Dialogue playback engine (line-by-line, choices, conditions) |
| comm_character.gd | Character data (portrait, expressions, voice config) |
| comm_sprite_renderer.gd | Character sprite rendering |
| comm_ui.gd | Comm overlay UI (text, portrait, choices) |
| comm_voice.gd | Procedural voice synthesis (sine/square/saw tones) |
| dial_manager.gd | DTMF dial state machine, call routing, modem download |
| dial_tone_generator.gd | Procedural DTMF/ringback/busy/modem/hangup audio |
