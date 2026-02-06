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
						pass
					else:
						pass
						
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
	
	$VBoxContainer/BtnTutorial.pressed.connect(_on_tutorial_pressed)
	
	# Settings Button
	var btn_settings = Button.new()
	btn_settings.text = "Settings"
	btn_settings.pressed.connect(_on_settings_pressed)
	$VBoxContainer.add_child(btn_settings)
	$VBoxContainer.move_child(btn_settings, 2) # New (0), Load (1), Settings (2), Tutorial (3)
	
	$NewBoardPopup/Panel/VBoxContainer/HBoxContainer/BtnCreate.pressed.connect(_on_create_confirm)
	$NewBoardPopup/Panel/VBoxContainer/HBoxContainer/BtnCancel.pressed.connect(func(): popup_new.hide())
	
	file_dialog.file_selected.connect(_on_file_selected)
	
	popup_new.hide()
	
	_setup_settings_panel()

# --- SETTINGS LOGIC ---
var settings_panel: Panel = null
var bg_option_btn: OptionButton = null

func _setup_settings_panel():
	settings_panel = Panel.new()
	settings_panel.visible = false
	settings_panel.custom_minimum_size = Vector2(300, 400)
	
	# Add to center of screen
	add_child(settings_panel)
	settings_panel.anchors_preset = Control.PRESET_CENTER
	# Force update layout
	settings_panel.set_anchors_preset(Control.PRESET_CENTER)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Margins
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		vbox.add_theme_constant_override(side, 20)
	settings_panel.add_child(vbox)
	
	# Title
	var lbl = Label.new()
	lbl.text = "Settings"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lbl)
	vbox.add_child(HSeparator.new())
	
	# Auto-Save Toggle
	var check = CheckBox.new()
	check.text = "Auto-Save on Unselect"
	check.button_pressed = Global.auto_save_on_unselect
	check.toggled.connect(func(pressed): 
		Global.auto_save_on_unselect = pressed
		Global.save_settings()
	)
	vbox.add_child(check)
	
	vbox.add_child(HSeparator.new())
	
	# Backgrounds
	var bg_lbl = Label.new()
	bg_lbl.text = "Background Image"
	vbox.add_child(bg_lbl)
	
	bg_option_btn = OptionButton.new()
	bg_option_btn.item_selected.connect(_on_bg_selected)
	vbox.add_child(bg_option_btn)
	
	var upload_btn = Button.new()
	upload_btn.text = "Upload Image..."
	upload_btn.pressed.connect(_on_upload_pressed)
	vbox.add_child(upload_btn)
	
	vbox.add_child(Control.new()) # Spacer?
	
	# Close
	var close_btn = Button.new()
	close_btn.text = "Close"
	close_btn.pressed.connect(func(): settings_panel.hide())
	vbox.add_child(close_btn)
	
	# Setup File Dialog for Upload
	var fd = FileDialog.new()
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = ["*.png, *.jpg, *.jpeg ; Images"]
	fd.file_selected.connect(_on_bg_uploaded)
	fd.name = "UploadDialog"
	add_child(fd)

func _on_settings_pressed():
	_refresh_bg_list()
	settings_panel.show()
	
func _refresh_bg_list():
	bg_option_btn.clear()
	var dir = DirAccess.open("res://backgrounds")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and not file_name.ends_with(".import"):
				if file_name.match("*.png") or file_name.match("*.jpg") or file_name.match("*.jpeg"):
					var full_path = "res://backgrounds/" + file_name
					bg_option_btn.add_item(file_name)
					var idx = bg_option_btn.item_count - 1
					bg_option_btn.set_item_metadata(idx, full_path)
					
					# Select if current
					if Global.selected_background == full_path:
						bg_option_btn.selected = idx
			file_name = dir.get_next()

func _on_bg_selected(index):
	var path = bg_option_btn.get_item_metadata(index)
	Global.selected_background = path
	Global.save_settings()

func _on_upload_pressed():
	var fd = get_node("UploadDialog")
	if fd: fd.popup_centered(Vector2(800, 600))

func _on_bg_uploaded(source_path):
	var file_name = source_path.get_file()
	var dest_path = "res://backgrounds/" + file_name
	
	var dir = DirAccess.open("res://")
	if not DirAccess.dir_exists_absolute("res://backgrounds"):
		dir.make_dir("backgrounds")
		
	dir = DirAccess.open("res://")
	dir.copy(source_path, dest_path)
	
	# Select it logic inside refresh?
	# Just refresh and finding it might be safe
	Global.selected_background = dest_path # Pre-set selection
	Global.save_settings()
	_refresh_bg_list()

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
