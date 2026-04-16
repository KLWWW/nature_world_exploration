class_name PerlinNoiseWorldGen
extends WorldGenAlgorithm

const WorldGenResult = preload("res://Script/WorldGen/WorldGenResult.gd")

## 双层噪声地形生成：
## - macro_noise 控制大区块分布
## - detail_noise 控制局部扰动细节
## 适合原型阶段快速试自然地形分布

var macro_frequency: float = 0.035
var detail_frequency: float = 0.095
var detail_strength: float = 0.35

var mountain_threshold: float = 0.42
var desert_threshold: float = -0.18


func generate(
	all_cubes: Array,
	world_pos_map: Dictionary,
	cube_dirs: Array[Vector3i],
	hex_size: float,
	rng: RandomNumberGenerator
) -> WorldGenResult:
	var result := WorldGenResult.new()
	var macro_noise := FastNoiseLite.new()
	var detail_noise := FastNoiseLite.new()

	macro_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	macro_noise.seed = rng.randi()
	macro_noise.frequency = macro_frequency

	detail_noise.noise_type = FastNoiseLite.TYPE_PERLIN
	detail_noise.seed = rng.randi()
	detail_noise.frequency = detail_frequency

	for cube_v in all_cubes:
		var cube: Vector3i = cube_v as Vector3i
		var world_pos: Vector2 = world_pos_map[cube]

		var macro_value := macro_noise.get_noise_2d(world_pos.x, world_pos.y)
		var detail_value := detail_noise.get_noise_2d(world_pos.x, world_pos.y)
		var combined := macro_value + detail_value * detail_strength

		var terrain := HexTile.TerrainType.PLAIN
		if combined >= mountain_threshold:
			terrain = HexTile.TerrainType.MOUNTAIN
		elif combined <= desert_threshold:
			terrain = HexTile.TerrainType.DESERT
		result.terrain_map[cube] = terrain

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

	for key_cube in [result.start_cube, result.finish_cube]:
		for dir: Vector3i in cube_dirs:
			var nb: Vector3i = key_cube + dir
			if result.terrain_map.get(nb, -1) == HexTile.TerrainType.MOUNTAIN:
				result.terrain_map[nb] = HexTile.TerrainType.PLAIN

	result.metadata["algorithm_id"] = "perlin_noise"
	result.metadata["macro_frequency"] = macro_frequency
	result.metadata["detail_frequency"] = detail_frequency
	result.metadata["detail_strength"] = detail_strength
	result.metadata["mountain_threshold"] = mountain_threshold
	result.metadata["desert_threshold"] = desert_threshold

	return result
