class_name LootItem
extends RefCounted

## 单个战利品的数据。
## 持有名称、描述、图标颜色和积分。

## 战利品显示名称。
var label: String = ""
## 战利品简短描述。
var description: String = ""
## 图标颜色（绘制在格子中央）。
var icon_color: Color = Color(1, 1, 1, 1)
## 该战利品的积分。
var score: int = 0


func _init(p_label: String, p_description: String, p_color: Color, p_score: int = 0) -> void:
	label       = p_label
	description = p_description
	icon_color  = p_color
	score       = p_score