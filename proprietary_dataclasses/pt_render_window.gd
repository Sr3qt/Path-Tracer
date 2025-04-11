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
	MULTISAMPLE = 2,
	SHOW_NODE_COUNT = 4,
	SHOW_OBJECT_COUNT = 8,
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
		_set_flag_bit(RenderFlagsBits.MULTISAMPLE, value)
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

# TODO 3: Do like other pathtracer and let the user precisely define the types of
# allowed bounces on different kinds of surfaces
## The max number of extra rays that will be called when ray hits a transparent object.
## Dielectric materials tend to need more ray bounces than other materials.
## Use this for low ray depth scenes with dielectrics.
@export_range(1, 128) var max_refraction_bounces : int = 4:
	set(value):
		settings_was_changed = true
		max_refraction_bounces = value

## DEBUG CONFIGURABLE SETTINGS

@export_storage var _current_render_mode : RenderMode

## Whether a bvh tree should be used or if every object should be checked for ray hit
@export_storage var use_bvh := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.USE_BVH, value)
		settings_was_changed = true
		frame = frame if use_bvh == value else 0
		use_bvh = value

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

## How many object tests appear in bvh view before defaulting color
@export_storage var object_display_threshold := 40:
	set(value):
		render_mode_changed = true
		settings_was_changed = true
		object_display_threshold = value

## How many node tests appear in bvh view before deufaulting color
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

## GPU render flags as an int
var flags : int = 0

## Whether _current_render_mode changed this frame
var render_mode_changed := false

## Whether this window was rendered in the last renderer draw call
var was_rendered := false

## Whether any settings that affect rendering changed this frame
var settings_was_changed := false

var frame_counter : Label
var frame_time : Label

## The number of samples that have been rendered
var frame : int = 0:
	set(value):
		if frame_counter:
			frame_counter.text = "Frame: " + str(value)
		frame = value

# The seconds passed since frame 1 was rendered,
#  stopping when frame max_samples have been rendered
#  Updated by PTRenderer
var frame_times : float:
	set(value):
		if frame_time:
			frame_time.text = "Time: %.2fs" % value
		frame_times = value

## Point in time when last sample started rendering
var sample_start_time : float

## Whether all samples will be cleared this frame
var frame_reset := false


func _init(group_x := -1, group_y := -1, group_z := 1, offset_x := 0, offset_y := 0) -> void:
	_set_flags()

	if group_x >= 1:
		work_group_width = group_x
	if group_y >= 1:
		work_group_height = group_y
	work_group_depth = group_z

	x_offset = offset_x
	y_offset = offset_y


func is_defualt_view() -> bool:
	return _current_render_mode == RenderMode.DEFAULT


func is_bvh_view() -> bool:
	return _current_render_mode == RenderMode.BVH_DEPTH


func is_normal_view() -> bool:
	return _current_render_mode == RenderMode.NORMAL_VIEW


## Whether the given render mode can multisample or not.
func render_mode_can_multisample(render_mode : RenderMode) -> bool:
	return true if render_mode == RenderMode.DEFAULT else false


## Whether the render window is allowed to multisample this frame.
func can_multisample() -> bool:
	return (
		enable_multisampling and
		not render_mode_changed and
		render_mode_can_multisample(_current_render_mode) and
		(not stop_rendering_on_max_samples or frame < max_samples)
)

## Sets the given render mode to true by defualt.
## Disabling a render mode will change the render mode to DEFUALT.
func set_render_mode(render_mode : RenderMode, enable := true) -> void:
	if not enable:
		assert(render_mode != RenderMode.DEFAULT,
				"Cannot disable the defualt render mode.")
		assert(render_mode == _current_render_mode,
				"Cannot disable a render_mode that is already disabled.")

		_current_render_mode = RenderMode.DEFAULT

	elif _current_render_mode != render_mode:
		_current_render_mode = render_mode
	else:
		# Trying to enable the current active render mode should do nothing
		return

	render_mode_changed = true
	settings_was_changed = true


func get_render_mode() -> RenderMode:
	return _current_render_mode


## Requests the renderer to reset frame counter next render call.
func clear_frames() -> void:
	frame_reset = true


## Checks if frame counter should reset and resets it if it does.
func _frame_reset_check(movement : bool) -> void:
	if (
			movement
			or frame_reset
			or render_mode_changed
			or (frame >= max_samples and not stop_rendering_on_max_samples)
	):
		frame = 0
		frame_times = 0
		frame_reset = false


## Used once for _init()
func _set_flags() -> void:
	flags = (
		RenderFlagsBits.USE_BVH * int(use_bvh) +
		RenderFlagsBits.MULTISAMPLE * int(enable_multisampling) +
		RenderFlagsBits.SHOW_NODE_COUNT * int(display_node_count) +
		RenderFlagsBits.SHOW_OBJECT_COUNT * int(display_object_count)
	)

func _set_flag_bit(bit : int, boolean : bool) -> void:
	flags = (flags & ~bit) | (bit * int(boolean))


## Resets frame dependant values
func _frame_cleanup() -> void:
	render_mode_changed = false
	was_rendered = true
