extends PTPrimitive3D

class_name PTPlane

var normal : Vector3
var distance : float

func _init(normal_ : Vector3, distance_ : float, material_ : PTMaterial, mtl_i):
	normal = normal_
	distance = distance_
	material = material_
	# TEMP: mtl_i is temporary will be removed
	material_index = mtl_i 
	
	
func to_byte_array():
	return (PackedFloat32Array(PTObject.vec2array(normal) + [distance]).to_byte_array() +
	PackedInt32Array([material_index, 0, 0, 0]).to_byte_array())
