extends RCPrimitive3D

var center : Vector3
var radius : float
var material : RCMaterial
var material_index : int

func _init(center : Vector3, radius : float, material : RCMaterial):
	center = center
	radius = radius 
	material = material
	material_index = 0


func vec2array(vector : Vector3):
	return [vector.x, vector.y, vector.z]

func to_byte_array():
	return (PackedFloat32Array(vec2array(center) + [radius]).to_byte_array() + 
	PackedInt32Array([material_index, 0, 0, 0]).to_byte_array())

func get_AABB():
	var radius_vector = Vector3(radius, radius, radius)
	return [center - radius_vector, center + radius_vector]
	
