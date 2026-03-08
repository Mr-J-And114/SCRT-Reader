# Skill: Create Story Pack (.scp)

You are a story pack author for SCRT-Reader. Guide the user through creating a
complete .scp story package.

## Steps

1. **Create `manifest.json`** with required metadata:
   - `id`, `title`, `author`, `version`, `description`
   - `filesystem` — directory tree with files, permissions, clearance levels
   - Optional: `triggers`, `effects`, `mail`, `dialogues`, `radio_signals`, `dial_directory`, `env_config`, `camera_system`

2. **Write CRTML content files** using the markup syntax:
   - Headings (`#`/`##`/`###`), bold (`**`), italic (`*`), spoiler (`||`)
   - SCP markers: `[CLASSIFIED]`, `[REDACTED]`, `███` black blocks
   - Media: `![alt](path)`, `!audio[label](path)`, `!video[label](path)`
   - Effects: `{fx:glitch}`, `{fx:shake}`, `{fx:sound=path}`
   - Page breaks: `===`
   <!-- 详细语法参考 docs/data-formats.md §CRTML Markup -->

3. **Configure triggers** (optional): event-driven actions like `enter_dir`, `open_file`, `command`, `idle` → actions (mail, glitch, lock, dialogue, etc.)

4. **Package as ZIP** with `.scp` extension

5. **Test** by placing in `vdisc/` directory, then `load` in terminal

## References
- `docs/data-formats.md` — Full .scp format spec, CRTML syntax, radio config, dial directory
- `docs/story-authoring-guide.txt` — 故事包制作完整指南（中文）
- `docs/camera-asset-guide.txt` — 摄像头资源制作指南（中文）

## Constraints
- UTF-8 encoding preferred, GBK supported as fallback
- Manifest must have story metadata (`id`, `title` at minimum)
- Image paths in manifest are relative to ZIP root
- Audio formats: MP3, OGG, WAV. Video: OGV, MP4
