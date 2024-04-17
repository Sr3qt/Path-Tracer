class_name PTWorkDispatcher
extends Node
# Can potentially be Refcounted


# Holds the uniforms that will be bound to a set
var uniform_sets = [
	{}, # For image
	{}, # For camera
	{}, # For objects
	{}, # For BVH
	{}, # Empty
]
var RIDs_to_free = [] # array of RIDs that need to be freed when done with them.
var set_RIDs = []

var rd : RenderingDevice
var shader : RID
var pipeline : RID

var texture : Texture2DRD

# Set / binding indices
var image_set_index := 0
var image_buffer_bind := 0
var image_size_bind := 1

var camera_set_index := 1
var LOD_bind := 0 # For sample per pixel, bounce depth etc.

var object_set_index := 2
var materials_bind := 0
var spheres_bind := 1
var planes_bind := 2

var BVH_set_index := 3
var BVH_bind := 0

# Set RIDs
var image_set : RID
var camera_set : RID
var object_set : RID
var BVH_set : RID

# Buffer RIDS
var image_buffer : RID

var camera_buffer : RID
var LOD_buffer : RID

var material_buffer : RID
var sphere_buffer : RID
var plane_buffer : RID

var BVH_buffer : RID

# Whether this instance is using a local RenderDevice
var is_local_renderer

# References to renderer and scene that will render
var _renderer : PTRenderer
var _scene : PTScene 


func _init(renderer : PTRenderer, is_local = false):
	_renderer = renderer
	
	is_local_renderer = is_local
	
	if is_local_renderer:
		rd = RenderingServer.create_local_rendering_device()
	else:
		# Holy merge clutch https://github.com/godotengine/godot/pull/79288 
		# RenderingDevice for realtime rendering
		rd = RenderingServer.get_rendering_device()


func create_buffers():
	"""Creates and binds buffers to RenderDevice"""
	
	print("Starting to setup buffers")
	var prev_time = Time.get_ticks_usec()
	
	# Trying to set up buffers without a scene makes no sense
	if not _scene:
		print("Set a scene to the Renderer before trying to create gpu buffers.")
		return
	
	# The image buffer used in compute and fragment shader
	image_buffer = _create_image_buffer()
	
	LOD_buffer = _create_uniform(
			_create_lod_byte_array(), camera_set_index, LOD_bind
	)
	# List of materials
	material_buffer = _create_uniform(
			_create_materials_byte_array(), object_set_index, materials_bind
	)
	# One of the object lists, for spheres
	sphere_buffer = _create_uniform(
			_create_spheres_byte_array(), object_set_index, spheres_bind
	)
	# One of the object lists, for planes
	plane_buffer = _create_uniform(
			_create_planes_byte_array(), object_set_index, planes_bind
	)
	
	create_bvh_buffer()
	
	bind_sets()
	
	# Set texture RID for Canvas
	var material = _renderer.canvas.get_mesh().surface_get_material(0)
	
	texture = material.get_shader_parameter("image_buffer")
	texture.texture_rd_rid = image_buffer
	
	print("Setting up buffers took %s ms" % ((Time.get_ticks_usec() - prev_time) / 1000.))
	

func bind_sets():
	# Bind uniforms and sets
	# Get uniforms
	var image_uniforms = uniform_sets[image_set_index].values()
	var camera_uniform = uniform_sets[camera_set_index].values()
	var object_uniforms = uniform_sets[object_set_index].values()
	var BVH_uniforms = uniform_sets[BVH_set_index].values()

	# Bind uniforms to sets
	image_set = rd.uniform_set_create(image_uniforms, shader, image_set_index)
	camera_set = rd.uniform_set_create(camera_uniform, shader, camera_set_index)
	object_set = rd.uniform_set_create(object_uniforms, shader, object_set_index)
	BVH_set = rd.uniform_set_create(BVH_uniforms, shader, BVH_set_index)


func load_shader(shader_ : RDShaderSource):
	# Load GLSL shader
	# Was very annoying to find since this function is not mentioned anywhere
	#	in RDShaderSource documentation wrrr
	var shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_)
	shader = rd.shader_create_from_spirv(shader_spirv)
	RIDs_to_free.append(shader)
	
	# Create a compute pipeline
	pipeline = rd.compute_pipeline_create(shader)


func free_RIDs():
	if texture:
		texture.texture_rd_rid = RID()

	# Frees buffers and shader RIDS
	for rid in RIDs_to_free:
		rd.free_rid(rid)
		
	# TODO when RIDs are freed, remember to remove them from the arrays


func create_compute_list(window : PTRenderWindow = null):
	""" Creates the compute list required for every compute call 
	
	Requires workgroup coordinates to be given in an array or vector
	"""
	
	# By default, will dispatch groups to fill whole render size
	if window == null:
		window = PTRenderWindow.new()
		
		window.work_group_width = ceili(_renderer.render_width / 
										_renderer.compute_invocation_width)
		window.work_group_height = ceili(_renderer.render_height / 
										_renderer.compute_invocation_height)
		window.work_group_depth = 1
	
	var x = window.work_group_width
	var y = window.work_group_height
	var z = window.work_group_depth
	
	var push_bytes = _push_constant_byte_array(window)
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	
	# Bind uniform sets
	rd.compute_list_bind_uniform_set(compute_list, image_set, image_set_index)
	rd.compute_list_bind_uniform_set(compute_list, camera_set, camera_set_index)
	rd.compute_list_bind_uniform_set(compute_list, object_set, object_set_index)
	rd.compute_list_bind_uniform_set(compute_list, BVH_set, BVH_set_index)
	rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())
	
	rd.capture_timestamp(window.render_name)
	rd.compute_list_dispatch(compute_list, x, y, z)
	
	rd.compute_list_end()
	
	# Sync is not required when using main RenderingDevice
	if is_local_renderer:
		rd.submit()
		rd.sync()
	

func set_scene(scene : PTScene):
	"""set this this PTWorkDispatcher to use specified scene data"""
	_scene = scene
	

func render_image():
	"""Render image over time, possibly needed to be called multiple times"""
	
	var before = Time.get_ticks_msec()
	
	var finished_render = false
	
	#create_compute_list()
	
	# CPU waits for texture data to be ready.
	# TODO Find a way for the cpu to wait for buffer access
	var before_render = Time.get_ticks_msec()
	
	if finished_render:
		#var image = rd.texture_get_data(image_buffer, 0)
		var after_render = Time.get_ticks_msec()
		
		#var new_image = Image.create_from_data(render_width, render_height, false,
											   #Image.FORMAT_RGBAF, image)
											#
		#
		#var folder_path = "res://renders/temps/" + Time.get_date_string_from_system()
		#
		## Make folder for today if it doesnt exist
		#if not DirAccess.dir_exists_absolute(folder_path):
			#DirAccess.make_dir_absolute(folder_path)
		#
		#new_image.save_png(folder_path + "/temp-" +
		#Time.get_datetime_string_from_system().replace(":", "-") + ".png")
		
		print("---------------------------------------")
		print("Render time: " + str(after_render - before_render) + " ms")
		print("Total time: " + str(Time.get_ticks_msec() - before) + " ms")
		print("---------------------------------------")
	
		#samples_per_pixel = 1
		#max_default_depth = 8
		#max_refraction_bounces = 8
		var byte_array = _create_lod_byte_array()
		rd.buffer_update(LOD_buffer, 0, byte_array.size(), byte_array)


func create_bvh_buffer():
	# Contains the BVH tree in the form of a list
	BVH_buffer = _create_uniform(
			_create_bvh_byte_array(), BVH_set_index, BVH_bind
	)
	

func _create_uniform(bytes : PackedByteArray, _set : int, binding : int) -> RID:
	"""Create and bind uniform to a shader from bytes.
	
	returns the uniform and buffer created in an array"""
	
	var buffer : RID = rd.storage_buffer_create(bytes.size(), bytes)
	RIDs_to_free.append(buffer)
	var uniform = RDUniform.new()
	
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	
	uniform_sets[_set][binding] = uniform
	
	return buffer


func _create_image_buffer():
	"""Creates and binds render result texture buffer aka. image_buffer"""
	var usage_bits = (
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
	var new_image_buffer = _create_texture_buffer(
		RenderingDevice.TEXTURE_TYPE_2D,
		_renderer.render_width, 
		_renderer.render_height,
		[],
		1,
		usage_bits
	)
	
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = image_buffer_bind
	uniform.add_id(new_image_buffer)
	
	uniform_sets[image_set_index][image_buffer_bind] = uniform
	
	return new_image_buffer


func _create_texture_buffer(
	texture_type,
	width : int,
	height : int,
	data : PackedByteArray,
	array_layers : int,
	usage_bits : int):
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
	
	var new_texture_buffer = rd.texture_create(tf, RDTextureView.new(), data)
	RIDs_to_free.append(new_texture_buffer)
	
	return new_texture_buffer


func _create_lod_byte_array() -> PackedByteArray:
	var lod_array = [
		_renderer.render_width, 
		_renderer.render_height, 
		_renderer.samples_per_pixel, 
		_renderer.max_default_depth, 
		_renderer.max_refraction_bounces
	]
	return PackedInt32Array(lod_array).to_byte_array()


func _create_materials_byte_array() -> PackedByteArray:
	var bytes = PackedByteArray()
	if _scene.materials:
		for material in _scene.materials:
			bytes += material.to_byte_array()
			
	return bytes


func _create_spheres_byte_array() -> PackedByteArray:
	var bytes = PackedByteArray()
	if _scene.objects[PTObject.ObjectType.SPHERE].size():
		for sphere in _scene.objects[PTObject.ObjectType.SPHERE]:
			bytes += sphere.to_byte_array()
	else:
		bytes = PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()
	
	return bytes
	

func _create_planes_byte_array() -> PackedByteArray:
	var bytes = PackedByteArray()
	if _scene.objects[PTObject.ObjectType.PLANE].size():
		for plane in _scene.objects[PTObject.ObjectType.PLANE]:
			bytes += plane.to_byte_array()
	else:
		bytes = PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()
	
	return bytes
	

func _push_constant_byte_array(window : PTRenderWindow) -> PackedByteArray:
	var bytes = PackedByteArray()
	
	bytes += _scene.camera.to_byte_array()
	# A higher divisor seems to give a more volatile local noise
	#  If set to low, refractive materials might not multisample correctly
	var divisor = 100_000.0
	var time = Time.get_ticks_msec() / divisor
	
	bytes += PackedFloat32Array([time]).to_byte_array()
	bytes += window.flags_to_byte_array()
	bytes += PackedInt32Array([window.x_offset, window.y_offset]).to_byte_array()
	bytes += PackedFloat32Array([window.frame, 0, 0, 0]).to_byte_array()
	
	return bytes
	

func _create_bvh_byte_array() -> PackedByteArray:
	if _scene.bvh:
		return _scene.bvh.to_byte_array()
	else:
		return PTBVHTree.new().to_byte_array()



