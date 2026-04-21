@tool
class_name HexTile
extends Node2D

const TerrainType = preload("res://Script/TerrainType.gd")
const POIType     = preload("res://Script/POIType.gd")

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
	TerrainType.FINISH:   "金字塔",
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
# POI 图标节点组（动态创建的白底 + 主色圆，渲染在所有子节点之上）。
var _poi_nodes: Array = []

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
# 当前是否处于技能范围预览高亮状态。
var _terraform_ranged: bool = false
# 技能范围预览使用的颜色。
var _terraform_range_color: Color = Color(0.2, 0.95, 0.45, 0.80)

# 当前格子上的 POI 类型（POIType.NONE 表示无 POI）。
var _poi_type: int = POIType.NONE
# POI 图标的圆形半径（相对于 hex_size）。
const POI_ICON_RADIUS_RATIO := 0.22
# POI 图标名称标签的字体大小。
const POI_ICON_FONT_SIZE := 16

# ── 战争迷雾 ─────────────────────────────────────────────────
## 迷雾状态枚举值（直接用整数常量，避免引入额外枚举文件）。
const FOG_HIDDEN   := 0   # 未探索：完全黑色遮罩
const FOG_EXPLORED := 1   # 已探索：半透明暗色遮罩
const FOG_VISIBLE  := 2   # 可见：无遮罩

# 当前迷雾状态（默认全黑遮罩）。
var _fog_state: int = FOG_HIDDEN
# 迷雾遮罩 Polygon2D 节点（动态创建，z_index 最高）。
var _fog_overlay: Polygon2D = null


# 设置地形类型：更新颜色、边框和文字标签。
func set_terrain(type: int) -> void:
	terrain      = type
	fill_color   = TERRAIN_FILL.get(type, fill_color)
	border_color = TERRAIN_BORDER.get(type, border_color)
	if is_node_ready():
		_terrain_label.text = TERRAIN_LABEL.get(type, "")
		_update_shape()


# 节点就绪后刷新一次几何和颜色表现，并补绘尚未创建的 POI 图标。
func _ready() -> void:
	_terrain_label.text = TERRAIN_LABEL.get(terrain, "")
	_update_shape()
	# 如果 set_poi 在 _ready 之前被调用过，此处补绘图标。
	if _poi_type != POIType.NONE:
		var t := _poi_type
		_poi_type = POIType.NONE  # 重置，让 set_poi 重新执行
		set_poi(t)


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


# 设置技能范围预览高亮（绿色轮廓提示改造范围）。
func set_terraform_ranged(on: bool) -> void:
	_terraform_ranged = on
	if on:
		_border.default_color = _terraform_range_color
		_border.width = 5.0
	else:
		_border.default_color = border_color
		_border.width = border_width
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
	if _terraform_ranged:
		return fill_color.lerp(_terraform_range_color, 0.25)
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


# ── POI 图标渲染 ─────────────────────────────────────────────

## 设置该格的 POI 类型，在格子中央显示对应的彩色圆形图标。
## 传入 POIType.NONE 则清除图标。
## 使用动态子节点 Polygon2D 而非 _draw()，确保渲染层级高于 $Polygon2D。
func set_poi(type: int) -> void:
	_poi_type = type

	# 移除旧图标节点（白底 + 主色圆都清除）。
	for n in _poi_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_poi_nodes.clear()

	# NONE / START 不绘制（起点地形色已足够区分）。
	if type == POIType.NONE or type == POIType.START:
		return

	var icon_color: Color = POIType.ICON_COLOR.get(type, Color(1, 1, 1, 1))
	var radius: float = hex_size * POI_ICON_RADIUS_RATIO

	# ── FINISH（金字塔）：用三角形图标代替圆形 ──
	if type == POIType.FINISH:
		var pyramid_size: float = radius * 1.6
		# 白底三角（稍大一圈）
		var bg := Polygon2D.new()
		bg.polygon = _make_triangle_polygon(pyramid_size + 3.0)
		bg.color   = Color(1, 1, 1, 0.85)
		bg.z_index = 11
		add_child(bg)
		_poi_nodes.append(bg)
		# 金色主三角
		var icon := Polygon2D.new()
		icon.polygon = _make_triangle_polygon(pyramid_size)
		icon.color   = icon_color
		icon.z_index = 12
		add_child(icon)
		_poi_nodes.append(icon)
		# 名称标签
		var lbl := _make_poi_label(type, pyramid_size + 3.0)
		lbl.z_index = 13
		add_child(lbl)
		_poi_nodes.append(lbl)
		return

	# ── 普通 POI：圆形图标 ──
	# 外圈白底（提升对比度）
	var bg := Polygon2D.new()
	bg.polygon = _make_circle_polygon(radius + 3.0, 24)
	bg.color   = Color(1, 1, 1, 0.85)
	bg.z_index = 11
	add_child(bg)
	_poi_nodes.append(bg)

	# 主色填充圆
	var icon := Polygon2D.new()
	icon.polygon = _make_circle_polygon(radius, 24)
	icon.color   = icon_color
	icon.z_index = 12
	add_child(icon)
	_poi_nodes.append(icon)

	# 名称标签（显示在图标下方）
	var label := _make_poi_label(type, radius + 3.0)
	label.z_index = 13
	add_child(label)
	_poi_nodes.append(label)


## 生成以原点为中心、给定半径的近似圆形多边形顶点（用于 Polygon2D）。
func _make_circle_polygon(radius: float, segments: int) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in segments:
		var a := TAU * i / segments
		pts.append(Vector2(cos(a) * radius, sin(a) * radius))
	return pts


## 生成以原点为中心、正立等边三角形的顶点（金字塔图标用）。
## size 为从中心到顶点的距离。
func _make_triangle_polygon(size: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	# 顶点朝上：三个角分别在 -90°、+30°、+150°
	for i in 3:
		var a := deg_to_rad(-90.0 + 120.0 * i)
		pts.append(Vector2(cos(a) * size, sin(a) * size))
	return pts


## 创建 POI 名称标签节点，显示在图标正下方。
## icon_bottom 为图标底部到原点的距离，用于定位标签位置。
func _make_poi_label(type: int, icon_bottom: float) -> Label:
	var label := Label.new()
	label.text = POIType.LABEL.get(type, "")
	label.z_index = 3
	label.add_theme_font_size_override("font_size", POI_ICON_FONT_SIZE)
	label.add_theme_color_override("font_color", Color(0.1, 0.1, 0.1, 1.0))
	label.add_theme_color_override("font_shadow_color", Color(1, 1, 1, 0.8))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment   = VERTICAL_ALIGNMENT_TOP
	label.size     = Vector2(hex_size, 24)
	label.position = Vector2(-hex_size * 0.5, icon_bottom)
	return label


# ── 战争迷雾接口 ──────────────────────────────────────────────

## 设置该格子的迷雾状态（FOG_HIDDEN / FOG_EXPLORED / FOG_VISIBLE）。
## 同时控制遮罩透明度和 POI / 地形标签的可见性。
func set_fog_state(state: int) -> void:
	_fog_state = state
	_ensure_fog_overlay()
	match state:
		FOG_HIDDEN:
			_fog_overlay.color = Color(0.0, 0.0, 0.0, 1.0)
			_terrain_label.visible = false
			for n in _poi_nodes:
				if is_instance_valid(n):
					n.visible = false
		FOG_EXPLORED:
			_fog_overlay.color = Color(0.0, 0.0, 0.0, 0.55)
			_terrain_label.visible = true
			for n in _poi_nodes:
				if is_instance_valid(n):
					n.visible = true
		FOG_VISIBLE:
			_fog_overlay.color = Color(0.0, 0.0, 0.0, 0.0)
			_terrain_label.visible = true
			for n in _poi_nodes:
				if is_instance_valid(n):
					n.visible = true


## 返回当前迷雾状态。
func get_fog_state() -> int:
	return _fog_state


## 将 POI 图标灰化，表示已触发失效（图标保留但不可再触发）。
## 将所有图标节点颜色替换为半透明灰，并将文字标签也调暗。
func set_poi_inactive() -> void:
	for n in _poi_nodes:
		if not is_instance_valid(n):
			continue
		if n is Polygon2D:
			n.color = Color(0.45, 0.45, 0.45, 0.7)
		elif n is Label:
			n.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5, 0.8))


## 确保迷雾遮罩节点存在（首次调用时动态创建）。
func _ensure_fog_overlay() -> void:
	if _fog_overlay != null and is_instance_valid(_fog_overlay):
		return
	_fog_overlay = Polygon2D.new()
	_fog_overlay.polygon = _get_hex_points(hex_size)
	_fog_overlay.color   = Color(0.0, 0.0, 0.0, 1.0)
	_fog_overlay.z_index = 10
	add_child(_fog_overlay)
