extends Node

var current_file_path: String = ""
var is_tutorial: bool = false
var auto_save_on_unselect: bool = true

# Default to "user://" directory for new files
var default_dir: String = "user://"
var selected_background: String = "" # Path to background texture

const SETTINGS_PATH = "user://settings.json"

func _ready():
	load_settings()

func save_settings():
	var data = {
		"selected_background": selected_background,
		"auto_save_on_unselect": auto_save_on_unselect
	}
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(data))

func load_settings():
	if not FileAccess.file_exists(SETTINGS_PATH):
		return
		
	var file = FileAccess.open(SETTINGS_PATH, FileAccess.READ)
	if file:
		var json = JSON.new()
		var error = json.parse(file.get_as_text())
		if error == OK:
			var data = json.data
			selected_background = data.get("selected_background", "")
			auto_save_on_unselect = data.get("auto_save_on_unselect", true)
			# print("Settings Loaded. BG: ", selected_background)
		else:
			pass # print("Error parsing settings: ", json.get_error_message())
