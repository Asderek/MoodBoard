extends Control

signal add_node_requested
signal node_data_changed(node_data)
signal jump_requested(percent)
signal exit_requested
# New Signals
signal delete_mode_toggled(active)
signal delete_confirmed

@onready var add_button = $ForegroundLayer/AddButton
@onready var delete_mode_btn = $ForegroundLayer/DeleteModeButton
@onready var delete_cancel_btn = $ForegroundLayer/DeleteCancelButton

@onready var sidebar = $ForegroundLayer/Sidebar
@onready var name_edit = $ForegroundLayer/Sidebar/VBoxContainer/NameEdit
@onready var desc_edit = $ForegroundLayer/Sidebar/VBoxContainer/DescEdit
@onready var recycling_bin = $ForegroundLayer/RecycleBin
var current_node_data: Dictionary = {}
var current_node_ref = null

func _ready():
	add_button.pressed.connect(_on_add_button_pressed)
	$ForegroundLayer/Sidebar/VBoxContainer/SaveButton.pressed.connect(_on_save_pressed)
	
	# Delete Mode Connections
	delete_mode_btn.pressed.connect(_on_delete_mode_pressed)
	delete_cancel_btn.pressed.connect(_on_delete_cancel_pressed)
	delete_cancel_btn.visible = false
	
	sidebar.visible = false
	recycling_bin.visible = false
	
	_setup_exit_button()

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
	
	btn.pressed.connect(func(): emit_signal("exit_requested"))
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

func close_sidebar():
	sidebar.visible = false
	current_node_ref = null

func _on_save_pressed():
	if current_node_data.is_empty(): return
	
	current_node_data["name"] = name_edit.text
	current_node_data["description"] = desc_edit.text
	
	emit_signal("node_data_changed", current_node_data)
	
	if current_node_ref:
		if current_node_ref.has_method("update_visuals"):
			current_node_ref.update_visuals()
		else:
			print("Node ref missing update_visuals method")
	else:
		print("No current node ref to update")
