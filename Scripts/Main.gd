extends Node3D

const MoodNodeScene = preload("res://Scenes/MoodNode.tscn")

@onready var camera = $Camera3D
@onready var node_root = $NodeRoot

var current_depth_layer = 0
var current_path_stack: Array = [] 

const DEFAULT_DATA_PATH = "res://default_data.json"
const DEBUG_DATA_PATH = "res://debug_data.json"

# Data Structure 
var mood_data = {}

# Grid Layout Configuration
const GRID_COLS = 5
const GRID_SPACING_X = 2.5
const GRID_SPACING_Y = 2.5

var ui_layer = null

func _ready():
	var ui_scene = preload("res://Scenes/UI.tscn").instantiate()
	ui_scene.name = "UI"
	add_child(ui_scene)
	ui_layer = ui_scene
	ui_scene.connect("add_node_requested", add_new_node)
	ui_scene.connect("node_data_changed", func(_d): save_data())
	ui_scene.connect("node_data_changed", func(_d): save_data())
	ui_scene.connect("exit_requested", return_to_menu)
	
	# Camera connection removed (no longer needed for rotation)
	
	load_data()
	
	if mood_data.is_empty():
		# Fallback if both files fail
		mood_data = {"name": "Empty Board", "color": Color.GRAY.to_html(), "children": []}
	
	# Pool initialization removed
		
	_spawn_layer(mood_data, Vector3.ZERO)

func save_data():
	# Don't save in Tutorial Mode
	if Global.is_tutorial:
		return
		
	if Global.current_file_path == "":
		print("Error: No save path defined")
		return

	var file = FileAccess.open(Global.current_file_path, FileAccess.WRITE)
	if file:
		var json = JSON.stringify(mood_data)
		file.store_string(json)
		print("Saved to: ", Global.current_file_path)

func load_data():
	# 1. Tutorial Mode / Debug
	if Global.is_tutorial:
		if FileAccess.file_exists(DEFAULT_DATA_PATH):
			var file = FileAccess.open(DEFAULT_DATA_PATH, FileAccess.READ)
			if _parse_json_file(file) == OK:
				print("Loaded Tutorial Data")
				return
		
		# Fallback to empty if default missing
		mood_data = {"name": "Tutorial (Empty)", "color": Color.GRAY.to_html(), "children": []}
		return

	# 2. Load Specific File
	if Global.current_file_path != "" and FileAccess.file_exists(Global.current_file_path):
		var file = FileAccess.open(Global.current_file_path, FileAccess.READ)
		if _parse_json_file(file) == OK:
			print("Loaded Board: ", Global.current_file_path)
			return
			
	# 3. New File (or missing)
	if Global.current_file_path != "":
		print("Creating New Board: ", Global.current_file_path)
		mood_data = {"name": "New Board", "color": Color.hex(0x4B0082FF).to_html(), "children": []}
		save_data() # Create the file
		return
		
	# Fallback (Shouldn't happen if coming from Menu)
	mood_data = {"name": "Error - No File", "color": Color.RED.to_html(), "children": []}

func _parse_json_file(file: FileAccess) -> Error:
	var json_str = file.get_as_text()
	var json = JSON.new()
	var error = json.parse(json_str)
	if error == OK:
		mood_data = json.data
	else:
		print("JSON Parse Error: ", json.get_error_message())
	return error

func _unhandled_input(event):
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			_go_up_layer()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			# If we clicked empty space (since this is unhandled), close sidebar
			if ui_layer:
				ui_layer.close_sidebar()

func _go_up_layer():
	if current_path_stack.is_empty():
		return
		
	var parent_data = current_path_stack.pop_back()
	
	# Transition
	_spawn_layer(parent_data, Vector3.ZERO, AnimType.TUNNEL_OUT)
	
	# Removed camera reset tween, handled by _spawn_layer reset

func add_new_node():
	if current_view_data.has("children"):
		var new_node_data = {
			"name": "New Idea",
			"color": Color.from_hsv(randf(), 0.7, 0.9),
			"children": []
		}
		current_view_data["children"].append(new_node_data)
		_spawn_layer(current_view_data, Vector3.ZERO) # Refresh view


enum AnimType { DEFAULT, TUNNEL_IN, TUNNEL_OUT }

var current_view_data: Dictionary = {}

func _process(_delta):
	pass # No continuous updates needed for grid

func _spawn_layer(parent_data: Dictionary, center_pos: Vector3, anim_type: AnimType = AnimType.DEFAULT, focus_pos: Vector3 = Vector3.ZERO):
	current_view_data = parent_data
	var children_data = parent_data.get("children", [])
	
	# Transition Animation: Clean up OLD nodes
	# For simplicity, let's just queue_free everything in node_root that is a MoodNode
	# Or if we want animation, we can tunnel them out.
	
	# 1. Create Exit Snapshot (Tunnel Effect)
	var exit_root = Node3D.new()
	add_child(exit_root)
	
	# Move current children to exit_root
	# Note: This reparents them, so they are removed from node_root
	var old_nodes = node_root.get_children()
	for child in old_nodes:
		child.reparent(exit_root)
		# Fade out logic if desired
		if child.has_method("fade_label"):
			child.fade_label(0.0, 0.2)

	# 2. Spawn NEW nodes
	var idx = 0
	for data in children_data:
		var n = MoodNodeScene.instantiate()
		node_root.add_child(n)
		n.setup(data)
		n.connect("node_entered", _on_node_entered)
		n.connect("node_selected", _on_node_selected)
		n.connect("node_drag_started", _on_node_drag_started)
		n.connect("node_drag_ended", _on_node_drag_ended)
		
		# Grid Layout Logic
		var col = idx % GRID_COLS
		var row = idx / GRID_COLS
		
		# Centering offset (optional)
		var start_x = -(GRID_COLS * GRID_SPACING_X) / 2.0 + GRID_SPACING_X / 2.0
		var x_pos = start_x + (col * GRID_SPACING_X)
		var y_pos = -(row * GRID_SPACING_Y) # Grow downwards
		
		n.position = Vector3(x_pos, y_pos, 0)
		
		# Entry Animation
		if anim_type == AnimType.TUNNEL_IN:
			# Drill Down: New nodes come from distance (Deep)
			n.scale = Vector3.ZERO
			n.position.z = -50.0
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(n, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(n, "position:z", 0.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			
		elif anim_type == AnimType.TUNNEL_OUT:
			# Go Back: New nodes come from Camera (Behind/Close)
			# Start Big and Close
			n.scale = Vector3.ONE * 3.0
			n.position.z = 20.0 
			if n.has_method("set_label_opacity"):
				n.set_label_opacity(0.0)
				n.fade_label(1.0, 0.5)
			
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(n, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tween.tween_property(n, "position:z", 0.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			
		else:
			# Default Pop
			n.scale = Vector3.ZERO
			var tween = create_tween()
			tween.tween_property(n, "scale", Vector3.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(randf() * 0.2)
		
		idx += 1
		
	# Animate Exit Root
	var exit_tween = create_tween().set_parallel(true)
	if anim_type == AnimType.TUNNEL_IN:
		# Zoom Exit Root big and fade
		exit_tween.tween_property(exit_root, "position:z", 20.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		exit_tween.tween_property(exit_root, "scale", Vector3.ONE * 3.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		exit_tween.tween_property(exit_root, "modulate:a", 0.0, 0.5)
	elif anim_type == AnimType.TUNNEL_OUT:
		# Shrink away
		exit_tween.tween_property(exit_root, "position:z", -50.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		exit_tween.tween_property(exit_root, "scale", Vector3.ZERO, 0.5)
	else:
		# Just fade out
		exit_tween.tween_property(exit_root, "modulate:a", 0.0, 0.3)
	
	exit_tween.chain().tween_callback(exit_root.queue_free)


func _on_node_selected(node):
	if ui_layer:
		ui_layer.show_sidebar(node.node_data, node)

func _on_node_drag_started(_node):
	if ui_layer:
		ui_layer.set_bin_visible(true)

func _on_node_drag_ended(node):
	if ui_layer:
		if ui_layer.is_bin_hovered():
			pass # Handle delete? With virtual scroll, deleting from list is trickier.
		ui_layer.set_bin_visible(false)



func _on_node_entered(node):
	_enter_node(node)

func _enter_node(node):
	var data = node.node_data
	current_path_stack.append(current_view_data) 
	
	# Pass the *current* local position of the node as the focus point
	_spawn_layer(data, Vector3.ZERO, AnimType.TUNNEL_IN)
func return_to_menu():
	save_data()
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")
