class_name WorldGenResult
extends RefCounted

## 地图生成算法的统一输出对象。
## HexGrid 只消费这个结果，不感知算法内部细节。

# cube → TerrainType (int)
var terrain_map: Dictionary = {}

# 起点 / 终点的 cube 坐标
var start_cube: Vector3i = Vector3i.ZERO
var finish_cube: Vector3i = Vector3i.ZERO

# cube → POI 实例，记录地图上所有 POI 的位置与类型。
# 算法负责填充，HexGrid 消费后负责驱动每个 POI 的环境影响。
var poi_map: Dictionary = {}

# 算法内部剔除的 cube 列表（如边缘噪声剔除），HexGrid 据此释放对应节点。
var removed_cubes: Array = []

# Debug 线段列表，格式：Array of [Vector2, Vector2]
# 算法可以往这里塞任意想可视化的线，HexGrid 统一用红线画出来。
var debug_segments: Array = []

# 算法可选填的附加元数据（字符串 key → 任意值），方便调试输出
var metadata: Dictionary = {}
