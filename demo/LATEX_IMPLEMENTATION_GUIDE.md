# LaTeX 公式渲染器 — AI 实施指南

> **给 AI 助手的第一条指令**：本文件是 LaTeX 公式渲染功能的完整实施规范。
> 开发位置：`demo/scripts/latex_renderer.gd`，完成后同步到 `SCRT/scripts/latex_renderer.gd`。
> 先做 Demo 集成，验证效果后再同步本体项目。

---

## 一、目标

在 Demo PPT 和 SCRT CRTML 文本系统中实现接近网页级 LaTeX 公式渲染能力。
用户在文本中使用 `[math]...[/math]`（行内）和 `[math block]...[/math]`（块级）标记，
渲染时自动转为 Image 并插入 RichTextLabel 或 draw 到画布。

---

## 二、字体测试结论（已完成）

**测试字体**：`demo/fonts/SarasaMonoSC-Regular.ttf`（25MB）

| 类别 | 覆盖率 | 说明 |
|------|--------|------|
| 数学运算符 (67个) | 100% | × ÷ ± ∓ ≤ ≥ ≠ ≈ → ← ∴ ∝ ∠ · ∧ ∨ ∩ ∪ ∈ ∉ ⊂ ⊃ ∅ ℝ ℕ |
| 希腊字母 | 100% | α-ω + Α-Ω |
| 大型运算符 | 100% | ∑ ∏ ∫ ∮ ∬ ∯ |
| 上标小写字母 | 26/26 | a-z 全覆盖 (U+1D41-U+1D5A) |
| 上标数字/符号 | 100% | 0-9 + - ( ) |
| 下标字母 | 16/16 已测 | a e h i k l m n o p r s t u v x |
| 可缩放定界符碎片 | 100% | ⎛⎝⎡⎣⎧⎩ 等 (U+239B-U+23A9) |
| 分数斜杠 | ✅ | ⁄ (U+2044) |
| 数学字母变体 (U+1D400+) | 0% | ❌ 无 Unicode bold/italic 变体，需用字体文件切换 |

**缺失的上下标字母**（Unicode 标准本身不存在）：`_b _c _d _f _g _j _q _w _y _z`
→ 这些必须自绘（缩小字号 + baseline 偏移）

**粗体/斜体**：用 `SarasaMonoSC-SemiBold.ttf` 和 `SarasaMonoSC-Italic.ttf` 字体文件切换实现

---

## 三、架构

### 模块结构

```
latex_renderer.gd (新文件，约 1500-1800 行)
├── _LatexTokenizer        # 词法分析
├── _LatexParser           # 语法分析 → AST
├── _LatexLayout           # 布局引擎 → 位置树
├── _LatexRenderer         # 渲染器 → Image
├── 命令映射表              # \alpha→α 等
└── public API
    ├── render_to_texture(latex, font_size) -> ImageTexture
    └── render_to_image(latex, font_size) -> Image
```

### 渲染流程

```
[math]\frac{1}{1+x^2}[/math]

Step 1: Tokenize → Token 流
Step 2: Parse → AST (递归下降)
Step 3: Layout → 位置树 (measure + position)
Step 4: Render → Image (draw_string + draw_line + draw_rect)
Step 5: Image → ImageTexture → add_image() / draw_texture
```

---

## 四、AST 节点类型

| 类型 | 字段 | 示例 LaTeX |
|------|------|-----------|
| `Atom` | text, font_style(normal/bold/italic) | `x`, `\alpha`, `+` |
| `Script` | base, sup, sub | `x^2`, `x_i` |
| `Fraction` | numerator, denominator | `\frac{a}{b}` |
| `Root` | radicand, index | `\sqrt{x}`, `\sqrt[3]{x}` |
| `BigOp` | operator, sup, sub | `\sum_{i=1}^{n}` |
| `Delimited` | content, left_delim, right_delim | `\left( \frac{1}{2} \right)` |
| `Matrix` | rows, delim_type(none/paren/bracket/brace/bar) | `\begin{pmatrix}...\end{pmatrix}` |
| `Cases` | rows (Array of (condition, value)) | `\begin{cases}...\end{cases}` |
| `Aligned` | rows, column_count | `\begin{aligned}...\end{aligned}` |
| `OverUnder` | content, decoration(overline/underline/hat/vec/dot/ddot/tilde/bar) | `\overline{x}`, `\vec{v}` |
| `Space` | width_em | `\quad`, `\,` |
| `Color` | content, color_hex | `\color{red}...` |
| `Row` | children (Array of nodes) | `a + b + c` |

---

## 五、布局规则

```
base_font_size = 传入参数（如 18px）
script_size    = base × 0.70   (上标/下标)
frac_size      = base × 0.85   (分子/分母)
matrix_size    = base × 0.90   (矩阵单元格)

分数布局：
  numerator  居中放在分数线之上
  horizontal line (draw_line)
  denominator 居中放在分数线之下
  总高度 = num_h + line_gap(4px) + 1px + line_gap(3px) + den_h
  总宽度 = max(num_w, den_w) + padding(8px)

上下标布局：
  sup: 放在 base 右上角，baseline 上移 base_h × 0.5
  sub: 放在 base 右下角，baseline 下移 base_h × 0.3
  BigOp (∑∫): sup/sub 居中放在符号正上/正下

矩阵布局：
  grid: 列宽取每列最宽单元格
  cell padding: 6px 水平, 3px 垂直
  delim: 根据高度选择对应 Unicode 大型定界符碎片或自绘

根号布局：
  √ 符号 + radicand
  上方画横线覆盖 radicand 宽度
  index (n) 放在 √ 左上角，更小字号 (×0.6)

可缩放定界符：
  优先用 Unicode 碎片 (⎛⎝⎡⎣⎧⎩)
  超大尺寸时自绘（draw_line 画弧线/直线）
```

---

## 六、支持的 LaTeX 命令

### P0 — 核心结构（必须实现）

| 命令 | 说明 |
|------|------|
| `\frac{}{}` | 分数 |
| `\sqrt{}` | 平方根 |
| `\sqrt[]{}` | n 次根 |
| `^{}` | 上标 |
| `_ {}` | 下标 |
| `\\` | 换行 |
| `&` | 矩阵列分隔 |
| `\sum` `\int` `\prod` `\oint` `\lim` | 大运算符 |
| `\limits` `\nolimits` | 大运算符上下标位置 |
| `\left` `\right` + `(` `)` `[` `]` `\{` `\}` `\|` `\|` `.` | 可缩放定界符 |
| `\begin{matrix}` `\begin{pmatrix}` `\begin{bmatrix}` `\begin{cases}` `\begin{aligned}` | 环境 |

### P1 — 常用符号（必须实现）

| 类别 | 命令 |
|------|------|
| 希腊字母 | `\alpha` `\beta` `\gamma` `\delta` `\epsilon` `\theta` `\lambda` `\mu` `\pi` `\sigma` `\phi` `\omega` `\Sigma` `\Delta` `\Omega` (约 50 个) |
| 运算符 | `\times` `\div` `\pm` `\mp` `\leq` `\geq` `\neq` `\approx` `\to` `\cdot` `\cdots` `\ldots` `\vdots` `\ddots` |
| 集合论 | `\in` `\notin` `\subset` `\supset` `\cup` `\cap` `\emptyset` `\setminus` |
| 逻辑 | `\forall` `\exists` `\nabla` `\partial` `\infty` `\neg` |
| 装饰 | `\overline{}` `\underline{}` `\hat{}` `\vec{}` `\dot{}` `\ddot{}` `\tilde{}` `\bar{}` |

### P2 — 扩展功能

| 类别 | 命令 |
|------|------|
| 字体 | `\mathbf{}` `\mathit{}` `\mathrm{}` `\text{}` `\boldsymbol{}` |
| 间距 | `\,` `\:` `\;` `\quad` `\qquad` `\!` |
| 二项式 | `\binom{}{}` |
| 箭头 | `\rightarrow` `\leftarrow` `\Rightarrow` `\Leftarrow` `\leftrightarrow` `\mapsto` `\uparrow` `\downarrow` |
| 函数名 | `\det` `\max` `\min` `\sup` `\inf` `\log` `\ln` `\exp` `\sin` `\cos` `\tan` `\cot` `\sec` `\csc` `\arcsin` `\arccos` `\arctan` `\sinh` `\cosh` `\tanh` |
| 颜色 | `\color{}` (扩展) |

---

## 七、集成方案

### Demo PPT（先做）

#### 7.1 正文公式

**文件**：`demo/demo_camera.gd`

在 `_render_diagram_slide`、`_render_code_slide`、`_render_content_slide`、`_render_camera_link_slide` 中，
设置 `_body_text.text` 之前插入公式处理：

```gdscript
# 伪代码
var body_raw: String = slide.get("body", "")
_body_text.text = _process_math_in_body(body_raw)
```

`_process_math_in_body` 逻辑：
1. 扫描 `[math]...[/math]` 和 `[math block]...[/math]`
2. 提取 LaTeX → `LatexRenderer.render_to_texture(latex, font_size)`
3. 缓存纹理，生成占位符 `\u0001IMG:LATEX_n\u0002`
4. 用 RichTextLabel 的 `add_image()` 插入（参考 SCRT 的内联图片机制）

**注意**：Demo 的 `_body_text` 是 RichTextLabel，但当前没有 add_image 机制。
需要新增：在设置 text 后，扫描占位符并用 `add_image()` 替换。
或者改用 `clear()` + `add_text()` + `add_image()` 逐段构建内容。

#### 7.2 图表公式

**文件**：`demo/demo_camera.gd` 的 `_draw_*` 函数

将公式预渲染为 ImageTexture，用 `dc.draw_texture_rect(tex, Rect2(x, y, w, h), false)` 绘制。

示例（Slide 7 的 `_draw_local_variation`）：
```gdscript
# 旧：
var formula: String = "final = ref_distance + (raw - mask_mean) × scale"
dc.draw_string(font, Vector2(cx - fw * 0.5, formula_y), formula, ...)

# 新：
var formula_tex: ImageTexture = LatexRenderer.render_to_texture(
    "final = ref_{dist} + (raw - \\mu) \\times scale", 14)
var fw2: float = formula_tex.get_width()
dc.draw_texture_rect(formula_tex, Rect2(cx - fw2 * 0.5, formula_y, fw2, formula_tex.get_height()), false)
```

#### 7.3 示例展示文档

创建一个测试 slide（可加在 Slide 14 之前），展示所有支持的公式效果：
```gdscript
# 测试 slide
{
    "type": "content",
    "title": "LaTeX 公式渲染测试",
    "body": "[b]行内公式[/b]\n" +
            "欧拉公式：[math]e^{i\pi} + 1 = 0[/math]\n\n" +
            "[b]块级公式[/b]\n" +
            "[math block]\\int_{0}^{\\infty} e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}[/math]\n\n" +
            "[b]分数[/b]\n" +
            "[math]\\frac{1}{1+x^2}[/math]\n\n" +
            "[b]矩阵[/b]\n" +
            "[math]\\begin{pmatrix} 1 & 2 \\\\ 3 & 4 \\end{pmatrix}[/math]\n\n" +
            "[b]求和[/b]\n" +
            "[math]\\sum_{i=1}^{n} i = \\frac{n(n+1)}{2}[/math]\n\n" +
            "[b]根号[/b]\n" +
            "[math]\\sqrt{x^2+y^2}[/math]\n\n" +
            "[b]cases 环境[/b]\n" +
            "[math]|x| = \\begin{cases} x & x \\geq 0 \\\\ -x & x < 0 \\end{cases}[/math]",
}
```

### SCRT CRTML（后做，Demo 验证后同步）

#### 7.4 CRTML 解析器集成

**文件**：`SCRT/scripts/crtml_parser.gd`

在 `_process_inline()` 末尾新增：
```gdscript
# 12. LaTeX 公式 [math]...[/math] 和 [math block]...[/math]
result = _parse_math(result)
```

`_parse_math()` 逻辑：
1. 扫描 `[math]...[/math]`（行内）和 `[math block]...[/math]`（块级）
2. 提取 LaTeX → `LatexRenderer.render_to_texture(latex, font_size)`
3. 复用已有的 `_inline_image_cache` 机制
4. 输出 `\u0001IMG:placeholder_id\u0002` 占位符
5. 下游 `document_viewer.gd` / `typewriter.gd` 的 `add_image()` 自动处理

**字体大小**：行内公式用 RichTextLabel 的 normal_font_size（18px），块级用 22px。

---

## 八、缓存策略

```gdscript
# latex_renderer.gd 中
static var _cache: Dictionary = {}  # key(hash) → ImageTexture

static func render_to_texture(latex: String, font_size: int) -> ImageTexture:
    var key: String = latex + "|" + str(font_size)
    if _cache.has(key):
        return _cache[key]
    var img: Image = render_to_image(latex, font_size)
    var tex: ImageTexture = ImageTexture.create_from_image(img)
    _cache[key] = tex
    return tex
```

缓存无上限（公式数量有限），如果需要 LRU 可以后续加。

---

## 九、文件清单

| 文件 | 操作 | 估行数 | 说明 |
|------|------|--------|------|
| `demo/scripts/latex_renderer.gd` | 新建 | ~1500-1800 | 主开发位置 |
| `SCRT/scripts/latex_renderer.gd` | 新建 | 同上 | 同步副本 |
| `SCRT/scripts/crtml_parser.gd` | 修改 | +~40 | 新增 `_parse_math()` |
| `demo/demo_camera.gd` | 修改 | +~60 | 正文/图表集成 |
| `SCRT/scripts/CLAUDE.md` | 修改 | +1 行 | 新增 latex_renderer.gd 条目 |
| `docs/data-formats.md` | 修改 | +~20 | 新增 `[math]` 标记说明 |

---

## 十、实施步骤与估时

| 步骤 | 内容 | 估时 | 依赖 |
|------|------|------|------|
| 1 | 命令映射表 + Tokenizer | 5h | 无 |
| 2 | Parser（递归下降 → AST） | 5h | 步骤 1 |
| 3 | Layout（测量 + 位置计算） | 6h | 步骤 2 |
| 4 | Renderer（draw to Image） | 4h | 步骤 3 |
| 5 | 可缩放定界符 | 2h | 步骤 4 |
| 6 | 环境支持（matrix/cases/aligned） | 3h | 步骤 4 |
| 7 | 缓存 + public API | 1h | 步骤 4 |
| 8 | 集成到 Demo PPT（正文 + 图表） | 2h | 步骤 7 |
| 9 | 示例展示文档 + 测试 | 2h | 步骤 8 |
| 10 | 同步到 SCRT CRTML | 2h | 步骤 9 |
| 11 | 更新文档 | 1h | 步骤 10 |

**总计约 33 小时（约 4-5 天）**

---

## 十一、风险与缓解

| 风险 | 缓解方案 |
|------|---------|
| 复杂公式布局不准 | 参考 KaTeX 源码的布局逻辑 |
| 性能问题（大公式渲染慢） | 静态缓存 + 预渲染 |
| 缺失的上下标字母 | 自绘（缩小字号 + baseline 偏移） |
| 可缩放定界符不完美 | 优先用 Unicode 碎片，超大时自绘 |
| Godot Image 绘制 API 限制 | 用 Font.draw_char() + draw_line + draw_rect |
| Demo RichTextLabel 无 add_image 机制 | 新增：clear() + add_text() + add_image() 逐段构建 |

---

## 十二、验证方式

1. 在 Demo PPT 中插入示例展示 slide
2. 检查所有公式是否正确渲染：
   - 分数（分子分母堆叠 + 分数线）
   - 上下标（位置正确，缺失字母自绘）
   - 根号（符号 + 上方横线）
   - 求和/积分（符号 + 上下限）
   - 矩阵（网格对齐 + 定界符）
   - cases 环境（左大括号 + 条件对齐）
   - 希腊字母（正确显示）
   - 粗体/斜体（字体切换）
3. 检查行内公式与文字对齐
4. 检查块级公式居中

---

## 十三、关键参考

- **KaTeX 源码**：https://github.com/KaTeX/KaTeX （布局逻辑参考）
- **Unicode 数学字符参考**：https://unicode.org/charts/PDF/U2200.pdf
- **Godot Font API**：`Font.draw_char()` `Font.get_string_size()` `Font.get_char_size()`
- **Godot Image API**：`Image.create()` `Image.fill()` `RenderingServer`
- **项目已有内联图片机制**：`crtml_parser.gd` 的 `_build_image_inline()` + `document_viewer.gd` 的 `_append_line_with_images()`
