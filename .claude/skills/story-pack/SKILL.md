# Skill: Create Story Pack (.scp)

You are a story pack author for SCRT-Reader (Godot 4.6). Guide the user through
creating a complete .scp story package.

## Step 1: Create manifest.json

Minimal manifest:
```json
{
  "story": {
    "id": "my_story",
    "title": "故事标题",
    "author": "作者名",
    "version": "1.0",
    "description": "故事简介"
  },
  "filesystem": {
    "/": {
      "children": {
        "README.txt": { "type": "file" },
        "classified": {
          "type": "dir",
          "children": {
            "report.txt": { "type": "file", "clearance": 2 }
          }
        }
      }
    }
  }
}
```

### All Supported Manifest Keys

| Key | Type | Purpose |
|---|---|---|
| `story` | Object | **Required.** id, title, author, version, description |
| `filesystem` | Object | **Required.** Virtual directory tree definition |
| `settings.start_clearance` | int | Initial player security clearance level |
| `hidden_dirs` | Array | Paths hidden from `ls` output |
| `permissions` | Object | Per-path access control |
| `passwords` | Object | Password → clearance mapping |
| `file_passwords` | Object | Per-file unlock passwords |
| `ambient` | Object | Path → background music config `{file, volume}` |
| `headers` | Object | Path display metadata |
| `file_descriptions` | Object | File annotation strings |
| `triggers` | Object | Event-driven action system (see below) |
| `comm_characters` | Object | Character definitions (portrait, voice config) |
| `comm_dialogues` | Object | Dialogue scripts with lines, choices, conditions |
| `dial_directory` | Object | Phone numbers for voice calls and modem downloads |
| `mail_system` | Object | In-game email configuration |
| `radio_signals` | Array | Radio signal definitions (morse/sstv/audio) |
| `camera_system` | Object | CCTV camera definitions with assets |
| `env_config` | Object | Environment monitoring overrides |
| `daily_dialogues` | Object | Per-day dialogue and mail triggers |
| `loading_screen` | Object | Custom disc loading animation |

## Step 2: Write CRTML Content Files

Markdown-like syntax that converts to BBCode:

```markdown
# 一级标题
## 二级标题
### 三级标题

**粗体文本** 和 *斜体文本*
~~删除线~~ 和 `行内代码`
||这是剧透内容||

> 这是引用块

[CLASSIFIED] 或 [REDACTED] — SCP风格遮挡标记
███████████ — 黑色遮挡块

---  分隔线
===  翻页符

![图片说明](images/photo.png)
!audio[播放录音](audio/recording.mp3)
!video[观看录像](video/footage.ogv)

{tw:speed=30}  调整打字速度
{fx:glitch}    触发故障效果
{fx:shake}     触发屏幕震动
{fx:sound=audio/alert.ogg}  播放音效

| 列1 | 列2 | 列3 |
|-----|-----|-----|
| 数据 | 数据 | 数据 |
```

## Step 3: Configure Triggers (optional)

```json
{
  "triggers": {
    "/classified": [
      {
        "condition": "on_first_enter",
        "actions": ["glitch:chaos", "new_mail:warning_msg"]
      }
    ],
    "/classified/report.txt": [
      {
        "condition": "on_open_file:report.txt",
        "actions": ["sound:audio/alert.ogg", "comm:debrief_dialogue"]
      }
    ]
  }
}
```

### Trigger Conditions

| Condition | Description |
|---|---|
| `on_enter` | Every directory entry (repeatable) |
| `on_first_enter` | First entry only (one-shot) |
| `on_open_file:filename` | When specific file is opened |
| `on_level_reach:N` | When clearance reaches level N |
| `on_read_complete:path` | After file is fully read |
| `on_command:cmdname` | When command executed in this directory |
| `on_idle:N` | After N seconds of inactivity |

Suffix modifiers: `.once` (force one-shot), `.repeat` (force repeatable)

### Trigger Actions

| Action | Description |
|---|---|
| `new_mail:mail_id` | Deliver email |
| `level_up:N` | Raise security clearance |
| `sound:path` | Play sound effect |
| `text:message` | Output text to terminal |
| `redirect:/path` | Auto-navigate to directory |
| `glitch:intensity[:duration_ms]` | Visual glitch (or preset name like `chaos`, `heavy`) |
| `shake:intensity:duration_ms` | Screen shake |
| `tear:strength:duration_ms` | Tear distortion |
| `noise_burst:intensity:duration_ms` | Static burst |
| `play_effect:effect_id` | Trigger named effect sequence |
| `preset_effect:name[:duration_ms]` | Preset effect |
| `screen_off:ms` | Black screen |
| `reboot` | Simulate reboot |
| `lock_folder:/path` | Lock directory |
| `unlock_folder:/path` | Unlock directory |
| `color_scheme:theme[:force]` | Switch theme |
| `comm:dialogue_id` | Trigger dialogue |
| `delay:ms:action` | Delay then execute action |
| `camera_unlock:cam_id` | Unlock camera |
| `camera_anomaly:cam_id[:anom_id]` | Trigger camera anomaly |

## Step 4: Package as ZIP

1. Place all content files (text, images, audio, video) in a folder
2. Put `manifest.json` at the root of the folder
3. ZIP the folder contents (manifest.json should be at ZIP root, not nested)
4. Rename `.zip` to `.scp`

## Step 5: Test

1. Place `.scp` file in `vdisc/` directory
2. Launch the terminal
3. Run `scan` to detect the disc
4. Run `load` to load the story
5. Navigate with `cd`, `ls`, `open` to verify content
6. Test triggers by entering configured directories/opening files
7. Run `eject` and `load` again to test save/load

## References
- `docs/data-formats.md` — Full format specifications
- `docs/story-authoring-guide.txt` — 故事包制作完整指南（中文）
- `docs/camera-asset-guide.txt` — 摄像头资源制作指南（中文）

## Constraints
- UTF-8 encoding preferred, GBK supported as fallback
- Manifest must have `story.id` and `story.title` at minimum
- All asset paths in manifest are relative to ZIP root
- Audio formats: MP3, OGG, WAV. Video: OGV, MP4. Images: PNG, JPG
- Hidden signals (`hidden: true`) won't appear on radio UI but are discoverable by tuning
