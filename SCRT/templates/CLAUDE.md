# templates/ — Document Viewer Templates

Specialized full-screen document viewers, selected by file header `template:` field.

## Files

| File | Template ID | Layout |
|---|---|---|
| article_viewer.gd | `article` | Single-page scroll with progress bar |
| chat_viewer.gd | `chat` | Multi-speaker chat log with typing indicator |
| email_viewer.gd | `email` | Email with sender info, single scroll |
| two_page_reader.gd | `two-page` | Dual-column book with left/right pagination |

All extend `RefCounted`, follow overlay pattern (`is_active`, `overlay: Panel`).

## Template Selection Flow

1. `header_parser.gd` reads file header → extracts `template:` field
2. Maps to `HeaderParser.Template` enum: DOCUMENT, TWO_PAGE, CHAT, EMAIL, REPORT, ARTICLE, RAW
3. `document_viewer.gd` instantiates the matching viewer

## Header Fields (parsed by header_parser.gd)

`template`, `title`, `password`, `typewriter_speed`, `style`, `date`, `participants` (Array), `author`, `classification`, `custom` (Dictionary)

## Adding a New Template

1. Create `SCRT/templates/my_viewer.gd` extending RefCounted
2. Add enum value in `HeaderParser.Template`
3. Add string mapping in `HeaderParser._template_map`
4. Register in `document_viewer.gd` viewer selection logic
5. Follow overlay pattern: `is_active` flag, Panel overlay, ESC/Q to close
