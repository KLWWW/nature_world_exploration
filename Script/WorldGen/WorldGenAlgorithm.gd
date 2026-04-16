class_name WorldGenAlgorithm
extends RefCounted

## 地图生成算法统一抽象层。
## 所有具体算法都应实现 generate()，输出 WorldGenResult。

func generate(
	all_cubes: Array,
	world_pos_map: Dictionary,
	cube_dirs: Array[Vector3i],
	hex_size: float,
	rng: RandomNumberGenerator
) -> WorldGenResult:
	return WorldGenResult.new()
