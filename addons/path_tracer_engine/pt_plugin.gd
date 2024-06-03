@tool
extends EditorPlugin

const MainPanel := preload("res://addons/path_tracer_engine/pt_plugin_scene.tscn")
const AUTOLOAD_NAME = "PTRendererAuto"
const PLUGIN_NAME = "Path Tracer"

var main_panel_instance : _PTPluginControlRoot

var is_docked := true
var is_main := !is_docked


func _enter_tree():
	main_panel_instance = MainPanel.instantiate() as _PTPluginControlRoot
	main_panel_instance._is_plugin_hint = true

	add_autoload_singleton(AUTOLOAD_NAME, "res://proprietary_dataclasses/pt_renderer.gd")

	if is_main:
		get_editor_interface().get_editor_main_screen().add_child(main_panel_instance)

	if is_docked:
		add_control_to_dock(EditorPlugin.DOCK_SLOT_RIGHT_UL, main_panel_instance)

	connect("scene_changed", _scene_swapped)
	connect("scene_closed", _scene_closed)
	_make_visible(false)


func _exit_tree():

	if is_docked:
		remove_control_from_docks(main_panel_instance)

	if main_panel_instance:
		main_panel_instance.queue_free()

	remove_autoload_singleton(AUTOLOAD_NAME)


# NOTE: This is how you add plugin configs
#func _get_window_layout(configuration):
	#configuration.set_value(PLUGIN_NAME, "open_scenes", EditorInterface.get_open_scenes())


func _set_window_layout(configuration):
	#var temp = configuration.get_value(PLUGIN_NAME, "open_scenes", PackedStringArray([]))
	print()
	print("Loading PT plugin config (there has never been one)")
	print("Total Editor Startup Time: ", (Time.get_ticks_usec()) / 1000., " ms")
	print()
	PTRendererAuto._is_init = true


func _has_main_screen():
	return is_main


func _make_visible(visible : bool):
	if main_panel_instance:
		main_panel_instance.visible = visible


func _get_plugin_name():
	return PLUGIN_NAME


func _get_plugin_icon():
	return get_editor_interface().get_base_control().get_theme_icon("Node", "EditorIcons")


func _scene_swapped(scene_root : Node) -> void:
	PTRendererAuto._plugin_change_scene(scene_root)


func _scene_closed(file_path : String) -> void:
	PTRendererAuto._plugin_scene_closed(file_path)

