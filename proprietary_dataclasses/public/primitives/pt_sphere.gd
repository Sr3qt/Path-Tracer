@tool
class_name PTSphere
extends PTObject

@export var radius : float = 1.0:
	set(value):
		if mesh is SphereMesh:
			(mesh as SphereMesh).radius = value
			(mesh as SphereMesh).height = value * 2
		radius = value
		if _scene and is_node_ready():
			_scene.update_object(self)


func _init(
			p_center := Vector3.ZERO,
			p_radius : float = 1.0,
			p_material : PTMaterial = null,
	) -> void:

	if Engine.is_editor_hint():
		mesh = SphereMesh.new()
		(mesh as SphereMesh).radius = p_radius
		(mesh as SphereMesh).height = p_radius * 2
	else:
		mesh = null

	if p_center != Vector3.ZERO:
		position = p_center

	if p_radius != 1.0:
		radius = p_radius

	if p_material:
		material = p_material


func _set(property : StringName, _value : Variant) -> bool:
	if _scene:
		# NOTE: Set position is for transform property in the editor,
		#  while transform notification is for moving objects in 3D
		if property == "position":
			_scene.update_object(self)

	return false


func to_byte_array() -> PackedByteArray:
	return (PackedFloat32Array(PTObject.vector_to_array(position) + [radius]).to_byte_array() +
	_get_property_byte_array())

