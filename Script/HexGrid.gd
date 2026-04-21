extends Node2D

const WorldGenResult    = preload("res://Script/WorldGen/WorldGenResult.gd")
const WorldGenAlgorithm = preload("res://Script/WorldGen/WorldGenAlgorithm.gd")
const CellWorldGen      = preload("res://Script/WorldGen/Algorithms/CellWorldGen.gd")
const PerlinNoiseWorldGen = preload("res://Script/WorldGen/Algorithms/PerlinNoiseWorldGen.gd")
const TerrainType       = preload("res://Script/TerrainType.gd")
const POIType           = preload("res://Script/POIType.gd")
const POI               = preload("res://Script/POI.gd")

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
# cube 坐标到 POI 实例的映射，用于查询和效果触发。
var _poi_map: Dictionary = {}
# cube 坐标到迷雾状态的映射（0=Hidden, 1=Explored, 2=Visible）。
var _fog_map: Dictionary = {}
# 玩家视野半径（以格为单位）。
const VISIBILITY_RADIUS := 3
# DEBUG：是否已全图揭示（开启后 update_fog 不再降级任何格子）。
var _fog_all_revealed: bool = false
# 当前使用的地图生成算法 ID。
@export_enum("cell", "perlin_noise") var algorithm_id: String = "cell"

# ── 柏林噪声算法参数（含边缘不规则参数，由 PN 算法内部处理）──────────
@export_group("Perlin Noise")
## 边缘噪声频率。值越小，整体轮廓越大块；值越大，轮廓越细碎。
@export var edge_noise_frequency: float = 0.0022
## 边缘剔除强度（0.0 = 不剔除，1.0 = 全部剔除）。
@export_range(0.0, 1.0, 0.01) var edge_irregularity: float = 0.60
## 内圈安全半径（以格为单位）。该半径以内的格子不受噪声影响，始终保留。
@export_range(1, 10, 1) var inner_safe_rings: int = 4
## 大区块噪声频率。值越小，地形块越大越平滑。
@export var noise_macro_frequency: float = 0.035
## 细节扰动噪声频率。值越大，边缘越锯齿。
@export var noise_detail_frequency: float = 0.095
## 细节层叠加强度（0.0 = 纯 macro，1.0 = 两层各半）。
@export_range(0.0, 1.0, 0.01) var noise_detail_strength: float = 0.35
## combined 值超过此阈值 → 山地。值越高，山越少越集中。
@export_range(-1.0, 1.0, 0.01) var noise_mountain_threshold: float = 0.42
## combined 值低于此阈值 → 沙漠。值越低，沙漠越少。
@export_range(-1.0, 1.0, 0.01) var noise_desert_threshold: float = -0.18

## 玩家踏入含有 POI 的格子时发出，携带 POI 实例和所在 cube 坐标。
signal poi_triggered(poi: POI, cube: Vector3i)

# 起点和终点的 cube 坐标。
var start_cube: Vector3i = Vector3i.ZERO
var finish_cube: Vector3i = Vector3i.ZERO
# 本局使用的随机种子，供罗盘等系统做确定性随机。
var map_seed: int = 0
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
			hex.set_terrain(TerrainType.PLAIN)

			add_child(hex)
			_hex_map[cube] = world_pos
			_hex_nodes[cube] = hex
			_terrain_map[cube] = TerrainType.PLAIN
			count += 1

		ring += 1

	# ── 第二阶段：调用当前算法生成地图内容（边缘剔除和连通性修复由算法自行处理）─
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	map_seed = rng.seed
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
			var algo := PerlinNoiseWorldGen.new()
			algo.macro_frequency      = noise_macro_frequency
			algo.detail_frequency     = noise_detail_frequency
			algo.detail_strength      = noise_detail_strength
			algo.mountain_threshold   = noise_mountain_threshold
			algo.desert_threshold     = noise_desert_threshold
			algo.edge_noise_frequency = edge_noise_frequency
			algo.edge_irregularity    = edge_irregularity
			algo.inner_safe_rings     = inner_safe_rings
			return algo
		_:
			return CellWorldGen.new()


# 应用算法产出的统一结果对象。
func _apply_generation_result(result: WorldGenResult) -> void:
	# 算法内部剔除的格子（边缘噪声 + 孤岛），释放对应 Hex 节点并更新缓存。
	for cube_v in result.removed_cubes:
		var cube: Vector3i = cube_v as Vector3i
		var hex = _hex_nodes.get(cube)
		if hex and is_instance_valid(hex):
			hex.queue_free()
		_hex_map.erase(cube)
		_hex_nodes.erase(cube)
		_terrain_map.erase(cube)

	_terrain_map = result.terrain_map.duplicate()
	start_cube = result.start_cube
	finish_cube = result.finish_cube
	_debug_border_segments = result.debug_segments.duplicate()

	for cube: Vector3i in _hex_nodes.keys():
		var terrain_type: int = _terrain_map.get(cube, TerrainType.PLAIN)
		var hex = _hex_nodes[cube]
		hex.set_terrain(terrain_type)

	# 同步 POI 数据：把结果里的 poi_map 存入本地缓存，
	# 并通知每个 Hex 节点设置其 POI 类型（用于渲染图标）。
	_poi_map = result.poi_map.duplicate()
	for cube: Vector3i in _poi_map.keys():
		var hex = _hex_nodes.get(cube)
		if hex:
			var poi: POI = _poi_map[cube]
			hex.set_poi(poi.poi_type)

	# 地图和 POI 视觉就绪后，依次触发每个 POI 的环境影响。
	for cube: Vector3i in _poi_map.keys():
		var poi: POI = _poi_map[cube]
		poi.apply_environment_effect(self)

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
	_poi_map.clear()
	_debug_border_segments.clear()


# Godot _draw 回调，绘制红色 Debug 线段。
func _draw() -> void:
	if not debug_draw_cells:
		return
	for seg in _debug_border_segments:
		draw_line(seg[0], seg[1], Color.RED, 3.0, true)


# 查询某格的地形类型，不存在时返回 -1。
func get_terrain(cube: Vector3i) -> int:
	return _terrain_map.get(cube, -1)


# 公开设置某格的地形类型，同步更新视觉。
func set_terrain(cube: Vector3i, type: int) -> void:
	if not _terrain_map.has(cube):
		return
	_terrain_map[cube] = type
	var hex = _hex_nodes.get(cube)
	if hex:
		hex.set_terrain(type)


# 强制修改某格的地形类型（覆盖已有随机结果）。
func _force_terrain(cube: Vector3i, type: int) -> void:
	_terrain_map[cube] = type
	var hex = _hex_nodes.get(cube)
	if hex:
		hex.set_terrain(type)


# 返回以 center 为圆心、max_rings 圈以内（含自身）所有存在于地图中的格子。
func get_area_cubes(center: Vector3i, max_rings: int) -> Array[Vector3i]:
	var result: Array[Vector3i] = []
	for ring in range(0, max_rings + 1):
		for cube in _get_ring_from(center, ring):
			if _hex_map.has(cube):
				result.append(cube)
	return result


# 取以任意格子为中心、指定半径那一圈上的所有 cube 坐标（不做地图过滤）。
func _get_ring_from(center: Vector3i, radius: int) -> Array:
	if radius == 0:
		return [center]
	var results: Array = []
	var cube := center + CUBE_DIRS[4] * radius
	for dir_idx in 6:
		for _step in radius:
			results.append(cube)
			cube += CUBE_DIRS[dir_idx]
	return results


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
	return _terrain_map.get(cube, TerrainType.PLAIN) != TerrainType.MOUNTAIN


# 获取进入某个格子的移动代价（沙漠消耗 5 体力，平原消耗 1）。
func get_move_cost(cube: Vector3i) -> float:
	var t: int = _terrain_map.get(cube, TerrainType.PLAIN)
	if t == TerrainType.DESERT:
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


# ── POI 查询接口 ─────────────────────────────────────────────

## 查询某格是否存在 POI。
func has_poi(cube: Vector3i) -> bool:
	return _poi_map.has(cube)


## 获取某格的 POI 实例，不存在时返回 null。
func get_poi(cube: Vector3i):
	return _poi_map.get(cube, null)


## 获取某格的 POI 类型（POIType 枚举值），不存在时返回 POIType.NONE。
func get_poi_type(cube: Vector3i) -> int:
	var poi = _poi_map.get(cube, null)
	if poi == null:
		return POIType.NONE
	return poi.poi_type


## 返回地图上所有 POI 的 cube 坐标列表。
func get_all_poi_cubes() -> Array:
	return _poi_map.keys()


## 在运行时向某格动态添加或替换 POI，并立即触发其环境影响。
func place_poi(cube: Vector3i, poi_type_val: int) -> void:
	if not has_cube(cube):
		return
	var poi := POI.new(poi_type_val, cube)
	_poi_map[cube] = poi
	var hex = _hex_nodes.get(cube)
	if hex:
		hex.set_poi(poi_type_val)
	poi.apply_environment_effect(self)


## 移除某格的 POI，并清除其视觉表现（完全删除图标）。
func remove_poi(cube: Vector3i) -> void:
	if not _poi_map.has(cube):
		return
	_poi_map.erase(cube)
	var hex = _hex_nodes.get(cube)
	if hex:
		hex.set_poi(POIType.NONE)


## 使某格的 POI 失效：从逻辑映射中移除（不可再触发），但保留图标并灰化显示。
func deactivate_poi(cube: Vector3i) -> void:
	if not _poi_map.has(cube):
		return
	_poi_map.erase(cube)
	var hex = _hex_nodes.get(cube)
	if hex:
		hex.set_poi_inactive()


## 玩家踏入某格时调用此方法。
## 若该格存在可触发的 POI（非 START/FINISH），则发出 poi_triggered 信号。
## 普通 POI 触发一次后自动失效（图标保留但灰化，不可重复触发）。
func notify_player_entered(cube: Vector3i) -> void:
	var poi = _poi_map.get(cube, null)
	if poi == null:
		return
	# 起点/终点 POI 不触发事件（由 main 单独处理胜利/死亡逻辑）。
	if poi.poi_type == POIType.START or poi.poi_type == POIType.FINISH:
		return
	# 发出信号，让 main（或其他监听者）处理具体游戏效果。
	poi_triggered.emit(poi, cube)
	# 触发后使 POI 失效（保留灰化图标），防止重复触发。
	deactivate_poi(cube)


# ── 战争迷雾接口 ──────────────────────────────────────────────

## 初始化全图迷雾：所有格子设为 Hidden，起点周围设为 Visible。
func init_fog(player_start: Vector3i) -> void:
	# 将所有格子设为未探索状态。
	for cube: Vector3i in _hex_nodes.keys():
		_fog_map[cube] = 0  # FOG_HIDDEN
		var hex = _hex_nodes[cube]
		if hex:
			hex.set_fog_state(0)
	# 起点周围立刻揭示。
	reveal_around(player_start, VISIBILITY_RADIUS)


## 以 center 为中心、radius 格为半径揭示视野：
##   - 范围内且视线未被山地阻挡的格子 → FOG_VISIBLE
##   - 上次视野范围（当前仍为 VISIBLE）→ 降为 FOG_EXPLORED
func update_fog(old_visible_cubes: Array, new_center: Vector3i) -> Array:
	# 全图揭示模式：只扩展新视野，不降级任何格子。
	if _fog_all_revealed:
		var new_visible := _calc_visible_cubes(new_center, VISIBILITY_RADIUS)
		for cube in new_visible:
			_set_fog(cube, 2)  # FOG_VISIBLE（已全揭示，此步仅保持状态）
		return old_visible_cubes  # 保持 _visible_cubes 不变，防止下次再降级

	# 计算新视野（考虑山地遮挡）。
	var new_visible := _calc_visible_cubes(new_center, VISIBILITY_RADIUS)
	var new_set: Dictionary = {}
	for c in new_visible:
		new_set[c] = true

	# 将旧视野中不再可见的格子降为已探索。
	for cube in old_visible_cubes:
		if not new_set.has(cube):
			_set_fog(cube, 1)  # FOG_EXPLORED

	# 将新视野格设为可见。
	for cube in new_visible:
		_set_fog(cube, 2)  # FOG_VISIBLE

	return new_visible


## 直接揭示以 center 为中心 radius 圈内的所有格子（设为 FOG_VISIBLE，不做遮挡判断）。
func reveal_around(center: Vector3i, radius: int) -> void:
	for cube in _calc_visible_cubes(center, radius):
		_set_fog(cube, 2)  # FOG_VISIBLE


## 计算从 origin 出发、基础视野半径为 radius 内实际可见的格子列表。
## 规则：
##   1. 自身格始终可见。
##   2. 某格是否在范围内：target_reveal_range + radius - distance >= 0
##      即：distance <= radius + target_reveal_range
##      （山地 reveal_range=+2，因此距离最远能被看到的范围更大）
##   3. 在扩展范围内再做视线遮挡检测：视线路径上遇到山地即被阻断，
##      山地本身可见，山后格子不可见。
func _calc_visible_cubes(origin: Vector3i, radius: int) -> Array:
	# 计算最大可能范围（基础视野 + 地形最大揭示加成 + POI 最大揭示加成）。
	var max_reveal: int = 0
	for v in TerrainType.REVEAL_RANGE.values():
		if v > max_reveal:
			max_reveal = v
	for v in POIType.REVEAL_RANGE.values():
		if v > max_reveal:
			max_reveal = v
	var search_radius := radius + max_reveal

	var visible: Array = [origin]
	var area := get_area_cubes(origin, search_radius)
	for target in area:
		if target == origin:
			continue
		var dist := _hex_distance(origin, target)
		var terrain_t: int = _terrain_map.get(target, TerrainType.PLAIN)
		var terrain_bonus: int = TerrainType.REVEAL_RANGE.get(terrain_t, 0)
		# POI 揭示加成（若该格有 POI）。
		var poi_bonus: int = 0
		var poi = _poi_map.get(target, null)
		if poi != null:
			poi_bonus = POIType.REVEAL_RANGE.get(poi.poi_type, 0)
		var reveal_bonus: int = terrain_bonus + poi_bonus
		# 判断目标格是否在有效视野内（含揭示距离加成）。
		if dist > radius + reveal_bonus:
			continue
		# 视线遮挡检测：沿视线逐格检查，遇山则阻断。
		var blocked := false
		for step_cube in _line_cubes(origin, target):
			if step_cube == origin:
				continue
			var step_terrain: int = _terrain_map.get(step_cube, -1)
			if step_terrain == TerrainType.MOUNTAIN:
				# 山地本身可见，山后面的格子不可见。
				if step_cube not in visible:
					visible.append(step_cube)
				blocked = true
				break
			if step_cube == target:
				break
		if not blocked:
			visible.append(target)
	return visible


## 使用 cube 坐标线性插值，返回从 a 到 b 经过的所有格子（含两端）。
## 利用六边形网格上的"cube lerp + round"方法精确枚举路径上的格子。
func _line_cubes(a: Vector3i, b: Vector3i) -> Array:
	var dist := _hex_distance(a, b)
	if dist == 0:
		return [a]
	var result: Array = []
	for i in range(dist + 1):
		var t := float(i) / float(dist)
		var fx := float(a.x) + (float(b.x) - float(a.x)) * t
		var fy := float(a.y) + (float(b.y) - float(a.y)) * t
		var fz := float(a.z) + (float(b.z) - float(a.z)) * t
		result.append(_cube_round(Vector3(fx, fy, fz)))
	return result


## 获取某格的迷雾状态（0=Hidden, 1=Explored, 2=Visible）。
func get_fog_state(cube: Vector3i) -> int:
	return _fog_map.get(cube, 0)


## DEBUG：将全图所有格子设为 FOG_VISIBLE，并锁定降级逻辑。
func reveal_all() -> void:
	_fog_all_revealed = true
	for cube: Vector3i in _hex_nodes.keys():
		_set_fog(cube, 2)  # FOG_VISIBLE


## 返回地图上所有格子的 cube 坐标列表。
func get_all_cubes() -> Array:
	return _hex_nodes.keys()


## 内部方法：同步设置 _fog_map 和对应 Hex 节点的迷雾状态。
func _set_fog(cube: Vector3i, state: int) -> void:
	if not _hex_nodes.has(cube):
		return
	_fog_map[cube] = state
	var hex = _hex_nodes[cube]
	if hex:
		hex.set_fog_state(state)
