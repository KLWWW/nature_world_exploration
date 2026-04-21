class_name TerrainType
extends RefCounted

# Shared terrain identifiers used by generation, rules, and tile rendering.
enum {
	PLAIN,
	DESERT,
	MOUNTAIN,
	START,
	FINISH,
}

# 每种地形的揭示距离加成。
# 某格能否被发现 = REVEAL_RANGE[target] + 玩家视野半径 - 玩家与目标距离 >= 0
const REVEAL_RANGE := {
	PLAIN:    0,
	DESERT:   0,
	MOUNTAIN: 1,
	START:    0,
	FINISH:   0,
}
