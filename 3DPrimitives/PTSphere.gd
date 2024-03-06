extends PTPrimitive3D

class_name PTSphere

var center : Vector3
var radius : float

func _init(center_ : Vector3, radius_ : float, material_ : PTMaterial, mtl_i):
	center = center_
	radius = radius_
	material = material_
	# TEMP: mtl_i is temporary will be removed
	material_index = mtl_i 
	
	aabb = get_AABB()


func vec2array(vector : Vector3):
	return [vector.x, vector.y, vector.z]

func to_byte_array():
	return (PackedFloat32Array(vec2array(center) + [radius]).to_byte_array() + 
	PackedInt32Array([material_index, 0, 0, 0]).to_byte_array())

func get_AABB():
	var radius_vector = Vector3(radius, radius, radius)
	return PTAABB.new(center - radius_vector, center + radius_vector)
	
