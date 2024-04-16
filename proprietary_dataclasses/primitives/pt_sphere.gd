class_name PTSphere
extends PTPrimitive3D

# TODO Investigate why diffuse spheres are reflective on one side
var center : Vector3
var radius : float


func _init(_center : Vector3, _radius : float, _material : PTMaterial, mtl_i):
	center = _center
	radius = _radius
	material = _material
	material_index = mtl_i 
	
	aabb = get_AABB()


func get_AABB():
	var radius_vector = Vector3(radius, radius, radius)
	return PTAABB.new(center - radius_vector, center + radius_vector)
	

func to_byte_array():
	return (PackedFloat32Array(PTObject.vec2array(center) + [radius]).to_byte_array() + 
	PackedInt32Array([material_index, 0, 0, 0]).to_byte_array())

