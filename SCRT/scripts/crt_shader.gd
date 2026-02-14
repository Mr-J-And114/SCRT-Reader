extends ColorRect

func _ready() -> void:
	_update_size.call_deferred()
	get_tree().root.size_changed.connect(_update_size)



func _update_size() -> void:
	var viewport_size: Vector2 = get_viewport_rect().size
	set_deferred("position", Vector2.ZERO)
	set_deferred("size", viewport_size)        # ← 用 set_deferred 避免锚点冲突
