@tool
extends EditorPlugin

const MainPanel = preload("res://addons/path_tracer_engine/render_scene_plugin.tscn")

var main_panel_instance
var renderer

var is_docked := true
var is_main := !is_docked


func _enter_tree():
	print("EdiorPlugin entered tree")
	main_panel_instance = MainPanel.instantiate()
	main_panel_instance._is_plugin_instance = true
	
	EditorInterface.get_file_system_dock().has_focus()
	
	if is_main:
		get_editor_interface().get_editor_main_screen().add_child(main_panel_instance)
		
	if is_docked:
		add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, main_panel_instance)
	
	#renderer = %PluginRenderer
	renderer = main_panel_instance.renderer
	print(renderer)
	
	
	_make_visible(false)


func _exit_tree():
	print("EdiorPlugin exited tree")
	
	if is_docked:
		remove_control_from_docks(main_panel_instance)
	
	if main_panel_instance:
		main_panel_instance.queue_free()


func _has_main_screen():
	return is_main


func _make_visible(visible):
	if main_panel_instance:
		main_panel_instance.visible = visible
		

func _get_plugin_name():
	return "Path Tracer"


func _get_plugin_icon():
	return get_editor_interface().get_base_control().get_theme_icon("Node", "EditorIcons")
