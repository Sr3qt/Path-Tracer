@tool
class_name PTSphere
extends PTPrimitive3D

@export var radius : float = 1.0:
	set(value):
		if mesh is SphereMesh:
			mesh.radius = value
			mesh.height = value * 2
		radius = value
		if _scene and is_node_ready():
			_scene.update_object(self)


func _init(
			p_center := Vector3.ZERO, 
			p_radius : float = 1.0, 
			p_material : PTMaterial = null, 
			mtl_i = 1
	):
	
	if Engine.is_editor_hint():
		mesh = SphereMesh.new()
		mesh.radius = p_radius
		mesh.height = p_radius * 2
	else:
		mesh = null
	
	if p_center != Vector3.ZERO:
		position = p_center
	
	if p_radius != 1.0:
		radius = p_radius
	
	if not p_material:
		material = PTMaterial.new()
	else:
		material = p_material
	material_index = mtl_i
	


func _set(property, _value):
	if _scene:
		# NOTE: Set position is for transform property in the editor, 
		#  while transform notification is for moving objects in 3D
		if property == "position":
			_scene.update_object(self)


func to_byte_array():
	return (PackedFloat32Array(PTObject.vector_to_array(position) + [radius]).to_byte_array() + 
	PackedInt32Array([material_index, 0, 0, 0]).to_byte_array())

