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
var selected_nodes: Array = []
var nodes_marked_for_deletion: Array = []
var is_delete_mode: bool = false

# Grid Layout Configuration
const GRID_COLS = 5
const GRID_SPACING_X = 2.5
const GRID_SPACING_Y = 2.5


var ui_layer = null
var current_dragging_node = null
var hovered_reparent_node = null

enum LayoutMode { FREE, TIMELINE }
var current_layout_mode = LayoutMode.FREE

const TIMELINE_LANE_HEIGHT = 4.0
var timeline_item_width = 3.0 # Changed to var for slider control

var timeline_lines_mesh: MeshInstance3D = null


func _ready():
	var ui_scene = preload("res://Scenes/UI.tscn").instantiate()
	ui_scene.name = "UI"
	add_child(ui_scene)
	ui_layer = ui_scene
	ui_scene.connect("add_node_requested", add_new_node)
	ui_scene.connect("node_data_changed", func(_d): save_data())
	ui_scene.connect("exit_requested", return_to_menu)
	ui_scene.connect("delete_mode_toggled", _on_delete_mode_toggled)
	
	# View Mode Connections
	ui_scene.connect("view_mode_changed", _on_view_mode_changed)
	ui_scene.connect("view_mode_changed", _on_view_mode_changed)
	ui_scene.connect("align_grid_requested", _on_align_grid_requested)
	ui_scene.connect("spacing_changed", _on_spacing_changed)
	
	# Drag & Drop Handler
	get_tree().get_root().files_dropped.connect(_on_files_dropped)
	
	# Setup Timeline Visuals
	timeline_lines_mesh = MeshInstance3D.new()
	timeline_lines_mesh.mesh = ImmediateMesh.new()
	var mat = StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1, 1, 1, 0.3)
	mat.vertex_color_use_as_albedo = true
	timeline_lines_mesh.material_override = mat
	add_child(timeline_lines_mesh)
	
	# Camera connection removed (no longer needed for rotation)

	# Camera connection removed (no longer needed for rotation)
	
	# Enable Transparent BG so UI BackgroundLayer (Layer -1) is visible behind 3D nodes
	# get_viewport().transparent_bg = true # REVERTED: Causes occlusion issues with 2D layers
	
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
		var board_name = Global.current_file_path.get_file().get_basename()
		mood_data = {"name": board_name, "color": Color.hex(0x4B0082FF).to_html(), "children": []}
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

func _on_files_dropped(files: PackedStringArray):
	# Calculate Drop Position (Mouse Raycast)
	var mouse_pos = get_viewport().get_mouse_position()
	var plane = Plane(Vector3.BACK, 0)
	var from = camera.project_ray_origin(mouse_pos)
	var dir = camera.project_ray_normal(mouse_pos)
	var world_pos = plane.intersects_ray(from, dir)
	
	if not world_pos: return
	
	# If we have multiple files, scatter them slightly?
	var offset = Vector3.ZERO
	
	for file_path in files:
		add_new_node_from_file(file_path, world_pos + offset)
		offset.x += 2.2 # Stack right

func add_new_node_from_file(path: String, pos: Vector3):
	if not current_view_data.has("children"): return

	var new_node_data = {
		"name": path.get_file(), # Use filename as label
		"color": Color.from_hsv(randf(), 0.7, 0.9).to_html(),
		"children": [],
		"created_at": Time.get_unix_time_from_system(),
		"timeline_id": 0,
		"timeline_index": 9999,
		"pos_y": pos.y,
		"pos_x": pos.x,
		"file_path": path, # Store absolute path
		"use_bg_color": false # Default to no background for images
	}
	
	if current_layout_mode == LayoutMode.TIMELINE:
		# Map Y to lane
		var lane = round(-pos.y / TIMELINE_LANE_HEIGHT)
		new_node_data["timeline_id"] = int(lane)
	
	current_view_data["children"].append(new_node_data)
	_spawn_layer(current_view_data, Vector3.ZERO) 
	save_data()

func _unhandled_input(event):
	if event is InputEventKey:
		if event.pressed and event.keycode == KEY_V:
			if event.ctrl_pressed or event.command_or_control_autoremap:
				_handle_paste()
				get_viewport().set_input_as_handled()
				
	if event is InputEventMouseButton:
		if event.pressed:
			# PRESS EVENTS
			if event.button_index == MOUSE_BUTTON_RIGHT:
				_go_up_layer()
			elif event.button_index == MOUSE_BUTTON_LEFT:
				if event.double_click:
					# Double Click on "Nothing" -> Create New Node
					# Check distance to existing nodes to ensure we are in "empty space"
					var mouse_pos = get_viewport().get_mouse_position()
					var plane = Plane(Vector3.BACK, 0)
					var from = camera.project_ray_origin(mouse_pos)
					var dir = camera.project_ray_normal(mouse_pos)
					
					var world_pos = plane.intersects_ray(from, dir)
					
					if world_pos:
						var is_safe_space = true
						# Node Width is 2.0. Threshold = Width * 1.5 = 3.0
						var safe_distance = 3.0 
						
						for child in node_root.get_children():
							# Check against visible nodes (exclude fading ones if any?)
							# Just check all direct children which are nodes
							if child.position.distance_to(world_pos) < safe_distance:
								is_safe_space = false
								break
						
						if is_safe_space:
							add_new_node()
							
				else:
					# Single Click on "Nothing"
					if ui_layer:
						ui_layer.close_sidebar()
					
					if Time.get_ticks_msec() - last_selection_time > 150:
						clear_selection()

func _handle_paste():
	if DisplayServer.clipboard_has_image():
		var img = DisplayServer.clipboard_get_image()
		if img:
			# Ensure directory exists
			var dir_path = "user://pasted_images"
			if not DirAccess.dir_exists_absolute(dir_path):
				DirAccess.make_dir_absolute(dir_path)
			
			# Generate Filename
			var timestamp = Time.get_ticks_msec()
			var file_path = dir_path + "/paste_%d.png" % timestamp
			
			var err = img.save_png(file_path)
			if err == OK:
				# Calculate paste position (at mouse cursor or screen center)
				# Preferred: Mouse Cursor
				var mouse_pos = get_viewport().get_mouse_position()
				var plane = Plane(Vector3.BACK, 0)
				var from = camera.project_ray_origin(mouse_pos)
				var dir = camera.project_ray_normal(mouse_pos)
				var world_pos = plane.intersects_ray(from, dir)
				
				if not world_pos: 
					world_pos = Vector3(0, 0, 0) # Fallback
				
				add_new_node_from_file(file_path, world_pos)
			else:
				print("Failed to save clipboard image: ", err)


func _go_up_layer():
	if current_path_stack.is_empty():
		return
		
	# QoL: Close Sidebar on Transition
	if ui_layer:
		ui_layer.close_sidebar()
		
	var parent_data = current_path_stack.pop_back()
	
	# Transition
	_spawn_layer(parent_data, Vector3.ZERO, AnimType.TUNNEL_OUT)
	
	# Removed camera reset tween, handled by _spawn_layer reset

func add_new_node():
	if current_view_data.has("children"):
		var new_node_data = {
			"name": "New Idea",
			"color": Color.from_hsv(randf(), 0.7, 0.9).to_html(),
			"children": [],
			"created_at": Time.get_unix_time_from_system(),
			"timeline_id": 0,
			"timeline_index": 9999, # Put at end
			"pos_y": 0.0
		}
		
		# Prevent Overlap in Free Mode
		if current_layout_mode == LayoutMode.FREE:
			var safe_pos = Vector2.ZERO
			var offset = 0
			var found_safe = false
			
			# Check against existing nodes
			# Simple spiral or linear offset search
			while not found_safe:
				found_safe = true
				for child_data in current_view_data["children"]:
					var cx = child_data.get("pos_x", 0.0)
					var cy = child_data.get("pos_y", 0.0)
					
					# Distance Threshold (Node width approx 2.5)
					if Vector2(cx, cy).distance_to(safe_pos) < 2.5:
						found_safe = false
						break
				
				if not found_safe:
					offset += 1
					# Spiraling out: Right, Down, Left, Up... simplified to just random or linear spread for now
					# Or just stacking right
					safe_pos.x += 2.6 
					if safe_pos.x > 10.0: # Wrap line
						safe_pos.x = 0
						safe_pos.y -= 2.6
			
			new_node_data["pos_x"] = safe_pos.x
			new_node_data["pos_y"] = safe_pos.y
		
		# If in Free Mode, try to place it near center or intelligently?
		# Grid mode will auto-arrange.
		current_view_data["children"].append(new_node_data)
		_spawn_layer(current_view_data, Vector3.ZERO) # Refresh view
		save_data()


enum AnimType { DEFAULT, TUNNEL_IN, TUNNEL_OUT }

var current_view_data: Dictionary = {}

func _process(_delta):
	# QoL: Disable Zoom if Sidebar is Open
	if ui_layer and camera:
		camera.can_zoom = not ui_layer.is_sidebar_open()

	# Continuous Drag Check
	if current_dragging_node and is_instance_valid(current_dragging_node):
		_update_drag_hover()

func _update_drag_hover():
	var dragging_pos = current_dragging_node.position
	var found_node = null
	var threshold = 1.5 # Trigger "lid open" at this distance
	
	# Check interactions with other nodes
	for other in node_root.get_children():
		if other == current_dragging_node: continue
		if other.is_in_group("header_node"): continue # Headers handled separately if needed, or same logic
		if not is_instance_valid(other): continue
		if other.is_queued_for_deletion(): continue
		if other.has_method("is_marked_for_deletion") and other.is_marked_for_deletion(): continue
		
		var dist = dragging_pos.distance_to(other.position)
		if dist < threshold:
			found_node = other
			break
	
	# Update State
	if found_node != hovered_reparent_node:
		# Exit Old
		if hovered_reparent_node and is_instance_valid(hovered_reparent_node):
			if hovered_reparent_node.has_method("hide_reparent_feedback"):
				hovered_reparent_node.hide_reparent_feedback()
		
		# Enter New
		hovered_reparent_node = found_node
		if hovered_reparent_node and is_instance_valid(hovered_reparent_node):
			if hovered_reparent_node.has_method("show_reparent_feedback"):
				hovered_reparent_node.show_reparent_feedback()
	
	# If nothing found, hovered_reparent_node becomes null (after hiding old)


func clear_selection():
	if not selected_nodes.is_empty():
		pass
	for node in selected_nodes:
		if is_instance_valid(node):
			node.set_selected(false)
	selected_nodes.clear()

func _spawn_layer(parent_data: Dictionary, center_pos: Vector3, anim_type: AnimType = AnimType.DEFAULT, focus_pos: Vector3 = Vector3.ZERO):
	clear_selection()
	current_view_data = parent_data
	
	# --- 0. PREPARE EXIT (Cleanup Old Layer) ---
	# We must do this BEFORE adding any new children to node_root
	
	# 1. Create Exit Snapshot (Tunnel Effect)
	var exit_root = Node3D.new()
	add_child(exit_root)
	
	# Move current children to exit_root
	var old_nodes = node_root.get_children()
	for child in old_nodes:
		child.reparent(exit_root)

	# --- 1. NEW BREADCRUMB HEADER ---
	# Row above the grid (Y = 5.0)
	var header_y = 5.0
	var header_spacing = 3.0
	var stack = current_path_stack + [current_view_data] # All parents including current
	
	# Calculate total width to center them
	var stack_size = stack.size()
	var start_x = -(stack_size - 1) * header_spacing * 0.5
	
	for i in range(stack_size):
		var data = stack[i]
		
		var node = MoodNodeScene.instantiate()
		node_root.add_child(node)
		node.setup(data)
		
		# Position in Header Row
		var h_x = start_x + (i * header_spacing)
		node.position = Vector3(h_x, header_y, 0)
		node.add_to_group("header_node") 
		
		# Animation Logic
		if anim_type == AnimType.TUNNEL_IN and i == stack_size - 1:
			# NEW Item (Just clicked): "Slide Up" transition
			# Start invisible, wait for old node to arrive.
			node.scale = Vector3.ZERO
			var t = create_tween()
			t.tween_property(node, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(0.6)
		else:
			# ANCESTOR (Already there) or DEFAULT (Refresh): Spawn visible immediately
			node.scale = Vector3.ONE

	# --- 2. NEW GRID CONTENT (Children) ---
	var children_data = parent_data.get("children", [])
	
	# Determine positions based on Layout Mode
	var positions = []
	match current_layout_mode:
		LayoutMode.TIMELINE:
			positions = _calculate_timeline_layout(children_data)
			_draw_timeline_visuals(children_data)
		LayoutMode.FREE:
			positions = _calculate_free_layout(children_data)
			timeline_lines_mesh.mesh.clear_surfaces() # Hide lines
	
	# Fallback/Safety: If we somehow requested GRID (via align which sets FREE), 
	# layout is handled by align function before calling spawn, or FREE handles it.
	
	for i in range(children_data.size()):
		var data = children_data[i]
		var target_pos = positions[i]
		
		var n = MoodNodeScene.instantiate()
		node_root.add_child(n)
		n.setup(data)
		n.connect("node_entered", _on_node_entered)
		n.connect("node_selected", _on_node_selected)
		n.connect("node_drag_started", _on_node_drag_started)
		n.connect("node_drag_ended", _on_node_drag_ended)
		
		n.position = target_pos
		
		# Entry Animation (Same logic as before)
		# Entry Animation (Same logic as before)
		var s_val = float(data.get("scale", 1.0))
		var target_scale = Vector3(s_val, s_val, s_val)
		
		if anim_type == AnimType.TUNNEL_IN:
			n.scale = Vector3.ZERO
			n.position.z = -50.0
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(n, "scale", target_scale, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(n, "position:z", 0.0, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		elif anim_type == AnimType.TUNNEL_OUT:
			n.scale = target_scale * 3.0
			n.position.z = 20.0 
			if n.has_method("set_label_opacity"):
				n.set_label_opacity(0.0)
				n.fade_label(1.0, 0.5)
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(n, "scale", target_scale, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
			tween.tween_property(n, "position:z", 0.0, 0.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
		else:
			n.scale = Vector3.ZERO
			var tween = create_tween()
			tween.tween_property(n, "scale", target_scale, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT).set_delay(randf() * 0.2)




		
	# Animate Exit Root
	var exit_tween = create_tween().set_parallel(true)
	
	if anim_type == AnimType.TUNNEL_IN:
		# "Column Split": User enters a node.
		# 1. Left cols fly Left. Right cols fly Right. Same col flies Random.
		# 2. Clicked node slides UP to Header.
		
		# Calculate where the new header item will be?
		# It's the last item in the NEW stack (which is stack + current).
		# We can re-calculate the position logic used in _spawn_layer breadcrumbs.
		var stack_count = current_path_stack.size() + 1
		var anim_header_spacing = 3.0
		var anim_start_x = -(stack_count - 1) * anim_header_spacing * 0.5
		var target_header_x = anim_start_x + ((stack_count - 1) * anim_header_spacing)
		var target_header_pos = Vector3(target_header_x, 5.0, 0.0) # Local to NodeRoot, but exit_root is at 0,0,0
		
		for child in exit_root.get_children():
			# HEADER PROTECTION:
			if child.is_in_group("header_node") or child.position.y > 2.0:
				# This is an old header node.
				child.queue_free()
				continue
				
			var diff_x = child.position.x - focus_pos.x
			var is_clicked = child.position.distance_to(focus_pos) < 0.1
			
			if is_clicked:
				# SLIDE UP to Header
				# Note: exit_root is fading? No, we shouldn't fade exit_root if we want this visible.
				# We will fade individual children instead.
				var t = create_tween()
				t.tween_property(child, "position", target_header_pos, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
				t.tween_property(child, "scale", Vector3.ONE, 0.6) # Maintain scale?
				# Don't fade this one!
				
			elif abs(diff_x) > 0.1: # Different Column
				var dir = Vector3.RIGHT if diff_x > 0 else Vector3.LEFT
				var target = child.position + (dir * 30.0)
				
				var t = create_tween().set_parallel(true)
				t.tween_property(child, "position", target, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
				if child.has_method("fade_label"):
					child.fade_label(0.0, 0.3)
				
			else: # Same Column (but not clicked)
				# Fly Randomly Left or Right
				var rand_side = Vector3.LEFT if randf() < 0.5 else Vector3.RIGHT
				var target = child.position + (rand_side * 30.0) # Fly further?
				
				var t = create_tween().set_parallel(true)
				t.tween_property(child, "position", target, 0.5).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
				if child.has_method("fade_label"):
					child.fade_label(0.0, 0.3)
				
		# Keep alive long enough for slide to finish (0.6s) + buffer
		exit_tween.tween_interval(0.8)
	elif anim_type == AnimType.TUNNEL_OUT:
		# "Clear Out": Parting from the middle (Moses Effect)
		# Nodes fly off to the sides to reveal the layer behind.
		for child in exit_root.get_children():
			# HEADER PROTECTION (Essential for Go Back too)
			if child.is_in_group("header_node") or child.position.y > 2.0:
				child.queue_free() # Don't fling header nodes
				continue

			var dir = Vector3.RIGHT if child.position.x >= 0 else Vector3.LEFT
			# If perfectly center (x=0), maybe alternate or go Up? Default Right.
			
			var target_pos = child.position + (dir * 35.0) # Fly way off screen
			
			child.scale = Vector3.ONE # Ensure scale is normal before flying
			
			var tween = create_tween()
			tween.set_parallel(true)
			tween.tween_property(child, "position", target_pos, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
			# Add rotation for style?
			tween.tween_property(child, "rotation:z", deg_to_rad(dir.x * 45.0), 0.6)
			
			if child.has_method("fade_label"):
				child.fade_label(0.0, 0.2)
		
		# Keep exit_root alive until children are gone
		exit_tween.tween_interval(0.7)
	else:
		# Just scale out children since modulate:a doesn't work on Node3D
		for child in exit_root.get_children():
			# HEADER PROTECTION: Don't animate old header (it overlaps with new one)
			if child.is_in_group("header_node"):
				child.queue_free()
				continue
				
			var t = create_tween()
			t.tween_property(child, "scale", Vector3.ZERO, 0.3)
		exit_tween.tween_interval(0.3)
	
	exit_tween.chain().tween_callback(exit_root.queue_free)



var last_selection_time = 0

func _on_node_selected(node, _is_multi):
	last_selection_time = Time.get_ticks_msec()
	
	if is_delete_mode:
		# Toggle "Marked" status
		if node in nodes_marked_for_deletion:
			node.set_marked_for_deletion(false)
			nodes_marked_for_deletion.erase(node)
		else:
			node.set_marked_for_deletion(true)
			nodes_marked_for_deletion.append(node)
		
		# Update UI
		if ui_layer:
			ui_layer.set_delete_mode_state(true, nodes_marked_for_deletion.size())
		return

	# Standard Selection Logic (Only if not in delete mode)
	clear_selection()
	node.set_selected(true)
	selected_nodes.append(node)
		
	if ui_layer:
		ui_layer.show_sidebar(node.node_data, node)

func _on_delete_mode_toggled(active: bool):
	if active:
		if is_delete_mode and not nodes_marked_for_deletion.is_empty():
			# If already active and has items -> This is CONFIRM
			_execute_bulk_delete()
		else:
			# Enter Mode
			is_delete_mode = true
			clear_selection() # Clear normal selection
			if ui_layer:
				ui_layer.close_sidebar()
				ui_layer.set_delete_mode_state(true, 0)
	else:
		# Cancel / Exit
		_exit_delete_mode()

func _exit_delete_mode():
	is_delete_mode = false
	# Clear marks
	for node in nodes_marked_for_deletion:
		if is_instance_valid(node):
			node.set_marked_for_deletion(false)
	nodes_marked_for_deletion.clear()
	
	if ui_layer:
		ui_layer.set_delete_mode_state(false)

func _execute_bulk_delete():
	if nodes_marked_for_deletion.is_empty():
		return
		
	if current_view_data.has("children"):
		for n in nodes_marked_for_deletion:
			if is_instance_valid(n):
				current_view_data["children"].erase(n.node_data)
				
				# Animate deletion
				var t = create_tween()
				t.tween_property(n, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		
		await get_tree().create_timer(0.25).timeout
		
		for n in nodes_marked_for_deletion:
			if is_instance_valid(n):
				n.queue_free()
		
		_normalize_timeline_ids() # Collapse gaps
		_exit_delete_mode() # Clear state
		_spawn_layer(current_view_data, Vector3.ZERO) # Refresh view
		save_data()


func _on_node_drag_started(node):
	# If dragging an unselected node, select it exclusively (unless specific UX desired)
	if node not in selected_nodes:
		clear_selection()
		node.set_selected(true)
		selected_nodes.append(node)
		
	if ui_layer:
		ui_layer.set_bin_visible(true)
		
	current_dragging_node = node # Start tracking

func _on_node_drag_ended(node):
	# Check 2D Bin intersection via UI layer
	if ui_layer and ui_layer.is_bin_hovered():
		# Identify nodes to delete
		var nodes_to_delete = []
		if node in selected_nodes:
			nodes_to_delete = selected_nodes.duplicate()
		else:
			nodes_to_delete = [node]
		
		if nodes_to_delete.is_empty():
			return

		var data_changed = false
		if current_view_data.has("children"):
			for n in nodes_to_delete:
				if is_instance_valid(n):
					current_view_data["children"].erase(n.node_data)
					
					# Animate deletion
					var t = create_tween()
					t.tween_property(n, "scale", Vector3.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
					
					# Queue free after animation (we can just let them finish but we want to refresh grid)
					# If we refresh grid immediately, they disappear.
					# Let's refresh AFTER all are gone?
			
			data_changed = true
			
			# Visual cleanup wait
			await get_tree().create_timer(0.25).timeout
			
			for n in nodes_to_delete:
				if is_instance_valid(n):
					n.queue_free()
			
			clear_selection() # Clear selection logic
			_normalize_timeline_ids() # Collapse gaps
			_spawn_layer(current_view_data, Vector3.ZERO) # Refresh view layout
			save_data()
				
	if ui_layer:
		ui_layer.set_bin_visible(false)
		
	# Check for Reparenting FIRST (Priority over placement)
	if node and is_instance_valid(node):
		if _check_reparent_drop(node):
			return # Handled by reparenting

	# Save Position Update (if free mode)
	if node:
		if current_layout_mode == LayoutMode.FREE:
			node.node_data["pos_x"] = node.position.x
			node.node_data["pos_y"] = node.position.y
			save_data()
		elif current_layout_mode == LayoutMode.TIMELINE:
			_handle_timeline_drop(node)

func _check_reparent_drop(dropped_node) -> bool:
	var drop_pos = dropped_node.global_position # Use global for safety against local offsets
	
	# 1. Check VISUAL TARGET (Sibling Reparent)
	if hovered_reparent_node and is_instance_valid(hovered_reparent_node):
		# If we are hovering a node (lid is open), any drop nearby should trigger reparenting.
		# The visual feedback (lid open) implies "Ready to accept".
		# Let's check distance to the node itself, or just trust the hover state if close enough.
		
		var dist = drop_pos.distance_to(hovered_reparent_node.global_position)
		var accept_threshold = 2.0 # More permissive threshold (Node is size 2.0 approx)
		
		if dist < accept_threshold:
			_execute_reparent_to_sibling(dropped_node, hovered_reparent_node)
			
			# Reset Visuals immediately
			hovered_reparent_node.hide_reparent_feedback()
			hovered_reparent_node = null
			current_dragging_node = null
			return true

	# 2. Check ANCESTORS (Header Nodes) - Standard proximity logic
	var header_nodes = get_tree().get_nodes_in_group("header_node")
	for header in header_nodes:
		var dist = dropped_node.position.distance_to(header.position)
		if dist < 2.0:
			_execute_reparent_to_ancestor(dropped_node, header)
			current_dragging_node = null
			return true
			
	# If no action taken, clear drag state
	if hovered_reparent_node and is_instance_valid(hovered_reparent_node):
		hovered_reparent_node.hide_reparent_feedback()
	
	hovered_reparent_node = null
	current_dragging_node = null
	return false

func _execute_reparent_to_sibling(node, target_node):
	print("Reparenting ", node.name, " into ", target_node.name)
	
	# 1. Remove from Current Data
	current_view_data["children"].erase(node.node_data)
	
	# 2. Add to Target Data
	if not target_node.node_data.has("children"):
		target_node.node_data["children"] = []
	
	# Reset position for the new layer (center it for now?)
	# Or keep relative position? Relative is hard since we don't know the new layout.
	# Resetting to 0,0 is safe.
	node.node_data["pos_x"] = 0.0
	node.node_data["pos_y"] = 0.0
	node.node_data["timeline_id"] = 0
	
	target_node.node_data["children"].append(node.node_data)
	
	# 3. Visual Feedback
	# Shrink node into target
	var t = create_tween()
	t.tween_property(node, "scale", Vector3.ZERO, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(node, "position", target_node.position, 0.3)
	
	await t.finished
	
	# 4. Refresh & Save
	if is_instance_valid(node):
		node.queue_free()
	_spawn_layer(current_view_data, Vector3.ZERO) # Refresh current view (node is gone)
	save_data()

func _execute_reparent_to_ancestor(node, target_header):
	var target_data = target_header.node_data
	
	# Prevent moving to SELF (shouldn't happen as we are inside self's child layer)
	# Prevent moving to Current Layer (Header includes current layer usually? No, stack + current)
	# Actually stack + current is what we render. 
	# If target_data == current_view_data, we are dropping on "Current Folder" header.
	# Doing nothing is fine, or maybe "Move to Top" of list?
	if target_data == current_view_data:
		return
		
	print("Moving ", node.name, " up to ", target_data.get("name", "Ancestor"))
	
	# 1. Remove from Current
	current_view_data["children"].erase(node.node_data)
	
	# 2. Add to Ancestor
	if not target_data.has("children"):
		target_data["children"] = []
		
	# Reset Pos
	node.node_data["pos_x"] = 0.0
	node.node_data["pos_y"] = 0.0
	
	target_data["children"].append(node.node_data)
	
	# 3. Visuals
	var t = create_tween()
	t.tween_property(node, "scale", Vector3.ZERO, 0.3)
	t.tween_property(node, "position", target_header.position, 0.3)
	
	await t.finished
	
	# 4. Refresh
	node.queue_free()
	_spawn_layer(current_view_data, Vector3.ZERO)
	save_data()



func _on_node_entered(node):
	_enter_node(node)

func _enter_node(node):
	var data = node.node_data
	
	# Check if this node is a FILE (Image/PDF)
	if data.has("file_path") and data["file_path"] != "":
		# OPEN FILE externally
		OS.shell_open(data["file_path"])
		return

	# QoL: Close Sidebar on Transition
	if ui_layer:
		ui_layer.close_sidebar()

	current_path_stack.append(current_view_data) 
	
	# Pass the *current* local position of the node as the focus point
	_spawn_layer(data, Vector3.ZERO, AnimType.TUNNEL_IN, node.position)
func return_to_menu():
	save_data()
	get_tree().change_scene_to_file("res://Scenes/MainMenu.tscn")

func _calculate_grid_layout(nodes_data: Array) -> Array:
	var positions = []
	var is_mobile = OS.has_feature("mobile")
	var count = nodes_data.size()
	
	var base_dim = 1
	if count <= 1: base_dim = 1
	elif count <= 4: base_dim = 2
	elif count <= 9: base_dim = 3
	elif count <= 16: base_dim = 4
	elif count <= 25: base_dim = 5
	else: base_dim = 6
	
	var layout_cols = 1
	var layout_rows = 1
	
	if is_mobile:
		layout_cols = min(3, base_dim)
	else:
		layout_rows = min(6, base_dim)

	for idx in range(count):
		var col = 0
		var row = 0
		var x_pos = 0.0
		var y_pos = 0.0
		
		if is_mobile:
			col = idx % layout_cols
			row = idx / layout_cols
			var total_w = layout_cols * GRID_SPACING_X
			var start_x = -(total_w / 2.0) + (GRID_SPACING_X / 2.0)
			x_pos = start_x + (col * GRID_SPACING_X)
			y_pos = -(row * GRID_SPACING_Y)
		else:
			row = idx % layout_rows
			col = idx / layout_rows
			var total_cols_needed = ceil(float(count) / float(layout_rows))
			var total_w = total_cols_needed * GRID_SPACING_X
			var start_x = -(total_w / 2.0) + (GRID_SPACING_X / 2.0)
			x_pos = start_x + (col * GRID_SPACING_X)
			y_pos = -(row * GRID_SPACING_Y)
		
		positions.append(Vector3(x_pos, y_pos, 0))
	return positions

func _normalize_timeline_ids():
	if not current_view_data.has("children"):
		return
		
	var children = current_view_data["children"]
	if children.is_empty():
		return
		
	# 1. Collect all unique IDs presently used
	var used_ids = []
	for child in children:
		var tid = int(child.get("timeline_id", 0))
		if tid not in used_ids:
			used_ids.append(tid)
	
	used_ids.sort()
	
	# 2. Map Old -> New (0, 1, 2...)
	var id_map = {}
	for i in range(used_ids.size()):
		id_map[used_ids[i]] = i
		
	# 3. Apply
	for child in children:
		var old_id = int(child.get("timeline_id", 0))
		if id_map.has(old_id):
			child["timeline_id"] = id_map[old_id]

func _on_spacing_changed(value):
	# Slider value 0.0 to 1.0? Or raw multiplier?
	# Let's say slider gives 0.5 to 3.0 multiplier on base 2.5 width
	# Or user provides direct width 2.5 to 10.0
	timeline_item_width = value
	
	# Refresh layout only
	_spawn_layer(current_view_data, Vector3.ZERO)

func _calculate_timeline_layout(nodes_data: Array) -> Array:
	_cached_timeline_lines.clear() # Fix: Clear old cache
	var positions = []
	var count = nodes_data.size()
	positions.resize(count)
	
	# 1. Group by Timeline ID
	var map = [] # { index: int, data: dict }
	var max_timeline_id = 0
	
	for i in range(count):
		map.append({ "index": i, "data": nodes_data[i] })
		var tid = int(nodes_data[i].get("timeline_id", 0))
		if tid > max_timeline_id:
			max_timeline_id = tid
		
	# Sort map: Primary = timeline_id, Secondary = timeline_index
	map.sort_custom(func(a, b):
		var id_a = a.data.get("timeline_id", 0)
		var id_b = b.data.get("timeline_id", 0)
		if id_a != id_b:
			return id_a < id_b 
		var idx_a = a.data.get("timeline_index", 0)
		var idx_b = b.data.get("timeline_index", 0)
		return idx_a < idx_b
	)
	
	# 2. Iterate and assign positions
	var lane_nodes = {} 
	for item in map:
		var lane = item.data.get("timeline_id", 0)
		if not lane_nodes.has(lane): lane_nodes[lane] = []
		lane_nodes[lane].append(item)
	
	# --- LAYOUT LOGIC ---
	
	var current_y_cursor = 0.0
	
	var all_lanes = lane_nodes.keys()
	all_lanes.sort()
	
	# We must iterate lanes in order 0..max_id to stack them correcty
	for lane in all_lanes:
		var items = lane_nodes[lane]
		var row_count = items.size()
		
		# Allow infinite width for all timelines
		var items_per_row = row_count 
		if items_per_row == 0: items_per_row = 1 # Safety
			
		# Calculate rows needed for this lane (Should be 1 now always)
		var lane_rows = 1
		
		# Draw items
		for i in range(row_count):
			var item = items[i]
			
			# Grid coordinate within this lane
			var col = i % items_per_row
			var row_offset = floor(i / items_per_row)
			
			# X Position
			# How many items in *this specific* row_offset?
			var is_last_row = (row_offset == lane_rows - 1)
			# Standard is items_per_row. But if last row, it's remainder.
			# BUT: If row_count is exact multiple, remainder is 0, so checked items_per_row logic.
			
			var items_in_this_row = items_per_row 
			if is_last_row:
				var rem = row_count % items_per_row
				if rem > 0: items_in_this_row = rem
			
			var row_w = items_in_this_row * timeline_item_width
			var start_x = -(row_w / 2.0) + (timeline_item_width / 2.0)
			
			var x = start_x + (col * timeline_item_width)
			var y = current_y_cursor - (row_offset * TIMELINE_LANE_HEIGHT)
			
			positions[item.index] = Vector3(x, y, 0)
			
			# CACHE VISUAL LINE (Only once per row)
			if col == 0:
				# It's the start of a row. Calculate layout for this row.
				var line_start_x = start_x - (timeline_item_width * 0.5) - 2.0
				var line_end_x = start_x + ((items_in_this_row - 1) * timeline_item_width) + (timeline_item_width * 0.5) + 2.0
				
				_cached_timeline_lines.append({
					"start": Vector3(line_start_x, y, -0.1),
					"end": Vector3(line_end_x, y, -0.1),
					"is_ghost": false
				})

		# Advance Cursor for next lane
		current_y_cursor -= (lane_rows * TIMELINE_LANE_HEIGHT)
	
	# Add Ghost Line at bottom (for potential new lane)
	var gh_y = current_y_cursor
	var gh_width = 20.0
	_cached_timeline_lines.append({
		"start": Vector3(-gh_width, gh_y, -0.1),
		"end": Vector3(gh_width, gh_y, -0.1),
		"is_ghost": true
	})
			
	return positions

func _handle_timeline_drop(node):
	var drop_y = node.position.y
	
	# 1. Analyze existing lane positions from live nodes
	var lane_y_ranges = {} # { lane_id: {min: y, max: y} }
	var max_existing_id = -1
	
	for child in node_root.get_children():
		if child == node: continue 
		if not child.get("node_data"): continue
		
		var tid = int(child.node_data.get("timeline_id", 0))
		var y = child.position.y
		
		if tid > max_existing_id: max_existing_id = tid
		
		if not lane_y_ranges.has(tid):
			lane_y_ranges[tid] = { "min": y, "max": y }
		else:
			lane_y_ranges[tid].min = min(lane_y_ranges[tid].min, y)
			lane_y_ranges[tid].max = max(lane_y_ranges[tid].max, y)
			
	var target_lane = 0
	
	if lane_y_ranges.is_empty():
		target_lane = 0
	else:
		# Use distances logic from before
		var best_lane = 0
		var min_dist = 999999.0
		var sorted_ids = lane_y_ranges.keys()
		sorted_ids.sort()
		
		for tid in sorted_ids:
			var range_vals = lane_y_ranges[tid]
			var dist = 0.0
			if drop_y > range_vals.max: dist = drop_y - range_vals.max
			elif drop_y < range_vals.min: dist = range_vals.min - drop_y
			else: dist = 0.0
			
			if dist < min_dist:
				min_dist = dist
				best_lane = tid
				
		target_lane = best_lane
		
		# New Lane Logic (Bottom)
		if best_lane == max_existing_id:
			var bottom_min = lane_y_ranges[max_existing_id].min
			if drop_y < (bottom_min - 3.5):
				target_lane = max_existing_id + 1
	
	# 2. Update Timeline ID logic
	var drop_x = node.position.x
	var nodes_in_lane = [] 
	
	for child in node_root.get_children():
		if not child.get("node_data"): continue
		
		var n_data = child.node_data
		var n_x = child.position.x
		var n_lane = int(n_data.get("timeline_id", 0))
		
		if child == node:
			nodes_in_lane.append({ "data": n_data, "x": drop_x })
			n_data["timeline_id"] = target_lane
		else:
			if n_lane == target_lane:
				nodes_in_lane.append({ "data": n_data, "x": n_x })
	
	# 3. Sort and Re-Index
	nodes_in_lane.sort_custom(func(a,b): return a.x < b.x)
	
	for i in range(nodes_in_lane.size()):
		var item = nodes_in_lane[i]
		item.data["timeline_index"] = i
		item.data["timeline_id"] = target_lane
		
	# Refresh
	_normalize_timeline_ids() 
	_spawn_layer(current_view_data, Vector3.ZERO)
	save_data()

func _calculate_free_layout(nodes_data: Array) -> Array:
	var positions = []
	for data in nodes_data:
		var x = data.get("pos_x", null)
		var y = data.get("pos_y", null)
		
		if x == null or y == null:
			positions.append(Vector3.ZERO) 
		else:
			positions.append(Vector3(x, y, 0))
			
	# Fix placeholders
	var fallback_grid = _calculate_grid_layout(nodes_data)
	for i in range(positions.size()):
		if positions[i] == Vector3.ZERO and (nodes_data[i].get("pos_x") == null):
			positions[i] = fallback_grid[i]
			
	return positions

func _on_view_mode_changed(mode_name: String):
	match mode_name:
		"FREE": current_layout_mode = LayoutMode.FREE
		"TIMELINE": current_layout_mode = LayoutMode.TIMELINE
	_spawn_layer(current_view_data, Vector3.ZERO)

var _cached_timeline_lines = []

func _draw_timeline_visuals(nodes_data: Array):
	var mesh = timeline_lines_mesh.mesh as ImmediateMesh
	mesh.clear_surfaces()
	
	if current_layout_mode != LayoutMode.TIMELINE:
		return

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	
	for line in _cached_timeline_lines:
		var color = Color(1, 1, 1, 0.2)
		if line.get("is_ghost", false):
			color = Color(1, 1, 1, 0.1)
			
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(line.start)
		mesh.surface_add_vertex(line.end)
	
	mesh.surface_end()

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_data()
		get_tree().quit()

func _on_align_grid_requested():
	# Force align to grid and SAVE those positions (essentially applying grid layout to free mode)
	var grid_pos = _calculate_grid_layout(current_view_data.get("children", []))
	var children = current_view_data.get("children", [])
	for i in range(children.size()):
		children[i]["pos_x"] = grid_pos[i].x
		children[i]["pos_y"] = grid_pos[i].y
	
	current_layout_mode = LayoutMode.FREE # Switch to Free so they stay there
	if ui_layer:
		ui_layer._set_view_mode("FREE") # Update UI to reflect we are in Free mode (but aligned)
		
	_spawn_layer(current_view_data, Vector3.ZERO)
	save_data()
