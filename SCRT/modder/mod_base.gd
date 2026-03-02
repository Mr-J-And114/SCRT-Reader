# ============================================================
# mod_base.gd - 模组基类（增强版）
# 所有模组的主脚本必须继承此类
# ============================================================
class_name ModBase
extends RefCounted

## 模组 ID（由 PackageManager 在加载时设置）
var mod_id: String = ""
## 模组 API 接口（由 PackageManager 在加载时注入）
var api: ModAPI = null
## 模组包内的文件缓存 { "相对路径": PackedByteArray }
var _pack_files: Dictionary = {}

# ══════════════════════════════════════════
#  生命周期虚函数（模组重写这些）
# ══════════════════════════════════════════

## 首次安装时调用（只调用一次）
func _on_install() -> void:
	pass

## 卸载时调用
func _on_uninstall() -> void:
	pass

## 每次启用时调用（登录后恢复、或刚安装后）
func _on_enable() -> void:
	pass

## 禁用时调用（用户注销）
func _on_disable() -> void:
	pass

## 注册命令（在 _on_enable 之前自动调用）
## 通过 api.register_command() 注册
func _register_commands() -> void:
	pass

## 每帧更新（如果模组需要，可重写）
## delta: 帧时间
func _process(_delta: float) -> void:
	pass

# ══════════════════════════════════════════
#  ★ NEW: 事件钩子（模组可重写来拦截/响应系统事件）
# ══════════════════════════════════════════

## 命令执行前钩子（返回 true 阻止命令执行）
## cmd: 命令名, args: 参数数组
func _on_before_command(_cmd: String, _args: Array) -> bool:
	return false

## 命令执行后钩子
func _on_after_command(_cmd: String, _args: Array) -> void:
	pass

## 目录切换时触发
func _on_directory_changed(_old_path: String, _new_path: String) -> void:
	pass

## 文件打开前触发（返回 true 阻止默认打开行为）
func _on_before_file_open(_file_path: String) -> bool:
	return false

## 文件打开后触发
func _on_after_file_open(_file_path: String) -> void:
	pass

## 磁盘加载后触发
func _on_disc_loaded(_story_id: String, _manifest: Dictionary) -> void:
	pass

## 磁盘弹出后触发
func _on_disc_ejected() -> void:
	pass

## 模式切换时触发（桌面 ↔ 磁盘）
func _on_mode_changed(_is_desktop: bool) -> void:
	pass

## 收到跨模组消息时触发
func _on_mod_message(_from_mod_id: String, _data: Dictionary) -> void:
	pass

## 用户登录后触发
func _on_user_login(_username: String) -> void:
	pass

## 用户注销前触发
func _on_user_logout(_username: String) -> void:
	pass
