# user_manager.gd
# 职责：用户注册、登录、会话管理
class_name UserManager
extends RefCounted

var T = null  # ThemeManager

# 用户状态
var is_logged_in: bool = false
var current_user: String = ""
var user_session: Dictionary = {}

const USERS_FILE := "user://users.cfg"

## 初始化
func setup(p_theme) -> void:
	T = p_theme

func get_display_name() -> String:
	if is_logged_in:
		return current_user
	return "未登录"

func get_whoami_text() -> String:
	if is_logged_in:
		return "[color=" + str(T.primary_hex) + "]当前用户: " + current_user + "[/color]"
	return "[color=" + str(T.primary_hex) + "]未登录用户[/color]\n[color=" + str(T.muted_hex) + "](用户系统将在后续版本中实现)[/color]"

## 注册新用户
func register(_username: String, _password: String) -> Dictionary:
	# TODO: 阶段二实现
	return { "success": false, "message": "用户系统尚未实现" }

## 用户登录
func login(_username: String, _password: String) -> Dictionary:
	# TODO: 阶段二实现
	return { "success": false, "message": "用户系统尚未实现" }

## 登出
func logout() -> void:
	is_logged_in = false
	current_user = ""
	user_session.clear()

## 获取用户数据
func get_user_data() -> Dictionary:
	return {
		"is_logged_in": is_logged_in,
		"username": current_user,
		"session": user_session
	}
