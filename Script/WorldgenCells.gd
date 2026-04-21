class_name WorldgenCells
extends RefCounted

## 世界生成单元格系统
## 将六边形网格划分为多个 Cell（类似 Voronoi），并在 Cell 边界放置阻挡地形。

# ── 配置 ──────────────────────────────────────────────────
## 种子数量（即 Cell 数量）。
var cell_count: int = 10
## 边界格变为阻挡地形的概率（0.0 ~ 1.0）。
## 值越大，Cell 越封闭；值越小，Cell 越开放。
var blocking_density: float = 0.45

# ── 内部状态 ────────────────────────────────────────────────
## cube → 所属 cell_id (int)
var cell_map: Dictionary = {}
## cube → true（仅边界格存在于此字典中）
var border_set: Dictionary = {}
## 种子点列表（同时也是每个 Cell 的"中心"代表格）。
var seeds: Array[Vector3i] = []

# ── 对外只读查询 ────────────────────────────────────────────
## 返回某个格子的 cell_id，不存在返回 -1。
func get_cell_id(cube: Vector3i) -> int:
	return cell_map.get(cube, -1)

## 判断某个格子是否为 Cell 边界格。
func is_border(cube: Vector3i) -> bool:
	return border_set.has(cube)

# ── 核心算法 ────────────────────────────────────────────────
## 在给定的所有 cube 坐标上执行 Cell 划分 + 边界检测。
## all_cubes: 地图中所有格子的 cube 坐标数组。
## cube_dirs: 六方向偏移。
## rng: 随机数生成器（由外部传入保证种子可控）。
func partition(all_cubes: Array, cube_dirs: Array[Vector3i], rng: RandomNumberGenerator) -> void:
	cell_map.clear()
	border_set.clear()
	seeds.clear()

	if all_cubes.is_empty():
		return

	# ── 1. 选取种子点 ──────────────────────────────────────
	var shuffled := all_cubes.duplicate()
	shuffled.shuffle()
	var actual_count := mini(cell_count, shuffled.size())
	for i in actual_count:
		seeds.append(shuffled[i] as Vector3i)

	# ── 2. 离散 Voronoi：每格归属最近种子 ─────────────────
	for cube_v in all_cubes:
		var cube: Vector3i = cube_v as Vector3i
		var best_id := 0
		var best_dist := _hex_distance(cube, seeds[0])
		for id in range(1, seeds.size()):
			var d := _hex_distance(cube, seeds[id])
			if d < best_dist:
				best_dist = d
				best_id = id
		cell_map[cube] = best_id

	# ── 3. 边界检测：邻居属于不同 Cell 即为边界 ──────────
	for cube_v in all_cubes:
		var cube: Vector3i = cube_v as Vector3i
		var my_id: int = cell_map[cube]
		for dir: Vector3i in cube_dirs:
			var nb: Vector3i = cube + dir
			if cell_map.has(nb) and cell_map[nb] != my_id:
				border_set[cube] = true
				break  # 只要有一个异 Cell 邻居就够了

## 根据 blocking_density 判断某个边界格是否应放置阻挡地形。
## 调用者遍历 border_set 并逐个调用此方法。
func should_block(cube: Vector3i, rng: RandomNumberGenerator) -> bool:
	if not is_border(cube):
		return false
	return rng.randf() < blocking_density

# ── 工具 ──────────────────────────────────────────────────
func _hex_distance(a: Vector3i, b: Vector3i) -> int:
	return (abs(a.x - b.x) + abs(a.y - b.y) + abs(a.z - b.z)) / 2
