@tool
class_name PTCameraFPS
extends PTCamera

"""Built-in camera with controls"""

@export var mouse_sensitivity_x := 10.0
@export var mouse_sensitivity_y := 10.0
@export var move_speed := 3.5

# For plugin, relative root node in plugin instance
var freeze := true # stops input movement


func _process(delta : float) -> void:
	var plugin := (Engine.is_editor_hint() and not freeze)
	if not Engine.is_editor_hint() or plugin:
		# MOve to player ndoe
		if Input.is_key_pressed(KEY_W):
			self.position += ((-forward * Vector3(1,0,1)).normalized() * move_speed * delta)
		if Input.is_key_pressed(KEY_A):
			self.position += (-right * Vector3(1,0,1) * move_speed * delta)
		if Input.is_key_pressed(KEY_S):
			self.position += ((forward * Vector3(1,0,1)).normalized() * move_speed * delta)
		if Input.is_key_pressed(KEY_D):
			self.position += (right * Vector3(1,0,1) * move_speed * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not Engine.is_editor_hint():
		if event is InputEventKey:
			if (
					(event as InputEventKey).pressed and
					(event as InputEventKey).keycode == KEY_X and
					not event.is_echo()
				):
				PTRendererAuto.take_screenshot()

	if event is InputEventMouseMotion:
		if (event as InputEventMouseMotion).button_mask & 1:
			# modify accumulated mouse rotation
			var rot_x : float = ((event as InputEventMouseMotion).relative.x *
				mouse_sensitivity_x / 1000.)
			var rot_y : float = ((event as InputEventMouseMotion).relative.y *
				mouse_sensitivity_y / 1000.)

			# Old transform
			# NOTE: The new and old tranforms rotate in a different order and with negated
			#  values, still they both work correctly
			var _transform := (
					Transform3D()
					.rotated(Vector3.UP, rot_x)
					.rotated(right, rot_y))

			# Remember to translate to origin before rotating
			var prev_origin := transform.origin
			transform.origin = Vector3.ZERO

			self.transform = (
					transform
					.rotated(right, -rot_y)
					.rotated(Vector3.UP, -rot_x)
					.orthonormalized())
			transform.origin = prev_origin

