@tool
class_name PTSphere
extends PTObject

const USE_INSTANCING = true

@export var radius : float = 1.0:
	set(value):
		if mesh is SphereMesh:
			(mesh as SphereMesh).radius = value
			(mesh as SphereMesh).height = value * 2
		radius = value
		if USE_INSTANCING:
			scale = Vector3(radius, radius, radius)
		else:
			scale = Vector3.ONE
		if _scene and is_node_ready():
			object_changed.emit(self)


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
			object_changed.emit(self)

	return false


func _get_aabb() -> AABB:
	return AABB(-Vector3.ONE, Vector3.ONE * 2)


func get_global_aabb() -> AABB:
	"""Returns the objects aabb in world coordinates"""
	if USE_INSTANCING:
		return global_transform * _get_aabb()

	return global_transform * get_aabb()


func to_byte_array() -> PackedByteArray:
	var bytes : PackedByteArray
	if not USE_INSTANCING:
		bytes = (PackedFloat32Array(PTObject.vector_to_array(position) + [radius]).to_byte_array() +
		_get_property_byte_array()
		+ PackedInt32Array([0,0,0,0,0,0,0,0]).to_byte_array()
		)

	else:
		# TODO NOTE When adding meshes change to transform
		var ttransform := global_transform.affine_inverse()
		bytes = (
			PackedFloat32Array(PTObject.vector_to_array(ttransform.basis.x)).to_byte_array() +
			PackedInt32Array([_scene.get_material_index(material)]).to_byte_array() +
			PackedFloat32Array(PTObject.vector_to_array(ttransform.basis.y)).to_byte_array() +
			PackedInt32Array([_scene.get_texture_id(texture)]).to_byte_array() +
			PackedFloat32Array(PTObject.vector_to_array(ttransform.basis.z)).to_byte_array() +
			PackedInt32Array([0]).to_byte_array() +
			PackedFloat32Array(PTObject.vector_to_array(ttransform.origin)).to_byte_array() +
			PackedInt32Array([0]).to_byte_array()
			)

	return bytes





