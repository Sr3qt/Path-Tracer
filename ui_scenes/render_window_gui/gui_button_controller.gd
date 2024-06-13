@tool
class_name PTButtonController
extends Node

""" Controls all gui button connections """

const DISABLED_COLOR = Color(160, 0, 0, 0.4)
const CHANGED_VALUE_COLOR = Color(220, 165, 0, 0.6)

var pt_window : PTRenderWindow

var use_bvh : PTCheckBox
var show_bvh_depth : PTCheckBox
var show_node_count : PTCheckBox
var show_object_count : PTCheckBox
var node_count_threshold : PTSpinBox
var object_count_threshold : PTSpinBox
var bvh_type : PTOptionButton
var bvh_order : PTSpinBox

var enable_multisampling : PTCheckBox
var max_samples_pause : PTCheckBox
var max_samples : PTSpinBox

var disable_rendering : PTButton
var link_camera : PTButton
var create_bvh : PTButton
var clear_samples : PTButton

# For BVHType option button
var bvh_function_names : Array[String]
# TODO Update this and BVHType option button when new bvh added

var _is_plugin_instance := false


func _ready() -> void:
	if Engine.is_editor_hint() and not _is_plugin_instance:
		return

	use_bvh = %UseBVHButton as PTCheckBox
	show_bvh_depth = %ShowBVHDepthButton as PTCheckBox
	show_node_count = %ShowNodeButton as PTCheckBox
	show_object_count = %ShowObjectButton as PTCheckBox
	node_count_threshold = %NodeCountThreshold as PTSpinBox
	object_count_threshold = %ObjectCountThreshold as PTSpinBox
	bvh_type = %BVHType as PTOptionButton
	bvh_order = %BVHTreeOrder as PTSpinBox

	enable_multisampling = %EnableMultisampleButton as PTCheckBox
	max_samples_pause = %MaxSamplePauseButton as PTCheckBox
	max_samples = %MaxSamplesButton as PTSpinBox

	disable_rendering = %DisableRenderButton as PTButton
	link_camera = %LinkCameraButton as PTButton
	create_bvh = %CreateBVHButton as PTButton
	clear_samples = %ClearSamples as PTButton

	# Initialize bvh dropdown menu
	bvh_function_names.assign(PTBVHTree.enum_to_dict.values())
	for i in range(bvh_function_names.size()):
		bvh_type.add_item(bvh_function_names[i].capitalize(), i)

	# Set default value for bvh buttons
	use_bvh.button_pressed = pt_window.use_bvh
	show_bvh_depth.button_pressed = pt_window.show_bvh_depth
	show_node_count.button_pressed = pt_window.display_node_count
	show_object_count.button_pressed = pt_window.display_object_count
	_on_show_bvh_depth_button_toggled(pt_window.show_bvh_depth)
	_on_show_node_button_toggled(pt_window.display_node_count)
	_on_show_object_button_toggled(pt_window.display_object_count)

	object_count_threshold.value = pt_window.object_display_threshold
	object_count_threshold.previous_value = pt_window.object_display_threshold

	node_count_threshold.value = pt_window.node_display_threshold
	node_count_threshold.previous_value = pt_window.node_display_threshold

	# TODO use scene values
	bvh_order.value = PTRendererAuto.bvh_order
	bvh_order.previous_value = PTRendererAuto.bvh_order

	# Set default values for option button
	#  NOTE: Indexes should work as long as BVHType enums are positive
	#%BVHType.selected = pt_window.renderer.default_bvh
	#%BVHType.previous_value = pt_window.renderer.default_bvh

	# Set default values for sample buttons
	enable_multisampling.button_pressed = pt_window.enable_multisampling
	max_samples_pause.button_pressed = pt_window.stop_rendering_on_max_samples

	max_samples.value = pt_window.max_samples
	max_samples.previous_value = pt_window.max_samples

	# Set defualt for camera link button
	if Engine.is_editor_hint():
		_on_link_camera_button_toggled(PTRendererAuto.is_camera_linked)
	else:
		link_camera.visible = false

	# Set default for rendering disabled
	disable_rendering.button_pressed = PTRendererAuto.is_rendering_disabled

	# TODO THINGS TO ADD:
	#	-add button to select camera angle from enum and add method to add
	#	  new camera angle from current camera
	#	-add ability to change camera variables, fov, gamma, focal
	#	-add abilitiy to change recursive ray depth

	# TODO TURN labels to rich text labels with hints on hover'
	#  Also fix those labels' background being wrong in the editor


func _on_use_bvh_button_toggled(toggled_on : bool) -> void:
	pt_window.use_bvh = toggled_on

	show_bvh_depth.set_disable(not toggled_on)
	bvh_type.set_disable(not toggled_on)
	bvh_order.set_disable(not toggled_on)
	create_bvh.set_disable(not toggled_on)


func _on_show_bvh_depth_button_toggled(toggled_on : bool) -> void:
	pt_window.show_bvh_depth = toggled_on

	node_count_threshold.visible = toggled_on
	object_count_threshold.visible = toggled_on
	show_node_count.visible = toggled_on
	show_object_count.visible = toggled_on
	(%ShowNodeLabel as Label).visible= toggled_on
	(%NodeCountLabel as Label).visible = toggled_on
	(%ShowObjectLabel as Label).visible = toggled_on
	(%ObjectCountLabel as Label).visible = toggled_on


func _on_create_bvh_button_pressed() -> void:
	bvh_type.previous_value = bvh_type.selected
	bvh_order.previous_value = bvh_order.value

	PTRendererAuto.create_bvh(PTRendererAuto.scene, int(bvh_order.value),
			bvh_function_names[bvh_type.selected])


func _on_enable_multisample_button_toggled(toggled_on : bool) -> void:
	pt_window.enable_multisampling = toggled_on

	max_samples_pause.set_disable(not toggled_on)
	max_samples.set_disable(not toggled_on)
	clear_samples.set_disable(not toggled_on)


func _on_max_sample_pause_button_toggled(toggled_on : bool) -> void:
	pt_window.stop_rendering_on_max_samples = toggled_on


func _on_max_samples_button_focus_exited() -> void:
	pt_window.max_samples = int(max_samples.value)

	max_samples.previous_value = max_samples.value


func _on_clear_samples_pressed() -> void:
	pt_window.frame = 0


func _on_disable_render_button_toggled(toggled_on : bool) -> void:
	PTRendererAuto.is_rendering_disabled = toggled_on


func _on_link_camera_button_toggled(toggled_on : bool) -> void:
	PTRendererAuto.is_camera_linked = toggled_on
	link_camera.text = ("Unlink camera from editor" if toggled_on else
			"Link camera to editor")


func _on_screenshot_button_pressed() -> void:
	PTRendererAuto.take_screenshot()


func _on_show_node_button_toggled(toggled_on: bool) -> void:
	pt_window.display_node_count = toggled_on

	node_count_threshold.set_disable(not toggled_on)


func _on_show_object_button_toggled(toggled_on: bool) -> void:
	pt_window.display_object_count = toggled_on

	object_count_threshold.set_disable(not toggled_on)


func _on_node_count_threshold_value_changed(value: float) -> void:
	pt_window.node_display_threshold = int(node_count_threshold.value)
	node_count_threshold.previous_value = node_count_threshold.value


func _on_object_count_threshold_value_changed(value: float) -> void:
	pt_window.object_display_threshold = int(object_count_threshold.value)
	object_count_threshold.previous_value = object_count_threshold.value
