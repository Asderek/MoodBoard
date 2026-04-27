extends Camera3D

var default_distance: float = 12.0

# FPS Movement
var move_speed: float = 10.0
var mouse_sensitivity: float = 0.003
var pitch: float = 0.0
var yaw: float = 0.0

# Grabbing System
var grabbed_node: Node3D = null
var grab_distance: float = 4.0

# Hold-Click to Enter
var _left_click_target: Node3D = null
var _left_click_time: int = 0
var _is_left_holding: bool = false

func _ready():
	position = Vector3(0, 0, default_distance)
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event):
	# Escape to return to menu
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var main_script = get_node("/root/Main")
		if main_script == null:
			main_script = get_parent()
			
		if main_script and main_script.has_method("return_to_menu"):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			get_viewport().set_input_as_handled()
			main_script.return_to_menu()
			return
	
	# Left Click: Select (short) or Enter (hold)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.get_mouse_mode() != Input.MOUSE_MODE_CAPTURED:
			if event.pressed:
				Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				# Close sidebar when recapturing mouse
				var main_script = get_node("/root/Main")
				if main_script == null: main_script = get_parent()
				if main_script and main_script.ui_layer and main_script.ui_layer.has_method("close_sidebar"):
					main_script.ui_layer.close_sidebar()
					main_script.clear_selection()
				get_viewport().set_input_as_handled()
			return
		
		if event.pressed and grabbed_node != null:
			# Left click while holding a node: try reparent first, then drop
			var main_script = get_node("/root/Main")
			if main_script == null: main_script = get_parent()
			
			if main_script and main_script.has_method("execute_grab_reparent_drop"):
				if main_script.execute_grab_reparent_drop(grabbed_node):
					grabbed_node = null
					get_viewport().set_input_as_handled()
					return
			
			# No reparent target: just drop in place
			if main_script and main_script.has_method("clear_grab_reparent_hover"):
				main_script.clear_grab_reparent_hover()
			grabbed_node = null
			get_viewport().set_input_as_handled()
			return
		
		if event.pressed and grabbed_node == null:
			# Raycast from center of screen to find a node
			var space_state = get_world_3d().direct_space_state
			var query = PhysicsRayQueryParameters3D.create(global_position, global_position - global_transform.basis.z * 100.0)
			query.collide_with_areas = true
			query.collide_with_bodies = true
			
			var result = space_state.intersect_ray(query)
			if result:
				var collider = result.collider
				if collider.has_method("set_selected"):
					# Start hold timer
					_left_click_target = collider
					_left_click_time = Time.get_ticks_msec()
					_is_left_holding = true
					get_viewport().set_input_as_handled()
					return
		
		if not event.pressed and _is_left_holding:
			# Released - check hold duration
			var elapsed = Time.get_ticks_msec() - _left_click_time
			_is_left_holding = false
			
			var main_script = get_node("/root/Main")
			if main_script == null: main_script = get_parent()
			
			if elapsed >= 600:
				# Hold click: enter node
				if _left_click_target and is_instance_valid(_left_click_target):
					_left_click_target.emit_signal("node_entered", _left_click_target)
			else:
				# Short click: select node + open sidebar
				if _left_click_target and is_instance_valid(_left_click_target):
					if main_script and main_script.has_method("_on_node_selected"):
						main_script._on_node_selected(_left_click_target, false)
			
			# Hide hold indicator
			if main_script and main_script.ui_layer:
				main_script.ui_layer.hide_hold_indicator()
			
			_left_click_target = null
			get_viewport().set_input_as_handled()
			return

	# Right Click to Go Back
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		var main_script = get_node("/root/Main") # or get_parent() depending on scene tree
		if main_script == null:
			main_script = get_parent()
			
		if event.pressed:
			if main_script and main_script.has_method("_go_up_layer"):
				main_script.is_right_mouse_down = true
				main_script.right_mouse_down_time = Time.get_ticks_msec()
		else:
			if main_script and main_script.has_method("_go_up_layer"):
				main_script.is_right_mouse_down = false
				if main_script.ui_layer:
					main_script.ui_layer.hide_hold_indicator()
					
	# Mouse Wheel to move nodes closer/further
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			var scroll_dir = 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0 # UP = Further, DOWN = Closer
			var scroll_speed = 2.0
			var delta_z = scroll_dir * scroll_speed
			
			if grabbed_node:
				# Adjust grab distance for the currently held node
				grab_distance = clamp(grab_distance + delta_z, 2.0, 50.0)
				get_viewport().set_input_as_handled()
			else:
				# Try to push/pull selected nodes
				var main_script = get_node("/root/Main")
				if main_script == null: main_script = get_parent()
				
				if main_script and main_script.get("selected_nodes") and main_script.selected_nodes.size() > 0:
					var forward = -global_transform.basis.z.normalized()
					var move_vec = forward * delta_z
					
					for node in main_script.selected_nodes:
						if is_instance_valid(node):
							node.position += move_vec
							# Auto-save visually but wait for drop or explicit save for file writing
							if node.node_data:
								node.node_data["pos_x"] = node.position.x
								node.node_data["pos_y"] = node.position.y
								node.node_data["pos_z"] = node.position.z
								
					# Might want to call save_data if continuous saving is required, 
					# or let the user explicitly save. We'll let it auto-save when requested.
					get_viewport().set_input_as_handled()
			
	# 'E' to Grab / Drop
	if event is InputEventKey and event.pressed and event.keycode == KEY_E:
		_toggle_grab()

	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * mouse_sensitivity
		pitch -= event.relative.y * mouse_sensitivity
		pitch = clamp(pitch, -deg_to_rad(89), deg_to_rad(89))
		
		rotation.y = yaw
		rotation.x = pitch

func _process(delta):
	# Hold-Click Indicator (mirrors right-click hold)
	if _is_left_holding:
		var elapsed = Time.get_ticks_msec() - _left_click_time
		var progress = float(elapsed) / 600.0
		
		var main_script = get_node("/root/Main")
		if main_script == null: main_script = get_parent()
		
		# Show hold indicator at center of screen
		if main_script and main_script.ui_layer:
			var center = get_viewport().get_visible_rect().size / 2.0
			main_script.ui_layer.update_hold_indicator(center, progress)
		
		if elapsed >= 600:
			# Auto-enter on hold completion
			_is_left_holding = false
			if _left_click_target and is_instance_valid(_left_click_target):
				_left_click_target.emit_signal("node_entered", _left_click_target)
			_left_click_target = null
			if main_script and main_script.ui_layer:
				main_script.ui_layer.hide_hold_indicator()
	
	# Movement
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		var input_dir = Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_W): input_dir.z -= 1
		if Input.is_physical_key_pressed(KEY_S): input_dir.z += 1
		if Input.is_physical_key_pressed(KEY_A): input_dir.x -= 1
		if Input.is_physical_key_pressed(KEY_D): input_dir.x += 1
		if Input.is_physical_key_pressed(KEY_CTRL): input_dir.y -= 1
		if Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_E): # Wait, E is interact, use SPACE or R for up?
			pass
		if Input.is_physical_key_pressed(KEY_SPACE): input_dir.y += 1
		
		# Normalize to prevent faster diagonal movement
		input_dir = input_dir.normalized()
		
		# Move relative to looking direction
		var forward = -global_transform.basis.z.normalized()
		var right = global_transform.basis.x.normalized()
		var up = Vector3.UP
		
		# Keep forward and right flat on XZ plane if you want standard FPS movement,
		# or allow flying if you want 6DOF. Let's do 6DOF (flying) since it's a moodboard.
		var move_dir = (right * input_dir.x) + (global_transform.basis.y.normalized() * input_dir.y) + (forward * -input_dir.z)
		var speed = move_speed * (1.8 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
		position += move_dir * speed * delta

	# Update grabbed node position
	if grabbed_node and is_instance_valid(grabbed_node):
		var target_pos = global_position - global_transform.basis.z * grab_distance
		# Smooth interpolation
		grabbed_node.global_position = grabbed_node.global_position.lerp(target_pos, 15.0 * delta)
		
		# Update node's internal position data so it saves correctly
		grabbed_node.node_data["pos_x"] = grabbed_node.global_position.x
		grabbed_node.node_data["pos_y"] = grabbed_node.global_position.y
		if not grabbed_node.node_data.has("pos_z"):
			grabbed_node.node_data["pos_z"] = 0.0
		grabbed_node.node_data["pos_z"] = grabbed_node.global_position.z
		
		# Check reparent proximity
		var main_script = get_node("/root/Main")
		if main_script == null: main_script = get_parent()
		if main_script and main_script.has_method("update_grab_reparent_hover"):
			main_script.update_grab_reparent_hover(grabbed_node)

func _toggle_grab():
	if grabbed_node:
		# Drop it: try reparent first
		var main_script = get_node("/root/Main")
		if main_script == null: main_script = get_parent()
		
		if main_script and main_script.has_method("execute_grab_reparent_drop"):
			if main_script.execute_grab_reparent_drop(grabbed_node):
				grabbed_node = null
				return
		
		# No reparent: just drop
		if main_script and main_script.has_method("clear_grab_reparent_hover"):
			main_script.clear_grab_reparent_hover()
		grabbed_node = null
	else:
		# Attempt to grab
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(global_position, global_position - global_transform.basis.z * 100.0)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		
		var result = space_state.intersect_ray(query)
		if result:
			var collider = result.collider
			# Check if it's a MoodNode by duck typing
			if collider.has_method("set_selected"):
				grabbed_node = collider
				# Calculate grab distance based on how far it currently is, clamped between 2 and 10
				grab_distance = clamp(global_position.distance_to(grabbed_node.global_position), 2.0, 10.0)

# Dummy methods to prevent crash if other scripts call them
func focus_on(target_pos: Vector3, zoom_in: bool = false):
	pass
func zoom_into(target_pos: Vector3, completion_callback: Callable):
	pass
