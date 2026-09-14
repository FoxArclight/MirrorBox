class_name BoardState
extends RefCounted

## Compatibility aliases kept for the original one-player/one-mirror levels.
var player: Vector2i = Vector2i.ZERO
var players: Array = []
var crates: Array = []
var mirror: Dictionary = {}
var mirrors: Array = []
var bridges: Dictionary = {}
var action_count: int = 0
var push_count: int = 0
var reflection_count: int = 0
var won: bool = false
var failed: bool = false

static func from_level(level: LevelData) -> BoardState:
	var state := BoardState.new()
	state.players = level.players.duplicate(true)
	if state.players.size() == 1 and level.player != state.players[0].get("position", Vector2i(-1, -1)):
		if level.player.x < 0:
			state.players.clear()
		else:
			state.players[0]["position"] = level.player
	if state.players.is_empty() and level.player.x >= 0:
		state.players = [{"id": "player_01", "position": level.player, "alive": true}]
	state.player = level.player
	state.crates = level.crates.duplicate(true)
	state.mirrors = level.mirrors.duplicate(true)
	if state.mirrors.size() == 1 and level.mirror.is_empty():
		state.mirrors.clear()
	elif state.mirrors.size() == 1 and not level.mirror.is_empty() and (level.mirror.get("position", Vector2i(-1, -1)) != state.mirrors[0].get("position", Vector2i(-1, -1)) or str(level.mirror.get("orientation", "backslash")) != str(state.mirrors[0].get("orientation", "backslash"))):
		state.mirrors = [level.mirror.duplicate(true)]
	if state.mirrors.is_empty() and not level.mirror.is_empty():
		state.mirrors = [level.mirror.duplicate(true)]
	state.mirror = level.mirror.duplicate(true)
	state.bridges = {}
	state.action_count = 0
	state.push_count = 0
	state.reflection_count = 0
	state.won = false
	state.failed = state.players.is_empty()
	state.sync_compatibility()
	return state

func duplicate_state() -> BoardState:
	var next := BoardState.new()
	next.player = player
	next.players = players.duplicate(true)
	next.crates = crates.duplicate(true)
	next.mirror = mirror.duplicate(true)
	next.mirrors = mirrors.duplicate(true)
	next.bridges = bridges.duplicate(true)
	next.action_count = action_count
	next.push_count = push_count
	next.reflection_count = reflection_count
	next.won = won
	next.failed = failed
	next.sync_compatibility()
	return next

func sync_compatibility() -> void:
	if not players.is_empty():
		player = players[0].get("position", player)
	if not mirrors.is_empty():
		mirror = mirrors[0].duplicate(true)

func bridge_key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

func has_bridge(cell: Vector2i) -> bool:
	return bridges.has(bridge_key(cell))

func add_bridge(cell: Vector2i) -> void:
	bridges[bridge_key(cell)] = [cell.x, cell.y]

func remove_crate_at(cell: Vector2i) -> void:
	for i in range(crates.size() - 1, -1, -1):
		if crates[i].get("position", Vector2i(-1, -1)) == cell:
			crates.remove_at(i)
			return

func crate_at(cell: Vector2i) -> Dictionary:
	for crate in crates:
		if crate.get("position", Vector2i(-1, -1)) == cell:
			return crate
	return {}

func player_at(cell: Vector2i) -> Dictionary:
	for player_record in players:
		if player_record.get("position", Vector2i(-1, -1)) == cell:
			return player_record
	if players.is_empty() and not failed and player == cell:
		return {"id": "player_01", "position": player, "alive": true}
	return {}

func mirror_at(cell: Vector2i) -> Dictionary:
	for mirror_record in mirrors:
		if mirror_record.get("position", Vector2i(-1, -1)) == cell:
			return mirror_record
	if mirrors.is_empty() and not mirror.is_empty() and mirror.get("position", Vector2i(-1, -1)) == cell:
		return mirror
	return {}

func remove_mirror_at(cell: Vector2i) -> void:
	for i in range(mirrors.size() - 1, -1, -1):
		if mirrors[i].get("position", Vector2i(-1, -1)) == cell:
			mirrors.remove_at(i)
			if i == 0:
				mirror = mirrors[0].duplicate(true) if not mirrors.is_empty() else {}
			return

func has_entity(cell: Vector2i) -> bool:
	return not crate_at(cell).is_empty() or not mirror_at(cell).is_empty() or not player_at(cell).is_empty()
