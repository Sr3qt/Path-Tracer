@tool
class_name PTRenderWindow
extends Control

"""Class for showing gui and passing render flags for a portion of
the render window"""

enum RenderFlagsBits {
	USE_BVH = 1,
	SHOW_BVH_DEPTH = 2,
	MULTISAMPLE = 4,
	SHOW_NODE_COUNT = 8,
	SHOW_OBJECT_COUNT = 16,
	SHOW_NORMAL_VIEW = 32
}

enum RenderMode {
	DEFAULT,
	BVH_DEPTH,
	NORMAL_VIEW,
}

## GPU RENDER FLAGS
## Flags that are sent to the gpu

# GPU render flags as an int
var flags : int = 0

# Whether a bvh tree should be used or
#  if every object should be checked for ray hit
var use_bvh := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.USE_BVH, value)
		frame = frame if use_bvh == value else 0
		use_bvh = value

# If a bvh heat map of of most expensive traversals are shown
#  Also disables multisampling while on
var show_bvh_depth := false

var display_node_count := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.SHOW_NODE_COUNT, value)
		render_mode_changed = true
		display_node_count = value

var display_object_count := false:
	set(value):
		_set_flag_bit(RenderFlagsBits.SHOW_OBJECT_COUNT, value)
		render_mode_changed = true
		display_object_count = value

## How many object tests appear in show_bvh_depth before deufaulting color
var object_display_threshold := 40:
	set(value):
		render_mode_changed = true
		object_display_threshold = value

## How many node tests appear in show_bvh_depth before deufaulting color
var node_display_threshold := 50:
	set(value):
		render_mode_changed = true
		node_display_threshold = value

# Whether the shader will sample from previous draw call or not
var _multisample := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.MULTISAMPLE, value)
		_multisample = value

# TODO 0: FIX Flicker when enabled in editor
var show_normal_view := false

var _current_render_mode : RenderMode

## OTHER RENDER FLAGS
## Flags that dont go to the gpu

# Whether multisampling is enabled by the user or not
var enable_multisampling := true:
	set(value):
		_multisample = not value and can_multisample()
		enable_multisampling = value

# Updated whenever the camera or an object is moved
var scene_changed := false:
	set(value):
		_multisample = not value and can_multisample()
		scene_changed = value

# If rendering should stop when frame is larger than max_samples
var stop_rendering_on_max_samples := true

# Whether any flags that control *what* is rendered i.e. show_bvh_depth
var render_mode_changed := false

# A disable override for render modes that cannot utilize multisampling
var _disable_multisample := false

# Whether this window was rendered in the last renderer draw call
var was_rendered := false

## SAMPLE VALUES
var max_samples : int = 16

@onready var frame_counter : Label = %FrameCounter
@onready var frame_time : Label = %FrameTimes


# The numbered sample that will be rendered this frame
#  possible values: frame -> [0, max_samples)
var frame : int = 0:
	set(value):
		if frame_counter:
			frame_counter.text = "Frame: " + str(value)
		frame = value

# The seconds passed since frame 0 was rendered,
#  stopping when frame max_samples have been rendered
#  Updated by PTRenderer
var frame_times : float:
	set(value):
		if frame_time:
			frame_time.text = "Time: %.2fs" % value
		frame_times = value

var max_sample_start_time : float # Point in time when rendering started

## OTHER STUFF

var render_name := "unnamed_window"

# How many pixels are in a work group dimension
var work_group_width_pixels := PTRenderer.compute_invocation_width
var work_group_height_pixels := PTRenderer.compute_invocation_height
var work_group_depth_pixels := PTRenderer.compute_invocation_depth

# work_group_height and width are used for size calculations.
#  depth is passed to work dispatcher, but no support for depth > 1 exist yet
var work_group_width : int
var work_group_height : int
var work_group_depth := 1

var x_offset := 0
var y_offset := 0



func _init(group_x := 1, group_y := 1, group_z := 1, offset_x := 0, offset_y := 0) -> void:
	_set_flags()

	custom_minimum_size = Vector2(work_group_width_pixels, work_group_height_pixels)

	work_group_width = group_x
	work_group_height = group_y
	work_group_depth = group_z

	var new_size := Vector2(group_x * work_group_width_pixels,
						   group_y * work_group_height_pixels)
	set_size(new_size)

	x_offset = offset_x
	y_offset = offset_y

	set_position(Vector2(x_offset, y_offset))


func can_multisample() -> bool:
	return enable_multisampling and not _disable_multisample


## Sets the given render mode to true or false.
## Only one render mode can be true at the same time.
## Disabling a render mode will change the render mode to DEFUALT.
func set_render_mode(render_mode : RenderMode, enable : bool) -> void:
	if not enable:
		_disable_render_mode(render_mode)
		return

	# Trying to enable the current active render mode
	if _current_render_mode == render_mode:
		return

	if _current_render_mode != RenderMode.DEFAULT:
		_disable_render_mode(_current_render_mode)

	_current_render_mode = render_mode

	match render_mode:
		RenderMode.DEFAULT:
			return

		RenderMode.BVH_DEPTH:
			_set_flag_bit(RenderFlagsBits.SHOW_BVH_DEPTH, true)
			show_bvh_depth = true

		RenderMode.NORMAL_VIEW:
			_set_flag_bit(RenderFlagsBits.SHOW_NORMAL_VIEW, true)
			show_normal_view = false

	_disable_multisample = true
	_multisample = can_multisample()
	render_mode_changed = true


func get_render_mode() -> RenderMode:
	return _current_render_mode


func _disable_render_mode(render_mode : RenderMode) -> void:
	assert(render_mode != RenderMode.DEFAULT,
		"Cannot disable the defualt render mode.")

	if _current_render_mode != render_mode:
		return

	_current_render_mode = RenderMode.DEFAULT

	match render_mode:
		RenderMode.DEFAULT:
			return

		RenderMode.BVH_DEPTH:
			_set_flag_bit(RenderFlagsBits.SHOW_BVH_DEPTH, false)
			show_bvh_depth = false

		RenderMode.NORMAL_VIEW:
			_set_flag_bit(RenderFlagsBits.SHOW_NORMAL_VIEW, false)
			show_normal_view = false

	_disable_multisample = false
	_multisample = can_multisample()
	render_mode_changed = true
	frame = 0

func flags_to_byte_array() -> PackedByteArray:
	return PackedInt32Array([flags]).to_byte_array()


func _set_flags() -> void:
	"""Used once for init"""
	flags = (
		RenderFlagsBits.USE_BVH * int(use_bvh) +
		RenderFlagsBits.SHOW_BVH_DEPTH * int(show_bvh_depth) +
		RenderFlagsBits.MULTISAMPLE * int(_multisample) +
		RenderFlagsBits.SHOW_NODE_COUNT * int(display_node_count) +
		RenderFlagsBits.SHOW_OBJECT_COUNT * int(display_object_count) +
		RenderFlagsBits.SHOW_NORMAL_VIEW * int(show_normal_view)
	)

func _set_flag_bit(bit : int, boolean : bool) -> void:
	# Shamlessly stolen from:
	# https://stackoverflow.com/questions/47981/how-to-set-clear-and-toggle-a-single-bit
	flags = (flags & ~bit) | (bit * int(boolean))

