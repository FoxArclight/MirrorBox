class_name ProfileStore
extends RefCounted

const PATH := "user://profile.json"
var completed: Dictionary = {}
var best_actions: Dictionary = {}
var last_level: String = "level_001"
var muted: bool = false
var volume: float = 0.8

func load_profile() -> Dictionary:
    if not FileAccess.file_exists(PATH):
        return {"ok": true, "created": true}
    var parsed = JSON.parse_string(FileAccess.get_file_as_string(PATH))
    if not parsed is Dictionary:
        _backup_bad_profile()
        _reset()
        return {"ok": false, "recovered": true, "error": "profile.json 损坏，已回退空档案"}
    completed = parsed.get("completed", {}).duplicate(true)
    best_actions = parsed.get("best_actions", {}).duplicate(true)
    last_level = str(parsed.get("last_level", "level_001"))
    muted = bool(parsed.get("muted", false))
    volume = clampf(float(parsed.get("volume", 0.8)), 0.0, 1.0)
    return {"ok": true}

func save_profile() -> Dictionary:
    var file := FileAccess.open(PATH + ".tmp", FileAccess.WRITE)
    if file == null:
        return {"ok": false, "error": "无法写入 profile 临时文件"}
    file.store_string(JSON.stringify({"completed": completed, "best_actions": best_actions, "last_level": last_level, "muted": muted, "volume": volume}, "\t"))
    file.flush()
    file.close()
    if FileAccess.file_exists(PATH):
        DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
    var result := DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH + ".tmp"), ProjectSettings.globalize_path(PATH))
    return {"ok": result == OK, "error": "替换档案失败" if result != OK else ""}

func mark_completed(level_id: String, actions: int) -> void:
    completed[level_id] = true
    if not best_actions.has(level_id) or actions < int(best_actions[level_id]):
        best_actions[level_id] = actions

func is_completed(level_id: String) -> bool:
    return bool(completed.get(level_id, false))

func _reset() -> void:
    completed.clear()
    best_actions.clear()
    last_level = "level_001"
    muted = false
    volume = 0.8

func _backup_bad_profile() -> void:
    if FileAccess.file_exists(PATH):
        DirAccess.rename_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(PATH + ".bad"))
