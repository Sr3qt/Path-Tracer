@tool
class_name PTTriangle
extends PTPrimitive3D

# The triangles vertices relative to itself, not in local coordinates
# Used for defining the shape of the triangle
@export var vertex1 := Vector3.LEFT:
	set(value):
		vertex1 = value
		if is_node_ready():
			create_triangle_mesh()
			set_aabb()
			if _scene:
				object_changed.emit(self)
@export var vertex2 := Vector3.FORWARD:
	set(value):
		vertex2 = value
		if is_node_ready():
			create_triangle_mesh()
			set_aabb()
			if _scene:
				object_changed.emit(self)
@export var vertex3 := Vector3.ZERO:
	set(value):
		vertex3 = value
		if is_node_ready():
			create_triangle_mesh()
			set_aabb()
			if _scene:
				object_changed.emit(self)

var aabb : AABB


func _init(
		p_vertex1 := Vector3.LEFT,
		p_vertex2 := Vector3.FORWARD,
		p_vertex3 := Vector3.ZERO,
		p_material : PTMaterial = null,
	) -> void:

	if p_vertex1 != Vector3.LEFT:
		vertex1 = p_vertex1
	if p_vertex2 != Vector3.FORWARD:
		vertex2 = p_vertex2
	if p_vertex3 != Vector3.ZERO:
		vertex3 = p_vertex3

	if p_material:
		material = p_material


func _ready() -> void:
	set_aabb()
	if Engine.is_editor_hint():
		create_triangle_mesh()


func create_triangle_mesh() -> void:
	if mesh:
		mesh.clear_surfaces()
	else:
		mesh = ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.surface_add_vertex(vertex1)
	mesh.surface_add_vertex(vertex2)
	mesh.surface_add_vertex(vertex3)
	mesh.surface_end()


func set_aabb() -> void:
	var temp = AABB()
	temp = temp.expand(vertex1)
	temp = temp.expand(vertex2)
	aabb = temp.expand(vertex3)


func _get_aabb() -> AABB:
	return aabb


func get_global_aabb() -> AABB:
	return global_transform * _get_aabb()


func to_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()

	bytes += PackedFloat32Array(
		PTObject.vector_to_array(transform * vertex1) + [0] +
		PTObject.vector_to_array(transform * vertex2) + [0] +
		PTObject.vector_to_array(transform * vertex3) + [0] +
		PTObject.vector_to_array((vertex2 - vertex1).cross(vertex3 -  vertex1).normalized()) + [0]
	).to_byte_array()
	bytes += _get_property_byte_array()

	return bytes
