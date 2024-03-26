extends Node
# Can potentially be Refcounted

class_name PTAABB

var minimum : Vector3
var maximum : Vector3

func _init(minimum_ = Vector3(0,0,0), maximum_ = Vector3(1,1,1)):
	minimum = minimum_
	maximum = maximum_
	
	# Make minimum is smaller in all axies
	for i in range(3):
		if minimum[i] > maximum[i]:
			var temp = minimum[i]
			minimum[i] = maximum[i]
			maximum[i] = temp


func intersects(other : PTAABB):
	pass
	

func merge(other : PTAABB):
	for i in range(3):
		minimum[i] = min(other.minimum[i], minimum[i])
	for i in range(3):
		maximum[i] = max(other.maximum[i], maximum[i])
		

func vec3toarr(v):
	return [v.x, v.y, v.z]


func to_byte_array() -> PackedByteArray:
	var arr = vec3toarr(minimum) + [0] + vec3toarr(maximum) + [0]
	return PackedFloat32Array(arr).to_byte_array()





