class_name POI
extends RefCounted

## 单个 POI 实例数据。
## 持有 POI 类型和所在格子的 cube 坐标。
## 通过 apply_environment_effect 向周围格子施加影响（预留接口）。

const POIType = preload("res://Script/POIType.gd")

## 该 POI 的类型（POIType 枚举值）。
var poi_type: int = POIType.NONE
## 该 POI 所在格子的 cube 坐标。
var cube: Vector3i = Vector3i.ZERO


func _init(type: int, cube_coord: Vector3i) -> void:
	poi_type = type
	cube = cube_coord


## 获取该 POI 的显示名称。
func get_label() -> String:
	return POIType.LABEL.get(poi_type, "")


## 获取该 POI 的图标颜色。
func get_icon_color() -> Color:
	return POIType.ICON_COLOR.get(poi_type, Color(0, 0, 0, 0))


## ──────────────────────────────────────────────────────────────
## 环境影响接口（预留）
## 子类或外部逻辑可重写/调用此方法，对周围格子施加影响。
##
## 参数：
##   hex_grid  — HexGrid 节点，用于查询 / 修改地形和邻居数据。
##   radius    — 影响半径（以格为单位），默认为 1。
##
## 当前为空实现，后续按 POI 类型填充具体逻辑：
##   CAVE   → 例如：降低周围体力消耗（洞穴遮蔽）
##   SHRINE → 例如：提升周围格子的视野或增益
##   SPRING → 例如：将周围沙漠转化为平原（水分滋润）
## ──────────────────────────────────────────────────────────────
func apply_environment_effect(hex_grid: Node, radius: int = 1) -> void:
	match poi_type:
		POIType.CAVE:
			_effect_cave(hex_grid, radius)
		POIType.SHRINE:
			_effect_shrine(hex_grid, radius)
		POIType.SPRING:
			_effect_spring(hex_grid, radius)
		_:
			pass  # START / FINISH / NONE 暂无环境效果


## 山洞环境效果（预留，待填充）。
func _effect_cave(_hex_grid: Node, _radius: int) -> void:
	pass


## 神殿环境效果（预留，待填充）。
func _effect_shrine(_hex_grid: Node, _radius: int) -> void:
	pass


## 泉水环境效果（预留，待填充）。
func _effect_spring(_hex_grid: Node, _radius: int) -> void:
	pass
