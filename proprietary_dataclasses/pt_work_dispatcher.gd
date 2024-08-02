class_name PTWorkDispatcher
extends RefCounted

## The work dispatcher sends work to the gpu by orders of PTRenderer

## The maximum number of textures that in the shader array of texture.
## This is an arbitrary value, but must match the number in the shader.
const MAX_TEXTURE_COUNT := 512

# How many objects can be added without needing to update any buffers.
# This means that the buffers' sizes are divisible by the step count.
#  Mostly useful for plugin, but might be important for runtime as well.
const SPHERE_COUNT_STEP = 64
const PLANE_COUNT_STEP = 16
const TRIANGLE_COUNT_STEP = 16
# How many materials can be added without needing to update any buffers
const MATERIAL_COUNT_STEP = 16

const BVH_COUNT_STEP = 64

# How many objects can fit in each buffer
var sphere_buffer_size : int = PTObject.ObjectType.SPHERE:
	set(value):
		object_buffer_sizes[PTObject.ObjectType.SPHERE] = value
	get:
		return object_buffer_sizes[sphere_buffer_size]
var plane_buffer_size : int = PTObject.ObjectType.PLANE:
	set(value):
		object_buffer_sizes[PTObject.ObjectType.PLANE] = value
	get:
		return object_buffer_sizes[plane_buffer_size]
var triangle_buffer_size : int = PTObject.ObjectType.TRIANGLE:
	set(value):
		object_buffer_sizes[PTObject.ObjectType.TRIANGLE] = value
	get:
		return object_buffer_sizes[triangle_buffer_size]

## Can be indexed with ObjectType to get the size of the objects buffer size
var object_buffer_sizes : Array[int] = []

var material_buffer_size : int = 0

# TODO implement size check and expansion func
var bvh_buffer_size : int = 0

var uniforms : UniformStorage

# Array of RIDs that need to be freed when done with them.
# Only shader and buffers need to be manually removed
var rids_to_free : Array[RID] = []

var rd : RenderingDevice
var shader : RID
var pipeline : RID

var texture : Texture2DRD

# TODO Maybe consider order of sets
#  https://stackoverflow.com/a/76655166
# TODO Report umlaut bug to godot devs

## TO-DO List for creating buffer
##	- Make set bind index
##	- Make buffer variable
##	- Make create_buffer function
##	- Call create_buffer function in create_buffers
##

## TO-DO List for creating new uniform set
##	- See also instructions for creating buffer (There are none currently)
##	- Add set index constant and MAX constant
##	- Update UniformStorage
##	- Add set RID variable for WD
##	- Update bind_set and bind_sets
##	- Update create_compute_list

# Set / binding indices
const IMAGE_SET_INDEX : int = 0
const IMAGE_BUFFER_BIND : int = 0
const IMAGE_SET_MAX : int = 1

const CAMERA_SET_INDEX : int = 1
const LOD_BIND : int = 0 # For sample per pixel, bounce depth etc.
const CAMERA_SET_MAX : int = 1

const OBJECT_SET_INDEX : int = 2
const MATERIALS_BIND : int = 0
const SPHERES_BIND : int = 1
const PLANES_BIND : int = 2
## Refers to buffer storing PTTraingles, distinct from TRIANGLE_SET which stores
## godot surface/mesh arrays
const TRIANGLES_BIND : int = 3
const OBJECT_SET_MAX : int = 4

const BVH_SET_INDEX : int = 3
const BVH_BIND : int = 0
const OBJECT_ID_BIND : int = 1
const BVH_SET_MAX : int = 2

const TRIANGLE_SET_INDEX : int = 4
const TRIANGLE_VERTEX_BIND : int = 0
const TRIANGLE_UV_BIND : int = 1
const TRIANGLE_INDEX_BIND : int = 2
const TRIANGLE_SET_MAX : int = 3

const TEXTURE_SET_INDEX : int = 5
const TEXTURE_BIND : int = 0
const TEXTURE_SET_MAX : int = 1

const TRANSFORM_SET_INDEX : int = 6
const TRANSFORM_BIND : int = 0
const TRANSFORM_SET_MAX : int = 1

# Set RIDs
var image_set : RID
var camera_set : RID
var object_set : RID
var bvh_set : RID
var triangle_set : RID
var texture_set : RID
var transform_set : RID

# Buffer RIDS
var image_buffer : RID

var camera_buffer : RID
var LOD_buffer : RID

var material_buffer : RID
var sphere_buffer : RID
var plane_buffer : RID
var triangle_buffer : RID

var bvh_buffer : RID
var object_id_buffer: RID

var triangle_vertex_buffer : RID
var triangle_uv_buffer : RID
var triangle_index_buffer : RID

# Texture buffers are only kept in rids_to_free

var transform_buffer : RID

# Whether this instance is using a local RenderDevice
var is_local_renderer := false

# References to renderer and scene that will render
var _renderer : PTRenderer
var _scene : PTScene


func _init(renderer : PTRenderer, is_local := false) -> void:
	uniforms = UniformStorage.new()
	object_buffer_sizes.resize(PTObject.ObjectType.MAX)
	object_buffer_sizes.fill(0)

	_renderer = renderer

	is_local_renderer = is_local

	if is_local_renderer:
		rd = RenderingServer.create_local_rendering_device()
	else:
		# Holy merge clutch https://github.com/godotengine/godot/pull/79288
		# RenderingDevice for realtime rendering
		# TODO Investigate if all wds have the same rd
		rd = RenderingServer.get_rendering_device()


## Finds the smallest integer multiple of step that is strictly greater than x
func ceil_snap(x : int, step : int) -> int:
	@warning_ignore("integer_division")
	return (x / step + 1) * step


## Creates and binds buffers to RenderDevice
func create_buffers() -> void:

	var prev_time := Time.get_ticks_usec()

	# Trying to set up buffers without a scene makes no sense
	if not _scene:
		push_warning("PT: Set a scene for the WorkDispatcher before trying to",
				" create gpu buffers.")
		return

	# The image buffer used in compute and fragment shader
	image_buffer = _create_image_buffer()

	# TODO Add statistics buffer which the gpu can write to
	create_lod_buffer()
	create_material_buffer()
	create_sphere_buffer()
	create_plane_buffer()
	create_triangle_buffer()
	create_object_id_buffer()
	create_bvh_buffer()
	create_triangle_buffers(_scene.make_mesh_arrays())
	create_texture_buffers()
	create_transform_buffer()

	bind_sets()

	# Get texture RID for Canvas
	var material := _renderer.canvas.get_mesh().surface_get_material(0) as ShaderMaterial
	# NOTE: get_shader_parameter literally returns variant; get fgucked. UNSTATIC
	@warning_ignore("unsafe_cast")
	texture = material.get_shader_parameter("image_buffer") as Texture2DRD

	if _scene.get_size() != 0 and PTRendererAuto.is_debug:
		print("Setting up buffers took %s ms" % ((Time.get_ticks_usec() - prev_time) / 1000.))


func get_object_buffer(type : PTObject.ObjectType) -> RID:
	match type:
		PTObject.ObjectType.SPHERE:
			return sphere_buffer
		PTObject.ObjectType.PLANE:
			return plane_buffer
		PTObject.ObjectType.TRIANGLE:
			return triangle_buffer
	assert(false, "PT: ObjectType %s does not have a buffer." % [type])
	return RID()


## Will create the object buffer corresponding to the given type
func create_object_buffer(type : PTObject.ObjectType) -> void:
	match type:
		PTObject.ObjectType.SPHERE:
			create_sphere_buffer()
		PTObject.ObjectType.PLANE:
			create_plane_buffer()
		PTObject.ObjectType.TRIANGLE:
			create_triangle_buffer()
		_:
			assert(false, "PT: ObjectType %s does cannot create a buffer." % [type])


func create_lod_buffer() -> void:
	LOD_buffer = _create_uniform(
			_create_lod_byte_array(), CAMERA_SET_INDEX, LOD_BIND
	)

func create_sphere_buffer() -> void:
	sphere_buffer = _create_uniform(
			_create_spheres_byte_array(), OBJECT_SET_INDEX, SPHERES_BIND
	)

func create_plane_buffer() -> void:
	plane_buffer = _create_uniform(
			_create_planes_byte_array(), OBJECT_SET_INDEX, PLANES_BIND
	)

func create_triangle_buffer() -> void:
	triangle_buffer = _create_uniform(
			_create_triangles_byte_array(), OBJECT_SET_INDEX, TRIANGLES_BIND
	)

func create_material_buffer() -> void:
	material_buffer = _create_uniform(
			_create_materials_byte_array(), OBJECT_SET_INDEX, MATERIALS_BIND
	)

func create_bvh_buffer() -> void:
	# Contains the BVH tree in the form of a list
	bvh_buffer = _create_uniform(
			_create_bvh_byte_array(), BVH_SET_INDEX, BVH_BIND
	)

func create_object_id_buffer() -> void:
	object_id_buffer = _create_uniform(
			_create_object_id_byte_array(), BVH_SET_INDEX, OBJECT_ID_BIND
	)

func create_transform_buffer() -> void:
	transform_buffer = _create_uniform(
			_create_transform_byte_array(), TRANSFORM_SET_INDEX, TRANSFORM_BIND
	)


# TODO Make checks for sub-arrays existing in, array creation, destruction and here
func create_triangle_buffers(surface : Array = [null]) -> void:

	var vertex_bytes := PTUtils.empty_byte_array(12)
	var uv_bytes := PTUtils.empty_byte_array(12)
	var index_bytes := PTUtils.empty_byte_array(12)

	if surface[0] != null and surface[0].size() != 0:
		assert(surface.size() == Mesh.ARRAY_MAX)
		@warning_ignore("unsafe_method_access")
		vertex_bytes = surface[ArrayMesh.ARRAY_VERTEX].to_byte_array()
		if surface[ArrayMesh.ARRAY_TEX_UV] != null and not surface[ArrayMesh.ARRAY_TEX_UV].is_empty() :
			@warning_ignore("unsafe_method_access")
			uv_bytes = surface[ArrayMesh.ARRAY_TEX_UV].to_byte_array()
		@warning_ignore("unsafe_method_access")
		index_bytes = surface[ArrayMesh.ARRAY_INDEX].to_byte_array()

	triangle_vertex_buffer = _create_uniform(
		vertex_bytes,
		TRIANGLE_SET_INDEX,
		TRIANGLE_VERTEX_BIND
	)
	triangle_uv_buffer = _create_uniform(
		uv_bytes,
		TRIANGLE_SET_INDEX,
		TRIANGLE_UV_BIND
	)
	triangle_index_buffer = _create_uniform(
		index_bytes,
		TRIANGLE_SET_INDEX,
		TRIANGLE_INDEX_BIND
	)

func create_texture_buffers() -> void:
	# TODO Measure texture load time
	# # TODO REPORT GOOFY AH BUG
	# # https://forum.godotengine.org/t/retrieving-image-data-from-noisetexture2d-returns-null/55303/4

	var placeholder := load("res://assets/C4-D-UV-Grid-1024x1024.jpg")
	var texture1 := load("res://test_models/grimchild/GrimmchildTexture.png")
	var texture2 := load("res://assets/earthmap.jpg")

	var textures : Array[CompressedTexture2D] = [placeholder, texture1, texture2]

	var uniform := RDUniform.new()
	uniform.binding = TEXTURE_BIND
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE

	var usage_bits : int = (
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT +
			RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		)

	var fill_texture := _create_fill_texture()

	var sample_state := RDSamplerState.new()
	var sampler := rd.sampler_create(sample_state)
	for tex in textures:
		# TODO Find a way to use the compressed textures
		var img := tex.get_image()
		img.decompress()
		img.convert(Image.FORMAT_RGBAF)

		var tf : RDTextureFormat = RDTextureFormat.new()
		tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
		tf.width = img.get_width()
		tf.height = img.get_height()
		tf.mipmaps = img.get_mipmap_count() + 1
		tf.usage_bits = usage_bits

		var new_texture_buffer := rd.texture_create(tf, RDTextureView.new(), [img.get_data()])
		rids_to_free.append(new_texture_buffer)

		uniform.add_id(sampler)
		uniform.add_id(new_texture_buffer)

	var fill := MAX_TEXTURE_COUNT - textures.size()
	for i in range(fill):
		uniform.add_id(sampler)
		uniform.add_id(fill_texture)

	uniforms.set_uniform(TEXTURE_SET_INDEX, TEXTURE_BIND, uniform)


func _create_fill_texture() -> RID:
	# TODO Force texture to be pink and black grid filler texture / Override albedo
	var usage_bits : int = (
			RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
			+ RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		)

	var texture_size := 8
	var missing_texture := PTUtils.create_missing_texture_grid(texture_size)

	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = texture_size
	tf.height = texture_size
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT

	var new_texture_buffer := rd.texture_create(tf, RDTextureView.new(), [missing_texture])
	rids_to_free.append(new_texture_buffer)

	return new_texture_buffer


## Creates and binds render result texture buffer aka. image_buffer
func _create_image_buffer() -> RID:
	var usage_bits : int = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT +
		RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT +
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT +
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		# Remove bit for increased performance, have to add writeonly to shader buffer
		+ RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)

	#if is_local_renderer:
		#usage_bits += RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	# TODO Explore multi-layered texture for multisampling/ ping-ponging
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = PTRendererAuto.render_width
	tf.height = PTRendererAuto.render_height
	tf.usage_bits = usage_bits

	var new_image_buffer := rd.texture_create(tf, RDTextureView.new(), [])
	rids_to_free.append(new_image_buffer)

	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = IMAGE_BUFFER_BIND
	uniform.add_id(new_image_buffer)

	uniforms.set_uniform(IMAGE_SET_INDEX, IMAGE_BUFFER_BIND, uniform)

	return new_image_buffer


func bind_set(index : int) -> void:
	var uniforms_array := uniforms.get_set_uniforms(index)
	var new_set_rid := rd.uniform_set_create(uniforms_array, shader, index)
	match index:
		IMAGE_SET_INDEX:
			image_set = new_set_rid
		CAMERA_SET_INDEX:
			camera_set = new_set_rid
		OBJECT_SET_INDEX:
			object_set = new_set_rid
		BVH_SET_INDEX:
			bvh_set = new_set_rid
		TRIANGLE_SET_INDEX:
			triangle_set = new_set_rid
		TEXTURE_SET_INDEX:
			texture_set = new_set_rid
		TRANSFORM_SET_INDEX:
			transform_set = new_set_rid


func bind_sets() -> void:
	# Bind uniforms and sets
	bind_set(IMAGE_SET_INDEX)
	bind_set(CAMERA_SET_INDEX)
	bind_set(OBJECT_SET_INDEX)
	bind_set(BVH_SET_INDEX)
	bind_set(TRIANGLE_SET_INDEX)
	bind_set(TEXTURE_SET_INDEX)
	bind_set(TRANSFORM_SET_INDEX)


func load_shader(shader_ : RDShaderSource) -> void:
	# Load GLSL shader
	# Was very annoying to find since this function is not mentioned anywhere
	#	in RDShaderSource documentation wrrr
	var shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_)
	shader = rd.shader_create_from_spirv(shader_spirv)
	rids_to_free.append(shader)

	# Create a compute pipeline
	pipeline = rd.compute_pipeline_create(shader)


func free_rids() -> void:
	if texture:
		texture.texture_rd_rid = RID()

	# Frees buffers and shader RIDS
	for rid in rids_to_free:
		rd.free_rid(rid)


## Free a single rid
func free_rid(rid : RID) -> void:
	var index : int= rids_to_free.find(rid)
	if index != -1:
		rids_to_free.remove_at(index)
		rd.free_rid(rid)
	else:
		push_warning("PT: RID " + str(rid) + " is not meant to be freed.")


## Creates the compute list required for every compute call
##
## Requires workgroup coordinates to be given in an array or vector
func create_compute_list(window : PTRenderWindow = null) -> void:

	# By default, will dispatch groups to fill whole render size
	if window == null:
		window = PTRenderWindow.new()

		@warning_ignore("integer_division")
		window.work_group_width = ceili(_renderer.render_width /
										_renderer.compute_invocation_width)
		@warning_ignore("integer_division")
		window.work_group_height = ceili(_renderer.render_height /
										_renderer.compute_invocation_height)
		window.work_group_depth = 1

	var x := window.work_group_width
	var y := window.work_group_height
	var z := window.work_group_depth

	var push_bytes := _push_constant_byte_array(window)

	var compute_list := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)

	# Bind uniform sets
	rd.compute_list_bind_uniform_set(compute_list, image_set, IMAGE_SET_INDEX)
	rd.compute_list_bind_uniform_set(compute_list, camera_set, CAMERA_SET_INDEX)
	rd.compute_list_bind_uniform_set(compute_list, object_set, OBJECT_SET_INDEX)
	rd.compute_list_bind_uniform_set(compute_list, bvh_set, BVH_SET_INDEX)
	rd.compute_list_bind_uniform_set(compute_list, triangle_set, TRIANGLE_SET_INDEX)
	rd.compute_list_bind_uniform_set(compute_list, texture_set, TEXTURE_SET_INDEX)
	rd.compute_list_bind_uniform_set(compute_list, transform_set, TRANSFORM_SET_INDEX)
	rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())

	rd.capture_timestamp(window.render_name)
	rd.compute_list_dispatch(compute_list, x, y, z)

	rd.compute_list_end()

	# Sync is not required when using main RenderingDevice
	if is_local_renderer:
		rd.submit()
		rd.sync()


## set this this PTWorkDispatcher to use specified scene data
func set_scene(scene : PTScene) -> void:
	_scene = scene

# TODO Find a way for the cpu to wait for buffer access

# TODO Make single expand buffer function which can expand any buffer
## Will expand a given object buffer by its respective step constant times given steps.
## Will return true if buffer was expanded.
## Setting create_set to false skips creating a set. By defualt will expand buffer to
##  fit objects in scene. If objects already fit, do nothing, return false.
func expand_object_buffer(
			object_type : PTObject.ObjectType,
			steps : int = 0,
			create_set := true
	) -> bool:

	match object_type:
		PTObject.ObjectType.NOT_OBJECT:
			return false
		PTObject.ObjectType.SPHERE:
			if sphere_buffer_size >= _scene.unpacked_objects.spheres.size() and steps < 1:
				if PTRendererAuto.is_debug:
					print("Sphere buffer already fits. No buffer expansion")
				return false
			if steps < 1:
				var new_size : int = ceil_snap(_scene.unpacked_objects.spheres.size(), SPHERE_COUNT_STEP)
				if new_size <= sphere_buffer_size:
					return false
				sphere_buffer_size = new_size
			else:
				sphere_buffer_size = sphere_buffer_size + SPHERE_COUNT_STEP * steps
			free_rid(sphere_buffer)
			create_sphere_buffer()
		PTObject.ObjectType.PLANE:
			if plane_buffer_size >= _scene.unpacked_objects.planes.size() and steps < 1:
				if PTRendererAuto.is_debug:
					print("Plane buffer already fits. No buffer expansion")
				return false
			if steps < 1:
				var new_size : int = ceil_snap(_scene.unpacked_objects.planes.size(), PLANE_COUNT_STEP)
				if new_size <= plane_buffer_size:
					return false
				plane_buffer_size = new_size
			else:
				plane_buffer_size = plane_buffer_size + PLANE_COUNT_STEP * steps
			free_rid(plane_buffer)
			create_plane_buffer()
		PTObject.ObjectType.TRIANGLE:
			if triangle_buffer_size >= _scene.unpacked_objects.triangles.size() and steps < 1:
				if PTRendererAuto.is_debug:
					print("Triangle buffer already fits. No buffer expansion")
				return false
			if steps < 1:
				var new_size : int = ceil_snap(_scene.unpacked_objects.triangles.size(), TRIANGLE_COUNT_STEP)
				if new_size <= triangle_buffer_size:
					return false
				triangle_buffer_size = new_size
			else:
				triangle_buffer_size = triangle_buffer_size + TRIANGLE_COUNT_STEP * steps
			free_rid(triangle_buffer)
			create_triangle_buffer()

	if create_set:
		var object_uniforms := uniforms.get_set_uniforms(OBJECT_SET_INDEX)
		object_set = rd.uniform_set_create(object_uniforms, shader, OBJECT_SET_INDEX)

	return true


func check_object_buffer_size() -> void:
	var expanded_buffer := false
	for type : PTObject.ObjectType in PTObject.ObjectType.values():
		if type == PTObject.ObjectType.NOT_OBJECT or type == PTObject.ObjectType.MAX:
			continue

		if _scene.unpacked_objects.get_object_array(type).size() > object_buffer_sizes[type]:
			expand_object_buffer(type, 0, false)
			expanded_buffer = true

	if expanded_buffer:
		bind_set(OBJECT_SET_INDEX)


func expand_bvh_buffer(steps : int = 0, create_set := true) -> bool:
	if  bvh_buffer_size >= _scene.bvh.bvh_list.size() and steps < 1:
		if PTRendererAuto.is_debug:
			print("BVH buffer already fits. No buffer expansion")
		return false
	if steps < 1:
		var new_size : int = ceil_snap(_scene.bvh.bvh_list.size(), BVH_COUNT_STEP)
		if new_size <= bvh_buffer_size:
			return false
		bvh_buffer_size = new_size
	else:
		bvh_buffer_size = bvh_buffer_size + BVH_COUNT_STEP * steps
	free_rid(bvh_buffer)
	create_bvh_buffer()

	if create_set:
		var bvh_uniforms := uniforms.get_set_uniforms(BVH_SET_INDEX)
		bvh_set = rd.uniform_set_create(bvh_uniforms, shader, BVH_SET_INDEX)

	return true

## Will expand the material buffer by its step constant times given steps.
## Will return true if buffer was expanded.
## Setting create_set to false skips creating a set. By defualt will create buffer
##  to fit objects in scene. If objects already fit, do nothing, return false.
func expand_material_buffer(steps : int = 0, create_set := true) -> bool:
	if material_buffer_size >= _scene.materials.size() and steps < 1:
		if PTRendererAuto.is_debug:
			print("Material buffer already fits. No buffer expansion")
		return false
	if steps < 1:
		var new_size : int = ceil_snap(_scene.materials.size(), MATERIAL_COUNT_STEP)
		if new_size <= material_buffer_size:
			return false
		material_buffer_size = new_size
	else:
		material_buffer_size = material_buffer_size + MATERIAL_COUNT_STEP * steps
	free_rid(material_buffer)
	create_material_buffer()

	if create_set:
		var object_uniforms := uniforms.get_set_uniforms(OBJECT_SET_INDEX)
		object_set = rd.uniform_set_create(object_uniforms, shader, OBJECT_SET_INDEX)

	return true

# TODO Create function to expand texture buffer here

func expand_object_buffers(object_types : Array[PTObject.ObjectType]) -> void:
	for object_type in object_types:
		expand_object_buffer(object_type, 0, false)

	var object_uniforms := uniforms.get_set_uniforms(OBJECT_SET_INDEX)
	object_set = rd.uniform_set_create(object_uniforms, shader, OBJECT_SET_INDEX)


## Create and bind uniform to the shader from bytes.
## Returns the buffer created
func _create_uniform(bytes : PackedByteArray, _set : int, binding : int) -> RID:
	var buffer : RID = rd.storage_buffer_create(bytes.size(), bytes)
	rids_to_free.append(buffer)
	var uniform := RDUniform.new()

	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)

	uniforms.set_uniform(_set, binding, uniform)

	return buffer


func _create_lod_byte_array() -> PackedByteArray:
	var lod_array : Array[int] = [
		_renderer.render_width,
		_renderer.render_height,
		_renderer.samples_per_pixel,
		_renderer.max_default_depth,
		_renderer.max_refraction_bounces
	]
	return PackedInt32Array(lod_array).to_byte_array()


func _create_materials_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	var size : int = _scene.materials.size()
	for material in _scene.materials:
		if not material:
			bytes += PTMaterial.new().to_byte_array()
		else:
			bytes += material.to_byte_array()

	# Fill rest of bytes with empty
	if material_buffer_size == 0:
		material_buffer_size = ceil_snap(size, MATERIAL_COUNT_STEP)

	for i in range(material_buffer_size - size):
		bytes += PTMaterial.new().to_byte_array()

	return bytes


func _create_spheres_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	var size : int = _scene.unpacked_objects.spheres.size()
	for sphere in _scene.unpacked_objects.spheres:
		bytes += sphere.to_byte_array()

	# Fill rest of bytes with empty
	if sphere_buffer_size == 0:
		sphere_buffer_size = ceil_snap(size, SPHERE_COUNT_STEP)

	for i in range(sphere_buffer_size - size):
		bytes += PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()

	return bytes


func _create_planes_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	var size : int = _scene.unpacked_objects.planes.size()
	for plane in _scene.unpacked_objects.planes:
		bytes += plane.to_byte_array()

	# Fill rest of bytes with empty
	if plane_buffer_size == 0:
		plane_buffer_size = ceil_snap(size, PLANE_COUNT_STEP)

	for i in range(plane_buffer_size - size):
		bytes += PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()

	return bytes


func _create_triangles_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	var size : int = _scene.unpacked_objects.triangles.size()
	for triangle in _scene.unpacked_objects.triangles:
		bytes += triangle.to_byte_array()

	# Fill rest of bytes with empty
	if triangle_buffer_size == 0:
		triangle_buffer_size = ceil_snap(size, TRIANGLE_COUNT_STEP)

	for i in range(triangle_buffer_size - size):
		bytes += PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()

	return bytes


func _create_bvh_byte_array() -> PackedByteArray:
	# TODO Use bvh_buffer_size to pad
	if _scene.bvh:
		return _scene.bvh.to_byte_array()
	else:
		return PTBVHTree.new().to_byte_array()


func _create_object_id_byte_array() -> PackedByteArray:
	var bytes : PackedByteArray = []

	if _scene.bvh and _scene.bvh.scene:
		if _scene.bvh.object_ids.size() == 0:
			# TODO Find a beter place to create object_ids, shouldn't be here atleast
			_scene.bvh.create_object_ids()
		bytes = _scene.bvh.object_ids.to_byte_array()
	else:
		bytes = PTUtils.empty_byte_array(8)

	return bytes


func _create_transform_byte_array() -> PackedByteArray:
	var bytes : PackedByteArray = []
	if _scene.scene_objects.meshes.size() > 0:
		for mesh in _scene.scene_objects.meshes:
			bytes += mesh.to_byte_array()
	else:
		bytes = PTUtils.empty_byte_array(16 * 4)
	return bytes


func _push_constant_byte_array(window : PTRenderWindow) -> PackedByteArray:
	var bytes := PackedByteArray()

	if Engine.is_editor_hint():
		bytes += PTRendererAuto._pt_editor_camera.to_byte_array()
	else:
		bytes += _scene.camera.to_byte_array()
	# A higher divisor seems to give a more volatile local noise
	#  If set to low, refractive materials might not multisample correctly
	# TODO Make frame 1 always produce the same result, to eliminate pixelsd changing
	var divisor := 100_000.0
	var repeat := 10.0 # in seconds
	var time : float = fmod(Time.get_ticks_msec() / divisor, (repeat * 1000) / divisor)

	# NOTE: Must be 16-byte aligned
	bytes += window.flags_to_byte_array()
	bytes += PackedInt32Array([
		window.x_offset,
		window.y_offset,
		window.node_display_threshold,
		window.object_display_threshold,
	]).to_byte_array()
	bytes += PackedFloat32Array([time]).to_byte_array()
	bytes += PackedFloat32Array([
		window.frame,
		window.max_samples,
	]).to_byte_array()

	return bytes


class UniformStorage:
	var image_set : Array[RDUniform]
	var camera_set : Array[RDUniform]
	var object_set : Array[RDUniform]
	var bvh_set : Array[RDUniform]
	var triangle_set : Array[RDUniform]
	var texture_set : Array[RDUniform]
	var transform_set : Array[RDUniform]


	func _init() -> void:
		# Arrays need to be initialized with the same size as number of binds in a set
		image_set.resize(IMAGE_SET_MAX)
		camera_set.resize(CAMERA_SET_MAX)
		object_set.resize(OBJECT_SET_MAX)
		bvh_set.resize(BVH_SET_MAX)
		triangle_set.resize(TRIANGLE_SET_MAX)
		texture_set.resize(TEXTURE_SET_MAX)
		transform_set.resize(TRANSFORM_SET_MAX)


	func get_set_uniforms(index : int) -> Array[RDUniform]:
		match index:
			IMAGE_SET_INDEX:
				return image_set
			CAMERA_SET_INDEX:
				return camera_set
			OBJECT_SET_INDEX:
				return object_set
			BVH_SET_INDEX:
				return bvh_set
			TRIANGLE_SET_INDEX:
				return triangle_set
			TEXTURE_SET_INDEX:
				return texture_set
			TRANSFORM_SET_INDEX:
				return transform_set

		assert(false, "PT: Uniform index '%S' is invalid." % index)
		return []


	func set_uniform(set_index : int, bind_index : int, uniform : RDUniform) -> void:
		var uniform_set := get_set_uniforms(set_index)
		uniform_set[bind_index] = uniform
