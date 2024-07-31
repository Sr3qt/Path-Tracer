@tool
class_name PTTriangle
extends PTPrimitive3D

# TODO Ther's still a noise issue wioth triangles, can be seen in editor
#  There is a visible line cutting through the triangle


# The triangles vertices relative to itself, not in local coordinates
# Used for defining the shape of the triangle
@export var vertex1 := Vector3.LEFT:
	set(value):
		vertex1 = value
		_update()
@export var vertex2 := Vector3.FORWARD:
	set(value):
		vertex2 = value
		_update()
@export var vertex3 := Vector3.ZERO:
	set(value):
		vertex3 = value
		_update()

var uv_pos1 := Vector2.ZERO
var uv_pos2 := Vector2.ZERO
var uv_pos3 := Vector2.ZERO

## Is true when any uv_pos is set
var is_uv_set : bool:
	get:
		return not (uv_pos1 == uv_pos2 and uv_pos3 == uv_pos2 and uv_pos3 == Vector2.ZERO)

var vertex_normal1 : Vector3
var vertex_normal2 : Vector3
var vertex_normal3 : Vector3

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

	set_aabb()

	if p_material:
		material = p_material


func _update() -> void:
	if is_node_ready():
		set_aabb()
		if Engine.is_editor_hint():
			create_triangle_mesh()
		if _scene:
			object_changed.emit(self)


static func get_object_byte_size() -> int:
	return 80


func _ready() -> void:
	set_aabb()
	if Engine.is_editor_hint():
		create_triangle_mesh()


func create_triangle_mesh() -> void:
	if mesh:
		(mesh as ImmediateMesh).clear_surfaces()
	else:
		mesh = ImmediateMesh.new()
	(mesh as ImmediateMesh).surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	(mesh as ImmediateMesh).surface_add_vertex(vertex1)
	(mesh as ImmediateMesh).surface_add_vertex(vertex2)
	(mesh as ImmediateMesh).surface_add_vertex(vertex3)
	(mesh as ImmediateMesh).surface_end()


## Every PTObject defines this function with their own ObjectType.
## PTObject returns MAX.
func get_type() -> ObjectType:
	return ObjectType.TRIANGLE


func set_aabb() -> void:
	var temp := AABB()
	temp = temp.expand(vertex1)
	temp = temp.expand(vertex2)
	aabb = temp.expand(vertex3)


func _get_aabb() -> AABB:
	return aabb


func get_global_aabb() -> AABB:
	#if not is_inside_tree():
		#return _get_aabb()
	return global_transform * _get_aabb()


func set_uvs(uv1 : Vector2, uv2 : Vector2, uv3 : Vector2) -> void:
	uv_pos1 = uv1
	uv_pos2 = uv2
	uv_pos3 = uv3


func to_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()

	bytes += PackedFloat32Array(
		PTUtils.vector3_to_array(global_transform * vertex1) + [0] +
		PTUtils.vector3_to_array(global_transform * vertex2) + [0] +
		PTUtils.vector3_to_array(global_transform * vertex3) + [0] +
		PTUtils.vector3_to_array((vertex2 - vertex1).cross(vertex3 -  vertex1).normalized()) + [0]
	).to_byte_array()
	bytes += _get_property_byte_array()

	assert(bytes.size() == PTTriangle.get_object_byte_size(),
			"Acutal byte size and set byte size do not match ")

	return bytes
