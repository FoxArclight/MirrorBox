class_name LevelValidator
extends RefCounted

static func validate_format(data: Variant) -> Array[String]:
    var errors: Array[String] = []
    if not data is Dictionary:
        errors.append("根节点必须是 JSON 对象")
        return errors
    if int(data.get("schema_version", -1)) != 1:
        errors.append("不支持的 schema_version，当前仅支持 1")
    var width := int(data.get("width", -1))
    var height := int(data.get("height", -1))
    if width < 6 or width > 32 or height < 6 or height > 32:
        errors.append("地图宽高必须在 6—32 之间")
    var terrain = data.get("terrain", null)
    if not terrain is Array or terrain.size() != height:
        errors.append("terrain 行数必须等于 height")
    else:
        for y in range(terrain.size()):
            var row := str(terrain[y])
            if row.length() != width:
                errors.append("terrain 第 %d 行长度错误" % y)
            for x in range(row.length()):
                if row.substr(x, 1) not in [".", "~", "#"]:
                    errors.append("terrain 含未知字符：%s" % row.substr(x, 1))
    var ids := {}
    for crate in data.get("crates", []):
        if not crate is Dictionary:
            errors.append("箱子条目必须是对象")
            continue
        var cid := str(crate.get("id", ""))
        if cid.is_empty() or not _valid_id(cid):
            errors.append("箱子 ID 非法：%s" % cid)
        if ids.has(cid):
            errors.append("实体 ID 重复：%s" % cid)
        ids[cid] = true
    var mirror_items: Array = data.get("mirrors", []) if data.has("mirrors") else []
    if mirror_items.is_empty() and data.get("mirror", null) is Dictionary:
        mirror_items = [data.get("mirror")]
    for mirror in mirror_items:
        if not mirror is Dictionary:
            errors.append("镜子条目必须是对象")
            continue
        var mid := str(mirror.get("id", "mirror_%02d" % (mirror_items.find(mirror) + 1)))
        if ids.has(mid):
            errors.append("实体 ID 重复：%s" % mid)
        ids[mid] = true
        if str(mirror.get("orientation", "")) not in ["slash", "backslash"]:
            errors.append("镜子 orientation 必须是 slash 或 backslash")
    var player_items: Array = data.get("players", []) if data.has("players") else []
    if player_items.is_empty() and data.get("player", null) != null:
        player_items = [data.get("player")]
    for player in player_items:
        if player is Dictionary:
            var position = player.get("position", null)
            if position is Array and position.size() >= 2 and (not _is_int_value(position[0]) or not _is_int_value(position[1])):
                errors.append("玩家坐标必须是整数")
        elif not player is Array or player.size() < 2 or not _is_int_value(player[0]) or not _is_int_value(player[1]):
            errors.append("玩家必须是 [x,y] 或带 position 的对象")
    for name in ["player", "exit"]:
        var value = data.get(name, null)
        if value != null and (not value is Array or value.size() < 2):
            errors.append("%s 必须是 [x,y] 或 null" % name)
        elif value is Array and (not _is_int_value(value[0]) or not _is_int_value(value[1])):
            errors.append("%s 坐标必须是整数" % name)
    for item in data.get("goals", []):
        if not item is Array or item.size() < 2 or not _is_int_value(item[0]) or not _is_int_value(item[1]):
            errors.append("目标板坐标必须是整数数组")
    for text_record in data.get("texts", []):
        if not text_record is Dictionary:
            errors.append("字体条目必须是对象")
            continue
        var text_id := str(text_record.get("id", ""))
        if text_id.is_empty() or not _valid_id(text_id):
            errors.append("字体 ID 非法：%s" % text_id)
        if ids.has(text_id):
            errors.append("实体 ID 重复：%s" % text_id)
        ids[text_id] = true
        var text_position = text_record.get("position", null)
        if not text_position is Array or text_position.size() < 2 or not _is_number_value(text_position[0]) or not _is_number_value(text_position[1]):
            errors.append("字体坐标必须是数字数组")
        var content := str(text_record.get("text", ""))
        if content.strip_edges().is_empty():
            errors.append("字体内容不能为空")
        var font_size := int(text_record.get("size", 18))
        if font_size < 8 or font_size > 96:
            errors.append("字体大小必须在 8—96 之间")
        if str(text_record.get("color", "#eef5ff")).strip_edges().is_empty():
            errors.append("字体颜色不能为空")
        var background_alpha := float(text_record.get("background_alpha", 0.86))
        if background_alpha < 0.0 or background_alpha > 1.0:
            errors.append("字体背景 Alpha 必须在 0—1 之间")
    return errors

static func validate_playability(level: LevelData) -> Dictionary:
    var issues: Array = []
    if level.player.x < 0:
        _issue(issues, "missing_player", "error", "缺少角色：选择角色工具，在陆地上放置", [], "player")
    if level.exit_cell.x < 0:
        _issue(issues, "missing_exit", "error", "缺少出口：选择出口工具，在陆地上放置", [], "exit")
    var occupied := {}
    for crate in level.crates:
        var cell: Vector2i = crate.get("position", Vector2i(-1, -1))
        if not _valid_cell(level, cell):
            _issue(issues, "crate_bounds", "error", "箱子超出棋盘：%s" % cell, [cell], "crate")
        if occupied.has(BoardRules.key(cell)):
            _issue(issues, "crate_overlap", "error", "实体占位重复：%s" % cell, [cell], "crate")
        occupied[BoardRules.key(cell)] = true
        if level.terrain_at(cell) != ".":
            _issue(issues, "crate_terrain", "error", "箱子必须位于陆地：%s" % cell, [cell], "land")
    var mirror_items: Array = level.mirrors if not level.mirrors.is_empty() else ([] if level.mirror.is_empty() else [level.mirror])
    for mirror in mirror_items:
        var mirror_cell: Vector2i = mirror.get("position", Vector2i(-1, -1))
        if not _valid_cell(level, mirror_cell) or level.terrain_at(mirror_cell) != ".":
            _issue(issues, "mirror_terrain", "error", "镜子必须位于陆地：%s" % mirror_cell, [mirror_cell], "land")
        if occupied.has(BoardRules.key(mirror_cell)):
            _issue(issues, "mirror_overlap", "error", "镜子与其他实体重叠：%s" % mirror_cell, [mirror_cell], "mirror")
        occupied[BoardRules.key(mirror_cell)] = true
    var player_items: Array = level.players if not level.players.is_empty() else ([] if level.player.x < 0 else [{"position": level.player}])
    for player in player_items:
        var player_cell: Vector2i = player.get("position", Vector2i(-1, -1))
        if not _valid_cell(level, player_cell) or level.terrain_at(player_cell) != ".":
            _issue(issues, "player_terrain", "error", "角色必须位于陆地：%s" % player_cell, [player_cell], "land")
        if occupied.has(BoardRules.key(player_cell)):
            _issue(issues, "player_overlap", "error", "角色与实体重叠：%s" % player_cell, [player_cell], "player")
        occupied[BoardRules.key(player_cell)] = true
    if level.exit_cell.x >= 0:
        if not _valid_cell(level, level.exit_cell) or level.terrain_at(level.exit_cell) != ".":
            _issue(issues, "exit_terrain", "error", "出口必须位于陆地：%s" % level.exit_cell, [level.exit_cell], "land")
    var goals_seen := {}
    for goal in level.goals:
        if not _valid_cell(level, goal) or level.terrain_at(goal) != ".":
            _issue(issues, "goal_terrain", "error", "箱子终点必须位于陆地：%s" % goal, [goal], "land")
        if goal == level.exit_cell:
            _issue(issues, "goal_exit_overlap", "error", "出口与箱子终点不能重叠：%s" % goal, [goal], "goal")
        if goals_seen.has(BoardRules.key(goal)):
            _issue(issues, "goal_overlap", "error", "箱子终点重复：%s" % goal, [goal], "goal")
        goals_seen[BoardRules.key(goal)] = true
    # 文字是独立注释，允许位于棋盘外，不参与可玩性边界检查。
    var mirror_count := mirror_items.size()
    if not level.goals.is_empty() and level.crates.is_empty():
        _issue(issues, "missing_crate", "error", "有箱子终点时，至少需要一个箱子", level.goals, "crate")
    elif level.crates.size() < level.goals.size():
        if mirror_count > 1:
            _issue(issues, "crate_shortage_copy", "warning", "箱子少于终点；可尝试用多面镜子复制，允许试玩", level.goals, "crate")
        else:
            _issue(issues, "crate_shortage", "error", "箱子少于终点，且镜子不超过一面：请补充箱子", level.goals, "crate")
    if _validation_result(issues).errors.is_empty() and BoardRules.is_won(level, BoardState.from_level(level)):
        _issue(issues, "already_won", "error", "初始状态已经通关：请移动角色或出口", [level.exit_cell], "player")
    if mirror_items.is_empty() and level.width * level.height > 100:
        _issue(issues, "no_mirrors", "warning", "未配置镜子；若岛屿断开，可能无法抵达出口", [], "mirror")
    _issue(issues, "not_proven", "info", "结构校验不等于保证有解，请实际试玩。")
    return _validation_result(issues)

static func _issue(issues: Array, code: String, severity: String, message: String, cells: Array = [], tool: String = "") -> void:
    issues.append({"code": code, "severity": severity, "message": message, "cells": cells.duplicate(), "tool": tool})

static func _validation_result(issues: Array) -> Dictionary:
    var errors: Array[String] = []
    var warnings: Array[String] = []
    for issue in issues:
        if issue.severity == "error":
            errors.append(issue.message)
        else:
            warnings.append(issue.message)
    return {"errors": errors, "warnings": warnings, "issues": issues}

static func _valid_id(value: String) -> bool:
    if value.length() < 1 or value.length() > 48:
        return false
    for i in range(value.length()):
        var ch := value.substr(i, 1)
        var code := ch.unicode_at(0)
        if not ((code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or ch == "_" or ch == "-"):
            return false
    return true

static func _is_int_value(value: Variant) -> bool:
    return value is int or (value is float and float(value) == floor(float(value)))

static func _is_number_value(value: Variant) -> bool:
    return value is int or value is float

static func _valid_cell(level: LevelData, cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.y >= 0 and cell.x < level.width and cell.y < level.height
