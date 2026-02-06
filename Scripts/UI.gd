extends Control

signal add_node_requested
signal node_data_changed(node_data)
signal jump_requested(percent)
signal exit_requested
# New Signals
signal delete_mode_toggled(active)
signal delete_confirmed
signal spacing_changed(value)
# View Signals
signal view_mode_changed(mode_name)
signal align_grid_requested

@onready var add_button = $ForegroundLayer/AddButton
@onready var delete_mode_btn = $ForegroundLayer/DeleteModeButton
@onready var delete_cancel_btn = $ForegroundLayer/DeleteCancelButton

# View Controls
@onready var free_btn = $ForegroundLayer/ViewControls/FreeBtn
# GridBtn removed
@onready var timeline_btn = $ForegroundLayer/ViewControls/TimelineBtn
@onready var align_btn = $ForegroundLayer/ViewControls/AlignBtn

@onready var sidebar = $ForegroundLayer/Sidebar
@onready var name_edit = $ForegroundLayer/Sidebar/VBoxContainer/NameEdit
# DescEdit removed
@onready var color_picker = $ForegroundLayer/Sidebar/VBoxContainer/ColorPickerButton
@onready var recycling_bin = $ForegroundLayer/RecycleBin
var current_node_data: Dictionary = {}
var current_node_ref = null

# Annotation UI
var annotation_container: VBoxContainer = null
var annotation_scroll: ScrollContainer = null
var temp_annotations: Array = []

var toast_label: Label = null
var toast_tween: Tween = null
# var auto_save_checkbox: CheckBox = null # Removed

# Internal Class for Visual Indicator
class HoldIndicator extends Control:
	var progress: float = 0.0
	
	func set_progress(p: float):
		progress = clamp(p, 0.0, 1.0)
		queue_redraw()
		
	func _draw():
		# Draw Background Arc (Grey)
		var radius = 20.0
		var center = Vector2.ZERO
		var color_bg = Color(1, 1, 1, 0.3)
		var color_fg = Color(1, 1, 1, 0.9)
		
		# Full Circle BG
		draw_arc(center, radius, 0, TAU, 32, color_bg, 4.0, true)
		
		# Foreground Arc
		if progress > 0:
			var end_angle = progress * TAU
			# Godot arcs start at 0 (Right). -PI/2 is Up.
			var start_angle = -PI / 2
			draw_arc(center, radius, start_angle, start_angle + end_angle, 32, color_fg, 4.0, true)

var hold_indicator: HoldIndicator = null

func _ready():
	_setup_hold_indicator()
	
	add_button.pressed.connect(_on_add_button_pressed)
	$ForegroundLayer/Sidebar/VBoxContainer/SaveButton.pressed.connect(_on_save_pressed)
	
	if recycling_bin:
		recycling_bin.visible = false
	
	_setup_annotation_ui() # Setup new UI structure
	_setup_bg_toggle() # Add CheckBox dynamically
	# _setup_sidebar_toggle() # Removed
	_setup_exit_button()
	_setup_bottom_left_buttons()
	_setup_toast_ui()
	
	_setup_toast_ui()
	# _setup_settings_menu() # REVERTED: Moved to Main Menu
	
	sidebar.visible = false # Ensure sidebar is hidden on load
	
	# Fix: Explicitly connect delete buttons (missing from previous cleanup)
	if delete_mode_btn: delete_mode_btn.pressed.connect(_on_delete_mode_pressed)
	if delete_cancel_btn: delete_cancel_btn.pressed.connect(_on_delete_cancel_pressed)
	
	# Fix: Connect View Controls (Free, Timeline, Align)
	if free_btn: free_btn.pressed.connect(func(): _set_view_mode("FREE"))
	if timeline_btn: timeline_btn.pressed.connect(func(): _set_view_mode("TIMELINE"))
	if align_btn: align_btn.pressed.connect(func(): emit_signal("align_grid_requested"))
	
	_setup_spacing_slider()
	
	color_picker.color_changed.connect(_on_color_changed)

func _setup_hold_indicator():
	hold_indicator = HoldIndicator.new()
	hold_indicator.name = "HoldIndicator"
	# Add to ForegroundLayer ensuring it's on top and doesn't affect layout
	$ForegroundLayer.add_child(hold_indicator)
	hold_indicator.visible = false
	hold_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE # Don't block clicks

func update_hold_indicator(pos: Vector2, progress: float):
	if not hold_indicator: return
	
	hold_indicator.visible = true
	hold_indicator.global_position = pos
	hold_indicator.set_progress(progress)

func hide_hold_indicator():
	if hold_indicator:
		hold_indicator.visible = false

var show_bg_checkbox: CheckBox = null
var spacing_slider: HSlider = null
# var sidebar_toggle_btn: Button = null # Removed

func _setup_bg_toggle():
	show_bg_checkbox = CheckBox.new()
	show_bg_checkbox.text = "Show Background Box"
	# Add before Save Button (which is last)
	var vbox = $ForegroundLayer/Sidebar/VBoxContainer
	vbox.add_child(show_bg_checkbox)
	
	# REORDER: Place after ColorPicker (Index 1) => Index 2
	# Previous `auto_save` was put at 2. So if we put this at 2, Auto Save becomes 3.
	vbox.move_child(show_bg_checkbox, 2)
	
	show_bg_checkbox.toggled.connect(_on_bg_toggled)

	show_bg_checkbox.toggled.connect(_on_bg_toggled)
	
	_setup_font_slider()

var font_size_slider: HSlider = null
var font_size_label: Label = null

func _setup_font_slider():
	var vbox = $ForegroundLayer/Sidebar/VBoxContainer
	
	# Container for label and slider
	var hbox = HBoxContainer.new()
	vbox.add_child(hbox)
	vbox.move_child(hbox, 3) # After ShowBG (2)
	
	font_size_label = Label.new()
	font_size_label.text = "Font Size: 144"
	hbox.add_child(font_size_label)
	
	font_size_slider = HSlider.new()
	font_size_slider.min_value = 48
	font_size_slider.max_value = 300
	font_size_slider.step = 12
	font_size_slider.value = 144
	font_size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	font_size_slider.value_changed.connect(_on_font_size_changed)
	hbox.add_child(font_size_slider)

func _on_font_size_changed(value):
	font_size_label.text = "Font Size: " + str(value)
	if current_node_ref and is_instance_valid(current_node_ref):
		if current_node_ref.has_method("set_font_size"):
			current_node_ref.set_font_size(int(value))
	
	if not current_node_data.is_empty():
		current_node_data["font_size"] = int(value)

func _on_bg_toggled(pressed: bool):
	if current_node_data.is_empty(): return
	current_node_data["use_bg_color"] = pressed
	
	if current_node_ref and is_instance_valid(current_node_ref):
		if current_node_ref.has_method("set_show_background"):
			current_node_ref.set_show_background(pressed)

func show_sidebar(node_data: Dictionary, node_ref):
	var was_visible = sidebar.visible
	current_node_data = node_data
	current_node_ref = node_ref
	
	sidebar.visible = true
	
	if not was_visible:
		# Initial Open Animation (Slide In)
		# Start Off-Screen (Collapsed Position)
		sidebar.offset_left = 0
		sidebar.offset_right = 300
		
		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		# Move to On-Screen (Open Position)
		tween.tween_property(sidebar, "offset_left", -300, 0.3)
		tween.tween_property(sidebar, "offset_right", 0, 0.3)
			
	# Else: It is already open and visible, no need to touch position.
		
	name_edit.text = str(node_data.get("name", ""))
	
	# Initialize Temp Buffer
	var raw_list = node_data.get("annotations", [])
	# Legacy Migration (Real-time check)
	if raw_list.is_empty():
		var old_desc = node_data.get("description", "")
		if old_desc != "":
			raw_list = [{ "title": "Description", "content": old_desc, "expanded": true }]
			
	temp_annotations = raw_list.duplicate(true) # Deep Copy for editing
	
	_render_annotations() # Populate list
	
	var col_html = node_data.get("color", "ffffff")
	color_picker.color = Color.html(col_html)
	
	if show_bg_checkbox:
		show_bg_checkbox.set_pressed_no_signal(node_data.get("use_bg_color", true))

func _setup_annotation_ui():
	var vbox = $ForegroundLayer/Sidebar/VBoxContainer
	
	# 2. Create ScrollContainer
	annotation_scroll = ScrollContainer.new()
	annotation_scroll.name = "AnnotationScroll"
	annotation_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL # Fill remaining space
	annotation_scroll.custom_minimum_size = Vector2(0, 200) # Min height
	
	vbox.add_child(annotation_scroll)
	# vbox.move_child(annotation_scroll, 2) # OLD: Top
	
	# 3. Create Container
	annotation_container = VBoxContainer.new()
	annotation_container.name = "AnnotationContainer"
	annotation_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	annotation_scroll.add_child(annotation_container)
	
	# 4. Add "Add Annotation" Button
	var add_btn = Button.new()
	add_btn.text = "+ Add Annotation"
	add_btn.pressed.connect(_add_new_annotation)
	vbox.add_child(add_btn)
	# vbox.move_child(add_btn, 3) 
	
	# Auto Save Checkbox MOVED TO MAIN MENU
	
	# --- REORDERING ---
	# Desired Order:
	# 0: NameEdit
	# 1: ColorPicker
	# 2: Show BG Checkbox
	# 3: Annotation Scroll (Expands)
	# 4: Add Annotation Btn
	# 5: Save Button
	
	# We assume NameEdit (0) and ColorPicker (1) are fixed.
	
	# Move Controls to Top area (after ColorPicker - index 1)
	# vbox.move_child(auto_save_checkbox, 2) # Gone
	
	# Move Scroll and Add Button to just before Save Button?
	# Actually, if we want them at the bottom, just before Save is good.
	var save_btn = vbox.get_node("SaveButton")
	
	vbox.move_child(annotation_scroll, save_btn.get_index()) # Put scroll before save
	vbox.move_child(add_btn, save_btn.get_index())         # Put add btn before save (after scroll)


func _render_annotations():
	# Render from temp_annotations
	for child in annotation_container.get_children():
		child.queue_free()
		
	for i in range(temp_annotations.size()):
		var data = temp_annotations[i]
		_create_annotation_row(i, data)

func _create_annotation_row(index: int, data: Dictionary):
	var row = VBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	
	# --- HEADER (Title + Expand/Delete) ---
	var header = HBoxContainer.new()
	row.add_child(header)
	
	# Expand Toggle
	var toggle_btn = Button.new()
	toggle_btn.text = "v" if data.get("expanded", true) else ">"
	toggle_btn.custom_minimum_size = Vector2(24, 24)
	toggle_btn.flat = true
	header.add_child(toggle_btn)
	
	# Title Edit
	var title_edit = LineEdit.new()
	title_edit.text = data.get("title", "New Note")
	title_edit.placeholder_text = "Title"
	title_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_edit.flat = true # Look cleaner
	# Style override to look like header?
	header.add_child(title_edit)
	
	# Delete Button
	var del_btn = Button.new()
	del_btn.text = "x"
	del_btn.modulate = Color.RED
	del_btn.flat = true
	header.add_child(del_btn)
	
	# --- CONTENT (TextEdit) ---
	var content_edit = TextEdit.new()
	content_edit.text = data.get("content", "")
	content_edit.custom_minimum_size = Vector2(0, 100)
	content_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	content_edit.scroll_fit_content_height = true # Auto expand?
	row.add_child(content_edit)
	
	# Visibility Logic
	content_edit.visible = data.get("expanded", true)
	
	annotation_container.add_child(row)
	
	# --- CONNECTIONS ---
	# Connect signals to update 'data' reference directly (since dictionaries are passed by reference? No, generic get returns ref usually but let's be safe)
	# Safest to update current_node_data["annotations"][index]
	
	toggle_btn.pressed.connect(func():
		var is_exp = !content_edit.visible
		content_edit.visible = is_exp
		toggle_btn.text = "v" if is_exp else ">"
		_update_annotation_data(index, "expanded", is_exp)
	)
	
	title_edit.text_changed.connect(func(new_text):
		_update_annotation_data(index, "title", new_text)
	)
	
	content_edit.text_changed.connect(func():
		_update_annotation_data(index, "content", content_edit.text)
	)
	
	del_btn.pressed.connect(func():
		_delete_annotation(index)
	)

func _update_annotation_data(index: int, key: String, value):
	if index < 0 or index >= temp_annotations.size(): return
	temp_annotations[index][key] = value

func _add_new_annotation():
	temp_annotations.append({
		"title": "New Annotation",
		"content": "",
		"expanded": true
	})
	_render_annotations()

func _delete_annotation(index: int):
	temp_annotations.remove_at(index)
	_render_annotations()


func close_sidebar():
	# If already hidden, do nothing
	if not sidebar.visible:
		return
		
	# AUTO SAVE CHECK
	if Global.auto_save_on_unselect:
		_on_save_pressed()
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	
	# Move Sidebar Right (Off-screen) -> offset 0 to 300
	tween.tween_property(sidebar, "offset_left", 0, 0.3)
	tween.tween_property(sidebar, "offset_right", 300, 0.3)
	
	# After animation, hide everything
	tween.chain().tween_callback(func():
		sidebar.visible = false
	)

	current_node_ref = null

func _on_color_changed(color: Color):
	if current_node_data.is_empty(): return
	
	current_node_data["color"] = color.to_html()
	
	# Immediate Visual Update
	if current_node_ref and is_instance_valid(current_node_ref):
		if current_node_ref.has_method("set_color"):
			current_node_ref.set_color(color)
		
	pass

func _on_save_pressed():
	if current_node_data.is_empty(): return
	
	current_node_data["name"] = name_edit.text
	
	# Commit Annotations
	current_node_data["annotations"] = temp_annotations.duplicate(true)
	
	current_node_data["color"] = color_picker.color.to_html()
	
	if show_bg_checkbox:
		current_node_data["use_bg_color"] = show_bg_checkbox.button_pressed
	
	emit_signal("node_data_changed", current_node_data)
	
	if current_node_ref:
		if current_node_ref.has_method("update_visuals"):
			current_node_ref.update_visuals()
		# Also update color specifically if needed
	else:
		print("No current node ref to update")

func _on_add_button_pressed():
	emit_signal("add_node_requested")

func _setup_spacing_slider():
	spacing_slider = HSlider.new()
	spacing_slider.min_value = 2.0
	spacing_slider.max_value = 10.0
	spacing_slider.value = 3.0 # Default
	spacing_slider.step = 0.5
	
	spacing_slider.custom_minimum_size = Vector2(200, 30)
	
	# Add to ViewControls (Top Bar)
	$ForegroundLayer/ViewControls.add_child(spacing_slider)
	
	# Hidden by default (Free Mode)
	spacing_slider.visible = false
	
	spacing_slider.value_changed.connect(func(val): emit_signal("spacing_changed", val))


func _setup_bottom_left_buttons():
	# Add Button
	add_button.anchors_preset = Control.PRESET_BOTTOM_LEFT
	add_button.anchor_top = 1.0; add_button.anchor_bottom = 1.0
	add_button.anchor_left = 0.0; add_button.anchor_right = 0.0
	add_button.offset_left = 20
	add_button.offset_right = 60
	add_button.offset_top = -60
	add_button.offset_bottom = -20
	
	# Delete Mode Button
	delete_mode_btn.anchors_preset = Control.PRESET_BOTTOM_LEFT
	delete_mode_btn.anchor_top = 1.0; delete_mode_btn.anchor_bottom = 1.0
	delete_mode_btn.anchor_left = 0.0; delete_mode_btn.anchor_right = 0.0
	delete_mode_btn.offset_left = 80
	delete_mode_btn.offset_right = 200
	delete_mode_btn.offset_top = -60
	delete_mode_btn.offset_bottom = -20
	
	# Delete Cancel Button
	delete_cancel_btn.anchors_preset = Control.PRESET_BOTTOM_LEFT
	delete_cancel_btn.anchor_top = 1.0; delete_cancel_btn.anchor_bottom = 1.0
	delete_cancel_btn.anchor_left = 0.0; delete_cancel_btn.anchor_right = 0.0
	delete_cancel_btn.offset_left = 220
	delete_cancel_btn.offset_right = 260
	delete_cancel_btn.offset_top = -60
	delete_cancel_btn.offset_bottom = -20


func _on_delete_mode_pressed():
	# This button acts as "Enter Mode" OR "Confirm Delete" depending on state
	emit_signal("delete_mode_toggled", true) 

func _on_delete_cancel_pressed():
	emit_signal("delete_mode_toggled", false) # False = Cancel/Exit

func set_delete_mode_state(is_active: bool, items_marked: int = 0):
	delete_cancel_btn.visible = is_active
	
	if is_active:
		add_button.visible = false
		if items_marked > 0:
			delete_mode_btn.text = "Confirm (%d)" % items_marked
			delete_mode_btn.modulate = Color.RED
		else:
			delete_mode_btn.text = "Select Items"
			delete_mode_btn.modulate = Color.WHITE
	else:
		add_button.visible = true
		delete_mode_btn.text = "Delete Mode"
		delete_mode_btn.modulate = Color.WHITE

func _set_view_mode(mode: String):
	free_btn.button_pressed = (mode == "FREE")
	timeline_btn.button_pressed = (mode == "TIMELINE")
	
	# Align button only visible in Free Mode
	align_btn.visible = (mode == "FREE")
	
	# Slider only visible in Timeline Mode
	if spacing_slider:
		spacing_slider.visible = (mode == "TIMELINE")
	
	emit_signal("view_mode_changed", mode)

func is_bin_hovered() -> bool:
	if not recycling_bin.visible: return false
	return recycling_bin.get_global_rect().has_point(get_global_mouse_position())

func set_bin_visible(should_show: bool):
	if not recycling_bin: return
	
	# If state isn't changing and no animation is running, skip
	# But checking 'visible' might be misleading mid-animation. 
	# So we just enforce target state via tween.
	
	if bin_tween and bin_tween.is_valid():
		bin_tween.kill()
		
	bin_tween = create_tween()
	bin_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	if should_show:
		# SHOW
		# Ensure it's visible for animation
		if not recycling_bin.visible:
			recycling_bin.visible = true
			# Reset to off-screen starting pos if appearing
			# We assume Bottom Anchor. Offset Bottom usually 0 or negative.
			# Let's slide up from +150 (below screen) to its Original Pos.
			# Problem: We need to know Original Pos.
			# Let's assume layout in Editor is correct "Shown" state.
			# But if we hide it, we might lose it?
			# Better: Tween 'position:y' or 'offset'.
			# Let's assume it's anchored Center Bottom.
			# We will just offset it.
			
			# Current approach: Use modulation (fade) + Slide
			recycling_bin.modulate.a = 0.0
			# Offset Y by +100 relative to current (which should be target)
			# Only if we are securely at target.
			# Let's use a fixed offset approach.
			# If we rely on anchors, 'position.y' changes with resize. 
			# 'anchor_bottom' = 1.
			# Let's tween 'offset_bottom' and 'offset_top'.
			pass
			
		# ANIMATE IN
		bin_tween.set_parallel(true)
		bin_tween.tween_property(recycling_bin, "modulate:a", 1.0, 0.4)
		# We need a robust "Slide" that works with anchors.
		# A simple Pivot offset or Margin adjustment.
		# Let's try simpler: Just Fade + Scale? User asked for Translate.
		# Translate from "Out of screen" (Down).
		# We can change 'position.y'.
		# But we need to target the Correct Y. 
		# Let's use control's anchors.
		# If we assume it is correctly placed, we can treat current position as Target.
		# But since we hide it, we don't track state.
		# FIX: In _ready, we store 'default_bin_pos_y' or similar?
		# Or just use hardcoded offset if we know it's at bottom.
		
		# Let's try: visible = true. Move it down 100px. Tween to Original.
		# But if we call this multiple times, "Original" moves down repeatedly!
		# We need a latch.
		pass 
		
		# Better implementation:
		# Just set visible. 
		# Tween 'position:y' from (Target + 100) to Target.
		# How to get Target?
		# It's where it is right not (layout).
		var target_y = recycling_bin.position.y
		
		# If we are "Hidden" (via logic), we might be actually hidden or sitting at off-screen.
		# Let's use a variable 'is_bin_shown' to track logical state.
		
		recycling_bin.visible = true
		
		# Perform Slide Up
		# Force restart pos
		recycling_bin.position.y = target_y + 150
		bin_tween.tween_property(recycling_bin, "position:y", target_y, 0.4)
		bin_tween.tween_property(recycling_bin, "modulate:a", 1.0, 0.3)
		
	else:
		# HIDE
		# Slide Down + Fade Out
		bin_tween.set_parallel(true)
		bin_tween.tween_property(recycling_bin, "position:y", recycling_bin.position.y + 150, 0.3).set_ease(Tween.EASE_IN)
		bin_tween.tween_property(recycling_bin, "modulate:a", 0.0, 0.3)
		
		bin_tween.chain().tween_callback(func(): 
			recycling_bin.visible = false
			# Restore position so it doesn't drift if layout updates?
			# Actually resetting position here is tricky if we don't know original.
			# But next Show() captures current (which is +150!) -> BUG.
			# WE NEED ORIGINAL POSITION.
			
			# Undo the move logic.
			recycling_bin.position.y -= 150
		)

var bin_tween: Tween = null

func _setup_exit_button():
	var btn = Button.new()
	btn.text = "X"
	btn.modulate = Color.RED
	
	# Top Right Anchor
	btn.layout_mode = 1 # Anchors
	btn.anchors_preset = Control.PRESET_TOP_RIGHT
	btn.offset_left = -40
	btn.offset_bottom = 40
	btn.offset_top = 10
	btn.offset_right = -10
	
	btn.pressed.connect(func(): 
		# Auto-save any open sidebar changes before exiting
		if sidebar.visible:
			_on_save_pressed()
			
		emit_signal("exit_requested")
	)
	add_child(btn)

func is_sidebar_open() -> bool:
	return sidebar.visible

func _setup_toast_ui():
	# Create Toast Label
	toast_label = Label.new()
	toast_label.name = "ToastLabel"
	
	# Style
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.1, 0.9)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	
	toast_label.add_theme_stylebox_override("normal", style)
	
	# Font
	toast_label.add_theme_font_size_override("font_size", 24)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	# Positioning (Bottom Center)
	toast_label.anchors_preset = Control.PRESET_BOTTOM_WIDE
	toast_label.anchor_top = 1.0
	toast_label.anchor_bottom = 1.0
	toast_label.anchor_left = 0.5
	toast_label.anchor_right = 0.5
	toast_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	
	# Offsets - Just approximate centering with fixed width or auto width?
	# Using anchors preset center bottom is better
	toast_label.anchors_preset = Control.PRESET_CENTER_BOTTOM
	toast_label.offset_bottom = -100
	toast_label.offset_top = -150 # Height determined by content, but this sets initial pos
	
	toast_label.modulate.a = 0.0 # Hidden initially
	
	$ForegroundLayer.add_child(toast_label)

func show_toast(message: String, duration: float = 3.0):
	if not toast_label: return
	
	toast_label.text = message
	
	# Kill existing animation
	if toast_tween and toast_tween.is_valid():
		toast_tween.kill()
		
	toast_tween = create_tween()
	
	# 1. Fade In + Slide Up
	toast_label.modulate.a = 0.0
	toast_label.position.y += 20
	
	toast_tween.set_parallel(true)
	toast_tween.tween_property(toast_label, "modulate:a", 1.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	toast_tween.tween_property(toast_label, "position:y", toast_label.position.y - 20, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# 2. Wait
	toast_tween.set_parallel(false)
	toast_tween.tween_interval(duration)
	
	# 3. Fade Out
	toast_tween.tween_property(toast_label, "modulate:a", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
