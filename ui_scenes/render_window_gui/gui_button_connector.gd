@tool
extends CheckBox

""" Controls all gui button connections """

@onready var parent : PTRenderWindow = get_parent()

var bvh_types_array

var _is_plugin_instance = false


func _ready():
	# TODO add control to eat focus when clicking on nothing
	
	if get_parent()._renderer:
		_is_plugin_instance = get_parent()._renderer._is_plugin_instance
	
	if not Engine.is_editor_hint() or _is_plugin_instance:
		%PanelContainer.visible = false
		
		# Set default value for buttons
		%UseBVHButton.button_pressed = parent.use_bvh
		%ShowBVHDepthButton.button_pressed = parent.show_bvh_depth
		
		# Initialize bvh dropdown menu
		bvh_types_array = PTBVHTree.BVHType.keys()
		bvh_types_array[0] += " (Default)"
		for i in range(bvh_types_array.size()):
			%BVHType.add_item(bvh_types_array[i].capitalize(), i)


func _toggled(toggled_on):
	%PanelContainer.visible = toggled_on


func _on_use_bvh_button_toggled(toggled_on):
	parent.use_bvh = toggled_on
	
	%ShowBVHDepthButton.set_disable(not toggled_on)
	%BVHType.set_disable(not toggled_on)
	%BVHTreeOrder.set_disable(not toggled_on)


func _on_show_bvh_depth_button_toggled(toggled_on):
	parent.show_bvh_depth = toggled_on


func _on_bvh_type_item_selected(index):
	# TODO add button to send bvh data from user input to create a bvh tree
	pass # Replace with function body.
