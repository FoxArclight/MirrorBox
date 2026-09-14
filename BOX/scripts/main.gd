extends Node2D

const LevelDataScript = preload("res://scripts/core/level_data.gd")
const BoardStateScript = preload("res://scripts/core/board_state.gd")
const BoardRulesScript = preload("res://scripts/core/board_rules.gd")
const HistoryScript = preload("res://scripts/core/history.gd")
const ValidatorScript = preload("res://scripts/core/level_validator.gd")
const RepositoryScript = preload("res://scripts/storage/level_repository.gd")
const ProfileScript = preload("res://scripts/storage/profile_store.gd")
const EditorWorkspaceScript = preload("res://scripts/ui/editor_workspace.gd")

var screen := "menu"
var select_page := "formal"
var levels: Array = []
var custom_levels: Array = []
var current_level = null
var current_state = null
var initial_state = null
var history = null
var profile = null
var message := ""
var message_timer := 0.0
var preview := {}
var held_action := ""
var held_time := 0.0
var repeat_time := 0.0
var editor_level = null
var editor_history: Array = []
var editor_redo: Array = []
var editor_tool := "land"
var editor_dirty := false
var editor_stroke_before = null
var editor_stroke_changed := false
var editor_play_origin = null
var pending_confirm := ""
var font: Font
var title_edit: LineEdit
var description_edit: TextEdit
var editor_ui
var editor_mode := "paint"
var editor_mirror_orientation := "slash"
var editor_stroke_visited := {}
var editor_stroke_last := Vector2i(-1, -1)
var editor_stroke_dirty_before := false
var editor_rect_start := Vector2i(-1, -1)
var editor_rect_end := Vector2i(-1, -1)
var editor_drag_active := false
var editor_drag_tool := ""
var editor_drag_index := -1
var editor_drag_source := Vector2i(-1, -1)
var editor_drag_current := Vector2i(-1, -1)
var editor_drag_text_current := Vector2.ZERO
var editor_drag_text_grab_offset := Vector2.ZERO
var editor_palette_drag_active := false
var editor_palette_drag_tool := ""
var editor_palette_drag_moved := false
var editor_palette_drag_start := Vector2.ZERO
var editor_palette_drag_previous_tool := ""
var editor_validation_dirty := true
var editor_validation := {}
var editor_highlight_cells: Array = []
var editor_highlight_time := 0.0
var editor_highlight_color := ERROR
var editor_cell_size := -1.0
var editor_pan := Vector2.ZERO
const EDITOR_MAX_VISIBLE_ROWS := 8.0
var submerged_crates: Array = []
var splash_effects: Array = []
var sfx_player

const SFX_MIX_RATE := 44100

const BG := Color("#102036")
const PANEL := Color("#172b47")
const PANEL_2 := Color("#213957")
const TEXT := Color("#eef5ff")
const MUTED := Color("#a9bdd5")
const ACCENT := Color("#5fd1c5")
const WARNING := Color("#ffcb6b")
const ERROR := Color("#ff7f88")
const LAND := Color("#e6d8b8")
const WATER := Color("#22527a")
const WATER_LIGHT := Color("#347ea0")
const WALL := Color("#17283c")
const BRIDGE := Color("#c49554")
const WATER_DEEP := Color("#123b59")
const LAND_EDGE := Color("#fff0c2")
const WALL_EDGE := Color("#4d6b87")
const CRATE_FACE := Color("#a8673c")
const CRATE_EDGE := Color("#f2bd75")

func _ready() -> void:
	font = ThemeDB.fallback_font
	profile = ProfileScript.new()
	var profile_result: Dictionary = profile.load_profile()
	if not bool(profile_result.get("ok", true)):
		message = str(profile_result.get("error", "档案已恢复"))
	_load_builtin_levels()
	_load_custom_levels()
	_create_editor_inputs()
	_setup_audio()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_fit_initial_window()
	queue_redraw()

func _fit_initial_window() -> void:
	# Scale the complete interface together, preserving readable proportions.
	get_window().content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	if DisplayServer.get_name() == "headless" or Engine.is_embedded_in_editor() or get_window().is_embedded():
		return
	var usable := DisplayServer.screen_get_usable_rect()
	var available := Vector2i(maxi(640, usable.size.x - 64), maxi(360, usable.size.y - 96))
	var initial := Vector2i(mini(1280, available.x), mini(720, available.y))
	get_window().min_size = Vector2i(mini(960, initial.x), mini(540, initial.y))
	get_window().size = initial
	get_window().position = usable.position + (usable.size - initial) / 2

func _process(delta: float) -> void:
	if message_timer > 0.0:
		message_timer -= delta
		if message_timer <= 0.0:
			message = ""
	if (screen == "game" or screen == "editor_play") and held_action != "" and current_state != null and not current_state.won and not current_state.failed:
		if Input.is_action_pressed(_input_name(held_action)):
			held_time += delta
			if held_time >= 0.25:
				repeat_time += delta
				if repeat_time >= 0.12:
					repeat_time = 0.0
					_apply_game_action(held_action)
		else:
			held_action = ""
			held_time = 0.0
			repeat_time = 0.0
	if screen == "editor" and editor_level != null:
		_move_editor_camera(delta)
		if editor_validation_dirty:
			_refresh_editor_validation()
		editor_highlight_time = maxf(0.0, editor_highlight_time - delta)
		var hover := _editor_cell_at(get_global_mouse_position())
		editor_ui.update_status(editor_level, editor_tool, editor_mode, editor_dirty, editor_history.size(), editor_redo.size(), hover, float(_grid_metrics().cell), message)
	for i in range(splash_effects.size() - 1, -1, -1):
		splash_effects[i]["time"] = float(splash_effects[i].get("time", 0.0)) + delta
		if float(splash_effects[i]["time"]) >= 0.85:
			splash_effects.remove_at(i)
	queue_redraw()

func _setup_audio() -> void:
	sfx_player = AudioStreamPlayer.new()
	sfx_player.volume_db = -8.0
	add_child(sfx_player)

func _play_sfx(kind: String) -> void:
	if profile != null and profile.muted:
		return
	if not is_instance_valid(sfx_player):
		return
	var frequency := 220.0
	var duration := 0.10
	var volume := 0.12
	var slide := 0.0
	var decay := 9.0
	match kind:
		"move":
			frequency = 240.0
			duration = 0.045
			volume = 0.07
		"push":
			frequency = 120.0
			duration = 0.12
			volume = 0.16
			slide = 35.0
		"mirror":
			frequency = 620.0
			duration = 0.18
			volume = 0.10
			slide = 180.0
		"teleport":
			frequency = 760.0
			duration = 0.22
			volume = 0.10
			slide = -180.0
		"splash":
			frequency = 180.0
			duration = 0.28
			volume = 0.15
			slide = 280.0
			decay = 7.0
		"win":
			frequency = 880.0
			duration = 0.25
			volume = 0.12
			slide = 120.0
	var frame_count := maxi(1, int(duration * SFX_MIX_RATE))
	var bytes := PackedByteArray()
	bytes.resize(frame_count * 4)
	for i in range(frame_count):
		var t := float(i) / float(SFX_MIX_RATE)
		var envelope := exp(-t * decay)
		var phase := TAU * (frequency * t + 0.5 * slide * t * t)
		var sample := clampf(sin(phase) * envelope * volume, -1.0, 1.0)
		var pcm := clampi(int(sample * 32767.0), -32767, 32767)
		var offset := i * 4
		bytes[offset] = pcm & 0xff
		bytes[offset + 1] = (pcm >> 8) & 0xff
		bytes[offset + 2] = bytes[offset]
		bytes[offset + 3] = bytes[offset + 1]
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SFX_MIX_RATE
	stream.stereo = true
	stream.data = bytes
	sfx_player.stream = stream
	sfx_player.play()

func _load_builtin_levels() -> void:
	levels.clear()
	var campaign = JSON.parse_string(FileAccess.get_file_as_string("res://data/campaign.json"))
	for id in campaign.get("levels", []):
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/levels/%s.json" % str(id)))
		levels.append(LevelDataScript.from_dict(data))

func _load_custom_levels() -> void:
	custom_levels = RepositoryScript.list_custom_levels()

func _create_editor_inputs() -> void:
	editor_ui = EditorWorkspaceScript.new()
	add_child(editor_ui)
	editor_ui.hide()
	title_edit = editor_ui.title_input
	description_edit = editor_ui.description_input
	editor_ui.command_requested.connect(_editor_command)
	editor_ui.tool_selected.connect(_select_editor_tool)
	editor_ui.palette_drag_started.connect(_start_palette_drag)
	editor_ui.open_file_requested.connect(_editor_open_file_requested)
	editor_ui.save_as_requested.connect(_editor_save_as_requested)
	editor_ui.text_requested.connect(_editor_text_requested)
	editor_ui.issue_selected.connect(_focus_editor_issue)
	editor_ui.size_requested.connect(_editor_size_requested)
	editor_ui.metadata_changed.connect(_editor_metadata_changed)

func _set_editor_inputs(visible: bool, reset_text: bool = false) -> void:
	editor_ui.visible = visible
	if visible:
		if reset_text:
			editor_ui.set_level(editor_level)
			editor_highlight_cells.clear()
			editor_validation_dirty = true
	else:
		_clear_palette_drag()
		title_edit.release_focus()
		description_edit.release_focus()

func _on_viewport_resized() -> void:
	if editor_stroke_before != null:
		_finish_editor_stroke(false)
	queue_redraw()

func _reset_editor_view() -> void:
	editor_cell_size = -1.0
	editor_pan = Vector2.ZERO
	editor_drag_active = false
	_clear_palette_drag()

func _start_palette_drag(tool: String) -> void:
	if editor_palette_drag_active and editor_palette_drag_tool == tool:
		return
	_start_palette_drag_at(tool, get_viewport().get_mouse_position())

func _start_palette_drag_at(tool: String, start_position: Vector2) -> void:
	_finish_editor_stroke()
	editor_palette_drag_active = true
	editor_palette_drag_tool = tool
	editor_palette_drag_moved = false
	editor_palette_drag_start = start_position
	editor_palette_drag_previous_tool = editor_tool
	editor_tool = tool
	editor_mode = "paint"
	editor_ui.sync_tool_state(tool)
	title_edit.release_focus()
	description_edit.release_focus()
	show_message("拖动" + _tool_name(tool) + " 到棋盘放置")

func _clear_palette_drag(restore_previous: bool = false) -> void:
	if restore_previous and not editor_palette_drag_previous_tool.is_empty():
		editor_tool = editor_palette_drag_previous_tool
		editor_mode = "paint"
		if editor_ui != null:
			editor_ui.sync_tool_state(editor_tool)
	editor_palette_drag_active = false
	editor_palette_drag_tool = ""
	editor_palette_drag_moved = false
	editor_palette_drag_start = Vector2.ZERO
	editor_palette_drag_previous_tool = ""

func _place_palette_object(tool: String, drop_pos: Vector2) -> void:
	if tool == "text":
		editor_tool = "text"
		editor_mode = "paint"
		editor_ui.sync_tool_state("text")
		editor_ui.open_text_dialog(_editor_text_anchor_at(drop_pos))
		return
	if tool not in ["crate", "mirror", "player", "goal", "exit"]:
		return
	var cell := _editor_cell_at(drop_pos)
	if not BoardRulesScript.in_bounds(editor_level, cell):
		show_message("请把对象拖到棋盘内", true)
		return
	editor_tool = tool
	editor_mode = "paint"
	editor_ui.sync_tool_state(tool)
	var before: Dictionary = editor_level.to_dict()
	if not _apply_editor_tool(cell):
		return
	editor_history.append(before)
	if editor_history.size() > 100:
		editor_history.pop_front()
	editor_redo.clear()
	editor_dirty = true
	editor_validation_dirty = true
	show_message("已放置" + _tool_name(tool))

func _zoom_editor_at(pos: Vector2, factor: float) -> bool:
	if editor_level == null or editor_ui == null:
		return false
	var area: Rect2 = editor_ui.board_space.get_global_rect().grow(-32.0)
	if not area.has_point(pos):
		return false
	var old_metrics := _grid_metrics()
	var old_cell: float = old_metrics.cell
	if old_cell <= 0.0:
		return false
	var next_cell: float = clampf(old_cell * factor, old_metrics.fit_cell, old_metrics.max_cell)
	if is_equal_approx(next_cell, old_cell):
		return false
	var dimensions := Vector2(editor_level.width, editor_level.height)
	var local: Vector2 = (pos - old_metrics.origin) / old_cell
	editor_cell_size = next_cell
	if is_equal_approx(next_cell, old_metrics.fit_cell):
		editor_pan = Vector2.ZERO
	else:
		editor_pan = pos - (area.get_center() - dimensions * next_cell * 0.5 + local * next_cell)
	queue_redraw()
	return true

func _editor_metadata_changed() -> void:
	if screen != "editor" or editor_level == null:
		return
	editor_level.title = title_edit.text
	editor_level.description = description_edit.text
	editor_dirty = true

func _move_editor_camera(delta: float) -> void:
	if editor_ui.modal_open() or editor_stroke_before != null:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		direction.y -= 1.0
	if Input.is_key_pressed(KEY_S):
		direction.y += 1.0
	if Input.is_key_pressed(KEY_A):
		direction.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		direction.x += 1.0
	if direction == Vector2.ZERO:
		return
	var metrics := _grid_metrics()
	if metrics.cell <= metrics.fit_cell + 0.01:
		editor_pan = Vector2.ZERO
		return
	# WASD moves the camera; the board therefore travels in the opposite direction.
	var speed: float = maxf(180.0, metrics.cell * 4.0)
	editor_pan -= direction.normalized() * speed * delta
	queue_redraw()

func _refresh_editor_validation() -> void:
	editor_validation = ValidatorScript.validate_playability(editor_level)
	editor_validation_dirty = false
	editor_ui.update_issues(editor_validation)

func _focus_editor_issue(issue: Dictionary) -> void:
	_finish_editor_stroke()
	editor_highlight_cells = issue.get("cells", []).duplicate()
	editor_highlight_time = 4.0
	editor_highlight_color = ERROR if issue.get("severity", "error") == "error" else WARNING
	var tool := str(issue.get("tool", ""))
	if not tool.is_empty():
		_select_editor_tool(tool)
		editor_ui.focus_tool(tool)
	show_message(str(issue.get("message", "")))
	message_timer = 5.0

func _load_level(level, from_editor: bool = false) -> void:
	current_level = level.duplicate_level()
	current_state = BoardStateScript.from_level(current_level)
	initial_state = current_state.duplicate_state()
	history = HistoryScript.new()
	submerged_crates.clear()
	splash_effects.clear()
	preview = BoardRulesScript.get_reflection_preview(current_level, current_state)
	screen = "editor_play" if from_editor else "game"
	if not from_editor:
		profile.last_level = current_level.id
		profile.save_profile()
	_set_editor_inputs(false)
	message = "已载入：" + current_level.title
	message_timer = 2.0

func _restart_game() -> void:
	_clear_held_action()
	if current_level == null:
		return
	current_state = initial_state.duplicate_state()
	history.clear()
	submerged_crates.clear()
	splash_effects.clear()
	preview = BoardRulesScript.get_reflection_preview(current_level, current_state)
	show_message("关卡已重开")

func _undo_game() -> void:
	_clear_held_action()
	if history == null or not history.can_undo():
		show_message("没有可撤销的操作")
		return
	current_state = history.pop()
	_sync_submerged_crates()
	splash_effects.clear()
	current_state.won = BoardRulesScript.is_won(current_level, current_state)
	current_state.failed = current_state.players.is_empty()
	preview = BoardRulesScript.get_reflection_preview(current_level, current_state)
	show_message("已撤销；桥、镜子、计数和玩家均已恢复")

func _apply_game_action(action: String) -> void:
	if current_state == null or current_state.won or current_state.failed:
		return
	var was_exit_open := BoardRulesScript.are_goals_complete(current_level, current_state)
	var result = BoardRulesScript.apply_action(current_level, current_state, action)
	if not bool(result.accepted):
		show_message(_reason_text(str(result.reason)), true)
		return
	var pushes: Array = result.get("pushes", [])
	var push_info: Dictionary = result.get("push", {})
	if pushes.is_empty() and not push_info.is_empty():
		pushes = [push_info]
	for push in pushes:
		history.record_push(current_state, push)
	var reflection_info: Dictionary = result.get("reflection", {})
	if not reflection_info.is_empty():
		history.record_reflection(current_state, reflection_info)
	current_state = result.next_state
	var submerged_items: Array = result.get("submerged_crates", [])
	var submerged_crate: Dictionary = result.get("submerged_crate", {})
	if not submerged_crate.is_empty():
		submerged_items.append(submerged_crate)
	var splash_cells: Array = result.get("splash_cells", [])
	var splash_cell: Vector2i = result.get("splash_cell", Vector2i(-1, -1))
	if splash_cell.x >= 0:
		splash_cells.append(splash_cell)
	for submerged_item in submerged_items:
		var visual_crate: Dictionary = submerged_item.duplicate(true)
		var submerged_position: Vector2i = visual_crate.get("position", Vector2i(-1, -1))
		if submerged_position.x >= 0:
			submerged_crates.append(visual_crate)
	for splash_position in splash_cells:
		var splash_position_i: Vector2i = splash_position
		if splash_position_i.x >= 0:
			splash_effects.append({"cell": splash_position_i, "time": 0.0})
	if not splash_cells.is_empty():
		_play_sfx("splash")
	elif "PUSH_CRATE" in result.events:
		_play_sfx("push")
	elif "PUSH_MIRROR" in result.events:
		_play_sfx("mirror")
	elif "TELEPORT" in result.events:
		_play_sfx("teleport")
	elif "MOVE" in result.events:
		_play_sfx("move")
	preview = BoardRulesScript.get_reflection_preview(current_level, current_state)
	if current_state.won:
		_play_sfx("win")
		if screen == "game":
			profile.mark_completed(current_level.id, current_state.action_count)
			profile.save_profile()
		message = "通关！操作数 %d" % current_state.action_count
		message_timer = 4.0
	elif current_state.failed:
		_play_sfx("splash")
		show_message("所有可操控角色都落水，挑战失败", true)
	elif not was_exit_open and BoardRulesScript.are_goals_complete(current_level, current_state):
		show_message("所有箱子已到达箱子终点，出口已打开")

func _reason_text(reason: String) -> String:
	var labels := {"NO_MIRROR": "无法反射：没有可用镜子或同轴对象", "NO_REFLECTION": "无法反射：没有无遮挡的同行/同列对象", "SAME_CELL": "无法传送：投影落在原地", "NOT_ALIGNED": "无法传送：对象需与镜子同行或同列", "BLOCKED_LINE": "无法传送：镜前视线被遮挡", "BLOCKED_RAY": "无法反射：墙体、箱子或角色遮挡了光线", "OUT_OF_BOUNDS": "目的格是水面：反射仍会执行", "DEST_WATER": "目的格是水面：反射仍会执行", "DEST_WALL": "无法反射：目的格是墙", "DEST_OCCUPIED": "无法反射：目的格被占用", "NO_PLAYERS": "所有可操控角色都已落水", "WON": "本关已完成，请撤销或重开"}
	return str(labels.get(reason, "操作失败：" + reason))

func show_message(text: String, is_error: bool = false) -> void:
	message = text
	message_timer = 2.2

func _input_name(action: String) -> String:
	return {"UP": "move_up", "DOWN": "move_down", "LEFT": "move_left", "RIGHT": "move_right"}.get(action, "")

func _clear_held_action() -> void:
	held_action = ""
	held_time = 0.0
	repeat_time = 0.0

func _sync_submerged_crates() -> void:
	if current_state == null:
		submerged_crates.clear()
		return
	for i in range(submerged_crates.size() - 1, -1, -1):
		var cell: Vector2i = submerged_crates[i].get("position", Vector2i(-1, -1))
		if not current_state.has_bridge(cell):
			submerged_crates.remove_at(i)

func _input(event: InputEvent) -> void:
	# Capture the end of a stroke even when the pointer is released over a UI control.
	if screen != "editor" or editor_ui.modal_open():
		return
	# Start palette drags at the root before the Button's own GUI event handling.
	# This prevents the first drag from being consumed by the sidebar control.
	if not editor_palette_drag_active and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var palette_tool: String = editor_ui.palette_tool_at(event.position)
		if not palette_tool.is_empty():
			_start_palette_drag_at(palette_tool, event.position)
			get_viewport().set_input_as_handled()
			return
	if editor_palette_drag_active:
		if event is InputEventMouseMotion:
			if not editor_palette_drag_moved and event.position.distance_to(editor_palette_drag_start) >= 6.0:
				editor_palette_drag_moved = true
			if editor_palette_drag_moved:
				get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			var should_place: bool = editor_palette_drag_moved and editor_ui.board_space.get_global_rect().has_point(event.position)
			var was_moved: bool = editor_palette_drag_moved
			var tool := editor_palette_drag_tool
			_clear_palette_drag(was_moved and not should_place)
			if should_place:
				_place_palette_object(tool, event.position)
				get_viewport().set_input_as_handled()
			elif editor_palette_drag_moved:
				get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		if event.pressed and not editor_ui.board_space.get_global_rect().has_point(event.position):
			return
		if event.pressed:
			_editor_pick_at(event.position, event.shift_pressed)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var zoom_factor := 1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15
		if _zoom_editor_at(event.position, zoom_factor):
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if (event.ctrl_pressed and event.keycode == KEY_S) or event.keycode == KEY_F5:
			_editor_command("save" if event.keycode == KEY_S else "play")
			get_viewport().set_input_as_handled()
			return
	if editor_stroke_before == null:
		return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_finish_editor_stroke(false)
		get_viewport().set_input_as_handled()
	elif editor_drag_active and event is InputEventMouseMotion:
		_editor_drag_to(event.position)
		get_viewport().set_input_as_handled()
	elif editor_drag_active and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_editor_drag_to(event.position)
		_finish_editor_stroke()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		_editor_paint_at(event.position)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		_editor_paint_at(event.position)
		_finish_editor_stroke()
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if screen == "editor" and editor_ui.modal_open():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if screen == "editor" and (focused is LineEdit or focused is TextEdit) and event is InputEventKey:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if screen == "game" or screen == "editor_play":
			_handle_game_key(event)
		elif screen == "editor":
			_handle_editor_key(event)
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if screen == "editor" and event.alt_pressed:
				_editor_pick_at(event.position, event.shift_pressed)
			else:
				_handle_click(event.position, event.double_click)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and screen == "editor":
		_editor_delete_at(event.position)

func _handle_game_key(event: InputEventKey) -> void:
	if event.keycode == KEY_SPACE and current_state != null and current_state.won:
		if screen == "editor_play":
			_return_to_editor()
		else:
			_next_level()
		return
	if event.keycode == KEY_ESCAPE:
		_clear_held_action()
		if screen == "editor_play":
			_return_to_editor()
		else:
			screen = "select"
		return
	if event.keycode == KEY_Z:
		_undo_game()
	elif event.keycode == KEY_R:
		_restart_game()
	elif event.keycode == KEY_SPACE:
		_apply_game_action("MIRROR")
	elif event.keycode in [KEY_UP, KEY_W]:
		_apply_game_action("UP")
		held_action = "UP"
		held_time = 0.0
		repeat_time = 0.0
	elif event.keycode in [KEY_DOWN, KEY_S]:
		_apply_game_action("DOWN")
		held_action = "DOWN"
		held_time = 0.0
		repeat_time = 0.0
	elif event.keycode in [KEY_LEFT, KEY_A]:
		_apply_game_action("LEFT")
		held_action = "LEFT"
		held_time = 0.0
		repeat_time = 0.0
	elif event.keycode in [KEY_RIGHT, KEY_D]:
		_apply_game_action("RIGHT")
		held_action = "RIGHT"
		held_time = 0.0
		repeat_time = 0.0

func _handle_editor_key(event: InputEventKey) -> void:
	if event.keycode == KEY_ESCAPE:
		_request_editor_exit()
	elif event.keycode == KEY_1:
		_select_editor_tool("land")
		show_message("已选择陆地工具（1）")
	elif event.keycode == KEY_2:
		_select_editor_tool("water")
		show_message("已选择水面工具（2）")
	elif event.keycode == KEY_3:
		_select_editor_tool("wall")
		show_message("已选择墙工具（3）")
	elif event.ctrl_pressed and event.keycode == KEY_Z:
		_finish_editor_stroke()
		_editor_undo()
	elif event.ctrl_pressed and event.keycode == KEY_Y:
		_finish_editor_stroke()
		_editor_redo()
	elif event.ctrl_pressed and event.keycode == KEY_S:
		_editor_command("save")
	elif event.keycode == KEY_F5:
		_editor_command("play")
func _handle_click(pos: Vector2, double_click: bool = false) -> void:
	if screen == "menu":
		if Rect2(460, 205, 360, 52).has_point(pos):
			select_page = "formal"
			screen = "select"
		elif Rect2(460, 275, 360, 52).has_point(pos):
			_continue_game()
		elif Rect2(460, 345, 360, 52).has_point(pos):
			_open_editor()
		elif Rect2(460, 415, 360, 52).has_point(pos):
			get_tree().quit()
	elif screen == "select":
		if Rect2(40, 40, 120, 42).has_point(pos):
			screen = "menu"
		if Rect2(460, 610, 360, 48).has_point(pos):
			select_page = "editor" if select_page == "formal" else "formal"
			return
		var showing_custom := select_page == "editor"
		var entries: Array = custom_levels if showing_custom else levels
		for i in range(entries.size()):
			var card := _select_card_rect(i, showing_custom)
			if card.has_point(pos):
				_load_level(entries[i])
				return
	elif screen == "settings":
		if Rect2(40, 40, 120, 42).has_point(pos):
			screen = "menu"
		elif Rect2(440, 260, 400, 58).has_point(pos):
			profile.muted = not profile.muted
			profile.save_profile()
			show_message("音效已%s" % ("静音" if profile.muted else "开启"))
	elif screen == "game" or screen == "editor_play":
		_handle_game_click(pos)
	elif screen == "editor":
		_handle_editor_click(pos, double_click)

func _continue_game() -> void:
	for level in levels:
		if level.id == profile.last_level:
			_load_level(level)
			return
	if not levels.is_empty():
		_load_level(levels[0])

func _handle_game_click(pos: Vector2) -> void:
	if Rect2(1030, 34, 180, 42).has_point(pos):
		if screen == "editor_play":
			_return_to_editor()
		else:
			screen = "select"
		return
	if Rect2(820, 34, 90, 42).has_point(pos):
		_undo_game()
	elif Rect2(920, 34, 90, 42).has_point(pos):
		_restart_game()
	elif current_state != null and current_state.won:
		if Rect2(350, 520, 180, 48).has_point(pos):
			_restart_game()
		elif Rect2(550, 520, 180, 48).has_point(pos):
			if screen == "editor_play":
				_return_to_editor()
			else:
				_next_level()
		elif Rect2(750, 520, 180, 48).has_point(pos):
			if screen == "editor_play":
				_return_to_editor()
			else:
				screen = "select"
	elif current_state != null and current_state.failed:
		if Rect2(440, 520, 180, 48).has_point(pos):
			_restart_game()
		elif Rect2(650, 520, 180, 48).has_point(pos):
			if screen == "editor_play":
				_return_to_editor()
			else:
				screen = "select"

func _next_level() -> void:
	var index := _level_index(current_level.id)
	if index >= 0 and index + 1 < levels.size():
		_load_level(levels[index + 1])
	else:
		screen = "select"
		show_message("六关已完成，感谢体验")

func _level_index(id: String) -> int:
	for i in range(levels.size()):
		if levels[i].id == id:
			return i
	return -1

func _open_editor() -> void:
	editor_level = LevelDataScript.new().make_blank(16, 16)
	editor_level.id = "custom_draft"
	editor_level.title = "我的镜岛关卡"
	editor_level.description = ""
	editor_history.clear()
	editor_redo.clear()
	editor_dirty = false
	editor_tool = "land"
	editor_mode = "paint"
	_reset_editor_view()
	screen = "editor"
	_set_editor_inputs(true, true)

func _return_to_editor() -> void:
	if editor_play_origin != null:
		editor_level = editor_play_origin.duplicate_level()
	screen = "editor"
	_set_editor_inputs(true, true)
	show_message("已返回编辑器，试玩不会改动草稿")

func _new_editor(w: int, h: int) -> void:
	editor_level = LevelDataScript.new().make_blank(w, h)
	editor_level.id = "custom_draft_%d" % Time.get_ticks_msec()
	editor_level.title = "新建 %d×%d 关卡" % [w, h]
	editor_level.description = ""
	editor_history.clear()
	editor_redo.clear()
	editor_dirty = false
	_reset_editor_view()
	screen = "editor"
	_set_editor_inputs(true, true)

func _editor_command(action: String) -> void:
	_finish_editor_stroke()
	title_edit.release_focus()
	description_edit.release_focus()
	if action in ["new", "open", "import", "menu"] and editor_dirty:
		pending_confirm = action
		editor_ui.discard_dialog.popup_centered(Vector2i(460, 170))
		return
	if action in ["save_and_continue", "discard_and_continue"]:
		if action == "save_and_continue":
			editor_save()
			if editor_dirty:
				return
		var next_action := pending_confirm
		pending_confirm = ""
		_execute_editor_command(next_action)
		return
	_execute_editor_command(action)

func _execute_editor_command(action: String) -> void:
	match action:
		"new": editor_ui.open_size_dialog("new", 16, 16)
		"open": editor_ui.open_level_dialog()
		"save": editor_save()
		"save_as": editor_save_as()
		"import": editor_import()
		"export": editor_export()
		"undo": _editor_undo()
		"redo": _editor_redo()
		"play": _editor_play()
		"menu":
			screen = "menu"
			_set_editor_inputs(false)

func _editor_size_requested(kind: String, width: int, height: int) -> void:
	_finish_editor_stroke()
	if kind == "new":
		_new_editor(width, height)
		return
	if editor_level.width == width and editor_level.height == height:
		show_message("棋盘已经是 %d × %d" % [width, height])
		return
	var result: Dictionary = editor_level.resized_copy(width, height)
	if kind != "crop_confirmed" and (result.removed_terrain > 0 or result.removed_entities > 0 or result.removed_markers > 0):
		editor_ui.confirm_crop(width, height, "调整为 %d × %d，将裁掉：\n%d 格陆地/墙、%d 个实体、%d 个地面标记。" % [width, height, result.removed_terrain, result.removed_entities, result.removed_markers])
		return
	editor_stroke_before = editor_level.to_dict()
	editor_stroke_dirty_before = editor_dirty
	editor_stroke_changed = true
	editor_level = result.level
	editor_dirty = true
	_finish_editor_stroke()
	_set_editor_inputs(true, true)
	show_message("棋盘已调整为 %d × %d · 新增区域为水面 · Ctrl+Z 可恢复" % [width, height])

func _request_editor_exit() -> void:
	_editor_command("menu")

func _handle_editor_click(pos: Vector2, double_click: bool = false) -> void:
	var text_hit := _editor_text_hit_at(pos) if editor_tool == "text" else {}
	if not text_hit.is_empty():
		var text_index: int = text_hit.index
		var text_position: Vector2 = text_hit.position
		if text_hit.action == "edit" or (text_hit.action == "body" and double_click):
			editor_ui.open_text_dialog(text_position, editor_level.texts[text_index].duplicate(true))
		else:
			_start_editor_drag({"tool": "text", "index": text_index, "cell": Vector2i(floorf(text_position.x + 0.5), floorf(text_position.y + 0.5)), "position": text_position, "pointer": pos})
		return
	if editor_tool == "text":
		title_edit.release_focus()
		description_edit.release_focus()
		editor_ui.open_text_dialog(_editor_text_anchor_at(pos))
		return
	if not _editor_grid_rect().has_point(pos):
		return
	title_edit.release_focus()
	description_edit.release_focus()
	var cell := _editor_cell_at(pos)
	var drag_target := _editor_drag_target_at(cell)
	if not drag_target.is_empty():
		_start_editor_drag(drag_target)
		return
	if editor_mode == "pick":
		_editor_pick_at(pos)
		return
	editor_stroke_before = editor_level.to_dict()
	editor_stroke_dirty_before = editor_dirty
	editor_stroke_changed = false
	editor_stroke_visited.clear()
	editor_stroke_last = Vector2i(-1, -1)
	if editor_mode == "rectangle":
		editor_rect_start = _editor_cell_at(pos)
		editor_rect_end = editor_rect_start
	_editor_paint_at(pos)

func _start_editor_drag(target: Dictionary) -> void:
	_finish_editor_stroke()
	editor_drag_active = true
	editor_drag_tool = str(target.get("tool", ""))
	editor_drag_index = int(target.get("index", -1))
	editor_drag_source = target.get("cell", Vector2i(-1, -1))
	editor_drag_current = editor_drag_source
	editor_stroke_before = editor_level.to_dict()
	editor_stroke_dirty_before = editor_dirty
	editor_stroke_changed = false
	editor_stroke_visited.clear()
	if editor_drag_tool == "text":
		editor_drag_text_current = target.get("position", Vector2.ZERO)
		editor_drag_text_grab_offset = _editor_text_anchor_at(target.get("pointer", get_global_mouse_position())) - editor_drag_text_current
	show_message("拖动" + _tool_name(editor_drag_tool) + " · 松开鼠标放置")

func _editor_drag_to(pos: Vector2) -> void:
	if not editor_drag_active:
		return
	if editor_drag_tool == "text":
		var next_text_position := _editor_text_anchor_at(pos) - editor_drag_text_grab_offset
		if next_text_position.distance_to(editor_drag_text_current) < 0.001:
			return
		_move_editor_drag_target(next_text_position)
		editor_drag_text_current = next_text_position
		editor_stroke_changed = true
		editor_dirty = true
		editor_validation_dirty = true
		return
	if not _editor_grid_rect().has_point(pos):
		return
	var cell := _editor_cell_at(pos)
	if cell == editor_drag_current or not _can_move_editor_drag_to(cell):
		return
	_move_editor_drag_target(cell)
	editor_drag_current = cell
	editor_stroke_changed = true
	editor_dirty = true
	editor_validation_dirty = true

func _can_move_editor_drag_to(cell: Vector2i) -> bool:
	if not BoardRulesScript.in_bounds(editor_level, cell):
		return false
	match editor_drag_tool:
		"crate", "mirror", "player":
			return editor_level.terrain_at(cell) == "." and _editor_entity_at(cell).is_empty()
		"goal":
			return editor_level.terrain_at(cell) == "." and _editor_entity_at(cell).is_empty() and cell != editor_level.exit_cell and not cell in editor_level.goals
		"exit":
			return editor_level.terrain_at(cell) == "." and _editor_entity_at(cell).is_empty() and not cell in editor_level.goals
	return false

func _move_editor_drag_target(target: Variant) -> void:
	if editor_drag_tool == "text":
		editor_level.texts[editor_drag_index]["position"] = target
		return
	var cell: Vector2i = target
	match editor_drag_tool:
		"crate":
			editor_level.crates[editor_drag_index]["position"] = cell
		"mirror":
			editor_level.mirrors[editor_drag_index]["position"] = cell
			if editor_drag_index == 0:
				editor_level.mirror = editor_level.mirrors[0].duplicate(true)
		"player":
			if editor_drag_index >= 0:
				editor_level.players[editor_drag_index]["position"] = cell
				if editor_drag_index == 0:
					editor_level.player = cell
			else:
				editor_level.player = cell
		"goal":
			editor_level.goals[editor_drag_index] = cell
		"exit":
			editor_level.exit_cell = cell

func _editor_drag_target_at(cell: Vector2i) -> Dictionary:
	for i in range(editor_level.crates.size()):
		if editor_level.crates[i].get("position", Vector2i(-1, -1)) == cell:
			return {"tool": "crate", "index": i, "cell": cell}
	for i in range(editor_level.mirrors.size()):
		if editor_level.mirrors[i].get("position", Vector2i(-1, -1)) == cell:
			return {"tool": "mirror", "index": i, "cell": cell}
	for i in range(editor_level.players.size()):
		if editor_level.players[i].get("position", Vector2i(-1, -1)) == cell:
			return {"tool": "player", "index": i, "cell": cell}
	if editor_level.players.is_empty() and editor_level.player == cell:
		return {"tool": "player", "index": -1, "cell": cell}
	if editor_level.exit_cell == cell:
		return {"tool": "exit", "index": -1, "cell": cell}
	for i in range(editor_level.goals.size()):
		if editor_level.goals[i] == cell:
			return {"tool": "goal", "index": i, "cell": cell}
	return {}

func _tool_name(tool: String) -> String:
	if tool == "mirror":
		return "镜子（点击旋转）"
	return {"land": "陆地", "water": "水面", "wall": "墙", "crate": "箱子", "mirror_slash": "镜子 /", "mirror_backslash": "镜子 \\", "player": "玩家", "goal": "箱子终点", "exit": "出口", "text": "字体", "erase": "擦除"}.get(tool, tool)

func _grid_metrics() -> Dictionary:
	var area: Rect2 = editor_ui.board_space.get_global_rect()
	area = area.grow(-32.0)
	var grid_size := Vector2(editor_level.width, editor_level.height)
	var fit_cell := maxf(1.0, floorf(minf(area.size.x / grid_size.x, area.size.y / grid_size.y)))
	var max_cell := maxf(fit_cell, floorf(area.size.y / EDITOR_MAX_VISIBLE_ROWS))
	var cell := fit_cell if editor_cell_size <= 0.0 else clampf(editor_cell_size, fit_cell, max_cell)
	return {"origin": (area.get_center() - grid_size * cell * 0.5 + editor_pan).floor(), "cell": cell, "fit_cell": fit_cell, "max_cell": max_cell}

func _editor_grid_rect() -> Rect2:
	var metrics := _grid_metrics()
	return Rect2(metrics.origin, Vector2(editor_level.width, editor_level.height) * metrics.cell)

func _editor_cell_at(pos: Vector2) -> Vector2i:
	var metrics := _grid_metrics()
	var local = (pos - metrics.origin) / float(metrics.cell)
	return Vector2i(floori(local.x), floori(local.y))

func _editor_text_anchor_at(pos: Vector2) -> Vector2:
	var metrics := _grid_metrics()
	if metrics.cell <= 0.0:
		return Vector2.ZERO
	# 文字位置以棋盘左上角为原点、以格子为单位，但允许任意小数和负数。
	return (pos - metrics.origin) / float(metrics.cell) - Vector2(0.5, 0.5)

func _editor_paint_at(pos: Vector2) -> void:
	if screen != "editor" or editor_level == null or editor_stroke_before == null:
		return
	var cell := _editor_cell_at(pos)
	if editor_mode == "rectangle":
		editor_rect_end = Vector2i(clampi(cell.x, 0, editor_level.width - 1), clampi(cell.y, 0, editor_level.height - 1))
		return
	if not BoardRulesScript.in_bounds(editor_level, cell):
		editor_stroke_last = Vector2i(-1, -1)
		return
	if editor_stroke_last.x < 0:
		editor_stroke_last = cell
	var distance := cell - editor_stroke_last
	var steps := maxi(absi(distance.x), absi(distance.y))
	for step in range(steps + 1):
		var at := Vector2i(Vector2(editor_stroke_last).lerp(Vector2(cell), float(step) / maxi(1, steps)).round())
		if editor_stroke_visited.has(at):
			continue
		editor_stroke_visited[at] = true
		if _apply_editor_tool(at):
			editor_stroke_changed = true
			editor_dirty = true
			editor_validation_dirty = true
	editor_stroke_last = cell

func _finish_editor_stroke(commit: bool = true) -> void:
	if editor_stroke_before != null:
		if commit and editor_rect_start.x >= 0:
			_apply_editor_rectangle()
		if commit and editor_drag_active and not editor_stroke_changed and editor_drag_tool == "mirror":
			editor_stroke_changed = _rotate_editor_mirror_at(editor_drag_current)
			if editor_stroke_changed:
				editor_dirty = true
		if not commit:
			editor_level = LevelDataScript.from_dict(editor_stroke_before)
			editor_dirty = editor_stroke_dirty_before
			show_message("已取消当前绘制")
		elif editor_stroke_changed:
			editor_history.append(editor_stroke_before)
			if editor_history.size() > 100:
				editor_history.pop_front()
			editor_redo.clear()
		editor_stroke_before = null
		editor_stroke_changed = false
		editor_stroke_visited.clear()
		editor_stroke_last = Vector2i(-1, -1)
		editor_rect_start = Vector2i(-1, -1)
		editor_rect_end = Vector2i(-1, -1)
		editor_drag_active = false
		editor_drag_tool = ""
		editor_drag_index = -1
		editor_drag_source = Vector2i(-1, -1)
		editor_drag_current = Vector2i(-1, -1)
		editor_drag_text_current = Vector2.ZERO
		editor_drag_text_grab_offset = Vector2.ZERO
		editor_validation_dirty = true
		editor_highlight_cells.clear()

func _apply_editor_rectangle() -> void:
	var start := Vector2i(mini(editor_rect_start.x, editor_rect_end.x), mini(editor_rect_start.y, editor_rect_end.y))
	var end := Vector2i(maxi(editor_rect_start.x, editor_rect_end.x), maxi(editor_rect_start.y, editor_rect_end.y))
	var changed := 0
	var skipped := 0
	for y in range(start.y, end.y + 1):
		for x in range(start.x, end.x + 1):
			var cell := Vector2i(x, y)
			if editor_tool != "land" and (not _editor_entity_at(cell).is_empty() or not _editor_marker_at(cell).is_empty()):
				skipped += 1
				continue
			if _apply_editor_tool(cell):
				changed += 1
	editor_stroke_changed = changed > 0
	if editor_stroke_changed:
		editor_dirty = true
	show_message("矩形绘制：修改 %d 格，跳过 %d 个有对象/标记的格子" % [changed, skipped])

func _select_editor_tool(tool: String) -> void:
	_finish_editor_stroke()
	editor_tool = tool
	editor_ui.sync_tool_state(tool)
	if editor_mode == "pick" or (editor_mode == "rectangle" and tool not in ["land", "water", "wall"]):
		editor_mode = "paint"
	title_edit.release_focus()
	description_edit.release_focus()

func _select_editor_mode(mode: String) -> void:
	_finish_editor_stroke()
	editor_mode = mode
	if mode == "rectangle" and editor_tool not in ["land", "water", "wall"]:
		editor_tool = "land"
	title_edit.release_focus()
	description_edit.release_focus()

func _editor_pick_at(pos: Vector2, terrain_only: bool = false) -> void:
	if editor_level == null:
		return
	if not terrain_only:
		var text_hit := _editor_text_hit_at(pos)
		if not text_hit.is_empty():
			_finish_editor_stroke()
			_select_editor_tool("text")
			editor_ui.focus_tool("text")
			show_message("已吸取：字体 · 下一次左键使用此工具")
			return
	if not _editor_grid_rect().has_point(pos):
		return
	_finish_editor_stroke()
	var cell := _editor_cell_at(pos)
	var tool := "" if terrain_only else _editor_entity_at(cell)
	if tool.is_empty() and not terrain_only:
		tool = _editor_marker_at(cell)
	if tool.is_empty() and not terrain_only and _editor_text_index_at(cell) >= 0:
		tool = "text"
	if tool.is_empty():
		tool = {".": "land", "~": "water", "#": "wall"}.get(editor_level.terrain_at(cell), "land")
	if tool == "mirror":
		var index := _editor_mirror_index_at(cell)
		editor_mirror_orientation = str(editor_level.mirrors[index].get("orientation", "slash"))
		editor_ui.set_mirror_orientation(editor_mirror_orientation)
	editor_mode = "paint"
	_select_editor_tool(tool)
	editor_ui.focus_tool(tool)
	show_message("已吸取：" + _tool_name(tool) + " · 下一次左键使用此工具")

func _apply_editor_tool(cell: Vector2i) -> bool:
	var entity := _editor_entity_at(cell)
	var marker := _editor_marker_at(cell)
	if editor_tool in ["land", "water", "wall"]:
		var value = {"land": ".", "water": "~", "wall": "#"}[editor_tool]
		if value != "." and (not entity.is_empty() or not marker.is_empty()):
			show_message("不能把有对象/标记的格改成水或墙，请先擦除", true)
			return false
		if editor_level.terrain_at(cell) == value:
			return false
		editor_level.set_terrain(cell, value)
		return true
	if editor_tool == "erase":
		return _erase_any_editor_at(cell)
	if editor_level.terrain_at(cell) != ".":
		show_message("对象和标记只能放在陆地", true)
		return false
	if editor_tool in ["crate", "mirror", "player", "goal", "exit"] and (not entity.is_empty() or not marker.is_empty()):
		show_message("对象和标记不能互相覆盖，请先移动或右键删除", true)
		return false
	if editor_tool == "crate":
		if not entity.is_empty() or cell == editor_level.player:
			show_message("实体不能叠放", true)
			return false
		editor_level.crates.append({"id": _next_editor_entity_id("crate", editor_level.crates), "position": cell})
		return true
	if editor_tool == "mirror":
		if not entity.is_empty() and entity != "mirror":
			show_message("镜子不能覆盖其他实体", true)
			return false
		var mirror_index := _editor_mirror_index_at(cell)
		if mirror_index < 0:
			editor_level.mirrors.append({"id": _next_editor_entity_id("mirror", editor_level.mirrors), "position": cell, "orientation": editor_mirror_orientation})
			if editor_level.mirrors.size() == 1:
				editor_level.mirror = editor_level.mirrors[0].duplicate(true)
			show_message("已放置镜子；再次点击镜子可旋转 90°")
		else:
			_rotate_editor_mirror_at(cell)
		return true
	if editor_tool == "player":
		if not entity.is_empty():
			show_message("玩家不能覆盖实体", true)
			return false
		editor_level.player = cell
		if editor_level.players.is_empty():
			editor_level.players.append({"id": "player_01", "position": cell, "alive": true})
		else:
			editor_level.players[0]["position"] = cell
		return true
	if editor_tool == "goal":
		if cell == editor_level.exit_cell or cell in editor_level.goals:
			return false
		editor_level.goals.append(cell)
		return true
	if editor_tool == "exit":
		if cell in editor_level.goals:
			show_message("出口不能覆盖目标板", true)
			return false
		editor_level.exit_cell = cell
		return true
	if editor_tool == "erase":
		return _erase_any_editor_at(cell)
	return false

func _rotate_editor_mirror_at(cell: Vector2i) -> bool:
	var mirror_index := _editor_mirror_index_at(cell)
	if mirror_index < 0:
		return false
	editor_level.mirrors[mirror_index]["orientation"] = "backslash" if str(editor_level.mirrors[mirror_index].get("orientation", "slash")) == "slash" else "slash"
	if mirror_index == 0:
		editor_level.mirror = editor_level.mirrors[0].duplicate(true)
	show_message("镜子已旋转 90°")
	return true

func _editor_delete_at(pos: Vector2) -> void:
	if screen != "editor" or editor_level == null:
		return
	var text_hit := _editor_text_hit_at(pos)
	if not text_hit.is_empty():
		title_edit.release_focus()
		description_edit.release_focus()
		if editor_stroke_before != null:
			_finish_editor_stroke()
		editor_stroke_before = editor_level.to_dict()
		editor_stroke_dirty_before = editor_dirty
		editor_stroke_changed = true
		editor_level.texts.remove_at(int(text_hit.index))
		editor_dirty = true
		_finish_editor_stroke()
		return
	var metrics := _grid_metrics()
	var grid_rect := Rect2(metrics.origin, Vector2(editor_level.width, editor_level.height) * metrics.cell)
	if not grid_rect.has_point(pos):
		return
	title_edit.release_focus()
	description_edit.release_focus()
	var cell := _editor_cell_at(pos)
	if not BoardRulesScript.in_bounds(editor_level, cell):
		return
	if editor_stroke_before != null:
		_finish_editor_stroke()
	editor_stroke_before = editor_level.to_dict()
	editor_stroke_dirty_before = editor_dirty
	editor_stroke_changed = _erase_any_editor_at(cell)
	if editor_stroke_changed:
		editor_dirty = true
	_finish_editor_stroke()

func _delete_editor_tool(cell: Vector2i) -> bool:
	if editor_tool == "crate":
		for i in range(editor_level.crates.size() - 1, -1, -1):
			if editor_level.crates[i].position == cell:
				editor_level.crates.remove_at(i)
				return true
	if editor_tool == "mirror":
		var mirror_index := _editor_mirror_index_at(cell)
		if mirror_index >= 0:
			editor_level.mirrors.remove_at(mirror_index)
			editor_level.mirror = editor_level.mirrors[0].duplicate(true) if not editor_level.mirrors.is_empty() else {}
			return true
	if editor_tool == "player":
		return _erase_editor_player(cell)
	if editor_tool == "goal":
		for i in range(editor_level.goals.size() - 1, -1, -1):
			if editor_level.goals[i] == cell:
				editor_level.goals.remove_at(i)
				return true
	if editor_tool == "exit" and editor_level.exit_cell == cell:
		editor_level.exit_cell = Vector2i(-1, -1)
		return true
	if editor_tool == "text":
		var text_index := _editor_text_index_at(cell)
		if text_index >= 0:
			editor_level.texts.remove_at(text_index)
			return true
	if editor_tool == "erase":
		return _erase_any_editor_at(cell)
	return false

func _erase_any_editor_at(cell: Vector2i) -> bool:
	for i in range(editor_level.crates.size() - 1, -1, -1):
		if editor_level.crates[i].position == cell:
			editor_level.crates.remove_at(i)
			return true
	var mirror_index := _editor_mirror_index_at(cell)
	if mirror_index >= 0:
		editor_level.mirrors.remove_at(mirror_index)
		editor_level.mirror = editor_level.mirrors[0].duplicate(true) if not editor_level.mirrors.is_empty() else {}
		return true
	if _erase_editor_player(cell):
		return true
	for i in range(editor_level.goals.size() - 1, -1, -1):
		if editor_level.goals[i] == cell:
			editor_level.goals.remove_at(i)
			return true
	if editor_level.exit_cell == cell:
		editor_level.exit_cell = Vector2i(-1, -1)
		return true
	var text_index := _editor_text_index_at(cell)
	if text_index >= 0:
		editor_level.texts.remove_at(text_index)
		return true
	return false

func _editor_entity_at(cell: Vector2i) -> String:
	for crate in editor_level.crates:
		if crate.position == cell:
			return "crate"
	if _editor_mirror_index_at(cell) >= 0:
		return "mirror"
	for player in editor_level.players:
		if player.get("position", Vector2i(-1, -1)) == cell:
			return "player"
	if editor_level.players.is_empty() and editor_level.player == cell:
		return "player"
	return ""

func _erase_editor_player(cell: Vector2i) -> bool:
	for i in range(editor_level.players.size() - 1, -1, -1):
		if editor_level.players[i].get("position", Vector2i(-1, -1)) == cell:
			editor_level.players.remove_at(i)
			editor_level.player = editor_level.players[0].get("position", Vector2i(-1, -1)) if not editor_level.players.is_empty() else Vector2i(-1, -1)
			return true
	if editor_level.players.is_empty() and editor_level.player == cell:
		editor_level.player = Vector2i(-1, -1)
		return true
	return false

func _editor_mirror_index_at(cell: Vector2i) -> int:
	for i in range(editor_level.mirrors.size()):
		if editor_level.mirrors[i].get("position", Vector2i(-1, -1)) == cell:
			return i
	return -1

func _editor_text_index_at(cell: Vector2i) -> int:
	for i in range(editor_level.texts.size() - 1, -1, -1):
		var text_position := _text_position_from_record(editor_level.texts[i])
		var text_cell := Vector2i(floorf(text_position.x + 0.5), floorf(text_position.y + 0.5))
		if text_cell == cell:
			return i
	return -1

func _editor_text_index_at_position(position: Vector2) -> int:
	for i in range(editor_level.texts.size() - 1, -1, -1):
		if _text_position_from_record(editor_level.texts[i]).distance_to(position) < 0.001:
			return i
	return -1

func _editor_text_at(cell: Vector2i) -> Dictionary:
	var index := _editor_text_index_at(cell)
	return editor_level.texts[index].duplicate(true) if index >= 0 else {}

func _text_position_from_record(record: Dictionary) -> Vector2:
	var raw = record.get("position", Vector2(-1.0, -1.0))
	if raw is Vector2:
		return raw
	if raw is Vector2i:
		return Vector2(raw)
	if raw is Array and raw.size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2(-1.0, -1.0)

func _editor_text_hit_at(pos: Vector2) -> Dictionary:
	var metrics := _grid_metrics()
	var origin: Vector2 = metrics.origin
	var cell: float = metrics.cell
	for i in range(editor_level.texts.size() - 1, -1, -1):
		var record: Dictionary = editor_level.texts[i]
		var text_position := _text_position_from_record(record)
		var visual := _text_visual_data(origin + text_position * cell, cell, record)
		var radius: float = visual.handle_radius
		if pos.distance_to(visual.edit_center) <= radius + 3.0:
			return {"index": i, "cell": Vector2i(floorf(text_position.x + 0.5), floorf(text_position.y + 0.5)), "position": text_position, "action": "edit"}
		if pos.distance_to(visual.drag_center) <= radius + 3.0:
			return {"index": i, "cell": Vector2i(floorf(text_position.x + 0.5), floorf(text_position.y + 0.5)), "position": text_position, "action": "drag"}
		if visual.background.has_point(pos):
			return {"index": i, "cell": Vector2i(floorf(text_position.x + 0.5), floorf(text_position.y + 0.5)), "position": text_position, "action": "body"}
	return {}

func _editor_text_requested(position: Vector2, content: String, font_size: int, color: String, background_alpha: float) -> void:
	if editor_level == null:
		return
	var clean_content := content.strip_edges()
	if clean_content.is_empty():
		show_message("字体内容不能为空", true)
		return
	var before: Dictionary = editor_level.to_dict()
	var index := _editor_text_index_at_position(position)
	var record := {
		"id": _next_editor_entity_id("text", editor_level.texts),
		"position": position,
		"text": clean_content,
		"size": clampi(font_size, 8, 96),
		"color": color.strip_edges() if not color.strip_edges().is_empty() else "#eef5ff",
		"background_alpha": clampf(background_alpha, 0.0, 1.0)
	}
	if index >= 0:
		record["id"] = str(editor_level.texts[index].get("id", record["id"]))
		editor_level.texts[index] = record
	else:
		editor_level.texts.append(record)
	editor_history.append(before)
	if editor_history.size() > 100:
		editor_history.pop_front()
	editor_redo.clear()
	editor_dirty = true
	editor_validation_dirty = true
	show_message("已%s字体" % ("更新" if index >= 0 else "添加"))

func _next_editor_entity_id(prefix: String, records: Array) -> String:
	var index := 1
	while true:
		var candidate := "%s_%02d" % [prefix, index]
		var taken := false
		for record in records:
			if str(record.get("id", "")) == candidate:
				taken = true
				break
		if not taken:
			return candidate
		index += 1
	return "%s_%02d" % [prefix, index]

func _editor_marker_at(cell: Vector2i) -> String:
	if editor_level.exit_cell == cell:
		return "exit"
	if cell in editor_level.goals:
		return "goal"
	return ""

func _editor_undo() -> void:
	if editor_history.is_empty():
		show_message("编辑历史为空")
		return
	editor_redo.append(editor_level.to_dict())
	editor_level = LevelDataScript.from_dict(editor_history.pop_back())
	editor_dirty = true
	_set_editor_inputs(true, true)

func _editor_redo() -> void:
	if editor_redo.is_empty():
		show_message("没有可重做的编辑")
		return
	editor_history.append(editor_level.to_dict())
	editor_level = LevelDataScript.from_dict(editor_redo.pop_back())
	editor_dirty = true
	_set_editor_inputs(true, true)

func editor_save() -> void:
	if editor_level == null:
		return
	var result = RepositoryScript.save_level(editor_level)
	if bool(result.ok):
		editor_dirty = false
		_load_custom_levels()
		show_message("已保存到 user://levels/%s.json" % editor_level.id)
	else:
		show_message("保存失败：" + str(result.error), true)

func editor_save_as() -> void:
	if editor_level == null:
		return
	editor_ui.open_save_as_dialog(editor_level.id, "user://levels")

func _editor_save_as_requested(directory: String, file_name: String) -> void:
	if editor_level == null:
		return
	var clean_directory := directory.strip_edges()
	if clean_directory.is_empty():
		clean_directory = "user://levels"
	var clean_name := file_name.strip_edges()
	if clean_name.to_lower().ends_with(".json"):
		clean_name = clean_name.left(clean_name.length() - 5).strip_edges()
	if clean_name.is_empty() or clean_name in [".", ".."] or clean_name.find("/") >= 0 or clean_name.find("\\") >= 0:
		show_message("文件名不能为空，且不能包含路径分隔符", true)
		return
	var separator := "" if clean_directory.ends_with("/") or clean_directory.ends_with("\\") else "/"
	var output_path := clean_directory + separator + clean_name + ".json"
	var absolute_path := ProjectSettings.globalize_path(output_path)
	var absolute_directory := absolute_path.get_base_dir()
	var directory_result := DirAccess.make_dir_recursive_absolute(absolute_directory)
	if directory_result != OK and not DirAccess.dir_exists_absolute(absolute_directory):
		show_message("另存为失败：无法创建目录（%s）" % directory_result, true)
		return
	var safe_id := RepositoryScript.sanitize_id(clean_name)
	editor_level.id = safe_id if not safe_id.is_empty() else "custom_%d" % Time.get_ticks_msec()
	var temp_path := absolute_path + ".tmp"
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		show_message("另存为失败：无法写入目标地址", true)
		return
	file.store_string(JSON.stringify(editor_level.to_dict(), "\t"))
	file.flush()
	file.close()
	if not FileAccess.file_exists(temp_path):
		show_message("另存为失败：临时文件未生成", true)
		return
	if FileAccess.file_exists(absolute_path):
		var remove_result := DirAccess.remove_absolute(absolute_path)
		if remove_result != OK:
			show_message("另存为失败：无法覆盖目标文件（%s）" % remove_result, true)
			return
	var renamed := DirAccess.rename_absolute(temp_path, absolute_path)
	if renamed != OK:
		show_message("另存为失败：无法完成文件替换（%s）" % renamed, true)
		return
	editor_dirty = false
	if output_path.begins_with("user://levels"):
		_load_custom_levels()
	show_message("已另存为：" + output_path)

func editor_export() -> void:
	if editor_level == null:
		return
	RepositoryScript.ensure_dirs()
	var path := "user://levels/exported_%s.json" % RepositoryScript.sanitize_id(editor_level.id)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(editor_level.to_dict(), "\t"))
		file.close()
		show_message("已导出：" + path)

func editor_import() -> void:
	var loaded = RepositoryScript.load_level_path("user://levels/imported.json")
	if not bool(loaded.ok):
		show_message("导入入口等待文件：user://levels/imported.json", true)
		return
	editor_level = loaded.level
	editor_dirty = false
	editor_history.clear()
	editor_redo.clear()
	_reset_editor_view()
	_set_editor_inputs(true, true)
	show_message("JSON 导入成功")

func _editor_open_file_requested(path: String) -> void:
	var loaded := RepositoryScript.load_level_path(path)
	if not bool(loaded.get("ok", false)):
		show_message("打开失败：" + str(loaded.get("error", "关卡文件无效")), true)
		return
	editor_level = loaded.level
	editor_dirty = false
	editor_history.clear()
	editor_redo.clear()
	_reset_editor_view()
	_set_editor_inputs(true, true)
	var playable: Dictionary = loaded.get("playable", {})
	var warnings: Array = playable.get("warnings", [])
	show_message("已打开：%s%s" % [editor_level.title, "（有校验提示）" if not warnings.is_empty() else ""])

func _editor_play() -> void:
	var format_errors = ValidatorScript.validate_format(editor_level.to_dict())
	var playable = ValidatorScript.validate_playability(editor_level)
	if not format_errors.is_empty() or not playable.errors.is_empty():
		_refresh_editor_validation()
		for issue in playable.get("issues", []):
			if issue.get("severity", "") == "error":
				_focus_editor_issue(issue)
				break
		show_message("尚不能试玩：" + "; ".join(format_errors + playable.errors), true)
		return
	editor_play_origin = editor_level.duplicate_level()
	_load_level(editor_level, true)

func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), BG)
	if screen == "game" or screen == "editor_play":
		_draw_game_backdrop(size)
		_draw_game()
	elif screen == "menu":
		_draw_menu()
	elif screen == "select":
		_draw_select()
	elif screen == "settings":
		_draw_settings()
	elif screen == "editor":
		_draw_editor()
	if message != "" and screen != "editor":
		draw_rect(Rect2(30, size.y - 52, size.x - 60, 32), Color("#000000aa"))
		draw_string(font, Vector2(48, size.y - 30), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, TEXT)

func _draw_menu() -> void:
	draw_string(font, Vector2(0, 100), "镜岛推箱", HORIZONTAL_ALIGNMENT_CENTER, get_viewport_rect().size.x, 48, TEXT)
	draw_string(font, Vector2(0, 145), "Mirror Isles Workshop · Godot 4.6", HORIZONTAL_ALIGNMENT_CENTER, get_viewport_rect().size.x, 17, MUTED)
	_draw_button(Rect2(460, 205, 360, 52), "开始 / 选关", true)
	_draw_button(Rect2(460, 275, 360, 52), "继续：" + profile.last_level)
	_draw_button(Rect2(460, 345, 360, 52), "关卡编辑器")
	_draw_button(Rect2(460, 415, 360, 52), "退出")
	draw_string(font, Vector2(0, 650), "方向键 / WASD 移动 · Space 镜像 · Z 撤销 · R 重开 · Esc 返回", HORIZONTAL_ALIGNMENT_CENTER, get_viewport_rect().size.x, 16, MUTED)

func _draw_game_backdrop(size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, size), WATER_DEEP)
	var wave_color := Color("#4d9fba55")
	for y in range(105, int(size.y), 42):
		for x in range(-40, int(size.x) + 40, 92):
			var start := Vector2(x + ((y / 42) % 2) * 28, y)
			draw_line(start, start + Vector2(26, -5), wave_color, 2.0)
			draw_line(start + Vector2(26, -5), start + Vector2(52, 0), wave_color, 2.0)

func _draw_select() -> void:
	var showing_custom := select_page == "editor"
	var entries: Array = custom_levels if showing_custom else levels
	var page_title := "编辑器关卡" if showing_custom else "正式关卡"
	var page_subtitle := "选择一个编辑器关卡开始；可回到编辑器继续修改" if showing_custom else "选择一个正式关卡开始；完成记录与最佳操作数会保存在本机"
	_draw_header(page_title, page_subtitle)
	_draw_button(Rect2(40, 40, 120, 42), "返回")
	if entries.is_empty():
		draw_string(font, Vector2(80, 190), "暂无编辑器关卡\n从主菜单进入关卡编辑器创建。", HORIZONTAL_ALIGNMENT_LEFT, 520, 18, MUTED)
	for i in range(entries.size()):
		var level = entries[i]
		var card := _select_card_rect(i, showing_custom)
		if showing_custom:
			var custom_description: String = level.description if not level.description.is_empty() else "可编辑 · 可试玩 · 可另存为"
			_draw_button(card, "%d  %s\n%s" % [i + 1, level.title, custom_description])
		else:
			var completed = profile.is_completed(level.id)
			var formal_description: String = "已完成 · 最佳 %s" % str(profile.best_actions.get(level.id, "—")) if completed else level.description
			_draw_button(card, "%d  %s\n%s" % [i + 1, level.title, formal_description], completed)
	var switch_label := "切换到编辑器关卡" if not showing_custom else "切换到正式关卡"
	_draw_button(Rect2(460, 610, 360, 48), switch_label, true)
	draw_string(font, Vector2(0, 690), "当前页面：" + ("编辑器关卡" if showing_custom else "正式关卡") + " · 点击下方按钮切换", HORIZONTAL_ALIGNMENT_CENTER, get_viewport_rect().size.x, 15, MUTED)

func _select_card_rect(index: int, custom: bool) -> Rect2:
	if custom:
		return Rect2(80 + (index % 3) * 350, 170 + (index / 3) * 100, 300, 82)
	return Rect2(80 + (index % 2) * 330, 170 + (index / 2) * 118, 290, 88)

func _draw_settings() -> void:
	_draw_header("设置", "设置会保存到 user://profile.json")
	_draw_button(Rect2(40, 40, 120, 42), "返回")
	_draw_button(Rect2(440, 260, 400, 58), "音效：" + ("静音" if profile.muted else "开启"), profile.muted)
	draw_string(font, Vector2(440, 360), "本版本使用轻量几何反馈，不依赖外部素材。", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, MUTED)

func _draw_header(title: String, subtitle: String) -> void:
	draw_string(font, Vector2(40, 108), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, TEXT)
	draw_string(font, Vector2(40, 138), subtitle, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, MUTED)

func _draw_game() -> void:
	if current_level == null or current_state == null:
		return
	var size := get_viewport_rect().size
	draw_rect(Rect2(800, 100, size.x - 828, size.y - 176), Color("#102036ee"))
	draw_string(font, Vector2(40, 48), current_level.title, HORIZONTAL_ALIGNMENT_LEFT, -1, 25, TEXT)
	draw_string(font, Vector2(40, 76), current_level.description, HORIZONTAL_ALIGNMENT_LEFT, 680, 15, MUTED)
	_draw_button(Rect2(820, 34, 90, 42), "撤销 Z")
	_draw_button(Rect2(920, 34, 90, 42), "重开 R")
	_draw_button(Rect2(1030, 34, 180, 42), "返回编辑器" if screen == "editor_play" else "返回选关")
	var metrics := _game_metrics()
	var origin: Vector2 = metrics.origin
	var cell: float = metrics.cell
	for y in range(current_level.height):
		for x in range(current_level.width):
			var c := Vector2i(x, y)
			var rect := Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell))
			_draw_terrain_cell(rect, current_level.terrain_at(c), current_state.has_bridge(c))
			if c in current_level.goals:
				_draw_goal_crate_marker(rect)
			if c == current_level.exit_cell:
				_draw_exit_marker(rect, true, BoardRulesScript.are_goals_complete(current_level, current_state))
	_draw_level_texts(current_level, origin, cell)
	_draw_mirror_beams(origin, cell)
	for submerged in submerged_crates:
		var submerged_cell: Vector2i = submerged.get("position", Vector2i(-1, -1))
		if submerged_cell.x >= 0:
			_draw_submerged_crate(origin + Vector2(submerged_cell.x, submerged_cell.y) * cell, cell)
	for crate in current_state.crates:
		_draw_crate(origin + Vector2(crate.position.x, crate.position.y) * cell, cell)
	for splash in splash_effects:
		var splash_cell: Vector2i = splash.get("cell", Vector2i(-1, -1))
		if splash_cell.x >= 0:
			_draw_splash(splash_cell, float(splash.get("time", 0.0)), origin, cell)
	for mirror_record in BoardRulesScript.mirror_records(current_state):
		var mirror_position: Vector2i = mirror_record.get("position", Vector2i(-1, -1))
		_draw_mirror(origin + Vector2(mirror_position.x, mirror_position.y) * cell, cell, str(mirror_record.get("orientation", "backslash")))
	for player_record in BoardRulesScript.player_records(current_state):
		var player_position: Vector2i = player_record.get("position", Vector2i(-1, -1))
		_draw_player(origin + Vector2(player_position.x, player_position.y) * cell, cell)
	var preview_pairs: Array = preview.get("pairs", [])
	var danger_count := 0
	for pair in preview_pairs:
		var target: Vector2i = pair.get("target", Vector2i(-1, -1))
		var status := str(pair.get("status", "invalid"))
		if status == "danger":
			danger_count += 1
		if target.x < 0 or target.y < 0 or target.x >= current_level.width or target.y >= current_level.height:
			continue
		var preview_color: Color = ACCENT if status == "valid" else WARNING if status == "danger" else ERROR
		var preview_center := origin + (Vector2(target.x, target.y) + Vector2(0.5, 0.5)) * cell
		if str(pair.get("source_type", "")) == "CRATE":
			var preview_rect := Rect2(preview_center - Vector2.ONE * cell * 0.27, Vector2.ONE * cell * 0.54)
			draw_rect(preview_rect, Color(preview_color, 0.18))
			draw_rect(preview_rect, preview_color, false, 4.0)
		else:
			draw_circle(preview_center, cell * 0.26, Color(preview_color, 0.18))
			draw_arc(preview_center, cell * 0.26, 0.0, TAU, 32, preview_color, 4.0)
	var projection_text := "等待同行/同列对象"
	if not preview_pairs.is_empty():
		projection_text = "%d 个目标" % preview_pairs.size()
		if danger_count > 0:
			projection_text += " · %d 个水面危险" % danger_count
	draw_string(font, Vector2(820, 125), "投影：" + projection_text, HORIZONTAL_ALIGNMENT_LEFT, 380, 16, WARNING if danger_count > 0 else ACCENT)
	draw_string(font, Vector2(820, 175), "操作数  %03d" % current_state.action_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, TEXT)
	draw_string(font, Vector2(820, 205), "推动数  %03d" % current_state.push_count, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, MUTED)
	draw_string(font, Vector2(820, 250), "箱子终点：%d 个，当前覆盖 %d 个" % [current_level.goals.size(), _covered_goals()], HORIZONTAL_ALIGNMENT_LEFT, 360, 17, MUTED)
	var mirror_summary := "无"
	var mirror_list := BoardRulesScript.mirror_records(current_state)
	if mirror_list.size() == 1:
		mirror_summary = str(mirror_list[0].get("orientation", "backslash"))
	elif mirror_list.size() > 1:
		mirror_summary = "%d 面镜子" % mirror_list.size()
	draw_string(font, Vector2(820, 290), "镜子：" + mirror_summary, HORIZONTAL_ALIGNMENT_LEFT, 360, 17, MUTED)
	draw_string(font, Vector2(820, 318), "出口：" + ("已打开，请到达" if BoardRulesScript.are_goals_complete(current_level, current_state) else "关闭，先完成箱子终点"), HORIZONTAL_ALIGNMENT_LEFT, 380, 16, ACCENT if BoardRulesScript.are_goals_complete(current_level, current_state) else WARNING)
	var shortcuts := ["Space  镜面反射", "Z  回退推动 / 反射", "R  重开本关", "Esc  返回"]
	for i in range(shortcuts.size()):
		draw_string(font, Vector2(820, 370 + i * 28), shortcuts[i], HORIZONTAL_ALIGNMENT_LEFT, 350, 16, TEXT)
	if current_state.won:
		draw_rect(Rect2(250, 190, 780, 400), Color("#0b1424dd"))
		draw_string(font, Vector2(0, 275), "通关！", HORIZONTAL_ALIGNMENT_CENTER, size.x, 42, ACCENT)
		draw_string(font, Vector2(0, 325), "本局操作数 %d · 推动数 %d" % [current_state.action_count, current_state.push_count], HORIZONTAL_ALIGNMENT_CENTER, size.x, 19, TEXT)
		_draw_button(Rect2(350, 520, 180, 48), "重玩")
		_draw_button(Rect2(550, 520, 180, 48), "返回编辑器\nSpace" if screen == "editor_play" else "下一关\nSpace", true)
		_draw_button(Rect2(750, 520, 180, 48), "返回")
	elif current_state.failed:
		draw_rect(Rect2(250, 190, 780, 400), Color("#0b1424dd"))
		draw_string(font, Vector2(0, 275), "失败", HORIZONTAL_ALIGNMENT_CENTER, size.x, 42, ERROR)
		draw_string(font, Vector2(0, 325), "所有可操控角色都落水了 · Z 可撤销反射", HORIZONTAL_ALIGNMENT_CENTER, size.x, 19, TEXT)
		_draw_button(Rect2(440, 520, 180, 48), "重玩", true)
		_draw_button(Rect2(650, 520, 180, 48), "返回")

func _covered_goals() -> int:
	var count := 0
	for goal in current_level.goals:
		if not current_state.crate_at(goal).is_empty():
			count += 1
	return count

func _game_metrics() -> Dictionary:
	var size := get_viewport_rect().size
	var area := Rect2(32, 108, size.x - 482, size.y - 180)
	var dimensions := Vector2(current_level.width, current_level.height)
	var cell := floorf(minf(area.size.x / dimensions.x, area.size.y / dimensions.y))
	return {"origin": (area.get_center() - dimensions * cell * 0.5).floor(), "cell": cell}

func _draw_editor() -> void:
	if editor_level == null:
		return
	var board_area: Rect2 = editor_ui.board_space.get_global_rect()
	draw_rect(board_area, Color("#102b40"))
	draw_rect(board_area, Color("#35516b"), false, 1.0)
	var metrics := _grid_metrics()
	var origin: Vector2 = metrics.origin
	var cell: float = metrics.cell
	for x in range(editor_level.width):
		draw_string(font, origin + Vector2(x * cell, -10), str(x), HORIZONTAL_ALIGNMENT_CENTER, cell, 12, MUTED)
	for y in range(editor_level.height):
		draw_string(font, origin + Vector2(-28, y * cell + cell * 0.5 + 4), str(y), HORIZONTAL_ALIGNMENT_CENTER, 22, 12, MUTED)
	for y in range(editor_level.height):
		for x in range(editor_level.width):
			var c := Vector2i(x, y)
			var rect := Rect2(origin + Vector2(x, y) * cell, Vector2(cell, cell))
			_draw_terrain_cell(rect, editor_level.terrain_at(c))
			if c in editor_level.goals:
				_draw_goal_crate_marker(rect)
			if c == editor_level.exit_cell:
				_draw_exit_marker(rect, true)
	for crate in editor_level.crates:
		if BoardRulesScript.in_bounds(editor_level, crate.position):
			_draw_crate(origin + Vector2(crate.position.x, crate.position.y) * cell, cell)
	for mirror_record in editor_level.mirrors:
		var mirror_position: Vector2i = mirror_record.get("position", Vector2i(-1, -1))
		if BoardRulesScript.in_bounds(editor_level, mirror_position):
			_draw_mirror(origin + Vector2(mirror_position.x, mirror_position.y) * cell, cell, str(mirror_record.get("orientation", "backslash")))
	for player in editor_level.players:
		var pos: Vector2i = player.get("position", Vector2i(-1, -1))
		if BoardRulesScript.in_bounds(editor_level, pos):
			_draw_player(origin + Vector2(pos) * cell, cell)
	_draw_level_texts(editor_level, origin, cell, true)
	if editor_rect_start.x >= 0:
		var first := Vector2i(mini(editor_rect_start.x, editor_rect_end.x), mini(editor_rect_start.y, editor_rect_end.y))
		var last := Vector2i(maxi(editor_rect_start.x, editor_rect_end.x), maxi(editor_rect_start.y, editor_rect_end.y))
		var paint_color: Color = {"land": LAND, "water": WATER_LIGHT, "wall": WALL_EDGE}.get(editor_tool, ACCENT)
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var at := Vector2i(x, y)
				var occupied := editor_tool != "land" and (not _editor_entity_at(at).is_empty() or not _editor_marker_at(at).is_empty())
				var rect := Rect2(origin + Vector2(at) * cell, Vector2.ONE * cell)
				draw_rect(rect, Color(ERROR if occupied else paint_color, 0.42))
		var selection := Rect2(origin + Vector2(first) * cell, Vector2(last - first + Vector2i.ONE) * cell)
		draw_rect(selection, ACCENT, false, 3.0)
		draw_string(font, selection.position + Vector2(4, -5), "%d × %d" % [last.x - first.x + 1, last.y - first.y + 1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, ACCENT)
	elif not editor_ui.modal_open():
		var hover := _editor_cell_at(get_global_mouse_position())
		if BoardRulesScript.in_bounds(editor_level, hover):
			draw_rect(Rect2(origin + Vector2(hover) * cell, Vector2.ONE * cell), ACCENT, false, 2.0)
	if editor_highlight_time > 0:
		var opacity := 0.35 + 0.25 * sin(editor_highlight_time * 9.0)
		for at in editor_highlight_cells:
			var clamped := Vector2i(clampi(at.x, 0, editor_level.width - 1), clampi(at.y, 0, editor_level.height - 1))
			var rect := Rect2(origin + Vector2(clamped) * cell, Vector2.ONE * cell)
			draw_rect(rect, Color(editor_highlight_color, opacity))
			draw_rect(rect.grow(-2), editor_highlight_color, false, 3.0)

func _draw_level_texts(level: LevelData, origin: Vector2, cell: float, show_handles: bool = false) -> void:
	for text_record in level.texts:
		var text_position := _text_position_from_record(text_record)
		_draw_text_record(origin + text_position * cell, cell, text_record, show_handles)

func _draw_text_record(pos: Vector2, cell: float, text_record: Dictionary, show_handles: bool = false) -> void:
	var visual := _text_visual_data(pos, cell, text_record)
	var content: String = visual.content
	if content.is_empty():
		return
	var background: Rect2 = visual.background
	var padding: Vector2 = visual.padding
	var measured: Vector2 = visual.measured
	var draw_size: int = visual.draw_size
	var text_color: Color = visual.color
	draw_rect(background, Color("#081521", visual.background_alpha))
	draw_rect(background, Color(text_color, 0.62), false, maxf(1.0, draw_size * 0.08))
	draw_string(font, background.position + Vector2(padding.x, visual.header_height + measured.y), content, HORIZONTAL_ALIGNMENT_LEFT, measured.x, draw_size, text_color)
	if show_handles:
		var drag_center: Vector2 = visual.drag_center
		var edit_center: Vector2 = visual.edit_center
		var radius: float = visual.handle_radius
		draw_circle(drag_center, radius, Color("#235354"))
		draw_circle(drag_center, radius, ACCENT, false, maxf(1.5, radius * 0.18))
		draw_line(drag_center - Vector2(radius * 0.42, 0), drag_center + Vector2(radius * 0.42, 0), TEXT, maxf(1.5, radius * 0.18))
		draw_line(drag_center - Vector2(0, radius * 0.42), drag_center + Vector2(0, radius * 0.42), TEXT, maxf(1.5, radius * 0.18))
		draw_circle(edit_center, radius, Color("#5a4660"))
		draw_circle(edit_center, radius, WARNING, false, maxf(1.5, radius * 0.18))
		draw_line(edit_center - Vector2(radius * 0.42, radius * 0.34), edit_center + Vector2(radius * 0.42, radius * 0.34), TEXT, maxf(1.5, radius * 0.18))
		draw_line(edit_center - Vector2(0, radius * 0.34), edit_center + Vector2(0, radius * 0.42), TEXT, maxf(1.5, radius * 0.18))

func _text_visual_data(pos: Vector2, cell: float, text_record: Dictionary) -> Dictionary:
	var content := str(text_record.get("text", "")).replace("\n", " / ")
	var draw_size := clampi(int(text_record.get("size", 18)), 8, 96)
	var text_color := Color.from_string(str(text_record.get("color", "#eef5ff")), TEXT)
	var background_alpha := clampf(float(text_record.get("background_alpha", 0.86)), 0.0, 1.0)
	var measured: Vector2 = font.get_string_size(content, HORIZONTAL_ALIGNMENT_LEFT, -1, draw_size)
	var horizontal_padding := maxf(8.0, draw_size * 0.28)
	var handle_radius := maxf(7.0, draw_size * 0.28)
	var header_height := maxf(handle_radius * 2.0 + 5.0, draw_size * 0.72)
	var bottom_padding := maxf(6.0, draw_size * 0.20)
	var background_size := Vector2(maxf(measured.x + horizontal_padding * 2.0, handle_radius * 4.0 + 12.0), header_height + measured.y + bottom_padding)
	var background := Rect2(pos + Vector2(cell, cell) * 0.5 - background_size * 0.5, background_size)
	var handle_inset := handle_radius + 5.0
	return {
		"content": content,
		"draw_size": draw_size,
		"color": text_color,
		"background_alpha": background_alpha,
		"measured": measured,
		"padding": Vector2(horizontal_padding, 0),
		"header_height": header_height,
		"background": background,
		"handle_radius": handle_radius,
		"drag_center": background.position + Vector2(handle_inset, header_height * 0.5),
		"edit_center": Vector2(background.end.x - handle_inset, background.position.y + header_height * 0.5)
	}

func _draw_button(rect: Rect2, label: String, active: bool = false) -> void:
	var color := ACCENT.darkened(0.35) if active else PANEL_2
	draw_rect(rect, color)
	draw_rect(rect, ACCENT if active else Color("#47627f"), false, 2.0)
	var lines := label.split("\n")
	for i in range(lines.size()):
		draw_string(font, rect.position + Vector2(14, 25 + i * 20), str(lines[i]), HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 28, 16 if lines.size() == 1 else 14, TEXT)

func _draw_terrain_cell(rect: Rect2, terrain: String, bridge: bool = false) -> void:
	var size := rect.size.x
	if terrain == "#":
		draw_rect(rect, WALL)
		var inner := rect.grow(-size * 0.10)
		draw_rect(inner, Color("#20364e"))
		draw_line(inner.position + Vector2(0, inner.size.y * 0.36), inner.position + Vector2(inner.size.x, inner.size.y * 0.36), WALL_EDGE, 1.5)
		draw_line(inner.position + Vector2(0, inner.size.y * 0.70), inner.position + Vector2(inner.size.x, inner.size.y * 0.70), WALL_EDGE, 1.5)
		draw_line(inner.position + Vector2(inner.size.x * 0.36, 0), inner.position + Vector2(inner.size.x * 0.36, inner.size.y * 0.36), WALL_EDGE, 1.5)
		draw_line(inner.position + Vector2(inner.size.x * 0.70, inner.size.y * 0.36), inner.position + Vector2(inner.size.x * 0.70, inner.size.y * 0.70), WALL_EDGE, 1.5)
		draw_rect(rect, Color("#07152299"), false, 2.0)
		return
	if terrain == "~":
		draw_rect(rect, BRIDGE if bridge else WATER)
		var wave := WATER_LIGHT if not bridge else Color("#9bd0c077")
		draw_line(rect.position + Vector2(size * 0.12, size * 0.32), rect.position + Vector2(size * 0.42, size * 0.25), wave, 2.0)
		draw_line(rect.position + Vector2(size * 0.58, size * 0.68), rect.position + Vector2(size * 0.88, size * 0.61), wave, 2.0)
		if bridge:
			var planks := rect.grow(-size * 0.10)
			draw_rect(planks, Color("#e2b56d"), false, 2.0)
			for plank_y in [0.28, 0.52, 0.76]:
				draw_line(planks.position + Vector2(0, planks.size.y * plank_y), planks.position + Vector2(planks.size.x, planks.size.y * plank_y), Color("#835737cc"), 1.5)
			draw_line(planks.position + Vector2(planks.size.x * 0.34, 0), planks.position + Vector2(planks.size.x * 0.34, planks.size.y), Color("#835737aa"), 1.5)
			draw_line(planks.position + Vector2(planks.size.x * 0.70, 0), planks.position + Vector2(planks.size.x * 0.70, planks.size.y), Color("#835737aa"), 1.5)
	else:
		draw_rect(rect, LAND)
		draw_rect(rect.grow(-size * 0.08), Color("#f4e8c5"), false, 1.5)
		draw_line(rect.position + Vector2(size * 0.14, size * 0.80), rect.position + Vector2(size * 0.38, size * 0.65), Color("#b59b6e99"), 1.5)
		draw_line(rect.position + Vector2(size * 0.62, size * 0.30), rect.position + Vector2(size * 0.88, size * 0.18), Color("#b59b6e77"), 1.5)
	draw_rect(rect, Color("#07152255"), false, 1.0)

func _draw_dashed_segment(from: Vector2, to: Vector2, color: Color, width: float, dash: float = 6.0, gap: float = 4.0) -> void:
	var length := from.distance_to(to)
	if length <= 0.0:
		return
	var direction := (to - from) / length
	var offset := 0.0
	while offset < length:
		var segment_end := minf(offset + dash, length)
		draw_line(from + direction * offset, from + direction * segment_end, color, width)
		offset += dash + gap

func _draw_goal_crate_marker(rect: Rect2) -> void:
	var goal_rect := rect.grow(-rect.size.x * 0.17)
	draw_rect(goal_rect.grow(2.0), Color("#16233dcc"))
	draw_rect(goal_rect, Color("#3b2f62cc"))
	var halo := Color("#101a2ddd")
	var color := Color("#ffd36a")
	var width := maxf(1.5, rect.size.x * 0.045)
	_draw_dashed_segment(goal_rect.position, Vector2(goal_rect.end.x, goal_rect.position.y), halo, width + 3.0)
	_draw_dashed_segment(Vector2(goal_rect.end.x, goal_rect.position.y), goal_rect.end, halo, width + 3.0)
	_draw_dashed_segment(goal_rect.end, Vector2(goal_rect.position.x, goal_rect.end.y), halo, width + 3.0)
	_draw_dashed_segment(Vector2(goal_rect.position.x, goal_rect.end.y), goal_rect.position, halo, width + 3.0)
	_draw_dashed_segment(goal_rect.position, Vector2(goal_rect.end.x, goal_rect.position.y), color, width)
	_draw_dashed_segment(Vector2(goal_rect.end.x, goal_rect.position.y), goal_rect.end, color, width)
	_draw_dashed_segment(goal_rect.end, Vector2(goal_rect.position.x, goal_rect.end.y), color, width)
	_draw_dashed_segment(Vector2(goal_rect.position.x, goal_rect.end.y), goal_rect.position, color, width)
	draw_circle(goal_rect.get_center(), rect.size.x * 0.055, Color("#fff1a6cc"))

func _draw_exit_marker(rect: Rect2, include_label: bool = false, is_open: bool = false) -> void:
	var door := rect.grow(-rect.size.x * 0.20)
	# 与右侧“出口”工具图标保持同一门形；状态只改变整套配色。
	var frame_color := Color("#8ce4bb") if is_open else Color("#ff6674")
	var fill_color := Color("#14535a") if is_open else Color("#542d42")
	draw_rect(door, fill_color)
	draw_rect(door, frame_color, false, maxf(2.0, rect.size.x * 0.055))
	if is_open:
		draw_line(door.position + Vector2(door.size.x * 0.60, 2), door.position + Vector2(door.size.x * 0.60, door.size.y - 2), Color("#b8ffe0"), 2.0)
		draw_line(door.position + Vector2(door.size.x * 0.60, 3), door.position + Vector2(door.size.x * 0.90, door.size.y * 0.18), Color("#77d9a1cc"), 2.0)
	else:
		draw_line(door.position + Vector2(door.size.x * 0.60, 2), door.position + Vector2(door.size.x * 0.60, door.size.y - 2), Color("#ff9aa5"), 2.0)
		draw_line(door.position + Vector2(door.size.x * 0.60, 3), door.position + Vector2(door.size.x * 0.88, door.size.y * 0.18), Color("#ff8795cc"), 2.0)
	draw_circle(door.position + Vector2(door.size.x * 0.35, door.size.y * 0.52), maxf(1.5, rect.size.x * 0.045), Color("#ffcf70"))
	if include_label and rect.size.x >= 26.0:
		draw_string(font, rect.position + Vector2(3, rect.size.y - 4), "出口", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x - 6, 12, Color("#eafff4"))

func _draw_mirror_beams(origin: Vector2, cell: float) -> void:
	if current_state == null:
		return
	for pair in preview.get("pairs", []):
		var source_pos: Vector2i = pair.get("source_position", Vector2i(-1, -1))
		var mirror_pos: Vector2i = pair.get("mirror_position", Vector2i(-1, -1))
		var target: Vector2i = pair.get("target", Vector2i(-1, -1))
		if source_pos.x < 0 or mirror_pos.x < 0:
			continue
		var mirror_center := origin + (Vector2(mirror_pos.x, mirror_pos.y) + Vector2(0.5, 0.5)) * cell
		var source_center := origin + (Vector2(source_pos.x, source_pos.y) + Vector2(0.5, 0.5)) * cell
		var source_beam := Color("#d8ffff")
		source_beam.a = 0.82
		var source_endpoint := source_center
		var source_blocker: Vector2i = BoardRulesScript.first_reflection_line_blocker(current_level, current_state, source_pos, mirror_pos)
		if source_blocker.x >= 0:
			var source_direction := (source_center - mirror_center).normalized()
			source_endpoint = origin + (Vector2(source_blocker.x, source_blocker.y) + Vector2(0.5, 0.5)) * cell - source_direction * cell * 0.5
		draw_line(mirror_center, source_endpoint, Color("#72e8f066"), maxf(6.0, cell * 0.16))
		draw_line(mirror_center, source_endpoint, source_beam, maxf(1.5, cell * 0.045))
		var status := str(pair.get("status", "invalid"))
		var target_beam: Color = ACCENT if status == "valid" else WARNING if status == "danger" else ERROR
		target_beam.a = 0.70
		var target_center := origin + (Vector2(target.x, target.y) + Vector2(0.5, 0.5)) * cell
		var target_endpoint := target_center
		var target_blocker: Vector2i = BoardRulesScript.first_reflection_ray_blocker(current_level, current_state, mirror_pos, target, str(pair.get("source_type", "")), str(pair.get("source_id", "")))
		if target_blocker.x >= 0:
			var target_direction := (target_center - mirror_center).normalized()
			target_endpoint = origin + (Vector2(target_blocker.x, target_blocker.y) + Vector2(0.5, 0.5)) * cell - target_direction * cell * 0.5
		draw_line(mirror_center, target_endpoint, Color(target_beam, 0.18), maxf(6.0, cell * 0.16))
		draw_line(mirror_center, target_endpoint, target_beam, maxf(1.5, cell * 0.045))
		draw_circle(mirror_center, cell * 0.10, Color("#e7ffffcc"))

func _draw_submerged_crate(pos: Vector2, cell: float) -> void:
	var shadow := Rect2(pos + Vector2(cell * 0.20, cell * 0.23), Vector2(cell * 0.68, cell * 0.68))
	draw_rect(shadow, Color("#07152266"))
	var rect := Rect2(pos + Vector2(cell * 0.16, cell * 0.16), Vector2(cell * 0.68, cell * 0.68))
	draw_rect(rect, Color("#694738cc"))
	var lower_water := Rect2(rect.position + Vector2(0, rect.size.y * 0.48), Vector2(rect.size.x, rect.size.y * 0.52))
	draw_rect(lower_water, Color("#2a7892aa"))
	draw_rect(rect, Color("#e3a66fcc"), false, maxf(2.0, cell * 0.045))
	draw_line(rect.position + Vector2(cell * 0.10, cell * 0.10), rect.end - Vector2(cell * 0.10, cell * 0.10), Color("#d28b63aa"), 2.0)
	draw_line(Vector2(rect.end.x - cell * 0.10, rect.position.y + cell * 0.10), Vector2(rect.position.x + cell * 0.10, rect.end.y - cell * 0.10), Color("#d28b63aa"), 2.0)
	var waterline := rect.position.y + rect.size.y * 0.48
	draw_line(Vector2(pos.x + cell * 0.08, waterline), Vector2(pos.x + cell * 0.92, waterline - 2), Color("#a9f1f0dd"), maxf(2.0, cell * 0.045))
	draw_line(Vector2(pos.x + cell * 0.18, waterline + cell * 0.16), Vector2(pos.x + cell * 0.80, waterline + cell * 0.14), Color("#73cbd7aa"), 2.0)
	draw_string(font, rect.position + Vector2(0, rect.size.y * 0.63), "箱", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, maxi(12, int(cell * 0.22)), Color("#fff0c2cc"))

func _draw_splash(cell_pos: Vector2i, elapsed: float, origin: Vector2, cell: float) -> void:
	var center := origin + (Vector2(cell_pos.x, cell_pos.y) + Vector2(0.5, 0.55)) * cell
	var progress := clampf(elapsed / 0.85, 0.0, 1.0)
	var ring_color := Color("#9fe9f5")
	ring_color.a = 1.0 - progress
	draw_arc(center, cell * (0.10 + progress * 0.38), 0.0, TAU, 24, ring_color, maxf(2.0, cell * 0.035))
	for i in range(6):
		var angle := TAU * float(i) / 6.0
		var start := center + Vector2.from_angle(angle) * cell * (0.14 + progress * 0.10)
		var end := center + Vector2.from_angle(angle) * cell * (0.27 + progress * 0.30)
		draw_line(start, end, ring_color, maxf(1.5, cell * 0.035))

func _draw_crate(pos: Vector2, cell: float) -> void:
	var shadow := Rect2(pos + Vector2(cell * 0.20, cell * 0.23), Vector2(cell * 0.68, cell * 0.68))
	draw_rect(shadow, Color("#07152266"))
	var rect := Rect2(pos + Vector2(cell * 0.16, cell * 0.16), Vector2(cell * 0.68, cell * 0.68))
	draw_rect(rect, CRATE_FACE)
	draw_rect(rect, CRATE_EDGE, false, maxf(2.0, cell * 0.055))
	draw_line(rect.position + Vector2(cell * 0.10, cell * 0.10), rect.end - Vector2(cell * 0.10, cell * 0.10), CRATE_EDGE, maxf(1.5, cell * 0.035))
	draw_line(Vector2(rect.end.x - cell * 0.10, rect.position.y + cell * 0.10), Vector2(rect.position.x + cell * 0.10, rect.end.y - cell * 0.10), CRATE_EDGE, maxf(1.5, cell * 0.035))
	draw_string(font, rect.position + Vector2(0, rect.size.y * 0.63), "箱", HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, maxi(12, int(cell * 0.22)), Color("#fff0c2"))

func _draw_mirror(pos: Vector2, cell: float, orientation: String) -> void:
	var rect := Rect2(pos + Vector2(cell * 0.15, cell * 0.15), Vector2(cell * 0.7, cell * 0.7))
	draw_rect(rect, Color("#4aa9c988"))
	draw_rect(rect, Color("#d9fbff"), false, 3.0)
	if orientation == "slash":
		draw_line(rect.position + Vector2(rect.size.x - 5, 5), rect.position + Vector2(5, rect.size.y - 5), Color("#ffffff"), 5.0)
		draw_line(rect.position + Vector2(rect.size.x - 9, 5), rect.position + Vector2(5, rect.size.y - 9), Color("#b9f3ff99"), 2.0)
	else:
		draw_line(rect.position + Vector2(5, 5), rect.position + Vector2(rect.size.x - 5, rect.size.y - 5), Color("#ffffff"), 5.0)
		draw_line(rect.position + Vector2(9, 5), rect.position + Vector2(rect.size.x - 5, rect.size.y - 9), Color("#b9f3ff99"), 2.0)
	draw_circle(rect.position + Vector2(rect.size.x * 0.28, rect.size.y * 0.25), maxf(2.0, cell * 0.04), Color("#ffffffcc"))

func _draw_player(pos: Vector2, cell: float) -> void:
	draw_circle(pos + Vector2(cell, cell) * 0.5, cell * 0.26, Color("#ef7185"))
	draw_circle(pos + Vector2(cell * 0.42, cell * 0.44), cell * 0.05, Color("#ffffff"))
	draw_circle(pos + Vector2(cell * 0.58, cell * 0.44), cell * 0.05, Color("#ffffff"))
