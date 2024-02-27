extends Node

# Holds the uniforms that will be bound to a set
var uniform_sets = [
	{}, # For image
	{}  # For camera
]
var RIDs_to_free = [] # array of RIDs that need to be freed when done with them.

var rd
var shader

var mouse_sensitivity_x := 0.01
var mouse_sensitivity_y := 0.01
var move_speed := 0.1

# Set / binding indices
var image_set_index := 0
var image_buffer_bind := 0
var image_size_bind := 1

var camera_set_index := 1
var camera_bind := 0

# Set RIDs
var image_set
var camera_set

# Buffer RIDS
var camera_buffer
var image_buffer


# Render variables
var aspect_ratio := 16. / 9.
var render_width := 640 * 3
var render_height := int(render_width / aspect_ratio)

var focal_length := 1.
var viewport_width := 4.
var viewport_height := viewport_width * (float(render_height) / float(render_width))

var camera_pos := Vector3(0,0,0)
var view_vectors := PackedVector3Array([Vector3(1,0,0), Vector3(0,1,0), Vector3(0,0,1)])
var right: Vector3:
	get: return view_vectors[0]
	set(value): view_vectors.set(0, value)
var up: Vector3:
	get: return view_vectors[1]
	set(value): view_vectors.set(1, value)
var forward: Vector3:
	get: return view_vectors[2]
	set(value): view_vectors.set(2, value)
	
var camera_changed := false


func _ready():
	
	get_window().position = Vector2(1100, 400)
	# Create a local rendering device.
	rd = RenderingServer.create_local_rendering_device()

	# Load GLSL shader
	var shader_file = load("res://ray_tracer.comp.glsl")
	var shader_spirv: RDShaderSPIRV = shader_file.get_spirv()
	shader = rd.shader_create_from_spirv(shader_spirv)
	RIDs_to_free.append(shader)

	# SET DATA BUFFERS
	# ================

	# Viewport
	var size_bytes := PackedInt32Array([render_width, render_height]).to_byte_array()

	var image_array = PackedColorArray()
	image_array.resize(render_width * render_height)
	var image_bytes := image_array.to_byte_array()

	image_buffer = _create_uniform(image_bytes, rd, image_set_index, image_buffer_bind)
	var size_buffer = _create_uniform(size_bytes, rd, image_set_index, image_size_bind)

	var camera_bytes = _create_camera_bytes()

	camera_buffer = _create_uniform(camera_bytes, rd, camera_set_index, camera_bind)


	# BIND UNIFORMS AND SETS
	# ======================

	# Get uniforms
	var camera_uniform = uniform_sets[camera_set_index].values()
	var image_uniforms = uniform_sets[image_set_index].values()

	# Bind uniforms to sets
	image_set = rd.uniform_set_create(image_uniforms, shader, image_set_index)
	camera_set = rd.uniform_set_create(camera_uniform, shader, camera_set_index)

	RIDs_to_free.append(image_set)
	RIDs_to_free.append(camera_set)


func _process(delta):
	
	if Input.is_key_pressed(KEY_W):
		move_camera(-forward * Vector3(1,0,1) * move_speed)
	elif Input.is_key_pressed(KEY_A):
		move_camera(-right * Vector3(1,0,1) * move_speed)
	elif Input.is_key_pressed(KEY_S):
		move_camera(forward * Vector3(1,0,1) * move_speed)
	elif Input.is_key_pressed(KEY_D):
		move_camera(right * Vector3(1,0,1) * move_speed)
	
	
	
	
	_create_compute_list()
	
	var before = Time.get_ticks_usec()
	
	# Submit to GPU and wait for sync
	rd.submit()
	rd.sync()
	
	var frametime = (Time.get_ticks_usec() - before) / 1000.
	var fps = 1000 / frametime
	print(str(frametime) + " ms, FPS: " + str(fps))
	update_image_buffer()


# MOve to player ndoe
func _input(event):
	if event is InputEventMouseMotion and event.button_mask & 1:
		# modify accumulated mouse rotation
		var rot_x = event.relative.x * mouse_sensitivity_x
		var rot_y = event.relative.y * mouse_sensitivity_y
		var transform = Transform3D()
		transform = transform.rotated(Vector3(0,1,0), rot_x).rotated(right, rot_y)
		
		rotate_camera(transform)


func _exit_tree():
	
	var image = rd.buffer_get_data(image_buffer)
	var new_image = Image.create_from_data(render_width, render_height, false,
										   Image.FORMAT_RGBAF, image)
										
	new_image.save_png("temp.png")


func vector2array(vector):
	return [vector.x, vector.y, vector.z]


func _create_camera_bytes():
	var camera_array = (vector2array(camera_pos) + 
						[focal_length] + vector2array(right) + 
						[viewport_width] + vector2array(up) + 
						[viewport_height] + vector2array(forward))
	
	return (PackedFloat32Array(camera_array).to_byte_array())


func _create_compute_list():
	
	if camera_changed:
		var new_bytes = _create_camera_bytes()
		rd.buffer_update(camera_buffer, 0, new_bytes.size(), new_bytes)
		camera_changed = false
	
	# Create a compute pipeline
	var pipeline = rd.compute_pipeline_create(shader)
	RIDs_to_free.append(pipeline)
	
	var compute_list = rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
	
	# Bind uniform sets
	rd.compute_list_bind_uniform_set(compute_list, image_set, image_set_index)
	rd.compute_list_bind_uniform_set(compute_list, camera_set, camera_set_index)
	
	rd.compute_list_dispatch(compute_list, ceil(render_width / 8.), ceil(render_height / 8.), 1)
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


func update_image_buffer():
	""" Update image texture for canvas """
	
	var image = rd.buffer_get_data(image_buffer)
	var new_image = Image.create_from_data(render_width, render_height, false,
										   Image.FORMAT_RGBAF, image)
	
	var canvas = get_node("/root/Node3D/Camera3D/Canvas")
	var material = canvas.get_mesh().surface_get_material(0)
	var image_texture = ImageTexture.create_from_image(new_image)
	
	material.set_shader_parameter("image_buffer", image_texture)


func rotate_camera(transform : Transform3D):
	view_vectors *= transform
	
	right = view_vectors[0].normalized()
	up = view_vectors[1].normalized()
	forward = view_vectors[2].normalized()
	
	camera_changed = true
	

func move_camera(vector : Vector3):
	camera_pos += vector
	
	camera_changed = true

# I don't understand garbage collection. Maybe this helps idk
#func _exit_tree():
#	for dict in uniform_sets:
#		for rid in dict.values():
#			rd.free_rid(rid)
#
#
#	for rid in RIDs_to_free:
#		rd.free_rid(rid)






