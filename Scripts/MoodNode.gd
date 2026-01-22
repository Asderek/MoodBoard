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

var sprite: Sprite3D = null
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

# ... (Signals remain)

func setup(data: Dictionary):
	node_data = data
	var s = float(data.get("scale", 1.0))
	scale = Vector3(s, s, s)
	original_scale = scale
	update_visuals()

func update_visuals():
	var file_path = node_data.get("file_path", "")
	var has_file = file_path != ""
	
	if has_file:
		name = str(node_data.get("name", "File")).validate_node_name()
		# Hide text if it's an image, or show below?
		# Let's try to load it
		_load_file_content(file_path)
	else:
		name = str(node_data.get("name", "Node")).validate_node_name()
		label.text = str(node_data.get("name", "Node"))
		label.visible = true
		if sprite: sprite.visible = false
	
	var color_val = node_data.get("color", Color.GRAY)
	target_color = color_val if color_val is Color else Color.from_string(str(color_val), Color.GRAY)
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = target_color
	mat.roughness = 0.2
	mat.metallic = 0.1
	visual_mesh.material_override = mat
	
	# Show/Hide Background
	var show_bg = node_data.get("use_bg_color", true) # Default to true
	visual_mesh.visible = show_bg

func set_show_background(show: bool):
	node_data["use_bg_color"] = show
	visual_mesh.visible = show
	set_selected(is_selected) # Refresh selection visibility logic

func _load_file_content(path: String):
	# Create Sprite if missing
	if not sprite:
		sprite = Sprite3D.new()
		sprite.billboard = BaseMaterial3D.BILLBOARD_DISABLED # Flat on node? Or upright?
		# The node seems to be a flat box?
		# Actually Main.gd spawns them.
		# Let's assume upright for now, or match visual_mesh orientation.
		# visual_mesh is likely a box.
		sprite.pixel_size = 0.005 # Adjust scale
		add_child(sprite)
		# Position slightly in front
		sprite.position.z = 0.11 
		
	var ext = path.get_extension().to_lower()
	if ext in ["png", "jpg", "jpeg", "webp", "bmp"]:
		var img = Image.load_from_file(path)
		if img:
			var tex = ImageTexture.create_from_image(img)
			sprite.texture = tex
			sprite.visible = true
			label.visible = false # Hide text for images
			
			# Scale sprite to fit nicely within 2x2 bounds?
			# Node visual is approx 2.0 width.
			var aspect = float(img.get_width()) / float(img.get_height())
			
			# Constrain to width 1.8
			var target_w = 1.8
			# sprite width = tex_width * pixel_size
			# we want sprite_width = 1.8
			# pixel_size = 1.8 / tex_width
			
			sprite.pixel_size = target_w / float(img.get_width())
			
			# Check height constraint?
			if (img.get_height() * sprite.pixel_size) > 1.8:
				# Too tall, constrain height
				sprite.pixel_size = 1.8 / float(img.get_height())
				
		else:
			label.text = "Broken Image\n" + path.get_file()
			label.visible = true
			sprite.visible = false
	else:
		# Generic File (PDF, etc)
		label.text = "FILE:\n" + path.get_file()
		label.visible = true
		if sprite: sprite.visible = false

func _ready():
	original_scale = scale
	# Ensure label handles multi-line nicely
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	
	_create_selection_visual()
	_create_resize_handle()
	
	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	input_event.connect(_on_input_event)

var is_resizing = false
var resize_start_pos = Vector2.ZERO
var resize_start_scale = Vector3.ONE
var resize_handle: Area3D = null

func _create_resize_handle():
	# Small Cube at Bottom-Right
	resize_handle = Area3D.new()
	var coll = CollisionShape3D.new()
	var shape = BoxShape3D.new()
	shape.size = Vector3(0.4, 0.4, 0.2)
	coll.shape = shape
	resize_handle.add_child(coll)
	
	var mesh = MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = Vector3(0.4, 0.4, 0.2)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.ORANGE
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	resize_handle.add_child(mesh)
	
	add_child(resize_handle)
	
	# Position bottom-right of a 2x2 box -> x=1, y=-1
	resize_handle.position = Vector3(1.1, -1.1, 0.1)
	resize_handle.visible = false
	
	resize_handle.input_event.connect(_on_resize_input)

func _on_resize_input(camera, event, position, normal, shape_idx):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				is_resizing = true
				resize_start_pos = get_viewport().get_mouse_position()
				resize_start_scale = scale
				# Consume event so we don't drag node or deselect
				get_viewport().set_input_as_handled()
			else:
				is_resizing = false
				# Save final scale
				node_data["scale"] = scale.x

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
		# Only show selection mesh if background is enabled?
		# Or find a way to make it look better.
		# For now, hide it if bg is hidden as user requested "invisible".
		var show_bg = node_data.get("use_bg_color", true)
		selection_mesh.visible = is_selected and show_bg
		
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
	# Handle Resizing
	if is_resizing:
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var current_mouse = get_viewport().get_mouse_position()
			var diff = current_mouse.x - resize_start_pos.x
			# Sensitivity
			var scale_delta = diff * 0.01
			
			var new_s = clamp(resize_start_scale.x + scale_delta, 0.5, 5.0)
			scale = Vector3(new_s, new_s, new_s)
		else:
			is_resizing = false
			node_data["scale"] = scale.x
			original_scale = scale # Sync for animations
			save_scale_to_main()
			
	# Update Handle Visibility based on Selection
	if resize_handle:
		resize_handle.visible = is_selected
		# Inverse Scaling: Keep handle size constant on screen
		# Handle is child of Node. Node scale is (s,s,s).
		# We want Handle world scale to be ~ (1,1,1).
		# So Handle local scale should be (1/s, 1/s, 1/s).
		if scale.x > 0.001:
			var inv = 1.0 / scale.x
			resize_handle.scale = Vector3(inv, inv, inv)

	# If dragging, update position to follow mouse on plane
	if is_dragging and is_pressed:
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

func save_scale_to_main():
	# Trigger save in Main
	emit_signal("node_drag_ended", self)
