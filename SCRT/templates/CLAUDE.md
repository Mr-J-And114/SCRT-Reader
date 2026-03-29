# templates/ — 文档查看器模板 (Document Viewer Templates)

> 上级文档：[/CLAUDE.md](/CLAUDE.md) | 数据格式：[/docs/data-formats.md](/docs/data-formats.md)
> 新增模板后请同步更新本文件的文件列表和 Template 枚举说明。

专用全屏文档查看器，通过文件头部 `template:` 字段选择对应模板。
所有模板继承 `RefCounted`，遵循覆盖层模式（`is_active` 标志 + Panel 覆盖 + ESC/Q 关闭）。

## 文件列表

| 文件 | 模板 ID | 行数 | 布局说明 |
|---|---|---|---|
| article_viewer.gd | `article` | 466 | 单页滚动浏览，底部进度条 |
| chat_viewer.gd | `chat` | 823 | 多角色聊天记录，带打字指示动画 |
| email_viewer.gd | `email` | 788 | 邮件格式，含发件人信息栏，单页滚动 |
| two_page_reader.gd | `two-page` | 571 | 双栏书籍布局，左/右翻页 |

## 模板选择流程

```
1. header_parser.gd 读取文件头部 → 提取 template: 字段
2. 映射到 HeaderParser.Template 枚举：DOCUMENT, TWO_PAGE, CHAT, EMAIL, REPORT, ARTICLE, RAW
3. document_viewer.gd 根据枚举值实例化对应查看器
```

## 文件头部字段（header_parser.gd 解析）

| 字段 | 说明 |
|---|---|
| `template` | 模板类型（article/chat/email/two-page 等） |
| `title` | 文档标题 |
| `password` | 打开密码（需要玩家输入才能阅读） |
| `typewriter_speed` | 打字速度覆盖 |
| `style` | 样式覆盖 |
| `date` | 日期显示 |
| `participants` | 参与者列表（Array，用于 chat 模板） |
| `author` | 作者 |
| `classification` | 机密等级标记 |
| `custom` | 自定义字典（任意键值对） |

## 添加新模板

1. 在 `SCRT/templates/` 创建 `my_viewer.gd`，继承 RefCounted
2. 在 `HeaderParser.Template` 枚举中添加新值
3. 在 `HeaderParser._template_map` 中添加字符串映射
4. 在 `document_viewer.gd` 的查看器选择逻辑中注册
5. 遵循覆盖层模式：`is_active` 标志、Panel 覆盖层、ESC/Q 关闭
6. 更新本文件的文件列表
