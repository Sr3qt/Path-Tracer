extends Node

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
	pass





