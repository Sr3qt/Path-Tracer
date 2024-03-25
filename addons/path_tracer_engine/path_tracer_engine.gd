@tool
extends EditorPlugin

const MainPanel = preload("res://addons/path_tracer_engine/render_scene_plugin.tscn")

var main_panel_instance


func _enter_tree():
	print("EdiorPlugin entered tree")
	main_panel_instance = MainPanel.instantiate()
	
	
	get_editor_interface().get_editor_main_screen().add_child(main_panel_instance)
	
	_make_visible(false)


func _exit_tree():
	print("EdiorPlugin exited tree")
	if main_panel_instance:
		main_panel_instance.queue_free()


func _has_main_screen():
	return true

func _make_visible(visible):
	if main_panel_instance:
		main_panel_instance.visible = visible
		

func _get_plugin_name():
	return "Path Tracer"


func _get_plugin_icon():
	return get_editor_interface().get_base_control().get_theme_icon("Node", "EditorIcons")
