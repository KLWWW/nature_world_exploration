extends Node2D

const WorldGenResult = preload("res://Script/WorldGen/WorldGenResult.gd")
const WorldGenAlgorithm = preload("res://Script/WorldGen/WorldGenAlgorithm.gd")
const CellWorldGen = preload("res://Script/WorldGen/Algorithms/CellWorldGen.gd")
const PerlinNoiseWorldGen = preload("res://Script/WorldGen/Algorithms/PerlinNoiseWorldGen.gd")

# 单个六边形格子的场景资源。
const HEX_SCENE = preload("res://Hex.tscn")
# 六边形格子的半径，也用于 cube 坐标和世界坐标之间的换算。
const HEX_SIZE = 64.0
# Maximum number of tiles generated for the current map.
const MAX_TILES = 500
# cube 坐标系中的六个相邻方向。
const CUBE_DIRS: Array[Vector3i] = [
	Vector3i(1, -1, 0),
	Vector3i(1, 0, -1),
	Vector3i(0, 1, -1),
	Vector3i(-1, 1, 0),
	Vector3i(-1, 0, 1),
	Vector3i(0, -1, 1),
]

# cube 坐标到本地世界坐标的映射，用于玩家移动和格子定位。
var _hex_map: Dictionary = {}
# cube 坐标到 Hex 节点的映射，用于高亮和状态切换。
var _hex_nodes: Dictionary = {}
# cube 坐标到地形类型的映射，用于寻路判断。
var _terrain_map: Dictionary = {}
# 当前使用的地图生成算法 ID。
@export_enum("cell", "perlin_noise") var algorithm_id: String = "perlin_noise"
# 起点和终点的 cube 坐标。
var start_cube: Vector3i = Vector3i.ZERO
var finish_cube: Vector3i = Vector3i.ZERO
# 是否绘制算法返回的 Debug 线。
var debug_draw_cells: bool = true
# 缓存的 Debug 线段列表 [[from, to], ...]，避免每帧重复计算。
var _debug_border_segments: Array = []


# 生成整张六边形地图，并把每个格子注册到输入层。
func generate(input_controller) -> void:
	_clear_map_state()
	var count := 0
	var ring := 0

	# ── 第一阶段：生成地图骨架（节点与坐标索引） ───────────
	while count < MAX_TILES:
		for cube: Vector3i in _get_ring(ring):
			if count >= MAX_TILES:
				break

			var world_pos := cube_to_world(cube)
			var hex = HEX_SCENE.instantiate()
			hex.position = world_pos
			input_controller.register_hex(hex, cube)
			hex.set_terrain(HexTile.TerrainType.PLAIN)

			add_child(hex)
			_hex_map[cube] = world_pos
			_hex_nodes[cube] = hex
			_terrain_map[cube] = HexTile.TerrainType.PLAIN
			count += 1

		ring += 1

	# ── 第二阶段：调用当前算法生成地图内容 ────────────────
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var all_cubes: Array = _hex_map.keys()
	var algorithm: WorldGenAlgorithm = _create_algorithm()
	var result: WorldGenResult = algorithm.generate(all_cubes, _hex_map, CUBE_DIRS, HEX_SIZE, rng)
	_apply_generation_result(result)


# ── 生成算法架构 ───────────────────────────────────────────

# 根据当前 algorithm_id 创建对应的算法实例。
func _create_algorithm() -> WorldGenAlgorithm:
	match algorithm_id:
		"cell":
			return CellWorldGen.new()
		"perlin_noise":
			return PerlinNoiseWorldGen.new()
		_:
			return CellWorldGen.new()


# 应用算法产出的统一结果对象。
func _apply_generation_result(result: WorldGenResult) -> void:
	_terrain_map = result.terrain_map.duplicate()
	start_cube = result.start_cube
	finish_cube = result.finish_cube
	_debug_border_segments = result.debug_segments.duplicate()

	for cube: Vector3i in _hex_nodes.keys():
		var terrain_type: int = _terrain_map.get(cube, HexTile.TerrainType.PLAIN)
		var hex = _hex_nodes[cube]
		hex.set_terrain(terrain_type)

	if debug_draw_cells:
		queue_redraw()


# 清理地图节点和运行时缓存，保证可重复生成。
func _clear_map_state() -> void:
	for hex in _hex_nodes.values():
		if is_instance_valid(hex):
			hex.queue_free()
	_hex_map.clear()
	_hex_nodes.clear()
	_terrain_map.clear()
	_debug_border_segments.clear()


# Godot _draw 回调，绘制红色 Debug 线段。
func _draw() -> void:
	if not debug_draw_cells:
		return
	for seg in _debug_border_segments:
		draw_line(seg[0], seg[1], Color.RED, 3.0, true)


# 强制修改某格的地形类型（覆盖已有随机结果）。
func _force_terrain(cube: Vector3i, type: int) -> void:
	_terrain_map[cube] = type
	var hex = _hex_nodes.get(cube)
	if hex:
		hex.set_terrain(type)


# 判断某个 cube 坐标是否存在于当前地图中。
func has_cube(cube: Vector3i) -> bool:
	return _hex_map.has(cube)


# 根据 cube 坐标取出对应的 Hex 节点。
func get_hex_node(cube: Vector3i):
	return _hex_nodes.get(cube)


# 根据 cube 坐标取出对应的本地世界坐标。
func get_world_position(cube: Vector3i) -> Vector2:
	return _hex_map.get(cube, Vector2.ZERO)


# 将本地世界坐标转换成最近的 cube 坐标。
func world_to_cube(local_pos: Vector2) -> Vector3i:
	var q := (2.0 / 3.0 * local_pos.x) / HEX_SIZE
	var r := (-1.0 / 3.0 * local_pos.x + sqrt(3.0) / 3.0 * local_pos.y) / HEX_SIZE
	return _cube_round(Vector3(q, r, -q - r))


# 使用 A* 寻找从起点到终点的 cube 坐标路径。
func find_path(start: Vector3i, goal: Vector3i) -> Array[Vector3i]:
	if start == goal:
		return []

	# open_set 保存 [f_score, cube]，每轮优先扩展 f_score 最低的格子。
	var open_set: Array = [[0.0, start]]
	# came_from 记录每个格子的最优前驱，用于最后反向还原路径。
	var came_from: Dictionary = {}
	# g_score 记录从起点走到每个格子的当前最低已知成本。
	var g_score: Dictionary = {start: 0.0}

	while not open_set.is_empty():
		# 当前地图规模较小，每轮排序足够简单可靠。
		open_set.sort_custom(func(a, b): return a[0] < b[0])
		var current: Vector3i = open_set.pop_front()[1]

		if current == goal:
			return _reconstruct_path(came_from, current)

		# A* 主体只关心邻居、可通行性和移动代价，具体规则交给扩展点。
		for neighbor: Vector3i in get_neighbors(current):
			if not is_walkable(neighbor):
				continue

			var tentative_g: float = float(g_score.get(current, INF)) + get_move_cost(neighbor)
			if tentative_g < float(g_score.get(neighbor, INF)):
				came_from[neighbor] = current
				g_score[neighbor] = tentative_g
				open_set.append([tentative_g + _hex_distance(neighbor, goal), neighbor])

	return []


# 获取某个 cube 坐标周围所有存在于地图中的邻居。
func get_neighbors(cube: Vector3i) -> Array[Vector3i]:
	var neighbors: Array[Vector3i] = []

	# 邻居的六边形几何规则集中放在这里，避免寻路主体直接处理坐标细节。
	for dir: Vector3i in CUBE_DIRS:
		var neighbor: Vector3i = cube + dir
		if has_cube(neighbor):
			neighbors.append(neighbor)

	return neighbors


# 判断某个格子是否可以被寻路进入（山地不可通行）。
func is_walkable(cube: Vector3i) -> bool:
	if not has_cube(cube):
		return false
	return _terrain_map.get(cube, HexTile.TerrainType.PLAIN) != HexTile.TerrainType.MOUNTAIN


# 获取进入某个格子的移动代价（沙漠消耗 5 体力，平原消耗 1）。
func get_move_cost(cube: Vector3i) -> float:
	var t: int = _terrain_map.get(cube, HexTile.TerrainType.PLAIN)
	if t == HexTile.TerrainType.DESERT:
		return 5.0
	return 1.0


# 根据 came_from 中记录的前驱关系反向还原完整路径。
func _reconstruct_path(came_from: Dictionary, current: Vector3i) -> Array[Vector3i]:
	var path: Array[Vector3i] = [current]
	while came_from.has(current):
		current = came_from[current]
		path.push_front(current)
	return path


# 计算两个 cube 坐标之间的六边形网格距离。
func _hex_distance(a: Vector3i, b: Vector3i) -> int:
	return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)) / 2


# 获取以原点为中心、指定半径那一圈上的所有 cube 坐标。
func _get_ring(radius: int) -> Array:
	if radius == 0:
		return [Vector3i.ZERO]

	var results: Array = []
	var cube := Vector3i(-radius, 0, radius)

	# 从环上的一个角开始，沿六条边依次走完整圈。
	for dir_idx in 6:
		for _step in radius:
			results.append(cube)
			cube += CUBE_DIRS[dir_idx]

	return results


# 将 cube 坐标转换成本地世界坐标。
func cube_to_world(cube: Vector3i) -> Vector2:
	var q := float(cube.x)
	var r := float(cube.y)
	return Vector2(
		HEX_SIZE * 1.5 * q,
		HEX_SIZE * sqrt(3.0) * (r + q * 0.5)
	)


# 将浮点 cube 坐标修正为最近的合法整数 cube 坐标。
func _cube_round(frac: Vector3) -> Vector3i:
	var qr := roundi(frac.x)
	var rr := roundi(frac.y)
	var sr := roundi(frac.z)
	var dq := absf(float(qr) - frac.x)
	var dr := absf(float(rr) - frac.y)
	var ds := absf(float(sr) - frac.z)

	# cube 坐标必须满足 q + r + s = 0，因此修正误差最大的分量。
	if dq > dr and dq > ds:
		qr = -rr - sr
	elif dr > ds:
		rr = -qr - sr
	else:
		sr = -qr - rr

	return Vector3i(qr, rr, sr)