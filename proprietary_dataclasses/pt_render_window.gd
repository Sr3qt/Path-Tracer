@tool
class_name PTRenderWindow
extends Node

## Class for showing gui and passing render flags for a portion of the render window
## TODO 3: Consider renaming to PTRenderSettings
## TODO 3: Maybe they should have their own render texture each.
## TODO 3: Make a PTRenderWindow selection system, look at WorldEnvironment for inspiration


# How many pixels are in a work group dimension
const INVOCATION_WIDTH := PTRenderer.compute_invocation_width
const INVOCATION_HEIGHT := PTRenderer.compute_invocation_height
const INVOCATION_DEPTH := PTRenderer.compute_invocation_depth

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

## 	NODE CONFIGURABLE SETTINGS

## How many pixels to render horizontally
@export var render_width := 1920:
	set(value):
		settings_was_changed = true
		render_width = value

## How many pixels to render vertically
@export var render_height := 1080:
	set(value):
		settings_was_changed = true
		render_height = value

## Whether multisampling is enabled or not.
## Does not guarantee multisampling in all cases.
@export var enable_multisampling := true:
	set(value):
		_multisample = not value and can_multisample()
		settings_was_changed = true
		enable_multisampling = value

## If rendering should stop or reset when max_samples have been reached.
@export var stop_rendering_on_max_samples := true:
	set(value):
		settings_was_changed = true
		stop_rendering_on_max_samples = value

## How many samples should be taken before stopping or restarting.
@export var max_samples : int = 16:
	set(value):
		settings_was_changed = true
		max_samples = value

## The max numver of rays that will be called recursively.
## Equal to number of ray bounces + 1
@export_range(1, 128) var max_ray_depth : int = 1:
	set(value):
		settings_was_changed = true
		max_ray_depth = value

## The max number of extra rays that will be called when ray hits a transparent object.
## Dielectric materials tend to need more ray bounces than other materials.
## Use this for low ray depth scenes with dielectrics.
@export_range(1, 128) var max_refraction_bounces : int = 2:
	set(value):
		settings_was_changed = true
		max_refraction_bounces = value

## DEBUG CONFIGURABLE SETTINGS

## Whether a bvh tree should be used or if every object should be checked for ray hit
@export_storage var use_bvh := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.USE_BVH, value)
		settings_was_changed = true
		frame = frame if use_bvh == value else 0
		use_bvh = value

@export_storage var show_normal_view := false

# If a bvh heat map of of most expensive traversals are shown
#  Also disables multisampling while on
@export_storage var show_bvh_depth := false

@export_storage var display_node_count := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.SHOW_NODE_COUNT, value)
		render_mode_changed = true
		settings_was_changed = true
		display_node_count = value

@export_storage var display_object_count := false:
	set(value):
		_set_flag_bit(RenderFlagsBits.SHOW_OBJECT_COUNT, value)
		render_mode_changed = true
		settings_was_changed = true
		display_object_count = value

## How many object tests appear in show_bvh_depth before deufaulting color
@export_storage var object_display_threshold := 40:
	set(value):
		render_mode_changed = true
		settings_was_changed = true
		object_display_threshold = value

## How many node tests appear in show_bvh_depth before deufaulting color
@export_storage var node_display_threshold := 50:
	set(value):
		render_mode_changed = true
		settings_was_changed = true
		node_display_threshold = value

# work_group_height and width are used for size calculations.
#  depth is passed to work dispatcher, but no support for depth != 1 exist yet
@export_storage var work_group_width : int = render_width / INVOCATION_WIDTH:
	set(value):
		settings_was_changed = true
		work_group_width = value
@export_storage var work_group_height : int = render_height / INVOCATION_HEIGHT:
	set(value):
		settings_was_changed = true
		work_group_height = value
var work_group_depth := 1

@export_storage var x_offset := 0:
	set(value):
		settings_was_changed = true
		x_offset = value
@export_storage var y_offset := 0:
	set(value):
		settings_was_changed = true
		y_offset = value

# GPU render flags as an int
var flags : int = 0

# Whether the shader will sample from previous draw call or not
var _multisample := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.MULTISAMPLE, value)
		_multisample = value

# A disable override for render modes that cannot utilize multisampling
var _disable_multisample := false

# Updated whenever the camera or an object is moved
var scene_changed := false:
	set(value):
		_multisample = not value and can_multisample()
		scene_changed = value

var _current_render_mode : RenderMode

# Whether any flags that control *what* is rendered i.e. show_bvh_depth
var render_mode_changed := false

# Whether this window was rendered in the last renderer draw call
var was_rendered := false

## Whether any settings that affect rendering changed this frame
var settings_was_changed := false

var frame_counter : Label
var frame_time : Label

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


func _init(group_x := -1, group_y := -1, group_z := 1, offset_x := 0, offset_y := 0) -> void:
	_set_flags()

	if group_x >= 1:
		work_group_width = group_x
	if group_y >= 1:
		work_group_height = group_y
	work_group_depth = group_z

	x_offset = offset_x
	y_offset = offset_y


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
	settings_was_changed = true


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
	settings_was_changed = true
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

