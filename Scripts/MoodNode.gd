extends Area3D

signal node_clicked(node) # Renamed to node_entered for consistency? Kept old name for now or refactor. User asked for "enter". Let's use node_entered.
signal node_entered(node)
signal node_selected(node, is_multi)
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
@export var drag_threshold = 250 # 0.25s
var drag_plane = Plane(Vector3.BACK, 0)


var is_selected: bool = false
var selection_mesh: MeshInstance3D = null

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
	
	_create_selection_visual()
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)

func _create_selection_visual():
	# Create a slightly larger white mesh behind the main visual
	selection_mesh = MeshInstance3D.new()
	var mesh = BoxMesh.new()
	# Main visual is 2, 2, 0.2
	mesh.size = Vector3(2.1, 2.1, 0.15) 
	selection_mesh.mesh = mesh
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.WHITE
	mat.emission_enabled = true
	mat.emission = Color.WHITE
	mat.emission_energy_multiplier = 0.5
	selection_mesh.material_override = mat
	
	# Add as child of visual so it moves with it, but we need to be careful with scaling
	# Actually adding to self is better
	add_child(selection_mesh)
	selection_mesh.position.z = -0.1 # Slightly behind
	selection_mesh.visible = false

func set_marked_for_deletion(is_marked: bool):
	if selection_mesh:
		selection_mesh.visible = is_marked
		if is_marked:
			# Red Highlighting for Deletion
			selection_mesh.material_override.albedo_color = Color.RED
			selection_mesh.material_override.emission = Color.RED
		else:
			# Reset? For now, we only use this mesh for delete marking in this mode.
			# Or if we want to keep selection, we reset to White.
			selection_mesh.material_override.albedo_color = Color.WHITE
			selection_mesh.material_override.emission = Color.WHITE

func set_selected(selected: bool):
	is_selected = selected
	# Use standard selection visual (White) if not marked
	if selection_mesh:
		selection_mesh.visible = is_selected
		selection_mesh.material_override.albedo_color = Color.WHITE
		selection_mesh.material_override.emission = Color.WHITE

func set_label_opacity(alpha: float):
	label.modulate.a = alpha
	label.outline_modulate.a = alpha

func fade_label(target_alpha: float, duration: float, delay: float = 0.0):
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "modulate:a", target_alpha, duration).set_delay(delay)
	tween.tween_property(label, "outline_modulate:a", target_alpha, duration).set_delay(delay)

func _process(_delta):
	# If dragging, update position to follow mouse on plane
	if is_dragging:
		var camera = get_viewport().get_camera_3d()
		var mouse_pos = get_viewport().get_mouse_position()
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_normal = camera.project_ray_normal(mouse_pos)
		
		drag_plane.d = position.z
		var intersection = drag_plane.intersects_ray(ray_origin, ray_normal)
		
		if intersection:
			position = intersection

	# Check for drag start
	if is_pressed and not is_dragging:
		if Time.get_ticks_msec() - press_time > drag_threshold:
			is_dragging = true
			emit_signal("node_drag_started", self)
			# Visual feedback for drag start
			var tween = create_tween()
			tween.tween_property(self, "scale", original_scale * 0.9, 0.1)

func _on_mouse_entered():
	emit_signal("node_hovered", self)
	if not is_dragging and not is_pressed:
		var tween = create_tween()
		tween.tween_property(self, "scale", original_scale * 1.05, 0.1) # Reduced hover scale slightly

func _on_mouse_exited():
	emit_signal("node_unhovered", self)
	if not is_pressed:
		var tween = create_tween()
		tween.tween_property(self, "scale", original_scale, 0.1)

func _on_input_event(_camera, event, _position, _normal, _shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_pressed = true
				press_time = Time.get_ticks_msec()
				get_viewport().set_input_as_handled() 
				if event.double_click:
					emit_signal("node_entered", self)
					is_pressed = false 
			else:
				# Released
				if is_dragging:
					is_dragging = false
					emit_signal("node_drag_ended", self)
					var tween = create_tween()
					tween.tween_property(self, "scale", original_scale * 1.05, 0.1)
				else:
					# Clicked
					if is_pressed: 
						var is_multi = false
						# Allow Ctrl, Shift, or Command for multi-select
						if event.is_command_or_control_pressed() or event.shift_pressed:
							is_multi = true
						
						emit_signal("node_selected", self, is_multi)
				
				# Consume the release event too so Main doesn't see it (though safety guard handles it too)
				get_viewport().set_input_as_handled()
				is_pressed = false
