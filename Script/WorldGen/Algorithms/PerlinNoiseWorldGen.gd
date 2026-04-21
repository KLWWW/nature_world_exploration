class_name PerlinNoiseWorldGen
extends WorldGenAlgorithm

const WorldGenResult = preload("res://Script/WorldGen/WorldGenResult.gd")
const TerrainType = preload("res://Script/TerrainType.gd")

## 双层噪声地形生成：
## - macro_noise 控制大区块分布
## - detail_noise 控制局部扰动细节
## 适合原型阶段快速试自然地形分布

var macro_frequency: float = 0.035
var detail_frequency: float = 0.095
var detail_strength: float = 0.35

var mountain_threshold: float = 0.42
var desert_threshold: float = -0.18

# ── 边缘噪声剔除参数 ──────────────────────────────────────
## 边缘噪声频率。值越小，整体轮廓越大块；值越大，轮廓越细碎。
var edge_noise_frequency: float = 0.0022
## 边缘剔除强度（0.0 = 不剔除，1.0 = 全部剔除）。
var edge_irregularity: float = 0.60
## 内圈安全半径（以格为单位），该半径内的格子始终保留。
var inner_safe_rings: int = 4


func generate(
	all_cubes: Array,
	world_pos_map: Dictionary,
	cube_dirs: Array[Vector3i],
	hex_size: float,
	rng: RandomNumberGenerator
) -> WorldGenResult:
	var result := WorldGenResult.new()

	# ── 阶段 A：边缘噪声剔除 ────────────────────────────────
	var working_cubes: Array = all_cubes.duplicate()
	var working_pos_map: Dictionary = world_pos_map.duplicate()
	_apply_edge_noise(working_cubes, working_pos_map, rng)

	# ── 阶段 B：连通性修复（去孤岛） ────────────────────────
	_remove_disconnected_tiles(working_cubes, working_pos_map, cube_dirs)

	# ── 阶段 C：双层噪声地形生成 ────────────────────────────
	var macro_noise := FastNoiseLite.new()
	var detail_noise := FastNoiseLite.new()

	macro_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	macro_noise.seed = rng.randi()
	macro_noise.frequency = macro_frequency

	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.seed = rng.randi()
	detail_noise.frequency = detail_frequency

	for cube_v in working_cubes:
		var cube: Vector3i = cube_v as Vector3i
		var world_pos: Vector2 = working_pos_map[cube]

		var macro_value := macro_noise.get_noise_2d(world_pos.x, world_pos.y)
		var detail_value := detail_noise.get_noise_2d(world_pos.x, world_pos.y)
		var combined := macro_value + detail_value * detail_strength

		var terrain := TerrainType.PLAIN
		if combined >= mountain_threshold:
			terrain = TerrainType.MOUNTAIN
		elif combined <= desert_threshold:
			terrain = TerrainType.DESERT
		result.terrain_map[cube] = terrain

	# ── 阶段 D：起点 / 终点（最南 / 最北） ──────────────────
	var best_south: Vector3i = Vector3i.ZERO
	var best_north: Vector3i = Vector3i.ZERO
	var max_y := -INF
	var min_y := INF
	for cube_v in working_cubes:
		var cube: Vector3i = cube_v as Vector3i
		var wy: float = working_pos_map[cube].y
		if wy > max_y:
			max_y = wy
			best_south = cube
		if wy < min_y:
			min_y = wy
			best_north = cube

	result.start_cube = best_south
	result.finish_cube = best_north
	result.terrain_map[result.start_cube] = TerrainType.START
	result.terrain_map[result.finish_cube] = TerrainType.FINISH

	for key_cube in [result.start_cube, result.finish_cube]:
		for dir: Vector3i in cube_dirs:
			var nb: Vector3i = key_cube + dir
			if result.terrain_map.get(nb, -1) == TerrainType.MOUNTAIN:
				result.terrain_map[nb] = TerrainType.PLAIN

	# ── 阶段 E：记录被剔除的格子，通知 HexGrid 清理节点 ─────
	for cube_v in all_cubes:
		var cube: Vector3i = cube_v as Vector3i
		if not working_pos_map.has(cube):
			result.removed_cubes.append(cube)

	result.debug_segments = _build_terrain_boundary_segments(working_cubes, working_pos_map, cube_dirs, hex_size, result.terrain_map)

	result.metadata["algorithm_id"] = "perlin_noise"
	result.metadata["macro_frequency"] = macro_frequency
	result.metadata["detail_frequency"] = detail_frequency
	result.metadata["detail_strength"] = detail_strength
	result.metadata["mountain_threshold"] = mountain_threshold
	result.metadata["desert_threshold"] = desert_threshold

	return result


# 边缘噪声剔除：直接修改传入的 working_cubes / working_pos_map。
func _apply_edge_noise(
	working_cubes: Array,
	working_pos_map: Dictionary,
	rng: RandomNumberGenerator
) -> void:
	if edge_irregularity <= 0.0:
		return

	var edge_noise := FastNoiseLite.new()
	edge_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	edge_noise.seed = rng.randi()
	edge_noise.frequency = edge_noise_frequency

	var threshold: float = 2.0 * edge_irregularity - 1.0
	var to_remove: Array = []

	for cube_v in working_cubes:
		var cube: Vector3i = cube_v as Vector3i
		var ring_dist: int = (abs(cube.x) + abs(cube.y) + abs(cube.z)) / 2
		if ring_dist <= inner_safe_rings:
			continue
		var world_pos: Vector2 = working_pos_map[cube]
		if edge_noise.get_noise_2d(world_pos.x, world_pos.y) < threshold:
			to_remove.append(cube)

	for cube in to_remove:
		working_cubes.erase(cube)
		working_pos_map.erase(cube)


# 连通性修复：从原点 BFS，剔除所有孤岛格子。
func _remove_disconnected_tiles(
	working_cubes: Array,
	working_pos_map: Dictionary,
	cube_dirs: Array[Vector3i]
) -> void:
	if not working_pos_map.has(Vector3i.ZERO):
		return

	var visited: Dictionary = {}
	var queue: Array = [Vector3i.ZERO]
	visited[Vector3i.ZERO] = true

	while not queue.is_empty():
		var current: Vector3i = queue.pop_front()
		for dir: Vector3i in cube_dirs:
			var nb: Vector3i = current + dir
			if working_pos_map.has(nb) and not visited.has(nb):
				visited[nb] = true
				queue.append(nb)

	var to_remove: Array = []
	for cube_v in working_cubes:
		var cube: Vector3i = cube_v as Vector3i
		if not visited.has(cube):
			to_remove.append(cube)

	for cube in to_remove:
		working_cubes.erase(cube)
		working_pos_map.erase(cube)


func _build_terrain_boundary_segments(
	all_cubes: Array,
	world_pos_map: Dictionary,
	cube_dirs: Array[Vector3i],
	hex_size: float,
	terrain_map: Dictionary
) -> Array:
	var segments: Array = []
	var drawn: Dictionary = {}

	for cube_v in all_cubes:
		var cube: Vector3i = cube_v as Vector3i
		var my_terrain: int = terrain_map.get(cube, TerrainType.PLAIN)
		var world_pos: Vector2 = world_pos_map[cube]

		for dir_idx in 6:
			var nb: Vector3i = cube + cube_dirs[dir_idx]
			if not terrain_map.has(nb):
				continue

			var nb_terrain: int = terrain_map[nb]
			if nb_terrain == my_terrain:
				continue

			if not _is_debug_terrain(my_terrain) and not _is_debug_terrain(nb_terrain):
				continue

			var key := "%s_%s_%d" % [cube, nb, dir_idx] if str(cube) < str(nb) \
				else "%s_%s_%d" % [nb, cube, (dir_idx + 3) % 6]
			if drawn.has(key):
				continue
			drawn[key] = true

			var v1: Vector2 = world_pos + _hex_vertex((dir_idx + 5) % 6, hex_size)
			var v2: Vector2 = world_pos + _hex_vertex(dir_idx, hex_size)
			segments.append([v1, v2])

	return segments


func _is_debug_terrain(terrain_type: int) -> bool:
	return terrain_type == TerrainType.MOUNTAIN or terrain_type == TerrainType.DESERT


func _hex_vertex(index: int, size: float) -> Vector2:
	var angle_rad := deg_to_rad(60.0 * index)
	return Vector2(cos(angle_rad) * size, sin(angle_rad) * size)