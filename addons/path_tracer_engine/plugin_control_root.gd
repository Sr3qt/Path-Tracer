@tool
extends Button

var renderer : PTRenderer
var viewport : Viewport

var _is_plugin_hint := false

# TODO IN plugin move settings to space below dock
# TODO Add button to adjust render size and aspect ratio based on editor viewport
func _enter_tree():
	if _is_plugin_hint:
		renderer = %PluginRenderer
		viewport = %SubViewport
		
		renderer._is_plugin_hint = true
		renderer.root_node = self


func _ready():
	resized.connect(_on_resized)
	focus_entered.connect(_focus_entered)


func _focus_entered():
	release_focus()


func _on_resized():
	
	viewport.size.x = size.x
	
	if renderer.scene:
		if renderer.scene.camera:
			viewport.size.y = size.x / renderer.scene.camera.aspect_ratio
			return
	
	# Fallback ratio if no camera exists
	viewport.size.y = size.x / (16.0 / 9.0)
