extends Node2D

signal move_finished   ## 每步移动完成时发出

@export var radius: float = 12.0
@export var color: Color = Color(0.9, 0.15, 0.15, 1.0)
@export var outline_color: Color = Color(0.5, 0.0, 0.0, 1.0)
@export var outline_width: float = 2.0
@export var move_duration: float = 0.18   # 每步移动时长（秒）


func _draw() -> void:
	draw_circle(Vector2.ZERO, radius + outline_width, outline_color)
	draw_circle(Vector2.ZERO, radius, color)


## 平滑移动到目标位置，到达后发出 move_finished
func move_to(target: Vector2) -> void:
	var tween := create_tween()
	tween.tween_property(self, "position", target, move_duration) \
		.set_ease(Tween.EASE_OUT) \
		.set_trans(Tween.TRANS_CUBIC)
	tween.finished.connect(func(): move_finished.emit(), CONNECT_ONE_SHOT)