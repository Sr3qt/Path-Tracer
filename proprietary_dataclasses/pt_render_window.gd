@tool
class_name PTRenderWindow
extends Control

"""Class for showing gui and passing render flags for a smaller portion of 
the render window"""

enum RenderFlagsBits {
	USE_BVH = 1,
	SHOW_BVH_DEPTH = 2,
	#USE_MULTISAMPLING = 4,
	SCENE_CHANGED = 4,
	
	SAMPLE_ALL_TEXTURES = 8,
}

var render_name := "unnamed_window"

# Defualt render flags
var flags := 0

# Whether a bvh tree should be used or 
#  if every object should be checked for ray hit
var use_bvh := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.USE_BVH, int(value))
		use_bvh = value

# If a bvh heat map of of most expensive traversals are shown
var show_bvh_depth := false:
	set(value):
		_set_flag_bit(RenderFlagsBits.SHOW_BVH_DEPTH, int(value))
		show_bvh_depth = value

# Whether the shader can make assume nothing has changed since last frame or not
var scene_changed := true:
	set(value):
		_set_flag_bit(RenderFlagsBits.SCENE_CHANGED, int(value))
		scene_changed = value

# Whether every object who is hit should sample their texture or not
var sample_all_textures := false:
	set(value):
		_set_flag_bit(RenderFlagsBits.SAMPLE_ALL_TEXTURES, int(value))
		sample_all_textures = value

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

# What kind of bvh is used, if any. Is of type BVHType enum, but i can't 
#  type hint for some reason
var bvh_type = null
var bvh_order : int

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
		RenderFlagsBits.SCENE_CHANGED * int(scene_changed) +
		RenderFlagsBits.SAMPLE_ALL_TEXTURES * int(sample_all_textures)
	)

func _set_flag_bit(bit, boolean : bool):
	# Shamlessly stolen from:
	# https://stackoverflow.com/questions/47981/how-to-set-clear-and-toggle-a-single-bit
	flags = (flags & ~bit) | (bit * int(boolean))

