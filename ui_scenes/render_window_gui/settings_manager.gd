@tool
class_name _PTSettingsManager
extends Control

## Manages interaction between settings_buttons and PTRenderWindow.
##
## Also instantiates panel in correct position according to whether we are in
##  editor or not.

const SettingsPanel = preload("res://ui_scenes/settings_panel.tscn")
var settings_panel_instance : ScrollContainer

@onready var pt_window := get_parent() as PTRenderWindow
@onready var panel_container := %PanelContainer as PanelContainer
@onready var settings_button := %SettingsButton as CheckBox

var _is_plugin_instance := false
var _plugin_panel_node : Node # Node to attach settings panel to when in plugin


func _ready() -> void:
	if Engine.is_editor_hint() and not _is_plugin_instance:
		return

	settings_panel_instance = SettingsPanel.instantiate() as ScrollContainer
	var button_controller := (
		settings_panel_instance.get_node("%ButtonController") as PTButtonController)
	button_controller.pt_window = pt_window
	button_controller._is_plugin_instance = true

	if not Engine.is_editor_hint():
		panel_container.add_child(settings_panel_instance)
	else:
		_plugin_panel_node.add_child.call_deferred(settings_panel_instance)
		settings_button.visible = false

	panel_container.visible = false


func _on_settings_button_toggled(toggled_on : bool) -> void:
	panel_container.visible = toggled_on
