@tool
extends Button

var renderer : PTRenderer
var viewport : Viewport

var _is_plugin_instance := false


func _enter_tree():
	if _is_plugin_instance:
		renderer = %PluginRenderer
		viewport = %SubViewport
		
		renderer._is_plugin_instance = true
		renderer.root_node = self


func _ready():
	mouse_exited.connect(_on_root_node_mouse_exited)
	mouse_entered.connect(_on_root_node_mouse_entered)
	resized.connect(_on_resized)


func _pressed():
	if renderer.scene:
		if renderer.scene.camera:
			renderer.scene.camera.freeze = false


func _on_root_node_mouse_exited():
	if renderer.scene:
		if renderer.scene.camera:
			renderer.scene.camera.freeze = true
	renderer._mouse_hover_window = false


func _on_root_node_mouse_entered():
	renderer._mouse_hover_window = true


func _on_resized():
	
	viewport.size.x = size.x
	
	viewport.size.y = size.x / renderer.scene.camera.aspect_ratio
