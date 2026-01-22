extends Control

@onready var popup_new = $NewBoardPopup
@onready var line_edit_name = $NewBoardPopup/Panel/VBoxContainer/NameEdit
@onready var file_dialog = $FileDialog

func _ready():
	$VBoxContainer/BtnNew.pressed.connect(_on_new_pressed)
	$VBoxContainer/BtnLoad.pressed.connect(_on_load_pressed)
	$VBoxContainer/BtnTutorial.pressed.connect(_on_tutorial_pressed)
	
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
		
	var path = "user://" + name
	Global.is_tutorial = false
	Global.current_file_path = path
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")

func _on_file_selected(path):
	Global.is_tutorial = false
	Global.current_file_path = path
	get_tree().change_scene_to_file("res://Scenes/Main.tscn")
