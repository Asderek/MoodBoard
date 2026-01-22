extends CanvasLayer

signal add_node_requested
signal node_data_changed(node_data)
signal jump_requested(percent)
signal exit_requested

@onready var add_button = $AddButton
@onready var sidebar = $Sidebar
@onready var name_edit = $Sidebar/VBoxContainer/NameEdit
@onready var desc_edit = $Sidebar/VBoxContainer/DescEdit
@onready var recycle_bin = $RecycleBin

var current_node_data: Dictionary = {}
var current_node_ref = null # To update visuals in real-time if needed? Or just data.

func _ready():
	add_button.pressed.connect(_on_add_button_pressed)
	$Sidebar/VBoxContainer/SaveButton.pressed.connect(_on_save_pressed)
	sidebar.visible = false
	recycle_bin.visible = false
	
	_setup_exit_button()

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

func set_bin_visible(is_visible: bool):
	recycle_bin.visible = is_visible

func is_bin_hovered() -> bool:
	if not recycle_bin.visible: return false
	var mouse_pos = recycle_bin.get_global_mouse_position()
	return recycle_bin.get_global_rect().has_point(mouse_pos)
