@tool
class_name PTSphere
extends PTObject

@export var radius : float = 1.0:
	set(value):
		if mesh is SphereMesh:
			(mesh as SphereMesh).radius = value
			(mesh as SphereMesh).height = value * 2
		radius = value
		if is_node_ready():
			object_changed.emit(self)


func _init(
			p_center := Vector3.ZERO,
			p_radius : float = 1.0,
			p_material : PTMaterial = null,
	) -> void:

	if Engine.is_editor_hint() and not is_instance_valid(mesh):
		mesh = SphereMesh.new()
		(mesh as SphereMesh).radius = p_radius
		(mesh as SphereMesh).height = p_radius * 2

	if p_center != Vector3.ZERO:
		position = p_center

	if p_radius != 1.0:
		radius = p_radius

	if p_material:
		material = p_material


static func get_object_byte_size() -> int:
	return 32


## Every PTObject defines this function with their own ObjectType.
## PTObject returns MAX.
func get_type() -> ObjectType:
	return ObjectType.SPHERE


func _get_aabb() -> AABB:
	var radius_vector := Vector3(radius, radius, radius)
	return AABB(position - radius_vector, radius_vector * 2).abs()


## Return the aabb used by the BVH
func get_bvh_aabb() -> AABB:
	return _get_aabb()


func to_byte_array() -> PackedByteArray:
	var bytes := (PackedFloat32Array(PTUtils.vector3_to_array(position) + [radius]).to_byte_array())
	bytes += _get_property_byte_array()

	assert(bytes.size() == PTSphere.get_object_byte_size(),
			"Acutal byte size and set byte size do not match ")

	return bytes
