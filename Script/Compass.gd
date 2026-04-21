## 罗盘 UI 节点脚本。
## 始终在屏幕右下角显示，指针指向金字塔（终点）的方向。
## 准确度随距离变化：越远误差越大（最大 ±90°），越近越精准。
## 误差角与 seed+moveStep 绑定，每步重新采样并平滑过渡，
## 保证"这几步里一直偏同一个方向"，不会每帧乱跳。
extends Control

# 罗盘整体半径（像素）。
const RADIUS := 60.0
# 指针长度。
const NEEDLE_LENGTH := 44.0
# 指针宽度（底部半宽）。
const NEEDLE_WIDTH := 8.0

# 距离多少格时误差达到最大值（应略大于地图最大半径）。
const MAX_ERROR_STEPS := 30
# 进入此格子步数以内，误差强制归零。
const ACCURATE_STEPS := 3
# a 的偏移角范围（弧度），对应 0°~45°。
const MIN_OFFSET_A := 0.0
const MAX_OFFSET_A := PI * 0.25
# b 的最大摆动幅度（弧度），对应 ±30°。
const MAX_SWING_B := PI * 0.167
# 摆动频率（弧度/秒），控制来回晃动的快慢。
const SWING_SPEED := 2.2

# 当前显示的指针角度（弧度）。
var _display_angle: float = 0.0
# 当前准确度（0.0~1.0），用于文字显示。
var _accuracy: float = 1.0
# a 的初始偏移角（弧度，带正负），游戏开始时由 seed 随机，之后不变。
var _offset_a_base: float = 0.0
# 真实指向角度（每帧更新）。
var _true_angle: float = 0.0
# 摆动时间累计，驱动 sin 摆动，始终累加不冻结。
var _swing_time: float = 0.0
# 当前步的摆动幅度，落脚时根据准确度更新，移动中保持不变。
var _current_swing_b: float = 0.0
# 是否正在移动中。
var _is_moving: bool = false

# 游戏种子，由外部在游戏开始时通过 set_seed() 传入。
var seed_val: int = 0


## 由 main.gd 在游戏初始化时传入地图种子，随机确定 a 的偏转方向。
func set_seed(s: int) -> void:
	seed_val = s
	# 用两个不同哈希分别决定：幅度在 [MIN, MAX] 内的位置，以及正负方向。
	var h1 := hash(s ^ 0xDEADBEEF)
	var h2 := hash(s ^ 0xCAFEBABE)
	var magnitude := MIN_OFFSET_A + (float(h1 % 10000) / 10000.0) * (MAX_OFFSET_A - MIN_OFFSET_A)
	var sign_val  := 1.0 if (h2 % 2 == 0) else -1.0
	_offset_a_base = sign_val * magnitude
	# 起手时准确度最低（未走任何步），摆幅初始化为最大值。
	_current_swing_b = MAX_SWING_B


## 由 main.gd 每走完一步后调用，落脚时根据新准确度重新计算摆动幅度。
func on_step(player_cube: Vector3i, pyramid_cube: Vector3i) -> void:
	_update_accuracy(player_cube, pyramid_cube)
	# 落脚后重新确定本步的摆动目标幅度，移动中 sin 继续跑，到站后幅度已更新。
	_current_swing_b = MAX_SWING_B * (1.0 - _accuracy)


## 每帧由 main.gd 调用，传入 cube 坐标、世界坐标和帧时间。
func update_direction(player_cube: Vector3i, pyramid_cube: Vector3i,
		player_world: Vector2, pyramid_world: Vector2, delta: float) -> void:
	# _swing_time 始终累加，无论是否在移动。
	_swing_time += delta
	_update_accuracy(player_cube, pyramid_cube)

	# 计算真实方向角（世界坐标）。
	var dir := pyramid_world - player_world
	if dir.length_squared() > 0.0:
		_true_angle = atan2(dir.x, -dir.y)

	# a：游戏开始时由 seed 随机的带符号角度，随准确度提升线性归零。
	var offset_a := _offset_a_base * (1.0 - _accuracy)

	# b：用落脚时锁定的幅度持续摆动，移动中保持本次摆动，落脚后幅度由 on_step 更新。
	var swing_b := sin(_swing_time * SWING_SPEED) * _current_swing_b

	# 最终显示角 = 真实方向 + a + b。
	_display_angle = _true_angle + offset_a + swing_b

	queue_redraw()


# ── 内部工具 ─────────────────────────────────────────────────

## 用六边形 cube 坐标的切比雪夫距离（格子步数）计算准确度：
## - 步数 ≤ ACCURATE_STEPS → 强制 1.0（完全精准）
## - ACCURATE_STEPS ~ MAX_ERROR_STEPS → sqrt 曲线，中段已有明显准确度
## - 步数 ≥ MAX_ERROR_STEPS → 0.0（最大偏差）
func _update_accuracy(player_cube: Vector3i, pyramid_cube: Vector3i) -> void:
	var diff := pyramid_cube - player_cube
	# cube 坐标六边形距离公式
	var steps := maxi(maxi(absi(diff.x), absi(diff.y)), absi(diff.z))
	if steps <= ACCURATE_STEPS:
		_accuracy = 1.0
		return
	var t := clampf(float(steps - ACCURATE_STEPS) / float(MAX_ERROR_STEPS - ACCURATE_STEPS), 0.0, 1.0)
	_accuracy = 1.0 - sqrt(t)


func _draw() -> void:
	var center := Vector2(RADIUS, RADIUS)

	# ── 外圈背景 ─────────────────────────────────────────────
	draw_circle(center, RADIUS, Color(0.08, 0.06, 0.04, 0.80))
	draw_arc(center, RADIUS, 0, TAU, 48, Color(0.80, 0.65, 0.30, 0.90), 2.0)

	# ── 刻度（四个基本方向） ──────────────────────────────────
	for i in 4:
		var tick_angle := i * PI * 0.5
		var outer := center + Vector2(sin(tick_angle), -cos(tick_angle)) * (RADIUS - 2.0)
		var inner := center + Vector2(sin(tick_angle), -cos(tick_angle)) * (RADIUS - 8.0)
		draw_line(inner, outer, Color(0.80, 0.65, 0.30, 0.70), 1.5)

	# ── 北标小圆点 ───────────────────────────────────────────
	var north_tip := center + Vector2(0, -(RADIUS - 10.0))
	draw_circle(north_tip, 2.5, Color(0.80, 0.65, 0.30, 0.80))

	# ── 指针底部蒙版（以指针方向为中心，向下半圆深色渐变） ──
	var mask_dir := Vector2(sin(_display_angle), -cos(_display_angle))
	for r in range(30, 0, -1):
		var alpha := 0.22 * (1.0 - float(r) / 30.0)
		draw_circle(center + mask_dir * float(r) * 0.6, float(r), Color(0.0, 0.0, 0.0, alpha))

	# ── 指针（红色尖头朝目标，灰色尾部） ─────────────────────
	var tip      := center + Vector2(sin(_display_angle), -cos(_display_angle)) * NEEDLE_LENGTH
	var tail     := center + Vector2(sin(_display_angle), -cos(_display_angle)) * -(NEEDLE_LENGTH * 0.45)
	var perp     := Vector2(cos(_display_angle), sin(_display_angle)) * NEEDLE_WIDTH

	var red_poly  := PackedVector2Array([tip, tail + perp, tail - perp])
	draw_colored_polygon(red_poly, Color(0.90, 0.20, 0.15, 0.95))

	var gray_end  := center + Vector2(sin(_display_angle), -cos(_display_angle)) * -(NEEDLE_LENGTH * 0.45 + 8.0)
	var gray_poly := PackedVector2Array([tail + perp, tail - perp, gray_end])
	draw_colored_polygon(gray_poly, Color(0.55, 0.55, 0.55, 0.90))

	# ── 中心压针小圆 ─────────────────────────────────────────
	draw_circle(center, 4.0, Color(0.80, 0.65, 0.30, 1.0))
	draw_circle(center, 2.0, Color(0.15, 0.10, 0.05, 1.0))

	# ── 准确度文字（罗盘正上方，颜色随精度红→绿渐变） ────────
	var acc_color := Color(1.0 - _accuracy, _accuracy * 0.85, 0.1, 0.95)
	var acc_pct   := int(_accuracy * 100.0)
	var acc_text  := "准确度 %d%%" % acc_pct
	var font      := ThemeDB.fallback_font
	var font_size := 11
	var text_size := font.get_string_size(acc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var text_pos  := Vector2(center.x - text_size.x * 0.5, -4.0)
	# 黑色描边增强可读性。
	draw_string(font, text_pos + Vector2(1, 1), acc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0, 0, 0, 0.7))
	draw_string(font, text_pos, acc_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, acc_color)
