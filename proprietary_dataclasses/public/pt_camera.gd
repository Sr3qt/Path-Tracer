@tool
class_name PTCamera
extends Camera3D

""" Controls rendering paramaters and position in 3D space

Extends Camera3D for path traced rendering
"""

# Whether any camera settings has changed
var camera_changed := false

# Render variables
@export var aspect_ratio_x : int = 16
@export var aspect_ratio_y : int = 9
var aspect_ratio := float(aspect_ratio_x) / float(aspect_ratio_y)

@export var focal_length := 1.
@export var gamma : float = 1. / 2.2

# Viewport is the physical surface through which rays are initially cast 
var viewport_width : float
var viewport_height : float

var right: Vector3:
	get: return transform.basis.x
var up: Vector3:
	get: return transform.basis.y
var forward: Vector3:
	get: return transform.basis.z


func _ready():
	aspect_ratio = float(aspect_ratio_x) / float(aspect_ratio_y)
	set_viewport_size()
	
	set_notify_transform(true)


func _set(property, value):
	if property == "position":
		camera_changed = true
	
	if property == "fov":
		camera_changed = true
		

## NOTE: There might not be a difference between this and having a _set check
func _notification(what):
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			camera_changed = true


func set_viewport_size():
	var theta = deg_to_rad(fov)
	viewport_height = 2 * tan(theta / 2.) * focal_length
	# NOTE: Using the idealistic aspect ratio isn't technically correct, using 
	#  the actual ratio between the render width and height should be prefered,
	#  however for simplicity the ideal aspect ratio is used
	viewport_width = viewport_height * aspect_ratio
	
	camera_changed = true


func vector_to_array(vector):
	return [vector.x, vector.y, vector.z]


func to_byte_array() -> PackedByteArray:
	var camera_array = (vector_to_array(position) + [focal_length] + 
						vector_to_array(right) + [viewport_width] + 
						vector_to_array(up) + [viewport_height] + 
						vector_to_array(forward) + [gamma])
	
	return (PackedFloat32Array(camera_array).to_byte_array())
	
