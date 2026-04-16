extends Node

# 用户点击某个格子时发出的意图信号。
signal hex_selected(cube: Vector3i)
# 鼠标悬停格子发生变化时发出的意图信号。
signal hover_changed(cube)

# 由主场景注入的“鼠标位置转 cube 坐标”回调。
var _cube_from_mouse: Callable
# 上一次鼠标所在的 cube，用于避免重复发悬停信号。
var _last_hovered_cube: Variant = null


# 配置输入层使用的坐标转换回调。
func configure(cube_from_mouse: Callable) -> void:
	_cube_from_mouse = cube_from_mouse


# 注册一个格子节点的点击信号，并绑定它对应的 cube 坐标。
func register_hex(hex, cube: Vector3i) -> void:
	hex.hex_clicked.connect(_on_hex_clicked.bind(cube))


# 清空悬停缓存，使下一次鼠标检测强制刷新。
func reset_hover() -> void:
	_last_hovered_cube = null


# 每帧检测鼠标悬停的格子是否变化，并在变化时发出意图信号。
func _process(_delta: float) -> void:
	if _cube_from_mouse.is_null():
		return

	# 只有当鼠标真正跨进了另一个格子时，才向上层发新的悬停意图。
	var hovered_cube: Variant = _cube_from_mouse.call()
	if hovered_cube == _last_hovered_cube:
		return

	_last_hovered_cube = hovered_cube
	hover_changed.emit(hovered_cube)


# 将具体格子的点击事件转成场景能理解的 cube 坐标意图。
func _on_hex_clicked(_hex_position: Vector2, cube: Vector3i) -> void:
	hex_selected.emit(cube)
