class_name LevelRepository
extends RefCounted

const LEVEL_DIR := "user://levels"
const MAX_BYTES := 2 * 1024 * 1024

static func ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LEVEL_DIR))

static func save_level(level: LevelData, requested_id: String = "") -> Dictionary:
	ensure_dirs()
	var safe_id := sanitize_id(requested_id if not requested_id.is_empty() else level.id)
	if safe_id.is_empty():
		return {"ok": false, "error": "关卡 ID 非法"}
	level.id = safe_id
	var path := "%s/%s.json" % [LEVEL_DIR, safe_id]
	var temp := path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "error": "无法写入临时文件：%s" % FileAccess.get_open_error()}
	file.store_string(JSON.stringify(level.to_dict(), "\t"))
	file.flush()
	file.close()
	if not FileAccess.file_exists(temp):
		return {"ok": false, "error": "临时文件未生成"}
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var renamed := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp), ProjectSettings.globalize_path(path))
	if renamed != OK:
		return {"ok": false, "error": "替换保存文件失败：%s" % renamed}
	return {"ok": true, "path": path, "id": safe_id}

static func load_level_path(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "error": "文件不存在：%s" % path}
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.get_file_as_bytes(path).size() > MAX_BYTES:
		return {"ok": false, "error": "文件超过 2 MiB 限制"}
	var text := FileAccess.get_file_as_string(path)
	var parsed = JSON.parse_string(text)
	var format_errors := LevelValidator.validate_format(parsed)
	if not format_errors.is_empty():
		return {"ok": false, "error": "; ".join(format_errors)}
	var level = LevelData.from_dict(parsed)
	var playable := LevelValidator.validate_playability(level)
	return {"ok": true, "level": level, "playable": playable, "path": path, "absolute": absolute}

static func list_custom_levels() -> Array[LevelData]:
	ensure_dirs()
	var result: Array[LevelData] = []
	var dir := DirAccess.open(LEVEL_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var filename := dir.get_next()
	while not filename.is_empty():
		if not dir.current_is_dir() and filename.ends_with(".json"):
			var loaded := load_level_path("%s/%s" % [LEVEL_DIR, filename])
			if bool(loaded.get("ok", false)):
				result.append(loaded.level)
		filename = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a: LevelData, b: LevelData) -> bool: return a.title < b.title)
	return result

static func sanitize_id(value: String) -> String:
	var clean := ""
	for i in range(value.length()):
		var ch := value.substr(i, 1)
		var code := ch.unicode_at(0)
		if (code >= 48 and code <= 57) or (code >= 65 and code <= 90) or (code >= 97 and code <= 122) or ch == "_" or ch == "-":
			clean += ch
	return clean.substr(0, 48)
