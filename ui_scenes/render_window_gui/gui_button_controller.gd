@tool
class_name PTButtonController
extends Node

""" Controls all gui button connections """

const DISABLED_COLOR = Color(160, 0, 0, 0.4)
const CHANGED_VALUE_COLOR = Color(220, 165, 0, 0.6)

var pt_window : PTRenderWindow 

# For BVHType option button
var bvh_function_names
# TODO Update this and BVHType option button when new bvh added

var _is_plugin_instance := false


func _ready():
	if Engine.is_editor_hint() and not _is_plugin_instance:
		return
	
	# Initialize bvh dropdown menu
	bvh_function_names = PTBVHTree.enum_to_dict.values()
	for i in range(bvh_function_names.size()):
		%BVHType.add_item(bvh_function_names[i].capitalize(), i)
	
	# Set default value for bvh buttons
	%UseBVHButton.button_pressed = pt_window.use_bvh
	%ShowBVHDepthButton.button_pressed = pt_window.show_bvh_depth
	
	# TODO use scene values
	%BVHTreeOrder.value = PTRendererAuto.bvh_max_children
	%BVHTreeOrder.previous_value = PTRendererAuto.bvh_max_children
	
	# Set default values for option button
	#  NOTE: Indexes should work as long as BVHType enums are positive
	#%BVHType.selected = pt_window.renderer.default_bvh
	#%BVHType.previous_value = pt_window.renderer.default_bvh
	
	# Set default values for sample buttons
	%EnableMultisampleButton.button_pressed = pt_window.enable_multisampling
	%MaxSamplePauseButton.button_pressed = pt_window.stop_rendering_on_max_samples
	
	%MaxSamplesButton.value = pt_window.max_samples
	%MaxSamplesButton.previous_value = pt_window.max_samples
	
	# NOTE: Apparently linedit focus is seperate from the spinbox, 
	#  which doesn't have focus to begin with. 
	#  Therefore we have to manually bind it.
	%MaxSamplesButton.get_line_edit().connect("focus_exited", 
			_on_max_samples_button_focus_exited)
	
	# Set defualt for camera link button
	if Engine.is_editor_hint():
		_on_link_camera_button_toggled(PTRendererAuto.is_camera_linked)
	else:
		%LinkCameraButton.visible = false
	
	# Set default for rendering disabled
	%DisableRenderButton.button_pressed = PTRendererAuto.is_rendering_disabled
	
	# TODO THINGS TO ADD:
	#	-add button to select camera angle from enum and add method to add 
	#	  new camera angle from current camera
	#	-add ability to change camera variables, fov, gamma, focal
	#	-add abilitiy to change recursive ray depth
	
	# TODO TURN labels to rich text labels with hints on hover'
	#  Also fix those labels' background being wrong in the editor 


func _on_use_bvh_button_toggled(toggled_on):
	pt_window.use_bvh = toggled_on
	
	%ShowBVHDepthButton.set_disable(not toggled_on)
	%BVHType.set_disable(not toggled_on)
	%BVHTreeOrder.set_disable(not toggled_on)
	%CreateBVHButton.set_disable(not toggled_on)


func _on_show_bvh_depth_button_toggled(toggled_on):
	pt_window.show_bvh_depth = toggled_on


func _on_create_bvh_button_pressed():
	%BVHType.previous_value = %BVHType.selected
	%BVHTreeOrder.previous_value = %BVHTreeOrder.value
	
	PTRendererAuto.create_bvh(%BVHTreeOrder.value, 
			bvh_function_names[%BVHType.selected])


func _on_enable_multisample_button_toggled(toggled_on):
	pt_window.enable_multisampling = toggled_on
	
	%MaxSamplePauseButton.set_disable(not toggled_on)
	%MaxSamplesButton.set_disable(not toggled_on)
	%ClearSamples.set_disable(not toggled_on)


func _on_max_sample_pause_button_toggled(toggled_on):
	pt_window.stop_rendering_on_max_samples = toggled_on


func _on_max_samples_button_focus_exited():
	pt_window.max_samples = %MaxSamplesButton.value
	
	%MaxSamplesButton.previous_value = %MaxSamplesButton.value


func _on_clear_samples_pressed():
	pt_window.frame = 0


func _on_disable_render_button_toggled(toggled_on):
	PTRendererAuto.is_rendering_disabled = toggled_on


func _on_link_camera_button_toggled(toggled_on):
	PTRendererAuto.is_camera_linked = toggled_on
	%LinkCameraButton.text = ("Unlink camera from editor" if toggled_on else
			"Link camera to editor")


func _on_screenshot_button_pressed():
	PTRendererAuto.take_screenshot()
