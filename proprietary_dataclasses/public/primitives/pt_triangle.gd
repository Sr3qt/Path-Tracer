@tool
class_name PTTriangle
extends PTPrimitive3D

# The triangles vertices relative to itself, not in local coordinates
# Used for defining the shape of the triangle
@export var vertex1 = Vector3.LEFT
@export var vertex2 = Vector3.FORWARD
@export var vertex3 = Vector3.ZERO

# TODO Add godot mesh updating for vertex*


func _init(
		p_vertex1 := Vector3.LEFT,
		p_vertex2 := Vector3.FORWARD,
		p_vertex3 := Vector3.ZERO,
		p_material := PTMaterial.new(), 
	):
	
	mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.surface_add_vertex(Vector3.LEFT)
	mesh.surface_add_vertex(Vector3.FORWARD)
	mesh.surface_add_vertex(Vector3.ZERO)
	mesh.surface_end()
	
	vertex1 = p_vertex1
	vertex2 = p_vertex2
	vertex3 = p_vertex3
	
	material = p_material


func _get_aabb():
	# This is constant for most use cases
	# TODO Store result for further use
	var maximum_x = max(vertex1.x, vertex2.x, vertex3.x)
	var maximum_y = max(vertex1.y, vertex2.y, vertex3.y)
	var maximum_z = max(vertex1.z, vertex2.z, vertex3.z)
	var minimum_x = min(vertex1.x, vertex2.x, vertex3.x)
	var minimum_y = min(vertex1.y, vertex2.y, vertex3.y)
	var minimum_z = min(vertex1.z, vertex2.z, vertex3.z)
	var minimum = Vector3(minimum_x, minimum_y, minimum_z)
	var maximum = Vector3(maximum_x, maximum_y, maximum_z)
	var diff = maximum - minimum
	
	return AABB((minimum), diff)


func get_global_aabb():
	return global_transform * _get_aabb()


func to_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	
	bytes += PackedFloat32Array(
		PTObject.vector_to_array(transform * vertex1) + [0] +
		PTObject.vector_to_array(transform * vertex2) + [0] +
		PTObject.vector_to_array(transform * vertex3) + [0] +
		PTObject.vector_to_array((vertex2 - vertex1).cross(vertex3 -  vertex1).normalized()) + [0]
	).to_byte_array()
	bytes += PackedInt32Array([material_index,0,0,0]).to_byte_array()
	
	return bytes
