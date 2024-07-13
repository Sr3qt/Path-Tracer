class_name PTUtils
extends Node


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

	var i : int = 1
	var function_definitons := ""
	var function_calls := ""
	for _texture in ptscene.textures:
		if not _texture is PTProceduralTexture:
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
