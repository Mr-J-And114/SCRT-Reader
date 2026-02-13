# ============================================================
# file_system.gd - 虚拟文件系统模块
# 负责：路径操作、节点查询、权限检查、文件密码、文本框构建
# ============================================================
class_name FileSystem
extends RefCounted

# ============================================================
# 节点数据结构
# ============================================================
class FSNode:
	var type: String
	var content: String
	func _init(p_type: String, p_content: String = "") -> void:
		type = p_type
		content = p_content

# ============================================================
# 数据引用（由 main.gd 设置）
# ============================================================
var file_system: Dictionary = {}
var story_permissions: Dictionary = {}
var story_file_passwords: Dictionary = {}
var player_clearance: int = 0
var unlocked_file_passwords: Array[String] = []

# ============================================================
# 路径工具函数
# ============================================================
func join_path(base: String, child: String) -> String:
	if base == "/":
		return "/" + child
	else:
		return base + "/" + child

func get_parent_path(path: String) -> String:
	if path == "/":
		return "/"
	var clean_path: String = path.rstrip("/")
	var last_slash: int = clean_path.rfind("/")
	if last_slash <= 0:
		return "/"
	return clean_path.substr(0, last_slash)

func normalize_path(path: String) -> String:
	if not path.begins_with("/"):
		path = "/" + path
	var parts := path.split("/", false)
	var resolved: Array[String] = []
	for part in parts:
		if part == "..":
			if resolved.size() > 0:
				resolved.pop_back()
		elif part == ".":
			continue
		else:
			resolved.append(part)
	if resolved.is_empty():
		return "/"
	return "/" + "/".join(resolved)

# ============================================================
# 节点查询
# ============================================================
func get_node_at_path(path: String) -> FSNode:
	path = normalize_path(path)
	if path == "/":
		return FSNode.new("folder")
	if file_system.has(path):
		var entry: Dictionary = file_system[path]
		var content: String = entry.get("content", "")
		# 统一换行符，防止\r\n导致双倍行距
		content = content.replace("\r\n", "\n").replace("\r", "\n")
		return FSNode.new(entry.get("type", "file"), content)
	return null

func get_children_at_path(path: String) -> Array[String]:
	path = normalize_path(path)
	var children: Array[String] = []
	var prefix: String
	if path == "/":
		prefix = "/"
	else:
		prefix = path + "/"
	for key in file_system.keys():
		if key.begins_with(prefix):
			var remainder: String = key.substr(prefix.length())
			if not remainder.contains("/"):
				children.append(remainder)
	children.sort()
	return children

# ============================================================
# 权限检查
# ============================================================
# 检查路径是否需要权限，返回所需等级（0表示无需权限）
func get_required_clearance(path: String) -> int:
	path = normalize_path(path)
	var highest: int = 0
	for perm_path in story_permissions.keys():
		var perm_value: int = int(float(story_permissions[perm_path]))
		var normalized_perm: String = normalize_path(perm_path)
		# 精确匹配
		if path == normalized_perm:
			highest = max(highest, perm_value)
			continue
		# 目录前缀匹配：检查path是否在该目录下
		var dir_prefix: String = normalized_perm + "/"
		if path.begins_with(dir_prefix):
			highest = max(highest, perm_value)
	return highest

# 检查玩家是否有权限访问该路径
func has_clearance(path: String) -> bool:
	return player_clearance >= get_required_clearance(path)

# ============================================================
# 文件密码
# ============================================================
# 检查文件是否需要密码，返回对应的密码表key（空字符串表示不需要）
func get_file_password_key(file_path: String) -> String:
	file_path = normalize_path(file_path)
	# 精确匹配
	for fp_path in story_file_passwords.keys():
		var normalized_fp: String = normalize_path(fp_path)
		if file_path == normalized_fp:
			return fp_path
	return ""

# 检查文件密码是否已解锁
func is_file_password_unlocked(file_path: String) -> bool:
	return unlocked_file_passwords.has(file_path)

# ============================================================
# 显示工具函数
# ============================================================
# 计算字符串的显示宽度（中文=2，英文/符号=1）
func display_width(text: String) -> int:
	var width: int = 0
	for ch in text:
		var code: int = ch.unicode_at(0)
		if code >= 0x4E00 and code <= 0x9FFF:
			width += 2  # CJK统一汉字
		elif code >= 0x3000 and code <= 0x303F:
			width += 2  # CJK标点
		elif code >= 0xFF00 and code <= 0xFFEF:
			width += 2  # 全角字符
		else:
			width += 1
	return width

# 生成自适应宽度的文本框
# lines_data: 每行文本内容（纯文本，不含颜色标签）
# color: 框的颜色代码（如 #33FF33）
# 返回带BBCode的完整框字符串
func build_box(lines_data: Array[String], color: String) -> String:
	# 计算最宽行的显示宽度
	var max_width: int = 0
	for line in lines_data:
		var w: int = display_width(line)
		if w > max_width:
			max_width = w
	# 内部宽度 = 最宽行 + 左右各2个空格padding
	var inner_width: int = max_width + 4
	var border_h: String = "═".repeat(inner_width)
	var result: String = ""
	result += "[color=" + color + "]╔" + border_h + "╗[/color]\n"
	for i in range(lines_data.size()):
		var line: String = lines_data[i]
		var line_width: int = display_width(line)
		var pad_total: int = inner_width - line_width
		@warning_ignore("integer_division")
		var pad_left: int = pad_total / 2
		var pad_right: int = pad_total - pad_left
		result += "[color=" + color + "]║" + " ".repeat(pad_left) + line + " ".repeat(pad_right) + "║[/color]\n"
	result += "[color=" + color + "]╚" + border_h + "╝[/color]"
	return result

# 生成带中间分隔线的自适应方框
# sections: 二维数组，每个元素是一组行文本，组之间用分隔线隔开
func build_box_sectioned(sections: Array, color: String) -> String:
	# 计算所有行中最宽的显示宽度
	var max_width: int = 0
	for section in sections:
		for line in section:
			var w: int = display_width(str(line))
			if w > max_width:
				max_width = w
	var inner_width: int = max_width + 4
	var border_h: String = "═".repeat(inner_width)
	var divider_h: String = "═".repeat(inner_width)
	var result: String = ""
	result += "[color=" + color + "]╔" + border_h + "╗[/color]\n"
	for s_idx in range(sections.size()):
		var section: Array = sections[s_idx]
		for line in section:
			var line_str: String = str(line)
			var line_width: int = display_width(line_str)
			var pad_total: int = inner_width - line_width
			@warning_ignore("integer_division")
			var pad_left: int = pad_total / 2
			var pad_right: int = pad_total - pad_left
			result += "[color=" + color + "]║" + " ".repeat(pad_left) + line_str + " ".repeat(pad_right) + "║[/color]\n"
		# 在 section 之间插入分隔线（最后一组不加）
		if s_idx < sections.size() - 1:
			result += "[color=" + color + "]╠" + divider_h + "╣[/color]\n"
	result += "[color=" + color + "]╚" + border_h + "╝[/color]"
	return result

# ============================================================
# 测试文件系统
# ============================================================
func init_test_file_system() -> void:
	file_system = {
		"/reports": {
			"type": "folder"
		},
		"/personnel": {
			"type": "folder"
		},
		"/comms": {
			"type": "folder"
		},
		"/welcome.txt": {
			"type": "file",
			"content": """欢迎接入SCP基金会安全终端系统。
本系统用于查阅基金会内部文件档案。
您的一切操作都将被记录和监控。
请遵守信息安全协议，不要尝试访问
超出您权限等级的文件。
- 基金会信息安全部门"""
		},
		"/notice.txt": {
			"type": "file",
			"content": """[通知] 2024-01-15
所有站点人员注意：
由于近期发生的安全事故，
所有B区以上的文件访问权限已被临时冻结。
如需紧急访问，请联系您的直属主管。
- Site-19 管理层"""
		},
		"/reports/scp_001.txt": {
			"type": "file",
			"content": """项目编号: SCP-001
项目等级: [DATA EXPUNGED]
特殊收容措施:
████████████████████████████████
████████████████████████████████
[本文件需要O5级权限才能查阅完整内容]
描述:
SCP-001的真实性质属于最高机密。
目前已知的信息表明 ██████████████
████████████████████████████████"""
		},
		"/reports/scp_173.txt": {
			"type": "file",
			"content": """项目编号: SCP-173
项目等级: Euclid
特殊收容措施:
项目SCP-173应被收容在一个锁闭的房间中。
当人员必须进入SCP-173的收容室时，
不得少于3人进入，且门在重新锁闭后，
应始终保持与SCP-173的视觉接触。
描述:
SCP-173是一个混凝土和钢筋结构的雕塑，
上面有Krylon牌喷漆的痕迹。
SCP-173具有生命，且极端敌意。"""
		},
		"/reports/incident_log.txt": {
			"type": "file",
			"content": """事故日志 #2024-0117
日期: 2024年1月17日
地点: Site-19, B区走廊
涉及人员: Dr.████, Agent ████
事故描述:
在例行巡查中，B区走廊的照明系统突然失效。
持续时间约为4.7秒。
在照明恢复后，发现 ████████████████
████████████████████████████████
后续处理:
所有涉及人员已被施行A级记忆删除。
B区已被临时封锁。"""
		},
		"/personnel/dr_bright.txt": {
			"type": "file",
			"content": """人员档案: Dr. Bright
安全等级: 4级
职位: 高级研究员
当前站点: Site-19
备注:
Dr. Bright目前佩戴SCP-963。
有关Dr. Bright不被允许做的事情，
请参阅文件 bright_restrictions.txt
[警告: Dr. Bright的个人请求不应被认真对待]"""
		},
		"/personnel/agent_a.txt": {
			"type": "file",
			"content": """人员档案: Agent A
安全等级: 2级
职位: 外勤特工
当前站点: Site-19
状态: [color=#FF6666]失联[/color]
最后已知位置: Site-19 B区
最后联络时间: 2024-01-17 03:42
备注:
Agent A在事故#2024-0117后失去联络。
搜索行动正在进行中。"""
		},
		"/comms/radio_log.txt": {
			"type": "file",
			"content": """无线电通讯记录
频道: SITE-19-SECURE-7
日期: 2024-01-17
[03:38] 控制室: Alpha小组，报告状态。
[03:38] Agent A: 控制室，Alpha已到达B区入口。一切正常。
[03:39] Agent A: 开始例行巡查。
[03:41] Agent A: 控制室......这里的灯......
[03:41] 控制室: Alpha，请重复。
[03:42] Agent A: ......不对......这里有什么东西在......
[03:42] [信号中断]
[03:42] 控制室: Alpha? Alpha请回复!
[03:45] 控制室: Alpha小组失联。启动应急预案。"""
		}
	}

# ============================================================
# 数据重置
# ============================================================
func clear_all() -> void:
	file_system.clear()
	story_permissions.clear()
	story_file_passwords.clear()
	player_clearance = 0
	unlocked_file_passwords.clear()
