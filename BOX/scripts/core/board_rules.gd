class_name BoardRules
extends RefCounted

const ACTIONS := ["UP", "DOWN", "LEFT", "RIGHT", "MIRROR"]
const DIRECTIONS := {
	"UP": Vector2i(0, -1),
	"DOWN": Vector2i(0, 1),
	"LEFT": Vector2i(-1, 0),
	"RIGHT": Vector2i(1, 0)
}

static func in_bounds(level: LevelData, cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < level.width and cell.y < level.height

static func key(cell: Vector2i) -> String:
	return "%d,%d" % [cell.x, cell.y]

static func is_water(level: LevelData, state: BoardState, cell: Vector2i) -> bool:
	return level.terrain_at(cell) == "~" and not state.has_bridge(cell)

static func is_walkable(level: LevelData, state: BoardState, cell: Vector2i) -> bool:
	if not in_bounds(level, cell):
		return false
	var terrain := level.terrain_at(cell)
	return terrain == "." or state.has_bridge(cell)

static func player_records(state: BoardState) -> Array:
	var records: Array = state.players.duplicate(true)
	if records.is_empty() and state.failed:
		return []
	if records.is_empty() and state.player.x >= 0:
		return [{"id": "player_01", "position": state.player, "alive": true}]
	if records.size() == 1 and state.player != records[0].get("position", Vector2i(-1, -1)):
		records[0]["position"] = state.player
	return records

static func mirror_records(state: BoardState) -> Array:
	var records: Array = state.mirrors.duplicate(true)
	if records.is_empty() and not state.mirror.is_empty():
		return [state.mirror.duplicate(true)]
	if records.size() == 1 and not state.mirror.is_empty():
		var alias_position: Vector2i = state.mirror.get("position", Vector2i(-1, -1))
		if alias_position != records[0].get("position", Vector2i(-1, -1)) or str(state.mirror.get("orientation", "backslash")) != str(records[0].get("orientation", "backslash")):
			records[0] = state.mirror.duplicate(true)
	return records

static func entity_at(state: BoardState, cell: Vector2i) -> String:
	if not state.crate_at(cell).is_empty():
		return "CRATE"
	if not _mirror_at(state, cell).is_empty():
		return "MIRROR"
	if not _player_at(state, cell).is_empty():
		return "PLAYER"
	return ""

static func get_reflection_preview(level: LevelData, state: BoardState) -> Dictionary:
	var pairs: Array = []
	var sources: Array = []
	for player_record in player_records(state):
		sources.append({"type": "PLAYER", "record": player_record})
	for crate_record in state.crates:
		sources.append({"type": "CRATE", "record": crate_record})
	var mirrors_list := mirror_records(state)
	for source in sources:
		var source_record: Dictionary = source.get("record", {})
		var source_pos: Vector2i = source_record.get("position", Vector2i(-1, -1))
		var source_id := str(source_record.get("id", ""))
		for mirror_record in mirrors_list:
			var mirror_pos: Vector2i = mirror_record.get("position", Vector2i(-1, -1))
			var mirror_id := str(mirror_record.get("id", "mirror_01"))
			if source_pos == mirror_pos:
				continue
			if source_pos.x != mirror_pos.x and source_pos.y != mirror_pos.y:
				continue
			var target := _reflection_target(mirror_pos, source_pos, str(mirror_record.get("orientation", "backslash")))
			var status := "valid"
			var reason := "OK"
			if not has_clear_reflection_line(level, state, source_pos, mirror_pos):
				status = "invalid"
				reason = "BLOCKED_LINE"
			elif not has_clear_reflection_ray(level, state, mirror_pos, target, str(source.get("type", "")), source_id):
				status = "invalid"
				reason = "BLOCKED_RAY"
			elif not in_bounds(level, target) or is_water(level, state, target):
				# 海面是危险目标：预览用黄色，但 Space 仍然会执行。
				status = "danger"
				reason = "DEST_WATER"
			elif level.terrain_at(target) == "#":
				status = "invalid"
				reason = "DEST_WALL"
			elif entity_at_except(state, target, str(source.get("type", "")), source_id) != "":
				status = "invalid"
				reason = "DEST_OCCUPIED"
			pairs.append({
				"source_type": str(source.get("type", "")),
				"source_id": source_id,
				"source_position": source_pos,
				"mirror_id": mirror_id,
				"mirror_position": mirror_pos,
				"target": target,
				"status": status,
				"reason": reason
			})
	var accepted := false
	for pair in pairs:
		if str(pair.get("status", "invalid")) != "invalid":
			accepted = true
			break
	var reason := "NO_REFLECTION"
	if not pairs.is_empty() and not accepted:
		reason = str(pairs[0].get("reason", "BLOCKED_LINE"))
	return {"accepted": accepted, "reason": reason, "pairs": pairs}

## Backward-compatible single-player preview API used by old tests and UI callers.
static func get_mirror_preview(level: LevelData, state: BoardState) -> Dictionary:
	var reflection := get_reflection_preview(level, state)
	for pair in reflection.get("pairs", []):
		if str(pair.get("source_type", "")) != "PLAYER":
			continue
		var status := str(pair.get("status", "invalid"))
		return {
			"target": pair.get("target", Vector2i(-1, -1)),
			"valid": status == "valid",
			"danger": status == "danger",
			"reason": str(pair.get("reason", "NO_REFLECTION"))
		}
	var players := player_records(state)
	if players.is_empty() or mirror_records(state).is_empty():
		return {"target": Vector2i(-1, -1), "valid": false, "reason": "NO_MIRROR"}
	return {"target": Vector2i(-1, -1), "valid": false, "reason": str(reflection.get("reason", "NOT_ALIGNED"))}

static func has_clear_mirror_line(level: LevelData, state: BoardState, mirror_pos: Vector2i) -> bool:
	return has_clear_reflection_line(level, state, state.player, mirror_pos)

static func has_clear_reflection_line(level: LevelData, state: BoardState, source_pos: Vector2i, mirror_pos: Vector2i) -> bool:
	return first_reflection_line_blocker(level, state, source_pos, mirror_pos).x < 0

static func first_reflection_line_blocker(level: LevelData, state: BoardState, source_pos: Vector2i, mirror_pos: Vector2i) -> Vector2i:
	if source_pos.x != mirror_pos.x and source_pos.y != mirror_pos.y:
		return Vector2i(-1, -1)
	var step := Vector2i.ZERO
	if source_pos.x == mirror_pos.x:
		step = Vector2i(0, 1 if mirror_pos.y > source_pos.y else -1)
	else:
		step = Vector2i(1 if mirror_pos.x > source_pos.x else -1, 0)
	var cursor := source_pos + step
	while cursor != mirror_pos:
		# 水面不遮挡镜面视线；墙体和其他实体才会截断光路。
		if (in_bounds(level, cursor) and level.terrain_at(cursor) == "#") or entity_at(state, cursor) != "":
			return cursor
		cursor += step
	return Vector2i(-1, -1)

static func has_clear_reflection_ray(level: LevelData, state: BoardState, mirror_pos: Vector2i, target: Vector2i, excluded_type: String = "", excluded_id: String = "") -> bool:
	return first_reflection_ray_blocker(level, state, mirror_pos, target, excluded_type, excluded_id).x < 0

static func first_reflection_ray_blocker(level: LevelData, state: BoardState, mirror_pos: Vector2i, target: Vector2i, excluded_type: String = "", excluded_id: String = "") -> Vector2i:
	var delta := target - mirror_pos
	if delta.x != 0 and delta.y != 0:
		return Vector2i(-1, -1)
	if delta == Vector2i.ZERO:
		return Vector2i(-1, -1)
	var step := Vector2i.ZERO
	if delta.x != 0:
		step = Vector2i(1 if delta.x > 0 else -1, 0)
	else:
		step = Vector2i(0, 1 if delta.y > 0 else -1)
	var cursor := mirror_pos + step
	while cursor != target:
		if in_bounds(level, cursor):
			if level.terrain_at(cursor) == "#":
				return cursor
			if entity_at_except(state, cursor, excluded_type, excluded_id) != "":
				return cursor
		cursor += step
	if in_bounds(level, target) and level.terrain_at(target) == "#":
		return target
	return Vector2i(-1, -1)

static func entity_at_except(state: BoardState, cell: Vector2i, excluded_type: String, excluded_id: String) -> String:
	var crate := state.crate_at(cell)
	if not crate.is_empty() and not (excluded_type == "CRATE" and str(crate.get("id", "")) == excluded_id):
		return "CRATE"
	var mirror := _mirror_at(state, cell)
	if not mirror.is_empty() and not (excluded_type == "MIRROR" and str(mirror.get("id", "")) == excluded_id):
		return "MIRROR"
	var player := _player_at(state, cell)
	if not player.is_empty() and not (excluded_type == "PLAYER" and str(player.get("id", "")) == excluded_id):
		return "PLAYER"
	return ""

static func apply_action(level: LevelData, state: BoardState, action: String) -> Dictionary:
	if state.won:
		return {"accepted": false, "reason": "WON", "next_state": state, "events": []}
	if state.failed or player_records(state).is_empty():
		return {"accepted": false, "reason": "NO_PLAYERS", "next_state": state, "events": []}
	var normalized := action.to_upper()
	if normalized == "MIRROR":
		return _apply_reflection(level, state)
	if not DIRECTIONS.has(normalized):
		return {"accepted": false, "reason": "UNKNOWN_ACTION", "next_state": state, "events": []}
	return _apply_move(level, state, normalized, DIRECTIONS[normalized])

static func _apply_reflection(level: LevelData, state: BoardState) -> Dictionary:
	var preview := get_reflection_preview(level, state)
	if not bool(preview.get("accepted", false)):
		return {"accepted": false, "reason": str(preview.get("reason", "NO_REFLECTION")), "next_state": state, "events": []}
	var pairs: Array = preview.get("pairs", [])
	var by_source := {}
	for pair in pairs:
		var status := str(pair.get("status", "invalid"))
		if status == "invalid":
			continue
		var source_key := str(pair.get("source_type", "")) + ":" + str(pair.get("source_id", ""))
		if not by_source.has(source_key):
			by_source[source_key] = []
		by_source[source_key].append(pair)
	var next_state := state.duplicate_state()
	var next_players: Array = []
	var next_crates: Array = []
	var submerged: Array = []
	var splash_cells: Array = []
	var created := 0
	for player_record in player_records(state):
		var player_source_key := "PLAYER:" + str(player_record.get("id", ""))
		var player_source_pairs: Array = by_source.get(player_source_key, [])
		var successful := 0
		for pair in player_source_pairs:
			var target: Vector2i = pair.get("target", Vector2i(-1, -1))
			var status := str(pair.get("status", "invalid"))
			if status == "danger":
				_append_unique_cell(splash_cells, target)
				successful += 1
				created += 1
			else:
				var copy: Dictionary = player_record.duplicate(true)
				copy["id"] = str(player_record.get("id", "player_01")) + "__" + str(pair.get("mirror_id", "mirror_01"))
				copy["position"] = target
				copy["alive"] = true
				_append_unique_entity(next_players, copy)
				successful += 1
				created += 1
		if successful == 0:
			_append_unique_entity(next_players, player_record.duplicate(true))
	for crate_record in state.crates:
		var crate_source_key := "CRATE:" + str(crate_record.get("id", ""))
		var crate_source_pairs: Array = by_source.get(crate_source_key, [])
		var successful := 0
		for pair in crate_source_pairs:
			var target: Vector2i = pair.get("target", Vector2i(-1, -1))
			var status := str(pair.get("status", "invalid"))
			if status == "danger":
				if in_bounds(level, target):
					next_state.add_bridge(target)
				var submerged_crate: Dictionary = crate_record.duplicate(true)
				submerged_crate["position"] = target
				_append_unique_entity(submerged, submerged_crate)
				_append_unique_cell(splash_cells, target)
				successful += 1
				created += 1
			else:
				var copy: Dictionary = crate_record.duplicate(true)
				copy["id"] = str(crate_record.get("id", "crate_01")) + "__" + str(pair.get("mirror_id", "mirror_01"))
				copy["position"] = target
				_append_unique_entity(next_crates, copy)
				successful += 1
				created += 1
		if successful == 0:
			_append_unique_entity(next_crates, crate_record.duplicate(true))
	next_state.players = next_players
	next_state.crates = next_crates
	next_state.action_count += 1
	next_state.reflection_count += 1
	next_state.failed = next_state.players.is_empty()
	next_state.sync_compatibility()
	next_state.won = is_won(level, next_state)
	return {
		"accepted": created > 0,
		"reason": "OK",
		"next_state": next_state,
		"events": ["REFLECTION", "TELEPORT"],
		"reflection": {"pairs": pairs, "created": created},
		"submerged_crates": submerged,
		"splash_cells": splash_cells
	}

static func _ordered_player_indices(players: Array, delta: Vector2i) -> Array:
	var order: Array = []
	for i in range(players.size()):
		order.append(i)
	# Resolve the player furthest along the movement direction first.
	for i in range(1, order.size()):
		var current_index: int = order[i]
		var current_priority := _movement_priority(players[current_index], delta)
		var j := i - 1
		while j >= 0 and _movement_priority(players[order[j]], delta) < current_priority:
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = current_index
	return order


static func _movement_priority(player_record: Dictionary, delta: Vector2i) -> int:
	var position: Vector2i = player_record.get("position", Vector2i(-1, -1))
	return position.x * delta.x + position.y * delta.y


static func _append_unique_entity(records: Array, record: Dictionary) -> void:
	var position: Vector2i = record.get("position", Vector2i(-1, -1))
	for existing in records:
		var existing_position: Vector2i = existing.get("position", Vector2i(-1, -1))
		if existing_position == position:
			return
	records.append(record)

static func _append_unique_cell(cells: Array, cell: Vector2i) -> void:
	if cell in cells:
		return
	cells.append(cell)

static func _apply_move(level: LevelData, state: BoardState, normalized: String, delta: Vector2i) -> Dictionary:
	var next_state := state.duplicate_state()
	var records := player_records(state)
	next_state.players = records.duplicate(true)
	var pushes: Array = []
	var events: Array = []
	var submerged: Array = []
	var splash_cells: Array = []
	var changed := false
	var move_order: Array = _ordered_player_indices(next_state.players, delta)
	for i in move_order:
		var player_record: Dictionary = next_state.players[i]
		var current_pos: Vector2i = player_record.get("position", Vector2i(-1, -1))
		var destination := current_pos + delta
		var entity := entity_at(next_state, destination)
		if entity == "PLAYER":
			continue
		if entity == "":
			if is_walkable(level, next_state, destination):
				player_record["position"] = destination
				changed = true
			continue
		var pushed_to := destination + delta
		if not in_bounds(level, pushed_to) or entity_at(next_state, pushed_to) != "":
			continue
		if entity == "CRATE":
			if is_water(level, next_state, pushed_to):
				var pushed_crate: Dictionary = next_state.crate_at(destination).duplicate(true)
				next_state.remove_crate_at(destination)
				next_state.add_bridge(pushed_to)
				var submerged_crate: Dictionary = pushed_crate.duplicate(true)
				submerged_crate["position"] = pushed_to
				submerged.append(submerged_crate)
				splash_cells.append(pushed_to)
			else:
				if not is_walkable(level, next_state, pushed_to):
					continue
				var crate := next_state.crate_at(destination)
				crate["position"] = pushed_to
			var push_info := {"entity_id": str(pushed_crate_id(state, destination)), "direction": normalized, "special": not submerged.is_empty() and splash_cells.back() == pushed_to}
			pushes.append(push_info)
			if not "PUSH_CRATE" in events:
				events.append("PUSH_CRATE")
			if push_info.special and not "BRIDGE" in events:
				events.append("BRIDGE")
			player_record["position"] = destination
			changed = true
		elif entity == "MIRROR":
			if not is_walkable(level, next_state, pushed_to):
				continue
			var pushed_mirror := _mirror_at(next_state, destination)
			if pushed_mirror.is_empty():
				continue
			pushed_mirror["position"] = pushed_to
			pushes.append({"entity_id": str(pushed_mirror.get("id", "mirror_01")), "direction": normalized, "special": false})
			if not "PUSH_MIRROR" in events:
				events.append("PUSH_MIRROR")
			player_record["position"] = destination
			changed = true
	if not changed:
		return {"accepted": false, "reason": reason_for_cell(level, state, state.player + delta), "next_state": state, "events": []}
	next_state.action_count += 1
	next_state.push_count += pushes.size()
	next_state.sync_compatibility()
	next_state.won = is_won(level, next_state)
	if pushes.is_empty():
		events.append("MOVE")
	var result := {
		"accepted": true,
		"reason": "OK",
		"next_state": next_state,
		"events": events,
		"pushes": pushes,
		"submerged_crates": submerged,
		"splash_cells": splash_cells
	}
	if pushes.size() == 1:
		result["push"] = pushes[0]
	if submerged.size() == 1:
		result["submerged_crate"] = submerged[0]
	if splash_cells.size() == 1:
		result["splash_cell"] = splash_cells[0]
	return result

static func pushed_crate_id(state: BoardState, cell: Vector2i) -> String:
	var crate := state.crate_at(cell)
	return str(crate.get("id", ""))

static func reason_for_cell(level: LevelData, state: BoardState, cell: Vector2i) -> String:
	if not in_bounds(level, cell):
		return "DEST_WATER"
	if entity_at(state, cell) != "":
		return "DEST_OCCUPIED"
	if level.terrain_at(cell) == "~" and not state.has_bridge(cell):
		return "DEST_WATER"
	if level.terrain_at(cell) == "#":
		return "DEST_WALL"
	return "BLOCKED"

static func is_won(level: LevelData, state: BoardState) -> bool:
	if state.failed:
		return false
	if not are_goals_complete(level, state):
		return false
	if level.exit_cell.x < 0:
		return false
	for player_record in player_records(state):
		if player_record.get("position", Vector2i(-1, -1)) == level.exit_cell:
			return true
	return state.player == level.exit_cell

static func are_goals_complete(level: LevelData, state: BoardState) -> bool:
	if level.goals.is_empty():
		return true
	for goal in level.goals:
		if state.crate_at(goal).is_empty():
			return false
	return true

static func apply_sequence(level: LevelData, state: BoardState, actions: Array) -> Dictionary:
	var current := state
	var accepted := 0
	for action in actions:
		var result := apply_action(level, current, str(action))
		if not bool(result.accepted):
			return {"accepted": false, "count": accepted, "reason": str(result.reason), "state": current}
		accepted += 1
		current = result.next_state
	return {"accepted": true, "count": accepted, "reason": "OK", "state": current}

static func _reflection_target(mirror_pos: Vector2i, source_pos: Vector2i, orientation: String) -> Vector2i:
	var delta := source_pos - mirror_pos
	# The editor's orientation value follows the visible mirror material. The
	# requested artwork uses the opposite diagonal from the old prototype.
	return mirror_pos + (Vector2i(delta.y, delta.x) if orientation == "slash" else Vector2i(-delta.y, -delta.x))

static func _player_at(state: BoardState, cell: Vector2i) -> Dictionary:
	for player_record in player_records(state):
		if player_record.get("position", Vector2i(-1, -1)) == cell:
			return player_record
	return {}

static func _mirror_at(state: BoardState, cell: Vector2i) -> Dictionary:
	# This helper is used by movement as well as read-only previews. Return the
	# live record so a player can actually push a mirror in the current state.
	for mirror_record in state.mirrors:
		if mirror_record.get("position", Vector2i(-1, -1)) == cell:
			return mirror_record
	if state.mirrors.is_empty() and not state.mirror.is_empty() and state.mirror.get("position", Vector2i(-1, -1)) == cell:
		return state.mirror
	return {}
