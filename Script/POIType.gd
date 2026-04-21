class_name POIType
extends RefCounted

## POI（Point of Interest）类型枚举。
## 起点和终点也视为特殊 POI，与地形 START/FINISH 对应。
enum {
	NONE,     # 无 POI（占位，不应实际使用）
	CAVE,     # 山洞
	SHRINE,   # 神殿
	SPRING,   # 泉水
	START,    # 起点（特殊 POI）
	FINISH,   # 终点 · 金字塔（特殊 POI）
}

## POI 显示名称。
const LABEL := {
	NONE:   "",
	CAVE:   "山洞",
	SHRINE: "神殿",
	SPRING: "泉水",
	START:  "起点",
	FINISH: "金字塔",
}

## POI 的揭示距离加成。
## 某格能否被发现 = REVEAL_RANGE[terrain] + POI_REVEAL_RANGE[poi] + 视野半径 - 距离 >= 0
const REVEAL_RANGE := {
	NONE:   0,
	CAVE:   0,
	SHRINE: 1,  # 神殿醒目，略远处可见
	SPRING: 0,
	START:  0,
	FINISH: 2,  # 金字塔高大，很远就能看到
}

## POI 图标颜色（绘制在格子中央的小圆）。
const ICON_COLOR := {
	NONE:   Color(0, 0, 0, 0),
	CAVE:   Color(0.30, 0.20, 0.10, 1.0),  # 深棕
	SHRINE: Color(0.85, 0.70, 0.10, 1.0),  # 金黄
	SPRING: Color(0.20, 0.65, 0.95, 1.0),  # 天蓝
	START:  Color(0.20, 0.60, 0.90, 1.0),  # 蓝
	FINISH: Color(0.95, 0.78, 0.15, 1.0),  # 黄
}
