class_name PTMaterial
extends Node
# TODO Make into a resource


# Similar to GPU material, default value is the same as air
var albedo := Vector3(1, 1, 1) # Stored as linear color values from 0 to 1
var roughness := 0.
var metallic := 0.
var opacity := 1.
var IOR := 1.
var refraction_depth := 0

# TODO Add texture variable
# TODO Add chance to reflect for transparent objects
# TODO Calculate current IOR of camera and pass it to gpu

func get_rgb():
	"""Returns albedo as rgb values from 0 to 255 in srgb space"""


func find_in_array(materials : Array[PTMaterial]):
	"""Returns the index of this material in an array, otherwise returns -1"""
	
	for i in range(materials.size()):
		if is_equal(materials[i]):
			return i
	
	return -1
	

func is_equal(other : PTMaterial):
	"""Returns true if other has the same properties as this material"""
	return (other.albedo == albedo and 
			other.roughness == roughness and 
			other.metallic == metallic and 
			other.opacity == opacity and 
			other.IOR == IOR and 
			other.refraction_depth == refraction_depth
	)

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
