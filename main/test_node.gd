extends Node


enum {ENTER_SPHERE_1, EXIT_SPHERE_1, ENTER_SPHERE_2, EXIT_SPHERE_2}

var scenario = [ENTER_SPHERE_1, ENTER_SPHERE_2, EXIT_SPHERE_1, EXIT_SPHERE_2]

var sphere_1 = [0, 1]
var sphere_2 = [1, 1]


var inside_of = []
var inside_of_count = 0

var current_ior = 1.0

func get_IOR(sphere):
	var lowest_depth = INF;
	var IOR_out = 1.0;
	for i in range(inside_of_count):
		var index = inside_of[i];
		if (index.z < lowest_depth && !(sphere[0] == index.x && sphere[1] == index.y)): 
			lowest_depth = index.z;
			IOR_out = index.w;
		
	return IOR_out;

func remove_object(sphere):
	var shift = 0
	for i in range(inside_of_count - 1):
		var index = inside_of[i];
		if (sphere[0] == index.x && sphere[1] == index.y): 
			shift = 1
		
		inside_of[i] = inside_of[i + shift]
	
	inside_of_count -= 1


func _init():
	for i in scenario:
		var sphere
		if i == ENTER_SPHERE_1 or i == EXIT_SPHERE_1:
			sphere = sphere_1
		else:
			sphere = sphere_2
	
		var is_inside = i == EXIT_SPHERE_1 or i == EXIT_SPHERE_2
		var eta_in = current_ior
		
		var eta_out = get_IOR(sphere) if is_inside else 1.6
		
		var eta = eta_in / eta_out
		
		if is_zero_approx(eta - 1.0):
			if is_inside:
				remove_object(sphere)
			else:
				inside_of.insert(inside_of_count, Vector4(sphere[0], sphere[1], 0, 1.6))
				inside_of_count += 1
			print("went stragiht " + str(i))
			continue

		current_ior = eta_out
		
		if is_inside:
			remove_object(sphere)
		else:
			inside_of.insert(inside_of_count, Vector4(sphere[0], sphere[1], 0, 1.6))
			inside_of_count += 1
		print("refracted " + str(i))
