extends Control

signal add_node_requested
signal node_data_changed(node_data)
signal jump_requested(percent)
signal exit_requested
# New Signals
signal delete_mode_toggled(active)
signal delete_confirmed
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
	
	color_picker.color_changed.connect(_on_color_changed)
	
	# Delete Mode Connections
	delete_mode_btn.pressed.connect(_on_delete_mode_pressed)
	delete_cancel_btn.pressed.connect(_on_delete_cancel_pressed)
	delete_cancel_btn.visible = false
	
	# View Connections
	free_btn.pressed.connect(func(): _set_view_mode("FREE"))
	# Grid Toggle removed
	timeline_btn.pressed.connect(func(): _set_view_mode("TIMELINE"))
	align_btn.pressed.connect(func(): emit_signal("align_grid_requested"))
	
	sidebar.visible = false
	recycling_bin.visible = false
	
	_setup_exit_button()

func _set_view_mode(mode: String):
	free_btn.button_pressed = (mode == "FREE")
	timeline_btn.button_pressed = (mode == "TIMELINE")
	
	# Align button only visible in Free Mode
	align_btn.visible = (mode == "FREE")
	
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

func _on_add_button_pressed():
	emit_signal("add_node_requested")

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

func show_sidebar(node_data: Dictionary, node_ref):
	current_node_data = node_data
	current_node_ref = node_ref
	
	sidebar.visible = true
	name_edit.text = str(node_data.get("name", ""))
	desc_edit.text = str(node_data.get("description", ""))
	
	var col_html = node_data.get("color", "ffffff")
	color_picker.color = Color.html(col_html)

func close_sidebar():
	sidebar.visible = false
	current_node_ref = null

func _on_color_changed(color: Color):
	if current_node_data.is_empty(): return
	
	current_node_data["color"] = color.to_html()
	
	# Immediate Visual Update
	if current_node_ref and is_instance_valid(current_node_ref):
		if current_node_ref.has_method("set_color"):
			current_node_ref.set_color(color)
		
	# We could save immediately or just wait for Save Button.
	# Let's emit signal to update main data, which triggers save?
	# signal 'node_data_changed' triggers save in Main...
	# If we do this on every drag it might spam saves.
	# Better to just update visual here, and save on "Save Changes" or Sidebar Close?
	# Actually simple approach: Update visual, but update data. Save manually.
	# But user provided "click it once", maybe implies color picker close?
	# ColorPickerButton emits color_changed often.
	# Let's let "Save Changes" be the commit, BUT update Main data locally so if we close sidebar without saving, we lose it?
	# Standard Sidebar logic: "Save Changes" button commits text edits.
	# Color should probably be same to avoid confusion.
	# However, seeing it change in real time is nice.
	# I will only update visual in real time. Commit happens on save.
	pass

func _on_save_pressed():
	if current_node_data.is_empty(): return
	
	current_node_data["name"] = name_edit.text
	current_node_data["description"] = desc_edit.text
	current_node_data["color"] = color_picker.color.to_html()
	
	emit_signal("node_data_changed", current_node_data)
	
	if current_node_ref:
		if current_node_ref.has_method("update_visuals"):
			current_node_ref.update_visuals()
		# Also update color specifically if needed
	else:
		print("No current node ref to update")
