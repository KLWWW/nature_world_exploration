extends Node2D

const HEX_SCENE    = preload("res://Hex.tscn")
const PLAYER_SCENE = preload("res://Player.tscn")
const HEX_SIZE  = 64.0
const MAX_TILES = 120

const CUBE_DIRS: Array[Vector3i] = [
	Vector3i( 1, -1,  0),
	Vector3i( 1,  0, -1),
	Vector3i( 0,  1, -1),
	Vector3i(-1,  1,  0),
	Vector3i(-1,  0,  1),
	Vector3i( 0, -1,  1),
]

var _player:      Node2D
var _player_cube: Vector3i = Vector3i(0, 0, 0)
var _is_moving:   bool     = false

## cube坐标 → 世界位置（局部）
var _hex_map:   Dictionary = {}
## cube坐标 → Hex节点（用于高亮）
var _hex_nodes: Dictionary = {}
## 当前高亮中的路径节点列表
var _path_nodes: Array    = []
## 当前预览路径的节点列表
var _preview_nodes: Array = []


func _ready() -> void:
	get_tree().root.size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()

	# 生成六角地图
	var count := 0
	var ring  := 0
	while count < MAX_TILES:
		for cube: Vector3i in _get_ring(ring):
			if count >= MAX_TILES:
				break
			var world_pos := _cube_to_world(cube)
			var hex: Node2D = HEX_SCENE.instantiate()
			hex.position = world_pos
			# 绑定 cube 坐标一起传给回调
			hex.hex_clicked.connect(_on_hex_clicked.bind(cube))
			add_child(hex)
			_hex_map[cube]   = world_pos
			_hex_nodes[cube] = hex
			count += 1
		ring += 1

	# 生成主角，放在中心格
	_player          = PLAYER_SCENE.instantiate()
	_player.position = Vector2.ZERO
	_player.z_index  = 1
	add_child(_player)


# ─────────────────────────────────────────────
#  点击处理
# ─────────────────────────────────────────────
func _on_hex_clicked(_hex_pos: Vector2, target_cube: Vector3i) -> void:
	if _is_moving or target_cube == _player_cube:
		return
	var path := _find_path(_player_cube, target_cube)
	if path.size() > 1:
		_move_along_path(path)


# ─────────────────────────────────────────────
#  逐步移动（协程）
# ─────────────────────────────────────────────
func _move_along_path(path: Array[Vector3i]) -> void:
	_is_moving = true
	_clear_path_highlight()

	# 高亮路径：中间格→黄色，目标格→橙色
	for i in range(1, path.size()):
		var node = _hex_nodes.get(path[i])
		if node:
			var is_target := (i == path.size() - 1)
			node.set_highlighted(true, is_target)
			_path_nodes.append(node)

	# 逐格移动，经过的格子恢复原色
	for i in range(1, path.size()):
		_player_cube = path[i]
		_player.move_to(_hex_map[path[i]])
		await _player.move_finished          # 等待本步完成
		var passed = _hex_nodes.get(path[i])
		if passed:
			passed.set_highlighted(false)
			_path_nodes.erase(passed)

	_is_moving = false


func _clear_path_highlight() -> void:
	for node in _path_nodes:
		node.set_highlighted(false)
	_path_nodes.clear()


# ─────────────────────────────────────────────
#  悬停预览路径（_process 每帧检测，不依赖信号顺序）
# ─────────────────────────────────────────────
var _last_preview_cube: Variant = null   # 上一帧鼠标所在的 cube

@onready var _camera: Camera2D = $Camera2D


func _process(_delta: float) -> void:
	# 镜头始终跟随玩家（平滑由 Camera2D 的 position_smoothing 处理）
	if _player:
		_camera.position = _player.position

	if _is_moving:
		return
	# 将鼠标屏幕坐标转为本节点局部坐标，再逆算 cube
	var mouse_cube := _world_to_cube(get_local_mouse_position())

	# 没有变化就不刷新
	if mouse_cube == _last_preview_cube:
		return
	_last_preview_cube = mouse_cube

	_clear_preview()
	# 鼠标不在任何格子上，或就在主角格，不显示预览
	if not _hex_map.has(mouse_cube) or mouse_cube == _player_cube:
		return

	var path := _find_path(_player_cube, mouse_cube)
	for i in range(1, path.size()):
		var node = _hex_nodes.get(path[i])
		if node:
			node.set_preview_highlighted(true, i == path.size() - 1)
			_preview_nodes.append(node)


func _clear_preview() -> void:
	for node in _preview_nodes:
		node.set_preview_highlighted(false)
	_preview_nodes.clear()


## 鼠标局部坐标 → 最近的 Cube 坐标（平顶六边形逆变换）
func _world_to_cube(local_pos: Vector2) -> Vector3i:
	var q := ( 2.0 / 3.0 * local_pos.x) / HEX_SIZE
	var r := (-1.0 / 3.0 * local_pos.x + sqrt(3.0) / 3.0 * local_pos.y) / HEX_SIZE
	return _cube_round(Vector3(q, r, -q - r))


## 浮点 Cube 坐标四舍五入到最近整数格
func _cube_round(frac: Vector3) -> Vector3i:
	var qr := roundi(frac.x)
	var rr := roundi(frac.y)
	var sr := roundi(frac.z)
	var dq := absf(float(qr) - frac.x)
	var dr := absf(float(rr) - frac.y)
	var ds := absf(float(sr) - frac.z)
	if dq > dr and dq > ds:
		qr = -rr - sr
	elif dr > ds:
		rr = -qr - sr
	else:
		sr = -qr - rr
	return Vector3i(qr, rr, sr)


# ─────────────────────────────────────────────
#  A* 寻路（六角 Cube 坐标）
# ─────────────────────────────────────────────
func _find_path(start: Vector3i, goal: Vector3i) -> Array[Vector3i]:
	if start == goal:
		return []

	# open_set 元素：[f_score, cube]
	var open_set: Array        = [[0.0, start]]
	var came_from: Dictionary  = {}
	var g_score: Dictionary    = {start: 0.0}

	while not open_set.is_empty():
		# 取 f 值最小的节点
		open_set.sort_custom(func(a, b): return a[0] < b[0])
		var current: Vector3i = open_set.pop_front()[1]

		if current == goal:
			return _reconstruct_path(came_from, current)

		for dir: Vector3i in CUBE_DIRS:
			var nb: Vector3i = current + dir
			if not _hex_map.has(nb):
				continue   # 不是合法格子
			var tg: float = g_score.get(current, INF) + 1.0
			if tg < g_score.get(nb, INF):
				came_from[nb] = current
				g_score[nb]   = tg
				open_set.append([tg + _hex_distance(nb, goal), nb])

	return []   # 无路可走


func _reconstruct_path(came_from: Dictionary, current: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path


func _hex_distance(a: Vector3i, b: Vector3i) -> int:
	return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)) / 2


# ─────────────────────────────────────────────
#  工具函数
# ─────────────────────────────────────────────
func _on_viewport_size_changed() -> void:
	position = get_viewport_rect().size * 0.5


func _get_ring(radius: int) -> Array:
	if radius == 0:
		return [Vector3i(0, 0, 0)]
	var results: Array = []
	var cube := Vector3i(-radius, 0, radius)
	for dir_idx in 6:
		for _step in radius:
			results.append(cube)
			cube += CUBE_DIRS[dir_idx]
	return results


func _cube_to_world(cube: Vector3i) -> Vector2:
	var q := float(cube.x)
	var r := float(cube.y)
	return Vector2(
		HEX_SIZE * 1.5       * q,
		HEX_SIZE * sqrt(3.0) * (r + q * 0.5)
	)