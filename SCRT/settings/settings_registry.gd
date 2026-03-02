# ============================================================
# settings_registry.gd - 设置项注册表
# 负责：集中定义所有内置设置项，供 SettingsManager 初始化时调用
# 路径：res://scripts/settings/settings_registry.gd
# ============================================================
class_name SettingsRegistry
extends RefCounted

# ============================================================
# 分类定义
# ============================================================
## 返回所有内置分类定义
## 每个分类: { id, display_name, icon, order }
static func get_categories() -> Array[Dictionary]:
	return [
		{
			"id": "display",
			"display_name": "显示设置",
			"icon": "DIS",
			"order": 10,
		},
		{
			"id": "audio",
			"display_name": "音频设置",
			"icon": "AUD",
			"order": 20,
		},
		{
			"id": "effect",
			"display_name": "效果设置",
			"icon": "EFF",
			"order": 30,
		},
		{
			"id": "terminal",
			"display_name": "终端设置",
			"icon": "TER",
			"order": 40,
		},
	]

# ============================================================
# 设置项定义
# ============================================================
## 返回所有内置设置项定义
## 每个设置项:
##   key            - 全局唯一键 (分类.名称)
##   display_name   - 显示名
##   description    - 描述文本
##   type           - 值类型: bool / int / float / string / enum
##   default        - 默认值
##   min/max/step   - 数值范围约束 (float/int 类型)
##   enum_values    - 枚举可选值 (enum 类型)
##   enum_labels    - 枚举显示标签
##   unit           - 显示单位
##   user_bound     - 是否跟随用户存档 (默认 true)
##   shortcut_cmd   - 旧命令快捷方式提示 (可选)
##   requires_confirm - 是否需要确认才生效 (如主题切换)
static func get_settings() -> Array[Dictionary]:
	return [
		# ── display 分类 ──
		{
			"key": "display.theme",
			"display_name": "主题配色",
			"description": "终端配色方案。切换后需要确认并重新初始化界面。",
			"type": "enum",
			"default": "phosphor_green",
			"enum_values": ["phosphor_green", "amber", "cool_blue", "white"],
			"enum_labels": ["荧光绿", "琥珀", "冷蓝", "纯白"],
			"user_bound": true,
			"shortcut_cmd": "theme",
			"requires_confirm": true,
		},
		{
			"key": "display.cursor_blink_speed",
			"display_name": "光标闪烁速度",
			"description": "输入框光标闪烁间隔(秒)。值越小闪烁越快。",
			"type": "float",
			"default": 0.5,
			"min": 0.1,
			"max": 2.0,
			"step": 0.1,
			"unit": "秒",
			"user_bound": true,
		},

		# ── audio 分类 ──
		{
			"key": "audio.master_volume",
			"display_name": "主音量",
			"description": "控制所有音频的总音量。",
			"type": "float",
			"default": 0.8,
			"min": 0.0,
			"max": 1.0,
			"step": 0.05,
			"unit": "%",
			"user_bound": true,
			"shortcut_cmd": "volume master <0-100>",
		},
		{
			"key": "audio.ambient_volume",
			"display_name": "环境音量",
			"description": "磁盘内环境音/背景音的音量。",
			"type": "float",
			"default": 0.7,
			"min": 0.0,
			"max": 1.0,
			"step": 0.05,
			"unit": "%",
			"user_bound": true,
			"shortcut_cmd": "volume ambient <0-100>",
		},
		{
			"key": "audio.sfx_volume",
			"display_name": "音效音量",
			"description": "系统提示音、操作音效的音量。",
			"type": "float",
			"default": 0.8,
			"min": 0.0,
			"max": 1.0,
			"step": 0.05,
			"unit": "%",
			"user_bound": true,
			"shortcut_cmd": "volume sfx <0-100>",
		},
		{
			"key": "audio.media_volume",
			"display_name": "媒体音量",
			"description": "内联音频/视频播放的音量。",
			"type": "float",
			"default": 0.8,
			"min": 0.0,
			"max": 1.0,
			"step": 0.05,
			"unit": "%",
			"user_bound": true,
			"shortcut_cmd": "volume media <0-100>",
		},
		{
			"key": "audio.sound_enabled",
			"display_name": "操作音效",
			"description": "启用/禁用键盘输入音效和按钮点击音效。",
			"type": "bool",
			"default": true,
			"user_bound": true,
			"shortcut_cmd": "sound on/off",
		},

		# ── effect 分类 ──
		{
			"key": "effect.level",
			"display_name": "效果强度",
			"description": "控制CRT故障、画面抖动等动态效果的强度。full=完整效果，mild=强度降低50%，off=关闭所有动态效果。",
			"type": "enum",
			"default": "full",
			"enum_values": ["full", "mild", "off"],
			"enum_labels": ["完整", "温和(50%)", "关闭"],
			"user_bound": true,
			"shortcut_cmd": "fx_level <full/mild/off>",
		},
		{
			"key": "effect.photosensitive",
			"display_name": "光敏安全模式",
			"description": "开启后禁用强闪烁、jumpscare和高强度故障效果，为光敏感用户提供安全体验。",
			"type": "bool",
			"default": false,
			"user_bound": true,
			"shortcut_cmd": "fx_safe on/off",
		},

		# ── terminal 分类 ──
		{
			"key": "terminal.typing_speed",
			"display_name": "打字速度",
			"description": "打字机效果的基础间隔(秒)。值越小打字越快。设为0则瞬间显示。",
			"type": "float",
			"default": 0.008,
			"min": 0.0,
			"max": 0.1,
			"step": 0.002,
			"unit": "秒/字",
			"user_bound": true,
		},
		{
			"key": "terminal.typing_pause_chance",
			"display_name": "随机停顿概率",
			"description": "打字过程中随机出现短暂停顿的概率，模拟真实打字手感。",
			"type": "float",
			"default": 0.08,
			"min": 0.0,
			"max": 0.5,
			"step": 0.02,
			"unit": "",
			"user_bound": true,
		},
		{
			"key": "terminal.progress_speed",
			"display_name": "进度条速度",
			"description": "进度条动画的速度倍率。值越大进度条越快。",
			"type": "float",
			"default": 1.0,
			"min": 0.1,
			"max": 10.0,
			"step": 0.5,
			"unit": "x",
			"user_bound": true,
		},
	]
