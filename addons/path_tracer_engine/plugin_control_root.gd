@tool
class_name _PTPluginControlRoot
extends Control

var viewport : SubViewport

var _is_plugin_hint := false

# TODO 2: Add button to adjust render size and aspect ratio based on editor viewport
func _ready():
	if _is_plugin_hint:
		viewport = %SubViewport as SubViewport

		var camera := viewport.get_child(0) as PTCamera

		PTRendererAuto._set_plugin_camera(camera)

		var x := ceili(1920. / 8.)
		var y := ceili(1080. / 8.)

		var better_window := PTRendererAuto.WindowGui.instantiate() as PTRenderWindow

		var settings_manager := (
			better_window.get_node("SettingsManager") as _PTSettingsManager)

		settings_manager._is_plugin_instance = true
		settings_manager._plugin_panel_node = %VBoxContainer

		better_window.work_group_width = x
		better_window.work_group_height = y

		PTRendererAuto.add_window(better_window)
		viewport.get_parent().add_child(better_window)

	resized.connect(_on_resized)


func _on_resized():
	viewport.size.x = size.x

	if PTRendererAuto._pt_editor_camera:
		viewport.size.y = size.x / PTRendererAuto._pt_editor_camera.aspect_ratio

	else:
		# Fallback ratio if no camera exists
		viewport.size.y = size.x / (16.0 / 9.0)

	(%VBoxContainer as VBoxContainer).size = size
