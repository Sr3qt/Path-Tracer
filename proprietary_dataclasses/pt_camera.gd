@tool
extends Node

class_name PTCamera

# Whether the camera should react to button presses and mouse movements
#  NOTE: currently not implemented
var is_fps := true

# Relative root node in plugin instance
var root_node 
var freeze := true # For plugin

var mouse_sensitivity_x := 0.01
var mouse_sensitivity_y := 0.01
var move_speed := 3.5

# Render variables
# TODO make variables exportable to editor or changable during run time. move to PTRENDEREr
var aspect_ratio := 16. / 9.
var render_width := 1920
var render_height := int(render_width / aspect_ratio)

var focal_length := 1.
var hfov := 106. # In degrees
var vfov := hfov / aspect_ratio
var gamma = 1. / 2.2

# Viewport is the physical surface through which rays are initially cast 
var viewport_width : float
var viewport_height : float

var camera_pos : Vector3
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

func _init(
	pos := Vector3(0,0,0), 
	looking_at := Vector3(0,0,-1), 
	aspect_ratio_ : float = aspect_ratio, 
	resolution_width : int = render_width, 
	horizontal_fov : float = hfov, 
	focal_length_ : float = focal_length
	):
	camera_pos = pos
	look_at(looking_at)
	
	aspect_ratio = aspect_ratio_
	render_width = resolution_width
	render_height = int(render_width / aspect_ratio)
	
	focal_length = focal_length_
	hfov = horizontal_fov
	vfov = hfov / aspect_ratio
	
	set_viewport_size()
	
	camera_changed = false


func _ready():
	root_node = get_parent().get_parent().root_node
	
	if root_node:
		root_node.connect("gui_input", _input)
	

func _process(delta):
	
	if not Engine.is_editor_hint() or (root_node and root_node.visible and not freeze):
		# MOve to player ndoe
		if Input.is_key_pressed(KEY_W):
			move_camera(-forward * Vector3(1,0,1) * move_speed * delta)
		if Input.is_key_pressed(KEY_A):
			move_camera(-right * Vector3(1,0,1) * move_speed * delta)
		if Input.is_key_pressed(KEY_S):
			move_camera(forward * Vector3(1,0,1) * move_speed * delta)
		if Input.is_key_pressed(KEY_D):
			move_camera(right * Vector3(1,0,1) * move_speed * delta)

# MOve to player ndoe
func _input(event):
	if event is InputEventMouseMotion and event.button_mask & 1:
		# modify accumulated mouse rotation
		var rot_x = event.relative.x * mouse_sensitivity_x
		var rot_y = event.relative.y * mouse_sensitivity_y
		var transform = Transform3D()
		transform = transform.rotated(Vector3(0,1,0), rot_x).rotated(right, rot_y)
		
		rotate_camera(transform)

func set_viewport_size():
	var theta = deg_to_rad(hfov)
	viewport_width = 2 * tan(theta / 2.) * focal_length
	viewport_height = viewport_width * (float(render_height) / float(render_width))
	
	camera_changed = true


func look_at(point : Vector3):
	forward = (camera_pos - point).normalized()
	
	right = Vector3(0, 1, 0).cross(forward).normalized()
	up = forward.cross(right).normalized()
	
	camera_changed = true
	

func rotate_camera(transform : Transform3D):
	view_vectors *= transform
	
	right = view_vectors[0].normalized()
	up = view_vectors[1].normalized()
	forward = view_vectors[2].normalized()
	
	camera_changed = true
	

func move_camera(vector : Vector3):
	camera_pos += vector
	
	camera_changed = true


func vec2array(vector):
	return [vector.x, vector.y, vector.z]


func to_byte_array():
	var camera_array = (vec2array(camera_pos) + [focal_length] + 
						vec2array(right) + [viewport_width] + 
						vec2array(up) + [viewport_height] + 
						vec2array(forward) + [gamma])
	
	return (PackedFloat32Array(camera_array).to_byte_array())
	










