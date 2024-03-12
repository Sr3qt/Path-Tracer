extends Node

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

var scene : PTScene 

# Set / binding indices
var image_set_index := 0
var image_buffer_bind := 0
var image_size_bind := 1

var camera_set_index := 1
var camera_bind := 0
var LOD_bind := 1 # For sample per pixel, bounce depth etc.

var object_set_index := 2
var materials_bind := 0
var spheres_bind := 1
var planes_bind := 2

var BVH_set_index := 3
var BVH_bind := 0

# REnder modes, like bvh heat map
var flags_set_index := 4
var flags_bind := 0

# Set RIDs
var image_set : RID
var camera_set : RID
var object_set : RID
var BVH_set : RID
var flags_set : RID

# Buffer RIDS
var image_buffer : RID

var camera_buffer : RID
var LOD_buffer : RID

var sphere_buffer : RID
var plane_buffer : RID

var BVH_buffer : RID

var flags_buffer : RID

# Render variables
var aspect_ratio := 16. / 9.
# Render resolution
var render_width := 640 * 3
var render_height := int(render_width / aspect_ratio)

var focal_length := 1.

var samples_per_pixel = 16
var max_default_depth = 8
var max_refraction_bounces = 8 

var is_rendering = true


@onready var camera := PTCamera.new(
	Vector3(0,0,2), 
	Vector3(0,0,1),
	16. / 9.,
	render_width,
	106.,
	focal_length)

func _ready():
	
	get_window().position = Vector2(1200, 400)
	# Holy merge clutch https://github.com/godotengine/godot/pull/79288 
	# RenderingDevice for realtime rendering
	rd = RenderingServer.get_rendering_device()
	
	# Load GLSL shader
	var shader_file = load("res://ray_tracer.comp.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	RIDs_to_free.append(shader)
	
	# Create a compute pipeline
	pipeline = rd.compute_pipeline_create(shader)
	
	# Load scene with spheres
	scene = PTScene.load_scene("res://sphere_scene1.txt")
	
	# SET DATA BUFFERS
	# ================
	# The image buffer used in compute and fragment shader
	image_buffer = _create_image_buffer()
	#render_height /= 2
	#render_width /= 2
	
	# Viewport size
	var size_bytes := PackedInt32Array([render_width, render_height]).to_byte_array()
	var _size_buffer = _create_uniform(size_bytes, rd, image_set_index, image_size_bind)
	
	# Camera data
	camera_buffer = _create_uniform(camera.to_byte_array(), rd, camera_set_index, 
	camera_bind)
	
	LOD_buffer = _create_uniform(lod_byte_array(), rd, camera_set_index, 
	LOD_bind)
	
	# One of the object lists, for spheres
	sphere_buffer = _create_uniform(_create_spheres(), rd, object_set_index, 
	spheres_bind)
	# One of the object lists, for planes
	plane_buffer = _create_uniform(_create_planes(), rd, object_set_index, 
	planes_bind)
	
	scene.create_BVH()
	BVH_buffer = _create_uniform(scene.BVHTree.to_byte_array(), rd, 
	BVH_set_index, BVH_bind)
	
	flags_buffer = _create_uniform(_create_planes(), rd, flags_set_index, 
	flags_bind)
	
	# BIND UNIFORMS AND SETS
	# ======================
	# Get uniforms
	var image_uniforms = uniform_sets[image_set_index].values()
	var camera_uniform = uniform_sets[camera_set_index].values()
	var object_uniforms = uniform_sets[object_set_index].values()
	var BVH_uniforms = uniform_sets[BVH_set_index].values()
	var flags_uniforms = uniform_sets[flags_set_index].values()

	# Bind uniforms to sets
	image_set = rd.uniform_set_create(image_uniforms, shader, image_set_index)
	camera_set = rd.uniform_set_create(camera_uniform, shader, camera_set_index)
	object_set = rd.uniform_set_create(object_uniforms, shader, object_set_index)
	BVH_set = rd.uniform_set_create(BVH_uniforms, shader, BVH_set_index)
	flags_set = rd.uniform_set_create(flags_uniforms, shader, flags_set_index)
	
	# Set texture RID for Canvas
	var canvas = get_node("/root/Node3D/Camera3D/Canvas")
	var material = canvas.get_mesh().surface_get_material(0)
	
	texture = material.get_shader_parameter("image_buffer")
	texture.texture_rd_rid = image_buffer
	

func _process(delta):
	#var fps = 1. / delta
	#DisplayServer.window_set_title(str(fps)) 
	#print(str(delta * 1000) + " ms, FPS: " + str(fps))
	
	camera._process(delta)
	
	#if is_rendering:
	_create_compute_list()


func _input(event):
	camera._input(event)
	
	if Input.is_key_pressed(KEY_X):
		var before = Time.get_ticks_msec()
		
		samples_per_pixel = 512
		rd.buffer_update(LOD_buffer, 0, lod_byte_array().size(), lod_byte_array())
		
		_create_compute_list()
		
		var image = rd.texture_get_data(image_buffer, 0)
		var new_image = Image.create_from_data(render_width, render_height, false,
											   Image.FORMAT_RGBAF, image)
											
		new_image.save_png("res://renders/temps/temp-" +
		Time.get_datetime_string_from_system().replace(":", "-") + ".png")
		
		print("Total time " + str(Time.get_ticks_msec() - before) + " ms")
		
		samples_per_pixel = 16
		rd.buffer_update(LOD_buffer, 0, lod_byte_array().size(), lod_byte_array())

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


func _create_compute_list():
	""" Creates the compute list required for every compute call """
	if camera.camera_changed:
		var new_bytes = camera.to_byte_array()
		rd.buffer_update(camera_buffer, 0, new_bytes.size(), new_bytes)
		#camera.camera_changed = false
	
	#_update_sphere()
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	
	# Bind uniform sets
	rd.compute_list_bind_uniform_set(compute_list, image_set, image_set_index)
	rd.compute_list_bind_uniform_set(compute_list, camera_set, camera_set_index)
	rd.compute_list_bind_uniform_set(compute_list, object_set, object_set_index)
	rd.compute_list_bind_uniform_set(compute_list, BVH_set, BVH_set_index)
	rd.compute_list_bind_uniform_set(compute_list, flags_set, flags_set_index)
	
	rd.capture_timestamp("Render Scene")
	rd.compute_list_dispatch(compute_list, ceil(render_width / 8.), 
										   ceil(render_height / 8.), 1)
										
	# Sync is not required when using main RenderingDevice
	rd.compute_list_end()
	

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
		# Remove bit for increased performance
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
	if scene.objects[PTObject.OBJECT_TYPE.SPHERE].size():
		for sphere in scene.objects[PTObject.OBJECT_TYPE.SPHERE]:
			bytes += sphere.to_byte_array()
	else:
		bytes = PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()
	
	return bytes
	

func _create_planes():
	var bytes = PackedByteArray()
	if scene.objects[PTObject.OBJECT_TYPE.PLANE].size():
		for plane in scene.objects[PTObject.OBJECT_TYPE.PLANE]:
			bytes += plane.to_byte_array()
	else:
		bytes = PackedFloat32Array([0,0,0,0,0,0,0,0]).to_byte_array()
	
	return bytes

func _update_sphere():
	var sphere = scene.objects[PTObject.OBJECT_TYPE.SPHERE][0]
	sphere.center.x = sin(Time.get_ticks_msec() / 1000.)
	var bytes = sphere.to_byte_array()
	
	rd.buffer_update(sphere_buffer, 0, bytes.size(), bytes)
	

func lod_byte_array():
	var lod_array = [samples_per_pixel, max_default_depth, max_refraction_bounces]
	return PackedInt32Array(lod_array).to_byte_array()

