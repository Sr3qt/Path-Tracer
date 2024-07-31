@tool
class_name PTPlane
extends PTPrimitive3D

@export var normal := Vector3.UP:
	set(value):
		if value == Vector3.ZERO:
			push_warning("Cannot set plane normal to zero vector.")
			return

		if mesh is PlaneMesh and value != normal:
			rotate_to_new_normal(value)
			normal = value
			translate_with_new_d(distance)
@export var distance : float = 0.0:
	set(value):
		translate_with_new_d(value)
		distance = value


func _init(
			p_normal := Vector3.UP,
			p_distance : float = 0.0,
			p_material : PTMaterial = null,
	) -> void:

	if Engine.is_editor_hint() and not is_instance_valid(mesh):
		mesh = PlaneMesh.new()
		(mesh as PlaneMesh).size = Vector2(1000, 1000)

	if p_normal != Vector3.UP:
		normal = p_normal
	if p_distance != 0.0:
		distance = p_distance

	if p_material:
		material = p_material


static func get_object_byte_size() -> int:
	return 32


## Every PTObject defines this function with their own ObjectType.
## PTObject returns MAX.
func get_type() -> ObjectType:
	return ObjectType.PLANE


func rotate_to_new_normal(new_normal : Vector3) -> void:
	var axis := new_normal.cross(normal).normalized()
	var angle := normal.signed_angle_to(new_normal, axis)

	var prev_origin := position
	var temp_transform := Transform3D(transform)
	temp_transform.origin = Vector3.ZERO
	temp_transform = temp_transform.rotated(axis, angle)
	temp_transform.origin = prev_origin
	transform = temp_transform


func translate_with_new_d(new_d : float) -> void:
	position = new_d * normal


func to_byte_array() -> PackedByteArray:
	var bytes := (
		PackedFloat32Array(PTUtils.vector3_to_array(normal) +
		[distance]).to_byte_array() +
		_get_property_byte_array()
	)
	assert(bytes.size() == PTPlane.get_object_byte_size(),
			"Acutal byte size and set byte size do not match ")
	return bytes
