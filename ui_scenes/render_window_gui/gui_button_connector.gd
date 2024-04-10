@tool
class_name PTButtonController
extends CheckBox

""" Controls all gui button connections """

const DISABLED_COLOR = Color(160, 0, 0, 0.4)
const CHANGED_VALUE_COLOR = Color(220, 165, 0, 0.6)

@onready var parent : PTRenderWindow = get_parent()

# For BVHType option button
var bvh_function_names
# TODO Update this and BVHType option button when new bvh added

var _is_plugin_instance = false


func _ready():
	# TODO add button to select camera angle from enum and add method to add 
	#  new camera angle from current camera
	
	if get_parent()._renderer:
		_is_plugin_instance = get_parent()._renderer._is_plugin_instance
	
	if not Engine.is_editor_hint() or _is_plugin_instance:
		%PanelContainer.visible = false
		
		# Initialize bvh dropdown menu
		bvh_function_names = PTBVHTree.enum_to_dict.values()
		for i in range(bvh_function_names.size()):
			%BVHType.add_item(bvh_function_names[i].capitalize(), i)
		
		# Set default value for buttons
		%UseBVHButton.button_pressed = parent.use_bvh
		%ShowBVHDepthButton.button_pressed = parent.show_bvh_depth
		
		%BVHTreeOrder.value = parent._renderer.bvh_max_children
		%BVHTreeOrder.previous_value = parent._renderer.bvh_max_children
		
		# Set default values for option button
		#  NOTE: Indexes should work as long as BVHType enums are positive
		%BVHType.selected = parent._renderer.default_bvh
		%BVHType.previous_value = parent._renderer.default_bvh
		

func _toggled(toggled_on):
	%PanelContainer.visible = toggled_on


func _on_use_bvh_button_toggled(toggled_on):
	parent.use_bvh = toggled_on
	
	%ShowBVHDepthButton.set_disable(not toggled_on)
	%BVHType.set_disable(not toggled_on)
	%BVHTreeOrder.set_disable(not toggled_on)
	%CreateBVHButton.set_disable(not toggled_on)


func _on_show_bvh_depth_button_toggled(toggled_on):
	parent.show_bvh_depth = toggled_on


func _on_create_bvh_button_pressed():
	%BVHType.previous_value = %BVHType.selected
	%BVHTreeOrder.previous_value = %BVHTreeOrder.value
	
	parent._renderer.create_bvh(%BVHTreeOrder.value, bvh_function_names[%BVHType.selected])
	
