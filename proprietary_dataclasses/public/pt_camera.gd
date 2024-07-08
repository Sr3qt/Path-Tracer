@tool
class_name PTCamera
extends Camera3D

## Controls rendering paramaters and position in 3D space
##
## Extends Camera3D for path traced rendering

# Semi-Temp
enum CameraSetting {none, top_down, corner, book_ex, center, left, right, middle, cornell}

const camera_settings_values := {
	CameraSetting.top_down : [Vector3(0, 8, -15), Vector3(0,0,-6), 106.],
	CameraSetting.corner : [Vector3(-11, 3, -11), Vector3(0,0,0), 106.],
	CameraSetting.book_ex : [Vector3(13, 2, 3), Vector3(0,0,0), 20 * 16 / 9.],
	CameraSetting.center : [Vector3(0, 0, 1), Vector3(0,0,0), 106.],
	CameraSetting.left : [Vector3(0, 0, 1), Vector3(-1,0,1), 106.],
	CameraSetting.right : [Vector3(0, 0, 1), Vector3(1,0,1), 106.],
	CameraSetting.middle : [Vector3(7, 2, -3), Vector3(0,0,0), 30 * 16 / 9.],
	CameraSetting.cornell : [Vector3(-1, 0.5, 0.5), Vector3(1,0.5,0.5), 106.0],
}

# Render variables
@export var aspect_ratio_x : int = 16
@export var aspect_ratio_y : int = 9
var aspect_ratio := float(aspect_ratio_x) / float(aspect_ratio_y)

@export var focal_length := 1.0
@export var gamma : float = 1.0 / 2.2

# Holds actual value of is_active
var _is_active := false

## Similar to the built-in property "current". If is_active, the PTScene this
## camera belongs to is using this camera.
var is_active : bool:
	get:
		return _is_active
	set(value):
		if is_instance_valid(_scene):
			if value and not _is_active:
				_scene.set_active_camera(self)
			elif not value and _is_active:
				_scene._change_camera()
		else:
			push_warning("PT: No scene is set for Camera: ", self)

# Whether any camera settings has changed
var camera_changed := false

# Viewport is the physical surface through which rays are initially cast
var viewport_width : float
var viewport_height : float

var right: Vector3:
	get: return transform.basis.x
var up: Vector3:
	get: return transform.basis.y
var forward: Vector3:
	get: return transform.basis.z

var _scene : PTScene


func _ready() -> void:
	# Find and add self to _scene
	if not is_instance_valid(_scene):
		_scene = PTObject.find_scene_ancestor(self)
		if is_instance_valid(_scene):
			_scene.add_camera(self)

	aspect_ratio = float(aspect_ratio_x) / float(aspect_ratio_y)
	set_viewport_size()

	set_notify_transform(true)


func _set(property : StringName, _value : Variant) -> bool:
	if property == "position":
		camera_changed = true

	if property == "fov":
		camera_changed = true

	return false


## NOTE: There might not be a difference between this and having a _set check
func _notification(what : int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED:
			camera_changed = true


func copy_camera(from : Camera3D) -> void:
	translate(position - from.position)

	transform = from.transform
	fov = from.fov

	set_viewport_size()


func set_viewport_size() -> void:
	var theta := deg_to_rad(fov)
	viewport_height = 2 * tan(theta / 2.) * focal_length
	# NOTE: Using the idealistic aspect ratio isn't technically correct, using
	#  the actual ratio between the render width and height should be prefered,
	#  however for simplicity the ideal aspect ratio is used
	viewport_width = viewport_height * aspect_ratio

	camera_changed = true


func set_camera_setting(cam : CameraSetting) -> void:
	var pos : Vector3 = camera_settings_values[cam][0] # UNSTATIC
	var look : Vector3 = camera_settings_values[cam][1] # UNSTATIC
	var _fov : float = camera_settings_values[cam][2] # UNSTATIC

	position = pos

	look_at(look)

	fov = _fov / aspect_ratio
	set_viewport_size()


func vector_to_array(vector : Vector3) -> Array[float]:
	return [vector.x, vector.y, vector.z]


func to_byte_array() -> PackedByteArray:
	var camera_array := (
			vector_to_array(position) + [focal_length] +
			vector_to_array(right) + [viewport_width] +
			vector_to_array(up) + [viewport_height] +
			vector_to_array(forward) + [gamma]
	)

	return (PackedFloat32Array(camera_array).to_byte_array())

