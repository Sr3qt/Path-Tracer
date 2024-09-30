class_name _PTBVHTreeSetupHelper
extends GutTest

## Simple class to hold setup code for different PTBVHTree test scripts

var SceneA := preload("res://tests/test_scenes/test_scene_bvh_a.tscn")
var scene_a : PTScene
var bvh_a : PTBVHTree
var bvh_a2 : PTBVHTree
var tester_a : PTBVHTreeHelper


var SceneB := preload("res://tests/test_scenes/test_scene_bvh_b.tscn")
var scene_b : PTScene
var bvh_b : PTBVHTree
# var bvh_b2 : PTBVHTree
var tester_b : PTBVHTreeHelper


func before_all() -> void:
	bvh_a = create_test_bvh_a1()
	bvh_a2 = create_test_bvh_a2()

	tester_a = PTBVHTreeHelper.new(bvh_a)

	bvh_b = create_test_bvh_b()
	tester_b = PTBVHTreeHelper.new(bvh_b)


func after_all() -> void:
	scene_a.free()
	scene_b.free()


## Create a valid small tree
func create_test_bvh_a1() -> PTBVHTree:
	if not scene_a:
		scene_a = SceneA.instantiate()
		add_child(scene_a)

	var bvh := PTBVHTree.new(2)
	bvh.set_scene_as_owner(scene_a)

	var node_l := PTBVHTree.BVHNode.new(bvh.root_node, bvh)
	var node_r := PTBVHTree.BVHNode.new(bvh.root_node, bvh)
	var node_rl := PTBVHTree.BVHNode.new(node_r, bvh)
	var node_rr := PTBVHTree.BVHNode.new(node_r, bvh)

	node_l.is_leaf = true
	node_r.is_inner = true
	node_rl.is_leaf = true
	node_rr.is_leaf = true

	node_l.add_objects([scene_a.scene_objects.spheres[0],
			scene_a.scene_objects.triangles[0], scene_a.scene_objects.spheres[1]])
	node_rl.add_objects([scene_a.scene_objects.spheres[2],
			scene_a.scene_objects.spheres[3]])
	node_rr.add_object(scene_a.scene_objects.triangles[1])

	node_r.add_children([node_rl, node_rr])
	bvh.root_node.add_children([node_l, node_r])

	# Indices
	bvh.leaf_nodes = [node_l, node_rl, node_rr]
	bvh.bvh_list = [bvh.root_node, node_l, node_r, node_rl, node_rr]
	var i := 0
	for node in bvh.bvh_list:
		bvh._node_to_index[node] = i
		if node.is_leaf:
			bvh._node_to_object_id_index[node] = bvh.object_ids.size()
			for object in node.object_list:
				bvh.object_to_leaf[object] = node
				bvh.object_ids.append(object.get_object_id())

		i += 1

	bvh.inner_count = 2
	bvh.leaf_count = 3
	bvh.object_count = 6
	bvh.mesh_object_count = 0

	return bvh


## Create a sligthly smaller valid tree
func create_test_bvh_a2() -> PTBVHTree:
	if not scene_a:
		scene_a = SceneA.instantiate()
		add_child(scene_a)

	var bvh := PTBVHTree.new(2)
	bvh.set_scene_as_owner(scene_a)

	var node_l := PTBVHTree.BVHNode.new(bvh.root_node, bvh)
	var node_r := PTBVHTree.BVHNode.new(bvh.root_node, bvh)

	node_l.is_leaf = true
	node_r.is_leaf = true

	node_l.add_objects([scene_a.scene_objects.spheres[0],
			scene_a.scene_objects.triangles[0], scene_a.scene_objects.spheres[1]])
	node_r.add_objects([scene_a.scene_objects.spheres[2],
			scene_a.scene_objects.spheres[3],scene_a.scene_objects.triangles[1]])

	bvh.root_node.add_children([node_l, node_r])

	# Indices
	bvh.leaf_nodes = [node_l, node_r]
	bvh.bvh_list = [bvh.root_node, node_l, node_r]
	var i := 0
	for node in bvh.bvh_list:
		bvh._node_to_index[node] = i
		if node.is_leaf:
			bvh.set_object_id_index(node, bvh.object_ids.size())
			for object in node.object_list:
				bvh.object_to_leaf[object] = node
				bvh.object_ids.append(object.get_object_id())

		i += 1

	bvh.inner_count = 1
	bvh.leaf_count = 2
	bvh.object_count = 6
	bvh.mesh_object_count = 0

	return bvh


func create_test_bvh_b() -> PTBVHTree:
	if not scene_b:
		scene_b = SceneB.instantiate()
		add_child(scene_b)

	var mesh1 := scene_b.scene_objects.meshes[0]
	var mesh2 := scene_b.scene_objects.meshes[1]

	var scene_bvh := PTBVHTree.new(4, false)
	mesh1.bvh = PTBVHTree.new(4, false)
	mesh2.bvh = PTBVHTree.new(4, false)

	scene_bvh.set_scene_as_owner(scene_b)
	mesh1.bvh.set_mesh_as_owner(mesh1)
	mesh2.bvh.set_mesh_as_owner(mesh2)
	mesh1.bvh.parent_tree = scene_bvh
	mesh2.bvh.parent_tree = scene_bvh

	var root1 := mesh1.bvh.root_node
	var root2 := mesh2.bvh.root_node

	root1.parent = scene_bvh.root_node
	root2.parent = scene_bvh.root_node

	var node_l := PTBVHTree.BVHNode.new(scene_bvh.root_node, scene_bvh)
	var node_m := PTBVHTree.BVHNode.new(scene_bvh.root_node, scene_bvh)
	var node_r := PTBVHTree.BVHNode.new(scene_bvh.root_node, scene_bvh)

	# var node_lm := PTBVHTree.BVHNode.new(root1, mesh1.bvh)

	var node_rl := PTBVHTree.BVHNode.new(root2, mesh2.bvh)
	var node_rm := PTBVHTree.BVHNode.new(root2, mesh2.bvh)
	var node_rr := PTBVHTree.BVHNode.new(root2, mesh2.bvh)

	node_l.is_inner = true
	node_r.is_inner = true
	node_l.is_mesh_socket = true
	node_r.is_mesh_socket = true

	root1.is_leaf = true
	root2.is_inner = true
	node_m.is_leaf = true
	node_rl.is_leaf = true
	node_rm.is_leaf = true
	node_rr.is_leaf = true

	# Add to leaf nodes
	node_m.add_objects([scene_b.scene_objects.spheres[0],
			scene_b.scene_objects.triangles[0]])

	# TODO 1: Should object arrays be of type Array[PTObject]?
	var temp_array : Array[PTObject] = []
	temp_array.assign(mesh1.objects.triangles)
	root1.add_object(mesh1.objects.spheres[0])
	root1.add_objects(temp_array)

	var temp_spheres_1 : Array[PTObject] = []
	var temp_spheres_2 : Array[PTObject] = []
	var temp_spheres_3 : Array[PTObject] = []

	temp_spheres_1.assign(mesh2.objects.spheres.slice(0, 3))
	temp_spheres_2.assign(mesh2.objects.spheres.slice(3, 6))
	temp_spheres_3.assign(mesh2.objects.spheres.slice(6, 9))

	node_rl.add_objects(temp_spheres_1)
	node_rm.add_objects(temp_spheres_2)
	node_rr.add_objects(temp_spheres_3)

	# Add to inner nodes
	root2.add_children([node_rl, node_rm, node_rr])
	node_l.add_child(root1)
	node_r.add_child(root2)
	scene_bvh.root_node.add_children([node_l, node_m, node_r])

	# Scene Indices
	scene_bvh.leaf_nodes = [root1, node_m, node_rl, node_rm, node_rr]
	scene_bvh.bvh_list = [
		scene_bvh.root_node,
		node_l,
		node_m,
		node_r,
		root1,
		root2,
		node_rl,
		node_rm,
		node_rr,
	]
	scene_bvh._node_to_index = {
		scene_bvh.root_node : 0,
		node_l : 1,
		node_m : 2,
		node_r : 3,
		root1 : 4,
		root2 : 5,
		node_rl : 6,
		node_rm : 7,
		node_rr : 8,
	}
	scene_bvh._mesh_to_mesh_socket = {mesh1 : node_l, mesh2 : node_r}

	for node in scene_bvh.leaf_nodes:
		scene_bvh.set_object_id_index(node, scene_bvh.object_ids.size())
		for object in node.object_list:
			scene_bvh.object_to_leaf[object] = node
			scene_bvh.object_ids.append(object.get_object_id())

	scene_bvh.inner_count = 3
	scene_bvh.leaf_count = 5
	scene_bvh.object_count = 2
	scene_bvh.mesh_object_count = 14

	# Mesh1 indices
	mesh1.bvh.leaf_nodes = [root1]
	mesh1.bvh.bvh_list = [root1]
	mesh1.bvh._node_to_index = {root1 : 0}
	for object in root1.object_list:
		mesh1.bvh.object_to_leaf[object] = root1
	mesh1.bvh.inner_count = 0
	mesh1.bvh.leaf_count = 1
	mesh1.bvh.object_count = 5
	mesh1.bvh.mesh_object_count = 0

	# Mesh2 Indices
	mesh2.bvh.leaf_nodes = [node_rl, node_rm, node_rr]
	mesh2.bvh.bvh_list = [root2, node_rl, node_rm, node_rr]
	mesh2.bvh._node_to_index = {
		root2 : 0,
		node_rl : 1,
		node_rm : 2,
		node_rr : 3,
	}
	for node in mesh2.bvh.leaf_nodes:
		for object in node.object_list:
			scene_bvh.object_to_leaf[object] = node
	mesh2.bvh.inner_count = 1
	mesh2.bvh.leaf_count = 3
	mesh2.bvh.object_count = 9
	mesh2.bvh.mesh_object_count = 0

	return scene_bvh


# TODO 2: Create one more scene that has an instanced ptmeshinstance
func create_test_bvh_c() -> PTBVHTree:
	pass
	return
