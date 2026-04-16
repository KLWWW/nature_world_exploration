extends Node2D

# 单步移动结束时发出的信号。
signal move_finished
# 路径中的某一步完成时发出的信号，携带该步索引。
signal step_finished(step_index: int)
# 整条路径全部走完时发出的信号。
signal path_finished

# 玩家圆形本体半径。
@export var radius: float = 12.0
# 玩家主体填充颜色。
@export var color: Color = Color(0.9, 0.15, 0.15, 1.0)
# 玩家描边颜色。
@export var outline_color: Color = Color(0.5, 0.0, 0.0, 1.0)
# 玩家描边宽度。
@export var outline_width: float = 2.0
# 每一步移动的动画时长。
@export var move_duration: float = 0.18

# 玩家当前是否正在执行路径移动。
var _is_moving := false


# 绘制玩家圆形外观。
func _draw() -> void:
	draw_circle(Vector2.ZERO, radius + outline_width, outline_color)
	draw_circle(Vector2.ZERO, radius, color)


# 执行单步移动到目标世界坐标，并在动画结束后发出信号。
func move_to(target: Vector2) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", target, move_duration) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_CUBIC)
	tween.finished.connect(func(): move_finished.emit(), CONNECT_ONE_SHOT)


# 按顺序执行一组世界坐标路径。
func move_along(points: Array[Vector2]) -> void:
	if _is_moving:
		return
	_run_path(points)


# 实际执行路径移动，并在每一步及整条路径结束时发出对应信号。
func _run_path(points: Array[Vector2]) -> void:
	_is_moving = true

	# 路径移动本质上还是一连串单步 tween，只是由 Player 自己串起来执行。
	for i in range(points.size()):
		move_to(points[i])
		await move_finished
		step_finished.emit(i)

	# 全部走完后再统一发收尾信号，方便上层做最后状态同步。
	_is_moving = false
	path_finished.emit()
