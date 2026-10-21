# ============================================================
# latex_renderer.gd - LaTeX 公式渲染器
# 职责：LaTeX → Tokenize → Parse(AST) → Layout → Render(Image)
# 架构：RefCounted，通过 setup() 注入字体和宿主节点
# ============================================================
class_name LatexRenderer
extends RefCounted

# ══════════════════════════════════════════
#  常量
# ══════════════════════════════════════════

const DEFAULT_COLOR := Color(0.78, 0.9, 0.78, 1.0)
const PADDING := 2.0

# 布局比例
const SCALE_SCRIPT := 0.70
const SCALE_FRAC := 0.85
const SCALE_MATRIX := 0.90
const SCALE_ROOT_INDEX := 0.60
const FRAC_LINE_GAP_TOP := 4.0
const FRAC_LINE_GAP_BOT := 3.0
const FRAC_LINE_THICKNESS := 1.5
const FRAC_PADDING := 6.0

# ══════════════════════════════════════════
#  命令映射表
# ══════════════════════════════════════════

const GREEK_LOWER := {
	"alpha": "\u03B1", "beta": "\u03B2", "gamma": "\u03B3", "delta": "\u03B4",
	"epsilon": "\u03B5", "varepsilon": "\u03F5", "zeta": "\u03B6", "eta": "\u03B7",
	"theta": "\u03B8", "vartheta": "\u03D1", "iota": "\u03B9", "kappa": "\u03BA",
	"varkappa": "\u03F0", "lambda": "\u03BB", "mu": "\u03BC", "nu": "\u03BD",
	"xi": "\u03BE", "omicron": "\u03BF", "pi": "\u03C0", "varpi": "\u03D6",
	"rho": "\u03C1", "varrho": "\u03F1", "sigma": "\u03C3", "varsigma": "\u03C2",
	"tau": "\u03C4", "upsilon": "\u03C5", "phi": "\u03C6", "varphi": "\u03D5",
	"chi": "\u03C7", "psi": "\u03C8", "omega": "\u03C9",
}

const GREEK_UPPER := {
	"Alpha": "\u0391", "Beta": "\u0392", "Gamma": "\u0393", "Delta": "\u0394",
	"Epsilon": "\u0395", "Zeta": "\u0396", "Eta": "\u0397", "Theta": "\u0398",
	"Iota": "\u0399", "Kappa": "\u039A", "Lambda": "\u039B", "Mu": "\u039C",
	"Nu": "\u039D", "Xi": "\u039E", "Omicron": "\u039F", "Pi": "\u03A0",
	"Rho": "\u03A1", "Sigma": "\u03A3", "Tau": "\u03A4", "Upsilon": "\u03A5",
	"Phi": "\u03A6", "Chi": "\u03A7", "Psi": "\u03A8", "Omega": "\u03A9",
}

const MATH_SYMBOLS := {
	"times": "\u00D7", "div": "\u00F7", "pm": "\u00B1", "mp": "\u2213",
	"leq": "\u2264", "geq": "\u2265", "neq": "\u2260", "approx": "\u2248",
	"equiv": "\u2261", "sim": "\u223C", "simeq": "\u2243", "cong": "\u2245",
	"propto": "\u221D", "angle": "\u2220", "therefore": "\u2234",
	"because": "\u2235", "cdots": "\u22EF", "ldots": "\u2026",
	"vdots": "\u22EE", "ddots": "\u22F1", "cdot": "\u00B7",
	"neg": "\u00AC", "land": "\u2227", "wedge": "\u2227",
	"lor": "\u2228", "vee": "\u2228", "oplus": "\u2295", "otimes": "\u2297",
	"partial": "\u2202", "nabla": "\u2207", "infty": "\u221E",
	"in": "\u2208", "notin": "\u2209", "ni": "\u220B",
	"subset": "\u2282", "supset": "\u2283", "subseteq": "\u2286", "supseteq": "\u2287",
	"cup": "\u222A", "cap": "\u2229", "emptyset": "\u2205", "varnothing": "\u2205",
	"setminus": "\u2216", "forall": "\u2200", "exists": "\u2203", "nexists": "\u2204",
	"square": "\u25A1", "blacksquare": "\u25A0", "triangle": "\u25B3",
	"circ": "\u2218", "bullet": "\u2022", "ast": "\u2217", "star": "\u22C6",
	"diamond": "\u22C4", "prime": "\u2032", "dprime": "\u2033",
	"ell": "\u2113", "hbar": "\u210F", "Re": "\u211C", "Im": "\u2111",
	"aleph": "\u2135", "beth": "\u2136",
	"perp": "\u22A5", "parallel": "\u2225",
	"mid": "\u2223", "nmid": "\u2224",
	"flat": "\u266D", "natural": "\u266E", "sharp": "\u266F",
	"degree": "\u00B0",
}

const ARROWS := {
	"rightarrow": "\u2192", "gets": "\u2190", "leftarrow": "\u2190",
	"Rightarrow": "\u21D2", "Leftarrow": "\u21D0", "Leftrightarrow": "\u21D4",
	"leftrightarrow": "\u2194", "mapsto": "\u21A6", "uparrow": "\u2191",
	"downarrow": "\u2193", "updownarrow": "\u2195", "Updownarrow": "\u21D5",
	"nearrow": "\u2197", "searrow": "\u2198", "nwarrow": "\u2196", "swarrow": "\u2199",
	"hookrightarrow": "\u21AA", "hookleftarrow": "\u21A9",
	"rightleftharpoons": "\u21CC", "leftrightharpoons": "\u21CB",
}

const SPACING_COMMANDS := {
	",": 0.167, ":": 0.222, ";": 0.278, "!": -0.167,
	"quad": 1.0, "qquad": 2.0, "thinspace": 0.167,
	"medspace": 0.222, "thickspace": 0.278,
	"enspace": 0.5,
}

const FUNCTION_NAMES := [
	"det", "max", "min", "sup", "inf", "log", "ln", "exp",
	"sin", "cos", "tan", "cot", "sec", "csc",
	"arcsin", "arccos", "arctan", "sinh", "cosh", "tanh",
	"lim", "gcd", "deg", "dim", "hom", "ker", "Pr", "arg",
	"sech", "csch", "coth", "arcsinh", "arccosh", "arctanh",
]

const DECORATION_COMMANDS := {
	"overline": "overline", "underline": "underline",
	"hat": "hat", "vec": "vec", "dot": "dot", "ddot": "ddot",
	"tilde": "tilde", "bar": "bar", "check": "check",
	"breve": "breve", "acute": "acute", "grave": "grave",
	"widehat": "hat", "widetilde": "tilde",
	"overrightarrow": "vec", "overleftarrow": "vecleft",
	"overbrace": "overbrace", "underbrace": "underbrace",
}

const BIG_OPS := {
	"sum": "\u2211", "prod": "\u220F", "coprod": "\u2210",
	"iint": "\u222C", "iiint": "\u222D",
	"bigcup": "\u22C3", "bigcap": "\u22C2", "bigsqcup": "\u2294",
	"bigvee": "\u22C1", "bigwedge": "\u22C0", "bigoplus": "\u2A01", "bigotimes": "\u2A02",
	"bigodot": "\u2A00", "biguplus": "\u2A04",
}

const COLOR_NAMES := {
	"red": "#FF6666", "green": "#99FF99", "blue": "#66CCFF",
	"yellow": "#FFD966", "orange": "#FFA500", "purple": "#CC99FF",
	"cyan": "#66FFFF", "magenta": "#FF66FF", "white": "#FFFFFF",
	"black": "#000000", "gray": "#888888", "grey": "#888888",
	"pink": "#FFC0CB", "brown": "#A0522D", "lime": "#BFFF00",
	"olive": "#808000", "navy": "#000080", "teal": "#008080",
	"violet": "#EE82EE", "gold": "#FFD700", "silver": "#C0C0C0",
}

# ══════════════════════════════════════════
#  实例变量
# ══════════════════════════════════════════

var _host: Node = null
var _drawing: bool = false
signal draw_finished
var _viewport: SubViewport = null
var _canvas: _LatexCanvas = null
var _fonts: Dictionary = {}
var _default_color: Color = DEFAULT_COLOR

static var _cache: Dictionary = {}

# ══════════════════════════════════════════
#  初始化
# ══════════════════════════════════════════

func setup(host: Node, font_regular: Font, font_bold: Font,
		font_italic: Font, font_bold_italic: Font) -> void:
	_host = host
	_fonts = {
		"normal": font_regular,
		"bold": font_bold,
		"italic": font_italic,
		"bold_italic": font_bold_italic,
		"mathrm": font_regular,
		"mathit": font_italic,
		"mathbf": font_bold,
		"boldsymbol": font_bold,
		"text": font_regular,
	}
	_ensure_viewport()

func set_default_color(color: Color) -> void:
	_default_color = color

func _ensure_viewport() -> void:
	if _viewport != null and is_instance_valid(_viewport):
		return
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(10, 10)
	_viewport.transparent_bg = true
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.disable_3d = true
	if _host != null:
		_host.add_child(_viewport)
	_canvas = _LatexCanvas.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_viewport.add_child(_canvas)

# ══════════════════════════════════════════
#  Public API
# ══════════════════════════════════════════

func render_to_texture(latex: String, font_size: int = 18) -> ImageTexture:
	return await _render_to_texture_colored(latex, font_size, _default_color)

func render_to_texture_colored(latex: String, font_size: int, color: Color) -> ImageTexture:
	return await _render_to_texture_colored(latex, font_size, color)

func _render_to_texture_colored(latex: String, font_size: int, color: Color) -> ImageTexture:
	var cache_key: String = latex + "|" + str(font_size) + "|" + color.to_html()
	if _cache.has(cache_key):
		return _cache[cache_key]
	var img: Image = await _render_to_image_internal(latex, font_size, color)
	if img == null:
		return null
	var tex: ImageTexture = ImageTexture.create_from_image(img)
	_cache[cache_key] = tex
	return tex

func render_to_image(latex: String, font_size: int = 18) -> Image:
	return await _render_to_image_internal(latex, font_size, _default_color)

func render_to_image_colored(latex: String, font_size: int, color: Color) -> Image:
	return await _render_to_image_internal(latex, font_size, color)

func clear_cache() -> void:
	_cache.clear()

static func clear_global_cache() -> void:
	_cache.clear()

func get_cached_texture(latex: String, font_size: int = 18) -> ImageTexture:
	var key: String = latex + "|" + str(font_size) + "|" + _default_color.to_html()
	if _cache.has(key):
		return _cache[key]
	return null

func is_cached(latex: String, font_size: int = 18) -> bool:
	var key: String = latex + "|" + str(font_size) + "|" + _default_color.to_html()
	return _cache.has(key)

# ══════════════════════════════════════════
#  内部渲染
# ══════════════════════════════════════════

func _render_to_image_internal(latex: String, font_size: int, color: Color) -> Image:
	if latex.strip_edges().is_empty():
		return _create_empty_image()
	_ensure_viewport()
	if _fonts.is_empty():
		push_error("[LatexRenderer] 字体未设置，请先调用 setup()")
		return _create_empty_image()

	var tokenizer := _Tokenizer.new(latex)
	var tokens: Array = tokenizer.tokenize()
	if tokens.is_empty():
		return _create_empty_image()

	var parser := _Parser.new(tokens)
	var ast: Dictionary = parser.parse()
	if ast.is_empty():
		return _create_empty_image()

	var layout := _Layout.new(_fonts)
	var box: Dictionary = layout.layout_node(ast, font_size, "normal", color)
	if box.is_empty() or box.get("commands", []).is_empty():
		return _create_empty_image()

	return await _draw_to_image(box)

func _draw_to_image(box: Dictionary) -> Image:
	# 所有调用共用一个 SubViewport，避免并发打开时相互覆盖绘制内容。
	while _drawing:
		await draw_finished
	if not is_instance_valid(_host):
		return _create_empty_image()
	_drawing = true
	var result: Image = await _draw_to_image_exclusive(box)
	_drawing = false
	draw_finished.emit()
	return result

func _draw_to_image_exclusive(box: Dictionary) -> Image:
	var w: int = int(ceil(box.get("width", 1.0))) + int(PADDING * 2)
	var h: int = int(ceil(box.get("height", 1.0))) + int(PADDING * 2)
	w = max(w, 2)
	h = max(h, 2)

	_viewport.size = Vector2i(w, h)
	_canvas.commands = box.get("commands", [])
	_canvas.fonts = _fonts
	_canvas.offset = Vector2(PADDING, PADDING)
	_canvas.queue_redraw()

	await _await_frame()
	await RenderingServer.frame_post_draw

	if not is_instance_valid(_viewport):
		return _create_empty_image()
	var tex: ViewportTexture = _viewport.get_texture()
	if tex == null:
		return _create_empty_image()
	var img: Image = tex.get_image()
	if img == null:
		await _await_frame()
		await RenderingServer.frame_post_draw
		img = tex.get_image()
	if img == null:
		return _create_empty_image()

	var result: Image = Image.create(w, h, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	result.blend_rect(img, Rect2i(0, 0, w, h), Vector2i(0, 0))
	return result

func _await_frame() -> void:
	var tree: SceneTree = null
	if _host != null and is_instance_valid(_host) and _host.is_inside_tree():
		tree = _host.get_tree()
	if tree == null:
		var ml: MainLoop = Engine.get_main_loop()
		if ml is SceneTree:
			tree = ml as SceneTree
	if tree != null:
		await tree.process_frame
	else:
		await RenderingServer.frame_pre_draw

func _create_empty_image() -> Image:
	var img: Image = Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	return img

# ══════════════════════════════════════════
#  Tokenizer (词法分析)
# ══════════════════════════════════════════

class _Tokenizer:
	enum T { CMD, CHAR, LBRACE, RBRACE, LBRACKET, RBRACKET, CARET, UNDERSCORE, AMP, DNEWLINE, EOF }

	var _text: String = ""
	var _pos: int = 0
	var _tokens: Array = []

	func _init(text: String) -> void:
		_text = text

	func tokenize() -> Array:
		_tokens.clear()
		_pos = 0
		var n: int = _text.length()
		while _pos < n:
			var ch: String = _text[_pos]
			if ch == "\\":
				_tokenize_backslash()
			elif ch == "{":
				_tokens.append({type = T.LBRACE, value = ch})
				_pos += 1
			elif ch == "}":
				_tokens.append({type = T.RBRACE, value = ch})
				_pos += 1
			elif ch == "[":
				_tokens.append({type = T.LBRACKET, value = ch})
				_pos += 1
			elif ch == "]":
				_tokens.append({type = T.RBRACKET, value = ch})
				_pos += 1
			elif ch == "^":
				_tokens.append({type = T.CARET, value = ch})
				_pos += 1
			elif ch == "_":
				_tokens.append({type = T.UNDERSCORE, value = ch})
				_pos += 1
			elif ch == "&":
				_tokens.append({type = T.AMP, value = ch})
				_pos += 1
			elif ch == " " or ch == "\t" or ch == "\r":
				_pos += 1
			elif ch == "\n":
				_pos += 1
			else:
				_tokens.append({type = T.CHAR, value = ch})
				_pos += 1
		_tokens.append({type = T.EOF, value = ""})
		return _tokens

	func _tokenize_backslash() -> void:
		_pos += 1
		var n: int = _text.length()
		if _pos >= n:
			_tokens.append({type = T.CMD, value = ""})
			return
		var ch: String = _text[_pos]
		if ch == "\\":
			_tokens.append({type = T.DNEWLINE, value = "\\\\"})
			_pos += 1
			return
		if ch == "," or ch == ":" or ch == ";" or ch == "!" or ch == " " or ch == "%":
			_tokens.append({type = T.CMD, value = ch})
			_pos += 1
			return
		if ch == "{" or ch == "}" or ch == "|" or ch == "_" or ch == "#" or ch == "$":
			_tokens.append({type = T.CHAR, value = ch})
			_pos += 1
			return
		if _is_letter(ch):
			var start: int = _pos
			while _pos < n and _is_letter(_text[_pos]):
				_pos += 1
			var name: String = _text.substr(start, _pos - start)
			_tokens.append({type = T.CMD, value = name})
			return
		_tokens.append({type = T.CMD, value = ch})
		_pos += 1

	func _is_letter(ch: String) -> bool:
		return (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z")

# ══════════════════════════════════════════
#  Parser (语法分析 → AST)
# ══════════════════════════════════════════

class _Parser:
	var _tokens: Array = []
	var _pos: int = 0
	var _has_error: bool = false

	func _init(tokens: Array) -> void:
		_tokens = tokens

	func parse() -> Dictionary:
		var node: Dictionary = _parse_row(false)
		if _has_error:
			return {}
		return node

	func _cur() -> Dictionary:
		if _pos < _tokens.size():
			return _tokens[_pos]
		return {type = _Tokenizer.T.EOF, value = ""}

	func _cur_type() -> int:
		return _cur().type

	func _cur_val() -> String:
		return _cur().value

	func _advance() -> Dictionary:
		var t: Dictionary = _cur()
		_pos += 1
		return t

	func _expect(type_: int) -> Dictionary:
		var t: Dictionary = _cur()
		if t.type != type_:
			_has_error = true
			return {}
		_pos += 1
		return t

	func _is_at_end() -> bool:
		return _cur_type() == _Tokenizer.T.EOF

	func _parse_row(in_env: bool) -> Dictionary:
		var children: Array = []
		while not _is_at_end():
			var t: Dictionary = _cur()
			match t.type:
				_Tokenizer.T.RBRACE:
					break
				_Tokenizer.T.EOF:
					break
				_Tokenizer.T.AMP:
					if in_env:
						break
					_advance()
				_Tokenizer.T.DNEWLINE:
					if in_env:
						break
					_advance()
				_:
					if t.type == _Tokenizer.T.CMD and t.value == "end":
						break
					var node: Dictionary = _parse_element(in_env)
					if node.is_empty():
						break
					children.append(node)
		return {type = "row", children = children}

	func _parse_element(in_env: bool) -> Dictionary:
		var atom: Dictionary = _parse_atom(in_env)
		if atom.is_empty():
			return {}
		if _cur_type() == _Tokenizer.T.CARET or _cur_type() == _Tokenizer.T.UNDERSCORE:
			return _parse_script(atom)
		return atom

	func _parse_atom(in_env: bool) -> Dictionary:
		var t: Dictionary = _cur()
		match t.type:
			_Tokenizer.T.LBRACE:
				return _parse_group()
			_Tokenizer.T.CMD:
				return _parse_command()
			_Tokenizer.T.CHAR:
				_advance()
				return {type = "atom", text = t.value, style = "normal"}
			_Tokenizer.T.CARET:
				_advance()
				return {type = "atom", text = "^", style = "normal"}
			_Tokenizer.T.UNDERSCORE:
				_advance()
				return {type = "atom", text = "_", style = "normal"}
			_Tokenizer.T.LBRACKET:
				_advance()
				return {type = "atom", text = "[", style = "normal"}
			_Tokenizer.T.RBRACKET:
				_advance()
				return {type = "atom", text = "]", style = "normal"}
			_:
				_has_error = true
				return {}

	func _parse_group() -> Dictionary:
		_expect(_Tokenizer.T.LBRACE)
		if _has_error:
			return {}
		var row: Dictionary = _parse_row(false)
		_expect(_Tokenizer.T.RBRACE)
		if _has_error:
			return {}
		return row

	func _parse_arg() -> Dictionary:
		var t: Dictionary = _cur()
		if t.type == _Tokenizer.T.LBRACE:
			return _parse_group()
		elif t.type == _Tokenizer.T.CMD:
			return _parse_command()
		elif t.type == _Tokenizer.T.CHAR:
			_advance()
			return {type = "atom", text = t.value, style = "normal"}
		elif t.type == _Tokenizer.T.LBRACKET:
			_advance()
			return {type = "atom", text = "[", style = "normal"}
		else:
			return {type = "row", children = []}

	func _parse_script(base: Dictionary) -> Dictionary:
		var sup: Dictionary = {}
		var sub: Dictionary = {}
		var has_sup: bool = false
		var has_sub: bool = false
		if _cur_type() == _Tokenizer.T.CARET:
			_advance()
			sup = _parse_arg()
			has_sup = true
		if _cur_type() == _Tokenizer.T.UNDERSCORE:
			_advance()
			sub = _parse_arg()
			has_sub = true
		if not has_sup and _cur_type() == _Tokenizer.T.CARET:
			_advance()
			sup = _parse_arg()
			has_sup = true
		return {
			type = "script",
			base = base,
			sup = sup if has_sup else {},
			sub = sub if has_sub else {},
		}

	func _parse_optional_arg() -> Dictionary:
		if _cur_type() == _Tokenizer.T.LBRACKET:
			_advance()
			# 不能用 _parse_row，因为它不会在 ] 处停止
			var children: Array = []
			while not _is_at_end():
				var t: Dictionary = _cur()
				if t.type == _Tokenizer.T.RBRACKET:
					_advance()
					break
				if t.type == _Tokenizer.T.EOF:
					break
				var node: Dictionary = _parse_element(false)
				if node.is_empty():
					break
				children.append(node)
			return {type = "row", children = children}
		return {}

	func _parse_command() -> Dictionary:
		var t: Dictionary = _advance()
		var cmd: String = t.value
		if cmd.is_empty():
			return {type = "atom", text = "", style = "normal"}

		if cmd == "frac" or cmd == "dfrac" or cmd == "tfrac":
			var num: Dictionary = _parse_arg()
			var den: Dictionary = _parse_arg()
			return {type = "fraction", num = num, den = den, style = cmd}

		if cmd == "binom" or cmd == "dbinom" or cmd == "tbinom":
			var n1: Dictionary = _parse_arg()
			var n2: Dictionary = _parse_arg()
			return {type = "binom", num1 = n1, num2 = n2}

		if cmd == "sqrt":
			var idx: Dictionary = _parse_optional_arg()
			var rad: Dictionary = _parse_arg()
			return {type = "root", radicand = rad, index = idx}

		if BIG_OPS.has(cmd):
			var op_char: String = BIG_OPS[cmd]
			var limits: bool = false
			if _cur_type() == _Tokenizer.T.CMD:
				var next_cmd: String = _cur_val()
				if next_cmd == "limits":
					_advance()
					limits = true
				elif next_cmd == "nolimits":
					_advance()
					limits = false
			var sup: Dictionary = {}
			var sub: Dictionary = {}
			if _cur_type() == _Tokenizer.T.CARET:
				_advance()
				sup = _parse_arg()
			if _cur_type() == _Tokenizer.T.UNDERSCORE:
				_advance()
				sub = _parse_arg()
			if not sup.is_empty() or not sub.is_empty():
				return {type = "bigop", op = op_char, sup = sup, sub = sub, limits = limits}
			return {type = "atom", text = op_char, style = "normal"}

		if cmd == "lim":
			var sub: Dictionary = {}
			if _cur_type() == _Tokenizer.T.UNDERSCORE:
				_advance()
				sub = _parse_arg()
			return {type = "bigop", op = "lim", sup = {}, sub = sub, limits = true, is_text = true}

		if cmd == "int":
			var sup2: Dictionary = {}
			var sub2: Dictionary = {}
			if _cur_type() == _Tokenizer.T.CARET:
				_advance()
				sup2 = _parse_arg()
			if _cur_type() == _Tokenizer.T.UNDERSCORE:
				_advance()
				sub2 = _parse_arg()
			if not sup2.is_empty() or not sub2.is_empty():
				return {type = "bigop", op = "\u222B", sup = sup2, sub = sub2, limits = false}
			return {type = "atom", text = "\u222B", style = "normal"}

		if cmd == "oint":
			var sup3: Dictionary = {}
			var sub3: Dictionary = {}
			if _cur_type() == _Tokenizer.T.CARET:
				_advance()
				sup3 = _parse_arg()
			if _cur_type() == _Tokenizer.T.UNDERSCORE:
				_advance()
				sub3 = _parse_arg()
			if not sup3.is_empty() or not sub3.is_empty():
				return {type = "bigop", op = "\u222E", sup = sup3, sub = sub3, limits = false}
			return {type = "atom", text = "\u222E", style = "normal"}

		if cmd == "left":
			return _parse_delimited()

		if cmd == "begin":
			return _parse_environment()

		if DECORATION_COMMANDS.has(cmd):
			var deco: String = DECORATION_COMMANDS[cmd]
			var content: Dictionary = _parse_arg()
			return {type = "overunder", content = content, decoration = deco}

		if cmd == "mathbf" or cmd == "boldsymbol":
			return {type = "font", content = _parse_arg(), style = "bold"}
		if cmd == "mathit":
			return {type = "font", content = _parse_arg(), style = "italic"}
		if cmd == "mathrm" or cmd == "text" or cmd == "textrm" or cmd == "textnormal":
			return {type = "font", content = _parse_arg(), style = "normal"}
		if cmd == "mathbfit" or cmd == "textbf":
			return {type = "font", content = _parse_arg(), style = "bold_italic"}
		if cmd == "mathbb" or cmd == "mathfrak":
			return {type = "font", content = _parse_arg(), style = "bold"}
		if cmd == "mathcal" or cmd == "mathscr":
			return {type = "font", content = _parse_arg(), style = "italic"}

		if SPACING_COMMANDS.has(cmd):
			return {type = "space", width_em = SPACING_COMMANDS[cmd]}

		if cmd == "color":
			var color_arg: Dictionary = _parse_arg()
			var color_str: String = _extract_text(color_arg)
			var rest: Dictionary = _parse_row(false)
			return {type = "color", content = rest, color_hex = _resolve_color(color_str)}
		if cmd == "textcolor":
			var ca: Dictionary = _parse_arg()
			var cs: String = _extract_text(ca)
			var ct: Dictionary = _parse_arg()
			return {type = "color", content = ct, color_hex = _resolve_color(cs)}

		if FUNCTION_NAMES.has(cmd):
			if _cur_type() == _Tokenizer.T.CARET or _cur_type() == _Tokenizer.T.UNDERSCORE:
				return _parse_script({type = "func", text = cmd})
			return {type = "func", text = cmd}

		if GREEK_LOWER.has(cmd):
			return _maybe_script({type = "atom", text = GREEK_LOWER[cmd], style = "normal"})
		if GREEK_UPPER.has(cmd):
			return _maybe_script({type = "atom", text = GREEK_UPPER[cmd], style = "normal"})
		if MATH_SYMBOLS.has(cmd):
			return _maybe_script({type = "atom", text = MATH_SYMBOLS[cmd], style = "normal"})
		if ARROWS.has(cmd):
			return _maybe_script({type = "atom", text = ARROWS[cmd], style = "normal"})

		if cmd == "to":
			return _maybe_script({type = "atom", text = "\u2192", style = "normal"})

		if cmd == "limits" or cmd == "nolimits" or cmd == "displaystyle" or cmd == "textstyle" or cmd == "scriptstyle":
			return {type = "row", children = []}

		return {type = "atom", text = "\\" + cmd, style = "normal"}

	func _maybe_script(atom: Dictionary) -> Dictionary:
		if _cur_type() == _Tokenizer.T.CARET or _cur_type() == _Tokenizer.T.UNDERSCORE:
			return _parse_script(atom)
		return atom

	func _parse_delimited() -> Dictionary:
		var left_delim: String = _read_delimiter()
		var content: Dictionary = _parse_row_until_right()
		if _cur_type() == _Tokenizer.T.CMD and _cur_val() == "right":
			_advance()
		var right_delim: String = _read_delimiter()
		return {
			type = "delimited",
			content = content,
			left_delim = left_delim,
			right_delim = right_delim,
		}

	func _read_delimiter() -> String:
		var t: Dictionary = _cur()
		match t.type:
			_Tokenizer.T.CHAR:
				_advance()
				return t.value
			_Tokenizer.T.CMD:
				_advance()
				match t.value:
					"vert": return "|"
					"Vert": return "\u2016"
					"langle": return "\u27E8"
					"rangle": return "\u27E9"
					"lceil": return "\u2308"
					"rceil": return "\u2309"
					"lfloor": return "\u230A"
					"rfloor": return "\u230B"
					"backslash": return "\\"
					"uparrow": return "\u2191"
					"downarrow": return "\u2193"
					"Updownarrow": return "\u2195"
					_: return t.value
			_Tokenizer.T.LBRACKET:
				_advance()
				return "["
			_Tokenizer.T.RBRACKET:
				_advance()
				return "]"
			_:
				_advance()
				return "."

	func _parse_row_until_right() -> Dictionary:
		var children: Array = []
		while not _is_at_end():
			var t: Dictionary = _cur()
			if t.type == _Tokenizer.T.CMD and t.value == "right":
				break
			if t.type == _Tokenizer.T.RBRACE:
				break
			if t.type == _Tokenizer.T.EOF:
				break
			var node: Dictionary = _parse_element(false)
			if node.is_empty():
				break
			children.append(node)
		return {type = "row", children = children}

	func _parse_environment() -> Dictionary:
		var env_name: String = ""
		if _cur_type() == _Tokenizer.T.LBRACE:
			_advance()
			while _cur_type() == _Tokenizer.T.CHAR:
				env_name += _cur_val()
				_advance()
			if _cur_type() == _Tokenizer.T.RBRACE:
				_advance()
		var align_spec: String = ""
		if _cur_type() == _Tokenizer.T.LBRACKET:
			_advance()
			while _cur_type() == _Tokenizer.T.CHAR:
				align_spec += _cur_val()
				_advance()
			if _cur_type() == _Tokenizer.T.RBRACKET:
				_advance()

		var rows: Array = []
		var current_row: Array = []
		while not _is_at_end():
			var t: Dictionary = _cur()
			if t.type == _Tokenizer.T.CMD and t.value == "end":
				break
			if t.type == _Tokenizer.T.EOF:
				break
			if t.type == _Tokenizer.T.DNEWLINE:
				_advance()
				rows.append(current_row)
				current_row = []
				continue
			if t.type == _Tokenizer.T.AMP:
				_advance()
				continue
			var cell: Dictionary = _parse_cell()
			current_row.append(cell)

		if not current_row.is_empty():
			rows.append(current_row)

		if _cur_type() == _Tokenizer.T.CMD and _cur_val() == "end":
			_advance()
			if _cur_type() == _Tokenizer.T.LBRACE:
				_advance()
				while _cur_type() == _Tokenizer.T.CHAR:
					_advance()
				if _cur_type() == _Tokenizer.T.RBRACE:
					_advance()

		match env_name:
			"matrix", "smallmatrix":
				return {type = "matrix", rows = rows, delim = "none"}
			"pmatrix":
				return {type = "matrix", rows = rows, delim = "paren"}
			"bmatrix":
				return {type = "matrix", rows = rows, delim = "bracket"}
			"Bmatrix":
				return {type = "matrix", rows = rows, delim = "brace"}
			"vmatrix":
				return {type = "matrix", rows = rows, delim = "bar"}
			"Vmatrix":
				return {type = "matrix", rows = rows, delim = "doublebar"}
			"cases":
				return {type = "cases", rows = rows}
			"aligned", "align", "align*", "split":
				return {type = "aligned", rows = rows, align_spec = align_spec}
			"array":
				return {type = "matrix", rows = rows, delim = "none", align_spec = align_spec}
			_:
				return {type = "matrix", rows = rows, delim = "none"}

	func _parse_cell() -> Dictionary:
		var children: Array = []
		while not _is_at_end():
			var t: Dictionary = _cur()
			if t.type == _Tokenizer.T.AMP:
				break
			if t.type == _Tokenizer.T.DNEWLINE:
				break
			if t.type == _Tokenizer.T.CMD and t.value == "end":
				break
			if t.type == _Tokenizer.T.EOF:
				break
			var node: Dictionary = _parse_element(true)
			if node.is_empty():
				break
			children.append(node)
		return {type = "row", children = children}

	func _extract_text(node: Dictionary) -> String:
		if node.is_empty():
			return ""
		match node.get("type", ""):
			"atom":
				return node.get("text", "")
			"row":
				var s: String = ""
				for child in node.get("children", []):
					s += _extract_text(child)
				return s
			_:
				return ""

	func _resolve_color(color_str: String) -> String:
		color_str = color_str.strip_edges()
		if COLOR_NAMES.has(color_str):
			return COLOR_NAMES[color_str]
		if not color_str.begins_with("#"):
			return "#" + color_str
		return color_str

# ══════════════════════════════════════════
#  Layout (布局引擎)
# ══════════════════════════════════════════

class _Layout:
	var _fonts: Dictionary = {}

	func _init(fonts: Dictionary) -> void:
		_fonts = fonts

	func layout_node(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		if node.is_empty():
			return _empty_box()
		match node.get("type", ""):
			"row":
				return _layout_row(node, fs, style, color)
			"atom":
				return _layout_atom(node, fs, style, color)
			"script":
				return _layout_script(node, fs, style, color)
			"fraction":
				return _layout_fraction(node, fs, style, color)
			"binom":
				return _layout_binom(node, fs, style, color)
			"root":
				return _layout_root(node, fs, style, color)
			"bigop":
				return _layout_bigop(node, fs, style, color)
			"delimited":
				return _layout_delimited(node, fs, style, color)
			"matrix":
				return _layout_matrix(node, fs, style, color)
			"cases":
				return _layout_cases(node, fs, style, color)
			"aligned":
				return _layout_aligned(node, fs, style, color)
			"overunder":
				return _layout_overunder(node, fs, style, color)
			"space":
				return _layout_space(node, fs, style, color)
			"color":
				return _layout_color(node, fs, style, color)
			"font":
				return _layout_font(node, fs, style, color)
			"func":
				return _layout_func(node, fs, style, color)
			_:
				return _empty_box()

	func _empty_box() -> Dictionary:
		return {width = 0.0, height = 0.0, baseline = 0.0, commands = []}

	func _get_font(style: String) -> Font:
		if _fonts.has(style):
			return _fonts[style] as Font
		if _fonts.has("normal"):
			return _fonts["normal"] as Font
		return ThemeDB.fallback_font

	func _char_box(text: String, fs: int, style: String, color: Color) -> Dictionary:
		if text.is_empty():
			return _empty_box()
		var font: Font = _get_font(style)
		var ascent: float = font.get_ascent(fs)
		var descent: float = font.get_descent(fs)
		var w: float = 0.0
		for i in range(text.length()):
			w += font.get_char_size(text.unicode_at(i), fs).x
		var h: float = ascent + descent
		var cmds: Array = [{
			type = "char", x = 0.0, y = ascent,
			char = text, size = fs, style = style, color = color,
		}]
		return {width = w, height = h, baseline = ascent, commands = cmds}

	func _offset_cmds(cmds: Array, dx: float, dy: float) -> Array:
		var result: Array = []
		for cmd in cmds:
			var nc: Dictionary = cmd.duplicate(true)
			match cmd.get("type", ""):
				"char":
					nc.x = cmd.x + dx
					nc.y = cmd.y + dy
				"line":
					nc.x1 = cmd.x1 + dx
					nc.y1 = cmd.y1 + dy
					nc.x2 = cmd.x2 + dx
					nc.y2 = cmd.y2 + dy
				"rect":
					nc.x = cmd.x + dx
					nc.y = cmd.y + dy
				"circle":
					nc.cx = cmd.cx + dx
					nc.cy = cmd.cy + dy
			result.append(nc)
		return result

	func _merge_boxes_horizontal(boxes: Array) -> Dictionary:
		if boxes.is_empty():
			return _empty_box()
		var total_w: float = 0.0
		var max_ascent: float = 0.0
		var max_descent: float = 0.0
		for b in boxes:
			total_w += b.width
			var asc: float = b.baseline
			var desc: float = b.height - b.baseline
			if asc > max_ascent:
				max_ascent = asc
			if desc > max_descent:
				max_descent = desc
		var total_h: float = max_ascent + max_descent
		var all_cmds: Array = []
		var x: float = 0.0
		for b in boxes:
			var dy: float = max_ascent - b.baseline
			if dy != 0.0 or x != 0.0:
				all_cmds.append_array(_offset_cmds(b.commands, x, dy))
			else:
				all_cmds.append_array(b.commands)
			x += b.width
		return {width = total_w, height = total_h, baseline = max_ascent, commands = all_cmds}

	func _layout_row(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var children: Array = node.get("children", [])
		if children.is_empty():
			return _empty_box()
		var boxes: Array = []
		for child in children:
			var b: Dictionary = layout_node(child, fs, style, color)
			if not b.is_empty():
				boxes.append(b)
		return _merge_boxes_horizontal(boxes)

	func _layout_atom(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		return _char_box(node.get("text", ""), fs, style, color)

	func _layout_func(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var text: String = node.get("text", "")
		var b: Dictionary = _char_box(text, fs, "normal", color)
		var font: Font = _get_font("normal")
		b.width += font.get_char_size(32, fs).x * 0.3
		return b

	func _layout_script(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var base_box: Dictionary = layout_node(node.get("base", {}), fs, style, color)
		var sub_fs: int = int(float(fs) * SCALE_SCRIPT)
		var has_sup: bool = not node.get("sup", {}).is_empty()
		var has_sub: bool = not node.get("sub", {}).is_empty()
		var sup_box: Dictionary = layout_node(node.get("sup", {}), sub_fs, style, color) if has_sup else _empty_box()
		var sub_box: Dictionary = layout_node(node.get("sub", {}), sub_fs, style, color) if has_sub else _empty_box()

		var bw: float = base_box.width
		var bh: float = base_box.height
		var bb: float = base_box.baseline
		var all_cmds: Array = []
		all_cmds.append_array(base_box.commands)

		var min_y: float = 0.0
		var max_y: float = bh

		if has_sup:
			var sup_ascent: float = sup_box.baseline
			var sup_baseline: float = bb - bb * 0.45
			var sup_top: float = sup_baseline - sup_ascent
			all_cmds.append_array(_offset_cmds(sup_box.commands, bw, sup_top))
			if sup_top < min_y:
				min_y = sup_top
			var sup_bottom: float = sup_top + sup_box.height
			if sup_bottom > max_y:
				max_y = sup_bottom

		if has_sub:
			var sub_ascent: float = sub_box.baseline
			var base_descent: float = bh - bb
			var sub_baseline: float = bb + base_descent * 0.35 + sub_ascent * 0.2
			var sub_top: float = sub_baseline - sub_ascent
			all_cmds.append_array(_offset_cmds(sub_box.commands, bw, sub_top))
			if sub_top < min_y:
				min_y = sub_top
			var sub_bottom: float = sub_top + sub_box.height
			if sub_bottom > max_y:
				max_y = sub_bottom

		if min_y < 0:
			all_cmds = _offset_cmds(all_cmds, 0.0, -min_y)
			max_y -= min_y
			min_y = 0.0

		var total_w: float = bw
		if has_sup and bw + sup_box.width > total_w:
			total_w = bw + sup_box.width
		if has_sub and bw + sub_box.width > total_w:
			total_w = bw + sub_box.width
		var total_h: float = max_y - min_y
		var baseline: float = bb - min_y
		return {width = total_w, height = total_h, baseline = baseline, commands = all_cmds}

	func _layout_fraction(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var frac_fs: int = int(float(fs) * SCALE_FRAC)
		var num_box: Dictionary = layout_node(node.get("num", {}), frac_fs, style, color)
		var den_box: Dictionary = layout_node(node.get("den", {}), frac_fs, style, color)
		var nw: float = num_box.width
		var dw: float = den_box.width
		var nh: float = num_box.height
		var dh: float = den_box.height
		var total_w: float = max(nw, dw) + FRAC_PADDING * 2
		var line_y: float = nh + FRAC_LINE_GAP_TOP
		var total_h: float = nh + FRAC_LINE_GAP_TOP + FRAC_LINE_THICKNESS + FRAC_LINE_GAP_BOT + dh
		var baseline: float = line_y
		var all_cmds: Array = []
		all_cmds.append_array(_offset_cmds(num_box.commands, (total_w - nw) * 0.5, 0.0))
		all_cmds.append({
			type = "rect", x = FRAC_PADDING, y = line_y,
			w = total_w - FRAC_PADDING * 2, h = FRAC_LINE_THICKNESS,
			color = color, filled = true,
		})
		var den_y: float = line_y + FRAC_LINE_THICKNESS + FRAC_LINE_GAP_BOT
		all_cmds.append_array(_offset_cmds(den_box.commands, (total_w - dw) * 0.5, den_y))
		return {width = total_w, height = total_h, baseline = baseline, commands = all_cmds}

	func _layout_binom(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var frac_fs: int = int(float(fs) * SCALE_FRAC)
		var num_box: Dictionary = layout_node(node.get("num1", {}), frac_fs, style, color)
		var den_box: Dictionary = layout_node(node.get("num2", {}), frac_fs, style, color)
		var nw: float = num_box.width
		var dw: float = den_box.width
		var nh: float = num_box.height
		var dh: float = den_box.height
		var inner_w: float = max(nw, dw) + 4
		var line_gap: float = 2.0
		var total_h: float = nh + line_gap + dh
		var baseline: float = nh + line_gap * 0.5
		var all_cmds: Array = []
		all_cmds.append_array(_offset_cmds(num_box.commands, (inner_w - nw) * 0.5, 0.0))
		all_cmds.append_array(_offset_cmds(den_box.commands, (inner_w - dw) * 0.5, nh + line_gap))
		var left_w: float = _draw_delimiter(all_cmds, "(", 0, 0, total_h, fs, color)
		var right_w: float = _draw_delimiter(all_cmds, ")", inner_w + left_w, 0, total_h, fs, color)
		all_cmds = _offset_cmds(all_cmds, left_w, 0.0)
		return {width = left_w + inner_w + right_w, height = total_h, baseline = baseline, commands = all_cmds}

	func _layout_root(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var rad_box: Dictionary = layout_node(node.get("radicand", {}), fs, style, color)
		var idx_node: Dictionary = node.get("index", {})
		var has_idx: bool = not idx_node.is_empty()
		var idx_fs: int = int(float(fs) * SCALE_ROOT_INDEX)
		var idx_box: Dictionary = layout_node(idx_node, idx_fs, style, color) if has_idx else _empty_box()

		var rad_w: float = rad_box.width
		var rad_h: float = rad_box.height
		var rad_baseline: float = rad_box.baseline
		var rad_descent: float = rad_h - rad_baseline

		# 布局参数
		var line_thickness: float = 1.5
		var line_gap: float = 2.0          # 横线与 radicand 顶部之间的间隙
		var line_y: float = 0.0            # 横线位于画布顶部
		var rad_top: float = line_thickness + line_gap  # radicand 内容的起始 y
		var baseline: float = rad_top + rad_baseline    # 整体 baseline

		# √ 形状自绘参数（根据 radicand 高度自适应）
		var hook_depth: float = max(3.0, rad_descent * 0.5)  # 底部钩子向下延伸量
		var sqrt_bottom_y: float = baseline + hook_depth      # √ 底部 y
		var sqrt_top_y: float = line_y                        # √ 顶部 y（连接横线）
		var sqrt_height: float = sqrt_bottom_y - sqrt_top_y   # √ 总高度
		var sqrt_w: float = max(6.0, sqrt_height * 0.35)      # √ 宽度（约 63 度角）

		var total_h: float = max(rad_top + rad_h, sqrt_bottom_y)

		var idx_w: float = idx_box.width if has_idx else 0.0
		var sqrt_x: float = idx_w + 2 if has_idx else 0.0
		var bar_x: float = sqrt_x + sqrt_w     # 横线起点 = √ 顶部
		var total_w: float = bar_x + rad_w + 2

		var all_cmds: Array = []

		# index（n 次根的 n），放在 √ 左上角，底部约在横线高度
		if has_idx:
			var idx_y: float = max(0.0, line_y + line_thickness - idx_box.height)
			all_cmds.append_array(_offset_cmds(idx_box.commands, 0.0, idx_y))

		# 自绘 √ 形状：两条线组成 V 形
		var v_x: float = sqrt_x + sqrt_w * 0.3   # V 形底点 x
		# 钩子：从左下到 V 底点（短斜线）
		all_cmds.append({
			type = "line",
			x1 = sqrt_x, y1 = sqrt_bottom_y,
			x2 = v_x, y2 = baseline,
			color = color, width = 1.5,
		})
		# 主体：从 V 底点到右上（连接横线）
		all_cmds.append({
			type = "line",
			x1 = v_x, y1 = baseline,
			x2 = bar_x, y2 = sqrt_top_y,
			color = color, width = 1.5,
		})

		# 上方横线（覆盖 radicand 宽度）
		all_cmds.append({
			type = "rect", x = bar_x, y = line_y,
			w = total_w - bar_x, h = line_thickness,
			color = color, filled = true,
		})

		# radicand 内容（放在横线下方）
		all_cmds.append_array(_offset_cmds(rad_box.commands, bar_x, rad_top))

		return {width = total_w, height = total_h, baseline = baseline, commands = all_cmds}

	func _layout_space(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var em: float = float(fs)
		var w: float = node.get("width_em", 0.0) * em
		return {width = w, height = float(fs) * 0.5, baseline = float(fs) * 0.4, commands = []}

	func _layout_color(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var hex: String = node.get("color_hex", "#FFFFFF")
		var c: Color = Color(hex) if hex.begins_with("#") else color
		return layout_node(node.get("content", {}), fs, style, c)

	func _layout_font(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		return layout_node(node.get("content", {}), fs, node.get("style", "normal"), color)

	func _layout_bigop(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var op: String = node.get("op", "")
		var limits: bool = node.get("limits", false)
		var is_text: bool = node.get("is_text", false)
		var op_box: Dictionary = _char_box(op, fs, "normal" if is_text else style, color)
		var sub_fs: int = int(float(fs) * SCALE_SCRIPT)
		var has_sup: bool = not node.get("sup", {}).is_empty()
		var has_sub: bool = not node.get("sub", {}).is_empty()
		var sup_box: Dictionary = layout_node(node.get("sup", {}), sub_fs, style, color) if has_sup else _empty_box()
		var sub_box: Dictionary = layout_node(node.get("sub", {}), sub_fs, style, color) if has_sub else _empty_box()

		if not limits:
			var script_node: Dictionary = {
				type = "script",
				base = {type = "atom", text = op, style = style},
				sup = node.get("sup", {}),
				sub = node.get("sub", {}),
			}
			return _layout_script(script_node, fs, style, color)

		var ow: float = op_box.width
		var oh: float = op_box.height
		var ob: float = op_box.baseline
		var gap: float = 3.0
		var all_cmds: Array = []
		var total_w: float = ow
		var top_y: float = 0.0

		if has_sup:
			var sw: float = sup_box.width
			var sup_x: float = max(0.0, (ow - sw) * 0.5)
			all_cmds.append_array(_offset_cmds(sup_box.commands, sup_x, 0.0))
			top_y = sup_box.height + gap
			if sw > total_w:
				total_w = sw

		var op_x: float = max(0.0, (total_w - ow) * 0.5)
		all_cmds.append_array(_offset_cmds(op_box.commands, op_x, top_y))
		var bottom_y: float = top_y + oh

		if has_sub:
			var dw: float = sub_box.width
			var sub_x: float = max(0.0, (total_w - dw) * 0.5)
			var sub_y: float = bottom_y + gap
			all_cmds.append_array(_offset_cmds(sub_box.commands, sub_x, sub_y))
			bottom_y = sub_y + sub_box.height
			if dw > total_w:
				total_w = dw

		return {width = total_w, height = bottom_y, baseline = top_y + ob, commands = all_cmds}

	func _layout_delimited(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var content_box: Dictionary = layout_node(node.get("content", {}), fs, style, color)
		var left_delim: String = node.get("left_delim", ".")
		var right_delim: String = node.get("right_delim", ".")
		var ch: float = content_box.height
		var cw: float = content_box.width
		var cb: float = content_box.baseline
		var all_cmds: Array = []
		var left_w: float = 0.0
		var right_w: float = 0.0
		if left_delim != "." and not left_delim.is_empty():
			left_w = _draw_delimiter(all_cmds, left_delim, 0, 0, ch, fs, color)
		if right_delim != "." and not right_delim.is_empty():
			right_w = _draw_delimiter(all_cmds, right_delim, left_w + cw, 0, ch, fs, color)
		all_cmds.append_array(_offset_cmds(content_box.commands, left_w, 0.0))
		return {width = left_w + cw + right_w, height = ch, baseline = cb, commands = all_cmds}

	func _layout_matrix(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var rows: Array = node.get("rows", [])
		var delim: String = node.get("delim", "none")
		if rows.is_empty():
			return _empty_box()
		var cell_fs: int = int(float(fs) * SCALE_MATRIX)
		var col_pad: float = 12.0
		var row_pad: float = 4.0
		var laid_rows: Array = []
		var col_count: int = 0
		for row in rows:
			var laid_cells: Array = []
			for cell in row:
				laid_cells.append(layout_node(cell, cell_fs, style, color))
			laid_rows.append(laid_cells)
			if laid_cells.size() > col_count:
				col_count = laid_cells.size()
		var col_widths: Array = []
		for j in range(col_count):
			var max_w: float = 0.0
			for laid_row in laid_rows:
				if j < laid_row.size() and laid_row[j].width > max_w:
					max_w = laid_row[j].width
			col_widths.append(max_w)
		var row_heights: Array = []
		var row_baselines: Array = []
		for laid_row in laid_rows:
			var max_asc: float = 0.0
			var max_desc: float = 0.0
			for b in laid_row:
				if b.baseline > max_asc:
					max_asc = b.baseline
				var desc: float = b.height - b.baseline
				if desc > max_desc:
					max_desc = desc
			row_heights.append(max_asc + max_desc)
			row_baselines.append(max_asc)
		var inner_w: float = 0.0
		for cw in col_widths:
			inner_w += cw
		inner_w += col_pad * float(col_count)
		var inner_h: float = 0.0
		for rh in row_heights:
			inner_h += rh
		inner_h += row_pad * float(rows.size() - 1)
		var all_cmds: Array = []
		for i in range(laid_rows.size()):
			var laid_row: Array = laid_rows[i]
			var rh: float = row_heights[i]
			var rb: float = row_baselines[i]
			var x: float = 0.0
			for j in range(laid_row.size()):
				var b: Dictionary = laid_row[j]
				var cw: float = col_widths[j]
				var cell_dy: float = rb - b.baseline
				var cell_dx: float = x + (cw - b.width) * 0.5
				all_cmds.append_array(_offset_cmds(b.commands, cell_dx, cell_dy))
				x += cw + col_pad
		var left_w: float = 0.0
		var right_w: float = 0.0
		if delim != "none":
			match delim:
				"paren":
					left_w = _draw_delimiter(all_cmds, "(", 0, 0, inner_h, fs, color)
					right_w = _draw_delimiter(all_cmds, ")", left_w + inner_w, 0, inner_h, fs, color)
				"bracket":
					left_w = _draw_delimiter(all_cmds, "[", 0, 0, inner_h, fs, color)
					right_w = _draw_delimiter(all_cmds, "]", left_w + inner_w, 0, inner_h, fs, color)
				"brace":
					left_w = _draw_delimiter(all_cmds, "{", 0, 0, inner_h, fs, color)
					right_w = _draw_delimiter(all_cmds, "}", left_w + inner_w, 0, inner_h, fs, color)
				"bar":
					left_w = _draw_delimiter(all_cmds, "|", 0, 0, inner_h, fs, color)
					right_w = _draw_delimiter(all_cmds, "|", left_w + inner_w, 0, inner_h, fs, color)
				"doublebar":
					left_w = _draw_delimiter(all_cmds, "\u2016", 0, 0, inner_h, fs, color)
					right_w = _draw_delimiter(all_cmds, "\u2016", left_w + inner_w, 0, inner_h, fs, color)
			all_cmds = _offset_cmds(all_cmds, left_w, 0.0)
		var baseline: float = inner_h * 0.5 + (row_baselines[0] if not row_baselines.is_empty() else 0.0) * 0.25
		return {width = left_w + inner_w + right_w, height = inner_h, baseline = baseline, commands = all_cmds}

	func _layout_cases(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var rows: Array = node.get("rows", [])
		if rows.is_empty():
			return _empty_box()
		var cell_fs: int = int(float(fs) * SCALE_MATRIX)
		var col_pad: float = 20.0
		var row_pad: float = 4.0
		var laid_rows: Array = []
		for row in rows:
			var laid_cells: Array = []
			for cell in row:
				laid_cells.append(layout_node(cell, cell_fs, style, color))
			laid_rows.append(laid_cells)
		var col_count: int = 2
		var col_widths: Array = [0.0, 0.0]
		for laid_row in laid_rows:
			for j in range(min(laid_row.size(), col_count)):
				if laid_row[j].width > col_widths[j]:
					col_widths[j] = laid_row[j].width
		var row_heights: Array = []
		var row_baselines: Array = []
		for laid_row in laid_rows:
			var max_asc: float = 0.0
			var max_desc: float = 0.0
			for b in laid_row:
				if b.baseline > max_asc:
					max_asc = b.baseline
				var desc: float = b.height - b.baseline
				if desc > max_desc:
					max_desc = desc
			row_heights.append(max_asc + max_desc)
			row_baselines.append(max_asc)
		var inner_w: float = col_widths[0] + col_pad + col_widths[1]
		var inner_h: float = 0.0
		for rh in row_heights:
			inner_h += rh
		inner_h += row_pad * float(rows.size() - 1)
		var all_cmds: Array = []
		for i in range(laid_rows.size()):
			var laid_row: Array = laid_rows[i]
			var rb: float = row_baselines[i]
			var x: float = 0.0
			for j in range(min(laid_row.size(), col_count)):
				var b: Dictionary = laid_row[j]
				var cw: float = col_widths[j]
				var cell_dy: float = rb - b.baseline
				all_cmds.append_array(_offset_cmds(b.commands, x, cell_dy))
				x += cw + col_pad
		var left_w: float = _draw_delimiter(all_cmds, "{", 0, 0, inner_h, fs, color)
		all_cmds = _offset_cmds(all_cmds, left_w, 0.0)
		return {width = left_w + inner_w, height = inner_h, baseline = inner_h * 0.5, commands = all_cmds}

	func _layout_aligned(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var rows: Array = node.get("rows", [])
		if rows.is_empty():
			return _empty_box()
		var col_pad: float = 16.0
		var row_pad: float = 6.0
		var laid_rows: Array = []
		for row in rows:
			var laid_cells: Array = []
			for cell in row:
				laid_cells.append(layout_node(cell, fs, style, color))
			laid_rows.append(laid_cells)
		var col_count: int = 0
		for laid_row in laid_rows:
			if laid_row.size() > col_count:
				col_count = laid_row.size()
		var col_widths: Array = []
		for j in range(col_count):
			var max_w: float = 0.0
			for laid_row in laid_rows:
				if j < laid_row.size() and laid_row[j].width > max_w:
					max_w = laid_row[j].width
			col_widths.append(max_w)
		var row_heights: Array = []
		var row_baselines: Array = []
		for laid_row in laid_rows:
			var max_asc: float = 0.0
			var max_desc: float = 0.0
			for b in laid_row:
				if b.baseline > max_asc:
					max_asc = b.baseline
				var desc: float = b.height - b.baseline
				if desc > max_desc:
					max_desc = desc
			row_heights.append(max_asc + max_desc)
			row_baselines.append(max_asc)
		var inner_w: float = 0.0
		for cw in col_widths:
			inner_w += cw
		inner_w += col_pad * float(col_count)
		var inner_h: float = 0.0
		for rh in row_heights:
			inner_h += rh
		inner_h += row_pad * float(rows.size() - 1)
		var all_cmds: Array = []
		for i in range(laid_rows.size()):
			var laid_row: Array = laid_rows[i]
			var rb: float = row_baselines[i]
			var x: float = 0.0
			for j in range(laid_row.size()):
				var b: Dictionary = laid_row[j]
				var cw: float = col_widths[j]
				var cell_dy: float = rb - b.baseline
				if j % 2 == 0:
					all_cmds.append_array(_offset_cmds(b.commands, x + cw - b.width, cell_dy))
				else:
					all_cmds.append_array(_offset_cmds(b.commands, x, cell_dy))
				x += cw + col_pad
		var baseline: float = row_baselines[0] if not row_baselines.is_empty() else 0.0
		return {width = inner_w, height = inner_h, baseline = baseline, commands = all_cmds}

	func _layout_overunder(node: Dictionary, fs: int, style: String, color: Color) -> Dictionary:
		var content_box: Dictionary = layout_node(node.get("content", {}), fs, style, color)
		var deco: String = node.get("decoration", "")
		var cw: float = content_box.width
		var ch: float = content_box.height
		var cb: float = content_box.baseline
		var all_cmds: Array = []
		match deco:
			"overline":
				var lh: float = 1.5
				var gap: float = 2.0
				all_cmds.append({type = "rect", x = 0.0, y = 0.0, w = cw, h = lh, color = color, filled = true})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, lh + gap))
				return {width = cw, height = lh + gap + ch, baseline = lh + gap + cb, commands = all_cmds}
			"underline":
				var lh: float = 1.5
				var gap: float = 2.0
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, 0.0))
				all_cmds.append({type = "rect", x = 0.0, y = ch + gap, w = cw, h = lh, color = color, filled = true})
				return {width = cw, height = ch + gap + lh, baseline = cb, commands = all_cmds}
			"bar":
				var lh: float = 1.5
				var gap: float = 2.0
				var bar_w: float = min(cw, cw * 0.8 + 4)
				all_cmds.append({type = "rect", x = (cw - bar_w) * 0.5, y = 0.0, w = bar_w, h = lh, color = color, filled = true})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, lh + gap))
				return {width = cw, height = lh + gap + ch, baseline = lh + gap + cb, commands = all_cmds}
			"hat":
				var deco_h: float = 5.0
				var cx: float = cw * 0.5
				all_cmds.append({type = "line", x1 = cx - 3, y1 = deco_h, x2 = cx, y2 = 0.0, color = color, width = 1.5})
				all_cmds.append({type = "line", x1 = cx, y1 = 0.0, x2 = cx + 3, y2 = deco_h, color = color, width = 1.5})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, deco_h + 1))
				return {width = cw, height = deco_h + 1 + ch, baseline = deco_h + 1 + cb, commands = all_cmds}
			"vec":
				var deco_h: float = 7.0
				all_cmds.append({type = "line", x1 = 0.0, y1 = deco_h * 0.5, x2 = cw, y2 = deco_h * 0.5, color = color, width = 1.5})
				all_cmds.append({type = "line", x1 = cw, y1 = deco_h * 0.5, x2 = cw - 4, y2 = deco_h * 0.5 - 3, color = color, width = 1.5})
				all_cmds.append({type = "line", x1 = cw, y1 = deco_h * 0.5, x2 = cw - 4, y2 = deco_h * 0.5 + 3, color = color, width = 1.5})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, deco_h + 1))
				return {width = cw, height = deco_h + 1 + ch, baseline = deco_h + 1 + cb, commands = all_cmds}
			"vecleft":
				var deco_h: float = 7.0
				all_cmds.append({type = "line", x1 = 0.0, y1 = deco_h * 0.5, x2 = cw, y2 = deco_h * 0.5, color = color, width = 1.5})
				all_cmds.append({type = "line", x1 = 0.0, y1 = deco_h * 0.5, x2 = 4, y2 = deco_h * 0.5 - 3, color = color, width = 1.5})
				all_cmds.append({type = "line", x1 = 0.0, y1 = deco_h * 0.5, x2 = 4, y2 = deco_h * 0.5 + 3, color = color, width = 1.5})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, deco_h + 1))
				return {width = cw, height = deco_h + 1 + ch, baseline = deco_h + 1 + cb, commands = all_cmds}
			"dot":
				var deco_h: float = 4.0
				all_cmds.append({type = "circle", cx = cw * 0.5, cy = deco_h * 0.5, r = 1.5, color = color, filled = true})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, deco_h + 1))
				return {width = cw, height = deco_h + 1 + ch, baseline = deco_h + 1 + cb, commands = all_cmds}
			"ddot":
				var deco_h: float = 4.0
				all_cmds.append({type = "circle", cx = cw * 0.5 - 3, cy = deco_h * 0.5, r = 1.5, color = color, filled = true})
				all_cmds.append({type = "circle", cx = cw * 0.5 + 3, cy = deco_h * 0.5, r = 1.5, color = color, filled = true})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, deco_h + 1))
				return {width = cw, height = deco_h + 1 + ch, baseline = deco_h + 1 + cb, commands = all_cmds}
			"tilde":
				var deco_h: float = 5.0
				var cx2: float = cw * 0.5
				all_cmds.append({type = "line", x1 = 0.0, y1 = deco_h * 0.7, x2 = cx2 - 2, y2 = deco_h * 0.2, color = color, width = 1.5})
				all_cmds.append({type = "line", x1 = cx2 - 2, y1 = deco_h * 0.2, x2 = cx2 + 2, y2 = deco_h * 0.8, color = color, width = 1.5})
				all_cmds.append({type = "line", x1 = cx2 + 2, y1 = deco_h * 0.8, x2 = cw, y2 = deco_h * 0.3, color = color, width = 1.5})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, deco_h + 1))
				return {width = cw, height = deco_h + 1 + ch, baseline = deco_h + 1 + cb, commands = all_cmds}
			"check":
				var deco_h: float = 5.0
				var cx3: float = cw * 0.5
				all_cmds.append({type = "line", x1 = cx3 - 3, y1 = 0.0, x2 = cx3, y2 = deco_h, color = color, width = 1.5})
				all_cmds.append({type = "line", x1 = cx3, y1 = deco_h, x2 = cx3 + 3, y2 = 0.0, color = color, width = 1.5})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, deco_h + 1))
				return {width = cw, height = deco_h + 1 + ch, baseline = deco_h + 1 + cb, commands = all_cmds}
			"breve":
				var deco_h: float = 5.0
				var cx4: float = cw * 0.5
				all_cmds.append({type = "line", x1 = 0.0, y1 = 1.0, x2 = cx4 - 2, y2 = deco_h, color = color, width = 1.5})
				all_cmds.append({type = "line", x1 = cx4 - 2, y1 = deco_h, x2 = cx4 + 2, y2 = deco_h, color = color, width = 1.5})
				all_cmds.append({type = "line", x1 = cx4 + 2, y1 = deco_h, x2 = cw, y2 = 1.0, color = color, width = 1.5})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, deco_h + 1))
				return {width = cw, height = deco_h + 1 + ch, baseline = deco_h + 1 + cb, commands = all_cmds}
			"acute":
				var deco_h: float = 5.0
				var cx5: float = cw * 0.5
				all_cmds.append({type = "line", x1 = cx5 - 2, y1 = deco_h, x2 = cx5 + 2, y2 = 0.0, color = color, width = 1.5})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, deco_h + 1))
				return {width = cw, height = deco_h + 1 + ch, baseline = deco_h + 1 + cb, commands = all_cmds}
			"grave":
				var deco_h: float = 5.0
				var cx6: float = cw * 0.5
				all_cmds.append({type = "line", x1 = cx6 - 2, y1 = 0.0, x2 = cx6 + 2, y2 = deco_h, color = color, width = 1.5})
				all_cmds.append_array(_offset_cmds(content_box.commands, 0.0, deco_h + 1))
				return {width = cw, height = deco_h + 1 + ch, baseline = deco_h + 1 + cb, commands = all_cmds}
			_:
				return content_box

	func _draw_delimiter(cmds: Array, delim: String, x: float, y: float,
			height: float, base_fs: int, color: Color) -> float:
		if delim == "." or delim.is_empty():
			return 0.0
		var font: Font = _get_font("normal")
		var base_char_size: Vector2 = font.get_string_size(delim, HORIZONTAL_ALIGNMENT_LEFT, -1, base_fs)
		var base_h: float = base_char_size.y
		var scale: float = height / base_h if base_h > 0 else 1.0
		scale = clamp(scale, 1.0, 2.5)
		var scaled_fs: int = int(float(base_fs) * scale)

		if scale <= 1.5:
			var sz: Vector2 = font.get_string_size(delim, HORIZONTAL_ALIGNMENT_LEFT, -1, scaled_fs)
			var ascent: float = font.get_ascent(scaled_fs)
			var descent: float = font.get_descent(scaled_fs)
			var total_h: float = ascent + descent
			var dy: float = (height - total_h) * 0.5
			cmds.append({
				type = "char", x = x, y = y + dy + ascent,
				char = delim, size = scaled_fs, style = "normal", color = color,
			})
			return sz.x + 1.0

		match delim:
			"(", ")":
				return _draw_paren_lines(cmds, x, y, height, delim == ")", color)
			"[", "]":
				return _draw_bracket_lines(cmds, x, y, height, delim == "]", color)
			"{", "}":
				return _draw_brace_lines(cmds, x, y, height, delim == "}", color)
			"|":
				cmds.append({type = "line", x1 = x, y1 = y, x2 = x, y2 = y + height, color = color, width = 1.5})
				return 3.0
			"\u2016":
				cmds.append({type = "line", x1 = x, y1 = y, x2 = x, y2 = y + height, color = color, width = 1.5})
				cmds.append({type = "line", x1 = x + 3, y1 = y, x2 = x + 3, y2 = y + height, color = color, width = 1.5})
				return 5.0
			"\u27E8", "\u27E9":
				return _draw_angle_lines(cmds, x, y, height, delim == "\u27E9", color)
			"\u2308", "\u2309", "\u230A", "\u230B":
				return _draw_corner_lines(cmds, x, y, height, delim, color)
			_:
				var sz2: Vector2 = font.get_string_size(delim, HORIZONTAL_ALIGNMENT_LEFT, -1, scaled_fs)
				var ascent2: float = font.get_ascent(scaled_fs)
				var dy2: float = (height - font.get_height(scaled_fs)) * 0.5
				cmds.append({
					type = "char", x = x, y = y + dy2 + ascent2,
					char = delim, size = scaled_fs, style = "normal", color = color,
				})
				return sz2.x + 1.0

	func _draw_paren_lines(cmds: Array, x: float, y: float, h: float,
			is_right: bool, color: Color) -> float:
		var w: float = max(4.0, h * 0.08)
		var segments: int = 16
		var thickness: float = 1.5
		var sign: float = 1.0 if is_right else -1.0
		var base_x: float = x if is_right else x + w
		var prev: Vector2 = Vector2.ZERO
		for i in range(segments + 1):
			var t: float = float(i) / float(segments)
			var py: float = y + t * h
			var px: float = base_x + sign * w * (1.0 - (2.0 * t - 1.0) * (2.0 * t - 1.0))
			if i > 0:
				cmds.append({type = "line", x1 = prev.x, y1 = prev.y, x2 = px, y2 = py, color = color, width = thickness})
			prev = Vector2(px, py)
		return w + 2.0

	func _draw_bracket_lines(cmds: Array, x: float, y: float, h: float,
			is_right: bool, color: Color) -> float:
		var w: float = max(4.0, h * 0.08)
		var thickness: float = 1.5
		var sx: float = x + w if is_right else x
		cmds.append({type = "line", x1 = sx, y1 = y, x2 = sx, y2 = y + h, color = color, width = thickness})
		if is_right:
			cmds.append({type = "line", x1 = x, y1 = y, x2 = x + w, y2 = y, color = color, width = thickness})
			cmds.append({type = "line", x1 = x, y1 = y + h, x2 = x + w, y2 = y + h, color = color, width = thickness})
		else:
			cmds.append({type = "line", x1 = x, y1 = y, x2 = x + w, y2 = y, color = color, width = thickness})
			cmds.append({type = "line", x1 = x, y1 = y + h, x2 = x + w, y2 = y + h, color = color, width = thickness})
		return w + 2.0

	func _draw_brace_lines(cmds: Array, x: float, y: float, h: float,
			is_right: bool, color: Color) -> float:
		var w: float = max(5.0, h * 0.1)
		var thickness: float = 1.5
		var my: float = y + h * 0.5
		var sign: float = 1.0 if is_right else -1.0
		var base_x: float = x + w * 0.5
		var spike: float = w * 0.4
		var segments: int = 8
		var prev_top: Vector2 = Vector2.ZERO
		for i in range(segments + 1):
			var t: float = float(i) / float(segments)
			var py: float = y + t * (h * 0.5 - 2)
			var px: float = base_x - sign * w * 0.5 * (1.0 - (2.0 * t - 1.0) * (2.0 * t - 1.0))
			if i > 0:
				cmds.append({type = "line", x1 = prev_top.x, y1 = prev_top.y, x2 = px, y2 = py, color = color, width = thickness})
			prev_top = Vector2(px, py)
		cmds.append({type = "line", x1 = prev_top.x, y1 = prev_top.y, x2 = base_x - sign * (w * 0.5 + spike), y2 = my, color = color, width = thickness})
		var prev_bot: Vector2 = Vector2(base_x - sign * (w * 0.5 + spike), my)
		for i in range(1, segments + 1):
			var t: float = float(i) / float(segments)
			var py: float = my + 2 + t * (h * 0.5 - 2)
			var px: float = base_x - sign * w * 0.5 * ((2.0 * t - 1.0) * (2.0 * t - 1.0))
			cmds.append({type = "line", x1 = prev_bot.x, y1 = prev_bot.y, x2 = px, y2 = py, color = color, width = thickness})
			prev_bot = Vector2(px, py)
		return w + 4.0

	func _draw_angle_lines(cmds: Array, x: float, y: float, h: float,
			is_right: bool, color: Color) -> float:
		var w: float = max(5.0, h * 0.12)
		var thickness: float = 1.5
		var my: float = y + h * 0.5
		if is_right:
			cmds.append({type = "line", x1 = x, y1 = y, x2 = x + w, y2 = my, color = color, width = thickness})
			cmds.append({type = "line", x1 = x + w, y1 = my, x2 = x, y2 = y + h, color = color, width = thickness})
		else:
			cmds.append({type = "line", x1 = x + w, y1 = y, x2 = x, y2 = my, color = color, width = thickness})
			cmds.append({type = "line", x1 = x, y1 = my, x2 = x + w, y2 = y + h, color = color, width = thickness})
		return w + 2.0

	func _draw_corner_lines(cmds: Array, x: float, y: float, h: float,
			delim: String, color: Color) -> float:
		var w: float = max(4.0, h * 0.08)
		var thickness: float = 1.5
		var is_top: bool = delim == "\u2308" or delim == "\u2309"
		var is_right: bool = delim == "\u2309" or delim == "\u230B"
		var sx: float = x + w if is_right else x
		if is_top:
			cmds.append({type = "line", x1 = sx, y1 = y, x2 = sx, y2 = y + h, color = color, width = thickness})
			cmds.append({type = "line", x1 = x, y1 = y, x2 = x + w, y2 = y, color = color, width = thickness})
		else:
			cmds.append({type = "line", x1 = sx, y1 = y, x2 = sx, y2 = y + h, color = color, width = thickness})
			cmds.append({type = "line", x1 = x, y1 = y + h, x2 = x + w, y2 = y + h, color = color, width = thickness})
		return w + 2.0

# ══════════════════════════════════════════
#  LatexCanvas (SubViewport 绘制控件)
# ══════════════════════════════════════════

class _LatexCanvas extends Control:
	var commands: Array = []
	var fonts: Dictionary = {}
	var offset: Vector2 = Vector2.ZERO

	func _draw() -> void:
		var ci: RID = get_canvas_item()
		for cmd in commands:
			match cmd.get("type", ""):
				"char":
					var font: Font = _get_font(cmd.get("style", "normal"))
					if font:
						var pos: Vector2 = Vector2(cmd.get("x", 0.0), cmd.get("y", 0.0)) + offset
						font.draw_string(ci, pos, cmd.get("char", ""),
							HORIZONTAL_ALIGNMENT_LEFT, -1.0,
							int(cmd.get("size", 16)), cmd.get("color", Color.WHITE))
				"line":
					var p1: Vector2 = Vector2(cmd.get("x1", 0.0), cmd.get("y1", 0.0)) + offset
					var p2: Vector2 = Vector2(cmd.get("x2", 0.0), cmd.get("y2", 0.0)) + offset
					draw_line(p1, p2, cmd.get("color", Color.WHITE), cmd.get("width", 1.0))
				"rect":
					var rx: float = cmd.get("x", 0.0) + offset.x
					var ry: float = cmd.get("y", 0.0) + offset.y
					var rw: float = cmd.get("w", 1.0)
					var rh: float = cmd.get("h", 1.0)
					draw_rect(Rect2(rx, ry, rw, rh), cmd.get("color", Color.WHITE), cmd.get("filled", true))
				"circle":
					var cx: float = cmd.get("cx", 0.0) + offset.x
					var cy: float = cmd.get("cy", 0.0) + offset.y
					var r: float = cmd.get("r", 2.0)
					if cmd.get("filled", true):
						draw_circle(Vector2(cx, cy), r, cmd.get("color", Color.WHITE))
					else:
						draw_arc(Vector2(cx, cy), r, 0.0, TAU, 32, cmd.get("color", Color.WHITE), 1.0)

	func _get_font(style: String) -> Font:
		if fonts.has(style):
			return fonts[style] as Font
		if fonts.has("normal"):
			return fonts["normal"] as Font
		return null
