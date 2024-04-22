@tool
extends Button

var renderer : PTRenderer
var viewport : Viewport

var _is_plugin_hint := false


func _enter_tree():
	if _is_plugin_hint:
		renderer = %PluginRenderer
		viewport = %SubViewport
		
		renderer._is_plugin_hint = true
		renderer.root_node = self


func _ready():
	mouse_exited.connect(_on_root_node_mouse_exited)
	mouse_entered.connect(_on_root_node_mouse_entered)
	resized.connect(_on_resized)
	focus_entered.connect(_focus_entered)


func _pressed():
	if renderer.scene:
		if renderer.scene.camera:
			renderer.scene.camera.freeze = false


func _focus_entered():
	release_focus()


func _on_root_node_mouse_exited():
	if renderer.scene:
		if renderer.scene.camera:
			renderer.scene.camera.freeze = true
	renderer._mouse_hover_window = false


func _on_root_node_mouse_entered():
	renderer._mouse_hover_window = true


func _on_resized():
	
	viewport.size.x = size.x
	
	if renderer.scene:
		if renderer.scene.camera:
			viewport.size.y = size.x / renderer.scene.camera.aspect_ratio
			return
	
	# Fallback ratio if no camera exists
	viewport.size.y = size.x / (16.0 / 9.0)
