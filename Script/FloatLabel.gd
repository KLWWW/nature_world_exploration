## 浮动提示文字节点。
## 在指定世界坐标生成后自动向上飘动、淡出，动画结束后自销毁。
## 使用方法：
##   var lbl = FloatLabel.spawn(get_tree().root, "获得：狗头金", player.position)
extends Node2D

## 浮动总时长（秒）。
const DURATION   := 1.6
## 向上漂移距离（像素）。
const RISE       := 52.0
## 文字颜色（白色，带描边）。
const TEXT_COLOR := Color(1.0, 1.0, 1.0, 1.0)
## 描边颜色。
const SHADOW_COLOR := Color(0.0, 0.0, 0.0, 0.85)
## 字号。
const FONT_SIZE  := 30

var _text: String = ""
var _alpha: float  = 1.0
var _elapsed: float = 0.0
var _offset: Vector2 = Vector2.ZERO


## 静态工厂方法：在 parent 下生成一个浮动标签，起始位置为 world_pos（世界坐标）。
static func spawn(parent: Node, text: String, world_pos: Vector2) -> void:
	var lbl: Node2D = load("res://Script/FloatLabel.gd").new()
	lbl.set("_text", text)
	lbl.position = world_pos + Vector2(0, -20)
	lbl.z_index  = 10
	parent.add_child(lbl)


func _process(delta: float) -> void:
	_elapsed += delta
	var t := clampf(_elapsed / DURATION, 0.0, 1.0)

	# 向上漂移（缓出）。
	_offset.y = -RISE * (1.0 - pow(1.0 - t, 2.0))

	# 前半段不透明，后半段线性淡出。
	_alpha = clampf(1.0 - (t - 0.4) / 0.6, 0.0, 1.0) if t > 0.4 else 1.0

	queue_redraw()

	if _elapsed >= DURATION:
		queue_free()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var text_size := font.get_string_size(_text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE)
	var draw_pos  := _offset + Vector2(-text_size.x * 0.5, 0.0)

	# 描边（偏移 1px）
	var shadow := SHADOW_COLOR
	shadow.a  *= _alpha
	draw_string(font, draw_pos + Vector2(1, 1), _text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, shadow)
	draw_string(font, draw_pos + Vector2(-1, 1), _text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, shadow)

	# 主文字
	var col := TEXT_COLOR
	col.a   *= _alpha
	draw_string(font, draw_pos, _text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
