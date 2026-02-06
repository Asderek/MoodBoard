extends Node

var current_file_path: String = ""
var is_tutorial: bool = false
var auto_save_on_unselect: bool = true

# Default to "user://" directory for new files
var default_dir: String = "user://"

func _ready():
	print("Global Singleton Initialized")
