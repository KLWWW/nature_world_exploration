extends Node2D

# 玩家场景资源，由主场景负责实例化并接入流程。
const PLAYER_SCENE = preload("res://Player.tscn")
const TerrainType  = preload("res://Script/TerrainType.gd")
const POIType      = preload("res://Script/POIType.gd")
const POI          = preload("res://Script/POI.gd")
const LootItem     = preload("res://Script/LootItem.gd")
const LootBar      = preload("res://Script/LootBar.gd")
const FloatLabel   = preload("res://Script/FloatLabel.gd")

# 体力上限。
const MAX_STAMINA := 100
# 泡泡上限。
const MAX_BUBBLES := 30

# 当前场景中的玩家节点。
var _player
# 玩家当前所在的六边形 cube 坐标。
var _player_cube: Vector3i = Vector3i.ZERO
# 是否正处于整条路径移动流程中，用于阻止重复输入。
var _is_moving := false
# 玩家当前体力值。
var _stamina: int = MAX_STAMINA
# 玩家当前泡泡数量。
var _bubbles: int = MAX_BUBBLES

# 正式移动路径上仍处于高亮状态的格子节点。
var _path_nodes: Array = []
# 当前视野范围内的 cube 坐标列表（迷雾系统用）。
var _visible_cubes: Array = []
# 鼠标悬停预览路径上正在高亮的格子节点。
var _preview_nodes: Array = []
# 当前被玩家占据的格子节点。
var _occupied_node = null
# 当前移动的起点格节点，用于显示起点状态。
var _origin_node = null

# ── 改造环境技能状态 ──────────────────────────────────────
# 是否处于技能施法待机状态（等待玩家点击目标格）。
var _terraform_casting: bool = false
# 当前技能范围预览覆盖的格子节点列表。
var _terraform_range_nodes: Array = []
# 上一次技能预览的中心格，避免每帧重复刷新。
var _terraform_last_center: Variant = null

# 地图层，负责地图生成、坐标换算和寻路。
@onready var _hex_grid = $HexGrid
# 输入层，负责把鼠标操作转换成场景意图。
@onready var _input_controller = $InputController
# 摄像机节点，用于持续跟随玩家。
@onready var _camera: Camera2D = $Camera2D
# 体力 UI 条。
@onready var _stamina_bar = $UILayer/StaminaBar
# 泡泡 UI 条。
@onready var _bubble_bar = $UILayer/BubbleBar
# Game Over 界面。
@onready var _game_over = $UILayer/GameOver
# 胜利界面。
@onready var _victory = $UILayer/Victory
# 战利品栏。
@onready var _loot_bar: LootBar = $UILayer/LootBar
# 罗盘（始终指向金字塔）。
@onready var _compass = $UILayer/Compass


# 初始化主场景：接入输入、生成地图、生成玩家，并处理视口居中。
func _ready() -> void:
	# 先保证主场景始终以视口中心为锚点。
	get_tree().root.size_changed.connect(_on_viewport_size_changed)
	_on_viewport_size_changed()

	# 输入层只负责把鼠标位置翻译成 cube 坐标，并把意图信号抛给 main。
	_input_controller.configure(func() -> Vector3i: return _hex_grid.world_to_cube(get_local_mouse_position()))
	_input_controller.hex_selected.connect(_on_hex_selected)
	_input_controller.hover_changed.connect(_on_hover_changed)

	# 地图和玩家都由主场景统一装配。
	_hex_grid.generate(_input_controller)
	# 连接 POI 触碰信号，由本场景统一处理游戏效果。
	_hex_grid.poi_triggered.connect(_on_poi_triggered)
	_spawn_player()
	# 初始化战争迷雾：全图遮黑，起点周围立刻揭示。
	_visible_cubes = []
	_hex_grid.init_fog(_player_cube)
	_visible_cubes = _hex_grid.get_area_cubes(_player_cube, _hex_grid.VISIBILITY_RADIUS)
	# 把地图种子传给罗盘，保证同一局内误差角确定性。
	_compass.set_seed(_hex_grid.map_seed)
	_stamina_bar.update_value(_stamina, MAX_STAMINA)
	_bubble_bar.update_value(_bubbles, MAX_BUBBLES)

	# 改造环境按钮：磨砂玻璃圆形风格
	var terraform_btn: Button = $UILayer/TerraformBtn
	# 字体颜色白色
	terraform_btn.add_theme_color_override("font_color",         Color(1.0, 1.0, 1.0, 0.95))
	terraform_btn.add_theme_color_override("font_hover_color",   Color(1.0, 1.0, 1.0, 1.00))
	terraform_btn.add_theme_color_override("font_pressed_color", Color(0.8, 0.95, 1.0, 1.00))

	var _make_btn_style = func(bg: Color, border: Color, shadow: Color) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.corner_radius_top_left     = 40
		s.corner_radius_top_right    = 40
		s.corner_radius_bottom_left  = 40
		s.corner_radius_bottom_right = 40
		s.content_margin_left   = 4
		s.content_margin_right  = 4
		s.content_margin_top    = 4
		s.content_margin_bottom = 4
		s.bg_color = bg
		s.border_color = border
		s.border_width_left   = 2
		s.border_width_right  = 2
		s.border_width_top    = 2
		s.border_width_bottom = 2
		s.shadow_color = shadow
		s.shadow_size  = 6
		s.shadow_offset = Vector2(0, 2)
		return s

	terraform_btn.add_theme_stylebox_override("normal",   _make_btn_style.call(
		Color(0.08, 0.10, 0.14, 0.72),   # 深色半透明底
		Color(1.00, 1.00, 1.00, 0.22),   # 白色细边框
		Color(0.00, 0.00, 0.00, 0.35)))  # 柔和阴影
	terraform_btn.add_theme_stylebox_override("hover",    _make_btn_style.call(
		Color(0.15, 0.18, 0.25, 0.85),   # 悬停：稍亮蓝灰底
		Color(1.00, 1.00, 1.00, 0.60),   # 边框明亮
		Color(0.40, 0.70, 1.00, 0.40)))  # 蓝色光晕
	terraform_btn.add_theme_stylebox_override("pressed",  _make_btn_style.call(
		Color(0.04, 0.06, 0.10, 0.90),   # 按下：更深更实
		Color(0.60, 0.90, 1.00, 0.80),   # 边框亮蓝
		Color(0.20, 0.50, 1.00, 0.50)))  # 按下发光
	terraform_btn.add_theme_stylebox_override("focus",    _make_btn_style.call(
		Color(0.08, 0.10, 0.14, 0.72),
		Color(0.60, 0.90, 1.00, 0.70),
		Color(0.20, 0.50, 1.00, 0.40)))
	terraform_btn.add_theme_stylebox_override("disabled", _make_btn_style.call(
		Color(0.08, 0.08, 0.10, 0.40),
		Color(1.00, 1.00, 1.00, 0.08),
		Color(0.00, 0.00, 0.00, 0.10)))


# 生成玩家并放到起点格。
func _spawn_player() -> void:
	_player_cube = _hex_grid.start_cube
	_player = PLAYER_SCENE.instantiate()
	_player.position = _hex_grid.get_world_position(_player_cube)
	_player.z_index = 1
	add_child(_player)
	_set_occupied_hex(_player_cube)


# 处理格子点击：施法待机时触发改造，否则正常寻路移动。
func _on_hex_selected(target_cube: Vector3i) -> void:
	# 施法待机状态：点击任意格子即以该格为中心释放技能。
	if _terraform_casting:
		_do_terraform(target_cube)
		return

	if _is_moving or target_cube == _player_cube:
		return

	var path: Array[Vector3i] = _hex_grid.find_path(_player_cube, target_cube)
	if path.size() <= 1:
		return

	# 计算整条路径的实际体力消耗（地形代价之和），不足则拒绝移动。
	var total_cost := 0
	for i in range(1, path.size()):
		total_cost += int(_hex_grid.get_move_cost(path[i]))
	if total_cost > _stamina:
		return

	_move_along_path(path)


# 编排一整次移动流程：切换高亮、命令玩家移动，并同步地图状态。
func _move_along_path(path: Array[Vector3i]) -> void:
	_is_moving = true

	# 进入正式移动前，先清掉悬停缓存和所有临时高亮，避免视觉状态串在一起。
	_input_controller.reset_hover()
	_clear_path_highlight()
	_clear_preview()

	# 旧占据格在移动开始时先取消，占据状态只保留给最终落脚格。
	if _occupied_node:
		_occupied_node.set_occupied(false)
		_occupied_node = null

	# 起点格在移动期间单独标记，和普通路径格区分开。
	_origin_node = _hex_grid.get_hex_node(path[0])
	if _origin_node:
		_origin_node.set_origin(true)

	# 先把整条路径的视觉状态铺出来，真正移动时再逐格熄灭。
	for i in range(1, path.size()):
		var node = _hex_grid.get_hex_node(path[i])
		if node:
			var is_target := i == path.size() - 1
			node.set_highlighted(true, is_target)
			_path_nodes.append(node)

	# 将路径拆成“要经过的 cube 列表”，方便在每一步完成后同步逻辑位置。
	var cubes_to_visit: Array[Vector3i] = []
	for i in range(1, path.size()):
		cubes_to_visit.append(path[i])

	# 将逻辑路径转换成玩家真正要行走的世界坐标路径。
	var world_points: Array[Vector2] = []
	for cube in cubes_to_visit:
		world_points.append(_hex_grid.get_world_position(cube))

	# Player 负责执行路径移动，main 只在每一步完成后同步逻辑状态。
	_player.move_along(world_points)
	for i in range(cubes_to_visit.size()):
		await _player.step_finished
		_player_cube = cubes_to_visit[i]

		# 每走一步扣除该格地形代价的体力，并实时更新 UI。
		var cost := int(_hex_grid.get_move_cost(cubes_to_visit[i]))
		_stamina -= cost
		_stamina_bar.update_value(_stamina, MAX_STAMINA)

		# 玩家真正走过这一格后，再关闭该格的路径高亮。
		var passed = _hex_grid.get_hex_node(cubes_to_visit[i])
		if passed:
			passed.set_highlighted(false)
			_path_nodes.erase(passed)

		# 落脚后更新战争迷雾：旧视野格降为已探索，新视野格设为可见。
		_visible_cubes = _hex_grid.update_fog(_visible_cubes, _player_cube)

		# 落脚后通知地图层检测 POI（会同步发出 poi_triggered 信号）。
		_hex_grid.notify_player_entered(_player_cube)

		# 每步落脚后通知罗盘（接口保留，当前逻辑已简化）。
		_compass.on_step(_player_cube, _hex_grid.finish_cube)

	# 移动收尾：去掉起点标记，恢复最终占据格，并重新开放输入。
	if _origin_node:
		_origin_node.set_origin(false)
		_origin_node = null

	_set_occupied_hex(_player_cube)
	_is_moving = false

	# 到达终点 → 胜利（优先于体力判定）
	if _player_cube == _hex_grid.finish_cube:
		_victory.show_victory(_loot_bar.get_total_score())
		return

	# 体力耗尽 → Game Over
	if _stamina <= 0:
		_game_over.show_game_over(_loot_bar.get_total_score())


# 更新玩家占据格：取消旧格占据状态，并设置新格占据状态。
func _set_occupied_hex(cube: Vector3i) -> void:
	if _occupied_node:
		_occupied_node.set_occupied(false)

	_occupied_node = _hex_grid.get_hex_node(cube)
	if _occupied_node:
		_occupied_node.set_occupied(true)


# 清空正式移动路径的高亮状态。
func _clear_path_highlight() -> void:
	for node in _path_nodes:
		node.set_highlighted(false)
	_path_nodes.clear()


# 每帧让摄像机跟随玩家当前位置，同时刷新罗盘指向金字塔的方向。
func _process(delta: float) -> void:
	if _player:
		_camera.position = _player.position
		# 罗盘：传入 cube 坐标（算格子步数准确度）+ 世界坐标（算方向角）。
		var pyramid_world: Vector2 = _hex_grid.get_world_position(_hex_grid.finish_cube)
		_compass.update_direction(_player_cube, _hex_grid.finish_cube, _player.position, pyramid_world, delta)


# 处理鼠标悬停变化：施法待机时刷新范围预览，否则显示寻路预览。
func _on_hover_changed(mouse_cube: Variant) -> void:
	# 施法待机状态：跟随鼠标实时更新技能落点范围高亮。
	if _terraform_casting:
		if mouse_cube is Vector3i and _hex_grid.has_cube(mouse_cube):
			_refresh_terraform_range(mouse_cube)
		else:
			_clear_terraform_range()
		return

	# 悬停变化时，先清掉上一条预览路径。
	_clear_preview()

	# 移动中、鼠标不在合法格子上、或悬停在玩家脚下时都不显示预览。
	if _is_moving:
		return
	if not (mouse_cube is Vector3i):
		return
	if not _hex_grid.has_cube(mouse_cube) or mouse_cube == _player_cube:
		return

	# 预览和正式移动共用同一套寻路结果，只是颜色和生命周期不同。
	var path: Array[Vector3i] = _hex_grid.find_path(_player_cube, mouse_cube)
	for i in range(1, path.size()):
		var node = _hex_grid.get_hex_node(path[i])
		if node:
			node.set_preview_highlighted(true, i == path.size() - 1)
			_preview_nodes.append(node)


# 清空鼠标悬停产生的预览高亮。
func _clear_preview() -> void:
	for node in _preview_nodes:
		node.set_preview_highlighted(false)
	_preview_nodes.clear()


# ── 改造环境技能（指向性） ────────────────────────────────

# 点击按钮：切换施法待机状态。已在 casting 时再点则取消。
func _on_terraform_pressed() -> void:
	if _is_moving:
		return
	if _terraform_casting:
		_cancel_terraform()
	else:
		_begin_terraform()


# 进入施法待机：清掉寻路预览，屏蔽普通移动点击，等待玩家指定目标格。
func _begin_terraform() -> void:
	_terraform_casting = true
	_clear_preview()
	_terraform_last_center = null
	# 重置悬停，让 hover_changed 下一帧立刻刷新范围预览。
	_input_controller.reset_hover()


# 取消施法待机：清除所有范围高亮，恢复普通状态。
func _cancel_terraform() -> void:
	_terraform_casting = false
	_clear_terraform_range()
	_terraform_last_center = null
	_input_controller.reset_hover()


# 每帧检测右键，右键取消施法。
func _input(event: InputEvent) -> void:
	if _terraform_casting and event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_cancel_terraform()


# 处理施法状态下的格子点击：以目标格为中心触发改造，消耗 3 个皮克敏。
func _do_terraform(target_cube: Vector3i) -> void:
	# 皮克敏不足时拒绝释放。
	if _bubbles < 3:
		_cancel_terraform()
		return

	var area: Array[Vector3i] = _hex_grid.get_area_cubes(target_cube, 1)
	for cube in area:
		if _hex_grid.get_terrain(cube) == TerrainType.DESERT:
			_hex_grid.set_terrain(cube, TerrainType.PLAIN)

	_bubbles -= 3
	_bubble_bar.update_value(_bubbles, MAX_BUBBLES)
	_cancel_terraform()


# 刷新技能范围预览高亮（以 center 为中心的一圈范围轮廓）。
func _refresh_terraform_range(center: Vector3i) -> void:
	if _terraform_last_center == center:
		return
	_clear_terraform_range()
	_terraform_last_center = center
	var area: Array[Vector3i] = _hex_grid.get_area_cubes(center, 1)
	for cube in area:
		var node = _hex_grid.get_hex_node(cube)
		if node:
			node.set_terraform_ranged(true)
			_terraform_range_nodes.append(node)


# 清除所有技能范围预览高亮。
func _clear_terraform_range() -> void:
	for node in _terraform_range_nodes:
		if is_instance_valid(node):
			node.set_terraform_ranged(false)
	_terraform_range_nodes.clear()


# 恢复 20 体力（不超过上限）。
func _on_restore_pressed() -> void:
	_stamina = mini(_stamina + 20, MAX_STAMINA)
	_stamina_bar.update_value(_stamina, MAX_STAMINA)


# 直接触发 Game Over。
func _on_game_over_pressed() -> void:
	_stamina = 0
	_stamina_bar.update_value(_stamina, MAX_STAMINA)
	_game_over.show_game_over(_loot_bar.get_total_score())


## DEBUG：去除全图迷雾，将所有格子设为可见状态。
## 同步更新 _visible_cubes，防止玩家移动后迷雾重新出现。
func _on_reveal_all_pressed() -> void:
	_hex_grid.reveal_all()


# 当视口尺寸变化时，让整张棋盘场景重新居中。
func _on_viewport_size_changed() -> void:
	position = get_viewport_rect().size * 0.5


# ── POI 触碰事件 ────────────────────────────────────────────

## 玩家踏入 POI 格时由 HexGrid.poi_triggered 信号触发。
## 按 POI 类型分发对应的游戏效果，每个 POI 只触发一次（触发后 HexGrid 会移除）。
func _on_poi_triggered(poi: POI, _cube: Vector3i) -> void:
	match poi.poi_type:
		POIType.CAVE:
			_on_poi_cave()
		POIType.SHRINE:
			_on_poi_shrine()
		POIType.SPRING:
			_on_poi_spring()


## 在玩家头上生成浮动提示文字。
func _show_float_text(text: String) -> void:
	if _player:
		FloatLabel.spawn(self, text, _player.position)


## 神殿效果：固定获得 1 件随机战利品。
func _on_poi_shrine() -> void:
	var idx := randi() % LOOT_TABLE.size()
	add_loot_by_index(idx)
	_show_float_text("🏛 获得《%s》" % LOOT_TABLE[idx][0])


## 山洞效果：随机触发三种结果之一。
##   0 → 体力 -5（暗无天日，气力消耗）
##   1 → 泡泡 +5（发现神秘泡泡）
##   2 → 获得 1 件随机战利品
func _on_poi_cave() -> void:
	match randi() % 3:
		0:
			_stamina = maxi(_stamina - 5, 0)
			_stamina_bar.update_value(_stamina, MAX_STAMINA)
			_show_float_text("🕳 体力 -5")
		1:
			_bubbles = mini(_bubbles + 5, MAX_BUBBLES)
			_bubble_bar.update_value(_bubbles, MAX_BUBBLES)
			_show_float_text("🫧 泡泡 +5")
		2:
			var idx := randi() % LOOT_TABLE.size()
			add_loot_by_index(idx)
			_show_float_text("🕳 获得《%s》" % LOOT_TABLE[idx][0])


## 泉水效果：固定体力 +5、泡泡 +5。
func _on_poi_spring() -> void:
	_stamina = mini(_stamina + 5, MAX_STAMINA)
	_stamina_bar.update_value(_stamina, MAX_STAMINA)
	_bubbles = mini(_bubbles + 5, MAX_BUBBLES)
	_bubble_bar.update_value(_bubbles, MAX_BUBBLES)
	_show_float_text("💧 体力 +5  泡泡 +5")


# ── 战利品 ────────────────────────────────────────────────

## 预定义战利品表（名称、描述、颜色、积分）。
## 每种战利品积分暂时统一为 100 分。
const LOOT_TABLE := [
	# [名称,         描述,                       颜色,                              积分]
	["狗头金",   "一块天然形成的金块，金光闪闪。", Color(1.00, 0.80, 0.10, 1.0), 100],
	["水晶碎片", "折射七彩光芒的透明晶体碎片。", Color(0.55, 0.85, 1.00, 1.0), 100],
	["黄金权杖", "古代王者遗落的权杖，镶嵌宝石。", Color(0.95, 0.70, 0.05, 1.0), 100],
	["翡翠玉佩", "温润如玉，散发淡淡绿光。",     Color(0.20, 0.80, 0.45, 1.0), 100],
	["紫晶球",   "内含神秘漩涡的深紫色水晶球。", Color(0.60, 0.20, 0.90, 1.0), 100],
	["珊瑚宝珠", "来自深海的稀有红色珊瑚珠。",   Color(0.95, 0.30, 0.25, 1.0), 100],
]

## 向战利品栏添加指定类型的战利品（按 LOOT_TABLE 索引）。
## 返回 true 表示成功放入，false 表示背包已满或索引越界。
func add_loot_by_index(loot_index: int) -> bool:
	if loot_index < 0 or loot_index >= LOOT_TABLE.size():
		return false
	var entry = LOOT_TABLE[loot_index]
	return add_loot_to_bar(entry[0], entry[1], entry[2], entry[3])


## 向战利品栏添加一件战利品（自定义参数）。
## 返回 true 表示成功放入，false 表示战利品栏已满。
func add_loot_to_bar(p_label: String, p_description: String, p_color: Color, p_score: int = 100) -> bool:
	var item := LootItem.new(p_label, p_description, p_color, p_score)
	var ok := _loot_bar.add_loot(item)
	if ok:
		print("[战利品] 获得：%s（+%d分）" % [p_label, p_score])
	else:
		print("[战利品] 背包已满，无法放入：", p_label)
	return ok
