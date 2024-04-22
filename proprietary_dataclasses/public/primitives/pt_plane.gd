class_name PTPlane
extends PTPrimitive3D


var normal : Vector3
var distance : float


func _init(normal_ : Vector3, distance_ : float, material_ : PTMaterial, mtl_i):
	normal = normal_
	distance = distance_
	material = material_
	material_index = mtl_i 
	

func to_byte_array():
	return (PackedFloat32Array(PTObject.vec2array(normal) + [distance]).to_byte_array() +
	PackedInt32Array([material_index, 1, 0, 0]).to_byte_array())
