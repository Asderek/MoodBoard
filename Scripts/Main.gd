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
	# camera.position = Vector3(0, 0, -2) # Removed old cam effect, using node animation
	_spawn_layer(parent_data, Vector3.ZERO, AnimType.TUNNEL_OUT)
	
	# Reset camera smoothly just in case panned
	var tween = create_tween()
	tween.tween_property(camera, "position", Vector3(0, 0, 12), 0.5).set_trans(Tween.TRANS_CUBIC)

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
	
	# Handle existing nodes animation (Exit)
	var old_nodes = node_root.get_children()
	var exit_root = Node3D.new()
	add_child(exit_root)
	
	for child in old_nodes:
		child.reparent(exit_root) # Move to temp root for group animation
		# Fade out labels immediately for clean transition
		if child.has_method("fade_label"):
			child.fade_label(0.0, 0.2)
	
	var exit_tween = create_tween().set_parallel(true)
	
	if anim_type == AnimType.TUNNEL_IN:
		# Going Deeper: Center camera on the clicked node (by moving world opposite)
		# Split axes: Snap to center quickly (EaseOut) while accelerating forward (EaseIn)
		# This ensures we are "aimed" at the node before we fly through it.
		var duration = 0.5
		
		# XY Centering (Quart Out for snappy aiming)
		exit_tween.tween_property(exit_root, "position:x", -focus_pos.x, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		exit_tween.tween_property(exit_root, "position:y", -focus_pos.y, duration).set_trans(Tween.TRANS_QUART).set_ease(Tween.EASE_OUT)
		
		# Z Zoom (Expo In for tunnel acceleration)
		exit_tween.tween_property(exit_root, "position:z", 20.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		
		# Scale up to ensure we pass "through" it
		exit_tween.tween_property(exit_root, "scale", Vector3.ONE * 3.0, duration).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		
	elif anim_type == AnimType.TUNNEL_OUT:
		# Going Back: Current nodes shrink into distance
		# fade out faster?
		exit_tween.tween_property(exit_root, "position:z", -50.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
		exit_tween.tween_property(exit_root, "scale", Vector3.ZERO, 0.5)
	
	else:
		# Default: Just delete immediately (or simple fade)
		for child in old_nodes:
			child.queue_free()
		exit_root.queue_free() # No animation container needed here really if we free
	
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

func _enter_node(node):
	var data = node.node_data
	current_path_stack.append(current_view_data) 
	
	# Reset camera smoothly just in case panned
	var tween = create_tween()
	tween.tween_property(camera, "position", Vector3(0, 0, 12), 0.5).set_trans(Tween.TRANS_CUBIC)

	_spawn_layer(data, Vector3.ZERO, AnimType.TUNNEL_IN, node.position)
