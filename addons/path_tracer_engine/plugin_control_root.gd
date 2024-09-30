@tool
class_name _PTPluginControlRoot
extends Control

var viewport : SubViewport
var editor_window : PTRenderWindow
var runtime_window : PTRenderWindow

var _is_plugin_hint := false


# TODO 2: Add button to adjust render size and aspect ratio based on editor viewport
func _ready():
	if _is_plugin_hint:
		viewport = %SubViewport as SubViewport

		var EditorRenderConfig : PackedScene = load(PTConfig.EDITOR_RENDER_CONFIG)
		var RuntimeRenderConfig : PackedScene = load(PTConfig.RUNTIME_RENDER_CONFIG)

		var camera := viewport.get_child(0) as PTCamera

		PTRendererAuto._set_plugin_camera(camera)

		# Editor panel
		editor_window = EditorRenderConfig.instantiate()
		var editor_settings := PTRenderer.WindowGui.instantiate() as _PTSettingsManager
		editor_settings.set_pt_render_window(editor_window)
		editor_settings.set_settings_manager(editor_window)

		editor_settings._is_plugin_instance = true
		editor_settings._plugin_panel_node = %SettingsPanelTarget
		editor_settings.settings_panel_name = "EditorSettings"

		PTRendererAuto.add_window(editor_window)
		viewport.get_parent().add_child(editor_settings)

		# Runtime panel
		runtime_window = RuntimeRenderConfig.instantiate()
		var runtime_settings := PTRenderer.WindowGui.instantiate() as _PTSettingsManager
		runtime_settings.set_pt_render_window(runtime_window)

		runtime_settings._is_plugin_instance = true
		runtime_settings._plugin_panel_node = %SettingsPanelTarget
		runtime_settings.settings_panel_name = "RuntimeSettings"

		viewport.get_parent().add_child(runtime_settings)
		runtime_settings.visible = false

	resized.connect(_on_resized)


func _process(_delta):
	if _is_plugin_hint:
		if editor_window.settings_was_changed:
			editor_window.settings_was_changed = false
			PTConfig.save_editor_render_config(editor_window)
		if runtime_window.settings_was_changed:
			runtime_window.settings_was_changed = false
			PTConfig.save_runtime_render_config(runtime_window)


func _on_resized():
	viewport.size.x = size.x

	if PTRendererAuto._pt_editor_camera:
		viewport.size.y = size.x / PTRendererAuto._pt_editor_camera.aspect_ratio

	else:
		# Fallback ratio if no camera exists
		viewport.size.y = size.x / (16.0 / 9.0)

	(%VBoxContainer as VBoxContainer).size = size
