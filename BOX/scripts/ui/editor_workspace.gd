extends Control

signal command_requested(action: String)
signal tool_selected(tool: String)
signal palette_drag_started(tool: String)
signal open_file_requested(path: String)
signal save_as_requested(directory: String, file_name: String)
signal text_requested(position: Vector2, content: String, font_size: int, color: String, background_alpha: float)
signal issue_selected(issue: Dictionary)
signal size_requested(kind: String, width: int, height: int)
signal metadata_changed

const IconScript = preload("res://scripts/ui/editor_tool_icon.gd")
const INK := Color("#eef5ff")
const MUTED := Color("#a9bdd5")
const ACCENT := Color("#5fd1c5")
const WARNING := Color("#ffcb6b")
const ERROR := Color("#ff7f88")
const MIN_BOARD_SIZE := 6
const MAX_BOARD_SIZE := 32

var board_space: Control
var title_input: LineEdit
var description_input: TextEdit
var tabs: TabContainer
var tool_buttons: Dictionary = {}
var title_status: Label
var board_status: Label
var footer: Label
var notice: Label
var size_label: Label
var validation_label: Label
var issue_list: VBoxContainer
var undo_button: Button
var redo_button: Button
var size_dialog: ConfirmationDialog
var open_dialog: FileDialog
var save_as_dialog: ConfirmationDialog
var crop_dialog: ConfirmationDialog
var discard_dialog: ConfirmationDialog
var text_dialog: ConfirmationDialog
var save_as_directory_input: LineEdit
var save_as_filename_input: LineEdit
var text_input: TextEdit
var text_size_input: SpinBox
var text_color_input: LineEdit
var text_background_alpha_input: SpinBox
var text_dialog_position := Vector2.ZERO
var text_dialog_existing := false
var width_input: SpinBox
var height_input: SpinBox
var size_kind := "resize"
var crop_width := 6
var crop_height := 6
var syncing := false
var level_width := 16
var level_height := 16
var validation_summary := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	_sync_viewport_size()
	get_viewport().size_changed.connect(_sync_viewport_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ui_theme := Theme.new()
	ui_theme.default_font_size = 15
	ui_theme.set_color("font_color", "Label", INK)
	ui_theme.set_color("font_color", "Button", INK)
	ui_theme.set_stylebox("normal", "Button", _style(Color("#223b54")))
	ui_theme.set_stylebox("hover", "Button", _style(Color("#304e68"), Color("#6596a7")))
	ui_theme.set_stylebox("pressed", "Button", _style(Color("#235354"), ACCENT))
	ui_theme.set_stylebox("disabled", "Button", _style(Color("#172b40")))
	ui_theme.set_stylebox("panel", "TabContainer", _style(Color("#172b40")))
	ui_theme.set_stylebox("tab_selected", "TabBar", _style(Color("#235354"), ACCENT))
	ui_theme.set_stylebox("tab_unselected", "TabBar", _style(Color("#223b54")))
	theme = ui_theme
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 16)
	var root := VBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation", 10)
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var heading := _label("关卡工作台", 24)
	header.add_child(heading)
	title_status = _label("", 14, MUTED)
	title_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(title_status)
	_button(header, "试玩  F5", func(): command_requested.emit("play"))
	_button(header, "返回", func(): command_requested.emit("menu"))
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 8)
	root.add_child(toolbar)
	for item in [["打开", "open"], ["保存  Ctrl+S", "save"], ["另存为", "save_as"]]:
		_button(toolbar, item[0], _emit_command.bind(item[1]))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	undo_button = _button(toolbar, "撤销", _emit_command.bind("undo"))
	redo_button = _button(toolbar, "重做", _emit_command.bind("redo"))
	var body := HBoxContainer.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)
	var terrain_column := VBoxContainer.new()
	terrain_column.custom_minimum_size.x = 118
	terrain_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	terrain_column.add_theme_constant_override("separation", 7)
	body.add_child(terrain_column)
	terrain_column.add_child(_label("地形", 15, MUTED))
	_build_terrain_tools(terrain_column)
	var board_column := VBoxContainer.new()
	board_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(board_column)
	var board_header := HBoxContainer.new()
	board_column.add_child(board_header)
	board_status = _label("棋盘 · 自动适配", 15, MUTED)
	board_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_header.add_child(board_status)
	_button(board_header, "棋盘大小…", func(): open_size_dialog("resize", level_width, level_height))
	board_space = Control.new()
	board_space.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	board_space.size_flags_vertical = Control.SIZE_EXPAND_FILL
	board_space.clip_contents = false
	board_column.add_child(board_space)
	var side := VBoxContainer.new()
	side.custom_minimum_size.x = 166
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_theme_constant_override("separation", 10)
	body.add_child(side)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side.add_child(tabs)
	_build_tools()
	_build_properties()
	footer = _label("", 14, MUTED)
	footer.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(footer)
	notice = _label("左键铺设地形/拖动物体 · 右栏拖入物体 · 1陆地 2水面 3墙 · 滚轮缩放 · 中键吸取 · WASD 镜头 · 右键删除", 14, ACCENT)
	notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	root.add_child(notice)
	_build_dialogs()

func _build_tools() -> void:
	var page := VBoxContainer.new()
	page.name = "物体"
	page.add_theme_constant_override("separation", 8)
	tabs.add_child(page)
	page.add_child(_label("物体（按住拖入棋盘）", 14, MUTED))
	for item in [["player", "角色"], ["crate", "箱子"], ["mirror", "镜子"], ["goal", "箱子终点"], ["exit", "出口"], ["text", "字体"]]:
		_add_tool_button(page, str(item[0]), str(item[1]), true, 56)

func _build_terrain_tools(parent: Node) -> void:
	_add_tool_button(parent, "land", "陆地 1", false, 70)
	_add_tool_button(parent, "water", "水面 2", false, 70)
	_add_tool_button(parent, "wall", "墙 3", false, 70)

func palette_tool_at(pos: Vector2) -> String:
	for tool in ["player", "crate", "mirror", "goal", "exit", "text"]:
		var button = tool_buttons.get(tool)
		if button is Button and button.visible and button.get_global_rect().has_point(pos):
			return tool
	return ""

func _add_tool_button(parent: Node, tool: String, label_text: String, draggable: bool, button_height: float) -> void:
	var button := _button(parent, "", _emit_tool.bind(tool))
	button.custom_minimum_size = Vector2(0, button_height)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.toggle_mode = true
	button.tooltip_text = label_text + ("：点击已有镜子旋转 90°" if tool == "mirror" else "")
	var label := _label(label_text, 11 if draggable else 13)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.add_child(label)
	label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	label.offset_left = 2
	label.offset_right = -2
	label.offset_top = 3
	label.offset_bottom = 20
	var icon := IconScript.new()
	icon.tool = tool
	button.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 2
	icon.offset_right = -2
	icon.offset_top = 21 if not draggable else 23
	icon.offset_bottom = -3
	tool_buttons[tool] = button
	if draggable:
		button.mouse_default_cursor_shape = Control.CURSOR_DRAG
		button.button_down.connect(_emit_palette_drag.bind(tool))

func _build_properties() -> void:
	var page := VBoxContainer.new()
	page.name = "关卡设置"
	page.add_theme_constant_override("separation", 8)
	tabs.add_child(page)
	page.add_child(_label("标题", 14, MUTED))
	title_input = LineEdit.new()
	title_input.placeholder_text = "关卡标题"
	title_input.max_length = 80
	page.add_child(title_input)
	title_input.text_changed.connect(func(_text: String):
		if not syncing:
			metadata_changed.emit())
	page.add_child(_label("描述（可选）", 14, MUTED))
	description_input = TextEdit.new()
	description_input.placeholder_text = "描述关卡目标或给玩家一点提示"
	description_input.custom_minimum_size.y = 80
	description_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	page.add_child(description_input)
	description_input.text_changed.connect(func():
		if not syncing:
			metadata_changed.emit())
	size_label = _label("", 14, MUTED)
	page.add_child(size_label)
	_button(page, "调整棋盘宽高…", func(): open_size_dialog("resize", level_width, level_height))

func _build_dialogs() -> void:
	size_dialog = ConfirmationDialog.new()
	size_dialog.ok_button_text = "应用"
	size_dialog.cancel_button_text = "取消"
	add_child(size_dialog)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	size_dialog.add_child(column)
	var row := HBoxContainer.new()
	column.add_child(row)
	row.add_child(_label("宽度", 16))
	width_input = _dimension_input(row)
	row.add_child(_label("高度", 16))
	height_input = _dimension_input(row)
	column.add_child(_label("宽、高分别支持 6–32 格，可创建矩形棋盘。", 14, MUTED))
	column.add_child(_label("调整保留左上角；新增区域为水面。\n缩小会预告裁剪内容，调整后可 Ctrl+Z 撤销。", 14, MUTED))
	size_dialog.confirmed.connect(func():
		width_input.apply()
		height_input.apply()
		size_requested.emit(size_kind, int(width_input.value), int(height_input.value)))
	open_dialog = FileDialog.new()
	open_dialog.title = "打开关卡"
	open_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	open_dialog.access = FileDialog.ACCESS_FILESYSTEM
	open_dialog.filters = PackedStringArray(["*.json ; BOX 关卡文件 (*.json)"])
	open_dialog.show_hidden_files = false
	add_child(open_dialog)
	open_dialog.file_selected.connect(func(path: String): open_file_requested.emit(path))
	save_as_dialog = ConfirmationDialog.new()
	save_as_dialog.title = "另存为关卡"
	save_as_dialog.ok_button_text = "保存"
	save_as_dialog.cancel_button_text = "取消"
	add_child(save_as_dialog)
	var save_as_column := VBoxContainer.new()
	save_as_column.add_theme_constant_override("separation", 9)
	save_as_dialog.add_child(save_as_column)
	save_as_column.add_child(_label("保存地址（支持 user://、res:// 或绝对路径）", 14, MUTED))
	save_as_directory_input = LineEdit.new()
	save_as_directory_input.placeholder_text = "user://levels"
	save_as_column.add_child(save_as_directory_input)
	save_as_column.add_child(_label("文件名（自动追加 .json）", 14, MUTED))
	save_as_filename_input = LineEdit.new()
	save_as_filename_input.placeholder_text = "my_level"
	save_as_column.add_child(save_as_filename_input)
	save_as_dialog.confirmed.connect(func():
		save_as_requested.emit(save_as_directory_input.text, save_as_filename_input.text))
	crop_dialog = ConfirmationDialog.new()
	crop_dialog.title = "确认裁剪棋盘"
	crop_dialog.ok_button_text = "裁剪（可撤销）"
	crop_dialog.cancel_button_text = "取消"
	add_child(crop_dialog)
	crop_dialog.confirmed.connect(func(): size_requested.emit("crop_confirmed", crop_width, crop_height))
	discard_dialog = ConfirmationDialog.new()
	discard_dialog.title = "草稿尚未保存"
	discard_dialog.dialog_text = "继续前如何处理当前改动？"
	discard_dialog.ok_button_text = "保存后继续"
	discard_dialog.cancel_button_text = "取消"
	discard_dialog.add_button("不保存，继续", true, "discard")
	add_child(discard_dialog)
	discard_dialog.confirmed.connect(_emit_command.bind("save_and_continue"))
	discard_dialog.custom_action.connect(func(action: StringName):
		if action == "discard":
			discard_dialog.hide()
			command_requested.emit("discard_and_continue"))
	text_dialog = ConfirmationDialog.new()
	text_dialog.title = "添加字体"
	text_dialog.ok_button_text = "应用"
	text_dialog.cancel_button_text = "取消"
	add_child(text_dialog)
	var text_column := VBoxContainer.new()
	text_column.add_theme_constant_override("separation", 8)
	text_dialog.add_child(text_column)
	text_column.add_child(_label("文字内容", 14, MUTED))
	text_input = TextEdit.new()
	text_input.placeholder_text = "输入关卡提示或说明文字"
	text_input.custom_minimum_size = Vector2(420, 92)
	text_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	text_column.add_child(text_input)
	var text_options := HBoxContainer.new()
	text_options.add_theme_constant_override("separation", 8)
	text_column.add_child(text_options)
	text_options.add_child(_label("字号", 14, MUTED))
	text_size_input = SpinBox.new()
	text_size_input.min_value = 8
	text_size_input.max_value = 96
	text_size_input.step = 1
	text_size_input.rounded = true
	text_size_input.custom_minimum_size.x = 88
	text_options.add_child(text_size_input)
	text_options.add_child(_label("颜色", 14, MUTED))
	text_color_input = LineEdit.new()
	text_color_input.placeholder_text = "#eef5ff"
	text_color_input.text = "#eef5ff"
	text_color_input.custom_minimum_size.x = 150
	text_options.add_child(text_color_input)
	var text_background_options := HBoxContainer.new()
	text_background_options.add_theme_constant_override("separation", 8)
	text_column.add_child(text_background_options)
	text_background_options.add_child(_label("背景 Alpha", 14, MUTED))
	text_background_alpha_input = SpinBox.new()
	text_background_alpha_input.min_value = 0.0
	text_background_alpha_input.max_value = 1.0
	text_background_alpha_input.step = 0.05
	text_background_alpha_input.value = 0.86
	text_background_alpha_input.custom_minimum_size.x = 100
	text_background_options.add_child(text_background_alpha_input)
	text_dialog.confirmed.connect(func():
		text_requested.emit(text_dialog_position, text_input.text, int(text_size_input.value), text_color_input.text, float(text_background_alpha_input.value)))

func _dimension_input(parent: Node) -> SpinBox:
	var input := SpinBox.new()
	input.min_value = 6
	input.max_value = MAX_BOARD_SIZE
	input.step = 1
	input.rounded = true
	input.custom_minimum_size.x = 110
	parent.add_child(input)
	return input

func _sync_viewport_size() -> void:
	if get_viewport() == null:
		return
	position = Vector2.ZERO
	size = get_viewport_rect().size

func open_size_dialog(kind: String, width: int, height: int) -> void:
	size_kind = kind
	size_dialog.title = "新建关卡" if kind == "new" else "调整棋盘大小"
	width_input.value = width
	height_input.value = height
	size_dialog.popup_centered(Vector2i(450, 220))

func confirm_crop(width: int, height: int, summary: String) -> void:
	crop_width = width
	crop_height = height
	crop_dialog.dialog_text = summary + "\n保留左上角，其余格子将裁掉。Ctrl+Z 可完整恢复。"
	crop_dialog.popup_centered(Vector2i(460, 190))

func modal_open() -> bool:
	return open_dialog.visible or size_dialog.visible or save_as_dialog.visible or crop_dialog.visible or discard_dialog.visible or text_dialog.visible

func open_level_dialog(default_directory: String = "user://levels") -> void:
	var absolute_directory := ProjectSettings.globalize_path(default_directory)
	if DirAccess.dir_exists_absolute(absolute_directory):
		open_dialog.current_dir = absolute_directory
	open_dialog.popup_centered(Vector2i(820, 540))

func open_save_as_dialog(default_name: String, default_directory: String = "user://levels") -> void:
	save_as_directory_input.text = default_directory
	save_as_filename_input.text = default_name.trim_suffix(".json")
	save_as_dialog.popup_centered(Vector2i(560, 260))

func open_text_dialog(position: Vector2, existing: Dictionary = {}) -> void:
	text_dialog_position = position
	text_dialog_existing = not existing.is_empty()
	text_dialog.title = "编辑字体" if text_dialog_existing else "添加字体"
	text_input.text = str(existing.get("text", ""))
	text_size_input.value = clampi(int(existing.get("size", 18)), 8, 96)
	text_color_input.text = str(existing.get("color", "#eef5ff"))
	text_background_alpha_input.value = clampf(float(existing.get("background_alpha", 0.86)), 0.0, 1.0)
	text_dialog.popup_centered(Vector2i(520, 330))
	text_input.grab_focus()

func set_level(level: LevelData) -> void:
	syncing = true
	title_input.text = level.title
	description_input.text = level.description
	level_width = level.width
	level_height = level.height
	size_label.text = "棋盘  %d × %d  · 扩展填水，裁剪可撤销" % [level_width, level_height]
	syncing = false

func update_status(level: LevelData, tool: String, _mode: String, dirty: bool, undo_count: int, redo_count: int, hover: Vector2i, cell_size: float, message: String) -> void:
	title_status.text = "  /  " + level.title + ("  · 未保存" if dirty else "  · 已保存")
	board_status.text = "%d × %d 格  · %.0f px / 格  · 最小全图 / 最大约 8 行" % [level.width, level.height, cell_size]
	if not validation_summary.is_empty():
		board_status.text += "  ·  " + validation_summary
	undo_button.disabled = undo_count == 0
	redo_button.disabled = redo_count == 0
	sync_tool_state(tool)
	var cell_text := "移到棋盘查看坐标"
	if hover.x >= 0 and hover.y >= 0 and hover.x < level.width and hover.y < level.height:
		cell_text = "坐标 (%d, %d)" % [hover.x, hover.y]
	footer.text = "%s   ·   1陆地 2水面 3墙   ·   撤销 %d / 重做 %d" % [cell_text, undo_count, redo_count]
	notice.text = message if not message.is_empty() else "左键铺设地形/拖动物体 · 右栏拖入物体 · 滚轮缩放（最小全图，最大约 8 行）· 中键吸取 · WASD 镜头 · 右键删除"

func sync_tool_state(tool: String) -> void:
	for key in tool_buttons:
		tool_buttons[key].set_pressed_no_signal(key == tool)

func update_issues(result: Dictionary) -> void:
	var warnings := 0
	for issue in result.get("issues", []):
		if issue.severity == "warning":
			warnings += 1
	validation_summary = "校验 %d 错误 / %d 提醒" % [result.errors.size(), warnings]

func focus_tool(tool: String) -> void:
	tabs.current_tab = 0
	if tool_buttons.has(tool):
		var button: Button = tool_buttons[tool]
		button.modulate = WARNING
		var tween := create_tween()
		tween.tween_property(button, "modulate", Color.WHITE, 1.2)

func set_mirror_orientation(orientation: String) -> void:
	var button: Button = tool_buttons["mirror"]
	var icon = button.get_child(1)
	icon.mirror_orientation = orientation
	icon.queue_redraw()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _label(text: String, font_size: int = 15, color: Color = INK) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _style(color: Color, border: Color = Color("#35516b")) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 7
	style.content_margin_bottom = 7
	return style

func _emit_command(action: String) -> void:
	command_requested.emit(action)

func _emit_tool(tool: String) -> void:
	tool_selected.emit(tool)

func _emit_palette_drag(tool: String) -> void:
	palette_drag_started.emit(tool)

func _emit_issue(issue: Dictionary) -> void:
	issue_selected.emit(issue)
