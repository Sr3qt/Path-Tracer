extends Node

# Holds the uniforms that will be bound to a set
var uniform_sets = [
	{}, # For image
	{}, # For camera
	{}, # For objects
	{}, # For image preview
	{} # For BVH
]
var RIDs_to_free = [] # array of RIDs that need to be freed when done with them.

var rd : RenderingDevice
var shader : RID
var pipeline : RID

var texture : Texture2DRD

var objects_dict
var material_list

# Set / binding indices
var image_set_index := 0
var image_buffer_bind := 0
var image_size_bind := 1

var camera_set_index := 1
var camera_bind := 0

var object_set_index := 2
var materials_bind := 0
var spheres_bind := 1

var BVH_set_index := 4
var BVH_bind := 0

# Set RIDs
var image_set : RID
var camera_set : RID
var object_set : RID
var BVH_set : RID

# Buffer RIDS
var camera_buffer : RID
var image_buffer : RID
var sphere_buffer : RID
var BVH_buffer : RID

# Render variables
var aspect_ratio := 16. / 9.
var render_width := 640 * 3
var render_height := int(render_width / aspect_ratio)

var focal_length := 1.


@onready var camera := PTCamera.new(Vector3(0,0,0), Vector3(0,0,1))

func _ready():
	
	get_window().position = Vector2(1100, 400)
	# Create a local rendering device.
#	rd = RenderingServer.create_local_rendering_device()
	# Holy merge clutch https://github.com/godotengine/godot/pull/79288 
	rd = RenderingServer.get_rendering_device()
	

	# Load GLSL shader
	var shader_file = load("res://ray_tracer.comp.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	RIDs_to_free.append(shader)
	
	# Create a compute pipeline
	pipeline = rd.compute_pipeline_create(shader)
	
	var mtl_and_object_list = PTObject.read_PTobject_file("res://sphere_scene1.txt") 
	material_list = mtl_and_object_list[0]
	objects_dict = mtl_and_object_list[1]
	
	var temp = PTBVHTree.new()
	temp.create_BVH_List([objects_dict[PTObject.OBJECT_TYPE.SPHERE]])
	print(temp)
	
	# SET DATA BUFFERS
	# ================
	# The image buffer used in compute and fragment shader
	image_buffer = _create_image_buffer()
	
	# Viewport size
	var size_bytes := PackedInt32Array([render_width, render_height]).to_byte_array()
	var size_buffer = _create_uniform(size_bytes, rd, image_set_index, image_size_bind)
	
	# Camera data
	camera_buffer = _create_uniform(camera.to_byte_array(), rd, camera_set_index, camera_bind)
	
	# One of the object lists, for spheres
	sphere_buffer = _create_uniform(_create_spheres(), rd, object_set_index, spheres_bind)
	
	BVH_buffer = _create_uniform(_create_empty_BVHNode_array(), rd, 
	BVH_set_index, BVH_bind)
	
	# BIND UNIFORMS AND SETS
	# ======================

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
	
	# Set texture RID for Canvas
	var canvas = get_node("/root/Node3D/Camera3D/Canvas")
	var material = canvas.get_mesh().surface_get_material(0)
	
	texture = material.get_shader_parameter("image_buffer")
	texture.texture_rd_rid = image_buffer
	

func _process(delta):
	var fps = 1. / delta
	#print(str(delta * 1000) + " ms, FPS: " + str(fps))
	
	camera._process(delta)
	
	# Sync is not required when using main RenderingDevice
	_create_compute_list()
	
	#print_gpu_performance()


func _input(event):
	camera._input(event)
	

func _exit_tree():
	var image = rd.texture_get_data(image_buffer, 0)
	var new_image = Image.create_from_data(render_width, render_height, false,
										   Image.FORMAT_RGBAF, image)
										
	new_image.save_png("temp.png")
	
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


func _create_empty_BVHNode_array():
	var max_children = 2
	
	var array_length = 100 # IDK
	
	var bytes_per_node = max_children * 16 + 32 + 16 
	var total_bytes = bytes_per_node * array_length
	var new_bytes = PackedByteArray()
	new_bytes.resize(total_bytes)
	new_bytes.fill(0)
	
	print("Made a BVH array with a size of " + str(total_bytes) + " bytes.")
	return new_bytes


func _create_compute_list():
	""" Creates the compute list required for every compute call """
	if camera.camera_changed:
		var new_bytes = camera.to_byte_array()
		rd.buffer_update(camera_buffer, 0, new_bytes.size(), new_bytes)
		camera.camera_changed = false
	
	_update_sphere()
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	
	# Bind uniform sets
	rd.compute_list_bind_uniform_set(compute_list, image_set, image_set_index)
	rd.compute_list_bind_uniform_set(compute_list, camera_set, camera_set_index)
	rd.compute_list_bind_uniform_set(compute_list, object_set, object_set_index)
	rd.compute_list_bind_uniform_set(compute_list, BVH_set, BVH_set_index)
	
	rd.capture_timestamp("Render Scene")
	rd.compute_list_dispatch(compute_list, ceil(render_width / 8.), 
										   ceil(render_height / 8.), 1)
	rd.compute_list_end()
	


func print_gpu_performance():
	for i in range(1, rd.get_captured_timestamps_count()):
		var start_name = rd.get_captured_timestamp_name(i - 1)
		var end_name = rd.get_captured_timestamp_name(i)
		# Docs says this returns time in microseconds since start, looks more 
		#	like nanoseconds though
		var start_time = rd.get_captured_timestamp_gpu_time(i - 1)
		var end_time = rd.get_captured_timestamp_gpu_time(i)
		print("Time between " + start_name + " and " + end_name + " is: 
	" + str((end_time - start_time) / 1_000_000.) + " ms")

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
		RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT +
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	
	var new_image_buffer = rd.texture_create(tf, RDTextureView.new(), [])
	
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	uniform.binding = image_buffer_bind
	uniform.add_id(new_image_buffer)
	
	uniform_sets[image_set_index][image_buffer_bind] = uniform
	
	return new_image_buffer


func _create_spheres():
	
	var bytes = PackedByteArray()
	for sphere in objects_dict[PTObject.OBJECT_TYPE.SPHERE]:
		bytes += sphere.to_byte_array()
	
	return bytes
	

func _update_sphere():
	var sphere = objects_dict[PTObject.OBJECT_TYPE.SPHERE][0]
	sphere.center.x = sin(Time.get_ticks_msec() / 1000.)
	var bytes = sphere.to_byte_array()
	
	rd.buffer_update(sphere_buffer, 0, bytes.size(), bytes)
	





