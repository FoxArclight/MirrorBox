extends Node

var failures: int = 0
var passed: int = 0

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	test_format_and_levels()
	test_movement_and_push()
	test_bridge_and_undo()
	test_mirror_projection()
	test_multi_reflection()
	test_illegal_destinations()
	test_win_condition()
	test_optional_crates_and_goals()
	test_push_history_policy()
	test_solutions()
	print("RULE_TESTS passed=%d failed=%d" % [passed, failures])
	get_tree().quit(1 if failures > 0 else 0)

func check(condition: bool, label: String) -> void:
	if condition:
		passed += 1
	else:
		failures += 1
		push_error("FAIL: " + label)

func eq(actual: Variant, expected: Variant, label: String) -> void:
	check(actual == expected, "%s (got %s expected %s)" % [label, str(actual), str(expected)])

func level(data: Dictionary) -> LevelData:
	return LevelData.from_dict(data)

func open_level(id: String) -> LevelData:
	var raw = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/%s.json" % id))
	return LevelData.from_dict(raw)

func test_format_and_levels() -> void:
	for id in ["level_001", "level_002", "level_003", "level_004", "level_005", "level_006"]:
		var l := open_level(id)
		var format_errors := LevelValidator.validate_format(l.to_dict())
		var playable := LevelValidator.validate_playability(l)
		check(format_errors.is_empty(), id + " format")
		check(playable.errors.is_empty(), id + " playable")
		check(not playable.warnings.is_empty(), id + " records non-guarantee warning")

func test_movement_and_push() -> void:
	var l := level({"schema_version": 1, "id": "t", "title": "t", "width": 8, "height": 6, "terrain": ["########", "#......#", "#......#", "#......#", "#......#", "########"], "player": [1, 2], "crates": [{"id": "c1", "position": [2, 2]}, {"id": "c2", "position": [3, 2]}], "mirror": null, "goals": [], "exit": [6, 4]})
	var s := BoardState.from_level(l)
	var blocked := BoardRules.apply_action(l, s, "RIGHT")
	check(not blocked.accepted, "連推两个箱子失败")
	eq(s.player, Vector2i(1, 2), "失败动作不改玩家")
	var single := level({"schema_version": 1, "id": "single", "title": "single", "width": 8, "height": 6, "terrain": ["########", "#......#", "#......#", "#......#", "#......#", "########"], "player": [1, 2], "crates": [{"id": "c1", "position": [2, 2]}], "mirror": null, "goals": [], "exit": [6, 4]})
	var s2 := BoardState.from_level(single)
	var move := BoardRules.apply_action(single, s2, "RIGHT")
	check(move.accepted, "推单箱子成功")
	eq(move.next_state.player, Vector2i(2, 2), "推箱玩家位置")
	eq(move.next_state.crate_at(Vector2i(3, 2)).get("id", ""), "c1", "推箱子位置")
	var wall := BoardRules.apply_action(single, move.next_state, "UP")
	check(wall.accepted, "普通移动成功")

func test_bridge_and_undo() -> void:
	var l := open_level("level_002")
	var s := BoardState.from_level(l)
	var before := s.duplicate_state()
	var pushed := BoardRules.apply_action(l, s, "RIGHT")
	check(pushed.accepted, "推入水面成功")
	check(pushed.next_state.has_bridge(Vector2i(3, 2)), "水面变桥")
	check(pushed.next_state.crates.size() == 1 and pushed.next_state.crate_at(Vector2i(4, 2)).get("id", "") == "crate_02", "入水箱子从实体集合移除")
	check(bool(pushed.get("push", {}).get("special", false)), "落水推动标记为特殊推动")
	var history := ActionHistory.new()
	history.push(before)
	var restored := history.pop()
	check(restored != null and not restored.has_bridge(Vector2i(3, 2)), "撤销恢复水面")
	eq(restored.player, Vector2i(1, 2), "撤销恢复玩家")
	eq(restored.action_count, 0, "撤销恢复操作数")

func test_mirror_projection() -> void:
	var l := open_level("level_003")
	var s := BoardState.from_level(l)
	var preview := BoardRules.get_mirror_preview(l, s)
	check(preview.valid, "backslash 预览合法")
	eq(preview.target, Vector2i(4, 1), "backslash 非零镜心映射")
	var moved := BoardRules.apply_action(l, s, "MIRROR")
	check(moved.accepted and moved.next_state.player == Vector2i(4, 1), "backslash 传送")
	check(not moved.has("push"), "镜像传送不进入推动日志")
	var slash_level = l.duplicate_level()
	slash_level.player = Vector2i(2, 3)
	slash_level.mirror["orientation"] = "slash"
	slash_level.exit_cell = Vector2i(4, 5)
	var slash_state := BoardState.from_level(slash_level)
	var slash_preview := BoardRules.get_mirror_preview(slash_level, slash_state)
	eq(slash_preview.target, Vector2i(4, 5), "slash 象限映射")
	var unaligned_level: LevelData = l.duplicate_level()
	unaligned_level.player = Vector2i(2, 2)
	var unaligned_preview := BoardRules.get_mirror_preview(unaligned_level, BoardState.from_level(unaligned_level))
	eq(unaligned_preview.reason, "NOT_ALIGNED", "未同行同列不生成传送目标")
	var blocked_level: LevelData = l.duplicate_level()
	blocked_level.crates = [{"id": "blocker", "position": Vector2i(3, 3)}]
	var blocked_preview := BoardRules.get_mirror_preview(blocked_level, BoardState.from_level(blocked_level))
	eq(blocked_preview.reason, "BLOCKED_LINE", "镜前箱子遮挡传送")
	var center := Vector2i(7, 8)
	var point := Vector2i(5, 10)
	var back_target := center + Vector2i(point.y - center.y, point.x - center.x)
	var back_twice := center + Vector2i(back_target.y - center.y, back_target.x - center.x)
	eq(back_twice, point, "backslash 映射自反")
	var slash_target := center + Vector2i(-(point.y - center.y), -(point.x - center.x))
	var slash_twice := center + Vector2i(-(slash_target.y - center.y), -(slash_target.x - center.x))
	eq(slash_twice, point, "slash 映射自反")

func test_multi_reflection() -> void:
	var terrain := ["##########", "#........#", "#........#", "#........#", "#........#", "#........#", "#........#", "#........#", "##########"]
	var l := level({"schema_version": 1, "id": "multi", "title": "multi", "width": 10, "height": 9, "terrain": terrain, "player": [2, 3], "crates": [{"id": "c1", "position": [7, 3]}], "mirrors": [{"id": "m1", "position": [4, 3], "orientation": "backslash"}, {"id": "m2", "position": [2, 5], "orientation": "slash"}], "goals": [[4, 6]], "exit": [8, 7]})
	var state := BoardState.from_level(l)
	var preview := BoardRules.get_reflection_preview(l, state)
	var player_targets := 0
	var crate_targets := 0
	for pair in preview.pairs:
		if pair.source_type == "PLAYER":
			player_targets += 1
		if pair.source_type == "CRATE":
			crate_targets += 1
	eq(player_targets, 2, "同一玩家可同时命中两面镜子")
	eq(crate_targets, 1, "箱子也参与镜面反射")
	var reflected := BoardRules.apply_action(l, state, "MIRROR")
	check(reflected.accepted and reflected.next_state.players.size() == 2, "双镜生成两个可操控角色")
	eq(reflected.next_state.crate_at(Vector2i(4, 6)).get("id", ""), "c1__m1", "箱子反射结果可落在目标格")
	var water_level: LevelData = l.duplicate_level()
	water_level.mirrors = [{"id": "m1", "position": Vector2i(4, 3), "orientation": "slash"}]
	water_level.mirror = water_level.mirrors[0].duplicate(true)
	water_level.terrain[5] = "#...~....#"
	var water_state := BoardState.from_level(water_level)
	var water_preview := BoardRules.get_reflection_preview(water_level, water_state)
	check(water_preview.accepted and water_preview.pairs[0].status == "danger", "水面目标显示危险但允许反射")
	var water_result := BoardRules.apply_action(water_level, water_state, "MIRROR")
	check(water_result.accepted and water_result.next_state.failed, "唯一角色落水后进入失败态")
	var history := ActionHistory.new()
	history.record_reflection(state, water_result.get("reflection", {}))
	eq(history.size(), 1, "反射操作进入撤回列表")

func test_illegal_destinations() -> void:
	var l := open_level("level_003")
	l.terrain[1] = "#...#..#"
	l.player = Vector2i(2, 3)
	var s := BoardState.from_level(l)
	var preview := BoardRules.get_mirror_preview(l, s)
	check(not preview.valid, "墙面落点非法")
	eq(preview.reason, "DEST_WALL", "墙面失败原因")
	var no_mirror = l.duplicate_level()
	no_mirror.mirror = {}
	var no_state := BoardState.from_level(no_mirror)
	eq(BoardRules.get_mirror_preview(no_mirror, no_state).reason, "NO_MIRROR", "无镜失败原因")
	var out_level := open_level("level_003")
	out_level.mirror["position"] = Vector2i(1, 5)
	out_level.player = Vector2i(0, 3)
	var out := BoardRules.get_mirror_preview(out_level, BoardState.from_level(out_level))
	check(out.reason == "DEST_WATER" or out.reason == "DEST_WALL" or out.reason == "NOT_ALIGNED", "水面/墙面/未对齐失败原因")
	var outside_level := open_level("level_003")
	outside_level.mirror["position"] = Vector2i(1, 1)
	outside_level.mirror["orientation"] = "slash"
	outside_level.player = Vector2i(1, 4)
	var outside_preview := BoardRules.get_mirror_preview(outside_level, BoardState.from_level(outside_level))
	eq(outside_level.terrain_at(Vector2i(-1, 0)), "~", "场景外地形是水面")
	eq(outside_preview.reason, "DEST_WATER", "镜像目标越出地图按水面处理")

func test_win_condition() -> void:
	var l := level({"schema_version": 1, "id": "win", "title": "win", "width": 8, "height": 6, "terrain": ["########", "#......#", "#......#", "#......#", "#......#", "########"], "player": [1, 2], "crates": [{"id": "c1", "position": [2, 2]}], "mirror": null, "goals": [[3, 2]], "exit": [6, 4]})
	var state := BoardState.from_level(l)
	var player_at_exit := state.duplicate_state()
	player_at_exit.player = l.exit_cell
	check(not BoardRules.is_won(l, player_at_exit), "玩家到出口但箱子未到目标不通关")
	var player_at_goal := state.duplicate_state()
	player_at_goal.player = Vector2i(3, 2)
	check(not BoardRules.is_won(l, player_at_goal), "玩家到目标板但箱子未到目标不通关")
	var pushed := BoardRules.apply_action(l, state, "RIGHT")
	check(pushed.accepted and not pushed.next_state.won, "箱子覆盖目标板后出口仍关闭")
	check(pushed.next_state.player != l.exit_cell, "箱子到位后玩家仍需前往出口")
	var at_open_exit := pushed.next_state.duplicate_state()
	at_open_exit.player = l.exit_cell
	check(BoardRules.are_goals_complete(l, pushed.next_state), "箱子覆盖目标板后出口打开")
	check(BoardRules.is_won(l, at_open_exit), "箱子到位且玩家到出口才通关")
	var no_goal: LevelData = l.duplicate_level()
	no_goal.goals.clear()
	var no_goal_exit := pushed.next_state.duplicate_state()
	no_goal_exit.player = no_goal.exit_cell
	check(BoardRules.are_goals_complete(no_goal, no_goal_exit), "没有目标板时出口默认打开")
	check(BoardRules.is_won(no_goal, no_goal_exit), "没有目标板时玩家到出口可通关")

func test_optional_crates_and_goals() -> void:
	var base := {"schema_version": 1, "id": "optional", "title": "optional", "width": 8, "height": 6, "terrain": ["########", "#......#", "#......#", "#......#", "#......#", "########"], "player": [1, 1], "crates": [], "mirror": null, "goals": [], "exit": [6, 4]}
	var no_objects := level(base)
	check(LevelValidator.validate_playability(no_objects).errors.is_empty(), "无箱子无目标板可以试玩")
	var crates_without_goals := base.duplicate(true)
	crates_without_goals["crates"] = [{"id": "c1", "position": [2, 2]}]
	check(LevelValidator.validate_playability(level(crates_without_goals)).errors.is_empty(), "有箱子无目标板可以试玩")
	var goals_without_crate := base.duplicate(true)
	goals_without_crate["goals"] = [[3, 2]]
	check(not LevelValidator.validate_playability(level(goals_without_crate)).errors.is_empty(), "有目标板无箱子不能试玩")
	var shortage_without_replication := base.duplicate(true)
	shortage_without_replication["goals"] = [[3, 2], [4, 2]]
	shortage_without_replication["crates"] = [{"id": "c1", "position": [2, 2]}]
	check(not LevelValidator.validate_playability(level(shortage_without_replication)).errors.is_empty(), "镜子不超过一面时箱子不足不能试玩")
	var shortage_with_replication := shortage_without_replication.duplicate(true)
	shortage_with_replication["mirrors"] = [{"id": "m1", "position": [2, 3], "orientation": "slash"}, {"id": "m2", "position": [4, 3], "orientation": "backslash"}]
	var replicated_result := LevelValidator.validate_playability(level(shortage_with_replication))
	check(replicated_result.errors.is_empty() and not replicated_result.warnings.is_empty(), "镜子超过一面时箱子不足仅提示")

func test_push_history_policy() -> void:
	var l := level({"schema_version": 1, "id": "history", "title": "history", "width": 8, "height": 6, "terrain": ["########", "#......#", "#......#", "#......#", "#......#", "########"], "player": [1, 2], "crates": [{"id": "c1", "position": [2, 2]}], "mirror": null, "goals": [[6, 4]], "exit": [6, 4]})
	var state := BoardState.from_level(l)
	var history := ActionHistory.new()
	eq(history.size(), 0, "开局没有回退检查点")
	var move := BoardRules.apply_action(l, state, "UP")
	check(move.accepted, "推动策略测试的普通移动成功")
	state = move.next_state
	eq(history.size(), 0, "普通移动不新增回退检查点")
	var back := BoardRules.apply_action(l, state, "DOWN")
	check(back.accepted, "推动策略测试的回移动作成功")
	state = back.next_state
	var first_push := BoardRules.apply_action(l, state, "RIGHT")
	check(first_push.accepted and first_push.has("push"), "第一次推动返回推动元数据")
	var first_info: Dictionary = first_push.get("push", {})
	eq(first_info.get("entity_id", ""), "c1", "推动元数据包含稳定实体 ID")
	eq(first_info.get("direction", ""), "RIGHT", "推动元数据包含方向")
	history.record_push(state, first_info)
	state = first_push.next_state
	eq(history.size(), 1, "第一次推动新增回退检查点")
	var second_push := BoardRules.apply_action(l, state, "RIGHT")
	check(second_push.accepted, "同向连续推动成功")
	history.record_push(state, second_push.get("push", {}))
	state = second_push.next_state
	eq(history.size(), 1, "同箱同方向简单推动合并检查点")
	eq(history.push_log.size(), 2, "合并推动仍保留在推动日志")
	var special_info: Dictionary = second_push.get("push", {}).duplicate(true)
	special_info["special"] = true
	history.record_push(state, special_info)
	eq(history.size(), 2, "特殊推动强制新增检查点")
	eq(history.push_log.size(), 3, "特殊推动也进入推动日志")
	var undo_special: BoardState = history.pop()
	check(undo_special.player == state.player and undo_special.crate_at(Vector2i(4, 2)).get("id", "") == "c1", "Z 恢复特殊推动之前的完整状态")
	eq(history.size(), 1, "撤销特殊推动弹出最近检查点")
	eq(history.push_log.size(), 2, "撤销同步截断推动日志")
	var undo_first: BoardState = history.pop()
	check(undo_first.player == Vector2i(1, 2) and undo_first.crate_at(Vector2i(2, 2)).get("id", "") == "c1", "Z 再次回到第一次推动之前")
	eq(history.size(), 0, "撤销完毕后没有检查点")
	eq(history.push_log.size(), 0, "撤销完毕后推动日志为空")

func test_solutions() -> void:
	for id in ["level_001", "level_002", "level_003", "level_004", "level_005", "level_006"]:
		var l := open_level(id)
		var result := BoardRules.apply_sequence(l, BoardState.from_level(l), l.solution)
		check(result.accepted, id + " 解答每步接受")
		check(result.state.won, id + " 解答最终胜利")
