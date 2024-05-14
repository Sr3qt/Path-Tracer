@tool
extends Control

## Manages interaction between settings_buttons and PTRenderWindow.
##
## Also instantiates panel in correct position according to whether we are in
##  editor or not.

const SettingsPanel = preload("res://ui_scenes/settings_panel.tscn")
var settings_panel_instance : ScrollContainer

var pt_window : PTRenderWindow

var _is_plugin_instance := false
var _plugin_panel_node : Node # Node to attach settings panel to when in plugin


func _ready():
	if Engine.is_editor_hint() and not _is_plugin_instance:
		return

	pt_window = get_parent()

	settings_panel_instance = SettingsPanel.instantiate()
	var button_controller = settings_panel_instance.get_node("%ButtonController")
	button_controller.pt_window = pt_window
	button_controller._is_plugin_instance = true

	if not Engine.is_editor_hint():
		%PanelContainer.add_child(settings_panel_instance)
	else:
		_plugin_panel_node.add_child.call_deferred(settings_panel_instance)
		%SettingsButton.visible = false

	%PanelContainer.visible = false


func _on_settings_button_toggled(toggled_on):
	%PanelContainer.visible = toggled_on
