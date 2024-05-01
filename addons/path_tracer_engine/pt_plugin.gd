@tool
extends EditorPlugin

const MainPanel = preload("res://addons/path_tracer_engine/pt_plugin_scene.tscn")
const AUTOLOAD_NAME = "PTRendererAuto"

var main_panel_instance

var is_docked := true
var is_main := !is_docked


func _enter_tree():
	main_panel_instance = MainPanel.instantiate()
	main_panel_instance._is_plugin_hint = true
	
	add_autoload_singleton(AUTOLOAD_NAME, "res://proprietary_dataclasses/pt_renderer.gd")
	
	if is_main:
		get_editor_interface().get_editor_main_screen().add_child(main_panel_instance)
		
	if is_docked:
		add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, main_panel_instance)
	
	connect("scene_changed", _scene_swapped)
	_make_visible(false)


func _exit_tree():
	
	if is_docked:
		remove_control_from_docks(main_panel_instance)
	
	if main_panel_instance:
		main_panel_instance.queue_free()
	
	remove_autoload_singleton(AUTOLOAD_NAME)


func _has_main_screen():
	return is_main


func _make_visible(visible):
	if main_panel_instance:
		main_panel_instance.visible = visible
		

func _get_plugin_name():
	return "Path Tracer"


func _get_plugin_icon():
	return get_editor_interface().get_base_control().get_theme_icon("Node", "EditorIcons")


func _scene_swapped(scene_root):
	PTRendererAuto._plugin_change_scene(scene_root)

