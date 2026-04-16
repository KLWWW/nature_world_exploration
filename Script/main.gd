extends Node2D

# 玩家场景资源，由主场景负责实例化并接入流程。
const PLAYER_SCENE = preload("res://Player.tscn")

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
# 鼠标悬停预览路径上正在高亮的格子节点。
var _preview_nodes: Array = []
# 当前被玩家占据的格子节点。
var _occupied_node = null
# 当前移动的起点格节点，用于显示起点状态。
var _origin_node = null

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
	_spawn_player()
	_stamina_bar.update_value(_stamina, MAX_STAMINA)
	_bubble_bar.update_value(_bubbles, MAX_BUBBLES)


# 生成玩家并放到起点格。
func _spawn_player() -> void:
	_player_cube = _hex_grid.start_cube
	_player = PLAYER_SCENE.instantiate()
	_player.position = _hex_grid.get_world_position(_player_cube)
	_player.z_index = 1
	add_child(_player)
	_set_occupied_hex(_player_cube)


# 处理格子点击：决定是否寻路，以及是否开始正式移动。
func _on_hex_selected(target_cube: Vector3i) -> void:
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

	# 移动收尾：去掉起点标记，恢复最终占据格，并重新开放输入。
	if _origin_node:
		_origin_node.set_origin(false)
		_origin_node = null

	_set_occupied_hex(_player_cube)
	_is_moving = false

	# 到达终点 → 胜利（优先于体力判定）
	if _player_cube == _hex_grid.finish_cube:
		_victory.show_victory()
		return

	# 体力耗尽 → Game Over
	if _stamina <= 0:
		_game_over.show_game_over()


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


# 每帧让摄像机跟随玩家当前位置。
func _process(_delta: float) -> void:
	if _player:
		_camera.position = _player.position


# 处理鼠标悬停变化：决定是否显示预览路径，并刷新对应高亮。
func _on_hover_changed(mouse_cube: Variant) -> void:
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


# 恢复 20 体力（不超过上限）。
func _on_restore_pressed() -> void:
	_stamina = mini(_stamina + 20, MAX_STAMINA)
	_stamina_bar.update_value(_stamina, MAX_STAMINA)


# 直接触发 Game Over。
func _on_game_over_pressed() -> void:
	_stamina = 0
	_stamina_bar.update_value(_stamina, MAX_STAMINA)
	_game_over.show_game_over()


# 当视口尺寸变化时，让整张棋盘场景重新居中。
func _on_viewport_size_changed() -> void:
	position = get_viewport_rect().size * 0.5
