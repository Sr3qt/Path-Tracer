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
			mtl_i : int = 0
	) -> void:

	if Engine.is_editor_hint():
		mesh = PlaneMesh.new()
		(mesh as PlaneMesh).size = Vector2(1000, 1000)

	if p_normal != Vector3.UP:
		normal = p_normal
	if p_distance != 0.0:
		distance = p_distance

	if not p_material:
		material = PTMaterial.new()
	else:
		material = p_material

	material_index = mtl_i


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
	return (PackedFloat32Array(PTObject.vector_to_array(normal) + [distance]).to_byte_array() +
	PackedInt32Array([material_index, texture_id, 0, 0]).to_byte_array())
