@tool
class_name HexTile
extends Node2D

# 地形类型枚举。
enum TerrainType { PLAIN, DESERT, MOUNTAIN, START, FINISH }

# 各地形的默认填充色。
const TERRAIN_FILL := {
	TerrainType.PLAIN:    Color(0.34, 0.70, 0.34, 1.0),
	TerrainType.DESERT:   Color(0.82, 0.72, 0.42, 1.0),
	TerrainType.MOUNTAIN: Color(0.52, 0.52, 0.52, 1.0),
	TerrainType.START:    Color(0.20, 0.60, 0.90, 1.0),
	TerrainType.FINISH:   Color(0.95, 0.78, 0.15, 1.0),
}
# 各地形的边框色。
const TERRAIN_BORDER := {
	TerrainType.PLAIN:    Color(0.15, 0.40, 0.15, 1.0),
	TerrainType.DESERT:   Color(0.55, 0.45, 0.20, 1.0),
	TerrainType.MOUNTAIN: Color(0.30, 0.30, 0.30, 1.0),
	TerrainType.START:    Color(0.10, 0.35, 0.60, 1.0),
	TerrainType.FINISH:   Color(0.60, 0.50, 0.05, 1.0),
}
# 各地形显示的文字标签。
const TERRAIN_LABEL := {
	TerrainType.PLAIN:    "",
	TerrainType.DESERT:   "沙漠",
	TerrainType.MOUNTAIN: "山",
	TerrainType.START:    "起点",
	TerrainType.FINISH:   "终点",
}

# 点击当前格子时发出的信号，携带该格子的局部位置。
signal hex_clicked(hex_position: Vector2)

# 六边形半径，同时决定格子几何大小。
@export var hex_size: float = 64.0 : set = _set_hex_size
# 格子的默认填充颜色。
@export var fill_color: Color = Color(0.34, 0.70, 0.34, 1.0) : set = _set_fill_color
# 格子的边框颜色。
@export var border_color: Color = Color(0.15, 0.40, 0.15, 1.0) : set = _set_border_color
# 格子的边框宽度。
@export var border_width: float = 2.0 : set = _set_border_width

# 六边形填充多边形节点。
@onready var _polygon: Polygon2D = $Polygon2D
# 六边形边框节点。
@onready var _border: Line2D = $Border
# 点击检测使用的碰撞多边形节点。
@onready var _collision: CollisionPolygon2D = $Area2D/CollisionPolygon2D
# 地形文字标签节点。
@onready var _terrain_label: Label = $TerrainLabel

# 当前格子的地形类型。
var terrain: int = TerrainType.PLAIN

# 当前是否处于正式路径高亮状态。
var _highlighted: bool = false
# 正式路径高亮时使用的颜色。
var _highlight_color: Color
# 当前是否处于预览路径高亮状态。
var _previewed: bool = false
# 预览路径高亮时使用的颜色。
var _preview_color: Color
# 当前是否被玩家占据。
var _occupied: bool = false
# 玩家占据格时使用的颜色。
var _occupied_color: Color = Color(0.6, 0.35, 0.88, 1.0)
# 当前是否是本次移动的起点格。
var _is_origin: bool = false
# 起点格使用的颜色。
var _origin_color: Color = Color(0.05, 0.18, 0.65, 1.0)


# 设置地形类型：更新颜色、边框和文字标签。
func set_terrain(type: int) -> void:
	terrain      = type
	fill_color   = TERRAIN_FILL.get(type, fill_color)
	border_color = TERRAIN_BORDER.get(type, border_color)
	if is_node_ready():
		_terrain_label.text = TERRAIN_LABEL.get(type, "")
		_update_shape()


# 节点就绪后刷新一次几何和颜色表现。
func _ready() -> void:
	_terrain_label.text = TERRAIN_LABEL.get(terrain, "")
	_update_shape()


# 视觉缩小系数，用于在格子之间产生间隙（1.0 = 无间距，越小间距越大）。
const INNER_SCALE := 0.94

# 根据半径计算六边形六个顶点的局部坐标。
func _get_hex_points(size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(6):
		var angle_rad := deg_to_rad(60.0 * i)
		points.append(Vector2(cos(angle_rad) * size, sin(angle_rad) * size))
	return points


# 同步更新填充、边框和碰撞区域的六边形形状。
func _update_shape() -> void:
	if not is_node_ready():
		return
	# 视觉多边形稍微缩小以产生格子间隙。
	var visual_pts    := _get_hex_points(hex_size * INNER_SCALE)
	# 碰撞区域保持满尺寸，消除点击死区。
	var collision_pts := _get_hex_points(hex_size)

	_polygon.polygon = visual_pts
	_polygon.color   = fill_color

	var border_pts := PackedVector2Array(visual_pts)
	border_pts.append(visual_pts[0])
	_border.points        = border_pts
	_border.default_color = border_color
	_border.width         = border_width

	_collision.polygon = collision_pts


# 处理鼠标点击输入，并向外转发格子点击信号。
func _on_area_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			hex_clicked.emit(position)


# 设置正式移动路径高亮状态，并根据是否终点选择颜色。
func set_highlighted(on: bool, is_target: bool = false) -> void:
	_highlighted = on
	if on:
		_highlight_color = Color(0.95, 0.45, 0.1, 0.9) if is_target \
			else Color(0.85, 0.78, 0.2, 0.85)
	_apply_color()


# 设置预览路径高亮状态，并根据是否终点选择颜色。
func set_preview_highlighted(on: bool, is_target: bool = false) -> void:
	_previewed = on
	if on:
		_preview_color = Color(0.15, 0.45, 0.95, 0.9) if is_target \
			else Color(0.2, 0.78, 0.92, 0.75)
	_apply_color()


# 设置当前格子是否被玩家占据。
func set_occupied(on: bool) -> void:
	_occupied = on
	_apply_color()


# 设置当前格子是否为本次移动的起点。
func set_origin(on: bool) -> void:
	_is_origin = on
	_apply_color()


# 按优先级计算格子当前应该显示的基础颜色。
func _base_color() -> Color:
	# 这里用固定优先级解决颜色冲突，避免多个状态同时存在时互相覆盖得不可预期。
	if _highlighted:
		return _highlight_color
	if _is_origin:
		return _origin_color
	if _occupied:
		return _occupied_color
	if _previewed:
		return _preview_color
	return fill_color


# 将当前基础颜色真正应用到填充节点。
func _apply_color() -> void:
	_polygon.color = _base_color()


# 鼠标进入时做一层纯视觉提亮，不改变真实状态。
func _on_area_mouse_entered() -> void:
	_polygon.color = _base_color().lightened(0.22)


# 鼠标离开时恢复到由状态决定的真实颜色。
func _on_area_mouse_exited() -> void:
	_apply_color()


# 设置六边形大小并同步刷新形状。
func _set_hex_size(v: float) -> void:
	hex_size = v
	_update_shape()


# 设置默认填充颜色并同步刷新表现。
func _set_fill_color(v: Color) -> void:
	fill_color = v
	_update_shape()


# 设置边框颜色并同步刷新表现。
func _set_border_color(v: Color) -> void:
	border_color = v
	_update_shape()


# 设置边框宽度并同步刷新表现。
func _set_border_width(v: float) -> void:
	border_width = v
	_update_shape()
