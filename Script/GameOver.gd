extends Control

@onready var _timer: Timer = $Timer
@onready var _countdown_label: Label = $CenterContainer/VBoxContainer/CountdownLabel
@onready var _score_label: Label = $CenterContainer/VBoxContainer/ScoreLabel

var _time_left := 3


# 显示 Game Over 界面并展示积分，启动倒计时。
func show_game_over(total_score: int = 0) -> void:
	visible = true
	_score_label.text = "战利品总积分：%d" % total_score
	_time_left = 3
	_countdown_label.text = "%d 秒后重新开始..." % _time_left
	_timer.start(1.0)


# 每秒更新倒计时文字，归零时重载场景。
func _on_timer_timeout() -> void:
	_time_left -= 1
	if _time_left <= 0:
		get_tree().reload_current_scene()
	else:
		_countdown_label.text = "%d 秒后重新开始..." % _time_left
		_timer.start(1.0)