class_name PTWorkDispatcher
extends RefCounted

## The work dispatcher sends work to the gpu by orders of PTRenderer

# How many objects can be added without needing to update any buffers.
# This means that the buffers' sizes are divisible by the step count.
#  Mostly useful for plugin, but might be important for runtime as well.
const SPHERE_COUNT_STEP = 64
const PLANE_COUNT_STEP = 16
const TRIANGLE_COUNT_STEP = 16
# How many materials can be added without needing to update any buffers
const MATERIAL_COUNT_STEP = 16

# How many objects can fit in each buffer
var sphere_buffer_size : int = 0
var plane_buffer_size : int = 0
var triangle_buffer_size : int = 0

var material_buffer_size : int = 0

var uniforms : UniformStorage

# Array of RIDs that need to be freed when done with them.
# Only shader and buffers need to be manually removed
var rids_to_free : Array[RID] = []

var rd : RenderingDevice
var shader : RID
var pipeline : RID

var texture : Texture2DRD

# TODO Report umlaut bug to godot devs
## TO-DO List for creating new uniform set
##	- See also instructions for creating buffer \
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
const TRIANGLES_BIND : int = 3
const OBJECT_SET_MAX : int = 4

const BVH_SET_INDEX : int = 3
const BVH_BIND : int = 0
const BVH_SET_MAX : int = 1

# Set RIDs
var image_set : RID
var camera_set : RID
var object_set : RID
var bvh_set : RID

# Buffer RIDS
var image_buffer : RID

var camera_buffer : RID
var LOD_buffer : RID

var material_buffer : RID
var sphere_buffer : RID
var plane_buffer : RID
var triangle_buffer : RID

var bvh_buffer : RID

# Whether this instance is using a local RenderDevice
var is_local_renderer := false

# References to renderer and scene that will render
var _renderer : PTRenderer
var _scene : PTScene


func _init(renderer : PTRenderer, is_local := false) -> void:
	uniforms = UniformStorage.new()

	_renderer = renderer

	is_local_renderer = is_local

	if is_local_renderer:
		rd = RenderingServer.create_local_rendering_device()
	else:
		# Holy merge clutch https://github.com/godotengine/godot/pull/79288
		# RenderingDevice for realtime rendering
		rd = RenderingServer.get_rendering_device()


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
	create_bvh_buffer()

	bind_sets()

	# Get texture RID for Canvas
	var material := _renderer.canvas.get_mesh().surface_get_material(0) as ShaderMaterial
	# NOTE: get_shader_parameter literally returns variant; get fgucked. UNSTATIC
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

func bind_set(index : int) -> void:
	match index:
		IMAGE_SET_INDEX:
			var image_uniforms := uniforms.get_set_uniforms(IMAGE_SET_INDEX)
			image_set = rd.uniform_set_create(image_uniforms, shader, IMAGE_SET_INDEX)
		CAMERA_SET_INDEX:
			var camera_uniform := uniforms.get_set_uniforms(CAMERA_SET_INDEX)
			camera_set = rd.uniform_set_create(camera_uniform, shader, CAMERA_SET_INDEX)
		OBJECT_SET_INDEX:
			var object_uniforms := uniforms.get_set_uniforms(OBJECT_SET_INDEX)
			object_set = rd.uniform_set_create(object_uniforms, shader, OBJECT_SET_INDEX)
		BVH_SET_INDEX:
			var BVH_uniforms := uniforms.get_set_uniforms(BVH_SET_INDEX)
			bvh_set = rd.uniform_set_create(BVH_uniforms, shader, BVH_SET_INDEX)
		_:
			push_error("PT: Cannot bind set with index ", index, ".")


func bind_sets() -> void:
	# Bind uniforms and sets
	bind_set(IMAGE_SET_INDEX)
	bind_set(CAMERA_SET_INDEX)
	bind_set(OBJECT_SET_INDEX)
	bind_set(BVH_SET_INDEX)


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


func free_rid(rid : RID) -> void:
	"""Free a single rid"""
	var index : int= rids_to_free.find(rid)
	if index != -1:
		rids_to_free.remove_at(index)
		rd.free_rid(rid)
	else:
		push_warning("PT: RID " + str(rid) + " is not meant to be freed.")


func create_compute_list(window : PTRenderWindow = null) -> void:
	""" Creates the compute list required for every compute call

	Requires workgroup coordinates to be given in an array or vector
	"""

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
	rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())

	rd.capture_timestamp(window.render_name)
	rd.compute_list_dispatch(compute_list, x, y, z)

	rd.compute_list_end()

	# Sync is not required when using main RenderingDevice
	if is_local_renderer:
		rd.submit()
		rd.sync()


func set_scene(scene : PTScene) -> void:
	"""set this this PTWorkDispatcher to use specified scene data"""
	_scene = scene


# TODO Find a way for the cpu to wait for buffer access

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
			if sphere_buffer_size >= _scene.objects.spheres.size() and steps < 1:
				if PTRendererAuto.is_debug:
					print("Sphere buffer already fits. No buffer expansion")
				return false
			if steps < 1:
				@warning_ignore("integer_division")
				var new_size : int = _scene.objects.spheres.size() / SPHERE_COUNT_STEP + 1
				if new_size <= sphere_buffer_size:
					return false
				sphere_buffer_size = new_size
			else:
				sphere_buffer_size = sphere_buffer_size + SPHERE_COUNT_STEP * steps
			free_rid(sphere_buffer)
			create_sphere_buffer()
		PTObject.ObjectType.PLANE:
			if plane_buffer_size >= _scene.objects.planes.size() and steps < 1:
				if PTRendererAuto.is_debug:
					print("Plane buffer already fits. No buffer expansion")
				return false
			if steps < 1:
				@warning_ignore("integer_division")
				var new_size : int = _scene.objects.planes.size() / PLANE_COUNT_STEP + 1
				if new_size <= plane_buffer_size:
					return false
				plane_buffer_size = new_size
			else:
				plane_buffer_size = plane_buffer_size + PLANE_COUNT_STEP * steps
			free_rid(plane_buffer)
			create_plane_buffer()
		PTObject.ObjectType.TRIANGLE:
			if triangle_buffer_size >= _scene.objects.triangles.size() and steps < 1:
				if PTRendererAuto.is_debug:
					print("Triangle buffer already fits. No buffer expansion")
				return false
			if steps < 1:
				@warning_ignore("integer_division")
				var new_size : int = _scene.objects.triangles.size() / TRIANGLE_COUNT_STEP + 1
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
		@warning_ignore("integer_division")
		var new_size : int = _scene.materials.size() / MATERIAL_COUNT_STEP + 1
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


func _create_uniform(bytes : PackedByteArray, _set : int, binding : int) -> RID:
	"""Create and bind uniform to a shader from bytes.

	returns the uniform and buffer created in an array"""

	var buffer : RID = rd.storage_buffer_create(bytes.size(), bytes)
	rids_to_free.append(buffer)
	var uniform := RDUniform.new()

	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)

	uniforms.set_uniform(_set, binding, uniform)

	return buffer


func _create_image_buffer() -> RID:
	"""Creates and binds render result texture buffer aka. image_buffer"""
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

	# TODO Explore multi-layered texture for multisampling
	var new_image_buffer := _create_texture_buffer(
		RenderingDevice.TEXTURE_TYPE_2D,
		_renderer.render_width,
		_renderer.render_height,
		[],
		1,
		usage_bits
	)

	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = IMAGE_BUFFER_BIND
	uniform.add_id(new_image_buffer)

	uniforms.set_uniform(IMAGE_SET_INDEX, IMAGE_BUFFER_BIND, uniform)

	return new_image_buffer


func _create_texture_buffer(
	texture_type : RenderingDevice.TextureType,
	width : int,
	height : int,
	data : PackedByteArray,
	array_layers : int,
	usage_bits : int
	) -> RID:
	"""Creates an unbound texture buffer"""

	# Create image buffer for compute and fragment shader
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = texture_type
	tf.width = width
	tf.height = height
	tf.depth = 1
	tf.array_layers = array_layers
	tf.mipmaps = 1
	tf.usage_bits = usage_bits

	var new_texture_buffer := rd.texture_create(tf, RDTextureView.new(), data)
	rids_to_free.append(new_texture_buffer)

	return new_texture_buffer


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
		@warning_ignore("integer_division")
		material_buffer_size = (size / MATERIAL_COUNT_STEP + 1) * MATERIAL_COUNT_STEP

	for i in range(material_buffer_size - size):
		bytes += PTMaterial.new().to_byte_array()

	return bytes


func _create_spheres_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	var size : int = _scene.objects.spheres.size()
	for sphere in _scene.objects.spheres:
		bytes += sphere.to_byte_array()

	# Fill rest of bytes with empty
	if sphere_buffer_size == 0:
		@warning_ignore("integer_division")
		sphere_buffer_size = (size / SPHERE_COUNT_STEP + 1) * SPHERE_COUNT_STEP

	for i in range(sphere_buffer_size - size):
		bytes += PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()

	return bytes


func _create_planes_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	var size : int = _scene.objects.planes.size()
	for plane in _scene.objects.planes:
		bytes += plane.to_byte_array()

	# Fill rest of bytes with empty
	if plane_buffer_size == 0:
		@warning_ignore("integer_division")
		plane_buffer_size = (size / PLANE_COUNT_STEP + 1) * PLANE_COUNT_STEP

	for i in range(plane_buffer_size - size):
		bytes += PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()

	return bytes


func _create_triangles_byte_array() -> PackedByteArray:
	var bytes := PackedByteArray()
	var size : int = _scene.objects.triangles.size()
	for triangle in _scene.objects.triangles:
		bytes += triangle.to_byte_array()

	# Fill rest of bytes with empty
	if triangle_buffer_size == 0:
		@warning_ignore("integer_division")
		triangle_buffer_size = (size / TRIANGLE_COUNT_STEP + 1) * TRIANGLE_COUNT_STEP

	for i in range(triangle_buffer_size - size):
		bytes += PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()

	return bytes


func _create_bvh_byte_array() -> PackedByteArray:
	if _scene.bvh:
		return _scene.bvh.to_byte_array()
	else:
		return PTBVHTree.new().to_byte_array()


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


	func _init() -> void:
		# Arrays need to be initialized with the same size as number of binds in a set
		image_set.resize(IMAGE_SET_MAX)
		camera_set.resize(CAMERA_SET_MAX)
		object_set.resize(OBJECT_SET_MAX)
		bvh_set.resize(BVH_SET_MAX)


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

		push_error("PT: Uniform index '%S' is invalid." % index)
		return []


	func set_uniform(set_index : int, bind_index : int, uniform : RDUniform) -> void:
		var uniform_set := get_set_uniforms(set_index)
		uniform_set[bind_index] = uniform
