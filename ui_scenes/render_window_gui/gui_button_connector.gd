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

var _is_plugin_hint = false


func _ready():
	
	if get_parent()._renderer:
		_is_plugin_hint = get_parent()._renderer._is_plugin_hint
	
	if not Engine.is_editor_hint() or _is_plugin_hint:
		%PanelContainer.visible = false
		
		# Initialize bvh dropdown menu
		bvh_function_names = PTBVHTree.enum_to_dict.values()
		for i in range(bvh_function_names.size()):
			%BVHType.add_item(bvh_function_names[i].capitalize(), i)
		
		# Set default value for bvh buttons
		%UseBVHButton.button_pressed = parent.use_bvh
		%ShowBVHDepthButton.button_pressed = parent.show_bvh_depth
		
		%BVHTreeOrder.value = parent._renderer.bvh_max_children
		%BVHTreeOrder.previous_value = parent._renderer.bvh_max_children
		
		# Set default values for option button
		#  NOTE: Indexes should work as long as BVHType enums are positive
		%BVHType.selected = parent._renderer.default_bvh
		%BVHType.previous_value = parent._renderer.default_bvh
		
		# Set default values for sample buttons
		%EnableMultisampleButton.button_pressed = parent.enable_multisampling
		%MaxSamplePauseButton.button_pressed = parent.stop_rendering_on_max_samples
		
		%MaxSamplesButton.value = parent.max_samples
		%MaxSamplesButton.previous_value = parent.max_samples
		
		# TODO THINGS TO ADD:
		#	-add button to select camera angle from enum and add method to add 
		#	  new camera angle from current camera
		#	-add ability to change camera variables, fov, gamma, focal
		#	-add abilitiy to change recursive ray depth
		
		# TODO TURN labels to rich text labels with hints on hover'
		#  Also fix those labels' background being wrong in the editor 


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


func _on_enable_multisample_button_toggled(toggled_on):
	parent.enable_multisampling = toggled_on
	
	%MaxSamplePauseButton.set_disable(not toggled_on)
	%MaxSamplesButton.set_disable(not toggled_on)
	%ClearSamples.set_disable(not toggled_on)


func _on_max_sample_pause_button_toggled(toggled_on):
	parent.stop_rendering_on_max_samples = toggled_on


func _on_max_samples_button_focus_exited():
	parent.max_samples = %MaxSamplesButton.value
	
	%MaxSamplesButton.previous_value = %MaxSamplesButton.value


func _on_clear_samples_pressed():
	parent.frame = 0
