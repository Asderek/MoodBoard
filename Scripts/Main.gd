extends Node3D

const MoodNodeScene = preload("res://Scenes/MoodNode.tscn")

@onready var camera = $Camera3D
@onready var node_root = $NodeRoot

var current_depth_layer = 0
var current_path_stack: Array = [] 

const SAVE_PATH = "user://mood_board_v3.json"
const DEFAULT_DATA_PATH = "res://default_data.json"

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
	
	# Connect Camera Panning
	camera.connect("panned", _on_camera_panned)
	
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
	# 1. Try User Save
	if FileAccess.file_exists(SAVE_PATH):
		var file = FileAccess.open(SAVE_PATH, FileAccess.READ)
		var error = _parse_json_file(file)
		if error == OK:
			return
	
	# 2. Try Default Data (res://)
	if FileAccess.file_exists(DEFAULT_DATA_PATH):
		var file = FileAccess.open(DEFAULT_DATA_PATH, FileAccess.READ)
		var error = _parse_json_file(file)
		if error == OK:
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
	
	# --- Camera Panning Fix (Node Based) ---
	# The camera is STATIC at (0,0). The node_root is what moves.
	# When we spawn a new layer, we want the "center" of that new layer to be at (0,0).
	# But visually, we want to maintain continuity.
	
	# Current State:
	# node_root is at some position (P_old).
	# camera is at (0,0).
	
	# Transition Logic:
	# 1. We want to TUNNEL IN to a specific node at `focus_pos` (local to node_root).
	#    The world position of that node is `node_root.position + focus_pos`.
	#    To center it, we need to move `node_root` such that `node_root.position + focus_pos = (0,0)`.
	#    So Target Node Root Pos = `-focus_pos`.
	
	# 2. For the "Exit" animation (old nodes leaving), we treat them as a group.
	#    We move them into a temporary `exit_root` that mimics the current `node_root` transform.
	
	var old_nodes = node_root.get_children()
	var exit_root = Node3D.new()
	add_child(exit_root)
	
	# Inherit the current panning offset so they don't jump
	exit_root.position = node_root.position
	
	# Reset node_root to (0,0) for the NEW layer? 
	# Actually, for the NEW layer, we want it to start centered (0,0) by default, 
	# or should it inherit the parent's offset?
	# Users usually expect "entering" a node to reset the view to that node's context.
	# So RESETTING node_root to (0,0) is correct for the new layer's logical origin.
	
	node_root.position = Vector3.ZERO
	
	for child in old_nodes:
		child.reparent(exit_root) 
		if child.has_method("fade_label"):
			child.fade_label(0.0, 0.2)
	
	var exit_tween = create_tween().set_parallel(true)
	
	if anim_type == AnimType.TUNNEL_IN:
		# ANIMATION:
		# We want the *Clicked Node* (which is now inside exit_root) to fly towards the camera (0,0,Z).
		# The Clicked Node's position inside exit_root is `focus_pos`.
		# So we tween `exit_root.position` such that `exit_root.position + focus_pos` goes to `(0,0, Z_behind)`.
		
		# Current exit_root.position is whatever the user panned to.
		# Target exit_root.position = -focus_pos (to center X,Y)
		
		var duration = 0.5
		
		# 1. Center the target node (XY)
		exit_tween.tween_property(exit_root, "position:x", -focus_pos.x, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		exit_tween.tween_property(exit_root, "position:y", -focus_pos.y, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		
		# 2. Zoom pass (Z)
		# Move it way behind camera
		exit_tween.tween_property(exit_root, "position:z", 20.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		exit_tween.tween_property(exit_root, "scale", Vector3.ONE * 3.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		
	elif anim_type == AnimType.TUNNEL_OUT:
		# Going Back:
		# The current layer (now exit_root) shrinks into the distance.
		exit_tween.tween_property(exit_root, "position:z", -50.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		exit_tween.tween_property(exit_root, "scale", Vector3.ZERO, 0.5)
	
	else:
		for child in old_nodes:
			child.queue_free()
		exit_root.queue_free()
	
	if anim_type != AnimType.DEFAULT:
		exit_tween.chain().tween_callback(exit_root.queue_free)

	# --- Spawn New Nodes ---

	var children_data = parent_data.get("children", [])
	var count = children_data.size()
	# Reduced radius to ensure nodes fit in camera view (requested by user)
	var radius = 4.0 + (count * 0.5)
	var angle_step = TAU / count
	
	for i in range(count):
		var data = children_data[i]
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

func _on_camera_panned(relative_motion: Vector2):
	# Move node_root instead of camera
	# If I drag mouse RIGHT (positive x), camera would move LEFT. 
	# So we want objects to move RIGHT.
	# The event.relative is passed through.
	# CameraController: emit_signal("panned", event.relative * pan_sensitivity)
	
	node_root.position.x += relative_motion.x
	node_root.position.y -= relative_motion.y # Y is flip? Drag down (pos Y) = Move Objects Down? 
	# Standard pan: Drag text up -> Text moves up.
	# Mouse move down = +Y. Object Y += +Y.
	
func _enter_node(node):
	var data = node.node_data
	current_path_stack.append(current_view_data) 
	
	# Pass the *current* local position of the node as the focus point
	# but we need it relative to the NodeRoot's current transform if we weren't parenting?
	# The node is a child of node_root.
	# So `node.position` is local to `node_root`.
	_spawn_layer(data, Vector3.ZERO, AnimType.TUNNEL_IN, node.position)
