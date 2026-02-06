extends Control

@onready var popup_new = $NewBoardPopup
@onready var line_edit_name = $NewBoardPopup/Panel/VBoxContainer/NameEdit
@onready var file_dialog = $FileDialog

const SAVE_DIR_NAME = "save_files"

func _get_save_dir() -> String:
	var base_dir = OS.get_executable_path().get_base_dir()
	if OS.has_feature("editor"):
		base_dir = ProjectSettings.globalize_path("res://")
	return base_dir.path_join(SAVE_DIR_NAME)

func _process_save_files():
	var path = _get_save_dir()
	
	# Ensure Directory Exists
	if not DirAccess.dir_exists_absolute(path):
		var err = DirAccess.make_dir_absolute(path)
		if err != OK:
			print("Failed to create save_files directory: ", err)
			return
			
	# Auto-Rename .json -> .moo
	var dir = DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir():
				if file_name.ends_with(".json"):
					# perform rename
					var old_full_path = path.path_join(file_name)
					var new_name = file_name.get_basename() + ".moo"
					var new_full_path = path.path_join(new_name)
					
					var err = dir.rename(old_full_path, new_full_path)
					if err == OK:
						print("Renamed %s to %s" % [file_name, new_name])
					else:
						print("Error renaming file %s: %s" % [file_name, error_string(err)])
						
			file_name = dir.get_next()

func _ready():
	_process_save_files()
	
	# Configure FileDialog for External Access
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.current_dir = _get_save_dir()
	file_dialog.filters = ["*.moo ; MoodBoard Files"]
	
	$VBoxContainer/BtnNew.pressed.connect(_on_new_pressed)
	$VBoxContainer/BtnLoad.pressed.connect(_on_load_pressed)
	$VBoxContainer/BtnTutorial.pressed.connect(_on_tutorial_pressed)
	
	# Add Auto-Save Toggle
	var check = CheckButton.new()
	check.text = "Auto-Save on Unselect"
	check.button_pressed = Global.auto_save_on_unselect
	check.toggled.connect(func(pressed): Global.auto_save_on_unselect = pressed)
	$VBoxContainer.add_child(check)
	$VBoxContainer.move_child(check, 2) # Between Load and Tutorial? Or after all?
	# Order: New, Load, Tutorial. 
	# Let's put it after Load (Index 2). Tutorial is Index 2 usually?
	# New (0), Load (1), Tutorial (2).
	# Inserting at 2 pushes Tutorial to 3.
	
	$NewBoardPopup/Panel/VBoxContainer/HBoxContainer/BtnCreate.pressed.connect(_on_create_confirm)
	$NewBoardPopup/Panel/VBoxContainer/HBoxContainer/BtnCancel.pressed.connect(func(): popup_new.hide())
	
	file_dialog.file_selected.connect(_on_file_selected)
	
	popup_new.hide()

func _on_new_pressed():
	popup_new.show()
	line_edit_name.text = ""
	line_edit_name.grab_focus()

func _on_load_pressed():
	file_dialog.popup_centered()

func _on_tutorial_pressed():
	Global.is_tutorial = true
	Global.current_file_path = ""
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _on_create_confirm():
	var name = line_edit_name.text.strip_edges()
	if name.is_empty():
		return
		
	# Ensure .moo extension
	if not name.ends_with(".moo"):
		name += ".moo"
		
	# Use External Save Folder
	var path = _get_save_dir().path_join(name)
	Global.is_tutorial = false
	Global.current_file_path = path
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _on_file_selected(path):
	Global.is_tutorial = false
	Global.current_file_path = path
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
