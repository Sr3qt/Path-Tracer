class_name PTUtils
extends Node

const EPSILON = 1e-6
const AABB_PADDING := Vector3(EPSILON, EPSILON, EPSILON)


static func vector3_to_array(vector : Vector3) -> Array[float]:
	return [vector.x, vector.y, vector.z]


## Create empty byte array with given size in bytes, rounded down to 4 byte-intervals
static func empty_byte_array(size : int) -> PackedByteArray:
	var ints : Array[int] = []
	ints.resize(size / 4)
	ints.fill(0)

	return PackedInt32Array(ints).to_byte_array()


static func transform3d_to_byte_array(transform : Transform3D) -> PackedByteArray:
	var bytes : PackedByteArray = (
			PackedFloat32Array(PTUtils.vector3_to_array(transform.basis.x)).to_byte_array() +
			PackedFloat32Array(PTUtils.vector3_to_array(transform.basis.y)).to_byte_array() +
			PackedFloat32Array(PTUtils.vector3_to_array(transform.basis.z)).to_byte_array() +
			PackedFloat32Array(PTUtils.vector3_to_array(transform.origin)).to_byte_array()
	)
	return bytes


static func transform3d_smuggle_to_byte_array(transform : Transform3D, last_row := Vector4.ZERO) -> PackedByteArray:
	var bytes : PackedByteArray = (
			PackedFloat32Array(PTUtils.vector3_to_array(transform.basis.x)).to_byte_array() +
			PackedFloat32Array([last_row.x]).to_byte_array() +
			PackedFloat32Array(PTUtils.vector3_to_array(transform.basis.y)).to_byte_array() +
			PackedFloat32Array([last_row.y]).to_byte_array() +
			PackedFloat32Array(PTUtils.vector3_to_array(transform.basis.z)).to_byte_array() +
			PackedFloat32Array([last_row.z]).to_byte_array() +
			PackedFloat32Array(PTUtils.vector3_to_array(transform.origin)).to_byte_array() +
			PackedFloat32Array([last_row.w]).to_byte_array()
	)
	return bytes


## Turns AABB into bytes, with optional smuggling
static func aabb_to_byte_array(aabb : AABB, smuggle1 : Variant = 0.0, smuggle2 : Variant = 0.0) -> PackedByteArray:
	var new_aabb := aabb.abs()
	var bytes : PackedByteArray = []

	bytes += PackedFloat32Array(PTUtils.vector3_to_array(new_aabb.position - AABB_PADDING)).to_byte_array()

	if smuggle1 is float:
		bytes += PackedFloat32Array([smuggle1]).to_byte_array()
	elif smuggle1 is int:
		bytes += PackedInt32Array([smuggle1]).to_byte_array()
	else:
		assert(false, "PT: smuggle1 has to be int or float, but was " + str(type_string(typeof(smuggle1))))

	bytes += PackedFloat32Array(PTUtils.vector3_to_array(new_aabb.end + AABB_PADDING)).to_byte_array()

	if smuggle2 is float:
		bytes += PackedFloat32Array([smuggle2]).to_byte_array()
	elif smuggle2 is int:
		bytes += PackedInt32Array([smuggle2]).to_byte_array()
	else:
		assert(false, "PT: smuggle1 has to be int or float, but was " + str(type_string(typeof(smuggle2))))

	return bytes


static func create_canvas() -> MeshInstance3D:
	# Create canvas that will display rendered image
	# Prepare canvas shader
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/canvas.gdshader")
	mat.set_shader_parameter("image_buffer", Texture2DRD.new())
	mat.set_shader_parameter("is_rendering", not PTRendererAuto.is_rendering_disabled)

	var mesh := QuadMesh.new()
	mesh.size = Vector2(2, 2)
	mesh.surface_set_material(0, mat)

	# Create a canvas to which rendered images will be drawn
	var canvas := MeshInstance3D.new()
	canvas.position -= Vector3(0,0,1)
	canvas.set_layer_mask_value(20, true)
	canvas.set_layer_mask_value(1, false)
	canvas.mesh = mesh

	return canvas


static func create_missing_texture_grid(grid_size : int) -> PackedByteArray:
	var black := [0, 0, 0, 56]
	var pink := [56, 16, 56, 56]
	var colours : Array[Array]= [pink, black]
	var grid : Array[int] = []
	for i in range(grid_size):
		for j in range(grid_size):
			grid.append_array(colours[((i % 2) + (j % 2)) % 2])

	var temp_packed := PackedByteArray()
	temp_packed.resize(grid_size ** 2 * 4)

	for i in range(grid_size ** 2 * 4):
		temp_packed.encode_u8(i, grid[i])

	return temp_packed


static func load_shader(ptscene : PTScene) -> RDShaderSource:
	var file := FileAccess.open("res://shaders/ray_tracer.comp", FileAccess.READ_WRITE)
	var res := file.get_as_text()
	file.close()

	# Do changes
	# Change BVH tree order
	res = res.replace("const int order = 2;",
	"const int order = %s;" % ptscene.bvh_order)

	# Insert procedural texture functions
	const DEFUALT_FUNCTION_NAME = "procedural_texture"
	const BASE_FUNCTION_NAME = "_procedural_texture_function"

	# TODO 3: Add test to make sure the texture actually compiles
	var i : int = 1
	var function_definitons := ""
	var function_calls := ""
	for _texture in ptscene.procedural_textures:
		if _texture == null:
			continue
		var texture := _texture as PTProceduralTexture
		var path : String = texture.texture_path
		var tex_file := FileAccess.open(path, FileAccess.READ_WRITE)
		if not tex_file:
			push_error("PT: No procedural texture file found: " +
					texture.texture_path + " in " + path)
		var text := tex_file.get_as_text()

		var function_index : int = text.find(DEFUALT_FUNCTION_NAME)
		if function_index == -1:
			push_error("PT: No procedural texture function found in file: " +
					texture.texture_path + " in " + path)

		text = text.replace(DEFUALT_FUNCTION_NAME, BASE_FUNCTION_NAME + str(i))

		function_calls += (
			"else if (function == %s) {\n" % i + "		return " +
			BASE_FUNCTION_NAME + str(i) + "(pos);\n	}\n	"
		)

		function_definitons += text
		i += 1

	# Inserts function definitions
	res = res.replace("//procedural_texture_function_definition_hook",
			function_definitons)

	# Inserts function calls
	res = res.replace("//procedural_texture_function_call_hook", function_calls)

	# Set shader
	var shader := RDShaderSource.new()
	shader.source_compute = res

	return shader
