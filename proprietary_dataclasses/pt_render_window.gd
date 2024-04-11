@tool
class_name PTRenderWindow
extends Control

"""Class for showing gui and passing render flags for a smaller portion of 
the render window"""

enum RenderFlagsBits {
	USE_BVH = 1,
	SHOW_BVH_DEPTH = 2,
	MULTISAMPLE = 4,
	SAMPLE_ALL_TEXTURES = 8,
}

var render_name := "unnamed_window"

# Defualt render flags
var flags := 0

## GPU RENDER FLAGS
## Flags that are sent to the gpu

# Whether a bvh tree should be used or 
#  if every object should be checked for ray hit
var use_bvh := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.USE_BVH, int(value))
		use_bvh = value

# If a bvh heat map of of most expensive traversals are shown
#  Also disables multisampling while on
var show_bvh_depth := false:
	set(value):
		_set_flag_bit(RenderFlagsBits.SHOW_BVH_DEPTH, int(value))
		_disable_multisample = value
		_multisample = not value and enable_multisampling and not _disable_multisample
		render_mode_changed = true
		show_bvh_depth = value

# Whether the shader will sample from previous draw call or not
var _multisample := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.MULTISAMPLE, int(value))
		_multisample = value

# TODO Ponder over overall usefulness
# Whether every object who is hit should sample their texture or not
var sample_all_textures := false:
	set(value):
		_set_flag_bit(RenderFlagsBits.SAMPLE_ALL_TEXTURES, int(value))
		render_mode_changed = true
		sample_all_textures = value

## OTHER RENDER FLAGS
## Flags that dont go to the gpu

# Whether multisampling is enabled by the user or not
var enable_multisampling := true:
	set(value):
		_multisample = not value and enable_multisampling and not _disable_multisample
		enable_multisampling = value

# Updated whenever the camera or an object is moved
var scene_changed = false:
	set(value):
		_multisample = not value and enable_multisampling and not _disable_multisample
		scene_changed = value

# If rendering should stop when frame is larger than max_samples
var stop_rendering_on_max_samples := true

var max_samples : int = 16

# The number of samples that will be rendered this frame
#  possible values: frame -> [0, max_samples)
var frame : int = 0

# Whether any flags that control *what* is rendered i.e. show_bvh_depth 
var render_mode_changed := false

# An override for various render modes that cannot utilize multisampling
var _disable_multisample := false

## OTHER STUFF
# How many pixels are in a work group dimension
var work_group_width_pixels = PTRenderer.compute_invocation_width
var work_group_height_pixels = PTRenderer.compute_invocation_height
var work_group_depth_pixels = PTRenderer.compute_invocation_depth

# work_group_height and width are used for size calculations.
#  depth is passed to work dispatcher, but no support for depth > 1 exist yet
var work_group_width : int
var work_group_height : int
var work_group_depth := 1

var x_offset := 0
var y_offset := 0

var _renderer : PTRenderer


func _init(group_x := 1, group_y := 1, group_z := 1, offset_x := 0, offset_y := 0):
	# TODO add safeguards for running in editor
	_set_flags()
	
	custom_minimum_size = Vector2(work_group_width_pixels, work_group_height_pixels)
	
	work_group_width = group_x
	work_group_height = group_y
	work_group_depth = group_z
	
	var new_size = Vector2(group_x * work_group_width_pixels, 
						   group_y * work_group_height_pixels)
	set_size(new_size)
	
	x_offset = offset_x
	y_offset = offset_y
	
	set_position(Vector2(x_offset, y_offset))


func flags_to_byte_array():
	var flag_array = PackedInt32Array([flags])
	return flag_array.to_byte_array()


func _set_flags():
	"""Used once for init"""
	flags = (
		RenderFlagsBits.USE_BVH * int(use_bvh) +
		RenderFlagsBits.SHOW_BVH_DEPTH * int(show_bvh_depth) +
		RenderFlagsBits.MULTISAMPLE * int(_multisample) +
		RenderFlagsBits.SAMPLE_ALL_TEXTURES * int(sample_all_textures)
	)

func _set_flag_bit(bit, boolean : bool):
	# Shamlessly stolen from:
	# https://stackoverflow.com/questions/47981/how-to-set-clear-and-toggle-a-single-bit
	flags = (flags & ~bit) | (bit * int(boolean))

