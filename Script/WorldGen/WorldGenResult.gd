class_name WorldGenResult
extends RefCounted

## 地图生成算法的统一输出对象。
## HexGrid 只消费这个结果，不感知算法内部细节。

# cube → TerrainType (int)
var terrain_map: Dictionary = {}

# 起点 / 终点的 cube 坐标
var start_cube: Vector3i = Vector3i.ZERO
var finish_cube: Vector3i = Vector3i.ZERO

# Debug 线段列表，格式：Array of [Vector2, Vector2]
# 算法可以往这里塞任意想可视化的线，HexGrid 统一用红线画出来。
var debug_segments: Array = []

# 算法可选填的附加元数据（字符串 key → 任意值），方便调试输出
var metadata: Dictionary = {}
