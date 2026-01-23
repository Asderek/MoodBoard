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
@onready var desc_edit = $ForegroundLayer/Sidebar/VBoxContainer/DescEdit
@onready var color_picker = $ForegroundLayer/Sidebar/VBoxContainer/ColorPickerButton
@onready var recycling_bin = $ForegroundLayer/RecycleBin
var current_node_data: Dictionary = {}
var current_node_ref = null

func _ready():
	add_button.pressed.connect(_on_add_button_pressed)
	$ForegroundLayer/Sidebar/VBoxContainer/SaveButton.pressed.connect(_on_save_pressed)
	
	if recycling_bin:
		recycling_bin.visible = false
	
	_setup_bg_toggle() # Add CheckBox dynamically
	_setup_sidebar_toggle()
	_setup_exit_button()
	_setup_bottom_left_buttons()
	
	# Fix: Explicitly connect delete buttons (missing from previous cleanup)
	delete_mode_btn.pressed.connect(_on_delete_mode_pressed)
	delete_cancel_btn.pressed.connect(_on_delete_cancel_pressed)
	
	# Fix: Connect View Controls (Free, Timeline, Align)
	free_btn.pressed.connect(func(): _set_view_mode("FREE"))
	timeline_btn.pressed.connect(func(): _set_view_mode("TIMELINE"))
	align_btn.pressed.connect(func(): emit_signal("align_grid_requested"))
	
	_setup_spacing_slider()
	
	color_picker.color_changed.connect(_on_color_changed)

var show_bg_checkbox: CheckBox = null
var spacing_slider: HSlider = null
var sidebar_toggle_btn: Button = null

func _setup_bg_toggle():
	show_bg_checkbox = CheckBox.new()
	show_bg_checkbox.text = "Show Background Box"
	# Add before Save Button (which is last)
	var vbox = $ForegroundLayer/Sidebar/VBoxContainer
	vbox.add_child(show_bg_checkbox)
	vbox.move_child(show_bg_checkbox, vbox.get_child_count() - 2) # Before Save Button
	
	show_bg_checkbox.toggled.connect(_on_bg_toggled)

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
	if sidebar_toggle_btn:
		sidebar_toggle_btn.visible = true
	
	# Auto-open if collapsed (logical state)
	if is_sidebar_collapsed:
		_on_toggle_sidebar() # This handles its own animation
	elif not was_visible:
		# Initial Open Animation (Slide In)
		# Start Off-Screen (Collapsed Position)
		sidebar.offset_left = 0
		sidebar.offset_right = 300
		
		if sidebar_toggle_btn:
			sidebar_toggle_btn.offset_left = -160 + 300 # 140
			sidebar_toggle_btn.offset_right = -120 + 300 # 180
			
		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		
		# Move to On-Screen (Open Position)
		tween.tween_property(sidebar, "offset_left", -300, 0.3)
		tween.tween_property(sidebar, "offset_right", 0, 0.3)
		
		if sidebar_toggle_btn:
			tween.tween_property(sidebar_toggle_btn, "offset_left", -160, 0.3)
			tween.tween_property(sidebar_toggle_btn, "offset_right", -120, 0.3)
			
	# Else: It is already open and visible, no need to touch position.
		
	name_edit.text = str(node_data.get("name", ""))
	desc_edit.text = str(node_data.get("description", ""))
	
	var col_html = node_data.get("color", "ffffff")
	color_picker.color = Color.html(col_html)
	
	# Update Checkbox
	if show_bg_checkbox:
		show_bg_checkbox.set_pressed_no_signal(node_data.get("use_bg_color", true))

func _setup_sidebar_toggle():
	var btn = Button.new()
	btn.text = "≡" # Sandwich Icon
	btn.name = "SidebarToggle"
	sidebar_toggle_btn = btn
	
	$ForegroundLayer.add_child(btn)
	btn.visible = false # Hidden by default
	
	btn.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.offset_bottom = -20
	btn.offset_top = -80
	
	btn.offset_left = -160
	btn.offset_right = -120 
	
	btn.pressed.connect(_on_toggle_sidebar)

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
	
var is_sidebar_collapsed = false
const SIDEBAR_WIDTH = 300

func _on_toggle_sidebar():
	is_sidebar_collapsed = !is_sidebar_collapsed
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	
	var ctrls = [sidebar_toggle_btn]
	
	if is_sidebar_collapsed:
		tween.tween_property(sidebar, "offset_left", 0, 0.3)
		tween.tween_property(sidebar, "offset_right", 300, 0.3)
		
		
		for c in ctrls:
			if c:
				tween.tween_property(c, "offset_left", c.offset_left + 300, 0.3)
				tween.tween_property(c, "offset_right", c.offset_right + 300, 0.3)
				
	else:
		# SHOW Sidebar (Move Left onscreen)
		tween.tween_property(sidebar, "offset_left", -300, 0.3)
		tween.tween_property(sidebar, "offset_right", 0, 0.3)
		
		# Move Controls LEFT by 300 to avoid covering sidebar
		for c in ctrls:
			if c:
				tween.tween_property(c, "offset_left", c.offset_left - 300, 0.3)
				tween.tween_property(c, "offset_right", c.offset_right - 300, 0.3)


func close_sidebar():
	# If already hidden, do nothing
	if not sidebar.visible:
		return
		
	# If it's fully open (not collapsed), we want to animate it to "collapsed" (off-screen) state first
	if not is_sidebar_collapsed:
		# We can re-use the toggle logic closely, or just write a specific close tween
		# Let's write a specific one to ensure it ends with visible = false
		
		var tween = create_tween()
		tween.set_parallel(true)
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		
		# Move Sidebar Right (Off-screen) -> offset 0 to 300
		tween.tween_property(sidebar, "offset_left", 0, 0.3)
		tween.tween_property(sidebar, "offset_right", 300, 0.3)
		
		# Move Toggle Button Right
		if sidebar_toggle_btn:
			tween.tween_property(sidebar_toggle_btn, "offset_left", sidebar_toggle_btn.offset_left + 300, 0.3)
			tween.tween_property(sidebar_toggle_btn, "offset_right", sidebar_toggle_btn.offset_right + 300, 0.3)
			
		# After animation, hide everything
		tween.chain().tween_callback(func():
			sidebar.visible = false
			if sidebar_toggle_btn:
				sidebar_toggle_btn.visible = false
			is_sidebar_collapsed = false # Reset state
		)
		
	else:
		# If it was already collapsed (minimized), just hide it
		sidebar.visible = false
		if sidebar_toggle_btn:
			sidebar_toggle_btn.visible = false
		is_sidebar_collapsed = false

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
	current_node_data["description"] = desc_edit.text
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

func set_bin_visible(visible: bool):
	recycling_bin.visible = visible

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
	return sidebar.visible and not is_sidebar_collapsed
