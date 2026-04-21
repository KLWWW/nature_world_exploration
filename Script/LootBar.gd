extends Control

const LootItem = preload("res://Script/LootItem.gd")

## 战利品栏：底部横排 10 个格子，每格放一件战利品。
##
## 公开方法：
##   add_loot(item: LootItem) -> bool   — 向第一个空格添加战利品，满了返回 false
##   remove_loot(index: int)            — 移除指定格的战利品
##   clear_loot()                       — 清空所有格子
##   is_full() -> bool                  — 是否已满
##   get_loot(index: int) -> LootItem   — 获取指定格的战利品（空格返回 null）

## 格子数量。
const SLOT_COUNT := 10
## 每列格子数（行数）。
const SLOT_ROWS  := 2
## 每行格子数（列数）。
const SLOT_COLS  := 5
## 每个格子的大小（px）。
const SLOT_SIZE  := 38
## 格子水平间距（px）。
const SLOT_GAP_X := 4
## 格子垂直间距（px）。
const SLOT_GAP_Y := 4
## 面板两侧内边距。
const PANEL_PAD  := 7
## 标题区域高度（含下方留白）。
const TITLE_H    := 22

## 面板背景色（极简透明）。
const PANEL_BG_COLOR     := Color(0.05, 0.05, 0.08, 0.20)
## 面板边框色。
const PANEL_BORDER_COLOR := Color(1.00, 1.00, 1.00, 0.12)
## 格子底色（深灰）。
const SLOT_BG_COLOR      := Color(0.10, 0.10, 0.14, 0.30)
## 格子底色（悬停）。
const SLOT_BG_HOVER      := Color(0.22, 0.24, 0.30, 0.35)
## 格子边框（普通）。
const SLOT_BORDER_COLOR  := Color(1.00, 1.00, 1.00, 0.18)
## 格子边框（悬停高亮）。
const SLOT_BORDER_HOVER  := Color(0.90, 0.82, 0.30, 0.80)
## 空格子中心十字颜色。
const SLOT_EMPTY_COLOR   := Color(1.00, 1.00, 1.00, 0.15)
## 图标外圈高光色。
const ICON_SHINE_COLOR   := Color(1.00, 1.00, 1.00, 0.20)
## 图标内阴影色。
const ICON_SHADOW_COLOR  := Color(0.00, 0.00, 0.00, 0.10)

## 当前每个格子里存放的 LootItem（null 表示空）。
var _slots: Array = []


func _ready() -> void:
	_slots.resize(SLOT_COUNT)
	for i in SLOT_COUNT:
		_slots[i] = null

	# 2列×5行面板尺寸
	var panel_w := SLOT_COLS * SLOT_SIZE + (SLOT_COLS - 1) * SLOT_GAP_X + PANEL_PAD * 2
	var panel_h := TITLE_H + SLOT_ROWS * SLOT_SIZE + (SLOT_ROWS - 1) * SLOT_GAP_Y + PANEL_PAD
	custom_minimum_size = Vector2(panel_w, panel_h)
	# 纯显示，不捕获鼠标事件
	mouse_filter = Control.MOUSE_FILTER_IGNORE


# ─────────────────────────────────────────────────────────────
# 公开 API
# ─────────────────────────────────────────────────────────────

## 添加战利品，返回是否成功（背包满则失败）。
func add_loot(item: LootItem) -> bool:
	for i in SLOT_COUNT:
		if _slots[i] == null:
			_slots[i] = item
			queue_redraw()
			return true
	return false


## 移除指定格的战利品。
func remove_loot(index: int) -> void:
	if index >= 0 and index < SLOT_COUNT:
		_slots[index] = null
		queue_redraw()


## 清空所有格子。
func clear_loot() -> void:
	for i in SLOT_COUNT:
		_slots[i] = null
	queue_redraw()


## 判断背包是否已满。
func is_full() -> bool:
	for i in SLOT_COUNT:
		if _slots[i] == null:
			return false
	return true


## 获取指定格的战利品（空格返回 null）。
func get_loot(index: int) -> LootItem:
	if index >= 0 and index < SLOT_COUNT:
		return _slots[index]
	return null


# ─────────────────────────────────────────────────────────────
# 绘制（2列×5行网格，纯显示）
# ─────────────────────────────────────────────────────────────

func _draw() -> void:
	var font    := ThemeDB.fallback_font
	var panel_w := float(SLOT_COLS * SLOT_SIZE + (SLOT_COLS - 1) * SLOT_GAP_X + PANEL_PAD * 2)
	var panel_h := float(TITLE_H + SLOT_ROWS * SLOT_SIZE + (SLOT_ROWS - 1) * SLOT_GAP_Y + PANEL_PAD)

	# ── 面板背景 ──
	draw_rect(Rect2(0, 0, panel_w, panel_h), PANEL_BG_COLOR, true)
	# 顶部高光线
	draw_line(Vector2(2, 1), Vector2(panel_w - 2, 1), Color(1, 1, 1, 0.08), 1.0)
	# 外框
	draw_rect(Rect2(0, 0, panel_w, panel_h), PANEL_BORDER_COLOR, false, 1.0)

	# ── 标题 ──
	draw_rect(Rect2(float(PANEL_PAD), 7, 3, 14), Color(0.90, 0.82, 0.30, 0.90), true)
	draw_string(font, Vector2(float(PANEL_PAD) + 7, 20), "战利品",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.92, 0.88, 0.72, 1.0))
	draw_line(Vector2(6, float(TITLE_H) - 2), Vector2(panel_w - 6, float(TITLE_H) - 2),
			Color(0.40, 0.42, 0.55, 0.55), 1.0)

	# ── 格子（2列 × 5行） ──
	for i in SLOT_COUNT:
		var col    := i % SLOT_COLS
		var row    := i / SLOT_COLS
		var sx     := float(PANEL_PAD + col * (SLOT_SIZE + SLOT_GAP_X))
		var sy     := float(TITLE_H   + row * (SLOT_SIZE + SLOT_GAP_Y))
		var rect   := Rect2(sx, sy, SLOT_SIZE, SLOT_SIZE)
		var center := Vector2(sx + SLOT_SIZE * 0.5, sy + SLOT_SIZE * 0.5)

		# 格子底色
		draw_rect(rect, SLOT_BG_COLOR, true)
		# 内顶高光
		draw_line(Vector2(sx + 1, sy + 1), Vector2(sx + SLOT_SIZE - 1, sy + 1),
				Color(1, 1, 1, 0.07), 1.0)
		# 边框
		draw_rect(rect, SLOT_BORDER_COLOR, false, 1.0)

		var item: LootItem = _slots[i]
		if item != null:
			# 阴影圆
			draw_circle(center + Vector2(0, 1), 15.0, ICON_SHADOW_COLOR)
			# 主色圆
			draw_circle(center, 15.0, item.icon_color)
			# 高光弧
			draw_arc(center, 15.0, deg_to_rad(200), deg_to_rad(340),
					20, ICON_SHINE_COLOR, 3.0)
			# 描边
			draw_arc(center, 15.0, 0, TAU, 32, Color(0, 0, 0, 0.35), 1.0)
			# 名称文字（底部居中，带阴影）
			var lbl   := item.label if item.label.length() <= 3 else item.label.substr(0, 3)
			var lbl_x := sx + (SLOT_SIZE - float(lbl.length()) * 8.0) * 0.5
			draw_string(font, Vector2(lbl_x + 1, sy + SLOT_SIZE - 3),
					lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(0, 0, 0, 0.7))
			draw_string(font, Vector2(lbl_x, sy + SLOT_SIZE - 4),
					lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 1.0))
		else:
			# 空格：小十字占位
			draw_line(Vector2(center.x - 5, center.y), Vector2(center.x + 5, center.y),
					SLOT_EMPTY_COLOR, 1.2)
			draw_line(Vector2(center.x, center.y - 5), Vector2(center.x, center.y + 5),
					SLOT_EMPTY_COLOR, 1.2)


# ─────────────────────────────────────────────────────────────
# 积分汇总
# ─────────────────────────────────────────────────────────────

## 计算当前背包中所有战利品的积分总和。
func get_total_score() -> int:
	var total := 0
	for i in SLOT_COUNT:
		if _slots[i] != null:
			total += (_slots[i] as LootItem).score
	return total
