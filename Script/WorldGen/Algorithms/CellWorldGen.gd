class_name CellWorldGen
extends WorldGenAlgorithm

const WorldGenResult = preload("res://Script/WorldGen/WorldGenResult.gd")
const WorldgenCells = preload("res://Script/WorldgenCells.gd")

## 当前默认的 Cell 生成算法。
## 这是把原先 HexGrid 中的地图内容生成逻辑独立出来后的第一版。

var cell_count: int = 10
var blocking_density: float = 0.45
var desert_rate: float = 0.12


func generate(
	all_cubes: Array,
	world_pos_map: Dictionary,
	cube_dirs: Array[Vector3i],
	hex_size: float,
	rng: RandomNumberGenerator
) -> WorldGenResult:
	var result := WorldGenResult.new()

	# 1. 默认全部平原
	for cube_v in all_cubes:
		var cube: Vector3i = cube_v as Vector3i
		result.terrain_map[cube] = HexTile.TerrainType.PLAIN

	# 2. Cell 划分
	var cells := WorldgenCells.new()
	cells.cell_count = cell_count
	cells.blocking_density = blocking_density
	cells.partition(all_cubes, cube_dirs, rng)

	# 3. 在边界上按概率放山
	for cube_v in cells.border_set.keys():
		var cube: Vector3i = cube_v as Vector3i
		if cells.should_block(cube, rng):
			result.terrain_map[cube] = HexTile.TerrainType.MOUNTAIN

	# 4. Cell 内部少量沙漠
	for cube_v in all_cubes:
		var cube: Vector3i = cube_v as Vector3i
		if result.terrain_map[cube] != HexTile.TerrainType.PLAIN:
			continue
		if cells.is_border(cube):
			continue
		if rng.randf() < desert_rate:
			result.terrain_map[cube] = HexTile.TerrainType.DESERT

	# 5. 起点 / 终点：最南 / 最北
	var best_south: Vector3i = Vector3i.ZERO
	var best_north: Vector3i = Vector3i.ZERO
	var max_y := -INF
	var min_y := INF
	for cube_v in all_cubes:
		var cube: Vector3i = cube_v as Vector3i
		var wy: float = world_pos_map[cube].y
		if wy > max_y:
			max_y = wy
			best_south = cube
		if wy < min_y:
			min_y = wy
			best_north = cube

	result.start_cube = best_south
	result.finish_cube = best_north
	result.terrain_map[result.start_cube] = HexTile.TerrainType.START
	result.terrain_map[result.finish_cube] = HexTile.TerrainType.FINISH

	# 6. 清理起点和终点周围山地，防止出生点 / 终点被堵死
	for key_cube in [result.start_cube, result.finish_cube]:
		for dir: Vector3i in cube_dirs:
			var nb: Vector3i = key_cube + dir
			if result.terrain_map.get(nb, -1) == HexTile.TerrainType.MOUNTAIN:
				result.terrain_map[nb] = HexTile.TerrainType.PLAIN

	# 7. 生成红色 Debug 边界线
	result.debug_segments = _build_debug_border_segments(all_cubes, world_pos_map, cube_dirs, hex_size, cells)
	result.metadata["algorithm_id"] = "cell"
	result.metadata["cell_count"] = cell_count

	return result


func _build_debug_border_segments(
	all_cubes: Array,
	world_pos_map: Dictionary,
	cube_dirs: Array[Vector3i],
	hex_size: float,
	cells: WorldgenCells
) -> Array:
	var segments: Array = []
	var drawn: Dictionary = {}

	for cube_v in all_cubes:
		var cube: Vector3i = cube_v as Vector3i
		var my_cell: int = cells.get_cell_id(cube)
		var world_pos: Vector2 = world_pos_map[cube]

		for dir_idx in 6:
			var nb: Vector3i = cube + cube_dirs[dir_idx]
			if not cells.cell_map.has(nb):
				continue
			if cells.cell_map[nb] == my_cell:
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


func _hex_vertex(index: int, size: float) -> Vector2:
	var angle_rad := deg_to_rad(60.0 * index)
	return Vector2(cos(angle_rad) * size, sin(angle_rad) * size)
