extends Node3D

const MoodNodeScene = preload("res://Scenes/MoodNode.tscn")

@onready var camera = $Camera3D
@onready var node_root = $NodeRoot

var current_depth_layer = 0
var current_path_stack: Array = [] 

const SAVE_PATH = "user://mood_board_save.json"
const DEFAULT_DATA_PATH = "res://default_data.json"
const DEBUG_DATA_PATH = "res://debug_data.json"

# Data Structure 
var mood_data = {}

var ui_layer = null

func _ready():
	var ui_scene = preload("res://Scenes/UI.tscn").instantiate()
	ui_scene.name = "UI"
	add_child(ui_scene)
	ui_layer = ui_scene
	ui_scene.connect("add_node_requested", add_new_node)
	ui_scene.connect("node_data_changed", func(_d): save_data())
	
	# Connect Camera Rotation (Renamed from panned)
	camera.connect("rotated", _on_camera_rotated)
	
	load_data()
	
	if mood_data.is_empty():
		# Fallback if both files fail
		mood_data = {"name": "Empty Board", "color": Color.GRAY.to_html(), "children": []}
	
	_spawn_layer(mood_data, Vector3.ZERO)

func save_data():
	var file = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		var json = JSON.stringify(mood_data)
		file.store_string(json)

func load_data():
	# 1. Try Debug Data (res://debug_data.json) - Priority!
	if FileAccess.file_exists(DEBUG_DATA_PATH):
		var file = FileAccess.open(DEBUG_DATA_PATH, FileAccess.READ)
		var error = _parse_json_file(file)
		if error == OK:
			print("DEBUG MODE: Loaded debug_data.json")
			return

	# 2. Try User Save
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var error = _parse_json_file(file)
		if error == OK:
			print("Loaded User Save")
			return
	
	# 3. Try Default Data (res://)
	if FileAccess.file_exists(DEFAULT_DATA_PATH):
		var file = FileAccess.open(DEFAULT_DATA_PATH, FileAccess.READ)
		var error = _parse_json_file(file)
		if error == OK:
			print("Loaded Default Data")
			return

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

func _spawn_layer(parent_data: Dictionary, center_pos: Vector3, anim_type: AnimType = AnimType.DEFAULT, focus_pos: Vector3 = Vector3.ZERO):
	current_view_data = parent_data
	
	# --- Auto-Clustering Logic ---
	# If parent_data has children, we must process them to check for Clustering needs
	var processed_children = _process_layer_data(parent_data.get("children", []))
	
	# --- Rotation Handling ---
	# We want to maintain continuity.
	# The previous `node_root` might be rotated.
	# When we spawn the NEW layer, does it start at rotation 0?
	# YES, usually. We are "entering" a new context.
	# But the EXIT transition needs to account for the current rotation.
	
	var current_rot = node_root.rotation.z
	
	node_root.rotation.z = 0 # Reset for new layer
	
	# Handle existing nodes animation (Exit)
	var old_nodes = node_root.get_children()
	var exit_root = Node3D.new()
	add_child(exit_root)
	
	# Match rotation so no visual snap
	exit_root.rotation.z = current_rot
	
	for child in old_nodes:
		child.reparent(exit_root) 
		if child.has_method("fade_label"):
			child.fade_label(0.0, 0.2)
	
	var exit_tween = create_tween().set_parallel(true)
	
	if anim_type == AnimType.TUNNEL_IN:
		# ANIMATION:
		# Tunnel In Target: The clicked node at `focus_pos` (local to `exit_root`).
		# We want to bring that node to (0,0,Z_behind).
		# BUT `exit_root` is rotated by `current_rot`.
		# So the WORLD position of the target is: `focus_pos.rotated(Z, current_rot)`.
		
		# To center it, we need to move `exit_root` so that world pos becomes (0,0).
		# `exit_root.position` should be opposite of the rotated focus pos.
		
		var world_focus_target = focus_pos.rotated(Vector3.BACK, current_rot) # Vector3.BACK is (0,0,1)? Wrapper needed.
		# Actually, rotation is Z axis. Vector3 rotation in GDScript:
		var start_vec = Vector3(focus_pos.x, focus_pos.y, 0)
		var rotated_vec = start_vec.rotated(Vector3(0,0,1), current_rot)
		
		var duration = 0.5
		
		# 1. Center the target node (XY)
		exit_tween.tween_property(exit_root, "position:x", -rotated_vec.x, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		exit_tween.tween_property(exit_root, "position:y", -rotated_vec.y, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		
		# 2. Zoom pass (Z)
		exit_tween.tween_property(exit_root, "position:z", 20.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		exit_tween.tween_property(exit_root, "scale", Vector3.ONE * 3.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		
	elif anim_type == AnimType.TUNNEL_OUT:
		# Going Back:
		exit_tween.tween_property(exit_root, "position:z", -50.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		exit_tween.tween_property(exit_root, "scale", Vector3.ZERO, 0.5)
	
	else:
		for child in old_nodes:
			child.queue_free()
		exit_root.queue_free()
	
	if anim_type != AnimType.DEFAULT:
		exit_tween.chain().tween_callback(exit_root.queue_free)

	# --- Spawn New Nodes ---

	var count = processed_children.size()
	# Standard radius for ~12 items
	var radius = 4.0 if count <= 12 else 6.0 
	var angle_step = TAU / count
	
	for i in range(count):
		var data = processed_children[i]
		var angle = i * angle_step
		var pos_offset = Vector3(cos(angle) * radius, sin(angle) * radius, 0)
		var target_pos = center_pos + pos_offset
		
		# Override layout with saved position if exists
		if data.has("position_x") and data.has("position_y"):
			target_pos = Vector3(data["position_x"], data["position_y"], 0)
		
		var node_inst = MoodNodeScene.instantiate()
		node_root.add_child(node_inst)
		node_inst.setup(data)
		node_inst.connect("node_entered", _on_node_entered)
		node_inst.connect("node_selected", _on_node_selected)
		node_inst.connect("node_drag_started", _on_node_drag_started)
		node_inst.connect("node_drag_ended", _on_node_drag_ended)
		
		# Animate Entry
		if anim_type == AnimType.TUNNEL_IN:
			# New nodes come from distance
			node_inst.position = Vector3(target_pos.x, target_pos.y, -50)
			node_inst.scale = Vector3.ZERO
			node_inst.set_label_opacity(0.0) # Hide label initially
			
			var tween = create_tween()
			tween.tween_property(node_inst, "position", target_pos, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * 0.05 + 0.3)
			tween.parallel().tween_property(node_inst, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * 0.05 + 0.3)
			# Fade label in at end
			node_inst.fade_label(1.0, 0.3, 0.8) # Delay until near end matches anim time
			
		elif anim_type == AnimType.TUNNEL_OUT:
			# New nodes come from "behind" camera (top/down per user desc, or just zoom in form back)
			node_inst.position = Vector3(target_pos.x, target_pos.y, 10)
			node_inst.scale = Vector3.ONE * 2.0
			node_inst.set_label_opacity(0.0)
			
			var tween = create_tween()
			tween.tween_property(node_inst, "position", target_pos, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(i * 0.05 + 0.2)
			tween.parallel().tween_property(node_inst, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT).set_delay(i * 0.05 + 0.2)
			node_inst.fade_label(1.0, 0.3, 0.7)
			
		else:
			# Default Pop-in
			node_inst.position = target_pos
			node_inst.scale = Vector3.ZERO
			var tween = create_tween()
			tween.tween_property(node_inst, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(i * 0.1)

func _on_node_selected(node):
	if ui_layer:
		ui_layer.show_sidebar(node.node_data, node)

func _on_node_drag_started(_node):
	if ui_layer:
		ui_layer.set_bin_visible(true)

func _on_node_drag_ended(node):
	if ui_layer:
		if ui_layer.is_bin_hovered():
			_delete_node(node)
		ui_layer.set_bin_visible(false)

func _delete_node(node):
	var data = node.node_data
	if current_view_data.has("children"):
		current_view_data["children"].erase(data)
		node.queue_free()
		# Close sidebar if it was showing this node
		ui_layer.close_sidebar()

func _on_node_entered(node):
	var data = node.node_data
	# Direct tunnel entry instead of camera zoom first
	_enter_node(node)

func _on_camera_rotated(angle_delta: float):
	# Rotate the whole ring
	node_root.rotation.z += angle_delta
	
	# Counter-rotate children so they stay upright (Ferris Wheel effect)
	var current_rot = node_root.rotation.z
	for child in node_root.get_children():
		child.rotation.z = -current_rot

# --- Auto Clustering ---
func _process_layer_data(raw_children: Array) -> Array:
	const MAX_NODES = 12
	if raw_children.size() <= MAX_NODES:
		return raw_children
		
	# CLUSTERING ALGORITHM
	var clusters = []
	var chunk_size = MAX_NODES 
	# If massive (e.g. 1000), we might need larger chunks or recursive logic.
	# For now, simple chunking is fine for 100s.
	
	var chunks = []
	var current_chunk = []
	for item in raw_children:
		current_chunk.append(item)
		if current_chunk.size() >= chunk_size:
			chunks.append(current_chunk)
			current_chunk = []
	if current_chunk.size() > 0:
		chunks.append(current_chunk)
		
	# Create Cluster Nodes
	for idx in range(chunks.size()):
		var chunk = chunks[idx]
		var first_name = chunk[0].get("name", "Unknown")
		var last_name = chunk[-1].get("name", "Unknown")
		
		# Abbreviate names for label? 
		var cluster_name = "%s - %s" % [first_name.left(10), last_name.left(10)]
		if first_name.left(1) == last_name.left(1): # Same letter grouping?
			cluster_name = first_name.left(1) + " Section " + str(idx+1)
			
		var cluster_node_data = {
			"name": cluster_name,
			"color": Color.GRAY.to_html(), # Neutral color for groups
			"children": chunk, # The actual items are children of this group!
			"is_cluster": true # Marker
		}
		clusters.append(cluster_node_data)
		
	return clusters

	
func _enter_node(node):
	var data = node.node_data
	current_path_stack.append(current_view_data) 
	
	# Pass the *current* local position of the node as the focus point
	# but we need it relative to the NodeRoot's current transform if we weren't parenting?
	# The node is a child of node_root.
	# So `node.position` is local to `node_root`.
	_spawn_layer(data, Vector3.ZERO, AnimType.TUNNEL_IN, node.position)
