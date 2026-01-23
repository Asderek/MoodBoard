extends Camera3D

var tween: Tween
var current_focus_point: Vector3 = Vector3.ZERO
var default_distance: float = 12.0


signal panned(relative)

func _ready():
	# Set initial position
	position = Vector3(0, 0, default_distance)

func focus_on(target_pos: Vector3, zoom_in: bool = false):
	if tween:
		tween.kill()
	tween = create_tween()
	
	var target_z = 5.0 if zoom_in else default_distance
	var new_pos = Vector3(target_pos.x, target_pos.y, target_pos.z + target_z)
	
	tween.set_parallel(true)
	tween.tween_property(self, "position", new_pos, 1.0).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "rotation", Vector3.ZERO, 1.0) 

func zoom_into(target_pos: Vector3, completion_callback: Callable):
	if tween:
		tween.kill()
	tween = create_tween()
	
	# Zoom strictly into the target
	var zoom_pos = Vector3(target_pos.x, target_pos.y, target_pos.z + 1.0)
	
	tween.tween_property(self, "position", zoom_pos, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_callback(completion_callback)

var is_dragging = false
# Base sensitivity factor. 
# 0.001 is a rough starting point for "World Units / (Pixel * Depth)"
# You might need to tweak this.
var pan_base_sensitivity = 0.002 
var zoom_sensitivity = 0.1
var min_zoom = 2.0
var max_zoom = 50.0
var can_zoom : bool = true


func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if can_zoom:
				_handle_zoom(event.position, -1) # Zoom In
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if can_zoom:
				_handle_zoom(event.position, 1)  # Zoom Out
	
	if event is InputEventMouseMotion and is_dragging:
		# Panning: Move Camera Opposite to Drag
		# Scale by depth (position.z) so it feels 1:1 with mouse
		var speed = position.z * pan_base_sensitivity
		position.x -= event.relative.x * speed
		position.y += event.relative.y * speed

func _handle_zoom(mouse_pos: Vector2, direction: int):
	# Direction: -1 (In), 1 (Out)
	
	# 1. Calculate World Point under Mouse (assume Z=0 plane)
	var plane = Plane(Vector3.BACK, 0) # Normal (0,0,1), dist 0
	var ray_origin = project_ray_origin(mouse_pos)
	var ray_normal = project_ray_normal(mouse_pos)
	var intersection = plane.intersects_ray(ray_origin, ray_normal)
	
	if intersection == null:
		return # Mouse pointing at nothing/infinite
		
	# 2. Calculate New Camera Position
	# We want to move the Camera along the line connecting [CameraPos] and [Intersection]
	# To "Zoom In", we move Camera TOWARDS Intersection.
	# To "Zoom Out", we move Camera AWAY from Intersection.
	
	var zoom_factor = 1.1 if direction > 0 else 0.9
	
	# Check Limits based on Z height
	var new_z = position.z * zoom_factor
	if new_z < min_zoom or new_z > max_zoom:
		return
		
	# Interpolate current position towards target intersection
	# NewPos = Target + (Current - Target) * Factor
	position = intersection + (position - intersection) * zoom_factor
