@tool
class_name _PTSettingsManager
extends Control

## Manages interaction between settings_buttons and PTRenderWindow.
##
## Also instantiates panel in correct position according to whether we are in
##  editor or not.

## TODO 1: Move buttons like "toggle rendering" from settingspanel to its own thing.
## THen we can remove it from editorSettings and RuntimeSettings and put it above them

const SettingsPanel = preload("res://ui_scenes/settings_panel.tscn")
var settings_panel_instance : ScrollContainer

@onready var panel_container := %PanelContainer as PanelContainer
@onready var settings_button := %SettingsButton as CheckBox
var window : PTRenderWindow
var button_controller : PTButtonController

var _is_plugin_instance := false
var _plugin_panel_node : Node # Node to attach settings panel to when in plugin
var settings_panel_name : String


func _ready() -> void:
	if Engine.is_editor_hint() and not _is_plugin_instance:
		return

	settings_panel_instance = SettingsPanel.instantiate() as ScrollContainer
	if settings_panel_name:
		settings_panel_instance.name = settings_panel_name

	button_controller = (settings_panel_instance.get_node("%ButtonController") as PTButtonController)
	button_controller.pt_window = window

	if not Engine.is_editor_hint():
		panel_container.add_child(settings_panel_instance)
	else:
		button_controller._is_plugin_instance = true
		_plugin_panel_node.add_child.call_deferred(settings_panel_instance)
		settings_button.visible = false

	panel_container.visible = false


func _on_settings_button_toggled(toggled_on : bool) -> void:
	panel_container.visible = toggled_on


func set_pt_render_window(pt_window : PTRenderWindow) -> void:
	window = pt_window
	if button_controller:
		button_controller.pt_window = window


func set_settings_manager(pt_window : PTRenderWindow) -> void:
	pt_window.frame_counter = %FrameCounter
	pt_window.frame_time = %FrameTimes

