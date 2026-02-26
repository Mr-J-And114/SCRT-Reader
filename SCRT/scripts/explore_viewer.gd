# ============================================================
# explore_viewer.gd
# 探索进度查看器 — 右侧弹出面板，显示文件树形式的探索进度
#
# 功能：
#   - 纵向文件树展示已探索的目录和已阅读的文件
#   - 文件夹级/文件级两种展示粒度（Tab 切换）
#   - 已读文件标记 ✓，未读已知文件无标记
#   - 锁定目录显示 [LOCKED]
#   - 百分比统计（已读/总计）
#
# 调用方式：
#   explore_viewer.open()          打开面板
#   explore_viewer.close()         关闭面板
#   explore_viewer.toggle()        切换
# ============================================================
class_name ExploreViewer
extends RefCounted

var main: Control = null
var fs: FileSystem = null
var T: Variant = null

# ── UI ──
var panel: Panel = null
var content_rtl: RichTextLabel = null
var nav_label: RichTextLabel = null

var is_active: bool = false

# ── 展示模式 ──
enum ViewLevel { FOLDER, FILE }
var _view_level: ViewLevel = ViewLevel.FILE

# ── 连接标志 ──
var _size_connected: bool = false

# ── 树形字符 ──
const TREE_PIPE: String   = "|   "
const TREE_TEE: String    = "|-- "
const TREE_ELBOW: String  = "`-- "
const TREE_BLANK: String  = "    "

# ============================================================
func setup(p_main: Control, p_fs: FileSystem, p_theme: Variant) -> void:
	main = p_main
	fs = p_fs
	T = p_theme

# ============================================================
# UI 构建
# ============================================================
func _ensure_panel() -> void:
	if panel != null and is_instance_valid(panel):
		return

	panel = Panel.new()
	panel.name = "ExploreViewerPanel"
	panel.visible = false

	# 半透明深色背景
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.04, 0.02, 0.92)
	style.border_color = Color(0.2, 0.6, 0.2, 0.5)
	style.set_border_width_all(1)
	panel.add_theme_stylebox_override("panel", style)

	var root_control: Control = main
	root_control.add_child(panel)

	# 内部布局
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 2)
	margin.add_child(vbox)

	# 主内容
	content_rtl = RichTextLabel.new()
	content_rtl.bbcode_enabled = true
	content_rtl.fit_content = false
	content_rtl.scroll_active = true
	content_rtl.scroll_following = false
	content_rtl.selection_enabled = true
	content_rtl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_rtl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_rtl.mouse_filter = Control.MOUSE_FILTER_STOP
	CrtmlParser.apply_fonts(content_rtl)
	if T:
		content_rtl.add_theme_color_override("default_color", T.secondary)
	vbox.add_child(content_rtl)

	# 底部导航
	nav_label = RichTextLabel.new()
	nav_label.bbcode_enabled = true
	nav_label.fit_content = true
	nav_label.scroll_active = false
	nav_label.selection_enabled = false
	nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	CrtmlParser.apply_fonts(nav_label)
	if T:
		nav_label.add_theme_color_override("default_color", T.muted)
	vbox.add_child(nav_label)

	_align_panel()

	var tree: SceneTree = main.get_tree()
	if tree and tree.root and not _size_connected:
		_size_connected = true
		tree.root.size_changed.connect(_align_panel)

## 面板定位：右半屏（占输出区域右侧 40%）
func _align_panel() -> void:
	if panel == null or not is_instance_valid(panel):
		return
	var output_area: ScrollContainer = main.scroll_container
	if output_area == null:
		return
	var rect: Rect2 = output_area.get_global_rect()
	var panel_width: float = rect.size.x * 0.42
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(rect.position.x + rect.size.x - panel_width, rect.position.y)
	panel.size = Vector2(panel_width, rect.size.y)

# ============================================================
# 打开 / 关闭 / 切换
# ============================================================
func open() -> void:
	_ensure_panel()
	_align_panel()

	# 置顶（CRT 之前）
	var root: Control = main as Control
	root.move_child(panel, root.get_child_count() - 1)
	var crt: Node = root.get_node_or_null("CRTEffect")
	if crt:
		root.move_child(crt, root.get_child_count() - 1)

	is_active = true
	panel.visible = true
	_render()

func close() -> void:
	if not is_active:
		return
	is_active = false
	if panel and is_instance_valid(panel):
		panel.visible = false

func toggle() -> void:
	if is_active:
		close()
	else:
		open()

## 桌面模式下为指定磁盘打开（需要临时加载该磁盘的存档）
func open_for_story(story_index: int) -> void:
	if main.disc_mgr == null:
		return
	var stories: Array = main.disc_mgr.available_stories
	if story_index < 0 or story_index >= stories.size():
		return

	_ensure_panel()
	_align_panel()

	var root: Control = main as Control
	root.move_child(panel, root.get_child_count() - 1)
	var crt: Node = root.get_node_or_null("CRTEffect")
	if crt:
		root.move_child(crt, root.get_child_count() - 1)

	is_active = true
	panel.visible = true

	# 渲染该磁盘的进度信息（使用存档数据）
	_render_story_progress(story_index)

# ============================================================
# 输入
# ============================================================
func handle_input(event: InputEvent) -> bool:
	if not is_active:
		return false
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE, KEY_Q:
				close()
				return true
			KEY_TAB:
				# 切换展示级别
				_view_level = ViewLevel.FOLDER if _view_level == ViewLevel.FILE else ViewLevel.FILE
				_render()
				return true
			KEY_UP:
				_scroll(-60)
				return true
			KEY_DOWN:
				_scroll(60)
				return true
			KEY_PAGEUP:
				_scroll(-300)
				return true
			KEY_PAGEDOWN:
				_scroll(300)
				return true
	if event is InputEventMouseButton and event.pressed:
		# 检查点击是否在面板区域内
		if not _is_in_panel(event.position):
			close()
			return true
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_scroll(-60)
				return true
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll(60)
				return true
	return false

func _is_in_panel(pos: Vector2) -> bool:
	if panel == null:
		return false
	return panel.get_global_rect().has_point(pos)

func _scroll(amount: int) -> void:
	if content_rtl == null:
		return
	var v: VScrollBar = content_rtl.get_v_scroll_bar()
	if v:
		v.value += amount

# ============================================================
# 渲染文件树
# ============================================================
func _render() -> void:
	if content_rtl == null:
		return
	content_rtl.text = ""

	var p: String = T.primary_hex if T else "#A0FFA0"
	var m: String = T.muted_hex if T else "#888888"
	var w: String = T.warning_hex if T else "#FFFF80"
	var e: String = T.error_hex if T else "#FF6666"
	var s: String = T.success_hex if T else "#66FF66"

	# 统计
	var stats: Dictionary = {"total_files": 0, "read_files": 0, "total_folders": 0, "visited_folders": 0}

	# 标题
	var mode_label: String = "FILE" if _view_level == ViewLevel.FILE else "FOLDER"
	content_rtl.append_text("[color=" + p + "][b]EXPLORATION PROGRESS[/b][/color]\n")
	content_rtl.append_text("[color=" + m + "]Mode: " + mode_label + "  [Tab to switch][/color]\n")
	content_rtl.append_text("[color=" + p + "]" + "-".repeat(36) + "[/color]\n\n")

	# 渲染根目录
	content_rtl.append_text("[color=" + p + "]/[/color]\n")
	_render_children("/", "", stats)

	# 统计信息
	content_rtl.append_text("\n[color=" + p + "]" + "-".repeat(36) + "[/color]\n")

	var file_pct: int = 0
	if stats["total_files"] > 0:
		file_pct = int(float(stats["read_files"]) / float(stats["total_files"]) * 100)

	content_rtl.append_text("[color=" + m + "]Files:   [/color][color=" + s + "]" + str(stats["read_files"]) + "[/color][color=" + m + "] / " + str(stats["total_files"]) + "  (" + str(file_pct) + "%)[/color]\n")

	if _view_level == ViewLevel.FILE:
		var folder_pct: int = 0
		if stats["total_folders"] > 0:
			folder_pct = int(float(stats["visited_folders"]) / float(stats["total_folders"]) * 100)
		content_rtl.append_text("[color=" + m + "]Folders: [/color][color=" + s + "]" + str(stats["visited_folders"]) + "[/color][color=" + m + "] / " + str(stats["total_folders"]) + "  (" + str(folder_pct) + "%)[/color]\n")

	# 进度条
	var bar_width: int = 30
	var filled: int = int(float(file_pct) / 100.0 * float(bar_width))
	var bar: String = "#".repeat(filled) + "-".repeat(bar_width - filled)
	content_rtl.append_text("[color=" + p + "][" + bar + "][/color]\n")

	_render_nav()

func _render_children(dir_path: String, prefix: String, stats: Dictionary) -> void:
	var children: Array[String] = _get_visible_children(dir_path)
	if children.is_empty():
		return

	var p: String = T.primary_hex if T else "#A0FFA0"
	var m: String = T.muted_hex if T else "#888888"
	var w: String = T.warning_hex if T else "#FFFF80"
	var e: String = T.error_hex if T else "#FF6666"
	var s: String = T.success_hex if T else "#66FF66"

	for i in range(children.size()):
		var child_name: String = children[i]
		var child_path: String = fs.join_path(dir_path, child_name)
		var child_node = fs.get_node_at_path(child_path)
		if child_node == null:
			continue

		var is_last: bool = (i == children.size() - 1)
		var connector: String = TREE_ELBOW if is_last else TREE_TEE
		var child_prefix: String = prefix + (TREE_BLANK if is_last else TREE_PIPE)

		var node_type: String = ""
		if child_node is Dictionary:
			node_type = str(child_node.get("type", ""))
		elif "type" in child_node:
			node_type = str(child_node.type)

		if node_type == "folder":
			stats["total_folders"] = stats["total_folders"] + 1

			var has_access: bool = fs.has_clearance(child_path)
			var is_visited: bool = _is_folder_visited(child_path)

			if is_visited:
				stats["visited_folders"] = stats["visited_folders"] + 1

			if not has_access:
				# 锁定目录
				content_rtl.append_text("[color=" + m + "]" + prefix + connector + "[/color]")
				content_rtl.append_text("[color=" + e + "]" + child_name + "/  [LOCKED][/color]\n")
			elif is_visited:
				# 已访问目录
				content_rtl.append_text("[color=" + m + "]" + prefix + connector + "[/color]")
				content_rtl.append_text("[color=" + p + "]" + child_name + "/[/color]\n")
				# 递归渲染子目录
				_render_children(child_path, child_prefix, stats)
			else:
				# 未访问目录（已知存在但未进入）
				content_rtl.append_text("[color=" + m + "]" + prefix + connector + "[/color]")
				content_rtl.append_text("[color=" + m + "]" + child_name + "/[/color]\n")

		elif _view_level == ViewLevel.FILE:
			# 文件
			stats["total_files"] = stats["total_files"] + 1
			var is_read: bool = main.read_files.has(child_path)
			if is_read:
				stats["read_files"] = stats["read_files"] + 1

			var has_access: bool = fs.has_clearance(child_path)

			content_rtl.append_text("[color=" + m + "]" + prefix + connector + "[/color]")

			if not has_access:
				content_rtl.append_text("[color=" + e + "]" + child_name + "  [LOCKED][/color]\n")
			elif is_read:
				content_rtl.append_text("[color=" + s + "]" + child_name + "  [READ][/color]\n")
			else:
				content_rtl.append_text("[color=" + m + "]" + child_name + "[/color]\n")
		else:
			# FOLDER 模式下也要统计文件数
			stats["total_files"] = stats["total_files"] + 1
			if main.read_files.has(child_path):
				stats["read_files"] = stats["read_files"] + 1

# ============================================================
# 辅助
# ============================================================

## 获取可见子节点（过滤隐藏和配置文件），文件夹排前面
func _get_visible_children(dir_path: String) -> Array[String]:
	var raw: Array[String] = fs.get_children_at_path(dir_path)
	var folders: Array[String] = []
	var files: Array[String] = []

	for name in raw:
		var child_path: String = fs.join_path(dir_path, name)
		if fs.is_hidden_path(child_path):
			continue
		if name in [".meta.cfg", "_headers.cfg", "signals.cfg"]:
			continue
		var node = fs.get_node_at_path(child_path)
		if node == null:
			continue
		var ntype: String = ""
		if node is Dictionary:
			ntype = str(node.get("type", ""))
		elif "type" in node:
			ntype = str(node.type)
		if ntype == "folder":
			folders.append(name)
		else:
			files.append(name)

	# 文件夹优先
	var result: Array[String] = []
	result.append_array(folders)
	result.append_array(files)
	return result

## 判断目录是否已访问（曾 cd 进入或在其中打开过文件）
func _is_folder_visited(dir_path: String) -> bool:
	# 检查 visited_paths
	if "visited_paths" in main:
		var vp = main.visited_paths
		if vp is Array and vp.has(dir_path):
			return true
	# 兼容：如果有任何已读文件在该目录下，也视为已访问
	for rf in main.read_files:
		if rf.begins_with(dir_path.rstrip("/") + "/"):
			return true
	# 当前目录或其父目录链
	if main.current_path == dir_path or main.current_path.begins_with(dir_path.rstrip("/") + "/"):
		return true
	return false

func _render_nav() -> void:
	if nav_label == null:
		return
	nav_label.text = ""
	var m: String = T.muted_hex if T != null else "#888888"
	nav_label.append_text("[color=" + m + "]Tab=switch  Up/Dn=scroll  Q/Esc=close[/color]")

## 渲染指定磁盘的探索进度（桌面模式）
func _render_story_progress(story_index: int) -> void:
	if content_rtl == null:
		return
	content_rtl.text = ""

	var p: String = T.primary_hex if T else "#A0FFA0"
	var m: String = T.muted_hex if T else "#888888"
	var w: String = T.warning_hex if T else "#FFFF80"
	var s: String = T.success_hex if T else "#66FF66"

	var stories: Array = main.disc_mgr.available_stories
	var info: Dictionary = stories[story_index]
	var title: String = str(info.get("title", "未知"))
	var story_id: String = str(info.get("id", ""))

	content_rtl.append_text("[color=" + p + "][b]EXPLORATION PROGRESS[/b][/color]\n")
	content_rtl.append_text("[color=" + m + "]Disc: " + title + "[/color]\n")
	content_rtl.append_text("[color=" + p + "]" + "-".repeat(36) + "[/color]\n\n")

	# 尝试从存档读取该磁盘的进度
	var save_data: Dictionary = {}
	if main.save_mgr and main.save_mgr.has_method("load_story_progress"):
		save_data = main.save_mgr.load_story_progress(story_id)
	elif main.disc_mgr and main.disc_mgr.has_method("get_story_save_data"):
		save_data = main.disc_mgr.get_story_save_data(story_index)

	var read_count: int = 0
	var read_list: Array = save_data.get("read_files", []) as Array
	read_count = read_list.size()

	var visited_list: Array = save_data.get("visited_paths", []) as Array

	if read_count == 0 and visited_list.is_empty():
		content_rtl.append_text("[color=" + m + "]  (尚未探索此磁盘)[/color]\n")
	else:
		content_rtl.append_text("[color=" + m + "]  已读文件: [/color][color=" + s + "]" + str(read_count) + "[/color]\n")
		content_rtl.append_text("[color=" + m + "]  已访问目录: [/color][color=" + s + "]" + str(visited_list.size()) + "[/color]\n")
		if not read_list.is_empty():
			content_rtl.append_text("\n[color=" + m + "]  已读文件列表:[/color]\n")
			for rf in read_list:
				content_rtl.append_text("  [color=" + s + "]  [READ] " + str(rf) + "[/color]\n")
		if not visited_list.is_empty():
			content_rtl.append_text("\n[color=" + m + "]  已访问目录:[/color]\n")
			for vp in visited_list:
				content_rtl.append_text("  [color=" + p + "]  " + str(vp) + "/[/color]\n")

	content_rtl.append_text("\n[color=" + p + "]" + "-".repeat(36) + "[/color]\n")
	_render_nav()

func get_active_page_rtl() -> RichTextLabel:
	if is_active and content_rtl != null and is_instance_valid(content_rtl):
		return content_rtl
	return null
