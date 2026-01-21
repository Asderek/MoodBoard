extends Camera3D

var tween: Tween
var current_focus_point: Vector3 = Vector3.ZERO
var default_distance: float = 12.0

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
	tween.tween_property(self, "rotation", Vector3.ZERO, 1.0) # Ensure we stay looking forward

func zoom_into(target_pos: Vector3, completion_callback: Callable):
	if tween:
		tween.kill()
	tween = create_tween()
	
	# Zoom strictly into the target
	var zoom_pos = Vector3(target_pos.x, target_pos.y, target_pos.z + 1.0)
	
	tween.tween_property(self, "position", zoom_pos, 0.8).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_IN)
	tween.tween_callback(completion_callback)

var is_panning = false
var pan_sensitivity = 0.02

func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = event.pressed
	
	if event is InputEventMouseMotion and is_panning:
		# "Grab and Drag" behavior
		# Drag Right (Pos X) -> Move Camera Left (Neg X)
		# Drag Down (Pos Y) -> Move Camera Up (Pos Y)
		position.x -= event.relative.x * pan_sensitivity
		position.y += event.relative.y * pan_sensitivity
