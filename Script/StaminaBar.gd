extends MarginContainer

# 资源名称，可在编辑器中配置（如"体力"、"泡泡"）。
@export var resource_name: String = "体力"
# 进度条默认颜色（正常状态）。
@export var bar_color: Color = Color(1.0, 1.0, 1.0)

# 进度条节点。
@onready var _bar: ProgressBar = $VBoxContainer/ProgressBar
# 数值文字节点。
@onready var _label: Label = $VBoxContainer/Label


func _ready() -> void:
	_bar.modulate = bar_color


# 更新资源显示。
func update_value(current: int, max_val: int) -> void:
	_bar.max_value = max_val
	_bar.value     = current
	_label.text    = "%s: %d / %d" % [resource_name, current, max_val]

	# 低于 25% 时变红色警示，低于 50% 变黄。
	if current <= max_val * 0.25:
		_bar.modulate = Color(1.0, 0.3, 0.3)
	elif current <= max_val * 0.5:
		_bar.modulate = Color(1.0, 0.8, 0.3)
	else:
		_bar.modulate = bar_color