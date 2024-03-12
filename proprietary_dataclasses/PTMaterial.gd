extends Node

class_name PTMaterial

# Similar to GPU material, temporary
var albedo : Vector3 # Stored as linear color values from 0 to 1
var roughness : float
var metallic : float
var opacity : float
var IOR : float
var refraction_depth : int


func get_rgb():
	"""Returns albedo as rgb values from 0 to 255 in srgb space"""


func to_byte_array():
	var floats_array = PTObject.vec2array(albedo) + [
		roughness,
		metallic,
		opacity,
		IOR
	]
	
	var bytes = (PackedFloat32Array(floats_array).to_byte_array() +
	PackedInt32Array([refraction_depth]).to_byte_array())
	
	return bytes
