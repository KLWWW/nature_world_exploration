class_name CellWorldGen
extends WorldGenAlgorithm

const WorldGenResult = preload("res://Script/WorldGen/WorldGenResult.gd")
const WorldgenCells  = preload("res://Script/WorldgenCells.gd")
const TerrainType    = preload("res://Script/TerrainType.gd")
const POIType        = preload("res://Script/POIType.gd")
const POI            = preload("res://Script/POI.gd")

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
		result.terrain_map[cube] = TerrainType.PLAIN

	# 2. Cell 划分
	var cells := WorldgenCells.new()
	cells.cell_count = cell_count
	cells.blocking_density = blocking_density
	cells.partition(all_cubes, cube_dirs, rng)

	# 3. 在边界上按概率放山
	for cube_v in cells.border_set.keys():
		var cube: Vector3i = cube_v as Vector3i
		if cells.should_block(cube, rng):
			result.terrain_map[cube] = TerrainType.MOUNTAIN

	# 4. Cell 内部少量沙漠
	for cube_v in all_cubes:
		var cube: Vector3i = cube_v as Vector3i
		if result.terrain_map[cube] != TerrainType.PLAIN:
			continue
		if cells.is_border(cube):
			continue
		if rng.randf() < desert_rate:
			result.terrain_map[cube] = TerrainType.DESERT

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
	result.terrain_map[result.start_cube] = TerrainType.START
	result.terrain_map[result.finish_cube] = TerrainType.FINISH

	# 6. 清理起点和终点周围山地，防止出生点 / 终点被堵死
	for key_cube in [result.start_cube, result.finish_cube]:
		for dir: Vector3i in cube_dirs:
			var nb: Vector3i = key_cube + dir
			if result.terrain_map.get(nb, -1) == TerrainType.MOUNTAIN:
				result.terrain_map[nb] = TerrainType.PLAIN

	# 7. 生成 POI
	# 起点和终点先注册为特殊 POI。
	result.poi_map[result.start_cube]  = POI.new(POIType.START,  result.start_cube)
	result.poi_map[result.finish_cube] = POI.new(POIType.FINISH, result.finish_cube)

	# 每个 Cell 的种子格（即 Cell 中心）放置一个普通 POI。
	# 三种 POI 类型循环分配，跳过已被起点/终点占用或地形为山地的格子。
	# 同时，起点和终点所在的 Cell 内不放置任何普通 POI。
	var start_cell_id: int  = cells.get_cell_id(result.start_cube)
	var finish_cell_id: int = cells.get_cell_id(result.finish_cube)

	var regular_poi_types: Array = [POIType.CAVE, POIType.SHRINE, POIType.SPRING]
	var poi_index := 0
	for seed_cube: Vector3i in cells.seeds:
		# 起/终点格已注册，跳过。
		if result.poi_map.has(seed_cube):
			poi_index += 1
			continue
		# 山地格不放 POI（种子格理论上不会是山地，但做保险检查）。
		if result.terrain_map.get(seed_cube, TerrainType.PLAIN) == TerrainType.MOUNTAIN:
			poi_index += 1
			continue
		# 起点或终点所在 Cell 内不放普通 POI。
		var seed_cell_id: int = cells.get_cell_id(seed_cube)
		if seed_cell_id == start_cell_id or seed_cell_id == finish_cell_id:
			poi_index += 1
			continue
		var poi_type_val: int = regular_poi_types[poi_index % regular_poi_types.size()]
		result.poi_map[seed_cube] = POI.new(poi_type_val, seed_cube)
		poi_index += 1

	# 8. 生成红色 Debug 边界线
	result.debug_segments = _build_debug_border_segments(all_cubes, world_pos_map, cube_dirs, hex_size, cells)
	result.metadata["algorithm_id"] = "cell"
	result.metadata["cell_count"] = cell_count
	result.metadata["poi_count"] = result.poi_map.size()

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
