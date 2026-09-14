class_name LevelData
extends RefCounted

const SCHEMA_VERSION := 1
const MIN_BOARD_SIZE := 6
const MAX_BOARD_SIZE := 32

var schema_version: int = SCHEMA_VERSION
var id: String = "draft"
var title: String = "未命名关卡"
var description: String = ""
var width: int = 6
var height: int = 6
var terrain: Array = []
var player: Vector2i = Vector2i(-1, -1)
var players: Array = []
var crates: Array = []
var mirror: Dictionary = {}
var mirrors: Array = []
var goals: Array = []
var texts: Array = []
var exit_cell: Vector2i = Vector2i(-1, -1)
var solution: Array = []
var teaching_goal: String = ""

static func from_dict(data: Dictionary):
	var level = LevelData.new()
	level.schema_version = int(data.get("schema_version", SCHEMA_VERSION))
	level.id = str(data.get("id", "draft"))
	level.title = str(data.get("title", "未命名关卡"))
	level.description = str(data.get("description", ""))
	level.width = int(data.get("width", 6))
	level.height = int(data.get("height", 6))
	level.terrain.clear()
	for row in data.get("terrain", []):
		level.terrain.append(str(row))

	level.players.clear()
	var player_items: Array = data.get("players", []) if data.has("players") else []
	if player_items.is_empty() and data.get("player", null) is Array:
		player_items = [data.get("player")]
	for item in player_items:
		var player_record: Dictionary = {}
		var position_data = item
		if item is Dictionary:
			player_record = item.duplicate(true)
			position_data = player_record.get("position", [-1, -1])
		var position := Vector2i(-1, -1)
		if position_data is Array and position_data.size() >= 2:
			position = Vector2i(int(position_data[0]), int(position_data[1]))
		player_record["id"] = str(player_record.get("id", "player_%02d" % (level.players.size() + 1)))
		player_record["position"] = position
		player_record["alive"] = bool(player_record.get("alive", true))
		level.players.append(player_record)
	level.player = level.players[0].get("position", Vector2i(-1, -1)) if not level.players.is_empty() else Vector2i(-1, -1)

	level.crates.clear()
	for item in data.get("crates", []):
		if item is Dictionary:
			var crate: Dictionary = {}
			for key in item.keys():
				crate[key] = item[key]
			var position_data = crate.get("position", [-1, -1])
			crate["id"] = str(crate.get("id", "crate_%02d" % (level.crates.size() + 1)))
			if position_data is Array and position_data.size() >= 2:
				crate["position"] = Vector2i(int(position_data[0]), int(position_data[1]))
			else:
				crate["position"] = Vector2i(-1, -1)
			level.crates.append(crate)

	level.mirrors.clear()
	var mirror_items: Array = data.get("mirrors", []) if data.has("mirrors") else []
	if mirror_items.is_empty() and data.get("mirror", null) is Dictionary:
		mirror_items = [data.get("mirror")]
	for item in mirror_items:
		if not item is Dictionary:
			continue
		var mirror_record: Dictionary = item.duplicate(true)
		var mirror_position = mirror_record.get("position", [-1, -1])
		mirror_record["id"] = str(mirror_record.get("id", "mirror_%02d" % (level.mirrors.size() + 1)))
		mirror_record["orientation"] = str(mirror_record.get("orientation", "backslash"))
		if mirror_position is Array and mirror_position.size() >= 2:
			mirror_record["position"] = Vector2i(int(mirror_position[0]), int(mirror_position[1]))
		else:
			mirror_record["position"] = Vector2i(-1, -1)
		level.mirrors.append(mirror_record)
	level.mirror = level.mirrors[0].duplicate(true) if not level.mirrors.is_empty() else {}

	level.goals.clear()
	for goal in data.get("goals", []):
		if goal is Array and goal.size() >= 2:
			level.goals.append(Vector2i(int(goal[0]), int(goal[1])))

	level.texts.clear()
	for item in data.get("texts", []):
		if not item is Dictionary:
			continue
		var text_record: Dictionary = item.duplicate(true)
		var text_position = text_record.get("position", [-1, -1])
		text_record["id"] = str(text_record.get("id", "text_%02d" % (level.texts.size() + 1)))
		if text_position is Array and text_position.size() >= 2:
			text_record["position"] = Vector2(float(text_position[0]), float(text_position[1]))
		else:
			text_record["position"] = Vector2(-1.0, -1.0)
		text_record["text"] = str(text_record.get("text", ""))
		text_record["size"] = clampi(int(text_record.get("size", 18)), 8, 96)
		text_record["color"] = str(text_record.get("color", "#eef5ff"))
		text_record["background_alpha"] = clampf(float(text_record.get("background_alpha", 0.86)), 0.0, 1.0)
		level.texts.append(text_record)

	var exit_data = data.get("exit", null)
	if exit_data is Array and exit_data.size() >= 2:
		level.exit_cell = Vector2i(int(exit_data[0]), int(exit_data[1]))
	else:
		level.exit_cell = Vector2i(-1, -1)

	level.solution.clear()
	for action in data.get("solution", []):
		level.solution.append(str(action))
	level.teaching_goal = str(data.get("teaching_goal", ""))
	return level

func duplicate_level():
	return LevelData.from_dict(to_dict())

func resized_copy(new_width: int, new_height: int) -> Dictionary:
	var resized: LevelData = duplicate_level()
	resized.width = clampi(new_width, MIN_BOARD_SIZE, MAX_BOARD_SIZE)
	resized.height = clampi(new_height, MIN_BOARD_SIZE, MAX_BOARD_SIZE)
	resized.terrain.clear()
	var removed_terrain := 0
	for y in range(height):
		for x in range(width):
			if (x >= resized.width or y >= resized.height) and terrain_at(Vector2i(x, y)) != "~":
				removed_terrain += 1
	for y in range(resized.height):
		var row := ""
		for x in range(resized.width):
			row += terrain_at(Vector2i(x, y)) if x < width and y < height else "~"
		resized.terrain.append(row)
	var removed_entities := 0
	for records in [resized.players, resized.crates, resized.mirrors]:
		for i in range(records.size() - 1, -1, -1):
			var pos: Vector2i = records[i].get("position", Vector2i(-1, -1))
			if pos.x >= resized.width or pos.y >= resized.height:
				records.remove_at(i)
				removed_entities += 1
	resized.player = resized.players[0].get("position", Vector2i(-1, -1)) if not resized.players.is_empty() else Vector2i(-1, -1)
	resized.mirror = resized.mirrors[0].duplicate(true) if not resized.mirrors.is_empty() else {}
	var removed_markers := 0
	for i in range(resized.goals.size() - 1, -1, -1):
		var goal: Vector2i = resized.goals[i]
		if goal.x >= resized.width or goal.y >= resized.height:
			resized.goals.remove_at(i)
			removed_markers += 1
	if resized.exit_cell.x >= resized.width or resized.exit_cell.y >= resized.height:
		resized.exit_cell = Vector2i(-1, -1)
		removed_markers += 1
	# 文字是独立的场景注释，可以位于棋盘外；调整棋盘大小不裁剪文字。
	return {"level": resized, "removed_terrain": removed_terrain, "removed_entities": removed_entities, "removed_markers": removed_markers}

func to_dict() -> Dictionary:
	var out: Dictionary = {
		"schema_version": SCHEMA_VERSION,
		"id": id,
		"title": title,
		"description": description,
		"width": width,
		"height": height,
		"terrain": terrain.duplicate(),
		"player": null,
		"crates": [],
		"mirror": null,
		"goals": [],
		"texts": [],
		"exit": null,
		"solution": solution.duplicate(),
		"teaching_goal": teaching_goal
	}
	var player_records: Array = players
	if player_records.is_empty() and player.x >= 0:
		player_records = [{"id": "player_01", "position": player}]
	if player_records.size() > 1:
		var player_list: Array = []
		for player_record in player_records:
			var player_position: Vector2i = player_record.get("position", Vector2i(-1, -1))
			player_list.append({"id": str(player_record.get("id", "player_%02d" % (player_list.size() + 1))), "position": [player_position.x, player_position.y]})
		out["players"] = player_list
	elif player_records.size() == 1:
		var first_player: Vector2i = player if player.x >= 0 else player_records[0].get("position", Vector2i(-1, -1))
		if first_player.x >= 0:
			out["player"] = [first_player.x, first_player.y]
	var crate_list: Array = []
	for crate in crates:
		var crate_position: Vector2i = crate.get("position", Vector2i(-1, -1))
		crate_list.append({
			"id": str(crate.get("id", "crate_%02d" % (crate_list.size() + 1))),
			"position": [crate_position.x, crate_position.y]
		})
	out["crates"] = crate_list
	var mirror_records: Array = mirrors
	if mirror_records.is_empty() and not mirror.is_empty():
		mirror_records = [mirror]
	if mirror_records.size() > 1:
		var mirror_list: Array = []
		for mirror_record in mirror_records:
			var mirror_position: Vector2i = mirror_record.get("position", Vector2i(-1, -1))
			mirror_list.append({
				"id": str(mirror_record.get("id", "mirror_%02d" % (mirror_list.size() + 1))),
				"position": [mirror_position.x, mirror_position.y],
				"orientation": str(mirror_record.get("orientation", "backslash"))
			})
		out["mirrors"] = mirror_list
	elif mirror_records.size() == 1:
		var first_mirror: Dictionary = mirror if not mirror.is_empty() else mirror_records[0]
		var mirror_position: Vector2i = first_mirror.get("position", Vector2i(-1, -1))
		out["mirror"] = {
			"id": str(first_mirror.get("id", "mirror_01")),
			"position": [mirror_position.x, mirror_position.y],
			"orientation": str(first_mirror.get("orientation", "backslash"))
		}
	var goal_list: Array = []
	for goal in goals:
		var goal_position: Vector2i = goal
		goal_list.append([goal_position.x, goal_position.y])
	out["goals"] = goal_list
	if exit_cell.x >= 0:
		out["exit"] = [exit_cell.x, exit_cell.y]
	var text_list: Array = []
	for text_record in texts:
		var text_position: Vector2 = text_record.get("position", Vector2(-1.0, -1.0))
		text_list.append({
			"id": str(text_record.get("id", "text_%02d" % (text_list.size() + 1))),
			"position": [text_position.x, text_position.y],
			"text": str(text_record.get("text", "")),
			"size": clampi(int(text_record.get("size", 18)), 8, 96),
			"color": str(text_record.get("color", "#eef5ff")),
			"background_alpha": clampf(float(text_record.get("background_alpha", 0.86)), 0.0, 1.0)
		})
	out["texts"] = text_list
	return out

func terrain_at(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= terrain.size() or cell.x < 0 or cell.x >= width:
		# 关卡坐标之外没有硬边界，场景外统一视作水面。
		return "~"
	return str(terrain[cell.y]).substr(cell.x, 1)

func set_terrain(cell: Vector2i, value: String) -> void:
	if cell.y < 0 or cell.y >= terrain.size() or cell.x < 0 or cell.x >= width:
		return
	var row: String = str(terrain[cell.y])
	terrain[cell.y] = row.substr(0, cell.x) + value + row.substr(cell.x + 1)

func make_blank(new_width: int = 6, new_height: int = 6):
	width = clampi(new_width, MIN_BOARD_SIZE, MAX_BOARD_SIZE)
	height = clampi(new_height, MIN_BOARD_SIZE, MAX_BOARD_SIZE)
	terrain.clear()
	for y in range(height):
		var row := ""
		for x in range(width):
			row += "#" if x == 0 or y == 0 or x == width - 1 or y == height - 1 else "."
		terrain.append(row)
	player = Vector2i(1, 1)
	players = [{"id": "player_01", "position": player, "alive": true}]
	crates.clear()
	mirror = {}
	mirrors.clear()
	goals.clear()
	texts.clear()
	exit_cell = Vector2i(width - 2, height - 2)
	solution.clear()
	return self
