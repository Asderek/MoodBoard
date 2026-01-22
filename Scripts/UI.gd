extends Control

signal add_node_requested
signal node_data_changed(node_data)
signal jump_requested(percent)
signal exit_requested

@onready var add_button = $ForegroundLayer/AddButton
@onready var sidebar = $ForegroundLayer/Sidebar
@onready var name_edit = $ForegroundLayer/Sidebar/VBoxContainer/NameEdit
@onready var desc_edit = $ForegroundLayer/Sidebar/VBoxContainer/DescEdit
@onready var recycling_bin = $ForegroundLayer/RecycleBin
var current_node_data: Dictionary = {}
var current_node_ref = null
	# Add Background Color (since Viewport is transparent now)
	# REMOVED: ColorRect blocks 3D view because CanvasLayers render after 3D.
	

func _ready():
	add_button.pressed.connect(_on_add_button_pressed)
	$ForegroundLayer/Sidebar/VBoxContainer/SaveButton.pressed.connect(_on_save_pressed)
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
