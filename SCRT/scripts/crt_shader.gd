extends ColorRect

func _ready() -> void:
	# 初始化大小为窗口大小
	_update_size()
	# 监听窗口大小变化
	get_tree().root.size_changed.connect(_update_size)


func _update_size() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	position = Vector2.ZERO
	size = viewport_size
