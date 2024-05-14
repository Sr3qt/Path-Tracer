@tool
extends Control

var viewport : SubViewport

var _is_plugin_hint := false

# TODO Add button to adjust render size and aspect ratio based on editor viewport
func _enter_tree():
	if _is_plugin_hint:
		viewport = %SubViewport

		var camera : PTCamera = viewport.get_child(0)

		PTRendererAuto._set_plugin_camera(camera)

		var x := ceili(1920. / 8.)
		var y := ceili(1080. / 8.)

		var better_window : PTRenderWindow = PTRendererAuto.WindowGui.instantiate()

		better_window.get_node("SettingsManager")._is_plugin_instance = true
		better_window.get_node("SettingsManager")._plugin_panel_node = get_child(0)

		better_window.work_group_width = x
		better_window.work_group_height = y

		PTRendererAuto.add_window(better_window)
		viewport.get_parent().add_child(better_window)


func _ready():
	resized.connect(_on_resized)


func _on_resized():
	viewport.size.x = size.x

	if PTRendererAuto._pt_editor_camera:
		viewport.size.y = size.x / PTRendererAuto._pt_editor_camera.aspect_ratio

	else:
		# Fallback ratio if no camera exists
		viewport.size.y = size.x / (16.0 / 9.0)

	$VBoxContainer.size = size
