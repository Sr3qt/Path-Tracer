@tool
class_name PTMaterial
extends Resource

# Similar to GPU material. Default value is white diffuse
@export_color_no_alpha var albedo := Color(1, 1, 1):
	set(value):
		albedo = value
		material_changed.emit(self)
@export_range(0.0, 1.0) var roughness := 0.0:
	set(value):
		roughness = value
		material_changed.emit(self)
@export_range(0.0, 1.0) var metallic := 0.0:
	set(value):
		metallic = value
		material_changed.emit(self)
@export_range(0.0, 1.0) var opacity := 1.0:
	set(value):
		opacity = value
		material_changed.emit(self)
@export_range(0.0, 2.0) var reflectivity := 1.0:
	set(value):
		reflectivity = value
		material_changed.emit(self)
@export var IOR := 1.0:
	set(value):
		IOR = value
		material_changed.emit(self)
# NOTE: Because of how the shader is written, negint_limit is not available
## During an intersection between at least one dielectric object and another object,
## the object with the highest dielectric_priority will "exist" in the overlap between objects.
@export_range(-2147483645, 2147483647) var dielectric_priority : int = 0:
	set(value):
		dielectric_priority = value
		material_changed.emit(self)
@export var is_emissive := false:
	set(value):
		is_emissive = value
		material_changed.emit(self)

# TODO 3: Calculate current IOR of camera and pass it to gpu
# Would need to calculate the whole IOR stack and pass it to GPU
# That might require double buffers.

# TODO 2: Add Glossiness
# TODO 3: read on the Pixar PBR model, video by Acerola

signal material_changed(material_instance : PTMaterial)


func get_rgb() -> void:
	"""Returns albedo as rgb values from 0 to 255 in srgb space"""


## DEPRECATED For the most part
func find_in_array(materials : Array[PTMaterial]) -> int:
	"""Returns the index of this material in an array, otherwise returns -1"""

	for i in range(materials.size()):
		if is_equal(materials[i]):
			return i

	return -1


## DEPRECATED For the most part
func is_equal(other : PTMaterial) -> bool:
	"""Returns true if other has the same properties as this material"""
	return (other.albedo == albedo and
			other.roughness == roughness and
			other.metallic == metallic and
			other.opacity == opacity and
			other.IOR == IOR and
			other.dielectric_priority == dielectric_priority
	)


func to_byte_array() -> PackedByteArray:
	var floats_array : Array[float] = [
		albedo.r,
		albedo.g,
		albedo.b,
		roughness,
		metallic,
		opacity,
		reflectivity,
		IOR,
	]

	var ints_array : Array[int] = [
		dielectric_priority,
		is_emissive,
		0,
		0,
		0,
		0,
		0,
		0,
	]

	var bytes := (
		PackedFloat32Array(floats_array).to_byte_array() +
		PackedInt32Array(ints_array).to_byte_array()
	)

	return bytes
