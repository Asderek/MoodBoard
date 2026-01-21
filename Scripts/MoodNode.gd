extends Area3D

signal node_clicked(node) # Renamed to node_entered for consistency? Kept old name for now or refactor. User asked for "enter". Let's use node_entered.
signal node_entered(node)
signal node_selected(node)
signal node_hovered(node)
signal node_unhovered(node)
signal node_drag_started(node)
signal node_drag_ended(node)

@onready var visual_mesh: MeshInstance3D = $Visual
@onready var label: Label3D = $Label3D

var node_data: Dictionary = {}
var target_color: Color = Color.WHITE
var original_scale: Vector3 = Vector3.ONE

# Interaction State
var is_dragging = false
var is_pressed = false
var press_time = 0
var drag_threshold = 250 # 0.25s
var drag_plane = Plane(Vector3.BACK, 0)

func setup(data: Dictionary):
	node_data = data
	update_visuals()

func update_visuals():
	name = str(node_data.get("name", "Node")).validate_node_name()
	label.text = str(node_data.get("name", "Node"))
	
	var color_val = node_data.get("color", Color.GRAY)
	target_color = color_val if color_val is Color else Color.from_string(str(color_val), Color.GRAY)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = target_color
	mat.roughness = 0.2
	mat.metallic = 0.1
	visual_mesh.material_override = mat

func _ready():
	original_scale = scale
	# Ensure label handles multi-line nicely
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)

func set_label_opacity(alpha: float):
	label.modulate.a = alpha
	label.outline_modulate.a = alpha

func fade_label(target_alpha: float, duration: float, delay: float = 0.0):
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", target_alpha, duration).set_delay(delay)
	tween.tween_property(label, "outline_modulate:a", target_alpha, duration).set_delay(delay)

func _process(_delta):
	if is_pressed and not is_dragging:
		if Time.get_ticks_msec() - press_time > drag_threshold:
			is_dragging = true
			emit_signal("node_drag_started", self)
			# Visual feedback for drag start?
			var tween = create_tween()
			tween.tween_property(self, "scale", original_scale * 0.9, 0.1) # Shrink slightly to indicate "grabbed"

	if is_dragging:
		var camera = get_viewport().get_camera_3d()
		var mouse_pos = get_viewport().get_mouse_position()
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_normal = camera.project_ray_normal(mouse_pos)
		
		drag_plane.d = position.z
		var intersection = drag_plane.intersects_ray(ray_origin, ray_normal)
		
		if intersection:
			position = intersection

func _on_mouse_entered():
	emit_signal("node_hovered", self)
	if not is_dragging and not is_pressed:
		var tween = create_tween()
		tween.tween_property(self, "scale", original_scale * 1.25, 0.1)

func _on_mouse_exited():
	emit_signal("node_unhovered", self)
	if not is_dragging: # If dragging we might exit collider but still want to keep visual? 
		# Actually if we exit while pressed, we might lose "pressed" state if input event depends on it.
		# But usually _input is global or _input_event only local.
		# If we drag fast we exit.
		pass
		
	# Revert hover effect if not holding
	if not is_pressed:
		var tween = create_tween()
		tween.tween_property(self, "scale", original_scale, 0.1)

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_pressed = true
				press_time = Time.get_ticks_msec()
				get_viewport().set_input_as_handled() # Consume event so Main doesn't see it as "empty space" click
				if event.double_click:
					emit_signal("node_entered", self)
					is_pressed = false # Cancel drag potential
			else:
				# Released
				if is_dragging:
					is_dragging = false
					emit_signal("node_drag_ended", self)
					# Restore scale
					var tween = create_tween()
					tween.tween_property(self, "scale", original_scale * 1.25, 0.1) # Back to hover state
				else:
					# Was a click (short press)
					if is_pressed: # If we were pressed
						emit_signal("node_selected", self)
				
				is_pressed = false
