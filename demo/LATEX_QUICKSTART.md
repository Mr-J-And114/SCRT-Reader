# LaTeX 快速启动口令

> **给 AI 助手**：当用户说"开始做 LaTeX"或类似指令时，阅读本文件获取完整上下文。

---

## 快速启动指令

复制以下内容发给 AI 即可恢复完整上下文：

```
请阅读 D:\Godot\Projects\demo\LATEX_IMPLEMENTATION_GUIDE.md，然后开始实施 LaTeX 公式渲染器。

要求：
1. 先在 demo 项目中开发，文件位置：demo/scripts/latex_renderer.gd
2. 完成后同步到 SCRT/scripts/latex_renderer.gd
3. 先做 Demo PPT 集成（正文 + 图表），验证效果后再同步 SCRT CRTML
4. 用户使用 [math]...[/math] 标记行内公式，[math block]...[/math] 标记块级公式
5. 完成后创建一个示例展示 slide 验证所有效果
6. 字体测试已完成，Sarasa Mono SC 覆盖率 100%（详见实施指南第二节）
7. 遵循实施指南中的架构、AST 节点类型、布局规则、命令清单
8. 完成后更新 SCRT/scripts/CLAUDE.md 和 docs/data-formats.md
```

---

## 项目背景速览

- **项目**：SCRT-Reader（SCP 主题 CRT 终端模拟器）
- **引擎**：Godot 4.6，GDScript，全类型标注
- **Demo 位置**：`D:\Godot\Projects\demo\`
- **SCRT 位置**：`D:\Godot\Projects\SCRT\`
- **字体**：Sarasa Mono SC（等宽中文字体，含数学符号）
- **PPT 文件**：`demo/demo_camera.gd`（渲染） + `demo/demo_slides.gd`（数据）
- **CRTML 解析器**：`SCRT/scripts/crtml_parser.gd`（Markdown→BBCode）

---

## 关键文件索引

| 文件 | 用途 |
|------|------|
| `demo/LATEX_IMPLEMENTATION_GUIDE.md` | 完整实施规范（架构/AST/布局/命令清单） |
| `demo/demo_camera.gd` | PPT 渲染逻辑，集成点 |
| `demo/demo_slides.gd` | PPT 数据，示例展示 slide 位置 |
| `demo/fonts/SarasaMonoSC-Regular.ttf` | 正文字体（含数学符号） |
| `demo/fonts/SarasaMonoSC-SemiBold.ttf` | 粗体字体（\mathbf 用） |
| `demo/fonts/SarasaMonoSC-Italic.ttf` | 斜体字体（\mathit 用） |
| `SCRT/scripts/crtml_parser.gd` | CRTML 解析器，SCRT 集成点 |
| `SCRT/scripts/document_viewer.gd` | 文档查看器，已有 add_image 机制 |

---

## 开发顺序

1. `demo/scripts/latex_renderer.gd` — 命令映射表 + Tokenizer
2. → Parser（递归下降 → AST）
3. → Layout（测量 + 位置计算）
4. → Renderer（draw to Image）
5. → 可缩放定界符 + 环境支持
6. → 缓存 + public API
7. → 集成到 `demo/demo_camera.gd`（正文 + 图表）
8. → 示例展示 slide + 测试
9. → 同步到 `SCRT/scripts/latex_renderer.gd`
10. → 集成到 `SCRT/scripts/crtml_parser.gd`
11. → 更新文档

---

## 注意事项

- Demo 的 `_body_text` (RichTextLabel) 当前没有 `add_image()` 机制，需要新增
- SCRT 已有完整的内联图片机制（占位符 `\u0001IMG:id\u0002` → `add_image()`），可直接复用
- 字体切换：`SarasaMonoSC-Regular.ttf` → `SarasaMonoSC-SemiBold.ttf`（粗体）/ `SarasaMonoSC-Italic.ttf`（斜体）
- 缺失的下标字母（b/c/d/f/g/j/q/w/y/z）需自绘（缩小字号 + baseline 偏移）
- 缓存策略：`latex + "|" + font_size` 作为 key，静态字典存储 ImageTexture
