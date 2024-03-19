
extends Node
# Can potentially be Refcounted

class_name PTWorkDispatcher

# Holds the uniforms that will be bound to a set
var uniform_sets = [
	{}, # For image
	{}, # For camera
	{}, # For objects
	{}, # For BVH
	{} # For flags
]
var RIDs_to_free = [] # array of RIDs that need to be freed when done with them.

var rd : RenderingDevice
var shader : RID
var pipeline : RID

var texture : Texture2DRD

var _scene : PTScene 

# Set / binding indices
var image_set_index := 0
var image_buffer_bind := 0
var image_size_bind := 1

var camera_set_index := 1
#var camera_bind := 0 # Depricated
var LOD_bind := 0 # For sample per pixel, bounce depth etc.

var object_set_index := 2
var materials_bind := 0
var spheres_bind := 1
var planes_bind := 2

var BVH_set_index := 3
var BVH_bind := 0

# For external messages like time and render mode flags
var external_set_index := 4
var flags_bind := 0

# Set RIDs
var image_set : RID
var camera_set : RID
var object_set : RID
var BVH_set : RID
var external_set : RID

# Buffer RIDS
var image_buffer : RID

var camera_buffer : RID
var LOD_buffer : RID

var material_buffer : RID
var sphere_buffer : RID
var plane_buffer : RID

var BVH_buffer : RID

var flags_buffer : RID
var random_buffer : RID

# Render variables
var render_width : int
var render_height : int

# Move to Renderer
var samples_per_pixel = 1
var max_default_depth = 8
var max_refraction_bounces = 8 

var is_rendering = true
var is_taking_picture = false

# Temp
var _image_render_time := 0
var _image_render_start

# Flags
var use_bvh := true
var show_bvh_depth := false # TODO FIX this

var scene_changed := !true

# Whether this instance is using a local RenderDevice
var is_local_renderer

var work_group_x : int
var work_group_y : int
var work_group_z : int

var _renderer

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
	# The image buffer used in compute and fragment shader
	image_buffer = _create_image_buffer()
	
	LOD_buffer = _create_uniform(
		_lod_byte_array(), rd, camera_set_index, LOD_bind
	)
	# List of materials
	material_buffer = _create_uniform(
		_create_materials(), rd, object_set_index, materials_bind
	)
	# One of the object lists, for spheres
	sphere_buffer = _create_uniform(
		_create_spheres(), rd, object_set_index, spheres_bind
	)
	# One of the object lists, for planes
	plane_buffer = _create_uniform(
		_create_planes(), rd, object_set_index, planes_bind
	)
	BVH_buffer = _create_uniform(
		_scene.BVHTree.to_byte_array(), rd, BVH_set_index, BVH_bind
	)
	flags_buffer = _create_uniform(
		_renderer.flags_to_byte_array(), rd, external_set_index, flags_bind
	)
	
	# Bind uniforms and sets
	# Get uniforms
	var image_uniforms = uniform_sets[image_set_index].values()
	var camera_uniform = uniform_sets[camera_set_index].values()
	var object_uniforms = uniform_sets[object_set_index].values()
	var BVH_uniforms = uniform_sets[BVH_set_index].values()
	var flags_uniforms = uniform_sets[external_set_index].values()

	# Bind uniforms to sets
	image_set = rd.uniform_set_create(image_uniforms, shader, image_set_index)
	camera_set = rd.uniform_set_create(camera_uniform, shader, camera_set_index)
	object_set = rd.uniform_set_create(object_uniforms, shader, object_set_index)
	BVH_set = rd.uniform_set_create(BVH_uniforms, shader, BVH_set_index)
	external_set = rd.uniform_set_create(flags_uniforms, shader, external_set_index)
	
	# Set texture RID for Canvas
	var material = _renderer.canvas.get_mesh().surface_get_material(0)
	
	texture = material.get_shader_parameter("image_buffer")
	texture.texture_rd_rid = image_buffer
	

func _process(delta):
	# TODO: Make loading bar
	# TODO: MAke able to take images with long render time
	# Takes picture
	if Input.is_key_pressed(KEY_X) and not is_taking_picture:
		# Make last changes to camera settings
		samples_per_pixel = 80
		max_default_depth = 16
		max_refraction_bounces = 16
		rd.buffer_update(LOD_buffer, 0, _lod_byte_array().size(), _lod_byte_array())
		
		## Currently disabled
		#is_taking_picture = true
		#is_rendering = false
		_image_render_start = Time.get_ticks_msec()
		
	# Don't send work when window is not focused
	if get_window() != null: # For some reason get_window can return null
		if get_window().has_focus() and is_rendering:
			create_compute_list()
		
	if is_taking_picture:
		render_image()


func _exit_tree():
	#if is_local_renderer:
	var image = rd.texture_get_data(image_buffer, 0)
	var new_image = Image.create_from_data(render_width, render_height, false,
										   Image.FORMAT_RGBAF, image)
										
	new_image.save_png("temp.png")
	
	free_RIDs()

func free_RIDs():
	# I don't understand garbage collection. Maybe this helps idk
	if texture:
		texture.texture_rd_rid = RID()
	
	# Frees uniforms, don't know if needed
	for dict in uniform_sets:
		for rid in dict.values():
			rd.free_rid(rid)

	# Frees buffers and shader RIDS
	for rid in RIDs_to_free:
		rd.free_rid(rid)


func create_compute_list(x := work_group_x, y := work_group_y, z := work_group_z):
	""" Creates the compute list required for every compute call 
	
	Requires workgroup coordinates to be given in an array or vector
	"""
	
	var push_bytes = _push_constant_byte_array()
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	
	# Bind uniform sets
	rd.compute_list_bind_uniform_set(compute_list, image_set, image_set_index)
	rd.compute_list_bind_uniform_set(compute_list, camera_set, camera_set_index)
	rd.compute_list_bind_uniform_set(compute_list, object_set, object_set_index)
	rd.compute_list_bind_uniform_set(compute_list, BVH_set, BVH_set_index)
	rd.compute_list_bind_uniform_set(compute_list, external_set, external_set_index)
	rd.compute_list_set_push_constant(compute_list, push_bytes, push_bytes.size())
	
	rd.capture_timestamp("Render Scene")
	rd.compute_list_dispatch(compute_list, x, y, z)
	
	# Sync is not required when using main RenderingDevice
	rd.compute_list_end()
	
	if is_local_renderer:
		rd.submit()
		rd.sync()
	

func set_scene(scene : PTScene):
	"""set this this PTWorkDispatcher to use specified scene data"""
	_scene = scene
	
	render_width = _scene.camera.render_width
	render_height = _scene.camera.render_height
	work_group_x = ceil(render_width / 8.)
	work_group_y = ceil(render_height / 8.)
	work_group_z = 1


func load_shader(shader_ : RDShaderSource):
	# Load GLSL shader
	# Was very annoying to find since this function is not mentioned anywhere
	#	in RDShaderSource documentation wrrr
	var shader_spirv: RDShaderSPIRV = rd.shader_compile_spirv_from_source(shader_)
	shader = rd.shader_create_from_spirv(shader_spirv)
	RIDs_to_free.append(shader)
	
	# Create a compute pipeline
	pipeline = rd.compute_pipeline_create(shader)


func render_image():
	"""Render image over time, possibly needed to be called multiple times"""
	
	var before = Time.get_ticks_msec()
	
	var finished_render = false
	
	
	create_compute_list()
	
	# CPU waits for texture data to be ready.
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
	
		samples_per_pixel = 1
		max_default_depth = 8
		max_refraction_bounces = 8
		rd.buffer_update(LOD_buffer, 0, _lod_byte_array().size(), _lod_byte_array())
		
		is_rendering = true
		is_taking_picture = false
	

func _create_uniform(bytes, render_device, set_, binding):
	"""Create and bind uniform to a shader from bytes.
	
	returns the uniform and buffer created in an array"""
	
	var buffer = render_device.storage_buffer_create(bytes.size(), bytes)
	RIDs_to_free.append(buffer)
	var uniform = RDUniform.new()
	
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = binding
	uniform.add_id(buffer)
	
	uniform_sets[set_][binding] = uniform
	
	return buffer


func _create_image_buffer():
	# Create image buffer for compute and fragment shader
	var tf : RDTextureFormat = RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	tf.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	tf.width = render_width
	tf.height = render_height
	tf.depth = 1
	tf.array_layers = 1
	tf.mipmaps = 1
	tf.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT + 
		RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT +
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT +
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT 
		# Remove bit for increased performance, have to add readonly to shader buffer
		+ RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	#if is_local_renderer:
		#tf.usage_bits += RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT 
	
	var new_image_buffer = rd.texture_create(tf, RDTextureView.new(), [])
	
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = image_buffer_bind
	uniform.add_id(new_image_buffer)
	
	uniform_sets[image_set_index][image_buffer_bind] = uniform
	
	return new_image_buffer


func _create_spheres():
	var bytes = PackedByteArray()
	if _scene.objects[PTObject.OBJECT_TYPE.SPHERE].size():
		for sphere in _scene.objects[PTObject.OBJECT_TYPE.SPHERE]:
			bytes += sphere.to_byte_array()
	else:
		bytes = PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()
	
	return bytes
	

func _create_planes():
	var bytes = PackedByteArray()
	if _scene.objects[PTObject.OBJECT_TYPE.PLANE].size():
		for plane in _scene.objects[PTObject.OBJECT_TYPE.PLANE]:
			bytes += plane.to_byte_array()
	else:
		bytes = PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()
	
	return bytes
	

func _create_materials():
	var bytes = PackedByteArray()
	if _scene.materials:
		for material in _scene.materials:
			bytes += material.to_byte_array()
			
	return bytes


func _update_sphere():
	var sphere = _scene.objects[PTObject.OBJECT_TYPE.SPHERE][0]
	sphere.center.x = sin(Time.get_ticks_msec() / 1000.)
	var bytes = sphere.to_byte_array()
	
	rd.buffer_update(sphere_buffer, 0, bytes.size(), bytes)
	

func _lod_byte_array():
	var lod_array = [render_width, render_height, samples_per_pixel, 
					 max_default_depth, max_refraction_bounces]
	return PackedInt32Array(lod_array).to_byte_array()


func _push_constant_byte_array():
	var bytes = PackedByteArray()
	
	bytes += _scene.camera.to_byte_array()
	bytes += PackedFloat32Array([Time.get_ticks_msec() / 1000.]).to_byte_array()
	
	# Filler
	bytes += PackedFloat32Array([0,0,0]).to_byte_array()
	
	return bytes


