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

# Reparenting Visuals
var lid_root: Node3D = null
var drop_target_root: Node3D = null
var is_reparent_open: bool = false

# Badge Visuals
var badge_root: Node3D = null
var badge_label: Label3D = null


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
	
	update_badge()

func update_badge():
	if not badge_root: return
	
	var children = node_data.get("children", [])
	var count = children.size()
	
	if count > 0:
		badge_root.visible = true
		badge_label.text = str(count)
		
		# Pulse animation if changed?
		# For now, just static updates.
	else:
		badge_root.visible = false

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
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.pixel_size = 0.002 
	label.width = 1.8 / label.pixel_size # Width is in pixels! 1.8m / 0.002 = 900px
	label.font_size = 144 # Increased by 50% (was 96)
	label.outline_size = 12
	
	_create_selection_visual()
	_create_resize_handle()
	_create_reparent_visuals()
	_create_badge_visuals()
	
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

# --- REPARENTING VISUALS ---

func _create_reparent_visuals():
	# 1. Lid Root (Pivot at Top Edge)
	lid_root = Node3D.new()
	add_child(lid_root)
	lid_root.position = Vector3(0, 1.0, 0.15) # Top edge, slightly in front
	
	# Lid Mesh (Covers the face)
	var lid_mesh = MeshInstance3D.new()
	lid_mesh.mesh = BoxMesh.new()
	lid_mesh.mesh.size = Vector3(2.0, 2.0, 0.05)
	
	# Material (Darker slightly transparent?)
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.2, 0.2, 0.8)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	lid_mesh.material_override = mat
	
	lid_root.add_child(lid_mesh)
	lid_mesh.position = Vector3(0, -1.0, 0) # Center relative to pivot is down
	
	lid_root.visible = false # Hidden by default
	
	# 2. Drop Target (Icon)
	drop_target_root = Node3D.new()
	add_child(drop_target_root)
	drop_target_root.position = Vector3(0, 0, 0.1)
	drop_target_root.scale = Vector3.ZERO # Hidden initially
	
	# Create Arrow Geometry (Cylinder + Cone? Or just a box for now)
	# Simplified "In Box" icon
	var icon_mesh = MeshInstance3D.new()
	icon_mesh.mesh = BoxMesh.new()
	icon_mesh.mesh.size = Vector3(0.8, 0.8, 0.2)
	
	var icon_mat = StandardMaterial3D.new()
	icon_mat.albedo_color = Color.GREEN
	icon_mat.emission_enabled = true
	icon_mat.emission = Color.GREEN
	icon_mat.emission_energy_multiplier = 0.5
	icon_mesh.material_override = icon_mat
	
	drop_target_root.add_child(icon_mesh)

func show_reparent_feedback():
	if is_reparent_open: return
	is_reparent_open = true
	
	lid_root.visible = true
	lid_root.rotation_degrees.x = 0
	
	var tween = create_tween().set_parallel(true)
	# Open Lid (Rotate up 110 degrees)
	tween.tween_property(lid_root, "rotation_degrees:x", 110.0, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	# Pop out Icon
	tween.tween_property(drop_target_root, "scale", Vector3.ONE, 0.4).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(drop_target_root, "position:z", 0.5, 0.4) # Move forward

func hide_reparent_feedback():
	if not is_reparent_open: return
	is_reparent_open = false
	
	var tween = create_tween().set_parallel(true)
	# Close Lid
	tween.tween_property(lid_root, "rotation_degrees:x", 0.0, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	
	# Hide Icon
	tween.tween_property(drop_target_root, "scale", Vector3.ZERO, 0.3)
	tween.tween_property(drop_target_root, "position:z", 0.1, 0.3)
	
	tween.chain().tween_callback(func(): lid_root.visible = false)

func get_drop_target_global_position() -> Vector3:
	return drop_target_root.global_position

func _create_badge_visuals():
	badge_root = Node3D.new()
	add_child(badge_root)
	# Position top-right: x=1.0, y=1.0. Move slightly out to (1.1, 1.1)
	badge_root.position = Vector3(1.1, 1.1, 0.2)
	
	# Red Sphere
	var mesh = MeshInstance3D.new()
	mesh.mesh = SphereMesh.new()
	mesh.mesh.radius = 0.25
	mesh.mesh.height = 0.5
	
	var mat = StandardMaterial3D.new()
	mat.albedo_color = Color.RED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material_override = mat
	
	badge_root.add_child(mesh)
	
	# Number
	badge_label = Label3D.new()
	badge_label.text = "0"
	badge_label.font_size = 48 # Scaled down by pixel_size?
	badge_label.pixel_size = 0.005
	badge_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	badge_label.no_depth_test = true
	badge_label.render_priority = 10 # On top
	badge_label.outline_render_priority = 9
	badge_label.modulate = Color.WHITE
	badge_label.outline_modulate = Color.WHITE # Ensure visibility
	
	badge_root.add_child(badge_label)
	badge_label.position.z = 0.26 # In front of sphere
	
	badge_root.visible = false
