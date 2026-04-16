@tool
extends Node2D

## 点击格子时发出信号，携带该格子的局部坐标
signal hex_clicked(hex_position: Vector2)

@export var hex_size: float = 64.0 : set = _set_hex_size
@export var fill_color: Color = Color(0.34, 0.70, 0.34, 1.0) : set = _set_fill_color
@export var border_color: Color = Color(0.15, 0.40, 0.15, 1.0) : set = _set_border_color
@export var border_width: float = 2.0 : set = _set_border_width

@onready var _polygon:   Polygon2D        = $Polygon2D
@onready var _border:    Line2D           = $Border
@onready var _collision: CollisionPolygon2D = $Area2D/CollisionPolygon2D


func _ready() -> void:
	_update_shape()


func _get_hex_points(size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle_rad := deg_to_rad(60.0 * i)
		points.append(Vector2(cos(angle_rad) * size, sin(angle_rad) * size))
	return points


func _update_shape() -> void:
	if not is_node_ready():
		return
	var pts := _get_hex_points(hex_size)

	_polygon.polygon = pts
	_polygon.color   = fill_color

	var border_pts := PackedVector2Array(pts)
	border_pts.append(pts[0])
	_border.points        = border_pts
	_border.default_color = border_color
	_border.width         = border_width

	_collision.polygon = pts


# -------- 鼠标输入 --------
func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			hex_clicked.emit(position)   # 发出局部坐标


# -------- 移动路径高亮（黄 / 橙）--------
var _highlighted:     bool  = false
var _highlight_color: Color

func set_highlighted(on: bool, is_target: bool = false) -> void:
	_highlighted = on
	if on:
		_highlight_color = Color(0.95, 0.45, 0.1, 0.9) if is_target \
						   else Color(0.85, 0.78, 0.2, 0.85)
	_apply_color()


# -------- 预览路径高亮（青 / 蓝）--------
var _previewed:       bool  = false
var _preview_color:   Color

func set_preview_highlighted(on: bool, is_target: bool = false) -> void:
	_previewed = on
	if on:
		_preview_color = Color(0.15, 0.45, 0.95, 0.9) if is_target \
						 else Color(0.2, 0.78, 0.92, 0.75)
	_apply_color()


# -------- 计算当前应显示的底色 --------
func _base_color() -> Color:
	if _highlighted: return _highlight_color   # 移动路径优先
	if _previewed:   return _preview_color     # 其次预览
	return fill_color


func _apply_color() -> void:
	_polygon.color = _base_color()


# -------- 悬停高亮（仅视觉，预览由 main.gd 的 _process 驱动）--------
func _on_area_mouse_entered() -> void:
	_polygon.color = _base_color().lightened(0.22)

func _on_area_mouse_exited() -> void:
	_apply_color()


# -------- Setters --------
func _set_hex_size(v: float)     -> void: hex_size     = v; _update_shape()
func _set_fill_color(v: Color)   -> void: fill_color   = v; _update_shape()
func _set_border_color(v: Color) -> void: border_color = v; _update_shape()
func _set_border_width(v: float) -> void: border_width = v; _update_shape()